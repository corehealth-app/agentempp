-- S7 real SQL test-first. Missing product/DDL is SETUP, never causal RED.
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
DO $$BEGIN RAISE EXCEPTION 'C59S7_SETUP_CONFLICTING_MODES';END$$;
\endif
\endif
\if :teardown_concurrency
BEGIN;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
DO $ownership$
DECLARE o record;
BEGIN
 SELECT * INTO STRICT o FROM c59s7_fixture.ownership WHERE tag='c59s7_command_v1';
 IF o.owner_name<>session_user OR o.object_oids IS DISTINCT FROM c59s7_fixture.object_oids()
   OR o.object_fingerprint IS DISTINCT FROM c59s7_fixture.object_fingerprint()
   OR (SELECT count(*) FROM c59s7_fixture.ownership)<>1
   OR EXISTS(SELECT 1 FROM jsonb_each(o.object_oids) WHERE value='null'::jsonb)
   OR EXISTS(SELECT 1 FROM pg_class c WHERE c.relnamespace='c59s7_fixture'::regnamespace AND c.relowner<>(SELECT oid FROM pg_roles WHERE rolname=session_user))
   OR (SELECT count(*) FROM pg_proc WHERE pronamespace='c59s7_fixture'::regnamespace)<>5
 THEN RAISE EXCEPTION 'C59S7_TEARDOWN_OWNERSHIP_MISMATCH';END IF;
 IF (SELECT count(*) FROM public.users WHERE id IN('c59a8000-0000-0000-0000-000000000003','c59a8000-0000-0000-0000-000000000004')
   AND metadata->>'c59s7_fixture'='c59s7_command_v1' AND wpp='c59s7-'||id::text)<>2
 THEN RAISE EXCEPTION 'C59S7_TEARDOWN_OWNER_MISMATCH';END IF;
 DELETE FROM public.users WHERE id IN('c59a8000-0000-0000-0000-000000000003','c59a8000-0000-0000-0000-000000000004')
   AND metadata->>'c59s7_fixture'='c59s7_command_v1';
 IF EXISTS(SELECT 1 FROM private.workout_strength_commands)
   OR EXISTS(SELECT 1 FROM private.workout_strength_operations) OR EXISTS(SELECT 1 FROM private.workout_strength_lifecycles)
   OR EXISTS(SELECT 1 FROM public.workout_logs) OR EXISTS(SELECT 1 FROM public.daily_snapshots)
 THEN RAISE EXCEPTION 'C59S7_TEARDOWN_FOREIGN_ROWS';END IF;
END $ownership$;
-- Explicit known task objects only; no CASCADE/schema-wide deletion.
DROP FUNCTION public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb);
DROP TABLE private.workout_strength_commands;
DROP TABLE private.workout_strength_operations;
DROP TABLE private.workout_strength_lifecycles;
DROP TABLE public.workout_logs;
DROP TABLE public.daily_snapshots;
DROP FUNCTION c59s7_fixture.object_fingerprint();
DROP FUNCTION c59s7_fixture.object_oids();
DROP FUNCTION c59s7_fixture.arguments(uuid,text);
DROP FUNCTION c59s7_fixture.throws(text,text,text,text);
DROP FUNCTION c59s7_fixture.ok(boolean,text);
DROP TABLE c59s7_fixture.ownership;
DROP SCHEMA c59s7_fixture;
COMMIT;
\echo C59S7_CONCURRENCY_TEARDOWN_CONFIRMED
\else
\if :{?migration_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S7_SETUP_MIGRATION_PATH';END$$;
\endif
\if :{?bindings_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S7_SETUP_BINDINGS_PATH';END$$;
\endif
\if :setup_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$
BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL
   OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S7_SETUP_PLATFORM';END IF;
 IF to_regclass('public.daily_snapshots') IS NOT NULL OR to_regclass('public.workout_logs') IS NOT NULL
   OR to_regclass('private.workout_strength_lifecycles') IS NOT NULL
   OR to_regclass('private.workout_strength_operations') IS NOT NULL
   OR to_regclass('private.workout_strength_commands') IS NOT NULL
   OR to_regnamespace('c59s7_fixture') IS NOT NULL
   OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname IN('register_workout_atomic','read_or_admit_workout_strength_command'))
 THEN RAISE EXCEPTION 'C59S7_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_commands_fixture.sql
\i :bindings_path
\i :migration_path
DO $$BEGIN
 IF to_regprocedure('public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'C59S7_SETUP_UNIMPLEMENTED';END IF;
END$$;

INSERT INTO public.users(id,wpp,name,metadata) VALUES
 ('c59a8000-0000-0000-0000-000000000003','c59s7-c59a8000-0000-0000-0000-000000000003','C59S7 concurrency commit','{"c59a2_synthetic":true,"c59s7_fixture":"c59s7_command_v1"}'),
 ('c59a8000-0000-0000-0000-000000000004','c59s7-c59a8000-0000-0000-0000-000000000004','C59S7 concurrency rollback','{"c59a2_synthetic":true,"c59s7_fixture":"c59s7_command_v1"}');
INSERT INTO private.workout_strength_lifecycles VALUES
 ('c59a8000-0000-0000-0000-000000000003','c59a8000-0000-0000-0000-000000000103','2026-10-01T00:00:00Z',NULL,NULL),
 ('c59a8000-0000-0000-0000-000000000004','c59a8000-0000-0000-0000-000000000104','2026-10-01T00:00:00Z',NULL,NULL);
INSERT INTO c59s7_fixture.ownership VALUES('c59s7_command_v1',session_user,c59s7_fixture.object_oids(),c59s7_fixture.object_fingerprint());
COMMIT;
\echo C59S7_CONCURRENCY_SETUP_CONFIRMED
\else
\if :{?legacy_api_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S7_SETUP_LEGACY_API_PATH';END$$;
\endif
\if :{?legacy_permissions_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S7_SETUP_LEGACY_PERMISSIONS_PATH';END$$;
\endif
-- Independent RR transaction really reaches isolation guard, not SET failure25001.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$
BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL
   OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S7_SETUP_PLATFORM';END IF;
 IF to_regclass('public.daily_snapshots') IS NOT NULL OR to_regclass('public.workout_logs') IS NOT NULL
   OR to_regclass('private.workout_strength_lifecycles') IS NOT NULL
   OR to_regclass('private.workout_strength_operations') IS NOT NULL
   OR to_regclass('private.workout_strength_commands') IS NOT NULL
   OR to_regnamespace('c59s7_fixture') IS NOT NULL
   OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname IN('register_workout_atomic','read_or_admit_workout_strength_command'))
 THEN RAISE EXCEPTION 'C59S7_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_commands_fixture.sql
\i :bindings_path
\i :migration_path
DO $$BEGIN
 IF to_regprocedure('public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'C59S7_SETUP_UNIMPLEMENTED';END IF;
END$$;

SELECT c59s7_fixture.throws('SELECT public.read_or_admit_workout_strength_command(''c59a8000-0000-0000-0000-000000000001'',''c59a8000-0000-0000-0000-000000000101'',''key'',''musculacao'',NULL)',
 '22023','workout_strength_requires_read_committed','actual_RR_before_owner_lookup');
ROLLBACK;

BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$
BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL
   OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S7_SETUP_PLATFORM';END IF;
 IF to_regclass('public.daily_snapshots') IS NOT NULL OR to_regclass('public.workout_logs') IS NOT NULL
   OR to_regclass('private.workout_strength_lifecycles') IS NOT NULL
   OR to_regclass('private.workout_strength_operations') IS NOT NULL
   OR to_regclass('private.workout_strength_commands') IS NOT NULL
   OR to_regnamespace('c59s7_fixture') IS NOT NULL
   OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname IN('register_workout_atomic','read_or_admit_workout_strength_command'))
 THEN RAISE EXCEPTION 'C59S7_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_commands_fixture.sql
\i :bindings_path
\i :legacy_api_path
\i :legacy_permissions_path
SELECT count(*) AS users FROM public.users
\gset s7_baseline_
SELECT md5(jsonb_build_object('api',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'config',p.proconfig,
 'guard',pg_get_functiondef('private.assert_trusted_backend()'::regprocedure))::text) AS fingerprint FROM pg_proc p
 WHERE p.oid='public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure
\gset s7_
\i :migration_path
DO $$BEGIN
 IF to_regprocedure('public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'C59S7_SETUP_UNIMPLEMENTED';END IF;
END$$;

INSERT INTO public.users(id,wpp,name,metadata) VALUES
 ('c59a8000-0000-0000-0000-000000000001','c59s7-sequential-a','C59S7 A','{"c59a2_synthetic":true}'),
 ('c59a8000-0000-0000-0000-000000000002','c59s7-sequential-b','C59S7 B','{"c59a2_synthetic":true}');
INSERT INTO private.workout_strength_lifecycles VALUES
 ('c59a8000-0000-0000-0000-000000000001','c59a8000-0000-0000-0000-000000000101','2026-10-01T00:00:00Z',NULL,NULL),
 ('c59a8000-0000-0000-0000-000000000002','c59a8000-0000-0000-0000-000000000102','2026-10-01T00:00:00Z',NULL,NULL);
SET LOCAL TimeZone='Pacific/Auckland';
SET LOCAL DateStyle='SQL, DMY';
DO $basic$
DECLARE a uuid:='c59a8000-0000-0000-0000-000000000001';l uuid:='c59a8000-0000-0000-0000-000000000101';
 raw text:='  MÚSCULAÇÃO'||chr(9);args jsonb;wire jsonb;before_clock timestamptz;after_clock timestamptz;x record;late jsonb;
BEGIN
 args:=c59s7_fixture.arguments(a,raw);
 PERFORM c59s7_fixture.ok(public.read_or_admit_workout_strength_command(a,l,'lookup',raw,NULL) IS NULL
   AND NOT EXISTS(SELECT 1 FROM private.workout_strength_commands),'lookup_SQLNULL_no_insert_no_autoopen');
 before_clock:=clock_timestamp();
 wire:=public.read_or_admit_workout_strength_command(a,l,'first',raw,args);after_clock:=clock_timestamp();
 PERFORM c59s7_fixture.ok(wire-ARRAY['ownerID','lifecycleKey','operationKey','originalOperationType','legacyArguments','admittedAt','recentCutoff']='{}'::jsonb
   AND (SELECT count(*)=7 FROM jsonb_object_keys(wire)) AND wire->>'ownerID'=a::text AND wire->>'lifecycleKey'=l::text
   AND wire->>'operationKey'='first' AND wire->>'originalOperationType'=raw
   AND wire->'legacyArguments'=args AND (wire->'legacyArguments')::text=args::text
   AND wire->>'admittedAt'~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$'
   AND wire->>'recentCutoff'~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$'
   AND (wire->>'admittedAt')::timestamptz BETWEEN before_clock AND after_clock
   AND (wire->>'recentCutoff')::timestamptz=(wire->>'admittedAt')::timestamptz-interval '6 hours',
   'exact7_wire_original13args_one_post_validation_clock_cutoff6h_US6');
 PERFORM set_config('c59s7_test.winner',wire::text,true);
 FOR x IN SELECT * FROM (VALUES('SQLNULL',NULL::jsonb),('JSONnull','null'::jsonb),('scalar','12'::jsonb),('invalid','{}'::jsonb),
   ('divergent',args||jsonb_build_object('p_date','2026-10-13','p_duration_min',90,'p_estimated_kcal',999,'p_notes','late preparation')))t(label,candidate) LOOP
   PERFORM c59s7_fixture.ok(public.read_or_admit_workout_strength_command(a,l,'first',raw,x.candidate)=wire,
     'existing_first_winner_ignores_candidate:'||x.label);
 END LOOP;
 PERFORM c59s7_fixture.ok((SELECT count(*)=1 FROM private.workout_strength_commands),'replay_no_second_row');
 PERFORM c59s7_fixture.ok(public.read_or_admit_workout_strength_command(a,l,'first','musculacao',NULL) IS NULL
   AND (raw COLLATE "C")<>(lower(raw) COLLATE "C")
   AND public.read_or_admit_workout_strength_command(a,l,'first',lower(raw),NULL) IS NULL,
   'F1_raw_spaces_case_are_distinct_no_normalization');
 late:=public.read_or_admit_workout_strength_command(a,l,' ',chr(9),c59s7_fixture.arguments(a,chr(9)));
 PERFORM c59s7_fixture.ok(late->>'operationKey'=' ' AND late->>'originalOperationType'=chr(9),'key_spaces_and_SQL_btrim_not_JS_trim');
END $basic$;

DO $metadata$
DECLARE cols text[];types text[];
BEGIN
 SELECT array_agg(attname::text ORDER BY attnum),array_agg(format_type(atttypid,atttypmod) ORDER BY attnum) INTO cols,types
 FROM pg_attribute WHERE attrelid='private.workout_strength_commands'::regclass AND attnum>0 AND NOT attisdropped;
 PERFORM c59s7_fixture.ok(cols=ARRAY['user_id','lifecycle_key','operation_key','original_operation_type','legacy_arguments','admitted_at','recent_cutoff']
  AND types=ARRAY['uuid','uuid','text','text','jsonb','timestamp with time zone','timestamp with time zone']
  AND (SELECT bool_and(attnotnull AND NOT atthasdef) FROM pg_attribute WHERE attrelid='private.workout_strength_commands'::regclass AND attnum>0 AND NOT attisdropped),
  'exact7_columns_NOTNULL_no_defaults');
 PERFORM c59s7_fixture.ok((SELECT count(*)=1 FROM pg_index WHERE indrelid='private.workout_strength_commands'::regclass)
  AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.workout_strength_commands'::regclass AND contype='p' AND conkey=ARRAY[1,2,3,4]::smallint[])
  AND (SELECT count(*)=2 FROM pg_attribute WHERE attrelid='private.workout_strength_commands'::regclass AND attname IN('operation_key','original_operation_type')
   AND attcollation='"C"'::regcollation), 'PK_owned_raw_C_only_required_index');
END $metadata$;

-- JSONB null is not lookup-only; malformed/cast failure is fixed22023, no payload.
DO $invalid$
DECLARE a uuid:='c59a8000-0000-0000-0000-000000000001';l uuid:='c59a8000-0000-0000-0000-000000000101';args jsonb:=c59s7_fixture.arguments(a,'musculacao');x record;i integer:=0;
BEGIN
 FOR x IN SELECT * FROM(VALUES
 ('jsonnull','null'::jsonb),('array','[]'::jsonb),('scalar','1'::jsonb),('missing',args-'p_notes'),('extra',args||'{"extra":true}'),
 ('foreignowner',args||jsonb_build_object('p_user_id','c59a8000-0000-0000-0000-000000000002')),
 ('rawmismatch',args||'{"p_workout_type":"MUSCULACAO"}'),('ownernonuuid',args||'{"p_user_id":"wrong"}'),
 ('rawnumber',args||'{"p_workout_type":12}'),('datenumber',args||'{"p_date":20261012}'),
 ('nullowner',args||'{"p_user_id":null}'),('datebad',args||'{"p_date":"not-a-date"}'),('datenull',args||'{"p_date":null}'),
 ('durationnull',args||'{"p_duration_min":null}'),('durationstring',args||'{"p_duration_min":"60"}'),
 ('durationfraction',args||'{"p_duration_min":1.5}'),('durationzero',args||'{"p_duration_min":0}'),('durationover',args||'{"p_duration_min":1441}'),
 ('kcalnegative',args||'{"p_estimated_kcal":-1}'),('kcalover',args||'{"p_estimated_kcal":10001}'),('kcalfraction',args||'{"p_estimated_kcal":1.5}'),
 ('intensitynumber',args||'{"p_intensity":4}'),('notesobject',args||'{"p_notes":{}}'),
 ('performedbad',args||'{"p_performed_at":"bad"}'),('providerbool',args||'{"p_provider_message_id":true}'),
 ('targetfraction',args||'{"p_calories_target":2000.5}'),('targetoverflow',args||'{"p_calories_target":2147483648}'),
 ('proteinstring',args||'{"p_protein_target":"150"}'),('proteinnonnumeric',args||'{"p_protein_target":[]}'),
 ('replaceinteger',args||'{"p_replace_recent":1}'),('replace_requires_since',args||'{"p_replace_recent":true}'),
 ('sincebad',args||'{"p_replace_since":"bad"}'),('rawlong',jsonb_set(args,'{p_workout_type}',to_jsonb(repeat('x',201))))
 )t(label,candidate) LOOP
 i:=i+1;
 PERFORM c59s7_fixture.throws(format('SELECT public.read_or_admit_workout_strength_command(%L,%L,%L,%L,%L::jsonb)',
   a,l,'invalid-'||i,CASE WHEN x.label='rawlong' THEN repeat('x',201) WHEN x.label='rawnumber' THEN '12' ELSE 'musculacao' END,x.candidate),
   '22023','invalid_workout_strength_input','invalid_candidate:'||x.label);
 END LOOP;
 PERFORM c59s7_fixture.ok((SELECT count(*)=2 FROM private.workout_strength_commands),'invalid_candidates_do_not_insert');
END $invalid$;

DO $valid$
DECLARE a uuid:='c59a8000-0000-0000-0000-000000000001';l uuid:='c59a8000-0000-0000-0000-000000000101';args jsonb:=c59s7_fixture.arguments(a,'musculacao');x record;wire jsonb;i integer:=0;
BEGIN
 FOR x IN SELECT * FROM(VALUES
 ('nullable8',args),
 ('SQLcompatible_literals',args||'{"p_date":"2026-10-12 AD","p_performed_at":"2026-10-12 15:00:00.123456+00","p_replace_since":"2026-10-11 15:00:00+00","p_replace_recent":true}'),
 ('integer_valued_decimal',args||'{"p_duration_min":1.0,"p_estimated_kcal":0.0,"p_calories_target":-2147483648}'),
 ('max_original_bounds',args||'{"p_duration_min":1440,"p_estimated_kcal":10000,"p_calories_target":2147483647}'),
 ('numeric_exact_no_JS_rounding',args||'{"p_protein_target":12345678901234567890.123456789}'),
 ('empty_nullable_texts',args||'{"p_intensity":"","p_notes":"","p_provider_message_id":"provider-differs-from-key","p_replace_recent":false}'),
 ('legacy_infinite_dates_castable',args||'{"p_date":"infinity","p_performed_at":"infinity","p_replace_since":"-infinity"}')
 )t(label,candidate) LOOP
 i:=i+1;wire:=public.read_or_admit_workout_strength_command(a,l,'valid-'||i,'musculacao',x.candidate);
 PERFORM c59s7_fixture.ok(wire->'legacyArguments'=x.candidate AND (wire->'legacyArguments')::text=x.candidate::text,
   'preserved_original_types_literals:'||x.label);
 END LOOP;
END $valid$;

SAVEPOINT command_constraints;
DO $constraints$
DECLARE a uuid:='c59a8000-0000-0000-0000-000000000001';l uuid:='c59a8000-0000-0000-0000-000000000101';base jsonb;x record;
BEGIN
 SELECT to_jsonb(c) INTO base FROM private.workout_strength_commands c WHERE user_id=a AND operation_key='first';
 FOR x IN SELECT * FROM(VALUES
 ('key_NULL','{"operation_key":null}'::jsonb,'23502'),('args_SQLNULL','{"legacy_arguments":null}'::jsonb,'23502'),
 ('admitted_NULL','{"admitted_at":null}'::jsonb,'23502'),('key_empty','{"operation_key":""}'::jsonb,'23514'),
 ('raw_blank','{"original_operation_type":"   "}'::jsonb,'23514'),('args_scalar','{"legacy_arguments":12}'::jsonb,'23514'),
 ('admitted_infinite','{"admitted_at":"infinity","recent_cutoff":"infinity"}'::jsonb,'23514'),('clock_year10000','{"admitted_at":"10000-01-01T06:00:00Z","recent_cutoff":"10000-01-01T00:00:00Z"}'::jsonb,'23514'),
 ('cutoff_wrong',jsonb_build_object('recent_cutoff','2020-01-01T00:00:00Z'),'23514'),
 ('foreign_life',jsonb_build_object('lifecycle_key','c59a8000-0000-0000-0000-000000000102'),'23503')
 )t(label,patch,state) LOOP
 PERFORM c59s7_fixture.throws(format('INSERT INTO private.workout_strength_commands SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_commands,%L::jsonb)',
  base||jsonb_build_object('operation_key','constraint-'||x.label)||x.patch),x.state,NULL,'table_constraint:'||x.label);
 END LOOP;
 PERFORM c59s7_fixture.throws(format('INSERT INTO private.workout_strength_commands SELECT * FROM jsonb_populate_record(NULL::private.workout_strength_commands,%L::jsonb)',base),
  '23505',NULL,'duplicate_F1_PK');
 -- jsonb_populate_record maps JSON null to SQL NULL, so use direct JSONB literal.
 PERFORM c59s7_fixture.throws(format('INSERT INTO private.workout_strength_commands VALUES(%L,%L,%L,%L,''null''::jsonb,''2026-10-14T18:00:00Z'',''2026-10-14T12:00:00Z'')',
  a,l,'jsonnull-storage','musculacao'),'23514',NULL,'table_JSONnull_is_not_object');
END $constraints$;
ROLLBACK TO command_constraints;
RELEASE command_constraints;

DO $guards$
DECLARE a uuid:='c59a8000-0000-0000-0000-000000000001';l uuid:='c59a8000-0000-0000-0000-000000000101';x record;
BEGIN
 FOR x IN SELECT * FROM(VALUES('owner',NULL::uuid,l,'key','musculacao'),('life',a,NULL::uuid,'key','musculacao'),
 ('keynull',a,l,NULL::text,'musculacao'),('keyempty',a,l,'','musculacao'),('typenull',a,l,'key',NULL::text),('typeblank',a,l,'key','   '))
 t(label,owner_id,life,key,raw) LOOP
 PERFORM c59s7_fixture.throws(format('SELECT public.read_or_admit_workout_strength_command(%L,%L,%L,%L,NULL)',x.owner_id,x.life,x.key,x.raw),
  '22023','invalid_workout_strength_input','syntax:'||x.label);
 END LOOP;
 PERFORM c59s7_fixture.throws(format('SELECT public.read_or_admit_workout_strength_command(%L,%L,%L,%L,NULL)',
  'c59a8000-0000-0000-0000-000000000099',l,'key','musculacao'),'P0002','workout_strength_patient_not_found','missing_owner');
 PERFORM c59s7_fixture.ok(public.read_or_admit_workout_strength_command(a,'c59a8000-0000-0000-0000-000000000102','first','musculacao','null')=
  '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb,'foreign_life_before_candidate');
END $guards$;
SAVEPOINT closed_life;
UPDATE private.workout_strength_lifecycles SET closed_at='2026-10-14T15:00:00Z',close_operation_key='s7-close'
 WHERE user_id='c59a8000-0000-0000-0000-000000000001';
SELECT c59s7_fixture.ok(public.read_or_admit_workout_strength_command('c59a8000-0000-0000-0000-000000000001','c59a8000-0000-0000-0000-000000000101','first','  MÚSCULAÇÃO'||chr(9),'null')=
 '{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb,'closed_life_denies_existing_and_invalid_candidate');
ROLLBACK TO closed_life;
RELEASE closed_life;
SAVEPOINT inactive_owner;
UPDATE public.users SET status='deleted' WHERE id='c59a8000-0000-0000-0000-000000000001';
SELECT c59s7_fixture.throws('SELECT public.read_or_admit_workout_strength_command(''c59a8000-0000-0000-0000-000000000001'',''c59a8000-0000-0000-0000-000000000101'',''first'',''raw'',''null'')',
 'P0002','workout_strength_patient_not_found','inactive_owner_before_life_and_candidate');
ROLLBACK TO inactive_owner;
RELEASE inactive_owner;

DO $acl$
DECLARE p record;r text;code text;wire jsonb;
BEGIN
 SELECT * INTO p FROM pg_proc WHERE oid='public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)'::regprocedure;
 PERFORM c59s7_fixture.ok(p.prosecdef AND p.provolatile='v' AND p.pronargdefaults=0 AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
  AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
   WHERE x.grantee NOT IN(p.proowner,(SELECT oid FROM pg_roles WHERE rolname='service_role')) OR x.is_grantable AND x.grantee<>p.proowner),
  'RPC_definer_volatile_exact_signature_ACL');
 PERFORM c59s7_fixture.ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.workout_strength_commands'::regclass)
  AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.workout_strength_commands'::regclass)
  AND NOT EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x
   WHERE c.oid='private.workout_strength_commands'::regclass AND x.grantee<>c.relowner),'table_RLS_no_external_DML');
 EXECUTE 'SET LOCAL ROLE service_role';
 wire:=public.read_or_admit_workout_strength_command('c59a8000-0000-0000-0000-000000000001','c59a8000-0000-0000-0000-000000000101','first','  MÚSCULAÇÃO'||chr(9),NULL);
 EXECUTE 'RESET ROLE';
 PERFORM c59s7_fixture.ok(wire=current_setting('c59s7_test.winner')::jsonb,'service_real_call_without_table_DML');
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
 PERFORM c59s7_fixture.ok(NOT has_function_privilege(r,p.oid,'EXECUTE'),'EXECUTE_denied:'||r);
 EXECUTE format('SET LOCAL ROLE %I',r);code:=NULL;
 BEGIN PERFORM public.read_or_admit_workout_strength_command(NULL,NULL,NULL,NULL,NULL);
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE;END;
 EXECUTE 'RESET ROLE';PERFORM c59s7_fixture.ok(code='42501','actual_ACL_denied:'||r);
 END LOOP;
END $acl$;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
SELECT c59s7_fixture.throws('SELECT public.read_or_admit_workout_strength_command(NULL,NULL,NULL,NULL,NULL)',
 '42501','trusted backend role required','trusted_guard_precedes_syntax');
SET LOCAL request.jwt.claims='{"role":"service_role"}';

SAVEPOINT rolled_back_admission;
SELECT public.read_or_admit_workout_strength_command('c59a8000-0000-0000-0000-000000000002','c59a8000-0000-0000-0000-000000000102','rolledback','musculacao',
 c59s7_fixture.arguments('c59a8000-0000-0000-0000-000000000002','musculacao'));
ROLLBACK TO rolled_back_admission;
RELEASE rolled_back_admission;
SELECT c59s7_fixture.ok(public.read_or_admit_workout_strength_command('c59a8000-0000-0000-0000-000000000002','c59a8000-0000-0000-0000-000000000102','rolledback','musculacao',NULL) IS NULL,
 'rollback_admission_not_durable');
SAVEPOINT cascade_owner;
DELETE FROM public.users WHERE id='c59a8000-0000-0000-0000-000000000001';
SELECT c59s7_fixture.ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_commands WHERE user_id='c59a8000-0000-0000-0000-000000000001')
 AND EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id='c59a8000-0000-0000-0000-000000000002'),'owner_cascade_commands_other_life_preserved');
ROLLBACK TO cascade_owner;
RELEASE cascade_owner;

DO $legacy$
DECLARE a uuid:='c59a8000-0000-0000-0000-000000000001';l uuid:='c59a8000-0000-0000-0000-000000000101';args jsonb;wire jsonb;legacy jsonb;
BEGIN
 args:=c59s7_fixture.arguments(a,'musculacao')||'{"p_performed_at":"2026-10-12 15:00:00.123456+00","p_provider_message_id":"provider-not-operation-key"}';
 wire:=public.read_or_admit_workout_strength_command(a,l,'actual-writer','musculacao',args);
 args:=wire->'legacyArguments';
 legacy:=public.register_workout_atomic((args->>'p_user_id')::uuid,(args->>'p_date')::date,args->>'p_workout_type',
  (args->>'p_duration_min')::integer,(args->>'p_estimated_kcal')::integer,args->>'p_intensity',args->>'p_notes',
  (args->>'p_performed_at')::timestamptz,args->>'p_provider_message_id',(args->>'p_calories_target')::integer,
  (args->>'p_protein_target')::numeric,(args->>'p_replace_recent')::boolean,(args->>'p_replace_since')::timestamptz);
 PERFORM c59s7_fixture.ok(legacy->'inserted'='true'::jsonb AND legacy->>'exercise_calories'='300'
  AND (SELECT workout_type='musculacao' AND raw_provider_message_id='provider-not-operation-key' AND estimated_kcal=300
   FROM public.workout_logs WHERE id=(legacy->>'workout_log_id')::uuid),'actual_legacy_13args_no_defaults_recalculation_or_activation');
END $legacy$;
SELECT c59s7_fixture.ok((SELECT md5(jsonb_build_object('api',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'config',p.proconfig,
 'guard',pg_get_functiondef('private.assert_trusted_backend()'::regprocedure))::text) FROM pg_proc p
 WHERE p.oid='public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure)=:'s7_fingerprint',
 'old_API_guard_definition_ACL_unchanged');
ROLLBACK;
SELECT to_regnamespace('c59s7_fixture') IS NULL AND to_regclass('private.workout_strength_commands') IS NULL
 AND to_regclass('private.workout_strength_lifecycles') IS NULL AND to_regclass('private.workout_strength_operations') IS NULL
 AND to_regclass('public.workout_logs') IS NULL AND to_regclass('public.daily_snapshots') IS NULL
 AND to_regprocedure('public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)') IS NULL
 AND (SELECT count(*) FROM public.users)=:'s7_baseline_users'::bigint AS rollback_ok
\gset s7_
\if :s7_rollback_ok
\echo C59S7_ROLLBACK_CONFIRMED
\else
DO $$BEGIN RAISE EXCEPTION 'C59S7_ROLLBACK_MISMATCH';END$$;
\endif
\endif
\endif
