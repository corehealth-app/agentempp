\set ON_ERROR_STOP on
-- Run only through the reviewed local prefix controller. The migration DO body
-- is supplied byte-for-byte; its BEGIN/COMMIT are owned by this rollback test.
\if :{?visibility_payload}
\else
DO $$BEGIN RAISE EXCEPTION 'S17C_TEST_PAYLOAD_REQUIRED';END$$;
\endif
\if :{?with_private_usage}
\else
DO $$BEGIN RAISE EXCEPTION 'S17C_TEST_SCENARIO_REQUIRED';END$$;
\endif
\if :{?reject_extra_execute}
\else
\set reject_extra_execute false
\endif
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=pg_catalog;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='5s';
DO $target$BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR current_database()<>'postgres' OR inet_server_addr() IS NOT NULL
 OR current_setting('listen_addresses')<>''
 OR to_regprocedure('private.mobile_workout_registration_pending_is_protected(uuid,uuid)') IS NULL
 OR to_regprocedure('public.mobile_workout_registration_pending_is_protected(uuid,uuid)') IS NOT NULL
 THEN RAISE EXCEPTION 'S17C_TEST_WRONG_LOCAL_PREFIX';END IF;
END $target$;
\if :with_private_usage
DO $$BEGIN
 IF NOT has_schema_privilege('service_role','private','USAGE') THEN
 RAISE EXCEPTION 'S17C_TEST_REAL_CHAIN_GRANT_MISSING';END IF;
END$$;
\else
-- Only this test transaction removes the old grant. ROLLBACK restores it.
REVOKE USAGE ON SCHEMA private FROM service_role;
\endif
\if :reject_extra_execute
GRANT EXECUTE ON FUNCTION private.mobile_workout_registration_pending_is_protected(uuid,uuid) TO anon;
\endif
CREATE TEMP TABLE s17c_usage_before ON COMMIT DROP AS
 SELECT (:'with_private_usage')::boolean AS expected_usage,
  (SELECT jsonb_agg(to_jsonb(n) ORDER BY n.oid) FROM pg_namespace n
   WHERE n.nspname IN('public','private')) AS schemas,
  (SELECT to_jsonb(p) FROM pg_proc p WHERE p.oid=
   'private.mobile_workout_registration_pending_is_protected(uuid,uuid)'::regprocedure) AS helper,
  (SELECT to_jsonb(p) FROM pg_proc p WHERE p.oid=
   'private.guard_mobile_workout_registration()'::regprocedure) AS guard;
\i :visibility_payload
DO $preservation$DECLARE baseline record;helper oid;BEGIN
 SELECT * INTO STRICT baseline FROM pg_temp.s17c_usage_before;
 helper:=to_regprocedure('public.mobile_workout_registration_pending_is_protected(uuid,uuid)');
 IF helper IS NULL OR helper IS DISTINCT FROM (baseline.helper->>'oid')::oid
 OR to_regprocedure('private.mobile_workout_registration_pending_is_protected(uuid,uuid)') IS NOT NULL
 OR has_schema_privilege('service_role','private','USAGE') IS DISTINCT FROM baseline.expected_usage
 OR (SELECT jsonb_agg(to_jsonb(n) ORDER BY n.oid) FROM pg_namespace n WHERE n.nspname IN('public','private')) IS DISTINCT FROM baseline.schemas
 OR (SELECT to_jsonb(p) FROM pg_proc p WHERE p.oid=helper) IS DISTINCT FROM
   jsonb_set(baseline.helper,'{pronamespace}',to_jsonb('public'::regnamespace::oid))
 OR (SELECT to_jsonb(p) FROM pg_proc p WHERE p.oid='private.guard_mobile_workout_registration()'::regprocedure) IS DISTINCT FROM
   jsonb_set(baseline.guard,'{prosrc}',to_jsonb(replace(baseline.guard->>'prosrc',
    'private.mobile_workout_registration_pending_is_protected(',
    'public.mobile_workout_registration_pending_is_protected(')))
 OR NOT has_function_privilege('service_role',helper,'EXECUTE')
 OR has_function_privilege('anon',helper,'EXECUTE')
 OR has_function_privilege('authenticated',helper,'EXECUTE')
 THEN RAISE EXCEPTION 'S17C_TEST_EXISTING_SCHEMA_AND_FUNCTION_CAPABILITIES_NOT_PRESERVED';END IF;
 RAISE NOTICE 'S17C_TEST_PRESERVATION_PASS:usage=%',baseline.expected_usage;
END $preservation$;
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $service$BEGIN
 IF public.mobile_workout_registration_pending_is_protected(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '00000000-0000-0000-0000-000000000000'::uuid) IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'S17C_TEST_SERVICE_BOOLEAN_CAPABILITY';END IF;
 RAISE NOTICE 'S17C_TEST_SERVICE_CAPABILITY_PASS';
END $service$;
RESET ROLE;
ROLLBACK;
DO $rollback$BEGIN
 IF to_regprocedure('private.mobile_workout_registration_pending_is_protected(uuid,uuid)') IS NULL
 OR to_regprocedure('public.mobile_workout_registration_pending_is_protected(uuid,uuid)') IS NOT NULL
 OR NOT has_schema_privilege('service_role','private','USAGE')
 OR to_regclass('pg_temp.s17c_usage_before') IS NOT NULL
 THEN RAISE EXCEPTION 'S17C_TEST_ROLLBACK_INCOMPLETE';END IF;
 RAISE NOTICE 'S17C_TEST_ROLLBACK_PASS';
END $rollback$;
