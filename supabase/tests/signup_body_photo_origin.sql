-- B4b trusted origin. Run with the existing SQL regression runner after migrations.
-- Synthetic transaction only; no Storage API, media worker or messages.
BEGIN;
INSERT INTO public.users(id,wpp,email,name) VALUES
 ('00000000-0000-0000-0000-000000000710','5511990000710','signup-origin-test@example.invalid','Synthetic signup origin test');
-- B4b origin candidate: local transaction-only regression, never executed in preparation.
RESET ROLE;
DO $test$
DECLARE
  v_role text;
  v_privilege text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_attribute a
    JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE a.attrelid = 'public.media_assets'::regclass
      AND a.attname = 'signup_origin'
      AND NOT a.attisdropped
      AND NOT a.attnotnull
      AND format_type(a.atttypid, a.atttypmod) = 'boolean'
      AND pg_get_expr(d.adbin, d.adrelid) = 'false'
  ) THEN
    RAISE EXCEPTION 'signup_origin must be nullable boolean with default false';
  END IF;

  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOREACH v_privilege IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE'] LOOP
      IF has_column_privilege(v_role, 'public.media_assets', 'signup_origin', v_privilege) THEN
        RAISE EXCEPTION 'client role has a forbidden signup_origin column privilege';
      END IF;
    END LOOP;
    IF has_function_privilege(v_role, 'private.enforce_signup_body_photo_origin()', 'EXECUTE') THEN
      RAISE EXCEPTION 'client role can execute private origin guard';
    END IF;
  END LOOP;

  IF NOT has_column_privilege('authenticated', 'public.media_assets', 'id', 'SELECT')
    OR NOT has_column_privilege('authenticated', 'public.media_assets', 'user_id', 'SELECT')
    OR has_column_privilege('authenticated', 'public.media_assets', 'object_path', 'SELECT')
    OR has_column_privilege('authenticated', 'public.media_assets', 'processing_result', 'SELECT') THEN
    RAISE EXCEPTION 'existing patient catalog exposure changed';
  END IF;

  FOREACH v_privilege IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE'] LOOP
    IF NOT has_column_privilege('service_role', 'public.media_assets', 'signup_origin', v_privilege) THEN
      RAISE EXCEPTION 'trusted service lost required origin column privilege';
    END IF;
  END LOOP;

  IF NOT has_function_privilege('service_role', 'private.enforce_signup_body_photo_origin()', 'EXECUTE') THEN
    RAISE EXCEPTION 'trusted service cannot execute origin guard';
  END IF;
END;
$test$;

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Uses only the synthetic account already created by this same rollback-only file.
INSERT INTO public.media_assets (
  id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
  context_text, source_request_hash, retention_until
) VALUES (
  '00000000-0000-0000-0000-00000000c901',
  '00000000-0000-0000-0000-000000000710',
  'body_checkin_photo', 'body-checkin-photos',
  '00000000-0000-0000-0000-000000000710/00000000-0000-0000-0000-00000000c901.jpg',
  'image/jpeg', 100, 'Foto de frente.', repeat('1',64), clock_timestamp()+interval '2 days'
);
INSERT INTO public.media_assets (
  id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
  context_text, signup_origin, source_request_hash, retention_until
) VALUES
(
  '00000000-0000-0000-0000-00000000c902',
  '00000000-0000-0000-0000-000000000710',
  'body_checkin_photo', 'body-checkin-photos',
  '00000000-0000-0000-0000-000000000710/00000000-0000-0000-0000-00000000c902.jpg',
  'image/jpeg', 100, 'Foto de frente.', NULL, repeat('2',64), clock_timestamp()+interval '2 days'
),
(
  '00000000-0000-0000-0000-00000000c903',
  '00000000-0000-0000-0000-000000000710',
  'body_checkin_photo', 'body-checkin-photos',
  '00000000-0000-0000-0000-000000000710/00000000-0000-0000-0000-00000000c903.jpg',
  'image/jpeg', 100, 'Foto de frente.', TRUE, repeat('3',64), clock_timestamp()+interval '2 days'
);

DO $test$
DECLARE
  v_id uuid;
  v_rejected integer := 0;
  v_count integer;
BEGIN
  IF (SELECT signup_origin FROM public.media_assets
      WHERE id='00000000-0000-0000-0000-00000000c901') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'an INSERT without private option must remain UNKNOWN false';
  END IF;
  IF (SELECT signup_origin FROM public.media_assets
      WHERE id='00000000-0000-0000-0000-00000000c902') IS NOT NULL THEN
    RAISE EXCEPTION 'explicit historical NULL must remain UNKNOWN NULL';
  END IF;

  FOREACH v_id IN ARRAY ARRAY[
    '00000000-0000-0000-0000-00000000c901'::uuid,
    '00000000-0000-0000-0000-00000000c902'::uuid
  ] LOOP
    BEGIN
      UPDATE public.media_assets SET signup_origin=true WHERE id=v_id;
    EXCEPTION WHEN SQLSTATE '22023' THEN
      v_rejected := v_rejected+1;
    END;
  END LOOP;
  BEGIN
    UPDATE public.media_assets SET signup_origin=false
      WHERE id='00000000-0000-0000-0000-00000000c903';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    v_rejected := v_rejected+1;
  END;
  BEGIN
    UPDATE public.media_assets SET signup_origin=NULL
      WHERE id='00000000-0000-0000-0000-00000000c903';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    v_rejected := v_rejected+1;
  END;
  IF v_rejected <> 4 THEN
    RAISE EXCEPTION 'origin guard did not reject all four retag transitions';
  END IF;

  -- Ordinary legal status updates still work and keep origin unchanged.
  UPDATE public.media_assets
    SET status='failed', failure_stage='upload', failure_code='synthetic-origin-test'
    WHERE id='00000000-0000-0000-0000-00000000c903';
  IF NOT EXISTS (
    SELECT 1 FROM public.media_assets
    WHERE id='00000000-0000-0000-0000-00000000c903'
      AND signup_origin IS TRUE AND status='failed' AND failure_stage='upload'
  ) THEN
    RAISE EXCEPTION 'origin guard broke normal media transition or changed origin';
  END IF;

  -- Query filtering, not client-side truthiness: false and NULL are excluded.
  SELECT count(*) INTO v_count FROM public.media_assets
  WHERE id IN (
    '00000000-0000-0000-0000-00000000c901',
    '00000000-0000-0000-0000-00000000c902',
    '00000000-0000-0000-0000-00000000c903'
  ) AND signup_origin=true;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'trusted-origin SQL scope included UNKNOWN';
  END IF;

  UPDATE public.media_assets SET processing_result=NULL
  WHERE id IN (
    '00000000-0000-0000-0000-00000000c901',
    '00000000-0000-0000-0000-00000000c902'
  ) AND signup_origin=true;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'trusted-origin UPDATE affected UNKNOWN rows';
  END IF;
END;
$test$;

ROLLBACK;
