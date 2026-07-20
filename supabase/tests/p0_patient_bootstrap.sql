BEGIN;

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
  (
    '00000000-0000-0000-0000-000000000401',
    'authenticated',
    'authenticated',
    'p0-confirmed@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
  ),
  (
    '00000000-0000-0000-0000-000000000402',
    'authenticated',
    'authenticated',
    'p0-unconfirmed@example.com',
    '',
    NULL,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
  ),
  (
    '00000000-0000-0000-0000-000000000403',
    'authenticated',
    'authenticated',
    'p0-admin@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
  ),
  (
    '00000000-0000-0000-0000-000000000404',
    'authenticated',
    'authenticated',
    'p0-legacy@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
  );

INSERT INTO public.admin_users (id, email, role)
VALUES (
  '00000000-0000-0000-0000-000000000403',
  'p0-admin@example.com',
  'master_admin'
);

INSERT INTO public.users (id, wpp, email)
VALUES (
  '00000000-0000-0000-0000-000000000405',
  NULL,
  'p0-legacy@example.com'
);

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000401","role":"authenticated","email":"p0-confirmed@example.com"}',
  true
);
SELECT public.bootstrap_patient_profile();
SELECT public.bootstrap_patient_profile();

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000402","role":"authenticated","email":"p0-unconfirmed@example.com"}',
  true
);
DO $test$
DECLARE
  v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.bootstrap_patient_profile();
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_denied := true;
  END;

  IF NOT v_denied THEN
    RAISE EXCEPTION 'unconfirmed email created a patient profile';
  END IF;
END;
$test$;

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000403","role":"authenticated","email":"p0-admin@example.com"}',
  true
);
DO $test$
DECLARE
  v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.bootstrap_patient_profile();
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_denied := true;
  END;

  IF NOT v_denied THEN
    RAISE EXCEPTION 'admin identity also created a patient profile';
  END IF;
END;
$test$;

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000404","role":"authenticated","email":"p0-legacy@example.com"}',
  true
);
DO $test$
DECLARE
  v_conflict boolean := false;
BEGIN
  BEGIN
    PERFORM public.bootstrap_patient_profile();
  EXCEPTION
    WHEN unique_violation THEN
      v_conflict := true;
  END;

  IF NOT v_conflict THEN
    RAISE EXCEPTION 'legacy email was linked automatically';
  END IF;
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
  v_patient_id uuid;
  v_count integer;
  v_separation_enforced boolean := false;
BEGIN
  SELECT id
  INTO v_patient_id
  FROM public.users
  WHERE auth_user_id = '00000000-0000-0000-0000-000000000401';

  IF v_patient_id IS NULL THEN
    RAISE EXCEPTION 'confirmed patient profile was not created';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = v_patient_id
      AND wpp IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'app-first patient received a WhatsApp identity';
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM public.users
  WHERE auth_user_id = '00000000-0000-0000-0000-000000000401';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'patient bootstrap is not idempotent';
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM public.user_profiles
  WHERE user_id = v_patient_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'patient domain profile was not created exactly once';
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM public.user_progress
  WHERE user_id = v_patient_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'patient progress baseline was not created exactly once';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000405'
      AND auth_user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'legacy domain user received an automatic auth link';
  END IF;

  BEGIN
    INSERT INTO public.admin_users (id, email, role)
    VALUES (
      '00000000-0000-0000-0000-000000000401',
      'p0-confirmed@example.com',
      'support'
    );
  EXCEPTION
    WHEN check_violation THEN
      v_separation_enforced := true;
  END;

  IF NOT v_separation_enforced THEN
    RAISE EXCEPTION 'patient identity was also accepted as an admin account';
  END IF;
END;
$test$;

ROLLBACK;
