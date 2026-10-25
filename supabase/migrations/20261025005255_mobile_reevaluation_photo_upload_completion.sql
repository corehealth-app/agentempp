-- Dormant recurring upload completion. No policy, endpoint, provider or job.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'mobile_reevaluation_requires_postgres_owner' USING ERRCODE='42501'; END IF;
  IF to_regclass('private.mobile_reevaluation_photo_upload_tickets') IS NULL THEN
    RAISE EXCEPTION 'mobile_reevaluation_requires_upload_tickets' USING ERRCODE='42P01'; END IF;
  IF EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_assets) THEN
    RAISE EXCEPTION 'mobile_reevaluation_source_order_requires_empty_ledger' USING ERRCODE='55000'; END IF;
END $preflight$;
ALTER TABLE private.mobile_reevaluation_photo_assets ADD CONSTRAINT mobile_reevaluation_photo_asset_pose_tuple
  UNIQUE(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id,pose);
CREATE TABLE private.mobile_reevaluation_photo_sources(
  user_id uuid NOT NULL,signup_generation uuid NOT NULL,cycle_id uuid NOT NULL,
  consent_acceptance_id uuid NOT NULL,pose text NOT NULL CHECK(pose IN('front','side','back')),
  requested_asset_id uuid NOT NULL,selected_asset_id uuid,
  source_revision bigint NOT NULL DEFAULT 1 CHECK(source_revision>0),selected_at timestamptz,
  PRIMARY KEY(user_id,signup_generation,cycle_id,consent_acceptance_id,pose),
  FOREIGN KEY(requested_asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id,pose)
    REFERENCES private.mobile_reevaluation_photo_assets(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id,pose),
  FOREIGN KEY(selected_asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id,pose)
    REFERENCES private.mobile_reevaluation_photo_assets(asset_id,user_id,signup_generation,cycle_id,consent_acceptance_id,pose),
  CHECK((selected_asset_id IS NULL)=(selected_at IS NULL)),
  CHECK(selected_at IS NULL OR isfinite(selected_at))
);
ALTER TABLE private.mobile_reevaluation_photo_sources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.mobile_reevaluation_photo_sources FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.preserve_mobile_reevaluation_photo_source() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF ROW(NEW.user_id,NEW.signup_generation,NEW.cycle_id,NEW.consent_acceptance_id,NEW.pose)
    IS DISTINCT FROM ROW(OLD.user_id,OLD.signup_generation,OLD.cycle_id,OLD.consent_acceptance_id,OLD.pose)
    OR NEW.source_revision IS DISTINCT FROM OLD.source_revision+1 THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_source_identity_immutable' USING ERRCODE='55000'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER preserve_mobile_reevaluation_photo_source BEFORE UPDATE ON private.mobile_reevaluation_photo_sources
  FOR EACH ROW EXECUTE FUNCTION private.preserve_mobile_reevaluation_photo_source();
CREATE FUNCTION private.request_mobile_reevaluation_photo_source() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  PERFORM private.assert_trusted_backend();
  -- The existing allocator already holds the owner lock. This trigger runs
  -- only for a new ledger row, never for an idempotent request-key replay.
  INSERT INTO private.mobile_reevaluation_photo_sources(user_id,signup_generation,cycle_id,
    consent_acceptance_id,pose,requested_asset_id)
    VALUES(NEW.user_id,NEW.signup_generation,NEW.cycle_id,NEW.consent_acceptance_id,NEW.pose,NEW.asset_id)
    ON CONFLICT(user_id,signup_generation,cycle_id,consent_acceptance_id,pose)
    DO UPDATE SET requested_asset_id=EXCLUDED.requested_asset_id,
      source_revision=private.mobile_reevaluation_photo_sources.source_revision+1;
  RETURN NEW;
END $$;
CREATE TRIGGER request_mobile_reevaluation_photo_source AFTER INSERT ON private.mobile_reevaluation_photo_assets
  FOR EACH ROW EXECUTE FUNCTION private.request_mobile_reevaluation_photo_source();

CREATE OR REPLACE FUNCTION private.mobile_reevaluation_photo_asset_wire(
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
      AND l.user_id=(p_context#>>'{current_acceptance,user_id}')::uuid
      AND l.cycle_id=(p_context#>>'{current_acceptance,cycle_id}')::uuid
      AND EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_sources s
        WHERE s.user_id=l.user_id AND s.signup_generation=l.signup_generation
          AND s.cycle_id=l.cycle_id AND s.consent_acceptance_id=l.consent_acceptance_id
          AND s.pose=l.pose AND l.asset_id IN(s.requested_asset_id,s.selected_asset_id))
$$;


CREATE FUNCTION private.mobile_reevaluation_photo_completion_wire(p_context jsonb,p_asset_id uuid) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
  SELECT private.mobile_reevaluation_photo_asset_wire(p_context,p_asset_id)||
    jsonb_build_object('source_revision',s.source_revision::text,'selection_state',
      CASE WHEN s.selected_asset_id=p_asset_id THEN 'selected' ELSE 'pending' END)
  FROM private.mobile_reevaluation_photo_sources s
  WHERE s.user_id=(p_context#>>'{current_acceptance,user_id}')::uuid
    AND s.signup_generation=(p_context->>'signup_generation')::uuid
    AND s.cycle_id=(p_context#>>'{current_acceptance,cycle_id}')::uuid
    AND s.consent_acceptance_id=(p_context#>>'{current_acceptance,acceptance_id}')::uuid
    AND s.requested_asset_id=p_asset_id
$$;
CREATE FUNCTION private.get_mobile_reevaluation_photo_upload_completion_at(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_asset_id IS NULL THEN RAISE EXCEPTION 'invalid_mobile_reevaluation_photo_completion' USING ERRCODE='22023'; END IF;
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  IF private.mobile_reevaluation_photo_consent_wire(context)->>'availability' IS DISTINCT FROM 'available' THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001'; END IF;
  result:=private.mobile_reevaluation_photo_completion_wire(context,p_asset_id);
  IF result IS NULL OR result->'asset' IS NULL OR result#>>'{asset,status}' NOT IN('pending_upload','uploaded','processing','processed') THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_source_changed' USING ERRCODE='40001'; END IF;
  RETURN result;
END $$;
CREATE FUNCTION private.complete_mobile_reevaluation_photo_upload_at(
  p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,p_expected_source_revision bigint,
  p_actual_size_bytes bigint,p_content_type text,p_etag text,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE context jsonb; result jsonb; source private.mobile_reevaluation_photo_sources%ROWTYPE;
  asset public.media_assets%ROWTYPE; at_time timestamptz; expiry timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_expected_source_revision IS NULL OR p_expected_source_revision<=0
    OR p_actual_size_bytes IS NULL OR p_actual_size_bytes NOT BETWEEN 1 AND 15728640
    OR p_content_type IS NULL OR p_content_type NOT IN('image/jpeg','image/png','image/webp','image/heic','image/heif')
    OR (p_etag IS NOT NULL AND (length(p_etag) NOT BETWEEN 1 AND 256 OR p_etag ~ '[[:cntrl:]]')) THEN
    RAISE EXCEPTION 'invalid_mobile_reevaluation_photo_completion' USING ERRCODE='22023'; END IF;
  -- The context locks owner, legal and policy authority. Network metadata has
  -- already been fetched; this transaction must re-authorize independently.
  result:=private.get_mobile_reevaluation_photo_upload_completion_at(p_user_id,p_cycle_id,p_asset_id,p_observed_at);
  SELECT s.* INTO source FROM private.mobile_reevaluation_photo_sources s
    WHERE s.user_id=p_user_id AND s.cycle_id=p_cycle_id AND s.requested_asset_id=p_asset_id FOR UPDATE;
  IF source.source_revision IS DISTINCT FROM p_expected_source_revision THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_source_changed' USING ERRCODE='40001'; END IF;
  -- Owner first, source second, all live media in deterministic order. No
  -- generic/workout/admission lock is acquired after this point.
  PERFORM m.id FROM public.media_assets m JOIN private.mobile_reevaluation_photo_assets l ON l.asset_id=m.id
    WHERE l.user_id=p_user_id AND l.cycle_id=p_cycle_id AND l.consent_acceptance_id=source.consent_acceptance_id
      AND l.invalidated_at IS NULL AND m.status<>'deleted' ORDER BY m.id FOR UPDATE OF m;
  -- Waiting for media must not allow an expired session to select a source.
  result:=private.get_mobile_reevaluation_photo_upload_completion_at(p_user_id,p_cycle_id,p_asset_id,p_observed_at);
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  IF private.mobile_reevaluation_photo_consent_wire(context)->>'availability' IS DISTINCT FROM 'available' THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_consent_changed' USING ERRCODE='40001'; END IF;
  at_time:=(context->>'observed_at')::timestamptz;
  SELECT m.* INTO asset FROM public.media_assets m WHERE m.id=p_asset_id AND m.user_id=p_user_id;
  IF asset.declared_size_bytes IS DISTINCT FROM p_actual_size_bytes OR asset.mime_type IS DISTINCT FROM p_content_type THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_metadata_mismatch' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_upload_tickets t
    WHERE t.asset_id=p_asset_id AND t.user_id=p_user_id AND t.signup_generation=source.signup_generation
      AND t.cycle_id=p_cycle_id AND t.consent_acceptance_id=source.consent_acceptance_id AND t.registered_at IS NOT NULL) THEN
    RAISE EXCEPTION 'mobile_reevaluation_photo_ticket_missing' USING ERRCODE='40001'; END IF;
  IF source.selected_asset_id=p_asset_id THEN
    IF asset.status NOT IN('uploaded','processing','processed') OR asset.actual_size_bytes IS DISTINCT FROM p_actual_size_bytes
      OR asset.etag IS DISTINCT FROM p_etag THEN
      RAISE EXCEPTION 'mobile_reevaluation_photo_completion_changed' USING ERRCODE='40001'; END IF;
    RETURN result;
  END IF;
  IF asset.status<>'pending_upload' THEN RAISE EXCEPTION 'mobile_reevaluation_photo_source_changed' USING ERRCODE='40001'; END IF;
  UPDATE public.media_assets SET status='uploaded',actual_size_bytes=p_actual_size_bytes,
    uploaded_at=at_time,etag=p_etag WHERE id=p_asset_id;
  IF source.selected_asset_id IS NOT NULL THEN
    UPDATE private.mobile_reevaluation_photo_assets SET invalidated_at=at_time,invalidated_reason='replaced'
      WHERE asset_id=source.selected_asset_id AND invalidated_at IS NULL;
  END IF;
  UPDATE private.mobile_reevaluation_photo_sources SET selected_asset_id=p_asset_id,
    selected_at=at_time,source_revision=source_revision+1
    WHERE user_id=source.user_id AND signup_generation=source.signup_generation AND cycle_id=source.cycle_id
      AND consent_acceptance_id=source.consent_acceptance_id AND pose=source.pose;
  UPDATE private.mobile_reevaluation_cycles SET revision=revision+1,status='collecting' WHERE cycle_id=p_cycle_id;
  UPDATE private.mobile_reevaluation_photo_consents SET last_activity_at=at_time WHERE acceptance_id=source.consent_acceptance_id;
  expiry:=at_time+make_interval(secs=>(context#>>'{document,idle_timeout_seconds}')::integer);
  UPDATE public.media_assets m SET retention_until=expiry FROM private.mobile_reevaluation_photo_assets l
    WHERE l.asset_id=m.id AND l.user_id=p_user_id AND l.cycle_id=p_cycle_id
      AND l.consent_acceptance_id=source.consent_acceptance_id AND l.invalidated_at IS NULL AND m.status<>'deleted';
  context:=private.mobile_reevaluation_photo_context(p_user_id,p_cycle_id,p_observed_at);
  RETURN private.mobile_reevaluation_photo_completion_wire(context,p_asset_id);
END $$;
CREATE FUNCTION public.get_mobile_reevaluation_photo_upload_completion(p_user_id uuid,p_cycle_id uuid,p_asset_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.get_mobile_reevaluation_photo_upload_completion_at(p_user_id,p_cycle_id,p_asset_id,NULL::timestamptz)
$$;
CREATE FUNCTION public.complete_mobile_reevaluation_photo_upload(p_user_id uuid,p_cycle_id uuid,p_asset_id uuid,
  p_expected_source_revision bigint,p_actual_size_bytes bigint,p_content_type text,p_etag text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
  SELECT private.complete_mobile_reevaluation_photo_upload_at(p_user_id,p_cycle_id,p_asset_id,
    p_expected_source_revision,p_actual_size_bytes,p_content_type,p_etag,NULL::timestamptz)
$$;
REVOKE ALL ON FUNCTION private.preserve_mobile_reevaluation_photo_source(),private.request_mobile_reevaluation_photo_source(),
  private.mobile_reevaluation_photo_completion_wire(jsonb,uuid),
  private.get_mobile_reevaluation_photo_upload_completion_at(uuid,uuid,uuid,timestamptz),
  private.complete_mobile_reevaluation_photo_upload_at(uuid,uuid,uuid,bigint,bigint,text,text,timestamptz),
  public.get_mobile_reevaluation_photo_upload_completion(uuid,uuid,uuid),
  public.complete_mobile_reevaluation_photo_upload(uuid,uuid,uuid,bigint,bigint,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_reevaluation_photo_upload_completion(uuid,uuid,uuid),
  public.complete_mobile_reevaluation_photo_upload(uuid,uuid,uuid,bigint,bigint,text,text) TO service_role;
COMMIT;
