-- Dormant recurring-media origin. No URL, provider request, policy or job.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$
BEGIN
  IF current_user<>'postgres' THEN
    RAISE EXCEPTION 'mobile_reevaluation_requires_postgres_owner' USING ERRCODE='42501';
  END IF;
  IF to_regprocedure('private.mobile_reevaluation_photo_context(uuid,uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'mobile_reevaluation_requires_consent_authority' USING ERRCODE='42P01';
  END IF;
END $preflight$;

ALTER TABLE public.media_assets ADD COLUMN reevaluation_origin_version smallint;
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_reevaluation_origin_shape CHECK(
  reevaluation_origin_version IS NULL OR (reevaluation_origin_version=1
    AND kind='body_checkin_photo' AND signup_origin IS FALSE AND signup_disposition_version IS NULL));
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_reevaluation_identity_unique
  UNIQUE(id,user_id,reevaluation_origin_version);

CREATE TABLE private.mobile_reevaluation_photo_assets (
  asset_id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  signup_generation uuid NOT NULL,
  cycle_id uuid NOT NULL,
  consent_acceptance_id uuid NOT NULL,
  origin_version smallint NOT NULL DEFAULT 1 CHECK(origin_version=1),
  pose text NOT NULL CHECK(pose IN('front','side','back')),
  request_key uuid NOT NULL,
  request_revision bigint NOT NULL CHECK(request_revision>0),
  created_at timestamptz NOT NULL CHECK(isfinite(created_at)),
  invalidated_at timestamptz,
  invalidated_reason text,
  UNIQUE(asset_id,user_id,origin_version),
  UNIQUE(user_id,request_key),
  FOREIGN KEY(user_id,signup_generation,cycle_id,consent_acceptance_id)
    REFERENCES private.mobile_reevaluation_photo_consents(user_id,signup_generation,cycle_id,acceptance_id)
    ON DELETE NO ACTION,
  -- The allocator inserts the ledger before its newly generated asset. The
  -- reverse FK below is immediate: marker1 can never exist without membership.
  FOREIGN KEY(asset_id,user_id,origin_version)
    REFERENCES public.media_assets(id,user_id,reevaluation_origin_version)
    DEFERRABLE INITIALLY DEFERRED,
  CHECK((invalidated_at IS NULL)=(invalidated_reason IS NULL)),
  CHECK(invalidated_at IS NULL OR (isfinite(invalidated_at) AND invalidated_at>=created_at)),
  CHECK(invalidated_reason IS NULL OR invalidated_reason IN(
    'replaced','discarded','expired','consent_changed','cycle_changed','completed'))
);
ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_reevaluation_source_fkey
  FOREIGN KEY(id,user_id,reevaluation_origin_version)
  REFERENCES private.mobile_reevaluation_photo_assets(asset_id,user_id,origin_version);
ALTER TABLE private.mobile_reevaluation_photo_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_reevaluation_photo_assets FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX mobile_reevaluation_photo_assets_cycle
  ON private.mobile_reevaluation_photo_assets(user_id,cycle_id,consent_acceptance_id);

CREATE FUNCTION private.preserve_mobile_reevaluation_photo_asset() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF (to_jsonb(NEW)-ARRAY['invalidated_at','invalidated_reason'])
      IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['invalidated_at','invalidated_reason'])
    OR (OLD.invalidated_at IS NOT NULL AND NEW IS DISTINCT FROM OLD) THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_asset_identity_immutable' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER preserve_mobile_reevaluation_photo_asset BEFORE UPDATE
  ON private.mobile_reevaluation_photo_assets FOR EACH ROW
  EXECUTE FUNCTION private.preserve_mobile_reevaluation_photo_asset();

CREATE FUNCTION private.preserve_mobile_reevaluation_media_origin() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF NEW.reevaluation_origin_version IS DISTINCT FROM OLD.reevaluation_origin_version
    OR (OLD.reevaluation_origin_version IS NOT NULL AND
      ROW(NEW.id,NEW.user_id,NEW.kind,NEW.bucket_id,NEW.object_path,NEW.mime_type,
        NEW.declared_size_bytes,NEW.context_text,NEW.source_request_hash,NEW.created_at,
        NEW.signup_origin,NEW.signup_disposition_version)
      IS DISTINCT FROM ROW(OLD.id,OLD.user_id,OLD.kind,OLD.bucket_id,OLD.object_path,OLD.mime_type,
        OLD.declared_size_bytes,OLD.context_text,OLD.source_request_hash,OLD.created_at,
        OLD.signup_origin,OLD.signup_disposition_version)) THEN
    RAISE EXCEPTION 'mobile_reevaluation_media_origin_immutable' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER preserve_mobile_reevaluation_media_origin BEFORE UPDATE ON public.media_assets
  FOR EACH ROW EXECUTE FUNCTION private.preserve_mobile_reevaluation_media_origin();

CREATE FUNCTION private.mobile_reevaluation_photo_asset_wire(
  p_context jsonb,p_asset_id uuid) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
  SELECT jsonb_build_object('version',1,'cycle_revision',p_context->'cycle_revision',
    'asset',jsonb_build_object('id',m.id,'user_id',m.user_id,'signup_generation',l.signup_generation,
      'cycle_id',l.cycle_id,'consent_acceptance_id',l.consent_acceptance_id,
      'origin','reevaluation_cycle_v1','pose',l.pose,'bucket_id',m.bucket_id,'object_path',m.object_path,
      'mime_type',m.mime_type,'size_bytes',m.declared_size_bytes,'status',m.status,
      'created_at',to_char(m.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'retention_until',to_char(m.retention_until AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))
    FROM private.mobile_reevaluation_photo_assets l
    JOIN public.media_assets m ON m.id=l.asset_id AND m.user_id=l.user_id AND m.reevaluation_origin_version=1
    WHERE l.asset_id=p_asset_id AND l.invalidated_at IS NULL
      AND l.signup_generation=(p_context->>'signup_generation')::uuid
      AND l.consent_acceptance_id=(p_context#>>'{current_acceptance,acceptance_id}')::uuid
      AND m.status<>'deleted'
$$;

CREATE FUNCTION private.create_mobile_reevaluation_photo_asset_at(
  p_user_id uuid,p_cycle_id uuid,p_expected_revision bigint,p_acceptance_id uuid,
  p_pose text,p_mime_type text,p_size_bytes bigint,p_request_key uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; consent_wire jsonb; previous private.mobile_reevaluation_photo_assets%ROWTYPE;
  old_asset public.media_assets%ROWTYPE; observed_at timestamptz; expires_at timestamptz;
  asset_id uuid; generation_id uuid; extension text; result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_expected_revision IS NULL OR p_expected_revision<=0 OR p_acceptance_id IS NULL
    OR p_request_key IS NULL OR p_pose IS NULL OR p_pose NOT IN('front','side','back')
    OR p_mime_type IS NULL OR p_mime_type NOT IN('image/jpeg','image/png','image/webp','image/heic','image/heif')
    OR p_size_bytes IS NULL OR p_size_bytes NOT BETWEEN 1 AND 15728640 THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_photo_asset' USING ERRCODE='22023';
  END IF;
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  consent_wire:=private.mobile_reevaluation_photo_consent_wire(context);
  IF consent_wire->>'availability' IS DISTINCT FROM 'available'
    OR context#>>'{current_acceptance,acceptance_id}' IS DISTINCT FROM p_acceptance_id::text THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001';
  END IF;
  generation_id:=(context->>'signup_generation')::uuid;
  SELECT l.* INTO previous FROM private.mobile_reevaluation_photo_assets l
    WHERE l.user_id=p_user_id AND l.request_key=p_request_key;
  IF FOUND THEN
    SELECT m.* INTO old_asset FROM public.media_assets m WHERE m.id=previous.asset_id AND m.user_id=p_user_id;
    IF previous.signup_generation IS DISTINCT FROM generation_id OR previous.cycle_id IS DISTINCT FROM p_cycle_id
      OR previous.consent_acceptance_id IS DISTINCT FROM p_acceptance_id OR previous.pose IS DISTINCT FROM p_pose
      OR previous.request_revision IS DISTINCT FROM p_expected_revision OR previous.invalidated_at IS NOT NULL
      OR old_asset.reevaluation_origin_version IS DISTINCT FROM 1
      OR old_asset.mime_type IS DISTINCT FROM p_mime_type OR old_asset.declared_size_bytes IS DISTINCT FROM p_size_bytes
      OR old_asset.status='deleted' THEN
      RAISE EXCEPTION 'mobile_reevaluation_photo_asset_replay_changed' USING ERRCODE='40001';
    END IF;
    RETURN private.mobile_reevaluation_photo_asset_wire(context,previous.asset_id);
  END IF;
  IF context->>'cycle_revision' IS DISTINCT FROM p_expected_revision::text THEN
    RAISE EXCEPTION 'mobile_reevaluation_revision_changed' USING ERRCODE='40001';
  END IF;
  observed_at:=(context->>'observed_at')::timestamptz;
  expires_at:=observed_at+make_interval(secs=>(context#>>'{document,idle_timeout_seconds}')::integer);
  extension:=CASE p_mime_type WHEN 'image/jpeg' THEN 'jpg' WHEN 'image/png' THEN 'png'
    WHEN 'image/webp' THEN 'webp' WHEN 'image/heic' THEN 'heic' ELSE 'heif' END;
  asset_id:=gen_random_uuid();
  INSERT INTO private.mobile_reevaluation_photo_assets(asset_id,user_id,signup_generation,cycle_id,
    consent_acceptance_id,pose,request_key,request_revision,created_at)
    VALUES(asset_id,p_user_id,generation_id,p_cycle_id,p_acceptance_id,p_pose,p_request_key,p_expected_revision,observed_at);
  INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,
    status,context_text,source_request_hash,retention_until,created_at,updated_at,signup_origin,reevaluation_origin_version)
    VALUES(asset_id,p_user_id,'body_checkin_photo','body-checkin-photos',
      p_user_id::text||'/'||asset_id::text||'.'||extension,p_mime_type,p_size_bytes,
      'pending_upload',CASE p_pose WHEN 'front' THEN 'Foto de frente.' WHEN 'side' THEN 'Foto de lado.' ELSE 'Foto de costas.' END,
      encode(extensions.digest('reevaluation_photo_v1:'||p_request_key::text,'sha256'),'hex'),
      expires_at,observed_at,observed_at,false,1);
  UPDATE private.mobile_reevaluation_photo_consents SET last_activity_at=observed_at
    WHERE acceptance_id=p_acceptance_id AND user_id=p_user_id;
  -- Owner is already locked. Lock all current assets in deterministic order;
  -- invalidated or deleted sources never have their retention renewed.
  PERFORM m.id FROM public.media_assets m JOIN private.mobile_reevaluation_photo_assets l ON l.asset_id=m.id
    WHERE l.user_id=p_user_id AND l.cycle_id=p_cycle_id AND l.consent_acceptance_id=p_acceptance_id
      AND l.invalidated_at IS NULL AND m.status<>'deleted' ORDER BY m.id FOR UPDATE OF m;
  UPDATE public.media_assets m SET retention_until=expires_at
    FROM private.mobile_reevaluation_photo_assets l
    WHERE l.asset_id=m.id AND l.user_id=p_user_id AND l.cycle_id=p_cycle_id
      AND l.consent_acceptance_id=p_acceptance_id AND l.invalidated_at IS NULL AND m.status<>'deleted';
  RETURN private.mobile_reevaluation_photo_asset_wire(context,asset_id);
EXCEPTION WHEN unique_violation THEN
  -- Never adopt a generic/signup asset after the global source hash conflict.
  RAISE EXCEPTION 'mobile_reevaluation_photo_asset_conflict' USING ERRCODE='40001';
END $$;

CREATE FUNCTION public.create_mobile_reevaluation_photo_asset(
  p_user_id uuid,p_cycle_id uuid,p_expected_revision bigint,p_acceptance_id uuid,
  p_pose text,p_mime_type text,p_size_bytes bigint,p_request_key uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.create_mobile_reevaluation_photo_asset_at(p_user_id,p_cycle_id,p_expected_revision,
    p_acceptance_id,p_pose,p_mime_type,p_size_bytes,p_request_key,NULL::timestamptz)
$$;

CREATE FUNCTION public.get_mobile_reevaluation_photo_asset(p_user_id uuid,p_cycle_id uuid,p_asset_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE context jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_asset_id IS NULL THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_photo_asset' USING ERRCODE='22023'; END IF;
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,NULL::timestamptz);
  IF private.mobile_reevaluation_photo_consent_wire(context)->>'availability' IS DISTINCT FROM 'available' THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001';
  END IF;
  RETURN private.mobile_reevaluation_photo_asset_wire(context,p_asset_id);
END $$;

REVOKE ALL ON FUNCTION private.preserve_mobile_reevaluation_photo_asset(),
  private.preserve_mobile_reevaluation_media_origin(),private.mobile_reevaluation_photo_asset_wire(jsonb,uuid),
  private.create_mobile_reevaluation_photo_asset_at(uuid,uuid,bigint,uuid,text,text,bigint,uuid,timestamptz),
  public.create_mobile_reevaluation_photo_asset(uuid,uuid,bigint,uuid,text,text,bigint,uuid),
  public.get_mobile_reevaluation_photo_asset(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_mobile_reevaluation_photo_asset(uuid,uuid,bigint,uuid,text,text,bigint,uuid),
  public.get_mobile_reevaluation_photo_asset(uuid,uuid,uuid) TO service_role;

-- Generic processing guards are appended below without changing their old
-- status/retry semantics. Dedicated recurring processing will be separate.
CREATE OR REPLACE FUNCTION public.claim_media_asset_processing(
  p_asset_id uuid,
  p_user_id uuid,
  p_request_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_asset public.media_assets%ROWTYPE;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_request_id !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid media processing request id' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_asset
  FROM public.media_assets
  WHERE id = p_asset_id
    AND user_id = p_user_id
    AND reevaluation_origin_version IS NULL
  FOR UPDATE;

  IF NOT FOUND OR v_asset.status IN ('pending_upload', 'processed', 'deleted') THEN
    RETURN NULL;
  END IF;

  IF v_asset.status = 'processing'
    AND v_asset.processing_request_id IS DISTINCT FROM p_request_id THEN
    RETURN NULL;
  END IF;

  IF v_asset.status = 'failed'
    AND v_asset.failure_stage <> 'processing' THEN
    RETURN NULL;
  END IF;

  IF v_asset.status IN ('uploaded', 'failed') THEN
    UPDATE public.media_assets
    SET status = 'processing',
        processing_request_id = p_request_id,
        processing_result = NULL,
        processed_at = NULL
    WHERE id = v_asset.id
    RETURNING * INTO v_asset;
  END IF;

  RETURN jsonb_build_object(
    'id', v_asset.id,
    'user_id', v_asset.user_id,
    'kind', v_asset.kind,
    'bucket_id', v_asset.bucket_id,
    'object_path', v_asset.object_path,
    'mime_type', v_asset.mime_type,
    'context_text', v_asset.context_text,
    'status', v_asset.status,
    'processing_request_id', v_asset.processing_request_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_media_asset_processing(
  p_asset_id uuid,
  p_user_id uuid,
  p_request_id text,
  p_result jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.media_assets
  SET status = 'processed',
      processing_result = p_result,
      processed_at = clock_timestamp()
  WHERE id = p_asset_id
    AND user_id = p_user_id
    AND reevaluation_origin_version IS NULL
    AND status = 'processing'
    AND processing_request_id = p_request_id;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_media_asset_processing(
  p_asset_id uuid,
  p_user_id uuid,
  p_request_id text,
  p_failure_code text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.media_assets
  SET status = 'failed',
      failure_stage = 'processing',
      failure_code = left(p_failure_code, 100)
  WHERE id = p_asset_id
    AND user_id = p_user_id
    AND reevaluation_origin_version IS NULL
    AND status = 'processing'
    AND processing_request_id = p_request_id;

  RETURN FOUND;
END;
$$;
COMMIT;
