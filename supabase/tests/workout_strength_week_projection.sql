-- Future missing RPC is SETUP, never product RED. No SQL executed by source author.
\set ON_ERROR_STOP on
\if :{?setup_concurrency}
\else
\set setup_concurrency false
\endif
\if :{?teardown_concurrency}
\else
\set teardown_concurrency false
\endif
\if :setup_concurrency
\if :teardown_concurrency
DO $$BEGIN RAISE EXCEPTION 'C59S12_SETUP_CONFLICTING_MODES';END$$;
\endif
\endif
\if :teardown_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $ownership$DECLARE o record;BEGIN
 SELECT * INTO STRICT o FROM c59s12_fixture.ownership WHERE tag='c59s12_week_projection_v1';
 IF o.owner_name<>session_user OR o.object_oids IS DISTINCT FROM c59s12_fixture.object_oids() OR o.object_fingerprint IS DISTINCT FROM c59s12_fixture.object_fingerprint() OR(SELECT count(*) FROM c59s12_fixture.ownership)<>1 THEN RAISE EXCEPTION 'C59S12_TEARDOWN_OBJECT_DRIFT';END IF;
 IF(SELECT count(*) FROM public.users WHERE id IN('c59ac000-0000-0000-0000-000000000011','c59ac000-0000-0000-0000-000000000012','c59ac000-0000-0000-0000-000000000013','c59ac000-0000-0000-0000-000000000014') AND metadata->>'c59s12_fixture'='c59s12_week_projection_v1' AND wpp='c59s12-'||id::text)<>4 THEN RAISE EXCEPTION 'C59S12_TEARDOWN_OWNER_DRIFT';END IF;
 DELETE FROM public.users WHERE id IN('c59ac000-0000-0000-0000-000000000011','c59ac000-0000-0000-0000-000000000012','c59ac000-0000-0000-0000-000000000013','c59ac000-0000-0000-0000-000000000014') AND metadata->>'c59s12_fixture'='c59s12_week_projection_v1';
 IF EXISTS(SELECT 1 FROM public.workout_logs) OR EXISTS(SELECT 1 FROM public.daily_snapshots) OR EXISTS(SELECT 1 FROM private.workout_strength_lifecycles) OR EXISTS(SELECT 1 FROM private.workout_strength_operations) OR EXISTS(SELECT 1 FROM private.workout_strength_facts) OR EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes) THEN RAISE EXCEPTION 'C59S12_TEARDOWN_FOREIGN_ROWS';END IF;
END $ownership$;
DROP FUNCTION public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date);
DROP FUNCTION public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text);
DROP FUNCTION public.prepare_workout_strength_calendar_scope(uuid,uuid);
DROP FUNCTION public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text);
DROP FUNCTION private.workout_strength_fact_snapshot(uuid,uuid,uuid);
DROP TABLE private.workout_strength_calendar_scopes;DROP TABLE private.workout_strength_facts;DROP TABLE private.workout_strength_operations;DROP TABLE private.workout_strength_lifecycles;
DROP TABLE public.workout_logs;DROP TABLE public.daily_snapshots;
DROP FUNCTION c59s12_fixture.seed_fact(uuid,uuid,uuid,date,text,text,text,text);
DROP FUNCTION c59s12_fixture.object_fingerprint();DROP FUNCTION c59s12_fixture.object_oids();DROP FUNCTION c59s12_fixture.state(uuid);DROP FUNCTION c59s12_fixture.throws(text,text,text);DROP FUNCTION c59s12_fixture.ok(boolean,text);
DROP TABLE c59s12_fixture.ownership;DROP SCHEMA c59s12_fixture;
COMMIT;
\echo C59S12_CONCURRENCY_TEARDOWN_CONFIRMED
\else
\if :{?migration_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S12_SETUP_MIGRATION_PATH';END$$;
\endif
\if :{?bindings_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S12_SETUP_BINDINGS_PATH';END$$;
\endif
\if :{?facts_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S12_SETUP_FACTS_PATH';END$$;
\endif
\if :{?answers_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S12_SETUP_ANSWERS_PATH';END$$;
\endif
\if :{?calendar_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S12_SETUP_CALENDAR_PATH';END$$;
\endif
\if :setup_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S12_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s12_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_calendar_scopes')))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='private' AND p.proname='workout_strength_fact_snapshot') OR(n.nspname='public' AND p.proname IN('resolve_confirmed_workout_strength_capture','answer_confirmed_workout_strength','prepare_workout_strength_calendar_scope','get_confirmed_workouts_for_strength_week')))
 THEN RAISE EXCEPTION 'C59S12_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_week_projection_fixture.sql
SELECT c59s12_fixture.object_fingerprint() AS before_DDL
\gset s12_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)') IS NULL THEN RAISE EXCEPTION 'C59S12_SETUP_UNIMPLEMENTED_NOT_PRODUCT_RED';END IF;END$$;
DO $owners$DECLARE i integer;u uuid;l uuid;s jsonb;BEGIN FOR i IN 11..14 LOOP
 u:=('c59ac000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;l:=('c59ac000-0000-0000-0000-'||lpad((i+100)::text,12,'0'))::uuid;
 INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES(u,'c59s12-'||u,'C59S12 synthetic','UTC','{"c59a2_synthetic":true,"c59s12_fixture":"c59s12_week_projection_v1"}');
 INSERT INTO private.workout_strength_lifecycles VALUES(u,l,clock_timestamp(),NULL,NULL);
 s:=public.prepare_workout_strength_calendar_scope(u,l);
 IF s->>'status'<>'prepared' THEN RAISE EXCEPTION 'C59S12_SETUP_SCOPE';END IF;
 IF i IN(11,12) THEN PERFORM c59s12_fixture.seed_fact(u,l,('c59ac000-0000-0000-0000-'||lpad((i+900)::text,12,'0'))::uuid,(s#>>'{scope,asOfLocalDate}')::date,'unrecognized');END IF;
 END LOOP;END $owners$;
INSERT INTO c59s12_fixture.ownership VALUES('c59s12_week_projection_v1',session_user,c59s12_fixture.object_oids(),c59s12_fixture.object_fingerprint());
COMMIT;
\echo C59S12_CONCURRENCY_SETUP_CONFIRMED
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S12_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s12_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_calendar_scopes')))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='private' AND p.proname='workout_strength_fact_snapshot') OR(n.nspname='public' AND p.proname IN('resolve_confirmed_workout_strength_capture','answer_confirmed_workout_strength','prepare_workout_strength_calendar_scope','get_confirmed_workouts_for_strength_week')))
 THEN RAISE EXCEPTION 'C59S12_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_week_projection_fixture.sql
SELECT c59s12_fixture.object_fingerprint() AS before_DDL
\gset s12_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)') IS NULL THEN RAISE EXCEPTION 'C59S12_SETUP_UNIMPLEMENTED_NOT_PRODUCT_RED';END IF;END$$;
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000000501','UTC','2026-10-12','2026-10-15'),'22023','P01_actual_RR_valid_UUID_before_absent_owner');
ROLLBACK;
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S12_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s12_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_calendar_scopes')))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='private' AND p.proname='workout_strength_fact_snapshot') OR(n.nspname='public' AND p.proname IN('resolve_confirmed_workout_strength_capture','answer_confirmed_workout_strength','prepare_workout_strength_calendar_scope','get_confirmed_workouts_for_strength_week')))
 THEN RAISE EXCEPTION 'C59S12_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_week_projection_fixture.sql
SELECT c59s12_fixture.object_fingerprint() AS before_DDL
\gset s12_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)') IS NULL THEN RAISE EXCEPTION 'C59S12_SETUP_UNIMPLEMENTED_NOT_PRODUCT_RED';END IF;END$$;
SELECT count(*) AS n FROM public.users
\gset s12_baseline_
INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES('c59ac000-0000-0000-0000-000000000001','c59s12-main-a','C59S12 A','UTC','{"c59a2_synthetic":true}'),('c59ac000-0000-0000-0000-000000000002','c59s12-main-b','C59S12 B','UTC','{"c59a2_synthetic":true}');
INSERT INTO private.workout_strength_lifecycles VALUES('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',clock_timestamp(),NULL,NULL),('c59ac000-0000-0000-0000-000000000002','c59ac000-0000-0000-0000-000000000102',clock_timestamp(),NULL,NULL);
SELECT public.prepare_workout_strength_calendar_scope('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101')->'scope' AS scope
\gset s12_
SELECT public.prepare_workout_strength_calendar_scope('c59ac000-0000-0000-0000-000000000002','c59ac000-0000-0000-0000-000000000102')->'scope' AS scope_b
\gset s12_
SET LOCAL DateStyle='SQL, DMY';SET LOCAL TimeZone='Pacific/Auckland';
SELECT c59s12_fixture.object_fingerprint() AS after_DDL
\gset s12_
SELECT c59s12_fixture.ok((:'s12_after_ddl'::jsonb-'functions')=(:'s12_before_ddl'::jsonb-'functions') AND (:'s12_after_ddl'::jsonb->'functions')-'public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)'=(:'s12_before_ddl'::jsonb->'functions') AND current_setting('DateStyle')='SQL, DMY' AND current_setting('TimeZone')='Pacific/Auckland','P15_only_new_RPC_metadata_all_substrate_guard_triggers_sequences_preserved_canonical');
SELECT c59s12_fixture.ok((SELECT prosecdef AND provolatile='v' AND prorettype='jsonb'::regtype AND pronargdefaults=0 AND proconfig=ARRAY['search_path=pg_catalog']::text[] AND proargnames=ARRAY['p_user_id','p_expected_lifecycle_key','p_scope_key','p_time_zone','p_week_start_date','p_as_of_local_date']::text[] FROM pg_proc WHERE oid='public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)'::regprocedure) AND (SELECT count(*)=1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='get_confirmed_workouts_for_strength_week'),'P15_single_exact_RPC6_volatile_security_config');
SELECT c59s12_fixture.ok(has_function_privilege('service_role','public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)','EXECUTE') AND NOT has_function_privilege('anon','public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)','EXECUTE') AND NOT has_function_privilege('authenticated','public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)','EXECUTE') AND NOT EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid='public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)'::regprocedure AND a.grantee NOT IN(p.proowner,'service_role'::regrole::oid)),'P15_only_owner_service_execute_all_grantees');
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)',NULL,NULL,NULL,NULL,NULL,NULL),'42501','P01_real_guard_before_NULL_validation');
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)',NULL,'c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date),'22023','P01_required_NULL_argument_1');
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','c59ac000-0000-0000-0000-000000000001',NULL,(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date),'22023','P01_required_NULL_argument_2');
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',NULL,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date),'22023','P01_required_NULL_argument_3');
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,NULL,(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date),'22023','P01_required_NULL_argument_4');
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',NULL,(:'s12_scope'::jsonb->>'asOfLocalDate')::date),'22023','P01_required_NULL_argument_5');
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,NULL),'22023','P01_required_NULL_argument_6');
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','not-a-uuid','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date),'22P02','P01_malformed_UUID_coercion_not_guard_proof');
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','c59ac000-0000-0000-0000-000000009999','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date),'P0002','P02_missing_owner_P0002');
SAVEPOINT inactive;UPDATE public.users SET status='blocked' WHERE id='c59ac000-0000-0000-0000-000000000001';
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date),'P0002','P02_inactive_owner_P0002');
ROLLBACK TO SAVEPOINT inactive;RELEASE SAVEPOINT inactive;
SAVEPOINT schema_failure;ALTER TABLE private.workout_strength_facts RENAME TO c59s12_facts_temporarily_absent;
SELECT c59s12_fixture.throws(format('SELECT public.get_confirmed_workouts_for_strength_week(%L,%L,%L,%L,%L,%L)','c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date),'42P01','P12_real_schema_error_propagates_no_fallback');
ROLLBACK TO SAVEPOINT schema_failure;RELEASE SAVEPOINT schema_failure;
SET LOCAL ROLE service_role;
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
RESET ROLE;
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"available","workouts":[]}'::jsonb,'P03_actual_service_complete_empty_U_available_exact');
INSERT INTO public.workout_logs(user_id,workout_type,performed_at) VALUES('c59ac000-0000-0000-0000-000000000002','C59S12 foreign legacy','1900-01-01T12:00:00Z');
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000002','c59ac000-0000-0000-0000-000000000102','c59ac000-0000-0000-0000-000000003001',(:'s12_scope'::jsonb->>'asOfLocalDate')::date,'matched','musculacao');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"available","workouts":[]}'::jsonb,'P03_foreign_owner_legacy_does_not_enter_U');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000102',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_foreign_lifecycle_calendar_null');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000009998',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_missing_lifecycle_calendar_null');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000009999',:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_missing_scope_calendar_null');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope_b'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_foreign_scope_calendar_null');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,'UTC ',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,'utc',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS zone_case_response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb AND :'s12_zone_case_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_altered_zone_calendar_null');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,'',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_empty_zone_calendar_null');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date-7,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_altered_week_calendar_null');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date+1,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_non_Monday_week_calendar_null');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone','infinity'::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_infinite_week_calendar_null');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date+1) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_altered_asOf_calendar_null');
SAVEPOINT closed;UPDATE private.workout_strength_lifecycles SET closed_at=clock_timestamp(),close_operation_key='C59S12-close' WHERE user_id='c59ac000-0000-0000-0000-000000000001';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P02_closed_lifecycle_denies_persisting_scope');
SELECT c59s12_fixture.ok(EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes WHERE user_id='c59ac000-0000-0000-0000-000000000001'),'P02_closed_UPDATE_did_not_delete_scope_but_does_not_authorize');
ROLLBACK TO SAVEPOINT closed;RELEASE SAVEPOINT closed;
SAVEPOINT profile_zone;UPDATE public.users SET timezone='C59S12/Not_Current_Zone' WHERE id='c59ac000-0000-0000-0000-000000000001';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"available","workouts":[]}'::jsonb,'P07_no_current_profile_zone_or_new_clock_authority');
ROLLBACK TO SAVEPOINT profile_zone;RELEASE SAVEPOINT profile_zone;
SAVEPOINT canonical;
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001001',(:'s12_scope'::jsonb->>'weekStartDate')::date,'matched','musculacao');
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001002',(:'s12_scope'::jsonb->>'asOfLocalDate')::date,'matched','cardio');
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001003',(:'s12_scope'::jsonb->>'weekStartDate')::date,'matched','esporte');
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001004',(:'s12_scope'::jsonb->>'weekStartDate')::date,'matched','mobilidade');
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001005',(:'s12_scope'::jsonb->>'weekStartDate')::date,'unrecognized',NULL);
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001006',(:'s12_scope'::jsonb->>'asOfLocalDate')::date,'unrecognized',NULL);
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001007',(:'s12_scope'::jsonb->>'weekStartDate')::date,'unrecognized',NULL);
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001008',(:'s12_scope'::jsonb->>'weekStartDate')::date-1,'unavailable',NULL);
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001009',(:'s12_scope'::jsonb->>'asOfLocalDate')::date+1,'matched','cardio');
SELECT c59s12_fixture.seed_fact('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001010',(:'s12_scope'::jsonb->>'weekStartDate')::date-1,'matched','cardio');
SELECT public.answer_confirmed_workout_strength('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001006',0,'c59ac000-0000-0000-0000-000000001006','yes','canonical-yes') AS answer_yes
\gset s12_
SELECT public.answer_confirmed_workout_strength('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000001007',0,'c59ac000-0000-0000-0000-000000001007','no','canonical-no') AS answer_no
\gset s12_
SELECT c59s12_fixture.ok(:'s12_answer_yes'::jsonb->>'status'='accepted' AND :'s12_answer_no'::jsonb->>'status'='accepted','P05_real_S9_yes_and_no_accepted_before_projection');
SELECT jsonb_agg(jsonb_build_object('ownerKey','c59ac000-0000-0000-0000-000000000001','workoutKey',w,'localDate',to_char(d,'YYYY-MM-DD'),'state','confirmed','catalogueCategory',category,'storedStrengthAnswer',CASE WHEN answer IS NULL THEN NULL ELSE jsonb_build_object('ownerKey','c59ac000-0000-0000-0000-000000000001','workoutKey',w,'answer',answer) END) ORDER BY d,w) AS expected FROM (VALUES ('c59ac000-0000-0000-0000-000000001001'::uuid,(:'s12_scope'::jsonb->>'weekStartDate')::date,'musculacao'::text,NULL::text),('c59ac000-0000-0000-0000-000000001002'::uuid,(:'s12_scope'::jsonb->>'asOfLocalDate')::date,'cardio'::text,NULL::text),('c59ac000-0000-0000-0000-000000001003'::uuid,(:'s12_scope'::jsonb->>'weekStartDate')::date,'esporte'::text,NULL::text),('c59ac000-0000-0000-0000-000000001004'::uuid,(:'s12_scope'::jsonb->>'weekStartDate')::date,'mobilidade'::text,NULL::text),('c59ac000-0000-0000-0000-000000001005'::uuid,(:'s12_scope'::jsonb->>'weekStartDate')::date,NULL::text,NULL::text),('c59ac000-0000-0000-0000-000000001006'::uuid,(:'s12_scope'::jsonb->>'asOfLocalDate')::date,NULL::text,'yes'::text),('c59ac000-0000-0000-0000-000000001007'::uuid,(:'s12_scope'::jsonb->>'weekStartDate')::date,NULL::text,'no'::text)) v(w,d,category,answer)
\gset s12_
SELECT c59s12_fixture.state('c59ac000-0000-0000-0000-000000000001') AS canonical_before
\gset s12_
SELECT c59s12_fixture.state('c59ac000-0000-0000-0000-000000000002') AS foreign_before
\gset s12_
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb=jsonb_build_object('status','available','workouts',:'s12_expected'::jsonb),'P04_P05_exact_DTO6_order_frozen4categories_unrecognized_yes_no_unanswered_dates');
SELECT c59s12_fixture.ok(c59s12_fixture.state('c59ac000-0000-0000-0000-000000000001')=:'s12_canonical_before'::jsonb AND c59s12_fixture.state('c59ac000-0000-0000-0000-000000000002')=:'s12_foreign_before'::jsonb,'P15_projection_readonly_owned_and_foreign_full_state');
SELECT c59s12_fixture.ok((SELECT bool_and(created_at>(SELECT created_at FROM private.workout_strength_calendar_scopes WHERE user_id='c59ac000-0000-0000-0000-000000000001')) FROM public.workout_logs WHERE user_id='c59ac000-0000-0000-0000-000000000001'),'P11_fixture_rows_created_after_scope_no_created_at_cutoff_proof');
SAVEPOINT all_outside;
INSERT INTO private.workout_strength_calendar_scopes VALUES('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000000601','UTC',DATE '1900-01-01',DATE '1900-01-04','1900-01-04T12:00:00Z');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000000601',:'s12_scope'::jsonb->>'timeZone',DATE '1900-01-01',DATE '1900-01-04') AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"available","workouts":[]}'::jsonb,'P04_all_global_calendars_proven_but_outside_historical_scope_available_empty');
ROLLBACK TO SAVEPOINT all_outside;RELEASE SAVEPOINT all_outside;
SAVEPOINT legacy_gap;
INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,performed_at,created_at) VALUES('c59ac000-0000-0000-0000-000000000001',NULL,'C59S12 legacy distant','1900-01-01T12:00:00Z',clock_timestamp());
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P06_legacy_null_snapshot_even_distant_no_temporal_exclusion');
ROLLBACK TO SAVEPOINT legacy_gap;RELEASE SAVEPOINT legacy_gap;
SAVEPOINT legacy_gap;
INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,performed_at,created_at) VALUES('c59ac000-0000-0000-0000-000000000001',(SELECT id FROM public.daily_snapshots WHERE user_id='c59ac000-0000-0000-0000-000000000001' AND date=(:'s12_scope'::jsonb->>'weekStartDate')::date-1),'C59S12 legacy distant','1900-01-01T12:00:00Z',clock_timestamp());
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P06_legacy_owned_snapshot_even_distant_no_temporal_exclusion');
ROLLBACK TO SAVEPOINT legacy_gap;RELEASE SAVEPOINT legacy_gap;
SAVEPOINT unknown_calendar;UPDATE private.workout_strength_facts SET calendar_status='unavailable',calendar_reason='zone_unproved',local_date=NULL,time_zone=NULL,zone_source=NULL,zone_observed_at=NULL WHERE workout_log_id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P06_outside_calendar_zone_unproved_blocks_complete_array');
ROLLBACK TO SAVEPOINT unknown_calendar;RELEASE SAVEPOINT unknown_calendar;
SAVEPOINT unknown_calendar;UPDATE private.workout_strength_facts SET calendar_status='unavailable',calendar_reason='calendar_conflict',local_date=NULL,time_zone=NULL,zone_source=NULL,zone_observed_at=NULL WHERE workout_log_id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P06_outside_calendar_calendar_conflict_blocks_complete_array');
ROLLBACK TO SAVEPOINT unknown_calendar;RELEASE SAVEPOINT unknown_calendar;
SAVEPOINT unknown_calendar;UPDATE private.workout_strength_facts SET calendar_status='unavailable',calendar_reason='legacy_calendar_gap',local_date=NULL,time_zone=NULL,zone_source=NULL,zone_observed_at=NULL WHERE workout_log_id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P06_outside_calendar_legacy_calendar_gap_blocks_complete_array');
ROLLBACK TO SAVEPOINT unknown_calendar;RELEASE SAVEPOINT unknown_calendar;
SAVEPOINT foreign_zone;UPDATE private.workout_strength_facts SET time_zone='Etc/UTC' WHERE workout_log_id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P07_foreign_literal_alias_zone_outside_still_blocks');
ROLLBACK TO SAVEPOINT foreign_zone;RELEASE SAVEPOINT foreign_zone;
SAVEPOINT old_life;INSERT INTO private.workout_strength_lifecycles VALUES('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000100','2020-01-01T00:00:00Z','2020-01-02T00:00:00Z','C59S12-old-close');UPDATE private.workout_strength_facts SET lifecycle_key='c59ac000-0000-0000-0000-000000000100' WHERE workout_log_id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P06_oldlife_fact_outside_not_hidden_by_fact_join_filter');
UPDATE public.workout_logs SET workout_type=workout_type||'-changed' WHERE id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"identity_unproved","workouts":null}'::jsonb,'P10_oldlife_and_anchor_contradiction_identity_precedes_calendar');
ROLLBACK TO SAVEPOINT old_life;RELEASE SAVEPOINT old_life;
SAVEPOINT identity_gap;
DO $case_only_premise$DECLARE raw text;BEGIN
 SELECT workout_type INTO STRICT raw FROM public.workout_logs WHERE id='c59ac000-0000-0000-0000-000000001008';
 IF (((raw COLLATE "C")<>(upper(raw) COLLATE "C")) AND ((lower(raw) COLLATE "C")=(lower(upper(raw)) COLLATE "C"))) IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S12_SETUP_CASE_ONLY_PREMISE';END IF;
END $case_only_premise$;
UPDATE public.workout_logs SET workout_type=upper(workout_type) WHERE id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"identity_unproved","workouts":null}'::jsonb,'P08_stored_type_C_mismatch_outside');
ROLLBACK TO SAVEPOINT identity_gap;RELEASE SAVEPOINT identity_gap;
SAVEPOINT identity_gap;
UPDATE public.workout_logs SET performed_at=performed_at+interval '1 microsecond' WHERE id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"identity_unproved","workouts":null}'::jsonb,'P08_performed_at_exact_microsecond_mismatch_outside');
ROLLBACK TO SAVEPOINT identity_gap;RELEASE SAVEPOINT identity_gap;
SAVEPOINT identity_gap;
UPDATE public.workout_logs SET snapshot_id=NULL WHERE id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"identity_unproved","workouts":null}'::jsonb,'P08_fact_present_snapshot_NULL_contradiction');
ROLLBACK TO SAVEPOINT identity_gap;RELEASE SAVEPOINT identity_gap;
SAVEPOINT identity_gap;
INSERT INTO public.daily_snapshots(user_id,date) VALUES('c59ac000-0000-0000-0000-000000000002',DATE '1900-01-01');UPDATE public.workout_logs SET snapshot_id=(SELECT id FROM public.daily_snapshots WHERE user_id='c59ac000-0000-0000-0000-000000000002' AND date=DATE '1900-01-01') WHERE id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"identity_unproved","workouts":null}'::jsonb,'P08_foreign_snapshot_real_UUID_not_owned');
ROLLBACK TO SAVEPOINT identity_gap;RELEASE SAVEPOINT identity_gap;
SAVEPOINT identity_gap;
UPDATE public.daily_snapshots SET date=(:'s12_scope'::jsonb->>'weekStartDate')::date-2 WHERE user_id='c59ac000-0000-0000-0000-000000000001' AND date=(:'s12_scope'::jsonb->>'weekStartDate')::date-1;
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"identity_unproved","workouts":null}'::jsonb,'P08_real_snapshot_date_differs_from_fact_copy');
ROLLBACK TO SAVEPOINT identity_gap;RELEASE SAVEPOINT identity_gap;
SAVEPOINT provenance;
UPDATE public.workout_logs SET snapshot_id=(SELECT id FROM public.daily_snapshots WHERE user_id='c59ac000-0000-0000-0000-000000000001' AND date=(:'s12_scope'::jsonb->>'weekStartDate')::date),performed_at=((:'s12_scope'::jsonb->>'weekStartDate')::date+TIME '12:00') AT TIME ZONE 'UTC' WHERE id='c59ac000-0000-0000-0000-000000001008';
UPDATE private.workout_strength_facts SET snapshot_id=(SELECT id FROM public.daily_snapshots WHERE user_id='c59ac000-0000-0000-0000-000000000001' AND date=(:'s12_scope'::jsonb->>'weekStartDate')::date),snapshot_date=(:'s12_scope'::jsonb->>'weekStartDate')::date,local_date=(:'s12_scope'::jsonb->>'weekStartDate')::date,performed_at=((:'s12_scope'::jsonb->>'weekStartDate')::date+TIME '12:00') AT TIME ZONE 'UTC' WHERE workout_log_id='c59ac000-0000-0000-0000-000000001008';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"provenance_gap","workouts":null}'::jsonb,'P09_relevant_classification_unavailable_only_provenance_gap');
SAVEPOINT precedence_identity;
UPDATE public.workout_logs SET workout_type=workout_type||'-changed' WHERE id='c59ac000-0000-0000-0000-000000001001';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"identity_unproved","workouts":null}'::jsonb,'P10_identity_precedes_relevant_provenance_gap');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101','c59ac000-0000-0000-0000-000000009999',:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P10_scope_mismatch_precedes_identity_and_provenance');
ROLLBACK TO SAVEPOINT precedence_identity;RELEASE SAVEPOINT precedence_identity;
INSERT INTO public.workout_logs(user_id,workout_type,performed_at) VALUES('c59ac000-0000-0000-0000-000000000001','C59S12 unknown outside','1900-01-01T12:00:00Z');
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P10_global_unknown_calendar_precedes_relevant_provenance_gap');
ROLLBACK TO SAVEPOINT provenance;RELEASE SAVEPOINT provenance;
SAVEPOINT correction;
DELETE FROM public.workout_logs WHERE id='c59ac000-0000-0000-0000-000000001001';INSERT INTO public.workout_logs(user_id,workout_type,performed_at,created_at) VALUES('c59ac000-0000-0000-0000-000000000001','C59S12 corrected new UUID',((:'s12_scope'::jsonb->>'weekStartDate')::date+TIME '12:00') AT TIME ZONE 'UTC',clock_timestamp());
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb,'P11_correction_new_legacy_UUID_cannot_reuse_deleted_fact');
SELECT c59s12_fixture.ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE workout_log_id='c59ac000-0000-0000-0000-000000001001'),'P11_real_deleted_workout_fact_cascade_observed');
ROLLBACK TO SAVEPOINT correction;RELEASE SAVEPOINT correction;
SAVEPOINT deletion;
DELETE FROM public.workout_logs WHERE id='c59ac000-0000-0000-0000-000000001001';
SELECT public.get_confirmed_workouts_for_strength_week('c59ac000-0000-0000-0000-000000000001','c59ac000-0000-0000-0000-000000000101',(:'s12_scope'::jsonb->>'scopeKey')::uuid,:'s12_scope'::jsonb->>'timeZone',(:'s12_scope'::jsonb->>'weekStartDate')::date,(:'s12_scope'::jsonb->>'asOfLocalDate')::date) AS response
\gset s12_
SELECT c59s12_fixture.ok(:'s12_response'::jsonb=jsonb_build_object('status','available','workouts',(SELECT jsonb_agg(e ORDER BY e->>'localDate',e->>'workoutKey') FROM jsonb_array_elements(:'s12_expected'::jsonb) e WHERE e->>'workoutKey'<>'c59ac000-0000-0000-0000-000000001001')),'P11_deleted_UUID_not_projected_or_resurrected');
ROLLBACK TO SAVEPOINT deletion;RELEASE SAVEPOINT deletion;
ROLLBACK TO SAVEPOINT canonical;RELEASE SAVEPOINT canonical;
SELECT c59s12_fixture.object_fingerprint() AS collision_before
\gset s12_
SELECT set_config('c59s12_test.migration_path',:'migration_path',true);
SELECT c59s12_fixture.throws('DO $actual_migration$BEGIN EXECUTE pg_read_file(current_setting(''c59s12_test.migration_path''));END $actual_migration$','42P07','P15_actual_migration_existing_RPC_CREATE_only');
SELECT c59s12_fixture.ok(c59s12_fixture.object_fingerprint()=:'s12_collision_before'::jsonb,'P15_CREATE_only_collision_no_overwrite');
SAVEPOINT unknown_overload;DROP FUNCTION public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date);CREATE FUNCTION public.get_confirmed_workouts_for_strength_week(text) RETURNS text LANGUAGE sql AS 'SELECT $1';
SELECT c59s12_fixture.throws('DO $actual_migration$BEGIN EXECUTE pg_read_file(current_setting(''c59s12_test.migration_path''));END $actual_migration$','42P07','P15_actual_migration_unknown_overload_CREATE_only');
SELECT c59s12_fixture.ok(to_regprocedure('public.get_confirmed_workouts_for_strength_week(text)') IS NOT NULL AND to_regprocedure('public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)') IS NULL,'P15_unknown_overload_preserved_no_new_signature');
ROLLBACK TO SAVEPOINT unknown_overload;RELEASE SAVEPOINT unknown_overload;
ROLLBACK;
SELECT CASE WHEN to_regnamespace('c59s12_fixture') IS NULL AND to_regclass('private.workout_strength_facts') IS NULL AND to_regclass('private.workout_strength_calendar_scopes') IS NULL AND to_regclass('private.workout_strength_lifecycles') IS NULL AND to_regclass('public.workout_logs') IS NULL AND (SELECT count(*) FROM public.users)=:s12_baseline_n THEN 'C59S12_ROLLBACK_CONFIRMED' ELSE 'C59S12_ROLLBACK_FAILED' END;
\endif
\endif
