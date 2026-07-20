BEGIN;

DO $test$
DECLARE
  v_bucket_count integer;
  v_public_count integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE public)
  INTO v_bucket_count, v_public_count
  FROM storage.buckets
  WHERE id IN (
    'meal-photos',
    'body-checkin-photos',
    'gym-photos',
    'audio-notes',
    'content-covers'
  );

  IF v_bucket_count <> 5 OR v_public_count <> 0 THEN
    RAISE EXCEPTION 'expected five private BodyFlow buckets, found % (% public)',
      v_bucket_count,
      v_public_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM storage.buckets
    WHERE id IN ('meal-photos', 'body-checkin-photos', 'gym-photos')
      AND file_size_limit <> 15728640
  ) THEN
    RAISE EXCEPTION 'patient image bucket limits are incorrect';
  END IF;

  IF EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id = 'audio-notes' AND file_size_limit <> 26214400
  ) OR EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id = 'content-covers' AND file_size_limit <> 10485760
  ) THEN
    RAISE EXCEPTION 'audio or content-cover bucket limits are incorrect';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM storage.buckets
    WHERE id IN ('meal-photos', 'body-checkin-photos', 'gym-photos', 'content-covers')
      AND 'image/svg+xml' = ANY(allowed_mime_types)
  ) THEN
    RAISE EXCEPTION 'SVG must not be accepted by BodyFlow image buckets';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'media_assets'
      AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'media_assets RLS is not enabled';
  END IF;

  IF has_table_privilege('anon', 'public.media_assets', 'SELECT')
    OR has_table_privilege('anon', 'public.media_assets', 'INSERT')
    OR has_table_privilege('authenticated', 'public.media_assets', 'INSERT')
    OR has_table_privilege('authenticated', 'public.media_assets', 'UPDATE')
    OR has_table_privilege('authenticated', 'public.media_assets', 'DELETE') THEN
    RAISE EXCEPTION 'media_assets exposes a forbidden client grant';
  END IF;

  IF NOT has_column_privilege('authenticated', 'public.media_assets', 'id', 'SELECT')
    OR NOT has_column_privilege('authenticated', 'public.media_assets', 'user_id', 'SELECT')
    OR has_column_privilege('authenticated', 'public.media_assets', 'object_path', 'SELECT')
    OR has_column_privilege('authenticated', 'public.media_assets', 'processing_result', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated media catalog columns are over- or under-exposed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'media_assets_user_id_fkey'
      AND conrelid = 'public.media_assets'::regclass
      AND confdeltype = 'r'
  ) THEN
    RAISE EXCEPTION 'media catalog does not block user purge before physical cleanup';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.claim_media_asset_processing(uuid,uuid,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.complete_media_asset_processing(uuid,uuid,text,jsonb)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.fail_media_asset_processing(uuid,uuid,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'authenticated can execute internal media processing RPCs';
  END IF;
END;
$test$;

INSERT INTO auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
) VALUES
  ('00000000-0000-0000-0000-000000000701', 'authenticated', 'authenticated', 'media-a@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000702', 'authenticated', 'authenticated', 'media-b@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false);

INSERT INTO public.users (id, auth_user_id, email, wpp, name)
VALUES
  ('00000000-0000-0000-0000-000000000710', '00000000-0000-0000-0000-000000000701', 'media-a@example.com', NULL, 'Media Patient A'),
  ('00000000-0000-0000-0000-000000000711', '00000000-0000-0000-0000-000000000702', 'media-b@example.com', NULL, 'Media Patient B');

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

INSERT INTO public.media_assets (
  id,
  user_id,
  kind,
  bucket_id,
  object_path,
  mime_type,
  declared_size_bytes,
  status,
  source_request_hash,
  retention_until
) VALUES
  (
    '00000000-0000-0000-0000-000000000720',
    '00000000-0000-0000-0000-000000000710',
    'meal_photo',
    'meal-photos',
    '00000000-0000-0000-0000-000000000710/00000000-0000-0000-0000-000000000720.jpg',
    'image/jpeg',
    1024,
    'pending_upload',
    repeat('a', 64),
    now() + interval '30 days'
  ),
  (
    '00000000-0000-0000-0000-000000000721',
    '00000000-0000-0000-0000-000000000711',
    'body_checkin_photo',
    'body-checkin-photos',
    '00000000-0000-0000-0000-000000000711/00000000-0000-0000-0000-000000000721.jpg',
    'image/jpeg',
    1024,
    'pending_upload',
    repeat('b', 64),
    now() + interval '730 days'
  );

DO $test$
DECLARE
  v_request_id text := repeat('1', 64);
  v_other_request_id text := repeat('2', 64);
  v_claim jsonb;
BEGIN
  UPDATE public.media_assets
  SET status = 'uploaded',
      actual_size_bytes = declared_size_bytes,
      uploaded_at = clock_timestamp()
  WHERE id = '00000000-0000-0000-0000-000000000720';

  v_claim := public.claim_media_asset_processing(
    '00000000-0000-0000-0000-000000000720',
    '00000000-0000-0000-0000-000000000710',
    v_request_id
  );
  IF v_claim ->> 'status' <> 'processing'
    OR v_claim ->> 'processing_request_id' <> v_request_id THEN
    RAISE EXCEPTION 'media processing was not claimed: %', v_claim;
  END IF;

  IF public.claim_media_asset_processing(
    '00000000-0000-0000-0000-000000000720',
    '00000000-0000-0000-0000-000000000710',
    v_other_request_id
  ) IS NOT NULL THEN
    RAISE EXCEPTION 'a second request stole an active media claim';
  END IF;

  IF NOT public.fail_media_asset_processing(
    '00000000-0000-0000-0000-000000000720',
    '00000000-0000-0000-0000-000000000710',
    v_request_id,
    'provider_error'
  ) THEN
    RAISE EXCEPTION 'media processing failure was not recorded';
  END IF;

  v_claim := public.claim_media_asset_processing(
    '00000000-0000-0000-0000-000000000720',
    '00000000-0000-0000-0000-000000000710',
    v_request_id
  );
  IF v_claim ->> 'status' <> 'processing' THEN
    RAISE EXCEPTION 'same media request could not resume after transient failure';
  END IF;

  IF NOT public.fail_media_asset_processing(
    '00000000-0000-0000-0000-000000000720',
    '00000000-0000-0000-0000-000000000710',
    v_request_id,
    'provider_error'
  ) THEN
    RAISE EXCEPTION 'resumed media failure was not recorded';
  END IF;

  v_claim := public.claim_media_asset_processing(
    '00000000-0000-0000-0000-000000000720',
    '00000000-0000-0000-0000-000000000710',
    v_other_request_id
  );
  IF v_claim ->> 'status' <> 'processing'
    OR v_claim ->> 'processing_request_id' <> v_other_request_id THEN
    RAISE EXCEPTION 'explicit retry could not claim failed media: %', v_claim;
  END IF;

  IF NOT public.complete_media_asset_processing(
    '00000000-0000-0000-0000-000000000720',
    '00000000-0000-0000-0000-000000000710',
    v_other_request_id,
    '{"type":"meal","items":[]}'::jsonb
  ) THEN
    RAISE EXCEPTION 'media processing completion was not recorded';
  END IF;
END;
$test$;

RESET ROLE;
SET LOCAL ROLE anon;
DO $test$
DECLARE
  v_denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  BEGIN
    PERFORM count(*) FROM public.media_assets;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'anon read media_assets'; END IF;
END;
$test$;

RESET ROLE;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_own integer;
  v_cross integer;
  v_insert_denied boolean := false;
  v_update_denied boolean := false;
  v_delete_denied boolean := false;
  v_storage_insert_denied boolean := false;
  v_internal_column_denied boolean := false;
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000701","role":"authenticated"}',
    true
  );

  SELECT count(*) INTO v_own
  FROM public.media_assets
  WHERE user_id = '00000000-0000-0000-0000-000000000710';
  SELECT count(*) INTO v_cross
  FROM public.media_assets
  WHERE user_id = '00000000-0000-0000-0000-000000000711';

  IF v_own <> 1 OR v_cross <> 0 THEN
    RAISE EXCEPTION 'patient media ownership failed: own %, cross %', v_own, v_cross;
  END IF;

  BEGIN
    PERFORM object_path
    FROM public.media_assets
    WHERE id = '00000000-0000-0000-0000-000000000721';
  EXCEPTION WHEN insufficient_privilege THEN
    v_internal_column_denied := true;
  END;

  BEGIN
    INSERT INTO public.media_assets (
      user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes, source_request_hash
    ) VALUES (
      '00000000-0000-0000-0000-000000000710',
      'meal_photo',
      'meal-photos',
      'forbidden.jpg',
      'image/jpeg',
      100,
      repeat('c', 64)
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_insert_denied := true;
  END;

  BEGIN
    UPDATE public.media_assets
    SET status = 'processed'
    WHERE id = '00000000-0000-0000-0000-000000000721';
  EXCEPTION WHEN insufficient_privilege THEN
    v_update_denied := true;
  END;

  BEGIN
    DELETE FROM public.media_assets
    WHERE id = '00000000-0000-0000-0000-000000000720';
  EXCEPTION WHEN insufficient_privilege THEN
    v_delete_denied := true;
  END;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name)
    VALUES (
      'meal-photos',
      '00000000-0000-0000-0000-000000000710/direct-client-upload.jpg'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_storage_insert_denied := true;
  END;

  IF NOT v_insert_denied OR NOT v_update_denied OR NOT v_delete_denied
    OR NOT v_internal_column_denied THEN
    RAISE EXCEPTION 'authenticated patient mutated media_assets';
  END IF;
  IF NOT v_storage_insert_denied THEN
    RAISE EXCEPTION 'authenticated patient bypassed signed upload BFF';
  END IF;
END;
$test$;

RESET ROLE;
SET LOCAL ROLE service_role;
DO $test$
DECLARE
  v_invalid_path boolean := false;
  v_invalid_mapping boolean := false;
  v_oversized boolean := false;
  v_invalid_transition boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  BEGIN
    INSERT INTO public.media_assets (
      id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes, source_request_hash
    ) VALUES (
      '00000000-0000-0000-0000-000000000722',
      '00000000-0000-0000-0000-000000000710',
      'meal_photo',
      'meal-photos',
      'another-user/guessed.jpg',
      'image/jpeg',
      100,
      repeat('d', 64)
    );
  EXCEPTION WHEN check_violation THEN
    v_invalid_path := true;
  END;

  BEGIN
    INSERT INTO public.media_assets (
      id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes, source_request_hash
    ) VALUES (
      '00000000-0000-0000-0000-000000000723',
      '00000000-0000-0000-0000-000000000710',
      'audio_note',
      'meal-photos',
      '00000000-0000-0000-0000-000000000710/00000000-0000-0000-0000-000000000723.mp3',
      'audio/mpeg',
      100,
      repeat('e', 64)
    );
  EXCEPTION WHEN check_violation THEN
    v_invalid_mapping := true;
  END;

  BEGIN
    INSERT INTO public.media_assets (
      id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes, source_request_hash
    ) VALUES (
      '00000000-0000-0000-0000-000000000724',
      '00000000-0000-0000-0000-000000000710',
      'meal_photo',
      'meal-photos',
      '00000000-0000-0000-0000-000000000710/00000000-0000-0000-0000-000000000724.jpg',
      'image/jpeg',
      15728641,
      repeat('f', 64)
    );
  EXCEPTION WHEN check_violation THEN
    v_oversized := true;
  END;

  BEGIN
    UPDATE public.media_assets
    SET status = 'processed'
    WHERE id = '00000000-0000-0000-0000-000000000721';
  EXCEPTION WHEN check_violation THEN
    v_invalid_transition := true;
  END;

  IF NOT v_invalid_path OR NOT v_invalid_mapping OR NOT v_oversized OR NOT v_invalid_transition THEN
    RAISE EXCEPTION 'media constraints failed: path %, mapping %, size %, transition %',
      v_invalid_path,
      v_invalid_mapping,
      v_oversized,
      v_invalid_transition;
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_status text;
BEGIN
  UPDATE public.media_assets
  SET status = 'failed',
      failure_stage = 'upload',
      failure_code = 'metadata_mismatch'
  WHERE id = '00000000-0000-0000-0000-000000000721';

  UPDATE public.media_assets
  SET status = 'deleted',
      failure_stage = NULL,
      failure_code = NULL,
      deleted_at = clock_timestamp()
  WHERE id = '00000000-0000-0000-0000-000000000721';

  SELECT status INTO v_status
  FROM public.media_assets
  WHERE id = '00000000-0000-0000-0000-000000000721';

  IF v_status <> 'deleted' THEN
    RAISE EXCEPTION 'failed upload could not be deleted';
  END IF;
END;
$test$;

ROLLBACK;
