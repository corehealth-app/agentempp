-- B8b: actual front/side/back numbers from the same materialized snapshot.
-- Additive v1; canonical mean, source fingerprint and closed/OFF branch unchanged.
-- No provider/worker/formula changes. Existing function owner/ACL preserved.

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
          ORDER BY CASE s.pose WHEN 'front' THEN 0 WHEN 'side' THEN 1 ELSE 2 END) AS fingerprint_rows,
        jsonb_agg(jsonb_build_object('pose', s.pose, 'body_fat_percent', s.reading)
          ORDER BY CASE s.pose WHEN 'front' THEN 0 WHEN 'side' THEN 1 ELSE 2 END) AS readings
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
        'feminino', CASE WHEN e.usable THEN jsonb_build_object('usable', true, 'body_fat_percent', e.mean) ELSE jsonb_build_object('usable', false, 'reason', 'out_of_range') END), 'readings', e.readings) END,
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
