-- S8 private executable test-first. Missing DDL/API is SETUP, not causal RED.
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
DO $$BEGIN RAISE EXCEPTION 'C59S8_SETUP_CONFLICTING_MODES';END$$;
\endif
\endif
\if :teardown_concurrency
BEGIN;
SET LOCAL search_path=public,pg_catalog;SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';
DO $ownership$DECLARE o record;BEGIN
 SELECT * INTO STRICT o FROM c59s8_fixture.ownership WHERE tag='c59s8_capture_v1';
 IF o.owner_name<>session_user OR o.object_oids IS DISTINCT FROM c59s8_fixture.object_oids()
 OR o.object_fingerprint IS DISTINCT FROM c59s8_fixture.object_fingerprint() OR(SELECT count(*) FROM c59s8_fixture.ownership)<>1
 THEN RAISE EXCEPTION 'C59S8_TEARDOWN_OBJECT_DRIFT';END IF;
 IF(SELECT count(*) FROM public.users WHERE id IN('c59a9000-0000-0000-0000-000000000011','c59a9000-0000-0000-0000-000000000012','c59a9000-0000-0000-0000-000000000013','c59a9000-0000-0000-0000-000000000014','c59a9000-0000-0000-0000-000000000015')
 AND metadata->>'c59s8_fixture'='c59s8_capture_v1' AND wpp='c59s8-'||id::text)<>5 THEN RAISE EXCEPTION 'C59S8_TEARDOWN_OWNER_DRIFT';END IF;
 DELETE FROM public.users WHERE id IN('c59a9000-0000-0000-0000-000000000011','c59a9000-0000-0000-0000-000000000012','c59a9000-0000-0000-0000-000000000013','c59a9000-0000-0000-0000-000000000014','c59a9000-0000-0000-0000-000000000015') AND metadata->>'c59s8_fixture'='c59s8_capture_v1';
 IF EXISTS(SELECT 1 FROM public.workout_logs) OR EXISTS(SELECT 1 FROM public.daily_snapshots) OR EXISTS(SELECT 1 FROM private.workout_strength_lifecycles)
 OR EXISTS(SELECT 1 FROM private.workout_strength_operations) OR EXISTS(SELECT 1 FROM private.workout_strength_facts) OR EXISTS(SELECT 1 FROM private.workout_strength_commands)
 OR EXISTS(SELECT 1 FROM public.workout_types WHERE id NOT IN('c59a9000-0000-0000-0000-000000009001','c59a9000-0000-0000-0000-000000009002','c59a9000-0000-0000-0000-000000009003','c59a9000-0000-0000-0000-000000009101','c59a9000-0000-0000-0000-000000009102'))
 THEN RAISE EXCEPTION 'C59S8_TEARDOWN_FOREIGN_ROWS';END IF;
END $ownership$;
DROP FUNCTION public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb);
DROP FUNCTION public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text);
DROP FUNCTION private.workout_strength_fact_snapshot(uuid,uuid,uuid);
DROP FUNCTION public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb);
DROP FUNCTION public.get_workout_strength_catalogue_context();
DROP FUNCTION public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz);
DROP TABLE private.workout_strength_commands;DROP TABLE private.workout_strength_facts;
DROP TABLE private.workout_strength_operations;DROP TABLE private.workout_strength_lifecycles;
DROP TABLE public.workout_logs;DROP TABLE public.daily_snapshots;DROP TABLE public.workout_types;
DROP FUNCTION c59s8_fixture.object_fingerprint();DROP FUNCTION c59s8_fixture.object_oids();
DROP FUNCTION c59s8_fixture.state(uuid);DROP FUNCTION c59s8_fixture.legacy(jsonb);DROP FUNCTION c59s8_fixture.capture(uuid,uuid,text,text);
DROP FUNCTION c59s8_fixture.decision(jsonb,text);DROP FUNCTION c59s8_fixture.admit(uuid,uuid,text,text,jsonb);
DROP FUNCTION c59s8_fixture.arguments(uuid,text,text);DROP FUNCTION c59s8_fixture.throws(text,text,text);DROP FUNCTION c59s8_fixture.ok(boolean,text);
DROP TABLE c59s8_fixture.ownership;DROP SCHEMA c59s8_fixture;
COMMIT;
\echo C59S8_CONCURRENCY_TEARDOWN_CONFIRMED
\else
\if :{?migration_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S8_SETUP_MIGRATION_PATH';END$$;
\endif
\if :{?bindings_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S8_SETUP_BINDINGS_PATH';END$$;
\endif
\if :{?catalogue_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S8_SETUP_CATALOGUE_PATH';END$$;
\endif
\if :{?facts_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S8_SETUP_FACTS_PATH';END$$;
\endif
\if :{?commands_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S8_SETUP_COMMANDS_PATH';END$$;
\endif
\if :{?legacy_api_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S8_SETUP_LEGACY_API_PATH';END$$;
\endif
\if :{?legacy_permissions_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S8_SETUP_LEGACY_PERMISSIONS_PATH';END$$;
\endif
\if :setup_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S8_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s8_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs','workout_types')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_commands')))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='private' AND p.proname='workout_strength_fact_snapshot')
 OR(n.nspname='public' AND p.proname IN('register_workout_atomic','get_workout_strength_catalogue_context','resolve_confirmed_workout_strength_capture','read_or_admit_workout_strength_command','register_workout_strength_atomic')))
 THEN RAISE EXCEPTION 'C59S8_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_capture_fixture.sql
SELECT md5(jsonb_agg(jsonb_build_object('oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'comment',obj_description(p.oid,'pg_proc')) ORDER BY p.oid)::text) AS fingerprint
 FROM pg_proc p WHERE p.oid IN('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure,
 'public.get_workout_strength_catalogue_context()'::regprocedure,'private.workout_strength_fact_snapshot(uuid,uuid,uuid)'::regprocedure,
 'public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)'::regprocedure,'public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)'::regprocedure,'private.assert_trusted_backend()'::regprocedure)
\gset s8_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)') IS NULL THEN RAISE EXCEPTION 'C59S8_SETUP_UNIMPLEMENTED';END IF;END$$;

DO $owners$DECLARE i integer;u uuid;l uuid;BEGIN FOR i IN 11..15 LOOP
 u:=('c59a9000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;l:=('c59a9000-0000-0000-0000-'||lpad((i+100)::text,12,'0'))::uuid;
 INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES(u,'c59s8-'||u,'C59S8 synthetic','America/Sao_Paulo','{"c59a2_synthetic":true,"c59s8_fixture":"c59s8_capture_v1"}');
 INSERT INTO private.workout_strength_lifecycles VALUES(u,l,'2026-10-01T00:00:00Z',NULL,NULL);
 PERFORM c59s8_fixture.admit(u,l,'case-'||i,'musculacao','{}');END LOOP;END $owners$;
INSERT INTO c59s8_fixture.ownership VALUES('c59s8_capture_v1',session_user,c59s8_fixture.object_oids(),c59s8_fixture.object_fingerprint());
COMMIT;
\echo C59S8_CONCURRENCY_SETUP_CONFIRMED
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S8_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s8_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs','workout_types')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_commands')))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='private' AND p.proname='workout_strength_fact_snapshot')
 OR(n.nspname='public' AND p.proname IN('register_workout_atomic','get_workout_strength_catalogue_context','resolve_confirmed_workout_strength_capture','read_or_admit_workout_strength_command','register_workout_strength_atomic')))
 THEN RAISE EXCEPTION 'C59S8_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_capture_fixture.sql
SELECT md5(jsonb_agg(jsonb_build_object('oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'comment',obj_description(p.oid,'pg_proc')) ORDER BY p.oid)::text) AS fingerprint
 FROM pg_proc p WHERE p.oid IN('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure,
 'public.get_workout_strength_catalogue_context()'::regprocedure,'private.workout_strength_fact_snapshot(uuid,uuid,uuid)'::regprocedure,
 'public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)'::regprocedure,'public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)'::regprocedure,'private.assert_trusted_backend()'::regprocedure)
\gset s8_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)') IS NULL THEN RAISE EXCEPTION 'C59S8_SETUP_UNIMPLEMENTED';END IF;END$$;

SELECT c59s8_fixture.throws('SELECT public.register_workout_strength_atomic(''c59a9000-0000-0000-0000-000000000001'',''c59a9000-0000-0000-0000-000000000101'',''key'',''musculacao'',NULL,NULL)',
 '22023','actual_RR_guard_before_owner');
ROLLBACK;
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S8_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s8_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs','workout_types')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_commands')))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='private' AND p.proname='workout_strength_fact_snapshot')
 OR(n.nspname='public' AND p.proname IN('register_workout_atomic','get_workout_strength_catalogue_context','resolve_confirmed_workout_strength_capture','read_or_admit_workout_strength_command','register_workout_strength_atomic')))
 THEN RAISE EXCEPTION 'C59S8_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_capture_fixture.sql
SELECT md5(jsonb_agg(jsonb_build_object('oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'comment',obj_description(p.oid,'pg_proc')) ORDER BY p.oid)::text) AS fingerprint
 FROM pg_proc p WHERE p.oid IN('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure,
 'public.get_workout_strength_catalogue_context()'::regprocedure,'private.workout_strength_fact_snapshot(uuid,uuid,uuid)'::regprocedure,
 'public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)'::regprocedure,'public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)'::regprocedure,'private.assert_trusted_backend()'::regprocedure)
\gset s8_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)') IS NULL THEN RAISE EXCEPTION 'C59S8_SETUP_UNIMPLEMENTED';END IF;END$$;

SELECT count(*) AS users FROM public.users
\gset s8_baseline_
INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES
 ('c59a9000-0000-0000-0000-000000000001','c59s8-main-a','C59S8 A','America/Sao_Paulo','{"c59a2_synthetic":true}'),
 ('c59a9000-0000-0000-0000-000000000002','c59s8-main-b','C59S8 B','America/Sao_Paulo','{"c59a2_synthetic":true}');
INSERT INTO private.workout_strength_lifecycles VALUES
 ('c59a9000-0000-0000-0000-000000000001','c59a9000-0000-0000-0000-000000000101','2026-10-01T00:00:00Z',NULL,NULL),
 ('c59a9000-0000-0000-0000-000000000002','c59a9000-0000-0000-0000-000000000102','2026-10-01T00:00:00Z',NULL,NULL);
SET LOCAL TimeZone='Pacific/Auckland';SET LOCAL DateStyle='SQL, DMY';
DO $metadata$DECLARE p record;BEGIN
 SELECT * INTO p FROM pg_proc WHERE oid='public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure;
 PERFORM c59s8_fixture.ok(p.prosecdef AND p.provolatile='v' AND p.pronargdefaults=0 AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
 AND(SELECT count(*)=1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='register_workout_strength_atomic'),'one_RPC6_no19_overload_no_defaults');
END $metadata$;

SAVEPOINT basic;
DO $basic$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';obs jsonb;wire jsonb;again jsonb;before jsonb;w uuid;official jsonb;BEGIN
 before:=c59s8_fixture.state(a);
 wire:=public.register_workout_strength_atomic(a,l,'missing','musculacao',NULL,NULL);
 PERFORM c59s8_fixture.ok(wire=
 '{"legacy_result":null,"strength":{"status":"unavailable","reason":"operation_key_missing","confirmedWorkoutLogID":null}}'::jsonb
 AND c59s8_fixture.state(a)=before,'missing_journal_no_admission_or_writes');
 PERFORM c59s8_fixture.admit(a,l,'precision','musculacao','{"p_duration_min":1.0,"p_protein_target":100.124999999999999999999}');
 obs:=public.get_workout_strength_catalogue_context();
 wire:=public.register_workout_strength_atomic(a,l,'precision','musculacao',obs,c59s8_fixture.decision(obs,'musculacao'));
 w:=(wire#>>'{strength,binding,workoutLogID}')::uuid;
 PERFORM c59s8_fixture.ok(wire->'legacy_result'->'inserted'='true'::jsonb AND wire#>>'{strength,status}'='committed'
 AND wire#>>'{strength,binding,resolution}'='sql_insert' AND(SELECT duration_min=1 FROM public.workout_logs WHERE id=w)
 AND(SELECT protein_target=100.12 FROM public.daily_snapshots WHERE id=(SELECT snapshot_id FROM public.workout_logs WHERE id=w)),'SQL_numeric_precision100_124999_to100_12_duration1_0');
 SELECT jsonb_build_object('snapshot_id',s.id,'workout_log_id',w,'inserted',true,'replaced_count',0,'exercise_calories',s.exercise_calories,
 'training_done',s.training_done,'calories_target',s.calories_target,'protein_target',s.protein_target) INTO official
 FROM public.daily_snapshots s JOIN public.workout_logs wl ON wl.snapshot_id=s.id WHERE wl.id=w;
 PERFORM c59s8_fixture.ok(wire=jsonb_build_object('legacy_result',official,'strength',jsonb_build_object('status','committed','binding',jsonb_build_object(
 'ownerID',a,'lifecycleKey',l,'operationKey','precision','originalOperationType','musculacao','workoutLogID',w,'resolution','sql_insert'),
 'fact',private.workout_strength_fact_snapshot(a,l,w))) AND wire#>>'{strength,fact,calendar,timeZone}'='America/Sao_Paulo'
 AND wire#>>'{strength,fact,classification,catalogue,category}'='musculacao' AND wire#>>'{strength,fact,revision}'='0','exact_outer_R2_legacy_actual_owned_fact_proven_calendar');
 again:=public.resolve_confirmed_workout_strength_capture(a,l,'precision','musculacao');
 PERFORM c59s8_fixture.ok(again=
 (wire->'strength')||'{"status":"reuse_existing"}'::jsonb,'resolverS5_reads_exact_committed_fact_binding');
 DELETE FROM private.workout_strength_commands WHERE user_id=a;
 UPDATE public.workout_types SET category='esporte',display_name='mutated after commit' WHERE slug='musculacao';
 UPDATE public.users SET timezone='unknown-current-zone' WHERE id=a;
 before:=c59s8_fixture.state(a);
 again:=public.register_workout_strength_atomic(a,l,'precision','musculacao','null','{"not":"trusted"}');
 PERFORM c59s8_fixture.ok(again=wire||jsonb_build_object('strength',wire->'strength'||'{"status":"reuse_existing"}')
 AND c59s8_fixture.state(a)=before,'binding_replay_before_missing_journal_invalid_envelope_and_current_catalogue');
END $basic$;
ROLLBACK TO basic;RELEASE basic;

SAVEPOINT nulls;
DO $nulls$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';r jsonb;w uuid;BEGIN
 PERFORM c59s8_fixture.admit(a,l,'null8','musculacao','{"p_intensity":null,"p_notes":null,"p_performed_at":null,"p_provider_message_id":null,"p_calories_target":null,"p_protein_target":null,"p_replace_recent":null,"p_replace_since":null}'::jsonb
 ||jsonb_build_object('p_date',to_char(((transaction_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-1)::timestamp,'YYYY-MM-DD')));
 -- Intentionally discard the first function result; retry must recover stored result.
 PERFORM c59s8_fixture.capture(a,l,'null8','musculacao');
 r:=public.register_workout_strength_atomic(a,l,'null8','musculacao',NULL,NULL);w:=(r#>>'{strength,binding,workoutLogID}')::uuid;
 PERFORM c59s8_fixture.ok((SELECT intensity IS NULL AND notes IS NULL AND raw_provider_message_id IS NULL AND performed_at=transaction_timestamp()
 FROM public.workout_logs WHERE id=w) AND(SELECT calories_target IS NULL AND protein_target IS NULL FROM public.daily_snapshots WHERE id=(SELECT snapshot_id FROM public.workout_logs WHERE id=w)),
 'nullable8_and_performed_NULL_real_old_COALESCE_not_admittedAt');
 PERFORM c59s8_fixture.ok(r#>>'{strength,status}'='reuse_existing' AND(SELECT count(*)=1 FROM public.workout_logs WHERE user_id=a)
 AND(SELECT count(*)=1 FROM private.workout_strength_operations WHERE user_id=a) AND r->'legacy_result'=(SELECT legacy_result FROM private.workout_strength_operations WHERE user_id=a),
 'discarded_function_reply_recovered_without_second_old_write');
 PERFORM c59s8_fixture.ok(r#>'{strength,fact,calendar}'='{"status":"unavailable","reason":"calendar_conflict"}'::jsonb,
 'NULL_now_calendar_conflict_does_not_change_legacy_date');
END $nulls$;
ROLLBACK TO nulls;RELEASE nulls;

SAVEPOINT envelopes;
DO $envelopes$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';obs jsonb;d jsonb;x record;before jsonb;r jsonb;BEGIN
 PERFORM c59s8_fixture.admit(a,l,'invalid','musculacao','{}');obs:=public.get_workout_strength_catalogue_context();d:=c59s8_fixture.decision(obs,'musculacao');before:=c59s8_fixture.state(a);
 FOR x IN SELECT * FROM(VALUES
 ('obs_SQLNULL',NULL::jsonb,d),('decision_JSONnull',obs,'null'::jsonb),
 ('obs_extra',obs||'{"extra":true}',d),('obs_incomplete',obs||'{"complete":false}',d),('obs_count_noncanonical',obs||'{"rowCount":"03"}',d),
 ('obs_count_type',obs||'{"rowCount":3}',d),('obs_rows_reversed',jsonb_set(obs,'{activeRows}',(SELECT jsonb_agg(v ORDER BY ord DESC) FROM jsonb_array_elements(obs->'activeRows') WITH ORDINALITY e(v,ord))),d),
 ('obs_bad_US6',obs||'{"observedAt":"2026-02-30T00:00:00.000000Z"}',d),('obs_offset',obs||'{"observedAt":"2026-10-12T00:00:00.000000+00:00"}',d),
 ('row_extra',jsonb_set(obs,'{activeRows,0}',(obs#>'{activeRows,0}')||'{"extra":true}'),d),
 ('row_inactive',jsonb_set(obs,'{activeRows,0,isActive}','false'),d),('row_category',jsonb_set(obs,'{activeRows,0,category}','"strength"'),d),
 ('decision_extra',obs,d||'{"category":"musculacao"}'),('decision_row_unknown',obs,d||'{"selectedRowID":"c59a9000-0000-0000-0000-000000000099"}'),
 ('decision_key',obs,d||'{"observationKey":"c59a9000-0000-0000-0000-000000000099"}'),('decision_version',obs,d||'{"matcherVersion":"v2"}'),
 ('decision_raw',obs,d||'{"originalOperationType":"MUSCULACAO"}'),('decision_method',obs,d||'{"method":"fuzzy"}'),
 ('decision_unknown_reason',obs,jsonb_build_object('status','unrecognized','observationKey',obs->'observationKey','matcherVersion',obs->'matcherVersion','originalOperationType','musculacao','reason','unknown')),
 ('unavailable_JSONnull_observation','null'::jsonb,'{"status":"unavailable","reason":"catalogue_read_error"}'::jsonb))t(label,o,d) LOOP
 r:=public.register_workout_strength_atomic(a,l,'invalid','musculacao',x.o,x.d);
 PERFORM c59s8_fixture.ok(r=
 '{"legacy_result":null,"strength":{"status":"forbidden","reason":"invalid_authority"}}'::jsonb
 AND c59s8_fixture.state(a)=before,'malformed_no_writes:'||x.label);
 END LOOP;
END $envelopes$;
ROLLBACK TO envelopes;RELEASE envelopes;

SAVEPOINT cas;
DO $cas$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';obs jsonb;d jsonb;before jsonb;patch text;r jsonb;BEGIN
 PERFORM c59s8_fixture.admit(a,l,'cas','musculacao','{}');obs:=public.get_workout_strength_catalogue_context();d:=c59s8_fixture.decision(obs,'musculacao');before:=c59s8_fixture.state(a);
 UPDATE public.workout_types SET display_name='changed competitor' WHERE slug='natacao';
 r:=public.register_workout_strength_atomic(a,l,'cas','musculacao',obs,d);
 PERFORM c59s8_fixture.ok(r=
 '{"legacy_result":null,"strength":{"status":"conflict","reason":"source_observation_changed"}}'::jsonb AND c59s8_fixture.state(a)=before,'CAS_competitor_edit_selected_unchanged_zero_writes');
 UPDATE public.workout_types SET display_name='Natação',is_active=false WHERE slug='natacao';
 r:=public.register_workout_strength_atomic(a,l,'cas','musculacao',obs,d);
 PERFORM c59s8_fixture.ok(r=
 '{"legacy_result":null,"strength":{"status":"conflict","reason":"source_observation_changed"}}'::jsonb AND c59s8_fixture.state(a)=before,'CAS_competitor_inactivation_zero_writes');
 UPDATE public.workout_types SET is_active=true WHERE slug='natacao';
 INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min) VALUES('c59a9000-0000-0000-0000-000000009101','competing','Musculação','musculacao',4);
 r:=public.register_workout_strength_atomic(a,l,'cas','musculacao',obs,d);
 PERFORM c59s8_fixture.ok(r=
 '{"legacy_result":null,"strength":{"status":"conflict","reason":"source_observation_changed"}}'::jsonb AND c59s8_fixture.state(a)=before,'CAS_competitor_insertion_zero_writes');
END $cas$;
ROLLBACK TO cas;RELEASE cas;

SAVEPOINT classifications;
DO $classes$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';obs jsonb;d jsonb;r jsonb;x record;i integer:=0;raw text;BEGIN
 INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min) VALUES
 ('c59a9000-0000-0000-0000-000000009101','ambiguous_a','Treino Ambíguo','musculacao',4),('c59a9000-0000-0000-0000-000000009102','ambiguous_b','Treino Ambíguo','musculacao',4);
 FOR x IN SELECT * FROM(VALUES('no_active_match','boxe_desconhecido'),('ambiguous_active_name','Treino Ambíguo'),('generic_outro','outro'))t(reason,raw) LOOP
 i:=i+1;PERFORM c59s8_fixture.admit(a,l,'unknown-'||i,x.raw,'{}');obs:=public.get_workout_strength_catalogue_context();
 d:=jsonb_build_object('status','unrecognized','observationKey',obs->'observationKey','matcherVersion',obs->'matcherVersion','originalOperationType',x.raw,'reason',x.reason);
 r:=public.register_workout_strength_atomic(a,l,'unknown-'||i,x.raw,obs,d);
 PERFORM c59s8_fixture.ok(r#>>'{strength,status}'='committed' AND r#>'{strength,fact,classification}'=jsonb_build_object('status','unrecognized',
 'observation',jsonb_build_object('observationKey',obs->'observationKey','observedAt',obs->'observedAt','matcherVersion',obs->'matcherVersion'),'reason',x.reason)
 AND r#>>'{strength,fact,clarification,status}'='unanswered' AND(r#>>'{strength,fact,clarification,questionKey}')::uuid IS NOT NULL
 AND r#>>'{strength,fact,revision}'='0','unrecognized_DB_question_revision0:'||x.reason);
 END LOOP;
 FOR x IN SELECT * FROM(VALUES('catalogue_read_error'),('catalogue_invalid'),('catalogue_incomplete'))t(reason) LOOP
 raw:='unavailable_'||x.reason;PERFORM c59s8_fixture.admit(a,l,raw,raw,'{}');
 r:=public.register_workout_strength_atomic(a,l,raw,raw,NULL,jsonb_build_object('status','unavailable','reason',x.reason));
 PERFORM c59s8_fixture.ok(r#>>'{strength,status}'='committed' AND r#>'{strength,fact,classification}'=jsonb_build_object('status','unavailable','reason',x.reason)
 AND r#>'{strength,fact,clarification}'='{"status":"not_applicable"}'::jsonb AND r#>>'{strength,fact,revision}'='0','unavailable_SQLNULL_observation_no_question:'||x.reason);
 END LOOP;
 UPDATE public.workout_types SET display_name='Musculação completa',category='mobilidade' WHERE slug='musculacao';
 raw:='Musculação completa';PERFORM c59s8_fixture.admit(a,l,'display-match',raw,'{}');obs:=public.get_workout_strength_catalogue_context();d:=c59s8_fixture.decision(obs,raw)||'{"method":"unique_active_display"}';
 r:=public.register_workout_strength_atomic(a,l,'display-match',raw,obs,d);
 PERFORM c59s8_fixture.ok(r#>>'{strength,fact,classification,method}'='unique_active_display'
 AND r#>>'{strength,fact,classification,catalogue,category}'='mobilidade','matched_method_and_category_copied_actual_row_not_input');
END $classes$;
ROLLBACK TO classifications;RELEASE classifications;

SAVEPOINT dedup;
DO $dedup$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';seed jsonb;r jsonb;other_result jsonb;again jsonb;cutoff timestamptz;older uuid;boundary uuid;BEGIN
 seed:=c59s8_fixture.legacy(c59s8_fixture.arguments(a,'musculacao','shared-provider'));
 PERFORM c59s8_fixture.admit(a,l,'different-operation-key','musculacao','{"p_provider_message_id":"shared-provider","p_duration_min":90,"p_date":"2026-10-13"}');
 r:=public.register_workout_strength_atomic(a,l,'different-operation-key','musculacao','null','null');
 PERFORM c59s8_fixture.ok(r=jsonb_build_object('legacy_result',NULL,'strength',jsonb_build_object('status','unavailable','reason','legacy_provenance_gap','confirmedWorkoutLogID',seed->'workout_log_id'))
 AND(SELECT resolution='provider_type_dedup' AND capture_outcome='legacy_provenance_gap' AND legacy_result IS NULL FROM private.workout_strength_operations WHERE user_id=a),
 'provider_dedup_before_envelope_provider_not_operationkey_gap_no_fact');
 PERFORM c59s8_fixture.admit(a,l,'recent','treino_recente','{}');SELECT recent_cutoff INTO cutoff FROM private.workout_strength_commands WHERE user_id=a AND operation_key='recent';
 older:=(c59s8_fixture.legacy(c59s8_fixture.arguments(a,'treino_recente','older'))->>'workout_log_id')::uuid;
 boundary:=(c59s8_fixture.legacy(c59s8_fixture.arguments(a,'treino_recente','boundary'))->>'workout_log_id')::uuid;
 UPDATE public.workout_logs SET created_at=cutoff-interval '1 microsecond' WHERE id=older;UPDATE public.workout_logs SET created_at=cutoff WHERE id=boundary;
 r:=public.register_workout_strength_atomic(a,l,'recent','treino_recente',NULL,NULL);
 PERFORM c59s8_fixture.ok(r#>>'{strength,confirmedWorkoutLogID}'=boundary::text AND(SELECT resolution='recent6h_dedup' FROM private.workout_strength_operations WHERE operation_key='recent'),
 'recent_persisted_cutoff_exact_boundary_excludes_minus1us');
 PERFORM c59s8_fixture.admit('c59a9000-0000-0000-0000-000000000002','c59a9000-0000-0000-0000-000000000102','plus1','treino_recente','{}');
 PERFORM c59s8_fixture.legacy(c59s8_fixture.arguments('c59a9000-0000-0000-0000-000000000002','treino_recente','B-minus'));
 PERFORM c59s8_fixture.legacy(c59s8_fixture.arguments('c59a9000-0000-0000-0000-000000000002','treino_recente','B-plus'));
 UPDATE public.workout_logs SET created_at=(SELECT recent_cutoff FROM private.workout_strength_commands WHERE user_id='c59a9000-0000-0000-0000-000000000002')
  +CASE WHEN raw_provider_message_id='B-plus' THEN interval '1 microsecond' ELSE interval '-1 microsecond' END WHERE user_id='c59a9000-0000-0000-0000-000000000002';
 other_result:=public.register_workout_strength_atomic('c59a9000-0000-0000-0000-000000000002','c59a9000-0000-0000-0000-000000000102','plus1','treino_recente',NULL,NULL);
 PERFORM c59s8_fixture.ok(other_result#>>'{strength,confirmedWorkoutLogID}'=
  (SELECT id::text FROM public.workout_logs WHERE user_id='c59a9000-0000-0000-0000-000000000002' AND raw_provider_message_id='B-plus'),'recent_plus1us_eligible_minus1us_excluded');
 UPDATE public.workout_logs SET created_at=cutoff-interval '1 microsecond' WHERE id=boundary;
 PERFORM c59s8_fixture.legacy(c59s8_fixture.arguments(a,'treino_recente','new-eligible'));
 again:=public.register_workout_strength_atomic(a,l,'recent','treino_recente',NULL,NULL);
 PERFORM c59s8_fixture.ok(again=r,'recent_binding_replay_does_not_reselect_new_eligible_row');
END $dedup$;
ROLLBACK TO dedup;RELEASE dedup;

SAVEPOINT replays;
DO $replays$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';first jsonb;r jsonb;seed jsonb;w uuid;raw text:='  musculacao  ';BEGIN
 PERFORM c59s8_fixture.admit(a,l,'with-fact',raw,'{}');first:=c59s8_fixture.capture(a,l,'with-fact',raw);w:=(first#>>'{strength,binding,workoutLogID}')::uuid;
 PERFORM c59s8_fixture.admit(a,l,'recent-fact','musculacao','{}');r:=public.register_workout_strength_atomic(a,l,'recent-fact','musculacao','null','null');
 PERFORM c59s8_fixture.ok(r->'legacy_result'='null'::jsonb AND r#>>'{strength,status}'='reuse_existing' AND r#>>'{strength,binding,resolution}'='recent6h_dedup'
 AND r#>'{strength,fact}'=first#>'{strength,fact}' AND(SELECT count(*)=1 FROM private.workout_strength_facts WHERE user_id=a),'early_recent_reuses_only_current_owned_fact_before_envelope');
 PERFORM c59s8_fixture.admit(a,l,'SQL-replay',raw,'{"p_provider_message_id":"with-fact","p_date":"2026-10-13","p_performed_at":"2026-10-13T15:00:00.123456Z"}');
 r:=c59s8_fixture.capture(a,l,'SQL-replay',raw);
 PERFORM c59s8_fixture.ok(r#>>'{strength,status}'='reuse_existing' AND r#>>'{strength,binding,resolution}'='sql_replay' AND r#>'{strength,fact}'=first#>'{strength,fact}'
 AND r#>>'{legacy_result,workout_log_id}'=w::text AND r#>>'{legacy_result,snapshot_id}'<>first#>>'{legacy_result,snapshot_id}'
 AND r#>>'{strength,fact,anchor,snapshotID}'=first#>>'{legacy_result,snapshot_id}','X26_sql_replay_actual_response13_original_fact_anchor12');
 seed:=c59s8_fixture.legacy(c59s8_fixture.arguments(a,raw,'legacy-X26'));
 PERFORM c59s8_fixture.admit(a,l,'SQL-gap',raw,'{"p_provider_message_id":"legacy-X26","p_date":"2026-10-13"}');r:=c59s8_fixture.capture(a,l,'SQL-gap',raw);
 PERFORM c59s8_fixture.ok(r#>>'{strength,status}'='unavailable' AND r#>>'{strength,reason}'='legacy_provenance_gap' AND r#>>'{strength,confirmedWorkoutLogID}'=seed->>'workout_log_id'
 AND r#>>'{legacy_result,snapshot_id}'<>seed->>'snapshot_id' AND NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE workout_log_id=(seed->>'workout_log_id')::uuid),
 'X26_sql_replay_oldrow_gap_without_historical_backfill');
END $replays$;
ROLLBACK TO replays;RELEASE replays;

SAVEPOINT oldlife;
DO $oldlife$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';newlife uuid:='c59a9000-0000-0000-0000-000000000201';before jsonb;r jsonb;BEGIN
 PERFORM c59s8_fixture.admit(a,l,'old-fact','musculacao','{}');PERFORM c59s8_fixture.capture(a,l,'old-fact','musculacao');
 UPDATE private.workout_strength_lifecycles SET closed_at='2026-10-14T00:00:00Z',close_operation_key='close' WHERE user_id=a;
 INSERT INTO private.workout_strength_lifecycles VALUES(a,newlife,'2026-10-14T00:00:00Z',NULL,NULL);
 PERFORM c59s8_fixture.admit(a,newlife,'new-life','musculacao','{"p_provider_message_id":"old-fact"}');before:=c59s8_fixture.state(a);
 r:=public.register_workout_strength_atomic(a,newlife,'new-life','musculacao',NULL,NULL);
 PERFORM c59s8_fixture.ok(r=
 '{"legacy_result":null,"strength":{"status":"forbidden","reason":"stale_workout"}}'::jsonb AND c59s8_fixture.state(a)=before,'oldlife_fact_never_gap_overwrite_or_new_binding');
 r:=public.register_workout_strength_atomic(a,l,'old-fact','musculacao',NULL,NULL);
 PERFORM c59s8_fixture.ok(r=
 '{"legacy_result":null,"strength":{"status":"forbidden","reason":"stale_lifecycle"}}'::jsonb,'closed_lifecycle_precedes_existing_binding_replay');
END $oldlife$;
ROLLBACK TO oldlife;RELEASE oldlife;

SAVEPOINT atomic;
DO $seed$BEGIN
 PERFORM c59s8_fixture.admit('c59a9000-0000-0000-0000-000000000001','c59a9000-0000-0000-0000-000000000101','old','musculacao','{}');
 PERFORM c59s8_fixture.capture('c59a9000-0000-0000-0000-000000000001','c59a9000-0000-0000-0000-000000000101','old','musculacao');
 PERFORM c59s8_fixture.legacy(c59s8_fixture.arguments('c59a9000-0000-0000-0000-000000000002','natacao','other-owner')||'{"p_estimated_kcal":200}');
 PERFORM c59s8_fixture.admit('c59a9000-0000-0000-0000-000000000001','c59a9000-0000-0000-0000-000000000101','correction','musculacao',
 '{"p_duration_min":80,"p_estimated_kcal":400,"p_replace_recent":true,"p_replace_since":"2000-01-01T00:00:00Z"}');
 PERFORM set_config('c59s8_test.before_atomic',c59s8_fixture.state('c59a9000-0000-0000-0000-000000000001')::text,true);
 PERFORM set_config('c59s8_test.other_owner',c59s8_fixture.state('c59a9000-0000-0000-0000-000000000002')::text,true);
END $seed$;
-- Physical test-only constraint, not runtime hook or fake old writer.
ALTER TABLE private.workout_strength_facts ADD CONSTRAINT c59s8_reject_new_fact CHECK(stored_workout_type<>'musculacao') NOT VALID;
SELECT c59s8_fixture.throws('SELECT c59s8_fixture.capture(''c59a9000-0000-0000-0000-000000000001'',''c59a9000-0000-0000-0000-000000000101'',''correction'',''musculacao'')','23514','actual_fact_CHECK_failure_propagates');
SELECT c59s8_fixture.ok(c59s8_fixture.state('c59a9000-0000-0000-0000-000000000001')=current_setting('c59s8_test.before_atomic')::jsonb,'mandatory_metadata_failure_rolls_back_real_correction_all_rows');
ALTER TABLE private.workout_strength_facts DROP CONSTRAINT c59s8_reject_new_fact;
DO $corrected$DECLARE r jsonb;old_replay jsonb;BEGIN
 r:=c59s8_fixture.capture('c59a9000-0000-0000-0000-000000000001','c59a9000-0000-0000-0000-000000000101','correction','musculacao');
 old_replay:=public.register_workout_strength_atomic('c59a9000-0000-0000-0000-000000000001','c59a9000-0000-0000-0000-000000000101','old','musculacao',NULL,NULL);
 PERFORM c59s8_fixture.ok(r#>>'{legacy_result,replaced_count}'='1' AND r#>>'{legacy_result,exercise_calories}'='400' AND r#>>'{strength,status}'='committed'
 AND old_replay=
 '{"legacy_result":null,"strength":{"status":"forbidden","reason":"stale_workout"}}'::jsonb,'actual_correction400_tombstone_no_rebind');
 PERFORM c59s8_fixture.ok(c59s8_fixture.state('c59a9000-0000-0000-0000-000000000002')=current_setting('c59s8_test.other_owner')::jsonb,'other_owner200_unchanged_during_correction');
END $corrected$;
ROLLBACK TO atomic;RELEASE atomic;

SAVEPOINT operational;
DO $operational$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';before jsonb;BEGIN
 PERFORM c59s8_fixture.admit(a,l,'overflow','musculacao','{"p_protein_target":1000000}');before:=c59s8_fixture.state(a);
 PERFORM c59s8_fixture.throws(format('SELECT c59s8_fixture.capture(%L,%L,%L,%L)',a,l,'overflow','musculacao'),'22003','old_numeric_overflow_operational_not_unavailable');
 PERFORM c59s8_fixture.ok(c59s8_fixture.state(a)=before,'oldwriter_failure_has_no_partial_writes');
 PERFORM c59s8_fixture.admit(a,l,'infinity','musculacao','{"p_performed_at":"infinity"}');before:=c59s8_fixture.state(a);
 PERFORM c59s8_fixture.throws(format('SELECT c59s8_fixture.capture(%L,%L,%L,%L)',a,l,'infinity','musculacao'),'23514','infinite_real_anchor_metadata_CHECK_failure');
 PERFORM c59s8_fixture.ok(c59s8_fixture.state(a)=before,'infinite_anchor_rolls_back_old_workout_snapshot_and_binding');
 PERFORM c59s8_fixture.admit(a,l,'bad-journal','musculacao','{}');UPDATE private.workout_strength_commands SET legacy_arguments=legacy_arguments||'{"p_duration_min":"bad"}' WHERE user_id=a AND operation_key='bad-journal';
 PERFORM c59s8_fixture.throws(format('SELECT c59s8_fixture.capture(%L,%L,%L,%L)',a,l,'bad-journal','musculacao'),'22P02','journal_decode_failure_is_operational_not_authority_or_unavailable');
END $operational$;
ROLLBACK TO operational;RELEASE operational;

SAVEPOINT calendar;
UPDATE public.users SET timezone='America/Sao_Paulo ' WHERE id='c59a9000-0000-0000-0000-000000000001';
DO $zone$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';r jsonb;BEGIN
 PERFORM c59s8_fixture.admit(a,l,'bad-zone','musculacao','{}');r:=c59s8_fixture.capture(a,l,'bad-zone','musculacao');
 PERFORM c59s8_fixture.ok(r#>'{strength,fact,calendar}'='{"status":"unavailable","reason":"zone_unproved"}'::jsonb
 AND r#>>'{legacy_result,exercise_calories}'='300' AND r#>>'{strength,fact,anchor,snapshotDate}'='2026-10-12','invalid_official_zone_unproved_without_changing_old_values');
END $zone$;
ROLLBACK TO calendar;RELEASE calendar;

DO $guards$DECLARE a uuid:='c59a9000-0000-0000-0000-000000000001';l uuid:='c59a9000-0000-0000-0000-000000000101';x record;r jsonb;BEGIN
 FOR x IN SELECT * FROM(VALUES('owner',NULL::uuid,l,'key','musculacao'),('life',a,NULL::uuid,'key','musculacao'),('keynull',a,l,NULL::text,'musculacao'),
 ('keyempty',a,l,'','musculacao'),('typenull',a,l,'key',NULL::text),('typeblank',a,l,'key','   '))t(label,u,life,key,raw) LOOP
 PERFORM c59s8_fixture.throws(format('SELECT public.register_workout_strength_atomic(%L,%L,%L,%L,NULL,NULL)',x.u,x.life,x.key,x.raw),'22023','syntax:'||x.label);
 END LOOP;
 PERFORM c59s8_fixture.throws(format('SELECT public.register_workout_strength_atomic(%L,%L,%L,%L,NULL,NULL)',
 'c59a9000-0000-0000-0000-000000000099',l,'missing','musculacao'),'P0002','missing_owner_before_journal');
 r:=public.register_workout_strength_atomic(a,'c59a9000-0000-0000-0000-000000000102','missing','musculacao',NULL,NULL);
 PERFORM c59s8_fixture.ok(r=
 '{"legacy_result":null,"strength":{"status":"forbidden","reason":"stale_lifecycle"}}'::jsonb,'foreign_owner_lifecycle_never_mixed');
END $guards$;
SAVEPOINT inactive;
UPDATE public.users SET status='deleted' WHERE id='c59a9000-0000-0000-0000-000000000001';
SELECT c59s8_fixture.throws('SELECT public.register_workout_strength_atomic(''c59a9000-0000-0000-0000-000000000001'',''c59a9000-0000-0000-0000-000000000101'',''key'',''musculacao'',NULL,NULL)','P0002','inactive_owner_precedes_replay_journal');
ROLLBACK TO inactive;RELEASE inactive;
DO $acl$DECLARE p record;role_name text;code text;r jsonb;BEGIN
 SELECT * INTO p FROM pg_proc WHERE oid='public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure;
 PERFORM c59s8_fixture.ok(NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 WHERE a.grantee NOT IN(p.proowner,(SELECT oid FROM pg_roles WHERE rolname='service_role')) OR(a.grantee<>p.proowner AND a.is_grantable)),'capture_ACL_owner_service_only');
 EXECUTE 'SET LOCAL ROLE service_role';r:=public.register_workout_strength_atomic('c59a9000-0000-0000-0000-000000000001','c59a9000-0000-0000-0000-000000000101','missing','musculacao',NULL,NULL);EXECUTE 'RESET ROLE';
 PERFORM c59s8_fixture.ok(r#>>'{strength,reason}'='operation_key_missing','real_service_role_rpc_without_private_DML');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
 PERFORM c59s8_fixture.ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'EXECUTE_denied:'||role_name);
 EXECUTE format('SET LOCAL ROLE %I',role_name);code:=NULL;
 BEGIN PERFORM public.register_workout_strength_atomic(NULL,NULL,NULL,NULL,NULL,NULL);EXCEPTION WHEN OTHERS THEN code:=SQLSTATE;END;
 EXECUTE 'RESET ROLE';PERFORM c59s8_fixture.ok(code='42501','actual_ACL_denied:'||role_name);
 END LOOP;
END $acl$;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
SELECT c59s8_fixture.throws('SELECT public.register_workout_strength_atomic(NULL,NULL,NULL,NULL,NULL,NULL)','42501','trusted_guard_precedes_invalid_syntax');
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT c59s8_fixture.ok((SELECT md5(jsonb_agg(jsonb_build_object('oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'comment',obj_description(p.oid,'pg_proc')) ORDER BY p.oid)::text)
 FROM pg_proc p WHERE p.oid IN('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure,
 'public.get_workout_strength_catalogue_context()'::regprocedure,'private.workout_strength_fact_snapshot(uuid,uuid,uuid)'::regprocedure,
 'public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)'::regprocedure,'public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)'::regprocedure,'private.assert_trusted_backend()'::regprocedure))=:'s8_fingerprint',
 'legacy_and_neighbors_definitions_ACL_owner_preserved');
ROLLBACK;
SELECT to_regnamespace('c59s8_fixture') IS NULL AND to_regclass('public.workout_logs') IS NULL AND to_regclass('public.daily_snapshots') IS NULL
 AND to_regclass('public.workout_types') IS NULL AND to_regclass('private.workout_strength_facts') IS NULL
 AND to_regclass('private.workout_strength_commands') IS NULL AND to_regprocedure('public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)') IS NULL
 AND(SELECT count(*) FROM public.users)=:'s8_baseline_users'::bigint AS rollback_ok
\gset s8_
\if :s8_rollback_ok
\echo C59S8_ROLLBACK_CONFIRMED
\else
DO $$BEGIN RAISE EXCEPTION 'C59S8_ROLLBACK_MISMATCH';END$$;
\endif
\endif
\endif
