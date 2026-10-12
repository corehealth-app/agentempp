-- D4: durable signup-only disposition. Task2 + Task3 required.
BEGIN;
-- NULL is historical/unknown: only new INSERTs passing the Task4 fence get 1.
-- No DEFAULT, UPDATE or backfill can attribute a generation to old photos.
ALTER TABLE public.media_assets ADD COLUMN signup_disposition_version smallint;
ALTER TABLE public.media_assets ADD CONSTRAINT media_signup_disposition_version_shape
 CHECK ((signup_disposition_version IS NULL OR
  (signup_origin IS TRUE AND signup_disposition_version=1)) IS TRUE);
CREATE FUNCTION private.preserve_signup_disposition_version()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.signup_disposition_version IS DISTINCT FROM OLD.signup_disposition_version THEN
  RAISE EXCEPTION 'signup_body_photo_disposition_version_immutable' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER preserve_signup_disposition_version BEFORE UPDATE ON public.media_assets
 FOR EACH ROW EXECUTE FUNCTION private.preserve_signup_disposition_version();
REVOKE ALL ON FUNCTION private.preserve_signup_disposition_version() FROM PUBLIC,anon,authenticated,service_role;
-- Durable private capture of the completed signup scope.
-- Apply only after Task3 reviewed migration. No media FK or generic media/core replacement.
CREATE TABLE private.signup_body_photo_dispositions (
 user_id uuid NOT NULL,
 onboarding_completed_at timestamptz NOT NULL,
 version smallint NOT NULL DEFAULT 1 CHECK(version=1),
 policy text NOT NULL DEFAULT 'delete_all_signup_v1' CHECK(policy='delete_all_signup_v1'),
 scope_sealed boolean NOT NULL DEFAULT true CHECK(scope_sealed IS TRUE),
 sealed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 manifest_count bigint NOT NULL CHECK(manifest_count BETWEEN 1 AND 9007199254740991),
 estimate_state text NOT NULL DEFAULT 'pending' CHECK(estimate_state IN ('pending','saved','unusable')),
 captured_candidate_method text,
 captured_candidate_value numeric(4,2),
 captured_front_asset_id uuid,
 captured_side_asset_id uuid,
 captured_back_asset_id uuid,
 captured_consent_document_id uuid,
 captured_consent_key text,
 captured_consent_version text,
 captured_consent_locale text,
 captured_consent_hash text,
 captured_consent_accepted_at timestamptz,
 captured_bf_percent_estimated numeric,
 captured_bf_source text,
 captured_bf_estimated_at timestamptz,
 estimate_method text,
 estimate_value numeric(4,2),
 estimate_front_asset_id uuid,
 estimate_side_asset_id uuid,
 estimate_back_asset_id uuid,
 estimate_decided_at timestamptz,
 estimate_proof text,
 sweep_no bigint NOT NULL DEFAULT 1 CHECK(sweep_no BETWEEN 1 AND 9007199254740991),
 last_asset_id uuid,
 sweep_state text NOT NULL DEFAULT 'pending' CHECK(sweep_state IN ('pending','complete')),
 last_sweep_completed_at timestamptz,
 PRIMARY KEY(user_id,onboarding_completed_at),
 FOREIGN KEY(user_id,onboarding_completed_at) REFERENCES private.signup_body_photo_receipts(user_id,onboarding_completed_at) ON DELETE CASCADE,
 CONSTRAINT signup_disposition_candidate_shape CHECK ((
  (captured_candidate_method IS NULL AND captured_candidate_value IS NULL AND captured_front_asset_id IS NULL AND captured_side_asset_id IS NULL AND captured_back_asset_id IS NULL)
  OR (captured_candidate_method='arithmetic_mean_v1' AND captured_candidate_value IS NOT NULL AND captured_candidate_value BETWEEN 3 AND 60 AND captured_front_asset_id IS NOT NULL AND captured_side_asset_id IS NOT NULL AND captured_back_asset_id IS NOT NULL AND captured_front_asset_id<>captured_side_asset_id AND captured_front_asset_id<>captured_back_asset_id AND captured_side_asset_id<>captured_back_asset_id)
 ) IS TRUE),
 CONSTRAINT signup_disposition_consent_shape CHECK ((
  (captured_consent_document_id IS NULL AND captured_consent_key IS NULL AND captured_consent_version IS NULL AND captured_consent_locale IS NULL AND captured_consent_hash IS NULL AND captured_consent_accepted_at IS NULL)
  OR (captured_consent_document_id IS NOT NULL AND captured_consent_key='body_photo_estimate_consent' AND captured_consent_version IS NOT NULL AND length(captured_consent_version)>0 AND captured_consent_locale IN ('pt-BR','en-US') AND captured_consent_hash IS NOT NULL AND captured_consent_hash ~ '^[0-9a-f]{64}$')
 ) IS TRUE),
 CONSTRAINT signup_disposition_estimate_shape CHECK ((CASE estimate_state
  WHEN 'pending' THEN estimate_method IS NULL AND estimate_value IS NULL AND estimate_front_asset_id IS NULL AND estimate_side_asset_id IS NULL AND estimate_back_asset_id IS NULL AND estimate_decided_at IS NULL AND estimate_proof IS NULL
  WHEN 'unusable' THEN estimate_method IS NULL AND estimate_value IS NULL AND estimate_front_asset_id IS NULL AND estimate_side_asset_id IS NULL AND estimate_back_asset_id IS NULL AND estimate_decided_at IS NOT NULL AND estimate_proof='unusable'
  WHEN 'saved' THEN estimate_method='arithmetic_mean_v1' AND estimate_value IS NOT NULL AND estimate_value BETWEEN 3 AND 60 AND estimate_front_asset_id IS NOT NULL AND estimate_side_asset_id IS NOT NULL AND estimate_back_asset_id IS NOT NULL AND estimate_front_asset_id<>estimate_side_asset_id AND estimate_front_asset_id<>estimate_back_asset_id AND estimate_side_asset_id<>estimate_back_asset_id AND estimate_decided_at IS NOT NULL AND estimate_proof IN ('accepted_receipt','d4_save')
  ELSE false END) IS TRUE)
);
CREATE TABLE private.signup_body_photo_disposition_assets (
 user_id uuid NOT NULL,
 onboarding_completed_at timestamptz NOT NULL,
 asset_id uuid NOT NULL,
 bucket_id text NOT NULL CHECK(bucket_id='body-checkin-photos'),
 object_path text NOT NULL,
 context_text text NOT NULL CHECK(context_text IN ('Foto de frente.','Foto de lado.','Foto de costas.')),
 catalogue_disposition text NOT NULL DEFAULT 'pending' CHECK(catalogue_disposition IN ('pending','deleted','failed_upload_preserved','absent')),
 disposed_at timestamptz,
 last_sweep_no bigint NOT NULL DEFAULT 0 CHECK(last_sweep_no BETWEEN 0 AND 9007199254740991),
 last_remove_ack_at timestamptz,
 PRIMARY KEY(user_id,onboarding_completed_at,asset_id),
 UNIQUE(asset_id),
 FOREIGN KEY(user_id,onboarding_completed_at) REFERENCES private.signup_body_photo_dispositions(user_id,onboarding_completed_at) ON DELETE CASCADE,
 CONSTRAINT signup_disposition_path_shape CHECK(object_path ~ ('^'||user_id::text||'/'||asset_id::text||'[.][a-z0-9]+$')),
 CONSTRAINT signup_disposition_asset_progress CHECK((catalogue_disposition='pending' AND disposed_at IS NULL AND last_sweep_no=0 AND last_remove_ack_at IS NULL) OR (catalogue_disposition<>'pending' AND disposed_at IS NOT NULL AND last_sweep_no>=1 AND last_remove_ack_at IS NOT NULL))
);
ALTER TABLE private.signup_body_photo_dispositions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.signup_body_photo_disposition_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.signup_body_photo_dispositions,private.signup_body_photo_disposition_assets FROM PUBLIC,anon,authenticated,service_role;
-- PK supports owner/generation/UUID keyset; UNIQUE(asset_id) supports assignment guards.
CREATE INDEX signup_disposition_owner_sweep_idx ON private.signup_body_photo_dispositions(user_id,sweep_state,onboarding_completed_at);

CREATE FUNCTION private.preserve_signup_disposition_header()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE mutable text[]:=ARRAY['estimate_state','estimate_method','estimate_value','estimate_front_asset_id','estimate_side_asset_id','estimate_back_asset_id','estimate_decided_at','estimate_proof','sweep_no','last_asset_id','sweep_state','last_sweep_completed_at'];
BEGIN
 IF (to_jsonb(NEW)-mutable) IS DISTINCT FROM (to_jsonb(OLD)-mutable)
  OR (OLD.estimate_state<>'pending' AND (to_jsonb(NEW)-ARRAY['sweep_no','last_asset_id','sweep_state','last_sweep_completed_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['sweep_no','last_asset_id','sweep_state','last_sweep_completed_at']))
  OR NEW.sweep_no<OLD.sweep_no OR NEW.sweep_no>OLD.sweep_no+1
  OR (NEW.sweep_no=OLD.sweep_no+1 AND (OLD.sweep_state<>'complete' OR NEW.sweep_state<>'pending' OR NEW.last_asset_id IS NOT NULL))
  OR (NEW.sweep_no=OLD.sweep_no AND OLD.last_asset_id IS NOT NULL AND (NEW.last_asset_id IS NULL OR NEW.last_asset_id<OLD.last_asset_id)) THEN
  RAISE EXCEPTION 'signup_body_photo_disposition_immutable' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER preserve_signup_disposition_header BEFORE UPDATE ON private.signup_body_photo_dispositions FOR EACH ROW EXECUTE FUNCTION private.preserve_signup_disposition_header();
CREATE FUNCTION private.preserve_signup_disposition_asset()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF (to_jsonb(NEW)-ARRAY['catalogue_disposition','disposed_at','last_sweep_no','last_remove_ack_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['catalogue_disposition','disposed_at','last_sweep_no','last_remove_ack_at'])
  OR (OLD.disposed_at IS NOT NULL AND NEW.disposed_at IS DISTINCT FROM OLD.disposed_at)
  OR NEW.last_sweep_no<OLD.last_sweep_no THEN
  RAISE EXCEPTION 'signup_body_photo_disposition_asset_immutable' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER preserve_signup_disposition_asset BEFORE UPDATE ON private.signup_body_photo_disposition_assets FOR EACH ROW EXECUTE FUNCTION private.preserve_signup_disposition_asset();

CREATE FUNCTION private.assert_signup_disposition_asset_identity(p_user_id uuid,p_generation timestamptz,p_asset_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE a private.signup_body_photo_disposition_assets%ROWTYPE; m public.media_assets%ROWTYPE;
BEGIN
 SELECT * INTO a FROM private.signup_body_photo_disposition_assets WHERE user_id=p_user_id AND onboarding_completed_at=p_generation AND asset_id=p_asset_id;
 IF NOT FOUND OR a.bucket_id<>'body-checkin-photos' OR a.object_path !~ ('^'||p_user_id::text||'/'||p_asset_id::text||'[.][a-z0-9]+$') THEN
  RAISE EXCEPTION 'signup_body_photo_disposition_identity_mismatch' USING ERRCODE='22023';
 END IF;
 SELECT * INTO m FROM public.media_assets WHERE id=p_asset_id;
 IF FOUND AND (m.user_id IS DISTINCT FROM p_user_id OR m.kind IS DISTINCT FROM 'body_checkin_photo' OR m.signup_origin IS NOT TRUE OR m.signup_disposition_version IS DISTINCT FROM 1 OR m.context_text IS DISTINCT FROM a.context_text OR m.bucket_id IS DISTINCT FROM a.bucket_id OR m.object_path IS DISTINCT FROM a.object_path) THEN
  RAISE EXCEPTION 'signup_body_photo_disposition_identity_mismatch' USING ERRCODE='22023';
 END IF;
END; $$;

-- Private only. Public wrapper already owns advisory/user/profile/assets locks and captured preclose inputs.
CREATE FUNCTION private.seal_signup_body_photo_disposition(
 p_user_id uuid,p_generation timestamptz,p_asset_ids uuid[],p_preclosed_snapshot jsonb,
 p_bf_percent_estimated numeric,p_bf_source text,p_bf_estimated_at timestamptz
) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE ids uuid[]; candidate jsonb; consent jsonb; has_candidate boolean; existing_count bigint;
BEGIN
 IF p_user_id IS NULL OR p_generation IS NULL OR p_asset_ids IS NULL THEN RAISE EXCEPTION 'invalid_signup_body_photo_disposition' USING ERRCODE='22023'; END IF;
 IF cardinality(p_asset_ids)=0 THEN RETURN; END IF;
 IF EXISTS(SELECT 1 FROM private.signup_body_photo_dispositions WHERE user_id=p_user_id AND onboarding_completed_at=p_generation) THEN RETURN; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.users u JOIN public.user_profiles p ON p.user_id=u.id WHERE u.id=p_user_id AND u.status='active' AND p.onboarding_completed IS TRUE AND p.onboarding_completed_at=p_generation) THEN RAISE EXCEPTION 'signup_body_photo_disposition_generation_changed' USING ERRCODE='40001'; END IF;
 IF p_preclosed_snapshot->>'user_id' IS DISTINCT FROM p_user_id::text OR p_preclosed_snapshot#>>'{generation_token,onboarding_completed}' IS DISTINCT FROM 'false' OR p_preclosed_snapshot#>>'{generation_token,onboarding_completed_at}' IS NOT NULL THEN RAISE EXCEPTION 'invalid_signup_body_photo_disposition_capture' USING ERRCODE='22023'; END IF;
 SELECT array_agg(m.id ORDER BY m.id) INTO ids FROM public.media_assets m WHERE m.user_id=p_user_id AND m.kind='body_checkin_photo' AND m.signup_origin IS TRUE AND m.signup_disposition_version=1 AND NOT EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets assigned WHERE assigned.asset_id=m.id);
 IF ids IS DISTINCT FROM p_asset_ids OR cardinality(ids)<>cardinality(ARRAY(SELECT DISTINCT a.id FROM unnest(p_asset_ids) a(id))) THEN RAISE EXCEPTION 'signup_body_photo_disposition_scope_changed' USING ERRCODE='40001'; END IF;
 IF EXISTS(SELECT 1 FROM public.media_assets m WHERE m.id=ANY(ids) AND (m.bucket_id<>'body-checkin-photos' OR m.context_text NOT IN ('Foto de frente.','Foto de lado.','Foto de costas.') OR m.object_path !~ ('^'||p_user_id::text||'/'||m.id::text||'[.][a-z0-9]+$'))) THEN RAISE EXCEPTION 'signup_body_photo_disposition_identity_mismatch' USING ERRCODE='22023'; END IF;
 candidate:=p_preclosed_snapshot->'candidate'; consent:=p_preclosed_snapshot->'consent';
 has_candidate:=jsonb_typeof(candidate)='object';
 IF has_candidate AND (candidate->>'method' IS DISTINCT FROM 'arithmetic_mean_v1' OR consent#>>'{accepted_at}' IS NULL OR (candidate#>>'{source_ids,front}')::uuid IS NULL OR (candidate#>>'{source_ids,side}')::uuid IS NULL OR (candidate#>>'{source_ids,back}')::uuid IS NULL OR NOT ((candidate#>>'{source_ids,front}')::uuid=ANY(ids) AND (candidate#>>'{source_ids,side}')::uuid=ANY(ids) AND (candidate#>>'{source_ids,back}')::uuid=ANY(ids))) THEN RAISE EXCEPTION 'invalid_signup_body_photo_disposition_capture' USING ERRCODE='22023'; END IF;
 INSERT INTO private.signup_body_photo_receipts(user_id,onboarding_completed_at) VALUES(p_user_id,p_generation) ON CONFLICT(user_id,onboarding_completed_at) DO NOTHING;
 INSERT INTO private.signup_body_photo_dispositions(user_id,onboarding_completed_at,manifest_count,
  captured_candidate_method,captured_candidate_value,captured_front_asset_id,captured_side_asset_id,captured_back_asset_id,
  captured_consent_document_id,captured_consent_key,captured_consent_version,captured_consent_locale,captured_consent_hash,captured_consent_accepted_at,
  captured_bf_percent_estimated,captured_bf_source,captured_bf_estimated_at)
 VALUES(p_user_id,p_generation,cardinality(ids),
  CASE WHEN has_candidate THEN candidate->>'method' END,CASE WHEN has_candidate THEN (candidate->>'body_fat_percent')::numeric(4,2) END,
  CASE WHEN has_candidate THEN (candidate#>>'{source_ids,front}')::uuid END,CASE WHEN has_candidate THEN (candidate#>>'{source_ids,side}')::uuid END,CASE WHEN has_candidate THEN (candidate#>>'{source_ids,back}')::uuid END,
  CASE WHEN jsonb_typeof(consent)='object' THEN (consent->>'legal_document_id')::uuid END,CASE WHEN jsonb_typeof(consent)='object' THEN consent->>'document_key' END,
  CASE WHEN jsonb_typeof(consent)='object' THEN consent->>'version' END,CASE WHEN jsonb_typeof(consent)='object' THEN consent->>'locale' END,CASE WHEN jsonb_typeof(consent)='object' THEN consent->>'body_hash' END,
  CASE WHEN jsonb_typeof(consent)='object' THEN (consent->>'accepted_at')::timestamptz END,
  p_bf_percent_estimated,p_bf_source,p_bf_estimated_at);
 INSERT INTO private.signup_body_photo_disposition_assets(user_id,onboarding_completed_at,asset_id,bucket_id,object_path,context_text)
 SELECT p_user_id,p_generation,m.id,m.bucket_id,m.object_path,m.context_text FROM public.media_assets m WHERE m.id=ANY(ids) ORDER BY m.id;
 SELECT count(*) INTO existing_count FROM private.signup_body_photo_disposition_assets WHERE user_id=p_user_id AND onboarding_completed_at=p_generation;
 IF existing_count<>cardinality(ids) THEN RAISE EXCEPTION 'signup_body_photo_disposition_scope_changed' USING ERRCODE='40001'; END IF;
END; $$;

-- TRUE alone joins the onboarding advisory/user/profile lock order; no generic status machine changes.
CREATE FUNCTION private.fence_signup_body_photo_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE completed boolean; completed_at timestamptz;
BEGIN
 IF NEW.signup_origin IS NOT TRUE THEN RETURN NEW; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('mobile-onboarding:'||NEW.user_id::text,0));
 SELECT p.onboarding_completed,p.onboarding_completed_at INTO completed,completed_at FROM public.users u JOIN public.user_profiles p ON p.user_id=u.id WHERE u.id=NEW.user_id AND u.status='active' FOR UPDATE OF u,p;
 IF NOT FOUND THEN RAISE EXCEPTION 'body_photos_unavailable' USING ERRCODE='22023'; END IF;
 IF completed IS NOT FALSE OR completed_at IS NOT NULL THEN RAISE EXCEPTION 'onboarding_already_completed' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets a WHERE a.asset_id=NEW.id) THEN RAISE EXCEPTION 'signup_body_photo_disposition_asset_closed' USING ERRCODE='22023'; END IF;
 NEW.signup_disposition_version:=1;
 RETURN NEW;
END; $$;
CREATE TRIGGER fence_signup_body_photo_insert BEFORE INSERT ON public.media_assets FOR EACH ROW WHEN(NEW.signup_origin IS TRUE) EXECUTE FUNCTION private.fence_signup_body_photo_insert();
-- Guard UUID reuse for ALL markers after uniqueness waits, while false/NULL new IDs keep the old path.
CREATE FUNCTION private.reject_reused_signup_disposition_asset()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='UPDATE' THEN
  IF EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets a WHERE a.asset_id IN (OLD.id,NEW.id)) THEN
   RAISE EXCEPTION 'signup_body_photo_disposition_asset_closed' USING ERRCODE='22023';
  END IF;
 ELSIF EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets a WHERE a.asset_id=NEW.id) THEN
  RAISE EXCEPTION 'signup_body_photo_disposition_asset_closed' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER reject_reused_signup_disposition_asset AFTER INSERT ON public.media_assets FOR EACH ROW EXECUTE FUNCTION private.reject_reused_signup_disposition_asset();
-- Historical sealed identities cannot be renamed into or out of another generation.
CREATE TRIGGER reject_renamed_signup_disposition_asset BEFORE UPDATE OF id ON public.media_assets
 FOR EACH ROW WHEN (OLD.id IS DISTINCT FROM NEW.id) EXECUTE FUNCTION private.reject_reused_signup_disposition_asset();
REVOKE ALL ON FUNCTION private.preserve_signup_disposition_header(),private.preserve_signup_disposition_asset(),private.assert_signup_disposition_asset_identity(uuid,timestamptz,uuid),private.seal_signup_body_photo_disposition(uuid,timestamptz,uuid[],jsonb,numeric,text,timestamptz),private.fence_signup_body_photo_insert(),private.reject_reused_signup_disposition_asset() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.build_signup_body_photo_snapshot(p_user_id uuid, p_include_open_photos boolean)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog AS $$
DECLARE v_result jsonb;
BEGIN
  IF p_user_id IS NULL OR p_include_open_photos IS NULL THEN
    RAISE EXCEPTION 'invalid_body_photo_snapshot_request' USING ERRCODE = '22023';
  END IF;
  -- The preliminary closed/profile-only snapshot is returned as a whole.
  -- An open read replaces it with one fully correlated SELECT below.
    WITH account AS (
      SELECT u.id, u.locale, u.timezone, p.user_id IS NOT NULL AS present,
        COALESCE(p.onboarding_completed, false) AS completed, p.onboarding_completed_at AS completed_at,
        p.body_fat_percent, (SELECT count(*) FROM private.signup_body_photo_receipts h WHERE h.user_id = u.id) AS receipt_count
      FROM public.users u LEFT JOIN public.user_profiles p ON p.user_id = u.id
      WHERE u.id = p_user_id AND u.status = 'active'
    )
    SELECT jsonb_build_object(
      'version', 1, 'user_id', a.id, 'profile_present', a.present, 'locale', a.locale, 'timezone', a.timezone,
      'generation_token', jsonb_build_object('onboarding_completed', a.completed, 'onboarding_completed_at', a.completed_at, 'receipt_count', a.receipt_count),
      'poses', '[]'::jsonb, 'remaining_uploads', 0, 'consent', NULL, 'estimate', NULL, 'candidate', NULL,
      'confirmation', CASE WHEN r.decision IS NULL THEN NULL ELSE jsonb_build_object(
        'decision', r.decision, 'method', r.method,
        'source_ids', CASE WHEN r.decision = 'accepted' THEN jsonb_build_object('front', r.front_asset_id, 'side', r.side_asset_id, 'back', r.back_asset_id) ELSE NULL END,
        'fingerprint', r.fingerprint, 'confirmed_body_fat_percent', r.confirmed_body_fat_percent,
        'decided_at', r.decided_at, 'invalidated_at', r.invalidated_at,
        'active', COALESCE(r.decision = 'accepted' AND r.invalidated_at IS NULL AND a.completed
          AND a.completed_at = r.onboarding_completed_at AND a.body_fat_percent = r.confirmed_body_fat_percent, false)
      ) END
    ) INTO v_result FROM account a LEFT JOIN private.signup_body_photo_receipts r
      ON r.user_id = a.id AND r.onboarding_completed_at = a.completed_at;
  IF p_include_open_photos AND v_result IS NOT NULL
    AND (v_result ->> 'profile_present')::boolean
    AND NOT (v_result #>> '{generation_token,onboarding_completed}')::boolean
    AND v_result #>> '{generation_token,onboarding_completed_at}' IS NULL THEN
    WITH instant AS MATERIALIZED (SELECT clock_timestamp() AS at),
    account AS MATERIALIZED (
      SELECT u.id, u.locale, u.timezone, p.user_id IS NOT NULL AS present,
        COALESCE(p.onboarding_completed, false) AS completed, p.onboarding_completed_at AS completed_at,
        p.body_fat_percent, (SELECT count(*) FROM private.signup_body_photo_receipts h WHERE h.user_id = u.id) AS receipt_count
      FROM public.users u LEFT JOIN public.user_profiles p ON p.user_id = u.id
      WHERE u.id = p_user_id AND u.status = 'active'
    ), document AS MATERIALIZED (
      SELECT d.* FROM public.legal_documents d JOIN account a ON d.locale = a.locale
      CROSS JOIN instant i WHERE d.document_key = 'body_photo_estimate_consent' AND d.required_from <= i.at
        AND a.present AND NOT a.completed AND a.completed_at IS NULL
      ORDER BY d.required_from DESC, d.created_at DESC, d.id DESC LIMIT 1
    ), consent AS MATERIALIZED (
      SELECT d.*, accepted.accepted_at FROM document d LEFT JOIN public.user_legal_acceptances accepted
        ON accepted.user_id = p_user_id AND accepted.legal_document_id = d.id
        AND accepted.document_key = d.document_key AND accepted.version = d.version
        AND accepted.locale = d.locale AND accepted.body_hash = d.body_hash
    ), selected AS MATERIALIZED (
      SELECT DISTINCT ON (m.context_text)
        CASE m.context_text WHEN 'Foto de frente.' THEN 'front' WHEN 'Foto de lado.' THEN 'side' ELSE 'back' END AS pose,
        m.id, m.status, m.failure_stage, m.created_at, m.uploaded_at,
        CASE WHEN m.processing_result ->> 'type' = 'body'
            AND jsonb_typeof(m.processing_result -> 'bf_percent_estimate') = 'number'
          THEN (m.processing_result ->> 'bf_percent_estimate')::numeric ELSE NULL END AS reading
      FROM public.media_assets m JOIN account a ON m.user_id = a.id
      WHERE m.kind = 'body_checkin_photo' AND m.signup_origin IS TRUE AND m.signup_disposition_version=1
        AND NOT EXISTS (SELECT 1 FROM private.signup_body_photo_disposition_assets assigned WHERE assigned.asset_id = m.id)
        AND m.context_text IN ('Foto de frente.', 'Foto de lado.', 'Foto de costas.')
        AND NOT a.completed AND a.completed_at IS NULL AND a.present
        AND EXISTS (SELECT 1 FROM document)
        AND (m.status IN ('uploaded', 'processing', 'processed')
          OR (m.status = 'failed' AND m.failure_stage = 'processing'))
      ORDER BY m.context_text, m.uploaded_at DESC NULLS LAST, m.id DESC
    ), triad AS (
      SELECT count(*) = 3 AND bool_and(s.status = 'processed' AND s.reading IS NOT NULL) AS finite,
        bool_and(s.reading BETWEEN 3 AND 60) AS in_range,
        round(sum(CASE WHEN s.reading BETWEEN 3 AND 60 THEN s.reading ELSE NULL END) / 3, 2) AS mean,
        jsonb_object_agg(s.pose, s.id) AS ids,
        jsonb_agg(jsonb_build_object('pose', s.pose, 'id', s.id,
          'uploaded_at_us', (extract(epoch FROM s.uploaded_at) * 1000000)::bigint, 'reading', s.reading)
          ORDER BY CASE s.pose WHEN 'front' THEN 0 WHEN 'side' THEN 1 ELSE 2 END) AS fingerprint_rows
      FROM selected s
    ), evaluation AS (
      SELECT t.*, c.accepted_at IS NOT NULL AND t.finite IS TRUE AS readable,
        c.accepted_at IS NOT NULL AND t.finite IS TRUE AND t.in_range IS TRUE AS usable
      FROM triad t LEFT JOIN consent c ON true
    )
    SELECT jsonb_build_object(
      'version', 1, 'user_id', a.id, 'profile_present', a.present, 'locale', a.locale, 'timezone', a.timezone,
      'generation_token', jsonb_build_object('onboarding_completed', a.completed, 'onboarding_completed_at', a.completed_at, 'receipt_count', a.receipt_count),
      'poses', CASE WHEN a.present AND NOT a.completed AND a.completed_at IS NULL
        THEN COALESCE((SELECT jsonb_agg(jsonb_build_object('pose', poses.pose, 'photo',
        CASE WHEN s.id IS NULL THEN NULL ELSE jsonb_build_object('id', s.id, 'created_at', s.created_at, 'status',
          CASE WHEN s.status = 'processing' THEN 'reading'
            WHEN s.status = 'processed' THEN CASE WHEN s.reading IS NULL THEN 'unreadable' ELSE 'read' END
            WHEN s.status = 'failed' THEN 'reading_failed' ELSE s.status END) END)
        ORDER BY poses.ordinality)
        FROM unnest(ARRAY['front','side','back']) WITH ORDINALITY poses(pose, ordinality)
        LEFT JOIN selected s ON s.pose = poses.pose), '[]'::jsonb) ELSE '[]'::jsonb END,
      'remaining_uploads', CASE WHEN c.id IS NULL THEN 0 ELSE greatest(0, 9 - (
        SELECT count(*) FROM public.media_assets m CROSS JOIN instant i WHERE m.user_id = a.id
          AND m.kind = 'body_checkin_photo' AND m.signup_origin IS TRUE AND m.created_at >= i.at - interval '24 hours'
      )) END,
      'consent', CASE WHEN c.id IS NULL THEN NULL ELSE jsonb_build_object(
        'legal_document_id', c.id, 'document_key', c.document_key, 'version', c.version, 'locale', c.locale,
        'body', c.body, 'body_hash', c.body_hash, 'accepted_at', c.accepted_at) END,
      'estimate', CASE WHEN NOT e.readable THEN NULL ELSE jsonb_build_object('is_estimate', true, 'by_sex', jsonb_build_object(
        'masculino', CASE WHEN e.usable THEN jsonb_build_object('usable', true, 'body_fat_percent', e.mean) ELSE jsonb_build_object('usable', false, 'reason', 'out_of_range') END,
        'feminino', CASE WHEN e.usable THEN jsonb_build_object('usable', true, 'body_fat_percent', e.mean) ELSE jsonb_build_object('usable', false, 'reason', 'out_of_range') END)) END,
      'candidate', CASE WHEN NOT e.usable THEN NULL ELSE jsonb_build_object(
        'method', 'arithmetic_mean_v1', 'body_fat_percent', e.mean, 'source_ids', e.ids,
        'fingerprint', encode(extensions.digest(convert_to(jsonb_build_object('version', 1, 'method', 'arithmetic_mean_v1',
          'owner', a.id, 'receipt_count', a.receipt_count, 'sources', e.fingerprint_rows)::text, 'UTF8'), 'sha256'), 'hex')) END,
      'confirmation', CASE WHEN r.decision IS NULL THEN NULL ELSE jsonb_build_object(
        'decision', r.decision, 'method', r.method,
        'source_ids', CASE WHEN r.decision = 'accepted' THEN jsonb_build_object('front', r.front_asset_id, 'side', r.side_asset_id, 'back', r.back_asset_id) ELSE NULL END,
        'fingerprint', r.fingerprint, 'confirmed_body_fat_percent', r.confirmed_body_fat_percent,
        'decided_at', r.decided_at, 'invalidated_at', r.invalidated_at,
        'active', COALESCE(r.decision = 'accepted' AND r.invalidated_at IS NULL AND a.completed
          AND a.completed_at = r.onboarding_completed_at AND a.body_fat_percent = r.confirmed_body_fat_percent, false)) END
    ) INTO v_result FROM account a CROSS JOIN evaluation e LEFT JOIN consent c ON true
      LEFT JOIN private.signup_body_photo_receipts r ON r.user_id = a.id AND r.onboarding_completed_at = a.completed_at;
  END IF;
  IF v_result IS NULL THEN
    RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF (v_result #>> '{generation_token,receipt_count}')::bigint > 9007199254740991 THEN
    RAISE EXCEPTION 'invalid_body_photo_snapshot_count' USING ERRCODE = '22003';
  END IF;
  RETURN v_result;
END;
$$;


CREATE OR REPLACE FUNCTION public.complete_mobile_onboarding_with_body_photo_confirmation(
  p_user_id uuid, p_submission jsonb, p_confirmation jsonb,
  p_expected_completed boolean, p_expected_completed_at timestamptz, p_expected_receipt_count bigint
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  v_completed boolean; v_completed_at timestamptz; v_count bigint;
  v_snapshot jsonb; v_candidate jsonb; v_receipt private.signup_body_photo_receipts%ROWTYPE;
  v_submission jsonb := p_submission; v_result jsonb; v_decision text; v_value numeric(4,2);
  v_front uuid; v_side uuid; v_back uuid; v_fingerprint text; v_fresh boolean;
  v_timezone text; v_locale text; v_final_at timestamptz;
  v_d4_ids uuid[]; v_d4_snapshot jsonb;
  v_d4_bf_percent_estimated numeric; v_d4_bf_source text; v_d4_bf_estimated_at timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR jsonb_typeof(p_submission) IS DISTINCT FROM 'object'
    OR p_expected_completed IS NULL OR p_expected_receipt_count IS NULL
    OR p_expected_receipt_count < 0 OR p_expected_receipt_count > 9007199254740991
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_submission) AS keys(key) WHERE keys.key <> ALL (ARRAY[
      'name','locale','country','timezone','sex','birth_date','height_cm','weight_kg','body_fat_percent',
      'objective','activity_level','training_frequency','water_intake','hunger_level','wake_time','bedtime',
      'food_organization','persona','document_actions'
    ]::text[])) THEN
    RAISE EXCEPTION 'invalid_body_photo_confirmation' USING ERRCODE = '22023';
  END IF;
  IF p_confirmation IS NOT NULL THEN
    IF jsonb_typeof(p_confirmation) IS DISTINCT FROM 'object'
      OR p_confirmation ->> 'decision' NOT IN ('accept','decline')
      OR p_confirmation ->> 'decision' IS NULL THEN
      RAISE EXCEPTION 'invalid_body_photo_confirmation' USING ERRCODE = '22023';
    END IF;
    v_decision := p_confirmation ->> 'decision';
    IF v_decision = 'decline' THEN
      IF p_confirmation - 'decision' <> '{}'::jsonb THEN
        RAISE EXCEPTION 'invalid_body_photo_confirmation' USING ERRCODE = '22023';
      END IF;
    ELSE
      IF p_confirmation - ARRAY['decision','source_ids','fingerprint'] <> '{}'::jsonb
        OR jsonb_typeof(p_confirmation -> 'source_ids') IS DISTINCT FROM 'object'
        OR (p_confirmation -> 'source_ids') - ARRAY['front','side','back'] <> '{}'::jsonb
        OR p_confirmation ->> 'fingerprint' IS NULL OR p_confirmation ->> 'fingerprint' !~ '^[0-9a-f]{64}$'
        OR EXISTS (SELECT 1 FROM unnest(ARRAY['front','side','back']) AS poses(pose)
          WHERE p_confirmation #>> ARRAY['source_ids',pose] IS NULL
            OR p_confirmation #>> ARRAY['source_ids',pose] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
        RAISE EXCEPTION 'invalid_body_photo_confirmation' USING ERRCODE = '22023';
      END IF;
      v_front := (p_confirmation #>> '{source_ids,front}')::uuid;
      v_side := (p_confirmation #>> '{source_ids,side}')::uuid;
      v_back := (p_confirmation #>> '{source_ids,back}')::uuid;
      IF v_front = v_side OR v_front = v_back OR v_side = v_back THEN
        RAISE EXCEPTION 'invalid_body_photo_confirmation' USING ERRCODE = '22023';
      END IF;
      v_fingerprint := p_confirmation ->> 'fingerprint';
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('mobile-onboarding:' || p_user_id::text, 0));
  SELECT p.onboarding_completed, p.onboarding_completed_at, u.timezone, u.locale
    INTO v_completed, v_completed_at, v_timezone, v_locale
    FROM public.users u JOIN public.user_profiles p ON p.user_id = u.id
    WHERE u.id = p_user_id AND u.status = 'active' FOR UPDATE OF u, p;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002';
  END IF;
  SELECT count(*) INTO v_count FROM private.signup_body_photo_receipts WHERE user_id = p_user_id;
  IF p_confirmation IS NOT NULL OR p_expected_receipt_count > 0 OR v_count > 0 THEN
    IF v_completed IS DISTINCT FROM p_expected_completed
      OR v_completed_at IS DISTINCT FROM p_expected_completed_at
      OR v_count IS DISTINCT FROM p_expected_receipt_count THEN
      RAISE EXCEPTION 'onboarding_generation_changed' USING ERRCODE = '40001';
    END IF;
  END IF;
  v_fresh := v_completed_at IS NULL;
  -- Strictly OPEN prestate only; historical/RC-E true-null closures are never backfilled.
  -- Same advisory/users/profile locks are already held. All source rows lock in UUID order
  -- before snapshot/old core, so callbacks cannot change the captured decision mid-close.
  IF v_fresh AND v_completed IS FALSE THEN
    PERFORM m.id FROM public.media_assets m
      WHERE m.user_id=p_user_id AND m.kind='body_checkin_photo' AND m.signup_origin IS TRUE AND m.signup_disposition_version=1
        AND NOT EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets assigned WHERE assigned.asset_id=m.id)
      ORDER BY m.id FOR UPDATE;
    SELECT ARRAY(SELECT m.id FROM public.media_assets m
      WHERE m.user_id=p_user_id AND m.kind='body_checkin_photo' AND m.signup_origin IS TRUE AND m.signup_disposition_version=1
        AND NOT EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets assigned WHERE assigned.asset_id=m.id)
      ORDER BY m.id) INTO v_d4_ids;
    IF cardinality(v_d4_ids)>0 THEN
      v_d4_snapshot:=private.build_signup_body_photo_snapshot(p_user_id,true);
      SELECT p.bf_percent_estimated,p.bf_source,p.bf_estimated_at
        INTO v_d4_bf_percent_estimated,v_d4_bf_source,v_d4_bf_estimated_at
        FROM public.user_profiles p WHERE p.user_id=p_user_id;
    END IF;
  END IF;


  IF p_confirmation IS NOT NULL THEN
    -- Canonicalization is internal; the idempotent payload remains ORIGINAL.
    -- Preserve the delegated RPC's validation of the original numeric values.
    -- Rounding must not turn an out-of-range value or a numeric string valid.
    IF jsonb_typeof(p_submission -> 'height_cm') IS DISTINCT FROM 'number'
      OR jsonb_typeof(p_submission -> 'weight_kg') IS DISTINCT FROM 'number'
      OR (p_submission ? 'body_fat_percent'
        AND jsonb_typeof(p_submission -> 'body_fat_percent') IS DISTINCT FROM 'number') THEN
      RAISE EXCEPTION 'invalid_onboarding_submission' USING ERRCODE = '22023';
    END IF;
    IF (p_submission ->> 'height_cm')::numeric NOT BETWEEN 100 AND 250
      OR (p_submission ->> 'weight_kg')::numeric NOT BETWEEN 30 AND 300
      OR (p_submission ? 'body_fat_percent'
        AND (p_submission ->> 'body_fat_percent')::numeric NOT BETWEEN 3 AND 60) THEN
      RAISE EXCEPTION 'invalid_onboarding_submission' USING ERRCODE = '22023';
    END IF;
    v_submission := jsonb_set(v_submission, '{height_cm}', to_jsonb((p_submission ->> 'height_cm')::numeric(5,2)));
    v_submission := jsonb_set(v_submission, '{weight_kg}', to_jsonb((p_submission ->> 'weight_kg')::numeric(5,2)));
    IF p_submission ? 'body_fat_percent' THEN
      v_submission := jsonb_set(v_submission, '{body_fat_percent}', to_jsonb((p_submission ->> 'body_fat_percent')::numeric(4,2)));
    END IF;
    IF NOT v_fresh THEN
      SELECT * INTO v_receipt FROM private.signup_body_photo_receipts
        WHERE user_id = p_user_id AND onboarding_completed_at = v_completed_at;
      IF v_decision = 'accept' THEN
        IF NOT v_completed OR NOT FOUND OR v_receipt.decision IS DISTINCT FROM 'accepted'
          OR v_receipt.method IS DISTINCT FROM 'arithmetic_mean_v1'
          OR v_receipt.front_asset_id IS DISTINCT FROM v_front OR v_receipt.side_asset_id IS DISTINCT FROM v_side
          OR v_receipt.back_asset_id IS DISTINCT FROM v_back OR v_receipt.fingerprint IS DISTINCT FROM v_fingerprint THEN
          RAISE EXCEPTION 'body_photo_confirmation_unavailable' USING ERRCODE = '22023';
        END IF;
        v_value := v_receipt.confirmed_body_fat_percent;
      ELSIF NOT FOUND OR v_receipt.decision IS DISTINCT FROM 'declined' THEN
        RAISE EXCEPTION 'body_photo_confirmation_unavailable' USING ERRCODE = '22023';
      END IF;
    ELSIF v_decision = 'accept' THEN
      IF v_completed THEN
        RAISE EXCEPTION 'body_photo_confirmation_unavailable' USING ERRCODE = '22023';
      END IF;
      PERFORM private.assert_signup_body_photo_age((p_submission ->> 'birth_date')::date, v_timezone, clock_timestamp());
      IF v_locale IS DISTINCT FROM p_submission ->> 'locale' THEN
        RAISE EXCEPTION 'body_photo_consent_locale_changed' USING ERRCODE = '22023';
      END IF;
      -- Plain rows, not an aggregate/DISTINCT FOR UPDATE. The next SELECT revalidates sources.
      PERFORM m.id FROM public.media_assets m WHERE m.user_id = p_user_id
        AND m.id IN (v_front,v_side,v_back) AND m.kind = 'body_checkin_photo' AND m.signup_origin IS TRUE AND m.signup_disposition_version=1
        ORDER BY m.id FOR UPDATE;
      v_snapshot := private.build_signup_body_photo_snapshot(p_user_id, true);
      IF v_snapshot -> 'consent' = 'null'::jsonb THEN
        RAISE EXCEPTION 'body_photos_unavailable' USING ERRCODE = '22023';
      END IF;
      IF v_snapshot #>> '{consent,accepted_at}' IS NULL THEN
        RAISE EXCEPTION 'body_photo_consent_required' USING ERRCODE = '22023';
      END IF;
      v_candidate := v_snapshot -> 'candidate';
      IF jsonb_typeof(v_candidate) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'body_photo_confirmation_unavailable' USING ERRCODE = '22023';
      END IF;
      IF (v_candidate #>> '{source_ids,front}')::uuid IS DISTINCT FROM v_front
        OR (v_candidate #>> '{source_ids,side}')::uuid IS DISTINCT FROM v_side
        OR (v_candidate #>> '{source_ids,back}')::uuid IS DISTINCT FROM v_back
        OR v_candidate ->> 'fingerprint' IS DISTINCT FROM v_fingerprint THEN
        RAISE EXCEPTION 'body_photo_confirmation_stale' USING ERRCODE = '22023';
      END IF;
      v_value := (v_candidate ->> 'body_fat_percent')::numeric(4,2);
    END IF;
    IF v_decision = 'accept' THEN
      IF p_submission ? 'body_fat_percent' AND (p_submission ->> 'body_fat_percent')::numeric(4,2) IS DISTINCT FROM v_value THEN
        RAISE EXCEPTION 'body_photo_confirmation_value_mismatch' USING ERRCODE = '22023';
      END IF;
      v_submission := jsonb_set(v_submission, '{body_fat_percent}', to_jsonb(v_value), true);
    END IF;
  END IF;

  v_result := public.complete_mobile_onboarding_atomic(p_user_id, v_submission);
  v_final_at := (v_result ->> 'completed_at')::timestamptz;
  IF v_fresh AND (p_confirmation IS NOT NULL OR v_count > 0) THEN
    INSERT INTO private.signup_body_photo_receipts (
      user_id, onboarding_completed_at, decision, method, front_asset_id, side_asset_id, back_asset_id,
      fingerprint, confirmed_body_fat_percent, decided_at
    ) VALUES (
      p_user_id, v_final_at,
      CASE v_decision WHEN 'accept' THEN 'accepted' WHEN 'decline' THEN 'declined' ELSE NULL END,
      CASE WHEN v_decision = 'accept' THEN 'arithmetic_mean_v1' ELSE NULL END,
      CASE WHEN v_decision = 'accept' THEN v_front ELSE NULL END,
      CASE WHEN v_decision = 'accept' THEN v_side ELSE NULL END,
      CASE WHEN v_decision = 'accept' THEN v_back ELSE NULL END,
      CASE WHEN v_decision = 'accept' THEN v_fingerprint ELSE NULL END,
      CASE WHEN v_decision = 'accept' THEN v_value ELSE NULL END,
      CASE WHEN p_confirmation IS NOT NULL THEN clock_timestamp() ELSE NULL END
    );
    IF v_decision = 'accept' THEN
      UPDATE public.user_profiles SET bf_percent_estimated = v_value, bf_source = 'signup_photos', bf_estimated_at = v_final_at
        WHERE user_id = p_user_id;
    END IF;
  END IF;
  IF v_d4_ids IS NOT NULL AND cardinality(v_d4_ids)>0 THEN
    PERFORM private.seal_signup_body_photo_disposition(p_user_id,v_final_at,v_d4_ids,v_d4_snapshot,
      v_d4_bf_percent_estimated,v_d4_bf_source,v_d4_bf_estimated_at);
  END IF;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_mobile_onboarding_with_body_photo_confirmation(uuid,jsonb,jsonb,boolean,timestamptz,bigint)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_mobile_onboarding_with_body_photo_confirmation(uuid,jsonb,jsonb,boolean,timestamptz,bigint)
  TO service_role;


-- Trusted preparation and paginated acknowledgement of the sealed scope.
-- Compose after the parent-owned header/items DDL, sealer and INSERT fence.
-- The three public RPCs return only the strict disposition.ts DTO keys.
-- All workers are private invoker functions with zero client grants.
-- All public entrypoints are backend-only definers, pg_catalog-only path.
-- Required parent-owned helper:
-- private.assert_signup_disposition_asset_identity(uuid,timestamptz,uuid)
-- Capture/proof columns are immutable; this file changes only estimate/sweep
-- progress and catalogue disposition. It never creates or backfills a scope.
-- Technical limit: page p_limit MUST equal 200, so ACK can recompute the exact
-- next page without a mutable page lease. Partial/subset ACKs are rejected.
-- Limit: an RPC ACK attests the backend's observed Storage remove, not Storage
-- object absence. Storage is external and its SDK cannot cancel remove.

CREATE FUNCTION private.prepare_signup_body_photo_disposition(
  p_user_id uuid,
  p_generation timestamptz,
  p_swept_generations timestamptz[]
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog AS $$
DECLARE
  v_profile public.user_profiles%ROWTYPE;
  v_header private.signup_body_photo_dispositions%ROWTYPE;
  v_receipt private.signup_body_photo_receipts%ROWTYPE;
  v_current_completed boolean;
  v_can_save boolean;
  v_count bigint;
  v_remaining_count bigint;
  v_asset_id uuid;
  v_at timestamptz;
BEGIN
  IF p_user_id IS NULL OR p_swept_generations IS NULL
    OR pg_catalog.array_ndims(p_swept_generations) > 1
    OR pg_catalog.array_position(p_swept_generations, NULL::timestamptz) IS NOT NULL
    OR (p_generation IS NOT NULL AND NOT pg_catalog.isfinite(p_generation))
    OR EXISTS (SELECT 1 FROM pg_catalog.unnest(p_swept_generations) AS g(at)
      WHERE NOT pg_catalog.isfinite(g.at)) THEN
    RAISE EXCEPTION 'invalid_body_photo_disposition_request' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('mobile-onboarding:' || p_user_id::text, 0));
  -- This lock order matches close/reset: owner -> users/profile -> receipts
  -- -> header -> captured assets -> catalogue assets in UUID order.
  PERFORM u.id FROM public.users u WHERE u.id = p_user_id AND u.status = 'active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002';
  END IF;
  SELECT p.* INTO v_profile FROM public.user_profiles p WHERE p.user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002';
  END IF;
  v_current_completed := COALESCE(v_profile.onboarding_completed, false)
    OR v_profile.onboarding_completed_at IS NOT NULL;
  PERFORM r.onboarding_completed_at FROM private.signup_body_photo_receipts r
    WHERE r.user_id = p_user_id ORDER BY r.onboarding_completed_at FOR UPDATE;

  -- A closed marked catalogue row without immutable ownership is UNKNOWN.
  -- Never infer its generation from current profile, kind or context.
  IF v_current_completed AND (p_generation IS NULL OR NOT EXISTS (
    SELECT 1 FROM private.signup_body_photo_dispositions exact_scope
    WHERE exact_scope.user_id=p_user_id AND exact_scope.onboarding_completed_at=p_generation
  )) AND EXISTS (
    SELECT 1 FROM public.media_assets m
    WHERE m.user_id = p_user_id AND m.kind = 'body_checkin_photo' AND m.signup_origin IS TRUE
      AND NOT EXISTS (SELECT 1 FROM private.signup_body_photo_disposition_assets a
        WHERE a.asset_id = m.id AND a.user_id = p_user_id)
  ) THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE = '55000';
  END IF;

  SELECT h.* INTO v_header FROM private.signup_body_photo_dispositions h
    WHERE h.user_id = p_user_id
      AND (p_generation IS NULL OR h.onboarding_completed_at = p_generation)
      AND NOT (h.onboarding_completed_at = ANY (p_swept_generations))
    ORDER BY CASE WHEN h.sweep_state = 'pending' THEN 0 ELSE 1 END,
      h.onboarding_completed_at
    LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('version', 1, 'user_id', p_user_id,
      'kind', 'empty', 'current_profile_completed', v_current_completed);
  END IF;
  IF v_header.version IS DISTINCT FROM 1 OR v_header.scope_sealed IS DISTINCT FROM true
    OR v_header.sealed_at IS NULL
    OR v_header.policy IS DISTINCT FROM 'delete_all_signup_v1'
    OR v_header.manifest_count IS NULL OR v_header.manifest_count < 1
    OR v_header.manifest_count > 9007199254740991
    OR v_header.sweep_no IS NULL OR v_header.sweep_no < 1
    OR v_header.sweep_no > 9007199254740991
    OR NOT pg_catalog.isfinite(v_header.onboarding_completed_at) THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE = '55000';
  END IF;
  PERFORM a.asset_id FROM private.signup_body_photo_disposition_assets a
    WHERE a.user_id = p_user_id AND a.onboarding_completed_at = v_header.onboarding_completed_at
    ORDER BY a.asset_id FOR UPDATE;
  SELECT count(*) INTO v_count FROM private.signup_body_photo_disposition_assets a
    WHERE a.user_id = p_user_id AND a.onboarding_completed_at = v_header.onboarding_completed_at;
  IF v_count IS DISTINCT FROM v_header.manifest_count THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE = '55000';
  END IF;
  PERFORM m.id FROM public.media_assets m JOIN private.signup_body_photo_disposition_assets a
    ON a.asset_id = m.id
    WHERE a.user_id = p_user_id AND a.onboarding_completed_at = v_header.onboarding_completed_at
    ORDER BY m.id FOR UPDATE OF m;
  FOR v_asset_id IN SELECT a.asset_id FROM private.signup_body_photo_disposition_assets a
    WHERE a.user_id = p_user_id AND a.onboarding_completed_at = v_header.onboarding_completed_at
    ORDER BY a.asset_id
  LOOP
    PERFORM private.assert_signup_disposition_asset_identity(
      p_user_id, v_header.onboarding_completed_at, v_asset_id);
  END LOOP;

  IF v_header.estimate_state = 'pending' THEN
    SELECT r.* INTO v_receipt FROM private.signup_body_photo_receipts r
      WHERE r.user_id = p_user_id AND r.onboarding_completed_at = v_header.onboarding_completed_at;
    IF FOUND AND v_receipt.decision = 'accepted' THEN
      -- Official acceptance already saved BF3 in the close transaction.
      -- Invalidation does not erase historical proof or authorize a BF3 write.
      UPDATE private.signup_body_photo_dispositions h SET
        estimate_state = 'saved', estimate_method = v_receipt.method,
        estimate_value = v_receipt.confirmed_body_fat_percent,
        estimate_front_asset_id = v_receipt.front_asset_id,
        estimate_side_asset_id = v_receipt.side_asset_id,
        estimate_back_asset_id = v_receipt.back_asset_id,
        estimate_decided_at = v_header.onboarding_completed_at,
        estimate_proof = 'accepted_receipt'
        WHERE h.user_id = p_user_id AND h.onboarding_completed_at = v_header.onboarding_completed_at
        RETURNING h.* INTO v_header;
    ELSE
      -- The sealer captured the exact private snapshot at G. Later consent
      -- document versions/purge do not substitute a different authorization.
      v_can_save := v_profile.onboarding_completed IS TRUE
        AND v_profile.onboarding_completed_at = v_header.onboarding_completed_at
        AND v_header.captured_candidate_method = 'arithmetic_mean_v1'
        AND v_header.captured_candidate_value BETWEEN 3 AND 60
        AND v_header.captured_front_asset_id IS NOT NULL
        AND v_header.captured_side_asset_id IS NOT NULL
        AND v_header.captured_back_asset_id IS NOT NULL
        AND v_header.captured_front_asset_id <> v_header.captured_side_asset_id
        AND v_header.captured_front_asset_id <> v_header.captured_back_asset_id
        AND v_header.captured_side_asset_id <> v_header.captured_back_asset_id
        AND v_header.captured_consent_document_id IS NOT NULL
        AND v_header.captured_consent_key = 'body_photo_estimate_consent'
        AND pg_catalog.length(v_header.captured_consent_version) > 0
        AND v_header.captured_consent_locale IN ('pt-BR', 'en-US')
        AND v_header.captured_consent_hash ~ '^[0-9a-f]{64}$'
        AND v_header.captured_consent_accepted_at IS NOT NULL
        AND EXISTS (SELECT 1 FROM private.signup_body_photo_disposition_assets a
          WHERE a.user_id = p_user_id AND a.onboarding_completed_at = v_header.onboarding_completed_at
            AND a.asset_id = v_header.captured_front_asset_id AND a.context_text = 'Foto de frente.')
        AND EXISTS (SELECT 1 FROM private.signup_body_photo_disposition_assets a
          WHERE a.user_id = p_user_id AND a.onboarding_completed_at = v_header.onboarding_completed_at
            AND a.asset_id = v_header.captured_side_asset_id AND a.context_text = 'Foto de lado.')
        AND EXISTS (SELECT 1 FROM private.signup_body_photo_disposition_assets a
          WHERE a.user_id = p_user_id AND a.onboarding_completed_at = v_header.onboarding_completed_at
            AND a.asset_id = v_header.captured_back_asset_id AND a.context_text = 'Foto de costas.');
      IF v_can_save IS TRUE THEN
        -- NULL-safe CAS preserves a later manual/numeric BF3 write. Conflict
        -- leaves this scope pending and the RPC returns no Storage paths.
        IF v_profile.bf_percent_estimated IS DISTINCT FROM v_header.captured_bf_percent_estimated
          OR v_profile.bf_source IS DISTINCT FROM v_header.captured_bf_source
          OR v_profile.bf_estimated_at IS DISTINCT FROM v_header.captured_bf_estimated_at THEN
          RAISE EXCEPTION 'body_photo_disposition_provenance_conflict' USING ERRCODE = '55000';
        END IF;
        v_at := pg_catalog.clock_timestamp();
        UPDATE public.user_profiles p SET
          bf_percent_estimated = v_header.captured_candidate_value,
          bf_source = 'signup_photos', bf_estimated_at = v_at
          WHERE p.user_id = p_user_id
            AND p.onboarding_completed IS TRUE
            AND p.onboarding_completed_at = v_header.onboarding_completed_at
            AND p.bf_percent_estimated IS NOT DISTINCT FROM v_header.captured_bf_percent_estimated
            AND p.bf_source IS NOT DISTINCT FROM v_header.captured_bf_source
            AND p.bf_estimated_at IS NOT DISTINCT FROM v_header.captured_bf_estimated_at;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'body_photo_disposition_provenance_conflict' USING ERRCODE = '55000';
        END IF;
        UPDATE private.signup_body_photo_dispositions h SET
          estimate_state = 'saved', estimate_method = v_header.captured_candidate_method,
          estimate_value = v_header.captured_candidate_value,
          estimate_front_asset_id = v_header.captured_front_asset_id,
          estimate_side_asset_id = v_header.captured_side_asset_id,
          estimate_back_asset_id = v_header.captured_back_asset_id,
          estimate_decided_at = v_at, estimate_proof = 'd4_save'
          WHERE h.user_id = p_user_id AND h.onboarding_completed_at = v_header.onboarding_completed_at
          RETURNING h.* INTO v_header;
      ELSE
        -- Superseded G or no usable captured estimate needs cleanup without
        -- changing the current profile's BF3. No arithmetic is recomputed.
        UPDATE private.signup_body_photo_dispositions h SET
          estimate_state = 'unusable', estimate_method = NULL, estimate_value = NULL,
          estimate_front_asset_id = NULL, estimate_side_asset_id = NULL, estimate_back_asset_id = NULL,
          estimate_decided_at = pg_catalog.clock_timestamp(), estimate_proof = 'unusable'
          WHERE h.user_id = p_user_id AND h.onboarding_completed_at = v_header.onboarding_completed_at
          RETURNING h.* INTO v_header;
      END IF;
    END IF;
  END IF;
  IF v_header.estimate_state IS NULL OR v_header.estimate_state NOT IN ('saved', 'unusable') THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE = '55000';
  END IF;
  IF v_header.sweep_state = 'complete' THEN
    IF v_header.sweep_no >= 9007199254740991 THEN
      RAISE EXCEPTION 'body_photo_disposition_sweep_overflow' USING ERRCODE = '22003';
    END IF;
    UPDATE private.signup_body_photo_dispositions h SET
      sweep_no = h.sweep_no + 1, last_asset_id = NULL, sweep_state = 'pending'
      WHERE h.user_id = p_user_id AND h.onboarding_completed_at = v_header.onboarding_completed_at
      RETURNING h.* INTO v_header;
  ELSIF v_header.sweep_state IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE = '55000';
  END IF;
  -- Authoritative count for this invocation, including resumed cursors.
  -- The header/cursor is locked and the manifest identity is sealed/immutable.
  SELECT count(*) INTO v_remaining_count FROM private.signup_body_photo_disposition_assets a
    WHERE a.user_id=p_user_id AND a.onboarding_completed_at=v_header.onboarding_completed_at
      AND (v_header.last_asset_id IS NULL OR a.asset_id>v_header.last_asset_id);
  IF v_remaining_count<1 OR v_remaining_count>v_header.manifest_count
    OR v_remaining_count>9007199254740991 THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE='55000';
  END IF;
  -- An active pending sweep retains both number and cursor on retry.
  RETURN pg_catalog.jsonb_build_object('version', 1, 'user_id', p_user_id,
    'kind', 'ready', 'current_profile_completed', v_current_completed,
    'generation', v_header.onboarding_completed_at, 'policy', 'delete_all_signup_v1',
    'estimate_state', v_header.estimate_state, 'sweep_no', v_header.sweep_no,
    'cursor', v_header.last_asset_id, 'manifest_count', v_header.manifest_count,
    'remaining_count', v_remaining_count);
END;
$$;

CREATE FUNCTION private.get_signup_body_photo_disposition_page(
  p_user_id uuid, p_generation timestamptz, p_expected_sweep bigint,
  p_expected_after uuid, p_limit integer
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog AS $$
DECLARE
  v_header private.signup_body_photo_dispositions%ROWTYPE;
  v_ids uuid[];
  v_asset_id uuid;
  v_items jsonb;
  v_has_more boolean;
BEGIN
  IF p_user_id IS NULL OR p_generation IS NULL OR NOT pg_catalog.isfinite(p_generation)
    OR p_expected_sweep IS NULL OR p_expected_sweep < 1 OR p_expected_sweep > 9007199254740991
    OR p_limit IS DISTINCT FROM 200 THEN
    RAISE EXCEPTION 'invalid_body_photo_disposition_request' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('mobile-onboarding:' || p_user_id::text, 0));
  PERFORM u.id FROM public.users u WHERE u.id = p_user_id AND u.status = 'active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002'; END IF;
  PERFORM p.user_id FROM public.user_profiles p WHERE p.user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002'; END IF;
  PERFORM r.onboarding_completed_at FROM private.signup_body_photo_receipts r
    WHERE r.user_id = p_user_id ORDER BY r.onboarding_completed_at FOR UPDATE;
  SELECT h.* INTO v_header FROM private.signup_body_photo_dispositions h
    WHERE h.user_id = p_user_id AND h.onboarding_completed_at = p_generation FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE = '55000';
  END IF;
  IF v_header.scope_sealed IS DISTINCT FROM true OR v_header.version IS DISTINCT FROM 1
    OR v_header.policy IS DISTINCT FROM 'delete_all_signup_v1'
    OR v_header.estimate_state IS NULL OR v_header.estimate_state NOT IN ('saved', 'unusable') THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE = '55000';
  END IF;
  IF v_header.sweep_state IS DISTINCT FROM 'pending'
    OR v_header.sweep_no IS DISTINCT FROM p_expected_sweep
    OR v_header.last_asset_id IS DISTINCT FROM p_expected_after THEN
    RAISE EXCEPTION 'body_photo_disposition_cursor_changed' USING ERRCODE = '40001';
  END IF;
  PERFORM a.asset_id FROM private.signup_body_photo_disposition_assets a
    WHERE a.user_id = p_user_id AND a.onboarding_completed_at = p_generation
    ORDER BY a.asset_id FOR UPDATE;
  SELECT pg_catalog.array_agg(q.asset_id ORDER BY q.asset_id) INTO v_ids
    FROM (SELECT a.asset_id FROM private.signup_body_photo_disposition_assets a
      WHERE a.user_id = p_user_id AND a.onboarding_completed_at = p_generation
        AND (p_expected_after IS NULL OR a.asset_id > p_expected_after)
      ORDER BY a.asset_id LIMIT 200) q;
  IF v_ids IS NULL OR pg_catalog.cardinality(v_ids) < 1 THEN
    RAISE EXCEPTION 'body_photo_disposition_cursor_changed' USING ERRCODE = '40001';
  END IF;
  PERFORM m.id FROM public.media_assets m WHERE m.id = ANY (v_ids) ORDER BY m.id FOR UPDATE;
  FOREACH v_asset_id IN ARRAY v_ids LOOP
    PERFORM private.assert_signup_disposition_asset_identity(p_user_id, p_generation, v_asset_id);
  END LOOP;
  -- Paths are exposed only after the complete page's identity checks pass.
  SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'asset_id', a.asset_id, 'bucket_id', a.bucket_id, 'object_path', a.object_path)
    ORDER BY a.asset_id) INTO v_items
    FROM private.signup_body_photo_disposition_assets a
    WHERE a.user_id = p_user_id AND a.onboarding_completed_at = p_generation
      AND a.asset_id = ANY (v_ids);
  SELECT EXISTS (SELECT 1 FROM private.signup_body_photo_disposition_assets a
    WHERE a.user_id = p_user_id AND a.onboarding_completed_at = p_generation
      AND a.asset_id > v_ids[pg_catalog.cardinality(v_ids)]) INTO v_has_more;
  RETURN pg_catalog.jsonb_build_object('version', 1, 'user_id', p_user_id,
    'generation', p_generation, 'sweep_no', p_expected_sweep,
    'cursor', p_expected_after, 'has_more', v_has_more, 'items', v_items);
END;
$$;

CREATE FUNCTION private.commit_signup_body_photo_disposition_page(
  p_user_id uuid, p_generation timestamptz, p_expected_sweep bigint,
  p_expected_after uuid, p_asset_ids uuid[]
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog AS $$
DECLARE
  v_header private.signup_body_photo_dispositions%ROWTYPE;
  v_media public.media_assets%ROWTYPE;
  v_expected_ids uuid[];
  v_asset_id uuid;
  v_assets jsonb := '[]'::jsonb;
  v_state text;
  v_newly_deleted boolean;
  v_deleted_at timestamptz;
  v_failure_stage text;
  v_failure_code text;
  v_at timestamptz;
  v_complete boolean;
  v_cursor uuid;
BEGIN
  IF p_user_id IS NULL OR p_generation IS NULL OR NOT pg_catalog.isfinite(p_generation)
    OR p_expected_sweep IS NULL OR p_expected_sweep < 1 OR p_expected_sweep > 9007199254740991
    OR p_asset_ids IS NULL OR pg_catalog.cardinality(p_asset_ids) NOT BETWEEN 1 AND 200
    OR pg_catalog.array_ndims(p_asset_ids) IS DISTINCT FROM 1
    OR pg_catalog.array_lower(p_asset_ids, 1) IS DISTINCT FROM 1
    OR pg_catalog.array_position(p_asset_ids, NULL::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'invalid_body_photo_disposition_request' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('mobile-onboarding:' || p_user_id::text, 0));
  PERFORM u.id FROM public.users u WHERE u.id = p_user_id AND u.status = 'active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002'; END IF;
  PERFORM p.user_id FROM public.user_profiles p WHERE p.user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'onboarding_user_not_found' USING ERRCODE = 'P0002'; END IF;
  PERFORM r.onboarding_completed_at FROM private.signup_body_photo_receipts r
    WHERE r.user_id = p_user_id ORDER BY r.onboarding_completed_at FOR UPDATE;
  SELECT h.* INTO v_header FROM private.signup_body_photo_dispositions h
    WHERE h.user_id = p_user_id AND h.onboarding_completed_at = p_generation FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE = '55000';
  END IF;
  IF v_header.scope_sealed IS DISTINCT FROM true OR v_header.version IS DISTINCT FROM 1
    OR v_header.policy IS DISTINCT FROM 'delete_all_signup_v1'
    OR v_header.estimate_state IS NULL OR v_header.estimate_state NOT IN ('saved', 'unusable') THEN
    RAISE EXCEPTION 'body_photo_disposition_scope_unknown' USING ERRCODE = '55000';
  END IF;
  IF v_header.sweep_state IS DISTINCT FROM 'pending'
    OR v_header.sweep_no IS DISTINCT FROM p_expected_sweep
    OR v_header.last_asset_id IS DISTINCT FROM p_expected_after THEN
    RAISE EXCEPTION 'body_photo_disposition_cursor_changed' USING ERRCODE = '40001';
  END IF;
  PERFORM a.asset_id FROM private.signup_body_photo_disposition_assets a
    WHERE a.user_id = p_user_id AND a.onboarding_completed_at = p_generation
    ORDER BY a.asset_id FOR UPDATE;
  SELECT pg_catalog.array_agg(q.asset_id ORDER BY q.asset_id) INTO v_expected_ids
    FROM (SELECT a.asset_id FROM private.signup_body_photo_disposition_assets a
      WHERE a.user_id = p_user_id AND a.onboarding_completed_at = p_generation
        AND (p_expected_after IS NULL OR a.asset_id > p_expected_after)
      ORDER BY a.asset_id LIMIT 200) q;
  -- Exact ordered array equality rejects partial ACKs, duplicates, reordering,
  -- cross-generation IDs and IDs outside the sealed manifest.
  IF v_expected_ids IS NULL OR p_asset_ids IS DISTINCT FROM v_expected_ids THEN
    RAISE EXCEPTION 'body_photo_disposition_page_mismatch' USING ERRCODE = '40001';
  END IF;
  PERFORM m.id FROM public.media_assets m WHERE m.id = ANY (v_expected_ids) ORDER BY m.id FOR UPDATE;
  FOREACH v_asset_id IN ARRAY v_expected_ids LOOP
    PERFORM private.assert_signup_disposition_asset_identity(p_user_id, p_generation, v_asset_id);
  END LOOP;
  v_at := pg_catalog.clock_timestamp();
  FOREACH v_asset_id IN ARRAY v_expected_ids LOOP
    v_newly_deleted := false;
    v_deleted_at := NULL;
    v_failure_stage := NULL;
    v_failure_code := NULL;
    SELECT m.* INTO v_media FROM public.media_assets m WHERE m.id = v_asset_id;
    IF NOT FOUND THEN
      v_state := 'absent';
    ELSIF v_media.status = 'failed' AND v_media.failure_stage = 'upload' THEN
      -- Preserve the original upload failure catalogue state and error.
      -- Even unexpected processing_result is cleared; status is not retried.
      IF v_media.failure_code IS NULL OR pg_catalog.length(v_media.failure_code) < 1
        OR v_media.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'body_photo_disposition_invalid_catalogue' USING ERRCODE = '22023';
      END IF;
      IF v_media.processing_result IS NOT NULL THEN
        UPDATE public.media_assets m SET processing_result = NULL
          WHERE m.id = v_asset_id;
      END IF;
      v_state := 'failed_upload_preserved';
      v_failure_stage := 'upload';
      v_failure_code := v_media.failure_code;
    ELSIF v_media.status IN ('pending_upload', 'uploaded', 'processing', 'processed', 'failed', 'deleted') THEN
      v_state := 'deleted';
      v_newly_deleted := v_media.status <> 'deleted';
      v_deleted_at := COALESCE(v_media.deleted_at, v_at);
      UPDATE public.media_assets m SET status = 'deleted', deleted_at = v_deleted_at,
        failure_stage = NULL, failure_code = NULL, processing_result = NULL
        WHERE m.id = v_asset_id
          AND (m.status <> 'deleted' OR m.deleted_at IS NULL OR m.failure_stage IS NOT NULL
            OR m.failure_code IS NOT NULL OR m.processing_result IS NOT NULL);
    ELSE
      RAISE EXCEPTION 'body_photo_disposition_invalid_catalogue' USING ERRCODE = '22023';
    END IF;
    UPDATE private.signup_body_photo_disposition_assets a SET
      catalogue_disposition = v_state, disposed_at = COALESCE(a.disposed_at, v_at),
      last_sweep_no = p_expected_sweep, last_remove_ack_at = v_at
      WHERE a.user_id = p_user_id AND a.onboarding_completed_at = p_generation AND a.asset_id = v_asset_id;
    v_assets := v_assets || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'asset_id', v_asset_id, 'processing_result', NULL, 'state', v_state,
      'newly_deleted', v_newly_deleted, 'deleted_at', v_deleted_at,
      'failure_stage', v_failure_stage, 'failure_code', v_failure_code));
  END LOOP;
  v_cursor := v_expected_ids[pg_catalog.cardinality(v_expected_ids)];
  SELECT NOT EXISTS (SELECT 1 FROM private.signup_body_photo_disposition_assets a
    WHERE a.user_id = p_user_id AND a.onboarding_completed_at = p_generation
      AND a.asset_id > v_cursor) INTO v_complete;
  UPDATE private.signup_body_photo_dispositions h SET last_asset_id = v_cursor,
    sweep_state = CASE WHEN v_complete THEN 'complete' ELSE 'pending' END,
    last_sweep_completed_at = CASE WHEN v_complete THEN v_at ELSE h.last_sweep_completed_at END
    WHERE h.user_id = p_user_id AND h.onboarding_completed_at = p_generation;
  RETURN pg_catalog.jsonb_build_object('version', 1, 'user_id', p_user_id,
    'generation', p_generation, 'sweep_no', p_expected_sweep,
    'previous_cursor', p_expected_after, 'cursor', v_cursor,
    'sweep_complete', v_complete, 'assets', v_assets);
END;
$$;

CREATE FUNCTION public.prepare_mobile_signup_body_photo_disposition(
  p_user_id uuid, p_generation timestamptz DEFAULT NULL,
  p_swept_generations timestamptz[] DEFAULT '{}'::timestamptz[]
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog AS $$
BEGIN
  PERFORM private.assert_trusted_backend();
  RETURN private.prepare_signup_body_photo_disposition(p_user_id, p_generation, p_swept_generations);
END;
$$;

CREATE FUNCTION public.get_mobile_signup_body_photo_disposition_page(
  p_user_id uuid, p_generation timestamptz, p_expected_sweep bigint,
  p_expected_after uuid, p_limit integer
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog AS $$
BEGIN
  PERFORM private.assert_trusted_backend();
  RETURN private.get_signup_body_photo_disposition_page(
    p_user_id, p_generation, p_expected_sweep, p_expected_after, p_limit);
END;
$$;

CREATE FUNCTION public.commit_mobile_signup_body_photo_disposition_page(
  p_user_id uuid, p_generation timestamptz, p_expected_sweep bigint,
  p_expected_after uuid, p_asset_ids uuid[]
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog AS $$
BEGIN
  PERFORM private.assert_trusted_backend();
  RETURN private.commit_signup_body_photo_disposition_page(
    p_user_id, p_generation, p_expected_sweep, p_expected_after, p_asset_ids);
END;
$$;

REVOKE ALL ON FUNCTION private.prepare_signup_body_photo_disposition(uuid,timestamptz,timestamptz[])
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.get_signup_body_photo_disposition_page(uuid,timestamptz,bigint,uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.commit_signup_body_photo_disposition_page(uuid,timestamptz,bigint,uuid,uuid[])
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.prepare_mobile_signup_body_photo_disposition(uuid,timestamptz,timestamptz[])
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_mobile_signup_body_photo_disposition_page(uuid,timestamptz,bigint,uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.commit_mobile_signup_body_photo_disposition_page(uuid,timestamptz,bigint,uuid,uuid[])
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.prepare_mobile_signup_body_photo_disposition(uuid,timestamptz,timestamptz[])
  TO service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_signup_body_photo_disposition_page(uuid,timestamptz,bigint,uuid,integer)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.commit_mobile_signup_body_photo_disposition_page(uuid,timestamptz,bigint,uuid,uuid[])
  TO service_role;

-- Dedicated upload completion rechecks the current signup scope after Storage inspection.
-- Used only by the signup repository; generic media retains its existing path.
-- Existing Storage validation happens first. This short TX rechecks membership/open state
-- after that external await, without holding any SQL lock during Storage/SDK/network.
CREATE OR REPLACE FUNCTION public.mark_mobile_signup_body_photo_uploaded(
 p_user_id uuid,p_asset_id uuid,p_actual_size_bytes bigint,p_etag text,p_uploaded_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE m public.media_assets%ROWTYPE; completed boolean; completed_at timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_asset_id IS NULL OR p_actual_size_bytes IS NULL OR p_actual_size_bytes<1
  OR p_uploaded_at IS NULL OR NOT isfinite(p_uploaded_at) THEN
  RAISE EXCEPTION 'invalid_signup_body_photo_upload' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('mobile-onboarding:'||p_user_id::text,0));
 SELECT p.onboarding_completed,p.onboarding_completed_at INTO completed,completed_at
  FROM public.users u JOIN public.user_profiles p ON p.user_id=u.id
  WHERE u.id=p_user_id AND u.status='active' FOR UPDATE OF u,p;
 IF NOT FOUND THEN RAISE EXCEPTION 'body_photos_unavailable' USING ERRCODE='22023'; END IF;
 IF completed IS NOT FALSE OR completed_at IS NOT NULL THEN
  RAISE EXCEPTION 'onboarding_already_completed' USING ERRCODE='22023';
 END IF;
 -- Membership remains closed even after a reset reopens the current profile.
 IF EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets a WHERE a.asset_id=p_asset_id) THEN
  RAISE EXCEPTION 'signup_body_photo_disposition_asset_closed' USING ERRCODE='22023';
 END IF;
 SELECT * INTO m FROM public.media_assets WHERE id=p_asset_id AND user_id=p_user_id
  AND kind='body_checkin_photo' AND signup_origin IS TRUE
  AND signup_disposition_version=1 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'body_photo_not_found' USING ERRCODE='P0002'; END IF;
 IF m.bucket_id<>'body-checkin-photos' OR m.context_text NOT IN ('Foto de frente.','Foto de lado.','Foto de costas.')
  OR m.object_path !~ ('^'||p_user_id::text||'/'||p_asset_id::text||'[.][a-z0-9]+$') THEN
  RAISE EXCEPTION 'signup_body_photo_disposition_identity_mismatch' USING ERRCODE='22023';
 END IF;
 IF m.status<>'pending_upload' THEN RAISE EXCEPTION 'media_upload_not_pending' USING ERRCODE='22023'; END IF;
 IF p_actual_size_bytes<>m.declared_size_bytes THEN
  RAISE EXCEPTION 'media_upload_metadata_mismatch' USING ERRCODE='22023';
 END IF;
 UPDATE public.media_assets SET status='uploaded',actual_size_bytes=p_actual_size_bytes,
  etag=p_etag,uploaded_at=p_uploaded_at WHERE id=p_asset_id AND user_id=p_user_id
  AND kind='body_checkin_photo' AND signup_origin IS TRUE AND signup_disposition_version=1
  AND status='pending_upload' AND NOT EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets assigned WHERE assigned.asset_id=p_asset_id)
  RETURNING * INTO m;
 IF NOT FOUND THEN RAISE EXCEPTION 'media_upload_not_pending' USING ERRCODE='22023'; END IF;
 -- Existing signup projection plus INTERNAL cutover version for dedicated parser guard.
 -- Generic APIs keep their old projection; no source/request hashes, tickets or secrets.
 RETURN jsonb_build_object('id',m.id,'user_id',m.user_id,'kind',m.kind,'bucket_id',m.bucket_id,
  'object_path',m.object_path,'mime_type',m.mime_type,'declared_size_bytes',m.declared_size_bytes,
  'actual_size_bytes',m.actual_size_bytes,'status',m.status,'failure_stage',m.failure_stage,
  'failure_code',m.failure_code,'context_text',m.context_text,'signup_origin',m.signup_origin,
  'signup_disposition_version',m.signup_disposition_version,
  'retention_until',m.retention_until,'uploaded_at',m.uploaded_at,'processed_at',m.processed_at,
  'deleted_at',m.deleted_at,'processing_result',m.processing_result,'created_at',m.created_at,
  'updated_at',m.updated_at);
END; $$;
REVOKE ALL ON FUNCTION public.mark_mobile_signup_body_photo_uploaded(uuid,uuid,bigint,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mark_mobile_signup_body_photo_uploaded(uuid,uuid,bigint,text,timestamptz) TO service_role;

-- Internal signup lookup preserves existing records and returns coherent scope flags.
-- Dedicated signup repository only. Do not filter legacy/generic/assigned records
-- into NULL: their request hashes must continue to block recreation or retagging.
-- Legacy rows without a disposition version remain UNKNOWN.
CREATE OR REPLACE FUNCTION public.get_mobile_signup_body_photo_asset(
 p_user_id uuid,p_asset_id uuid DEFAULT NULL,p_request_hash text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 -- Exactly ONE criterion. Empty/malformed request hashes cannot be an absent lookup.
 IF p_user_id IS NULL OR ((p_asset_id IS NULL)=(p_request_hash IS NULL))
  OR (p_request_hash IS NOT NULL AND p_request_hash !~ '^[0-9a-f]{64}$') THEN
  RAISE EXCEPTION 'invalid_signup_body_photo_asset_lookup' USING ERRCODE='22023';
 END IF;
 -- One SELECT correlates catalogue, current profile and historical assignment.
 -- Existing PK(id) and UNIQUE(user_id,source_request_hash) guarantee one row;
 -- do not LIMIT 1 or filter marker/version/status/assignment/active account.
 SELECT jsonb_build_object(
  'id',m.id,'user_id',m.user_id,'kind',m.kind,'bucket_id',m.bucket_id,
  'object_path',m.object_path,'mime_type',m.mime_type,'declared_size_bytes',m.declared_size_bytes,
  'actual_size_bytes',m.actual_size_bytes,'status',m.status,'failure_stage',m.failure_stage,
  'failure_code',m.failure_code,'context_text',m.context_text,'signup_origin',m.signup_origin,
  'signup_disposition_version',m.signup_disposition_version,
  'signup_disposition_assigned',membership.assigned,
  'signup_upload_open',COALESCE(
   u.status='active' AND p.onboarding_completed IS FALSE AND p.onboarding_completed_at IS NULL
   AND m.kind='body_checkin_photo' AND m.signup_origin IS TRUE AND m.signup_disposition_version=1
   AND NOT membership.assigned,false),
  'retention_until',m.retention_until,'uploaded_at',m.uploaded_at,'processed_at',m.processed_at,
  'deleted_at',m.deleted_at,'processing_result',m.processing_result,'created_at',m.created_at,
  'updated_at',m.updated_at
 ) INTO result
 FROM public.media_assets m
 LEFT JOIN public.users u ON u.id=m.user_id
 LEFT JOIN public.user_profiles p ON p.user_id=m.user_id
 CROSS JOIN LATERAL (
  SELECT EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets assigned WHERE assigned.asset_id=m.id) AS assigned
 ) membership
 WHERE m.user_id=p_user_id
  AND ((p_asset_id IS NOT NULL AND m.id=p_asset_id)
   OR (p_request_hash IS NOT NULL AND m.source_request_hash=p_request_hash));
 IF NOT FOUND THEN RETURN NULL; END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.get_mobile_signup_body_photo_asset(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_signup_body_photo_asset(uuid,uuid,text) TO service_role;

-- Dedicated open catalogue filters historical assignments before the existing page limit.
-- JSON rows preserve exact existing PHOTO_COLUMNS (nine named fields).
-- No generic catalogue/grants/counter/status-machine changes or DDL outside Task4.
CREATE OR REPLACE FUNCTION public.list_mobile_open_signup_body_photo_assets(
 p_user_id uuid,p_include_deleted boolean,p_limit integer DEFAULT 1000
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE account_status text; profile_present boolean; completed boolean; completed_at timestamptz; result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_include_deleted IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN
  RAISE EXCEPTION 'invalid_signup_body_photo_catalogue_request' USING ERRCODE='22023';
 END IF;
 -- Profile/current generation and data share one statement snapshot. This catches
 -- a completion committed after B2 repair and before this RPC's read.
 WITH account AS MATERIALIZED (
  SELECT u.id,u.status,p.user_id IS NOT NULL AS present,
   p.onboarding_completed AS completed,p.onboarding_completed_at AS completed_at
  FROM public.users u LEFT JOIN public.user_profiles p ON p.user_id=u.id
  WHERE u.id=p_user_id
 ), selected AS MATERIALIZED (
  SELECT m.id,m.bucket_id,m.object_path,m.status,m.failure_stage,m.context_text,
   m.created_at,m.uploaded_at,m.processing_result,m.deleted_at
  FROM public.media_assets m JOIN account a ON a.id=m.user_id
  WHERE a.status='active' AND a.present AND a.completed IS FALSE AND a.completed_at IS NULL
   AND m.kind='body_checkin_photo' AND m.signup_origin IS TRUE AND m.signup_disposition_version=1
   AND NOT EXISTS(SELECT 1 FROM private.signup_body_photo_disposition_assets assigned WHERE assigned.asset_id=m.id)
   AND (p_include_deleted OR m.status<>'deleted')
  -- Filter unassigned/version before order/LIMIT; sealed history cannot occupy the page.
  -- Existing primary sort: open newestcreated; every deleted_at DESC NULLS FIRST.
  -- UUID DESC only stabilizes equal primary sort keys.
  ORDER BY CASE WHEN NOT p_include_deleted THEN m.created_at END DESC,
   CASE WHEN p_include_deleted THEN m.deleted_at END DESC NULLS FIRST,m.id DESC
  LIMIT p_limit
 )
 SELECT a.status,a.present,a.completed,a.completed_at,
  COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',s.id,'bucket_id',s.bucket_id,'object_path',s.object_path,'status',s.status,
   'failure_stage',s.failure_stage,'context_text',s.context_text,'created_at',s.created_at,
   'uploaded_at',s.uploaded_at,'processing_result',s.processing_result
  ) ORDER BY CASE WHEN NOT p_include_deleted THEN s.created_at END DESC,
   CASE WHEN p_include_deleted THEN s.deleted_at END DESC NULLS FIRST,s.id DESC)
   FROM selected s),'[]'::jsonb)
 INTO account_status,profile_present,completed,completed_at,result
 FROM account a;
 IF NOT FOUND OR account_status IS DISTINCT FROM 'active' OR profile_present IS NOT TRUE THEN
  RAISE EXCEPTION 'body_photos_unavailable' USING ERRCODE='22023';
 END IF;
 IF completed IS NOT FALSE OR completed_at IS NOT NULL THEN
  RAISE EXCEPTION 'onboarding_already_completed' USING ERRCODE='22023';
 END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.list_mobile_open_signup_body_photo_assets(uuid,boolean,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.list_mobile_open_signup_body_photo_assets(uuid,boolean,integer) TO service_role;

COMMIT;
