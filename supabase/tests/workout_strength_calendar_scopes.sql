-- S11 test-first; future missing table/RPC is SETUP, never a causal product RED.
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
DO $$BEGIN RAISE EXCEPTION 'C59S11_SETUP_CONFLICTING_MODES';END$$;
\endif
\endif
\if :teardown_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $ownership$DECLARE o record;BEGIN
 SELECT * INTO STRICT o FROM c59s11_fixture.ownership WHERE tag='c59s11_scopes_v1';
 IF o.owner_name<>session_user OR o.object_oids IS DISTINCT FROM c59s11_fixture.object_oids()
 OR o.object_fingerprint IS DISTINCT FROM c59s11_fixture.object_fingerprint() OR(SELECT count(*) FROM c59s11_fixture.ownership)<>1
 THEN RAISE EXCEPTION 'C59S11_TEARDOWN_OBJECT_DRIFT';END IF;
 IF(SELECT count(*) FROM public.users WHERE id IN('c59ab000-0000-0000-0000-000000000011','c59ab000-0000-0000-0000-000000000012')
 AND metadata->>'c59s11_fixture'='c59s11_scopes_v1' AND wpp='c59s11-'||id::text)<>2 THEN RAISE EXCEPTION 'C59S11_TEARDOWN_OWNER_DRIFT';END IF;
 DELETE FROM public.users WHERE id IN('c59ab000-0000-0000-0000-000000000011','c59ab000-0000-0000-0000-000000000012') AND metadata->>'c59s11_fixture'='c59s11_scopes_v1';
 IF EXISTS(SELECT 1 FROM public.workout_logs) OR EXISTS(SELECT 1 FROM public.daily_snapshots) OR EXISTS(SELECT 1 FROM private.workout_strength_lifecycles)
 OR EXISTS(SELECT 1 FROM private.workout_strength_operations) OR EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes) THEN RAISE EXCEPTION 'C59S11_TEARDOWN_FOREIGN_ROWS';END IF;
END $ownership$;
DROP FUNCTION public.prepare_workout_strength_calendar_scope(uuid,uuid);
DROP TABLE private.workout_strength_calendar_scopes;
DROP TABLE private.workout_strength_operations;DROP TABLE private.workout_strength_lifecycles;
DROP TABLE public.workout_logs;DROP TABLE public.daily_snapshots;
DROP FUNCTION c59s11_fixture.object_fingerprint();DROP FUNCTION c59s11_fixture.object_oids();DROP FUNCTION c59s11_fixture.state(uuid);
DROP FUNCTION c59s11_fixture.throws(text,text,text);DROP FUNCTION c59s11_fixture.ok(boolean,text);
DROP TABLE c59s11_fixture.ownership;DROP SCHEMA c59s11_fixture;
COMMIT;
\echo C59S11_CONCURRENCY_TEARDOWN_CONFIRMED
\else
\if :{?migration_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S11_SETUP_MIGRATION_PATH';END$$;
\endif
\if :{?bindings_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S11_SETUP_BINDINGS_PATH';END$$;
\endif
\if :setup_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S11_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s11_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_calendar_scopes')))
 OR EXISTS(SELECT 1 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname='prepare_workout_strength_calendar_scope')
 THEN RAISE EXCEPTION 'C59S11_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_calendar_scopes_fixture.sql
SELECT jsonb_build_object('definition',pg_get_functiondef(p.oid),'oid',p.oid::text,'owner',p.proowner::text,'acl',p.proacl::text,'config',p.proconfig) AS guard FROM pg_proc p WHERE p.oid='private.assert_trusted_backend()'::regprocedure
\gset s11_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.prepare_workout_strength_calendar_scope(uuid,uuid)') IS NULL THEN RAISE EXCEPTION 'C59S11_SETUP_UNIMPLEMENTED_NOT_PRODUCT_RED';END IF;END$$;
DO $owners$DECLARE i integer;u uuid;l uuid;BEGIN FOR i IN 11..12 LOOP
 u:=('c59ab000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;l:=('c59ab000-0000-0000-0000-'||lpad((i+100)::text,12,'0'))::uuid;
 INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES(u,'c59s11-'||u,'C59S11 synthetic','UTC','{"c59a2_synthetic":true,"c59s11_fixture":"c59s11_scopes_v1"}');
 INSERT INTO private.workout_strength_lifecycles VALUES(u,l,clock_timestamp(),NULL,NULL);END LOOP;END $owners$;
INSERT INTO c59s11_fixture.ownership VALUES('c59s11_scopes_v1',session_user,c59s11_fixture.object_oids(),c59s11_fixture.object_fingerprint());
COMMIT;
\echo C59S11_CONCURRENCY_SETUP_CONFIRMED
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S11_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s11_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_calendar_scopes')))
 OR EXISTS(SELECT 1 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname='prepare_workout_strength_calendar_scope')
 THEN RAISE EXCEPTION 'C59S11_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_calendar_scopes_fixture.sql
SELECT jsonb_build_object('definition',pg_get_functiondef(p.oid),'oid',p.oid::text,'owner',p.proowner::text,'acl',p.proacl::text,'config',p.proconfig) AS guard FROM pg_proc p WHERE p.oid='private.assert_trusted_backend()'::regprocedure
\gset s11_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.prepare_workout_strength_calendar_scope(uuid,uuid)') IS NULL THEN RAISE EXCEPTION 'C59S11_SETUP_UNIMPLEMENTED_NOT_PRODUCT_RED';END IF;END$$;
SELECT c59s11_fixture.throws('SELECT public.prepare_workout_strength_calendar_scope(''c59ab000-0000-0000-0000-000000000001'',''c59ab000-0000-0000-0000-000000000101'')','22023','guard_actual_RR_before_owner');
ROLLBACK;
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S11_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s11_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_calendar_scopes')))
 OR EXISTS(SELECT 1 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname='prepare_workout_strength_calendar_scope')
 THEN RAISE EXCEPTION 'C59S11_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_calendar_scopes_fixture.sql
SELECT jsonb_build_object('definition',pg_get_functiondef(p.oid),'oid',p.oid::text,'owner',p.proowner::text,'acl',p.proacl::text,'config',p.proconfig) AS guard FROM pg_proc p WHERE p.oid='private.assert_trusted_backend()'::regprocedure
\gset s11_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.prepare_workout_strength_calendar_scope(uuid,uuid)') IS NULL THEN RAISE EXCEPTION 'C59S11_SETUP_UNIMPLEMENTED_NOT_PRODUCT_RED';END IF;END$$;
SELECT count(*) AS n FROM public.users
\gset s11_baseline_
INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES('c59ab000-0000-0000-0000-000000000001','c59s11-main-a','C59S11 A','UTC','{"c59a2_synthetic":true}'),('c59ab000-0000-0000-0000-000000000002','c59s11-main-b','C59S11 B','UTC','{"c59a2_synthetic":true}');
INSERT INTO private.workout_strength_lifecycles VALUES('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101',clock_timestamp(),NULL,NULL),('c59ab000-0000-0000-0000-000000000002','c59ab000-0000-0000-0000-000000000102',clock_timestamp(),NULL,NULL);
SELECT c59s11_fixture.object_fingerprint() AS fp
\gset s11_
SET LOCAL DateStyle='SQL, DMY';SET LOCAL TimeZone='Pacific/Auckland';
SELECT c59s11_fixture.object_fingerprint() AS fp_adversarial
\gset s11_
SELECT c59s11_fixture.ok(:'s11_fp_adversarial'::jsonb=:'s11_fp'::jsonb AND current_setting('DateStyle')='SQL, DMY' AND current_setting('TimeZone')='Pacific/Auckland','fingerprint_full_context_invariant_settings_restored');
SAVEPOINT fingerprint_change;ALTER TABLE private.workout_strength_calendar_scopes ADD CONSTRAINT c59s11_physical_probe CHECK(as_of_local_date<>DATE '2020-01-01') NOT VALID;
SELECT c59s11_fixture.ok(c59s11_fixture.object_fingerprint() IS DISTINCT FROM :'s11_fp'::jsonb,'fingerprint_real_constraint_change_detected');
ROLLBACK TO SAVEPOINT fingerprint_change;RELEASE SAVEPOINT fingerprint_change;
SELECT c59s11_fixture.ok((SELECT jsonb_build_object('definition',pg_get_functiondef(p.oid),'oid',p.oid::text,'owner',p.proowner::text,'acl',p.proacl::text,'config',p.proconfig)=:'s11_guard'::jsonb FROM pg_proc p WHERE p.oid='private.assert_trusted_backend()'::regprocedure),'real_trusted_guard_byte_metadata_preserved');
SELECT c59s11_fixture.ok((SELECT prosecdef AND provolatile='v' AND pronargdefaults=0 AND prorettype='jsonb'::regtype AND proconfig=ARRAY['search_path=pg_catalog']::text[] AND proargnames=ARRAY['p_user_id','p_expected_lifecycle_key']::text[] FROM pg_proc WHERE oid='public.prepare_workout_strength_calendar_scope(uuid,uuid)'::regprocedure) AND (SELECT count(*)=1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='prepare_workout_strength_calendar_scope'),'single_RPC2_security_volatile_config_exact');
SELECT c59s11_fixture.ok((SELECT array_agg(attname::text ORDER BY attnum)=ARRAY['user_id','lifecycle_key','scope_key','time_zone','week_start_date','as_of_local_date','created_at'] AND bool_and(attnotnull) AND array_agg(format_type(atttypid,atttypmod) ORDER BY attnum)=ARRAY['uuid','uuid','uuid','text','date','date','timestamp with time zone'] FROM pg_attribute WHERE attrelid='private.workout_strength_calendar_scopes'::regclass AND attnum>0 AND NOT attisdropped),'storage_exact7_types_NOTNULL');
SELECT c59s11_fixture.ok((SELECT attcollation='"C"'::regcollation FROM pg_attribute WHERE attrelid='private.workout_strength_calendar_scopes'::regclass AND attname='time_zone'),'time_zone_column_C');
SELECT c59s11_fixture.ok(EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.workout_strength_calendar_scopes'::regclass AND contype='p' AND conkey=ARRAY[1,2,3]::smallint[]) AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.workout_strength_calendar_scopes'::regclass AND contype='u' AND conkey=ARRAY[1,2,4,5,6]::smallint[]),'PK_and_normal_UNIQUE_exact_keys');
SELECT c59s11_fixture.ok(EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.workout_strength_calendar_scopes'::regclass AND contype='f' AND confrelid='private.workout_strength_lifecycles'::regclass AND conkey=ARRAY[1,2]::smallint[] AND confkey=ARRAY[1,2]::smallint[] AND confdeltype='c'),'owned_lifecycle_FK_cascade');
SELECT c59s11_fixture.ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.workout_strength_calendar_scopes'::regclass) AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.workout_strength_calendar_scopes'::regclass) AND NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.workout_strength_calendar_scopes'::regclass AND NOT tgisinternal),'RLS_no_policies_no_custom_triggers');
SELECT c59s11_fixture.ok(NOT EXISTS(SELECT 1 FROM (VALUES('anon'),('authenticated'),('service_role')) r(role) CROSS JOIN (VALUES('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) a(privilege) WHERE has_table_privilege(r.role,'private.workout_strength_calendar_scopes',a.privilege)) AND NOT EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='private.workout_strength_calendar_scopes'::regclass AND a.grantee=0),'storage_no_external_DML_or_PUBLIC');
SELECT c59s11_fixture.ok(has_function_privilege('service_role','public.prepare_workout_strength_calendar_scope(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.prepare_workout_strength_calendar_scope(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','public.prepare_workout_strength_calendar_scope(uuid,uuid)','EXECUTE') AND NOT EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid='public.prepare_workout_strength_calendar_scope(uuid,uuid)'::regprocedure AND a.grantee NOT IN(p.proowner,'service_role'::regrole::oid)),'RPC_only_service_owner_EXECUTE');
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
SELECT c59s11_fixture.throws('SELECT public.prepare_workout_strength_calendar_scope(NULL,NULL)','42501','real_guard_before_NULL_body_validation');
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT c59s11_fixture.throws('SELECT public.prepare_workout_strength_calendar_scope(NULL,''c59ab000-0000-0000-0000-000000000101'')','22023','NULL_owner_22023');
SELECT c59s11_fixture.throws('SELECT public.prepare_workout_strength_calendar_scope(''c59ab000-0000-0000-0000-000000000001'',NULL)','22023','NULL_lifecycle_22023');
SELECT c59s11_fixture.throws('SELECT public.prepare_workout_strength_calendar_scope(NULL,NULL)','22023','both_NULL_22023');
SELECT c59s11_fixture.throws('SELECT public.prepare_workout_strength_calendar_scope(''not-a-uuid'',NULL)','22P02','malformed_UUID_input_coercion_not_guard_proof');
SELECT c59s11_fixture.throws('SELECT public.prepare_workout_strength_calendar_scope(''c59ab000-0000-0000-0000-000000009999'',''c59ab000-0000-0000-0000-000000000101'')','P0002','missing_owner_P0002');
SAVEPOINT inactive;UPDATE public.users SET status='blocked' WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT c59s11_fixture.throws('SELECT public.prepare_workout_strength_calendar_scope(''c59ab000-0000-0000-0000-000000000001'',''c59ab000-0000-0000-0000-000000000101'')','P0002','inactive_owner_P0002');
ROLLBACK TO SAVEPOINT inactive;RELEASE SAVEPOINT inactive;
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS before
\gset s11_
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000009999') AS response
\gset s11_
SELECT c59s11_fixture.ok(:'s11_response'::jsonb='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001')=:'s11_before'::jsonb,'absent_lifecycle_exact_negative_zero_writes');
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000102') AS response
\gset s11_
SELECT c59s11_fixture.ok(:'s11_response'::jsonb='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001')=:'s11_before'::jsonb,'foreign_lifecycle_exact_negative_zero_writes');
SAVEPOINT closed;UPDATE private.workout_strength_lifecycles SET closed_at=clock_timestamp(),close_operation_key='c59s11-close' WHERE user_id='c59ab000-0000-0000-0000-000000000001';
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS closed_before
\gset s11_
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS response
\gset s11_
SELECT c59s11_fixture.ok(:'s11_response'::jsonb='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001')=:'s11_closed_before'::jsonb,'closed_lifecycle_not_reopened_zero_writes');
ROLLBACK TO SAVEPOINT closed;RELEASE SAVEPOINT closed;
SELECT c59s11_fixture.ok(NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name COLLATE "C" IN('C59S11/Definitely_Unlisted' COLLATE "C",'UTC ' COLLATE "C")),'invalid_zone_fixture_really_unlisted');
SAVEPOINT invalid_zone;UPDATE public.users SET timezone=NULL WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS zone_before
\gset s11_
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS response
\gset s11_
SELECT c59s11_fixture.ok(:'s11_response'::jsonb='{"status":"unavailable","reason":"zone_unproved"}'::jsonb AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001')=:'s11_zone_before'::jsonb,'zone_NULL_exact_negative_zero_writes');
ROLLBACK TO SAVEPOINT invalid_zone;RELEASE SAVEPOINT invalid_zone;
SAVEPOINT invalid_zone;UPDATE public.users SET timezone='' WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS zone_before
\gset s11_
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS response
\gset s11_
SELECT c59s11_fixture.ok(:'s11_response'::jsonb='{"status":"unavailable","reason":"zone_unproved"}'::jsonb AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001')=:'s11_zone_before'::jsonb,'zone_empty_exact_negative_zero_writes');
ROLLBACK TO SAVEPOINT invalid_zone;RELEASE SAVEPOINT invalid_zone;
SAVEPOINT invalid_zone;UPDATE public.users SET timezone='C59S11/Definitely_Unlisted' WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS zone_before
\gset s11_
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS response
\gset s11_
SELECT c59s11_fixture.ok(:'s11_response'::jsonb='{"status":"unavailable","reason":"zone_unproved"}'::jsonb AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001')=:'s11_zone_before'::jsonb,'zone_unlisted_exact_negative_zero_writes');
ROLLBACK TO SAVEPOINT invalid_zone;RELEASE SAVEPOINT invalid_zone;
SAVEPOINT invalid_zone;UPDATE public.users SET timezone='UTC ' WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS zone_before
\gset s11_
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS response
\gset s11_
SELECT c59s11_fixture.ok(:'s11_response'::jsonb='{"status":"unavailable","reason":"zone_unproved"}'::jsonb AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001')=:'s11_zone_before'::jsonb,'zone_trailing_space_exact_negative_zero_writes');
ROLLBACK TO SAVEPOINT invalid_zone;RELEASE SAVEPOINT invalid_zone;
-- Setup precondition exceeds the controller sequential timeout90s; not a sleep or clock seam.
DO $margin$DECLARE z text;BEGIN FOREACH z IN ARRAY ARRAY['UTC','Etc/UTC','America/Sao_Paulo'] LOOP IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name COLLATE "C"=z COLLATE "C") OR extract(epoch FROM(date_trunc('day',clock_timestamp() AT TIME ZONE z)+interval '1 day'-(clock_timestamp() AT TIME ZONE z)))<=180 THEN RAISE EXCEPTION 'C59S11_SETUP_CLOCK_MARGIN_OR_ZONE';END IF;END LOOP;END $margin$;
SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS lower
\gset s11_
SET LOCAL ROLE service_role;
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS first
\gset s11_
RESET ROLE;
SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS upper
\gset s11_
SELECT c59s11_fixture.ok(:'s11_first'::jsonb ?& ARRAY['status','scope'] AND :'s11_first'::jsonb-ARRAY['status','scope']='{}'::jsonb AND :'s11_first'::jsonb->>'status'='prepared' AND (:'s11_first'::jsonb->'scope') ?& ARRAY['ownerID','lifecycleKey','scopeKey','timeZone','weekStartDate','asOfLocalDate'] AND (:'s11_first'::jsonb->'scope')-ARRAY['ownerID','lifecycleKey','scopeKey','timeZone','weekStartDate','asOfLocalDate']='{}'::jsonb AND NOT EXISTS(SELECT 1 FROM jsonb_each(:'s11_first'::jsonb->'scope') e WHERE jsonb_typeof(e.value)<>'string'),'service_real_success_exact_envelope2_DTO6_strings');
SELECT c59s11_fixture.ok(EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes s WHERE user_id='c59ab000-0000-0000-0000-000000000001' AND lifecycle_key='c59ab000-0000-0000-0000-000000000101' AND scope_key=(:'s11_first'::jsonb#>>'{scope,scopeKey}')::uuid AND :'s11_first'::jsonb->'scope'=jsonb_build_object('ownerID',s.user_id,'lifecycleKey',s.lifecycle_key,'scopeKey',s.scope_key,'timeZone',s.time_zone,'weekStartDate',to_char(s.week_start_date,'YYYY-MM-DD'),'asOfLocalDate',to_char(s.as_of_local_date,'YYYY-MM-DD'))),'real_row_matches_DTO_owned_exact_ISO');
SELECT c59s11_fixture.ok((SELECT created_at>=:'s11_lower'::timestamptz AND created_at<=:'s11_upper'::timestamptz AND isfinite(created_at) AND time_zone='UTC' AND as_of_local_date=(created_at AT TIME ZONE time_zone)::date AND week_start_date=date_trunc('week',created_at AT TIME ZONE time_zone)::date AND extract(isodow FROM week_start_date)=1 AND as_of_local_date-week_start_date BETWEEN 0 AND 6 FROM private.workout_strength_calendar_scopes WHERE user_id='c59ab000-0000-0000-0000-000000000001'),'new_row_single_clock_real_bounds_official_zone_Monday');
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS first_state
\gset s11_
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS replay
\gset s11_
SELECT c59s11_fixture.ok(:'s11_replay'::jsonb=jsonb_build_object('status','reuse_existing','scope',:'s11_first'::jsonb->'scope') AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001')=:'s11_first_state'::jsonb,'same_tuple_reuse_exact_key_created_at_no_refresh');
-- C15: a genuine legacy workout with no snapshot/fact must not make scope preparation depend on workout history.
SAVEPOINT legacy_workout;
INSERT INTO public.workout_logs(id,user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at) VALUES('c59ab000-0000-0000-0000-000000000951','c59ab000-0000-0000-0000-000000000001',NULL,'c59s11_legacy_no_fact',60,300,clock_timestamp());
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS legacy_before_reuse
\gset s11_
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS legacy_reuse
\gset s11_
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS legacy_after_reuse
\gset s11_
UPDATE public.users SET timezone='Etc/UTC' WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS legacy_before_new
\gset s11_
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS legacy_new
\gset s11_
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS legacy_after_new
\gset s11_
SELECT c59s11_fixture.ok(:'s11_legacy_reuse'::jsonb=jsonb_build_object('status','reuse_existing','scope',:'s11_first'::jsonb->'scope') AND :'s11_legacy_before_reuse'::jsonb=:'s11_legacy_after_reuse'::jsonb AND :'s11_legacy_new'::jsonb=jsonb_build_object('status','prepared','scope',(SELECT jsonb_build_object('ownerID',user_id,'lifecycleKey',lifecycle_key,'scopeKey',scope_key,'timeZone',time_zone,'weekStartDate',to_char(week_start_date,'YYYY-MM-DD'),'asOfLocalDate',to_char(as_of_local_date,'YYYY-MM-DD')) FROM private.workout_strength_calendar_scopes WHERE scope_key=(:'s11_legacy_new'::jsonb#>>'{scope,scopeKey}')::uuid AND user_id='c59ab000-0000-0000-0000-000000000001' AND lifecycle_key='c59ab000-0000-0000-0000-000000000101' AND time_zone='Etc/UTC')) AND :'s11_legacy_before_new'::jsonb-'scopes'=:'s11_legacy_after_new'::jsonb-'scopes' AND (:'s11_legacy_after_new'::jsonb->'scopes') @> (:'s11_legacy_before_new'::jsonb->'scopes') AND jsonb_array_length(:'s11_legacy_after_new'::jsonb->'scopes')=jsonb_array_length(:'s11_legacy_before_new'::jsonb->'scopes')+1 AND to_regclass('private.workout_strength_facts') IS NULL,'C15_real_legacy_workout_no_fact_reuse_and_prepare_preserve_all_other_state');
ROLLBACK TO SAVEPOINT legacy_workout;RELEASE SAVEPOINT legacy_workout;
UPDATE public.users SET timezone='Etc/UTC' WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS zone_response
\gset s11_
SELECT c59s11_fixture.ok(:'s11_zone_response'::jsonb->>'status'='prepared' AND :'s11_zone_response'::jsonb#>>'{scope,timeZone}'='Etc/UTC' AND :'s11_zone_response'::jsonb#>>'{scope,scopeKey}'<>:'s11_first'::jsonb#>>'{scope,scopeKey}' AND EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes WHERE scope_key=(:'s11_zone_response'::jsonb#>>'{scope,scopeKey}')::uuid AND as_of_local_date=(created_at AT TIME ZONE time_zone)::date AND week_start_date=date_trunc('week',created_at AT TIME ZONE time_zone)::date),'listed_alias_literal_new_observation_current_authority');
UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS zone_response
\gset s11_
SELECT c59s11_fixture.ok(:'s11_zone_response'::jsonb->>'status'='prepared' AND :'s11_zone_response'::jsonb#>>'{scope,timeZone}'='America/Sao_Paulo' AND :'s11_zone_response'::jsonb#>>'{scope,scopeKey}'<>:'s11_first'::jsonb#>>'{scope,scopeKey}' AND EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes WHERE scope_key=(:'s11_zone_response'::jsonb#>>'{scope,scopeKey}')::uuid AND as_of_local_date=(created_at AT TIME ZONE time_zone)::date AND week_start_date=date_trunc('week',created_at AT TIME ZONE time_zone)::date),'changed_official_zone_new_observation_current_authority');
UPDATE public.users SET timezone='UTC' WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS returned
\gset s11_
SELECT c59s11_fixture.ok(:'s11_returned'::jsonb=jsonb_build_object('status','reuse_existing','scope',:'s11_first'::jsonb->'scope') AND (SELECT count(*)=3 FROM private.workout_strength_calendar_scopes WHERE user_id='c59ab000-0000-0000-0000-000000000001') AND (SELECT to_jsonb(s)=(:'s11_first_state'::jsonb->'scopes'->0) FROM private.workout_strength_calendar_scopes s WHERE scope_key=(:'s11_first'::jsonb#>>'{scope,scopeKey}')::uuid),'zone_A_B_A_reuses_original_immutable_observation');
-- Fixed prior-day storage control, never a claim of runtime execution on that day.
DO $$BEGIN IF EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes WHERE user_id='c59ab000-0000-0000-0000-000000000001' AND time_zone='UTC' AND as_of_local_date=DATE '2026-10-11') THEN RAISE EXCEPTION 'C59S11_SETUP_STORAGE_TUPLE_ALREADY_CURRENT';END IF;END$$;
SAVEPOINT storage_controls;
INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,'{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000901","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}'::jsonb)).*;
SELECT c59s11_fixture.ok(EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes WHERE scope_key='c59ab000-0000-0000-0000-000000000901' AND week_start_date=DATE '2026-10-05' AND as_of_local_date=DATE '2026-10-11'),'seeded_prior_day_storage_only_not_rare_runtime_claim');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":null,"lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23502','storage_NOTNULL_user_id');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":null,"scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23502','storage_NOTNULL_lifecycle_key');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":null,"time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23502','storage_NOTNULL_scope_key');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":null,"week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23502','storage_NOTNULL_time_zone');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":null,"as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23502','storage_NOTNULL_week_start_date');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":null,"created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23502','storage_NOTNULL_as_of_local_date');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":null}''::jsonb)).*','23502','storage_NOTNULL_created_at');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_empty_zone');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"infinity","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_infinite_week');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"infinity","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_infinite_asof');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"10000-01-03","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_week_year10000');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"10000-01-03","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_asof_year10000');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"0001-01-01 BC","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_week_BC');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"0001-01-01 BC","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_asof_BC');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-06","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_not_Monday');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-04","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_before_week');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-12","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23514','storage_CHECK_after_week');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"infinity"}''::jsonb)).*','23514','storage_CHECK_infinite_created');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"10000-01-01 00:00:00+00"}''::jsonb)).*','23514','storage_CHECK_created_year10000');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"0001-01-01 00:00:00 BC"}''::jsonb)).*','23514','storage_CHECK_created_BC');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000901","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23505','storage_primary_key_duplicate');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000001","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23505','storage_same_tuple_unique_different_scope_key');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000000002","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23503','storage_cross_owner_lifecycle_FK');
SELECT c59s11_fixture.throws('INSERT INTO private.workout_strength_calendar_scopes SELECT (jsonb_populate_record(NULL::private.workout_strength_calendar_scopes,''{"user_id":"c59ab000-0000-0000-0000-000000009999","lifecycle_key":"c59ab000-0000-0000-0000-000000000101","scope_key":"c59ab000-0000-0000-0000-000000000902","time_zone":"UTC","week_start_date":"2026-10-05","as_of_local_date":"2026-10-11","created_at":"2026-10-11T12:00:00.123456Z"}''::jsonb)).*','23503','storage_absent_owner_lifecycle_FK');
ROLLBACK TO SAVEPOINT storage_controls;RELEASE SAVEPOINT storage_controls;
SELECT c59s11_fixture.ok((SELECT bool_and(extract(isodow FROM m)=1 AND d-m BETWEEN 0 AND 6) FROM (VALUES(DATE '0001-01-01'),(DATE '2026-10-11'),(DATE '2026-10-12'),(DATE '9999-12-31')) v(d) CROSS JOIN LATERAL(SELECT d-(extract(isodow FROM d)::integer-1) AS m) w),'civil_boundary_math_control_year1_9999_not_runtime_clock_override');
SAVEPOINT write_failure;UPDATE public.users SET timezone='Asia/Tokyo' WHERE id='c59ab000-0000-0000-0000-000000000001';ALTER TABLE private.workout_strength_calendar_scopes ADD CONSTRAINT c59s11_reject_insert CHECK(false) NOT VALID;
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001') AS failed_before
\gset s11_
SELECT c59s11_fixture.throws('SELECT public.prepare_workout_strength_calendar_scope(''c59ab000-0000-0000-0000-000000000001'',''c59ab000-0000-0000-0000-000000000101'')','23514','actual_scope_insert_failure_propagates');
SELECT c59s11_fixture.ok(c59s11_fixture.state('c59ab000-0000-0000-0000-000000000001')=:'s11_failed_before'::jsonb,'insert_error_atomic_zero_writes');
ALTER TABLE private.workout_strength_calendar_scopes DROP CONSTRAINT c59s11_reject_insert;
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000001','c59ab000-0000-0000-0000-000000000101') AS recovered
\gset s11_
SELECT c59s11_fixture.ok(:'s11_recovered'::jsonb->>'status'='prepared' AND :'s11_recovered'::jsonb#>>'{scope,timeZone}'='Asia/Tokyo','same_call_after_storage_failure_can_prepare_no_negative_cache');
ROLLBACK TO SAVEPOINT write_failure;RELEASE SAVEPOINT write_failure;
SELECT public.prepare_workout_strength_calendar_scope('c59ab000-0000-0000-0000-000000000002','c59ab000-0000-0000-0000-000000000102') AS other
\gset s11_
SELECT c59s11_fixture.state('c59ab000-0000-0000-0000-000000000002') AS other_state
\gset s11_
SAVEPOINT lifecycle_cascade;DELETE FROM private.workout_strength_lifecycles WHERE user_id='c59ab000-0000-0000-0000-000000000001' AND lifecycle_key='c59ab000-0000-0000-0000-000000000101';
SELECT c59s11_fixture.ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes WHERE user_id='c59ab000-0000-0000-0000-000000000001') AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000002')=:'s11_other_state'::jsonb,'lifecycle_cascade_scopes_removed_other_owner_unchanged');
ROLLBACK TO SAVEPOINT lifecycle_cascade;RELEASE SAVEPOINT lifecycle_cascade;
SAVEPOINT owner_cascade;DELETE FROM public.users WHERE id='c59ab000-0000-0000-0000-000000000001';
SELECT c59s11_fixture.ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_calendar_scopes WHERE user_id='c59ab000-0000-0000-0000-000000000001') AND NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id='c59ab000-0000-0000-0000-000000000001') AND c59s11_fixture.state('c59ab000-0000-0000-0000-000000000002')=:'s11_other_state'::jsonb,'owner_cascade_scopes_lifecycles_other_owner_unchanged');
ROLLBACK TO SAVEPOINT owner_cascade;RELEASE SAVEPOINT owner_cascade;
SELECT c59s11_fixture.object_fingerprint() AS collision_before
\gset s11_
SELECT set_config('c59s11_test.migration_path',:'migration_path',true);
SELECT c59s11_fixture.throws('DO $actual_migration$BEGIN EXECUTE pg_read_file(current_setting(''c59s11_test.migration_path''));END $actual_migration$','42P07','actual_migration_existing_table_or_RPC_rejected');
SELECT c59s11_fixture.ok(c59s11_fixture.object_fingerprint()=:'s11_collision_before'::jsonb,'CREATE_only_collision_no_metadata_overwrite');
SAVEPOINT unknown_overload;DROP FUNCTION public.prepare_workout_strength_calendar_scope(uuid,uuid);DROP TABLE private.workout_strength_calendar_scopes;CREATE FUNCTION public.prepare_workout_strength_calendar_scope(text) RETURNS text LANGUAGE sql AS 'SELECT $1';
SELECT c59s11_fixture.throws('DO $actual_migration$BEGIN EXECUTE pg_read_file(current_setting(''c59s11_test.migration_path''));END $actual_migration$','42P07','actual_migration_unknown_overload_rejected_before_DDL');
SELECT c59s11_fixture.ok(to_regclass('private.workout_strength_calendar_scopes') IS NULL AND to_regprocedure('public.prepare_workout_strength_calendar_scope(text)') IS NOT NULL AND to_regprocedure('public.prepare_workout_strength_calendar_scope(uuid,uuid)') IS NULL,'unknown_overload_collision_preserves_reserved_state');
ROLLBACK TO SAVEPOINT unknown_overload;RELEASE SAVEPOINT unknown_overload;
SELECT c59s11_fixture.ok(NOT EXISTS(SELECT 1 FROM public.workout_logs) AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots) AND NOT EXISTS(SELECT 1 FROM private.workout_strength_operations) AND to_regclass('private.workout_strength_facts') IS NULL AND to_regclass('private.workout_strength_commands') IS NULL AND (SELECT count(*)=2 FROM private.workout_strength_lifecycles),'scope_preparation_no_workout_fact_command_writer_or_lifecycle_creation');
ROLLBACK;
SELECT CASE WHEN to_regnamespace('c59s11_fixture') IS NULL AND to_regclass('private.workout_strength_calendar_scopes') IS NULL AND to_regclass('private.workout_strength_lifecycles') IS NULL AND to_regclass('public.workout_logs') IS NULL AND (SELECT count(*) FROM public.users)=:s11_baseline_n THEN 'C59S11_ROLLBACK_CONFIRMED' ELSE 'C59S11_ROLLBACK_FAILED' END;
\endif
\endif
