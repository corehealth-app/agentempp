BEGIN;

-- Synthetic Auth identities. All rows are rolled back at the end of the test.
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
  ('00000000-0000-0000-0000-000000000501', 'authenticated', 'authenticated', 'p0-matrix-a@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000502', 'authenticated', 'authenticated', 'p0-matrix-b@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000503', 'authenticated', 'authenticated', 'p0-matrix-legacy@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000520', 'authenticated', 'authenticated', 'p0-support@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000521', 'authenticated', 'authenticated', 'p0-content@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000522', 'authenticated', 'authenticated', 'p0-nutrition@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000523', 'authenticated', 'authenticated', 'p0-operations@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
  ('00000000-0000-0000-0000-000000000524', 'authenticated', 'authenticated', 'p0-master@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false);

INSERT INTO public.users (id, auth_user_id, email, wpp, name)
VALUES
  ('00000000-0000-0000-0000-000000000510', '00000000-0000-0000-0000-000000000501', 'p0-matrix-a@example.com', NULL, 'P0 Patient A'),
  ('00000000-0000-0000-0000-000000000511', '00000000-0000-0000-0000-000000000502', 'p0-matrix-b@example.com', NULL, 'P0 Patient B'),
  ('00000000-0000-0000-0000-000000000512', NULL, 'p0-matrix-legacy@example.com', NULL, 'P0 Legacy');

INSERT INTO public.user_profiles (user_id)
VALUES
  ('00000000-0000-0000-0000-000000000510'),
  ('00000000-0000-0000-0000-000000000511');

INSERT INTO public.user_progress (user_id)
VALUES
  ('00000000-0000-0000-0000-000000000510'),
  ('00000000-0000-0000-0000-000000000511');

INSERT INTO public.daily_snapshots (id, user_id, date)
VALUES
  ('00000000-0000-0000-0000-000000000530', '00000000-0000-0000-0000-000000000510', DATE '2099-01-01'),
  ('00000000-0000-0000-0000-000000000531', '00000000-0000-0000-0000-000000000511', DATE '2099-01-01');

INSERT INTO public.meal_logs (
  id,
  user_id,
  snapshot_id,
  meal_type,
  food_name,
  quantity_g,
  kcal,
  protein_g,
  carbs_g,
  fat_g,
  source
)
VALUES
  ('00000000-0000-0000-0000-000000000532', '00000000-0000-0000-0000-000000000510', '00000000-0000-0000-0000-000000000530', 'cafe', 'p0 synthetic meal a', 100, 100, 10, 10, 2, 'pending_approved'),
  ('00000000-0000-0000-0000-000000000533', '00000000-0000-0000-0000-000000000511', '00000000-0000-0000-0000-000000000531', 'cafe', 'p0 synthetic meal b', 100, 100, 10, 10, 2, 'pending_approved');

INSERT INTO public.workout_logs (id, user_id, snapshot_id, workout_type, duration_min)
VALUES
  ('00000000-0000-0000-0000-000000000534', '00000000-0000-0000-0000-000000000510', '00000000-0000-0000-0000-000000000530', 'p0 synthetic workout', 10),
  ('00000000-0000-0000-0000-000000000535', '00000000-0000-0000-0000-000000000511', '00000000-0000-0000-0000-000000000531', 'p0 synthetic workout', 10);

INSERT INTO public.reevaluations (id, user_id, evaluation_date)
VALUES
  ('00000000-0000-0000-0000-000000000536', '00000000-0000-0000-0000-000000000510', DATE '2099-01-01'),
  ('00000000-0000-0000-0000-000000000537', '00000000-0000-0000-0000-000000000511', DATE '2099-01-01');

INSERT INTO public.messages (id, user_id, direction, role, content_type, content, provider)
VALUES
  ('00000000-0000-0000-0000-000000000538', '00000000-0000-0000-0000-000000000510', 'in', 'user', 'text', 'p0 synthetic message a', 'bodyflow_test'),
  ('00000000-0000-0000-0000-000000000539', '00000000-0000-0000-0000-000000000511', 'in', 'user', 'text', 'p0 synthetic message b', 'bodyflow_test');

INSERT INTO public.pending_registrations (id, user_id, proposal, expires_at)
VALUES
  ('00000000-0000-0000-0000-000000000540', '00000000-0000-0000-0000-000000000510', '{"kind":"meal","synthetic":true}'::jsonb, now() + interval '1 hour'),
  ('00000000-0000-0000-0000-000000000541', '00000000-0000-0000-0000-000000000511', '{"kind":"meal","synthetic":true}'::jsonb, now() + interval '1 hour');

INSERT INTO public.prescriptions (id, user_id, type, payload)
VALUES
  ('00000000-0000-0000-0000-000000000542', '00000000-0000-0000-0000-000000000510', 'diet', '{"synthetic":true}'::jsonb),
  ('00000000-0000-0000-0000-000000000543', '00000000-0000-0000-0000-000000000511', 'diet', '{"synthetic":true}'::jsonb);

INSERT INTO public.training_plans (id, user_id, days_per_week, weekly_schedule)
VALUES
  ('00000000-0000-0000-0000-000000000544', '00000000-0000-0000-0000-000000000510', 3, '{"synthetic":true}'::jsonb),
  ('00000000-0000-0000-0000-000000000545', '00000000-0000-0000-0000-000000000511', 3, '{"synthetic":true}'::jsonb);

INSERT INTO public.subscriptions (id, user_id, plan, status)
VALUES
  ('00000000-0000-0000-0000-000000000546', '00000000-0000-0000-0000-000000000510', 'trial', 'trial'),
  ('00000000-0000-0000-0000-000000000547', '00000000-0000-0000-0000-000000000511', 'trial', 'trial');

INSERT INTO public.admin_users (id, email, role)
VALUES
  ('00000000-0000-0000-0000-000000000520', 'p0-support@example.com', 'support'),
  ('00000000-0000-0000-0000-000000000521', 'p0-content@example.com', 'content_editor'),
  ('00000000-0000-0000-0000-000000000522', 'p0-nutrition@example.com', 'nutrition_admin'),
  ('00000000-0000-0000-0000-000000000523', 'p0-operations@example.com', 'operations_admin'),
  ('00000000-0000-0000-0000-000000000524', 'p0-master@example.com', 'master_admin');

INSERT INTO public.global_config (key, value, description)
VALUES ('p0.matrix.config', 'true'::jsonb, 'synthetic authorization fixture');

INSERT INTO public.engagement_phrases (id, phrase, slot, curated_by)
VALUES ('00000000-0000-0000-0000-000000000550', 'p0 synthetic engagement', 'any', 'p0');

INSERT INTO public.food_education_phrases (id, food_canonical_name, phrase, curated_by)
VALUES ('00000000-0000-0000-0000-000000000551', 'p0-synthetic-food', 'p0 synthetic education', 'p0');

INSERT INTO public.workout_types (id, slug, display_name, category, kcal_per_min)
VALUES ('00000000-0000-0000-0000-000000000552', 'p0_matrix_workout', 'P0 Matrix Workout', 'cardio', 1);

INSERT INTO public.attention_dismissals (id, user_id, kind, reason)
VALUES ('00000000-0000-0000-0000-000000000553', '00000000-0000-0000-0000-000000000510', 'p0_matrix', 'synthetic');

INSERT INTO public.user_food_corrections (id, user_id, said_name, corrected_to)
VALUES ('00000000-0000-0000-0000-000000000554', '00000000-0000-0000-0000-000000000510', 'p0-wrong', 'p0-right');

INSERT INTO public.user_phrase_cooldown (user_id, phrase_table, phrase_id)
VALUES ('00000000-0000-0000-0000-000000000510', 'food', '00000000-0000-0000-0000-000000000551');

-- anon: no table or application RPC access.
SET LOCAL ROLE anon;
DO $test$
DECLARE
  v_table_denied boolean := false;
  v_rpc_denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);

  BEGIN
    PERFORM count(*) FROM public.users;
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_table_denied := true;
  END;

  BEGIN
    PERFORM public.bootstrap_patient_profile();
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_rpc_denied := true;
  END;

  IF NOT v_table_denied OR NOT v_rpc_denied THEN
    RAISE EXCEPTION 'anon reached a protected table or patient bootstrap RPC';
  END IF;
END;
$test$;

-- patient A: own reads pass, cross-user and internal reads return no rows.
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_own_count integer;
  v_cross_count integer;
  v_internal_count integer;
  v_column_denied boolean := false;
  v_write_denied boolean := false;
  v_admin_rpc_denied boolean := false;
  v_legacy_conflict boolean := false;
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000501","role":"authenticated","email":"p0-matrix-a@example.com"}',
    true
  );

  SELECT
    (SELECT count(*) FROM public.users WHERE id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.user_profiles WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.user_progress WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.daily_snapshots WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.meal_logs WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.workout_logs WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.reevaluations WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.messages WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.pending_registrations WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.prescriptions WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.training_plans WHERE user_id = '00000000-0000-0000-0000-000000000510')
    + (SELECT count(*) FROM public.subscriptions WHERE user_id = '00000000-0000-0000-0000-000000000510')
  INTO v_own_count;

  IF v_own_count <> 12 THEN
    RAISE EXCEPTION 'patient own-read matrix expected 12 rows, got %', v_own_count;
  END IF;

  SELECT
    (SELECT count(*) FROM public.users WHERE id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.user_profiles WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.user_progress WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.daily_snapshots WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.meal_logs WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.workout_logs WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.reevaluations WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.messages WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.pending_registrations WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.prescriptions WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.training_plans WHERE user_id = '00000000-0000-0000-0000-000000000511')
    + (SELECT count(*) FROM public.subscriptions WHERE user_id = '00000000-0000-0000-0000-000000000511')
  INTO v_cross_count;

  IF v_cross_count <> 0 THEN
    RAISE EXCEPTION 'patient cross-user read exposed % rows', v_cross_count;
  END IF;

  SELECT
    (SELECT count(*) FROM public.global_config WHERE key = 'p0.matrix.config')
    + (SELECT count(*) FROM public.food_education_phrases WHERE id = '00000000-0000-0000-0000-000000000551')
    + (SELECT count(*) FROM public.workout_types WHERE id = '00000000-0000-0000-0000-000000000552')
  INTO v_internal_count;

  IF v_internal_count <> 0 THEN
    RAISE EXCEPTION 'patient read an admin/reference surface';
  END IF;

  BEGIN
    PERFORM admin_notes
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000510';
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_column_denied := true;
  END;

  BEGIN
    UPDATE public.user_profiles
    SET onboarding_step = 99
    WHERE user_id = '00000000-0000-0000-0000-000000000510';
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_write_denied := true;
  END;

  BEGIN
    PERFORM public.set_global_config('p0.matrix.patient-write', 'true'::jsonb);
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_admin_rpc_denied := true;
  END;

  IF NOT v_column_denied OR NOT v_write_denied OR NOT v_admin_rpc_denied THEN
    RAISE EXCEPTION 'patient bypassed column, write, or RPC restrictions';
  END IF;

  IF public.is_admin() OR public.admin_role() IS NOT NULL THEN
    RAISE EXCEPTION 'patient was resolved as an admin';
  END IF;

  IF public.bootstrap_patient_profile() <> '00000000-0000-0000-0000-000000000510' THEN
    RAISE EXCEPTION 'patient bootstrap did not resolve its existing linked profile';
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000503","role":"authenticated","email":"p0-matrix-legacy@example.com"}',
    true
  );

  BEGIN
    PERFORM public.bootstrap_patient_profile();
  EXCEPTION
    WHEN unique_violation THEN
      v_legacy_conflict := true;
  END;

  IF NOT v_legacy_conflict THEN
    RAISE EXCEPTION 'legacy domain identity was linked automatically';
  END IF;
END;
$test$;

-- support: patient-care and attention read, content/config denied.
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_count integer;
  v_write_denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000520","role":"authenticated"}', true);
  IF public.admin_role() <> 'support' OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'support RBAC identity failed';
  END IF;

  SELECT count(*) INTO v_count FROM public.user_profiles;
  IF v_count <> 2 THEN RAISE EXCEPTION 'support cannot read patient care rows'; END IF;
  SELECT count(*) INTO v_count FROM public.attention_dismissals WHERE kind = 'p0_matrix';
  IF v_count <> 1 THEN RAISE EXCEPTION 'support cannot read attention dismissals'; END IF;
  SELECT count(*) INTO v_count FROM public.global_config WHERE key = 'p0.matrix.config';
  IF v_count <> 0 THEN RAISE EXCEPTION 'support read operations config'; END IF;
  SELECT count(*) INTO v_count FROM public.food_education_phrases WHERE id = '00000000-0000-0000-0000-000000000551';
  IF v_count <> 0 THEN RAISE EXCEPTION 'support read nutrition content'; END IF;

  BEGIN
    UPDATE public.users SET name = 'forbidden' WHERE id = '00000000-0000-0000-0000-000000000510';
  EXCEPTION
    WHEN insufficient_privilege THEN v_write_denied := true;
  END;
  IF NOT v_write_denied THEN RAISE EXCEPTION 'support wrote directly to a patient'; END IF;
END;
$test$;

-- content_editor: curated content only, no patient or operations data.
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000521","role":"authenticated"}', true);
  IF public.admin_role() <> 'content_editor' OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'content_editor RBAC identity failed';
  END IF;
  SELECT count(*) INTO v_count FROM public.user_profiles;
  IF v_count <> 0 THEN RAISE EXCEPTION 'content_editor read patient profiles'; END IF;
  SELECT count(*) INTO v_count FROM public.engagement_phrases WHERE id = '00000000-0000-0000-0000-000000000550';
  IF v_count <> 1 THEN RAISE EXCEPTION 'content_editor cannot read engagement content'; END IF;
  SELECT count(*) INTO v_count FROM public.food_education_phrases WHERE id = '00000000-0000-0000-0000-000000000551';
  IF v_count <> 1 THEN RAISE EXCEPTION 'content_editor cannot read food education content'; END IF;
  SELECT count(*) INTO v_count FROM public.global_config WHERE key = 'p0.matrix.config';
  IF v_count <> 0 THEN RAISE EXCEPTION 'content_editor read operations config'; END IF;
END;
$test$;

-- nutrition_admin: patient care and nutrition reference data, no operations config.
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000522","role":"authenticated"}', true);
  IF public.admin_role() <> 'nutrition_admin' OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'nutrition_admin RBAC identity failed';
  END IF;
  SELECT count(*) INTO v_count FROM public.user_profiles;
  IF v_count <> 2 THEN RAISE EXCEPTION 'nutrition_admin cannot read patient profiles'; END IF;
  SELECT count(*) INTO v_count FROM public.food_education_phrases WHERE id = '00000000-0000-0000-0000-000000000551';
  IF v_count <> 1 THEN RAISE EXCEPTION 'nutrition_admin cannot read food education content'; END IF;
  SELECT count(*) INTO v_count FROM public.workout_types WHERE id = '00000000-0000-0000-0000-000000000552';
  IF v_count <> 1 THEN RAISE EXCEPTION 'nutrition_admin cannot read workout reference data'; END IF;
  SELECT count(*) INTO v_count FROM public.user_food_corrections WHERE id = '00000000-0000-0000-0000-000000000554';
  IF v_count <> 1 THEN RAISE EXCEPTION 'nutrition_admin cannot read food corrections'; END IF;
  SELECT count(*) INTO v_count FROM public.global_config WHERE key = 'p0.matrix.config';
  IF v_count <> 0 THEN RAISE EXCEPTION 'nutrition_admin read operations config'; END IF;
END;
$test$;

-- operations_admin: patient operations, config and cooldown, not curated content.
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000523","role":"authenticated"}', true);
  IF public.admin_role() <> 'operations_admin' OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'operations_admin RBAC identity failed';
  END IF;
  SELECT count(*) INTO v_count FROM public.user_profiles;
  IF v_count <> 2 THEN RAISE EXCEPTION 'operations_admin cannot read patient profiles'; END IF;
  SELECT count(*) INTO v_count FROM public.global_config WHERE key = 'p0.matrix.config';
  IF v_count <> 1 THEN RAISE EXCEPTION 'operations_admin cannot read global config'; END IF;
  SELECT count(*) INTO v_count FROM public.user_phrase_cooldown WHERE phrase_id = '00000000-0000-0000-0000-000000000551';
  IF v_count <> 1 THEN RAISE EXCEPTION 'operations_admin cannot read phrase cooldown'; END IF;
  SELECT count(*) INTO v_count FROM public.food_education_phrases WHERE id = '00000000-0000-0000-0000-000000000551';
  IF v_count <> 0 THEN RAISE EXCEPTION 'operations_admin read curated nutrition content'; END IF;
END;
$test$;

-- master_admin: all explicitly admin-readable surfaces, but still no direct writes/RPCs.
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_count integer;
  v_write_denied boolean := false;
  v_rpc_denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000524","role":"authenticated"}', true);
  IF public.admin_role() <> 'master_admin' OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'master_admin RBAC identity failed';
  END IF;
  SELECT
    (SELECT count(*) FROM public.user_profiles)
    + (SELECT count(*) FROM public.global_config WHERE key = 'p0.matrix.config')
    + (SELECT count(*) FROM public.engagement_phrases WHERE id = '00000000-0000-0000-0000-000000000550')
    + (SELECT count(*) FROM public.food_education_phrases WHERE id = '00000000-0000-0000-0000-000000000551')
    + (SELECT count(*) FROM public.workout_types WHERE id = '00000000-0000-0000-0000-000000000552')
  INTO v_count;
  IF v_count <> 6 THEN RAISE EXCEPTION 'master_admin read matrix expected 6 rows, got %', v_count; END IF;

  BEGIN
    UPDATE public.global_config SET value = 'false'::jsonb WHERE key = 'p0.matrix.config';
  EXCEPTION
    WHEN insufficient_privilege THEN v_write_denied := true;
  END;
  BEGIN
    PERFORM public.set_global_config('p0.matrix.master-write', 'true'::jsonb);
  EXCEPTION
    WHEN insufficient_privilege THEN v_rpc_denied := true;
  END;
  IF NOT v_write_denied OR NOT v_rpc_denied THEN
    RAISE EXCEPTION 'master_admin bypassed the BFF mutation boundary';
  END IF;
END;
$test$;

-- service_role: trusted backend sees all rows and can execute protected mutations.
RESET ROLE;
SET LOCAL ROLE service_role;
DO $test$
DECLARE
  v_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  SELECT count(*) INTO v_count
  FROM public.users
  WHERE id IN (
    '00000000-0000-0000-0000-000000000510',
    '00000000-0000-0000-0000-000000000511',
    '00000000-0000-0000-0000-000000000512'
  );
  IF v_count <> 3 THEN RAISE EXCEPTION 'service_role cannot read all synthetic users'; END IF;

  PERFORM public.set_global_config('p0.matrix.service-write', 'true'::jsonb);
  SELECT count(*) INTO v_count
  FROM public.global_config
  WHERE key = 'p0.matrix.service-write'
    AND value = 'true'::jsonb;
  IF v_count <> 1 THEN RAISE EXCEPTION 'service_role protected mutation failed'; END IF;

  SELECT count(*) INTO v_count FROM public.v_user_metrics;
  IF v_count < 2 THEN RAISE EXCEPTION 'service_role cannot read protected metrics view'; END IF;
END;
$test$;

RESET ROLE;
ROLLBACK;
