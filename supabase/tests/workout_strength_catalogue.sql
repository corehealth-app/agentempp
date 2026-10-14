-- S3 test-first: use ONLY Root's exclusive local synthetic retained cluster.
-- Root must bind/pin the CLI-generated migration_path and verify fresh baseline.
-- Missing path/function/include is SETUP, never causal RED or functional PASS.
\set ON_ERROR_STOP on
\if :{?migration_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59A3_S3_SETUP_MIGRATION_PATH_REQUIRED';END$$;
\endif
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL TimeZone='Pacific/Auckland';

DO $preflight$
BEGIN
  IF to_regclass('public.workout_types') IS NOT NULL
    OR to_regnamespace('c59a3s3_fixture') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='get_workout_strength_catalogue_context')
  THEN RAISE EXCEPTION 'C59A3_S3_SETUP_UNKNOWN_EXISTING_OBJECT';END IF;
  IF to_regprocedure('private.assert_trusted_backend()') IS NULL
  THEN RAISE EXCEPTION 'C59A3_S3_SETUP_ORIGINAL_GUARD_MISSING';END IF;
END $preflight$;
SELECT md5(jsonb_build_object('definition',pg_get_functiondef(p.oid),
  'acl',p.proacl::text,'owner',p.proowner::text,'config',p.proconfig,
  'security_definer',p.prosecdef,'volatility',p.provolatile)::text) AS guard_fingerprint
FROM pg_proc p WHERE p.oid='private.assert_trusted_backend()'::regprocedure
\gset s3_

\ir fixtures/workout_strength_catalogue_fixture.sql
SELECT coalesce(c.relacl::text,'<NULL>') AS legacy_table_acl
FROM pg_class c WHERE c.oid='public.workout_types'::regclass
\gset s3_
SELECT c59a3s3_fixture.ok(
  has_table_privilege('authenticated','public.workout_types','SELECT')
  AND has_table_privilege('service_role','public.workout_types','SELECT'),
  'setup_real_legacy_select_grants');

-- Root pins this exact absolute local migration file before any execution.
\i :migration_path
DO $installed$
BEGIN
  IF to_regprocedure('public.get_workout_strength_catalogue_context()') IS NULL
  THEN RAISE EXCEPTION 'C59A3_S3_SETUP_OBSERVER_UNIMPLEMENTED';END IF;
  PERFORM c59a3s3_fixture.ok((SELECT l.lanname='plpgsql' FROM pg_proc p
    JOIN pg_language l ON l.oid=p.prolang
    WHERE p.oid='public.get_workout_strength_catalogue_context()'::regprocedure),
    'installed_language_plpgsql');
END $installed$;
SELECT c59a3s3_fixture.ok((SELECT coalesce(c.relacl::text,'<NULL>') FROM pg_class c
  WHERE c.oid='public.workout_types'::regclass)=:'s3_legacy_table_acl',
  'legacy_table_acl_exact_after_migration');

-- G6 FIRST authorized execution: no valid-call cached relation before rename.
SAVEPOINT s3_missing_table;
ALTER TABLE public.workout_types RENAME TO workout_types_s3_missing;
SELECT c59a3s3_fixture.throws(
  'SELECT public.get_workout_strength_catalogue_context()',
  '42P01',NULL,'G6_real_missing_table_error_not_json');
ROLLBACK TO SAVEPOINT s3_missing_table;
RELEASE SAVEPOINT s3_missing_table;

-- G1 valid complete empty set, exact envelope types/keys and DB metadata.
DO $g1$
DECLARE r jsonb;lower_at timestamptz;upper_at timestamptz;
BEGIN
  lower_at:=clock_timestamp();r:=public.get_workout_strength_catalogue_context();upper_at:=clock_timestamp();
  PERFORM c59a3s3_fixture.ok(r ?& ARRAY['status','observationKey','observedAt','matcherVersion','complete','rowCount','activeRows']
    AND (SELECT count(*)=7 FROM jsonb_object_keys(r))
    AND r->>'status'='available' AND r->'complete'='true'::jsonb
    AND r->>'matcherVersion'='active_slug_then_unique_canonical_display_v1'
    AND r->'rowCount'='"0"'::jsonb AND r->'activeRows'='[]'::jsonb,
    'G1_complete_empty_exact_wire');
  PERFORM c59a3s3_fixture.ok((r->>'observationKey')~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND (r->>'observedAt')~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}Z$'
    AND (r->>'observedAt')::timestamptz BETWEEN lower_at AND upper_at,
    'G1_metadata_real_uuid_utc_us6_clock_bound');
END $g1$;

-- Six fixed rows inserted in reverse UUID order; only five are active.
INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min,is_active,updated_at)
VALUES
('c59a5000-0000-0000-0000-000000000006','caminhada','Caminhada','cardio',4.5,false,'2026-10-14T20:00:00.000006Z'),
('c59a5000-0000-0000-0000-000000000005','outro','Outro','cardio',6,true,'2026-10-14T20:00:00.000005Z'),
('c59a5000-0000-0000-0000-000000000004','yoga','Yoga','mobilidade',3,true,'2026-10-14T20:00:00.000004Z'),
('c59a5000-0000-0000-0000-000000000003','luta','Luta / Jiu-jitsu / Boxe','esporte',10.5,true,'2026-10-14T20:00:00.000003Z'),
('c59a5000-0000-0000-0000-000000000002','natacao','Natação','cardio',10,true,'2026-10-14T20:00:00.000002Z'),
('c59a5000-0000-0000-0000-000000000001','peito_triceps','Peito e tríceps','musculacao',5.5,true,'2026-10-14T20:00:00.000001Z');

-- G2/G3/G4 exact output independent of relation scan/insertion/session timezone.
DO $g234$
DECLARE r jsonb;expected jsonb;item jsonb;
BEGIN
  r:=public.get_workout_strength_catalogue_context();
  expected:=$rows$[
    {"id":"c59a5000-0000-0000-0000-000000000001","slug":"peito_triceps","displayName":"Peito e tríceps","category":"musculacao","isActive":true,"updatedAtLiteral":"2026-10-14T20:00:00.000001Z"},
    {"id":"c59a5000-0000-0000-0000-000000000002","slug":"natacao","displayName":"Natação","category":"cardio","isActive":true,"updatedAtLiteral":"2026-10-14T20:00:00.000002Z"},
    {"id":"c59a5000-0000-0000-0000-000000000003","slug":"luta","displayName":"Luta / Jiu-jitsu / Boxe","category":"esporte","isActive":true,"updatedAtLiteral":"2026-10-14T20:00:00.000003Z"},
    {"id":"c59a5000-0000-0000-0000-000000000004","slug":"yoga","displayName":"Yoga","category":"mobilidade","isActive":true,"updatedAtLiteral":"2026-10-14T20:00:00.000004Z"},
    {"id":"c59a5000-0000-0000-0000-000000000005","slug":"outro","displayName":"Outro","category":"cardio","isActive":true,"updatedAtLiteral":"2026-10-14T20:00:00.000005Z"}
  ]$rows$::jsonb;
  PERFORM c59a3s3_fixture.ok((SELECT count(*)=6 FROM public.workout_types)
    AND r->'rowCount'='"5"'::jsonb AND r->'complete'='true'::jsonb
    AND r->>'status'='available','G2_five_active_of_six_physical');
  PERFORM c59a3s3_fixture.ok(r->'activeRows'=expected,'G3_G4_exact_sorted_rows_category_names_microseconds');
  PERFORM c59a3s3_fixture.ok(r ?& ARRAY['status','observationKey','observedAt','matcherVersion','complete','rowCount','activeRows']
    AND (SELECT count(*)=7 FROM jsonb_object_keys(r)),'G3_exact_seven_envelope_keys');
  FOR item IN SELECT value FROM jsonb_array_elements(r->'activeRows') LOOP
    PERFORM c59a3s3_fixture.ok(item ?& ARRAY['id','slug','displayName','category','isActive','updatedAtLiteral']
      AND (SELECT count(*)=6 FROM jsonb_object_keys(item)),'G3_exact_six_row_keys:'||(item->>'slug'));
  END LOOP;
  PERFORM c59a3s3_fixture.ok(current_setting('TimeZone')='Pacific/Auckland'
    AND (r->>'observedAt')~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}Z$'
    AND (r->>'observationKey')~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    'G4_metadata_utc_under_non_utc_session');
END $g234$;

-- G5 known source invalidity uses legal original DDL, no dropped CHECK.
SAVEPOINT s3_invalid_source;
UPDATE public.workout_types SET updated_at='infinity'::timestamptz
WHERE id='c59a5000-0000-0000-0000-000000000001';
SELECT c59a3s3_fixture.ok(public.get_workout_strength_catalogue_context()=
  '{"status":"unavailable","reason":"catalogue_invalid"}'::jsonb,
  'G5_active_infinity_whole_source_invalid_not_partial');
ROLLBACK TO SAVEPOINT s3_invalid_source;
RELEASE SAVEPOINT s3_invalid_source;
SELECT c59a3s3_fixture.ok(public.get_workout_strength_catalogue_context()->'rowCount'='"5"'::jsonb,
  'G5_savepoint_restores_valid_source');

-- G7 actual service_role execution plus denied end-user EXECUTE (not guard alone).
DO $g7$
DECLARE r jsonb;role_name text;s text;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  r:=public.get_workout_strength_catalogue_context();
  EXECUTE 'RESET ROLE';
  PERFORM c59a3s3_fixture.ok(r->>'status'='available' AND r->'rowCount'='"5"'::jsonb,
    'G7_service_role_real_execution');
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
    s:=NULL;
    -- Service claims keep the guard permissive IF a forbidden EXECUTE leaked.
    EXECUTE format('SET LOCAL ROLE %I',role_name);
    BEGIN
      PERFORM public.get_workout_strength_catalogue_context();
    EXCEPTION WHEN OTHERS THEN s:=SQLSTATE;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM c59a3s3_fixture.ok(s='42501', 'G7_end_user_execute_denied:'||role_name);
  END LOOP;
END $g7$;

-- G8 owner has implicit EXECUTE: authenticated claims must hit ORIGINAL guard.
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
SELECT c59a3s3_fixture.throws('SELECT public.get_workout_strength_catalogue_context()',
  '42501','trusted backend role required','G8_owner_bad_claim_original_guard');
SET LOCAL request.jwt.claims='{"role":"service_role"}';

-- G9 native function metadata, exact ACL and no unrelated permission edits.
DO $g9$
DECLARE p record;service_oid oid;
BEGIN
  SELECT f.*,l.lanname INTO p FROM pg_proc f JOIN pg_language l ON l.oid=f.prolang
    WHERE f.oid='public.get_workout_strength_catalogue_context()'::regprocedure;
  SELECT oid INTO service_oid FROM pg_roles WHERE rolname='service_role';
  PERFORM c59a3s3_fixture.ok(p.pronargs=0 AND p.pronargdefaults=0 AND NOT p.proretset
    AND p.prorettype='jsonb'::regtype AND p.prosecdef AND p.provolatile='v'
    AND p.lanname='plpgsql' AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
    AND (SELECT count(*)=1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace
      WHERE n.nspname='public' AND f.proname='get_workout_strength_catalogue_context'),
    'G9_zero_args_jsonb_definer_volatile_path_no_overload');
  PERFORM c59a3s3_fixture.ok(has_function_privilege('service_role',p.oid,'EXECUTE')
    AND has_function_privilege(p.proowner,p.oid,'EXECUTE')
    AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      WHERE a.grantee NOT IN(p.proowner,service_oid) OR a.privilege_type<>'EXECUTE'
        OR (a.grantee=service_oid AND a.is_grantable)),
    'G9_execute_only_owner_service_no_PUBLIC_or_grant_option');
  PERFORM c59a3s3_fixture.ok(NOT has_schema_privilege('anon','c59a3s3_fixture','USAGE')
    AND NOT has_schema_privilege('authenticated','c59a3s3_fixture','USAGE')
    AND NOT has_schema_privilege('service_role','c59a3s3_fixture','USAGE')
    AND NOT has_function_privilege('service_role','c59a3s3_fixture.ok(boolean,text)','EXECUTE'),
    'G9_fixture_helpers_remain_owner_only');
END $g9$;
SELECT c59a3s3_fixture.ok((SELECT coalesce(c.relacl::text,'<NULL>') FROM pg_class c
  WHERE c.oid='public.workout_types'::regclass)=:'s3_legacy_table_acl'
  AND has_table_privilege('authenticated','public.workout_types','SELECT')
  AND has_table_privilege('service_role','public.workout_types','SELECT'),
  'G9_legacy_table_select_ACL_still_exact');
SELECT c59a3s3_fixture.ok((SELECT md5(jsonb_build_object('definition',pg_get_functiondef(p.oid),
  'acl',p.proacl::text,'owner',p.proowner::text,'config',p.proconfig,
  'security_definer',p.prosecdef,'volatility',p.provolatile)::text)
  FROM pg_proc p WHERE p.oid='private.assert_trusted_backend()'::regprocedure)=:'s3_guard_fingerprint',
  'G8_G9_original_guard_definition_ACL_metadata_unchanged');

-- G10 entire DDL, rows, ACL and helper state is rolled back, never COMMIT.
ROLLBACK;
SELECT (to_regclass('public.workout_types') IS NULL
  AND to_regnamespace('c59a3s3_fixture') IS NULL
  AND NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='get_workout_strength_catalogue_context')
  AND (SELECT md5(jsonb_build_object('definition',pg_get_functiondef(p.oid),
    'acl',p.proacl::text,'owner',p.proowner::text,'config',p.proconfig,
    'security_definer',p.prosecdef,'volatility',p.provolatile)::text)
    FROM pg_proc p WHERE p.oid='private.assert_trusted_backend()'::regprocedure)=:'s3_guard_fingerprint')
  AS rollback_ok
\gset s3_
\if :s3_rollback_ok
\echo C59A3_S3_ROLLBACK_OBJECTS_GUARD_CONFIRMED_NO_ACTIVATION_CLAIM
\else
DO $$BEGIN RAISE EXCEPTION 'C59A3_S3_ROLLBACK_OR_GUARD_MISMATCH';END$$;
\endif
-- Root executor separately compares fresh full baseline/rows/sequences and stop.
