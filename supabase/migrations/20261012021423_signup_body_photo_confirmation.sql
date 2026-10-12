-- B4b D2: explicit confirmation, durable private proof, generation cursor.
-- No legacy function, media worker, consent RPC or target formula is replaced.
BEGIN;

CREATE TABLE private.signup_body_photo_receipts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  onboarding_completed_at timestamptz NOT NULL,
  receipt_version smallint NOT NULL DEFAULT 1 CHECK (receipt_version = 1),
  decision text,
  method text,
  front_asset_id uuid,
  side_asset_id uuid,
  back_asset_id uuid,
  fingerprint text,
  confirmed_body_fat_percent numeric(4,2),
  decided_at timestamptz,
  invalidated_at timestamptz,
  invalidation_reason text,
  PRIMARY KEY (user_id, onboarding_completed_at),
  CONSTRAINT signup_body_photo_receipt_shape CHECK ((CASE
    WHEN decision = 'accepted' THEN
      method = 'arithmetic_mean_v1'
      AND front_asset_id IS NOT NULL AND side_asset_id IS NOT NULL AND back_asset_id IS NOT NULL
      AND front_asset_id <> side_asset_id AND front_asset_id <> back_asset_id
      AND side_asset_id <> back_asset_id
      AND fingerprint IS NOT NULL AND fingerprint ~ '^[0-9a-f]{64}$'
      AND confirmed_body_fat_percent IS NOT NULL AND confirmed_body_fat_percent BETWEEN 3 AND 60
      AND decided_at IS NOT NULL
      AND ((invalidated_at IS NULL AND invalidation_reason IS NULL)
        OR (invalidated_at IS NOT NULL AND invalidation_reason IN ('bf_write', 'profile_state', 'reset')))
    WHEN decision = 'declined' THEN
      decided_at IS NOT NULL AND method IS NULL AND front_asset_id IS NULL
      AND side_asset_id IS NULL AND back_asset_id IS NULL AND fingerprint IS NULL
      AND confirmed_body_fat_percent IS NULL AND invalidated_at IS NULL AND invalidation_reason IS NULL
    WHEN decision IS NULL THEN
      method IS NULL AND front_asset_id IS NULL AND side_asset_id IS NULL AND back_asset_id IS NULL
      AND fingerprint IS NULL AND confirmed_body_fat_percent IS NULL AND decided_at IS NULL
      AND invalidated_at IS NULL AND invalidation_reason IS NULL
    ELSE false END) IS TRUE)
);
ALTER TABLE private.signup_body_photo_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.signup_body_photo_receipts FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.preserve_signup_photo_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
BEGIN
  IF (to_jsonb(NEW) - 'invalidated_at' - 'invalidation_reason')
      IS DISTINCT FROM (to_jsonb(OLD) - 'invalidated_at' - 'invalidation_reason')
    OR (OLD.invalidated_at IS NOT NULL AND
      (NEW.invalidated_at IS DISTINCT FROM OLD.invalidated_at
        OR NEW.invalidation_reason IS DISTINCT FROM OLD.invalidation_reason)) THEN
    RAISE EXCEPTION 'signup_body_photo_receipt_immutable' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER preserve_signup_photo_receipt
  BEFORE UPDATE ON private.signup_body_photo_receipts
  FOR EACH ROW EXECUTE FUNCTION private.preserve_signup_photo_receipt();
REVOKE ALL ON FUNCTION private.preserve_signup_photo_receipt() FROM PUBLIC, anon, authenticated, service_role;

-- False is a separate branch: absent/decline/OFF history never read media or consent.
-- All correlated fields in either branch come from one SELECT snapshot.
CREATE FUNCTION private.build_signup_body_photo_snapshot(p_user_id uuid, p_include_open_photos boolean)
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
      WHERE m.kind = 'body_checkin_photo' AND m.signup_origin IS TRUE
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

CREATE FUNCTION public.get_mobile_signup_body_photo_snapshot(p_user_id uuid, p_include_open_photos boolean)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $$
BEGIN
  PERFORM private.assert_trusted_backend();
  RETURN private.build_signup_body_photo_snapshot(p_user_id, p_include_open_photos);
END;
$$;
REVOKE ALL ON FUNCTION private.build_signup_body_photo_snapshot(uuid,boolean)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_mobile_signup_body_photo_snapshot(uuid,boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_signup_body_photo_snapshot(uuid,boolean) TO service_role;

CREATE FUNCTION private.assert_signup_body_photo_age(p_birth_date date, p_timezone text, p_now timestamptz)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
DECLARE v_today date; v_years integer;
BEGIN
  IF p_birth_date IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'invalid_body_photo_confirmation' USING ERRCODE = '22023';
  END IF;
  v_today := (p_now AT TIME ZONE COALESCE((
    SELECT name FROM pg_catalog.pg_timezone_names WHERE lower(name) = lower(p_timezone) LIMIT 1
  ), 'America/Sao_Paulo'))::date;
  v_years := extract(year FROM v_today)::integer - extract(year FROM p_birth_date)::integer;
  IF extract(month FROM v_today) * 100 + extract(day FROM v_today)
      < extract(month FROM p_birth_date) * 100 + extract(day FROM p_birth_date) THEN
    v_years := v_years - 1;
  END IF;
  IF v_years < 18 THEN
    RAISE EXCEPTION 'body_photo_age_not_allowed' USING ERRCODE = '22023';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION private.assert_signup_body_photo_age(date,text,timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.complete_mobile_onboarding_with_body_photo_confirmation(
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
        AND m.id IN (v_front,v_side,v_back) AND m.kind = 'body_checkin_photo' AND m.signup_origin IS TRUE
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
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_mobile_onboarding_with_body_photo_confirmation(uuid,jsonb,jsonb,boolean,timestamptz,bigint)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_mobile_onboarding_with_body_photo_confirmation(uuid,jsonb,jsonb,boolean,timestamptz,bigint)
  TO service_role;

-- Only generations attested by this feature acquire reset normalization.
-- Preserve the legacy reset behavior for profiles without an official receipt.
CREATE FUNCTION private.normalize_signup_receipted_reset()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM private.signup_body_photo_receipts r
    WHERE r.user_id = OLD.user_id AND r.onboarding_completed_at = OLD.onboarding_completed_at) THEN
    NEW.onboarding_completed_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.normalize_signup_receipted_reset()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER normalize_signup_receipted_reset
  BEFORE UPDATE OF onboarding_completed ON public.user_profiles
  FOR EACH ROW WHEN (OLD.onboarding_completed IS TRUE AND NEW.onboarding_completed IS FALSE
    AND OLD.onboarding_completed_at IS NOT NULL)
  EXECUTE FUNCTION private.normalize_signup_receipted_reset();

CREATE FUNCTION private.invalidate_signup_photo_confirmation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE v_reason text;
BEGIN
  v_reason := CASE WHEN OLD.onboarding_completed IS TRUE AND NEW.onboarding_completed IS FALSE
    THEN 'reset' ELSE TG_ARGV[0] END;
  UPDATE private.signup_body_photo_receipts
    SET invalidated_at = clock_timestamp(), invalidation_reason = v_reason
    WHERE user_id = OLD.user_id AND decision = 'accepted' AND invalidated_at IS NULL;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.invalidate_signup_photo_confirmation()
  FROM PUBLIC, anon, authenticated, service_role;
-- UPDATE OF is intentional: writing the same manual percent invalidates its origin.
CREATE TRIGGER invalidate_signup_photo_bf_write
  AFTER UPDATE OF body_fat_percent ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION private.invalidate_signup_photo_confirmation('bf_write');
CREATE TRIGGER invalidate_signup_photo_profile_state
  AFTER UPDATE OF body_fat_measured_at, onboarding_completed, onboarding_completed_at
  ON public.user_profiles FOR EACH ROW
  WHEN (OLD.body_fat_measured_at IS DISTINCT FROM NEW.body_fat_measured_at
    OR OLD.onboarding_completed IS DISTINCT FROM NEW.onboarding_completed
    OR OLD.onboarding_completed_at IS DISTINCT FROM NEW.onboarding_completed_at)
  EXECUTE FUNCTION private.invalidate_signup_photo_confirmation('profile_state');

-- Adapter, API integration and finalization still require their own gates.
COMMIT;
