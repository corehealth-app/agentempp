-- S9 executable test-first. Missing future RPC is SETUP, never causal product RED.
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
DO $$BEGIN RAISE EXCEPTION 'C59S9_SETUP_CONFLICTING_MODES';END$$;
\endif
\endif
\if :teardown_concurrency
BEGIN;
SET LOCAL search_path=public,pg_catalog;SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';
DO $ownership$DECLARE o record;BEGIN
 SELECT * INTO STRICT o FROM c59s9_fixture.ownership WHERE tag='c59s9_answers_v1';
 IF o.owner_name<>session_user OR o.object_oids IS DISTINCT FROM c59s9_fixture.object_oids()
 OR o.object_fingerprint IS DISTINCT FROM c59s9_fixture.object_fingerprint() OR(SELECT count(*) FROM c59s9_fixture.ownership)<>1
 THEN RAISE EXCEPTION 'C59S9_TEARDOWN_OBJECT_DRIFT';END IF;
 IF(SELECT count(*) FROM public.users WHERE id IN('c59aa000-0000-0000-0000-000000000011','c59aa000-0000-0000-0000-000000000012','c59aa000-0000-0000-0000-000000000013','c59aa000-0000-0000-0000-000000000014')
 AND metadata->>'c59s9_fixture'='c59s9_answers_v1' AND wpp='c59s9-'||id::text)<>4 THEN RAISE EXCEPTION 'C59S9_TEARDOWN_OWNER_DRIFT';END IF;
 DELETE FROM public.users WHERE id IN('c59aa000-0000-0000-0000-000000000011','c59aa000-0000-0000-0000-000000000012','c59aa000-0000-0000-0000-000000000013','c59aa000-0000-0000-0000-000000000014') AND metadata->>'c59s9_fixture'='c59s9_answers_v1';
 IF EXISTS(SELECT 1 FROM public.workout_logs) OR EXISTS(SELECT 1 FROM public.daily_snapshots) OR EXISTS(SELECT 1 FROM private.workout_strength_lifecycles)
 OR EXISTS(SELECT 1 FROM private.workout_strength_operations) OR EXISTS(SELECT 1 FROM private.workout_strength_facts) OR EXISTS(SELECT 1 FROM private.workout_strength_commands)
 OR EXISTS(SELECT 1 FROM public.workout_types WHERE id NOT IN('c59a9000-0000-0000-0000-000000009001','c59a9000-0000-0000-0000-000000009002','c59a9000-0000-0000-0000-000000009003'))
 THEN RAISE EXCEPTION 'C59S9_TEARDOWN_FOREIGN_ROWS';END IF;
END $ownership$;
DROP FUNCTION public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text);
DROP FUNCTION public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb);
DROP FUNCTION public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text);
DROP FUNCTION private.workout_strength_fact_snapshot(uuid,uuid,uuid);
DROP FUNCTION public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb);
DROP FUNCTION public.get_workout_strength_catalogue_context();
DROP FUNCTION public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz);
DROP TABLE private.workout_strength_commands;DROP TABLE private.workout_strength_facts;
DROP TABLE private.workout_strength_operations;DROP TABLE private.workout_strength_lifecycles;
DROP TABLE public.workout_logs;DROP TABLE public.daily_snapshots;DROP TABLE public.workout_types;
DROP FUNCTION c59s9_fixture.object_fingerprint();DROP FUNCTION c59s9_fixture.object_oids();
DROP FUNCTION c59s9_fixture.seed(uuid,uuid,text,text,text,jsonb);DROP FUNCTION c59s9_fixture.immutable_state(uuid);
DROP FUNCTION c59s9_fixture.state(uuid);DROP FUNCTION c59s9_fixture.legacy(jsonb);DROP FUNCTION c59s9_fixture.capture(uuid,uuid,text,text);
DROP FUNCTION c59s9_fixture.decision(jsonb,text);DROP FUNCTION c59s9_fixture.admit(uuid,uuid,text,text,jsonb);
DROP FUNCTION c59s9_fixture.arguments(uuid,text,text);DROP FUNCTION c59s9_fixture.throws(text,text,text);DROP FUNCTION c59s9_fixture.ok(boolean,text);
DROP TABLE c59s9_fixture.ownership;DROP SCHEMA c59s9_fixture;
COMMIT;
\echo C59S9_CONCURRENCY_TEARDOWN_CONFIRMED
\else
\if :{?migration_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S9_SETUP_MIGRATION_PATH';END$$;
\endif
\if :{?bindings_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S9_SETUP_BINDINGS_PATH';END$$;
\endif
\if :{?catalogue_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S9_SETUP_CATALOGUE_PATH';END$$;
\endif
\if :{?facts_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S9_SETUP_FACTS_PATH';END$$;
\endif
\if :{?commands_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S9_SETUP_COMMANDS_PATH';END$$;
\endif
\if :{?capture_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S9_SETUP_CAPTURE_PATH';END$$;
\endif
\if :{?legacy_api_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S9_SETUP_LEGACY_API_PATH';END$$;
\endif
\if :{?legacy_permissions_path}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S9_SETUP_LEGACY_PERMISSIONS_PATH';END$$;
\endif
\if :setup_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S9_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s9_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs','workout_types')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_commands')))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='private' AND p.proname='workout_strength_fact_snapshot')
 OR(n.nspname='public' AND p.proname IN('register_workout_atomic','get_workout_strength_catalogue_context','resolve_confirmed_workout_strength_capture','read_or_admit_workout_strength_command','register_workout_strength_atomic','answer_confirmed_workout_strength')))
 THEN RAISE EXCEPTION 'C59S9_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_answers_fixture.sql
SELECT md5(jsonb_agg(jsonb_build_object('oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'comment',obj_description(p.oid,'pg_proc')) ORDER BY p.oid)::text) AS fingerprint
 FROM pg_proc p WHERE p.oid IN('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure,
 'public.get_workout_strength_catalogue_context()'::regprocedure,'private.workout_strength_fact_snapshot(uuid,uuid,uuid)'::regprocedure,
 'public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)'::regprocedure,'public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)'::regprocedure,
 'public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure,'private.assert_trusted_backend()'::regprocedure)
\gset s9_
SELECT md5((c59s9_fixture.object_fingerprint()->'relations')::text) AS relation_fingerprint
\gset s9_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)') IS NULL THEN RAISE EXCEPTION 'C59S9_SETUP_UNIMPLEMENTED';END IF;END$$;
DO $owners$DECLARE i integer;u uuid;l uuid;BEGIN FOR i IN 11..14 LOOP
 u:=('c59aa000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;l:=('c59aa000-0000-0000-0000-'||lpad((i+100)::text,12,'0'))::uuid;
 INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES(u,'c59s9-'||u,'C59S9 synthetic','America/Sao_Paulo','{"c59a2_synthetic":true,"c59s9_fixture":"c59s9_answers_v1"}');
 INSERT INTO private.workout_strength_lifecycles VALUES(u,l,'2026-10-01T00:00:00Z',NULL,NULL);
 PERFORM c59s9_fixture.seed(u,l,'capture-'||i,'c59s9_unknown_'||i);END LOOP;END $owners$;
INSERT INTO c59s9_fixture.ownership VALUES('c59s9_answers_v1',session_user,c59s9_fixture.object_oids(),c59s9_fixture.object_fingerprint());
COMMIT;
\echo C59S9_CONCURRENCY_SETUP_CONFIRMED
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S9_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s9_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs','workout_types')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_commands')))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='private' AND p.proname='workout_strength_fact_snapshot')
 OR(n.nspname='public' AND p.proname IN('register_workout_atomic','get_workout_strength_catalogue_context','resolve_confirmed_workout_strength_capture','read_or_admit_workout_strength_command','register_workout_strength_atomic','answer_confirmed_workout_strength')))
 THEN RAISE EXCEPTION 'C59S9_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_answers_fixture.sql
SELECT md5(jsonb_agg(jsonb_build_object('oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'comment',obj_description(p.oid,'pg_proc')) ORDER BY p.oid)::text) AS fingerprint
 FROM pg_proc p WHERE p.oid IN('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure,
 'public.get_workout_strength_catalogue_context()'::regprocedure,'private.workout_strength_fact_snapshot(uuid,uuid,uuid)'::regprocedure,
 'public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)'::regprocedure,'public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)'::regprocedure,
 'public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure,'private.assert_trusted_backend()'::regprocedure)
\gset s9_
SELECT md5((c59s9_fixture.object_fingerprint()->'relations')::text) AS relation_fingerprint
\gset s9_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)') IS NULL THEN RAISE EXCEPTION 'C59S9_SETUP_UNIMPLEMENTED';END IF;END$$;
SELECT c59s9_fixture.throws('SELECT public.answer_confirmed_workout_strength(''c59aa000-0000-0000-0000-000000000001'',''c59aa000-0000-0000-0000-000000000101'',''c59aa000-0000-0000-0000-000000000901'',0,''c59aa000-0000-0000-0000-000000000902'',''yes'',''key'')','22023','actual_RR_before_owner');
ROLLBACK;
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $preflight$BEGIN
 IF to_regclass('public.users') IS NULL OR to_regtype('public.protocol_enum') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN RAISE EXCEPTION 'C59S9_SETUP_PLATFORM';END IF;
 IF to_regnamespace('c59s9_fixture') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE
 (n.nspname='public' AND c.relname IN('daily_snapshots','workout_logs','workout_types')) OR(n.nspname='private' AND c.relname IN('workout_strength_lifecycles','workout_strength_operations','workout_strength_facts','workout_strength_commands')))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE(n.nspname='private' AND p.proname='workout_strength_fact_snapshot')
 OR(n.nspname='public' AND p.proname IN('register_workout_atomic','get_workout_strength_catalogue_context','resolve_confirmed_workout_strength_capture','read_or_admit_workout_strength_command','register_workout_strength_atomic','answer_confirmed_workout_strength')))
 THEN RAISE EXCEPTION 'C59S9_SETUP_UNKNOWN_OBJECT';END IF;
END $preflight$;
\ir fixtures/workout_strength_answers_fixture.sql
SELECT md5(jsonb_agg(jsonb_build_object('oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'comment',obj_description(p.oid,'pg_proc')) ORDER BY p.oid)::text) AS fingerprint
 FROM pg_proc p WHERE p.oid IN('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure,
 'public.get_workout_strength_catalogue_context()'::regprocedure,'private.workout_strength_fact_snapshot(uuid,uuid,uuid)'::regprocedure,
 'public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)'::regprocedure,'public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)'::regprocedure,
 'public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure,'private.assert_trusted_backend()'::regprocedure)
\gset s9_
SELECT md5((c59s9_fixture.object_fingerprint()->'relations')::text) AS relation_fingerprint
\gset s9_
\i :migration_path
DO $$BEGIN IF to_regprocedure('public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)') IS NULL THEN RAISE EXCEPTION 'C59S9_SETUP_UNIMPLEMENTED';END IF;END$$;
SELECT count(*) AS users FROM public.users
\gset s9_baseline_
INSERT INTO public.users(id,wpp,name,timezone,metadata) VALUES
 ('c59aa000-0000-0000-0000-000000000001','c59s9-main-a','C59S9 A','America/Sao_Paulo','{"c59a2_synthetic":true}'),
 ('c59aa000-0000-0000-0000-000000000002','c59s9-main-b','C59S9 B','America/Sao_Paulo','{"c59a2_synthetic":true}');
INSERT INTO private.workout_strength_lifecycles VALUES
 ('c59aa000-0000-0000-0000-000000000001','c59aa000-0000-0000-0000-000000000101','2026-10-01T00:00:00Z',NULL,NULL),
 ('c59aa000-0000-0000-0000-000000000002','c59aa000-0000-0000-0000-000000000102','2026-10-01T00:00:00Z',NULL,NULL);
DO $seed$BEGIN
 PERFORM c59s9_fixture.seed('c59aa000-0000-0000-0000-000000000001','c59aa000-0000-0000-0000-000000000101','capture-A','c59s9_a');
 PERFORM c59s9_fixture.seed('c59aa000-0000-0000-0000-000000000001','c59aa000-0000-0000-0000-000000000101','capture-A2','c59s9_a2');
 PERFORM c59s9_fixture.seed('c59aa000-0000-0000-0000-000000000002','c59aa000-0000-0000-0000-000000000102','capture-B','c59s9_b');
 PERFORM c59s9_fixture.seed('c59aa000-0000-0000-0000-000000000001','c59aa000-0000-0000-0000-000000000101','capture-known','musculacao','matched');
 PERFORM c59s9_fixture.seed('c59aa000-0000-0000-0000-000000000001','c59aa000-0000-0000-0000-000000000101','capture-unavailable','c59s9_unavailable','unavailable');END $seed$;
DO $fingerprint_baseline$DECLARE baseline jsonb;BEGIN
 baseline:=c59s9_fixture.object_fingerprint();
 PERFORM set_config('c59s9_test.fingerprint_baseline',baseline::text,true);
END $fingerprint_baseline$;
SET LOCAL TimeZone='Pacific/Auckland';SET LOCAL DateStyle='SQL, DMY';
DO $fingerprint_context$DECLARE actual jsonb;BEGIN
 -- Read the full payload first; only the later statement observes restored caller GUCs.
 actual:=c59s9_fixture.object_fingerprint();
 PERFORM c59s9_fixture.ok(actual=current_setting('c59s9_test.fingerprint_baseline')::jsonb
 AND current_setting('DateStyle')='SQL, DMY' AND current_setting('TimeZone')='Pacific/Auckland',
 'fingerprint_context_invariant_and_adversarial_settings_restored');
END $fingerprint_context$;
DO $metadata$DECLARE p record;BEGIN
 SELECT * INTO p FROM pg_proc WHERE oid='public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)'::regprocedure;
 PERFORM c59s9_fixture.ok(p.prosecdef AND p.provolatile='v' AND p.pronargdefaults=0 AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
 AND p.proargnames=ARRAY['p_user_id','p_expected_lifecycle_key','p_workout_log_id','p_expected_fact_revision','p_question_key','p_answer','p_operation_key']::text[]
 AND(SELECT count(*)=1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='answer_confirmed_workout_strength'),'single_RPC7_exact_names_no_defaults');END $metadata$;

SAVEPOINT canonical;
DO $canonical$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';l uuid:='c59aa000-0000-0000-0000-000000000101';f record;r jsonb;first jsonb;before jsonb;immutable jsonb;k text;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 immutable:=c59s9_fixture.immutable_state(a);
 -- Discard only this SQL function result, then recover the durable operation contents.
 PERFORM public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','answer-A');
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','answer-A');first:=r->'receipt';
 PERFORM c59s9_fixture.ok(r=jsonb_build_object('status','reuse_existing','receipt',jsonb_build_object('ownerID',a,'workoutLogID',f.workout_log_id,
 'questionKey',f.question_key,'answer','yes','operationKey','answer-A','acceptedAt',to_char((SELECT answer_accepted_at FROM private.workout_strength_facts WHERE user_id=a AND workout_log_id=f.workout_log_id) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))
 AND first->>'acceptedAt'~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$','X29_discard_function_result_exact_original_receipt_US6');
 PERFORM c59s9_fixture.ok((SELECT revision=1 AND answer='yes' AND answer_operation_key='answer-A' AND answer_accepted_at IS NOT NULL FROM private.workout_strength_facts WHERE user_id=a AND workout_log_id=f.workout_log_id)
 AND(SELECT count(*)=1 FROM private.workout_strength_operations WHERE user_id=a AND operation_kind='answer')
 AND c59s9_fixture.immutable_state(a)=immutable,'first_response_revision1_only_four_mutable_fact_fields');
 PERFORM c59s9_fixture.ok((SELECT answer_expected_revision=0 AND answer_question_key=f.question_key AND answer_value='yes'
 AND original_workout_log_id=f.workout_log_id AND live_workout_log_id=f.workout_log_id AND answer_receipt=first
 FROM private.workout_strength_operations WHERE user_id=a AND operation_kind='answer' AND operation_key='answer-A'),'A_original_canonical_revision0_persisted');
 before:=c59s9_fixture.state(a);
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,1,f.question_key,'yes','answer-A');
 PERFORM c59s9_fixture.ok(r='{"status":"conflict","reason":"operation_content_conflict"}'::jsonb AND c59s9_fixture.state(a)=before,'A_revision_only_change_content_conflict_before_CAS');
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'no','answer-A');
 PERFORM c59s9_fixture.ok(r='{"status":"conflict","reason":"operation_content_conflict"}'::jsonb AND c59s9_fixture.state(a)=before,'A_answer_change_content_conflict');
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','answer-B-stale');
 PERFORM c59s9_fixture.ok(r='{"status":"conflict","reason":"stale_fact"}'::jsonb AND c59s9_fixture.state(a)=before,'new_B_revision0_stale_no_negative_binding');
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,1,f.question_key,'no','answer-B-diff');
 PERFORM c59s9_fixture.ok(r='{"status":"conflict","reason":"answer_already_differs"}'::jsonb AND c59s9_fixture.state(a)=before,'new_B_revision1_different_answer_no_overwrite');
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,1,f.question_key,'yes','answer-B');
 PERFORM c59s9_fixture.ok(r=jsonb_build_object('status','reuse_existing','receipt',first)
 AND(SELECT operation_key='answer-B' AND answer_expected_revision=1 AND answer_value='yes' AND answer_receipt=first
 AND answer_receipt->>'operationKey'='answer-A' FROM private.workout_strength_operations WHERE user_id=a AND operation_kind='answer' AND operation_key='answer-B'),
 'B_canonicalB_revision1_keyB_but_exact_receiptA');
 before:=c59s9_fixture.state(a);r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,1,f.question_key,'yes','answer-B');
 PERFORM c59s9_fixture.ok(r=jsonb_build_object('status','reuse_existing','receipt',first) AND c59s9_fixture.state(a)=before,'B_replay_preserves_winner_receipt_and_original_canonical');
 FOREACH k IN ARRAY ARRAY['answer-b',' answer-B ',' '] LOOP
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,1,f.question_key,'yes',k);
 PERFORM c59s9_fixture.ok(r=jsonb_build_object('status','reuse_existing','receipt',first)
 AND(SELECT answer_expected_revision=1 AND answer_receipt=first FROM private.workout_strength_operations WHERE user_id=a AND operation_kind='answer' AND operation_key COLLATE "C"=k COLLATE "C"),
 'raw_C_key_distinct:'||encode(convert_to(k,'UTF8'),'hex'));END LOOP;
 PERFORM c59s9_fixture.ok(c59s9_fixture.immutable_state(a)=immutable AND(SELECT count(*)=5 FROM private.workout_strength_operations WHERE user_id=a AND operation_kind='answer'),'canonical_positive_immutable_snapshots_capture_and_calendar');
END $canonical$;
ROLLBACK TO canonical;RELEASE canonical;

SAVEPOINT negatives;
DO $negatives$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';b uuid:='c59aa000-0000-0000-0000-000000000002';l uuid:='c59aa000-0000-0000-0000-000000000101';lb uuid:='c59aa000-0000-0000-0000-000000000102';f record;f2 record;fb record;fk record;fu record;x record;r jsonb;before_a jsonb;before_b jsonb;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 SELECT * INTO STRICT f2 FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a2';
 SELECT * INTO STRICT fb FROM private.workout_strength_facts WHERE user_id=b;
 SELECT * INTO STRICT fk FROM private.workout_strength_facts WHERE user_id=a AND classification_status='matched';
 SELECT * INTO STRICT fu FROM private.workout_strength_facts WHERE user_id=a AND classification_status='unavailable';
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','key-A');
 PERFORM c59s9_fixture.ok(r->>'status'='accepted','negative_matrix_original_binding_live_positive_control');
 before_a:=c59s9_fixture.state(a);before_b:=c59s9_fixture.state(b);
 FOR x IN SELECT * FROM(VALUES
 ('unknown_workout',a,l,'c59aa000-0000-0000-0000-000000000999'::uuid,f.question_key,'forbidden','stale_workout'),
 ('foreign_workout',a,l,fb.workout_log_id,fb.question_key,'forbidden','stale_workout'),
 ('foreign_owner_scoped',b,lb,f.workout_log_id,f.question_key,'forbidden','stale_workout'),
 ('random_question_before_lookup',a,l,f.workout_log_id,'c59aa000-0000-0000-0000-000000000998'::uuid,'forbidden','stale_fact'),
 ('other_question_before_lookup',a,l,f.workout_log_id,f2.question_key,'forbidden','stale_fact'),
 ('foreign_lifecycle',a,lb,f.workout_log_id,f.question_key,'forbidden','stale_lifecycle'),
 ('missing_lifecycle',a,'c59aa000-0000-0000-0000-000000000997'::uuid,f.workout_log_id,f.question_key,'forbidden','stale_lifecycle'),
 ('live_original_new_valid_target',a,l,f2.workout_log_id,f2.question_key,'conflict','operation_content_conflict'),
 ('matched_before_question',a,l,fk.workout_log_id,f.question_key,'forbidden','not_unrecognized'),
 ('unavailable_before_question',a,l,fu.workout_log_id,f.question_key,'forbidden','not_unrecognized'))t(label,u,life,w,q,status,reason) LOOP
 r:=public.answer_confirmed_workout_strength(x.u,x.life,x.w,0,x.q,'yes','key-A');
 PERFORM c59s9_fixture.ok(r=jsonb_build_object('status',x.status,'reason',x.reason)
 AND c59s9_fixture.state(a)=before_a AND c59s9_fixture.state(b)=before_b,'negative_precedence_zero_writes:'||x.label);END LOOP;
 r:=public.answer_confirmed_workout_strength(a,l,f2.workout_log_id,0,f2.question_key,'no','new-A2');
 PERFORM c59s9_fixture.ok(r->>'status'='accepted' AND r#>>'{receipt,workoutLogID}'=f2.workout_log_id::text,'other_valid_owned_target_new_key_is_allowed');
 r:=public.answer_confirmed_workout_strength(b,lb,fb.workout_log_id,0,fb.question_key,'no','key-A');
 PERFORM c59s9_fixture.ok(r->>'status'='accepted' AND r#>>'{receipt,ownerID}'=b::text
 AND(SELECT answer='yes' FROM private.workout_strength_facts WHERE user_id=a AND workout_log_id=f.workout_log_id),'operation_key_is_owned_not_global');
END $negatives$;
ROLLBACK TO negatives;RELEASE negatives;

SAVEPOINT contradictory;
DO $contradictory$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';l uuid:='c59aa000-0000-0000-0000-000000000101';f record;f2 record;r jsonb;before jsonb;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 SELECT * INTO STRICT f2 FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a2';
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','contradictory-A');
 -- Physical local corruption retains the existing X4 CHECK shape and canonical fields.
 UPDATE private.workout_strength_operations SET answer_receipt=jsonb_set(answer_receipt,'{acceptedAt}','"2000-01-01T00:00:00.000000Z"')
 WHERE user_id=a AND operation_kind='answer' AND operation_key='contradictory-A';
 before:=c59s9_fixture.state(a);
 PERFORM c59s9_fixture.ok((SELECT answer_receipt IS DISTINCT FROM private.workout_strength_fact_snapshot(a,l,f.workout_log_id)#>'{clarification,receipt}'
 FROM private.workout_strength_operations WHERE user_id=a AND operation_kind='answer' AND operation_key='contradictory-A'),'contradictory_receipt_CHECK_valid_premise');
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','contradictory-A');
 PERFORM c59s9_fixture.ok(r='{"status":"forbidden","reason":"stale_workout"}'::jsonb AND c59s9_fixture.state(a)=before,'contradictory_receipt_denied_against_ORIGINAL_fact');
 r:=public.answer_confirmed_workout_strength(a,l,f2.workout_log_id,0,f2.question_key,'no','contradictory-A');
 PERFORM c59s9_fixture.ok(r='{"status":"forbidden","reason":"stale_workout"}'::jsonb AND c59s9_fixture.state(a)=before,'contradictory_original_receipt_precedes_new_valid_target_canonical');
END $contradictory$;
ROLLBACK TO contradictory;RELEASE contradictory;

SAVEPOINT missing_fact;
DO $missing$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';l uuid:='c59aa000-0000-0000-0000-000000000101';f record;r jsonb;before jsonb;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 DELETE FROM private.workout_strength_facts WHERE user_id=a AND workout_log_id=f.workout_log_id;before:=c59s9_fixture.state(a);
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','missing-fact');
 PERFORM c59s9_fixture.ok(r='{"status":"forbidden","reason":"stale_workout"}'::jsonb AND c59s9_fixture.state(a)=before,'missing_fact_is_not_new_authority');END $missing$;
ROLLBACK TO missing_fact;RELEASE missing_fact;
SAVEPOINT anchor;
DO $anchor$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';l uuid:='c59aa000-0000-0000-0000-000000000101';f record;r jsonb;before jsonb;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 UPDATE public.workout_logs SET performed_at=performed_at+interval '1 second' WHERE user_id=a AND id=f.workout_log_id;before:=c59s9_fixture.state(a);
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','invalid-anchor');
 PERFORM c59s9_fixture.ok(r='{"status":"forbidden","reason":"stale_workout"}'::jsonb AND c59s9_fixture.state(a)=before,'real_anchor_mismatch_is_stale');END $anchor$;
ROLLBACK TO anchor;RELEASE anchor;

SAVEPOINT lifecycle;
DO $life$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';l uuid:='c59aa000-0000-0000-0000-000000000101';newlife uuid:='c59aa000-0000-0000-0000-000000000201';f record;r jsonb;before jsonb;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','before-close');
 UPDATE private.workout_strength_lifecycles SET closed_at='2026-10-14T00:00:00Z',close_operation_key='fixture-close' WHERE user_id=a AND lifecycle_key=l;
 INSERT INTO private.workout_strength_lifecycles VALUES(a,newlife,'2026-10-14T00:00:00Z',NULL,NULL);before:=c59s9_fixture.state(a);
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','before-close');
 PERFORM c59s9_fixture.ok(r='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb AND c59s9_fixture.state(a)=before,'closed_lifecycle_before_replay_not_reset_integration');
 r:=public.answer_confirmed_workout_strength(a,newlife,f.workout_log_id,0,f.question_key,'yes','before-close');
 PERFORM c59s9_fixture.ok(r='{"status":"forbidden","reason":"stale_workout"}'::jsonb AND c59s9_fixture.state(a)=before,'oldlife_fact_never_rebound_to_new_lifecycle');END $life$;
ROLLBACK TO lifecycle;RELEASE lifecycle;

SAVEPOINT no_current_catalogue;
ALTER TABLE public.workout_types RENAME TO c59s9_unused_catalogue;
UPDATE public.users SET timezone='unproved-current-zone' WHERE id='c59aa000-0000-0000-0000-000000000001';
DO $no_catalogue$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';l uuid:='c59aa000-0000-0000-0000-000000000101';f record;r jsonb;immutable jsonb;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';immutable:=c59s9_fixture.immutable_state(a);
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'no','no-current-catalogue');
 PERFORM c59s9_fixture.ok(r->>'status'='accepted' AND r#>>'{receipt,answer}'='no' AND c59s9_fixture.immutable_state(a)=immutable,
 'answer_uses_historical_fact_without_current_catalogue_or_zone');END $no_catalogue$;
ROLLBACK TO no_current_catalogue;RELEASE no_current_catalogue;

SAVEPOINT atomic;
SELECT set_config('c59s9_test.before_atomic',c59s9_fixture.state('c59aa000-0000-0000-0000-000000000001')::text,true);
ALTER TABLE private.workout_strength_operations ADD CONSTRAINT c59s9_reject_answer CHECK(operation_kind<>'answer') NOT VALID;
DO $fingerprint_constraint$DECLARE actual jsonb;definition text;BEGIN
 actual:=c59s9_fixture.object_fingerprint();
 SELECT pg_get_constraintdef(oid,true) INTO STRICT definition FROM pg_constraint
 WHERE conrelid='private.workout_strength_operations'::regclass AND conname='c59s9_reject_answer';
 PERFORM c59s9_fixture.ok(actual IS DISTINCT FROM current_setting('c59s9_test.fingerprint_baseline')::jsonb
 AND actual#>'{relations,private.workout_strength_operations,constraints}' @> jsonb_build_array(jsonb_build_array('c59s9_reject_answer',definition)),
 'fingerprint_detects_real_atomic_CHECK_constraint');
END $fingerprint_constraint$;
DO $atomic$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';l uuid:='c59aa000-0000-0000-0000-000000000101';f record;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 PERFORM c59s9_fixture.throws(format('SELECT public.answer_confirmed_workout_strength(%L,%L,%L,0,%L,%L,%L)',a,l,f.workout_log_id,f.question_key,'yes','atomic-failure'),'23514','physical_answer_insert_failure_propagates');
 PERFORM c59s9_fixture.ok(c59s9_fixture.state(a)=current_setting('c59s9_test.before_atomic')::jsonb,'answer_insert_failure_rolls_back_fact_update_and_every_binding');END $atomic$;
ALTER TABLE private.workout_strength_operations DROP CONSTRAINT c59s9_reject_answer;
DO $retry$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';l uuid:='c59aa000-0000-0000-0000-000000000101';f record;r jsonb;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,0,f.question_key,'yes','atomic-failure');
 PERFORM c59s9_fixture.ok(r->>'status'='accepted' AND(SELECT revision=1 FROM private.workout_strength_facts WHERE user_id=a AND workout_log_id=f.workout_log_id)
 AND(SELECT count(*)=1 FROM private.workout_strength_operations WHERE user_id=a AND operation_kind='answer'),'same_operation_can_succeed_after_full_rollback');END $retry$;
ROLLBACK TO atomic;RELEASE atomic;

SAVEPOINT correction;
DO $correction$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';b uuid:='c59aa000-0000-0000-0000-000000000002';l uuid:='c59aa000-0000-0000-0000-000000000101';old record;newfact record;r jsonb;receipt jsonb;replacement jsonb;before jsonb;other_owner jsonb;BEGIN
 SELECT * INTO STRICT old FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 r:=public.answer_confirmed_workout_strength(a,l,old.workout_log_id,0,old.question_key,'yes','before-correction');receipt:=r->'receipt';other_owner:=c59s9_fixture.state(b);
 replacement:=c59s9_fixture.seed(a,l,'replacement','c59s9_a','unrecognized','{"p_duration_min":80,"p_estimated_kcal":400,"p_replace_recent":true,"p_replace_since":"2000-01-01T00:00:00Z"}');
 SELECT * INTO STRICT newfact FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';
 PERFORM c59s9_fixture.ok(replacement#>>'{legacy_result,replaced_count}'='1' AND replacement#>>'{legacy_result,exercise_calories}'='1300'
 AND newfact.workout_log_id<>old.workout_log_id AND newfact.question_key<>old.question_key AND newfact.revision=0 AND newfact.answer IS NULL
 AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE id=old.workout_log_id),'actual_old_correction_new_UUID_question_no_answer_carryover');
 PERFORM c59s9_fixture.ok((SELECT live_workout_log_id IS NULL AND original_workout_log_id=old.workout_log_id AND answer_receipt=receipt
 FROM private.workout_strength_operations WHERE user_id=a AND operation_kind='answer' AND operation_key='before-correction'),
 'correction_tombstone_keeps_original_canonical_receipt');
 before:=c59s9_fixture.state(a);
 r:=public.answer_confirmed_workout_strength(a,l,old.workout_log_id,0,old.question_key,'yes','before-correction');
 PERFORM c59s9_fixture.ok(r='{"status":"forbidden","reason":"stale_workout"}'::jsonb AND c59s9_fixture.state(a)=before,'X29_corrected_UUID_denied_before_original_replay');
 r:=public.answer_confirmed_workout_strength(a,l,newfact.workout_log_id,0,newfact.question_key,'no','before-correction');
 PERFORM c59s9_fixture.ok(r='{"status":"forbidden","reason":"stale_workout"}'::jsonb AND c59s9_fixture.state(a)=before,'tombstone_original_new_valid_target_is_stale_not_content_conflict');
 r:=public.answer_confirmed_workout_strength(a,l,newfact.workout_log_id,0,old.question_key,'yes','new-replacement');
 PERFORM c59s9_fixture.ok(r='{"status":"forbidden","reason":"stale_fact"}'::jsonb AND c59s9_fixture.state(a)=before,'old_question_cannot_answer_replacement');
 r:=public.answer_confirmed_workout_strength(a,l,newfact.workout_log_id,0,newfact.question_key,'no','new-replacement');
 PERFORM c59s9_fixture.ok(r->>'status'='accepted' AND r#>>'{receipt,answer}'='no' AND c59s9_fixture.state(b)=other_owner,
 'replacement_owns_new_answer_other_owner300_unchanged');END $correction$;
ROLLBACK TO correction;RELEASE correction;

DO $syntax$DECLARE a uuid:='c59aa000-0000-0000-0000-000000000001';l uuid:='c59aa000-0000-0000-0000-000000000101';f record;x record;r jsonb;before jsonb;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id=a AND stored_workout_type='c59s9_a';before:=c59s9_fixture.state(a);
 FOR x IN SELECT * FROM(VALUES
 ('owner',NULL::uuid,l,f.workout_log_id,0,f.question_key,'yes','key'),('lifecycle',a,NULL::uuid,f.workout_log_id,0,f.question_key,'yes','key'),
 ('workout',a,l,NULL::uuid,0,f.question_key,'yes','key'),('revision_null',a,l,f.workout_log_id,NULL::integer,f.question_key,'yes','key'),
 ('revision_negative',a,l,f.workout_log_id,-1,f.question_key,'yes','key'),('question',a,l,f.workout_log_id,0,NULL::uuid,'yes','key'),
 ('answer_null',a,l,f.workout_log_id,0,f.question_key,NULL::text,'key'),('answer_case',a,l,f.workout_log_id,0,f.question_key,'YES','key'),
 ('answer_padded',a,l,f.workout_log_id,0,f.question_key,'yes ','key'),('answer_empty',a,l,f.workout_log_id,0,f.question_key,'','key'),
 ('key_null',a,l,f.workout_log_id,0,f.question_key,'yes',NULL::text),('key_empty',a,l,f.workout_log_id,0,f.question_key,'yes',''))t(label,u,life,w,rev,q,ans,key) LOOP
 PERFORM c59s9_fixture.throws(format('SELECT public.answer_confirmed_workout_strength(%L,%L,%L,%L,%L,%L,%L)',x.u,x.life,x.w,x.rev,x.q,x.ans,x.key),'22023','syntax:'||x.label);END LOOP;
 PERFORM c59s9_fixture.throws(format('SELECT public.answer_confirmed_workout_strength(%L,%L,%L,0,%L,%L,%L)',
 'c59aa000-0000-0000-0000-000000000999',l,f.workout_log_id,f.question_key,'yes','missing-owner'),'P0002','missing_owner_P0002');
 r:=public.answer_confirmed_workout_strength(a,l,f.workout_log_id,1,f.question_key,'yes','new-stale-revision');
 PERFORM c59s9_fixture.ok(r='{"status":"conflict","reason":"stale_fact"}'::jsonb AND c59s9_fixture.state(a)=before,'new_request_CAS1_unanswered_fact0_zero_writes');
 PERFORM c59s9_fixture.ok(c59s9_fixture.state(a)=before,'syntax_and_missing_owner_leave_no_negative_bindings');END $syntax$;
SAVEPOINT inactive;
UPDATE public.users SET status='deleted' WHERE id='c59aa000-0000-0000-0000-000000000001';
DO $inactive$DECLARE f record;BEGIN
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id='c59aa000-0000-0000-0000-000000000001' AND stored_workout_type='c59s9_a';
 PERFORM c59s9_fixture.throws(format('SELECT public.answer_confirmed_workout_strength(%L,%L,%L,0,%L,%L,%L)',f.user_id,f.lifecycle_key,f.workout_log_id,f.question_key,'yes','inactive'),'P0002','inactive_owner_P0002');END $inactive$;
ROLLBACK TO inactive;RELEASE inactive;

DO $acl$DECLARE p record;f record;r jsonb;role_name text;code text;BEGIN
 SELECT * INTO p FROM pg_proc WHERE oid='public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)'::regprocedure;
 SELECT * INTO STRICT f FROM private.workout_strength_facts WHERE user_id='c59aa000-0000-0000-0000-000000000001' AND stored_workout_type='c59s9_a';
 PERFORM c59s9_fixture.ok(NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 WHERE a.grantee NOT IN(p.proowner,(SELECT oid FROM pg_roles WHERE rolname='service_role')) OR(a.grantee<>p.proowner AND a.is_grantable)),'answer_ACL_owner_service_only');
 EXECUTE 'SET LOCAL ROLE service_role';r:=public.answer_confirmed_workout_strength(f.user_id,f.lifecycle_key,f.workout_log_id,0,f.question_key,'yes','actual-service');EXECUTE 'RESET ROLE';
 PERFORM c59s9_fixture.ok(r->>'status'='accepted' AND r#>>'{receipt,answer}'='yes','actual_service_answer_without_private_DML_grants');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
 PERFORM c59s9_fixture.ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'EXECUTE_denied:'||role_name);
 EXECUTE format('SET LOCAL ROLE %I',role_name);code:=NULL;
 BEGIN PERFORM public.answer_confirmed_workout_strength(NULL,NULL,NULL,NULL,NULL,NULL,NULL);EXCEPTION WHEN OTHERS THEN code:=SQLSTATE;END;
 EXECUTE 'RESET ROLE';PERFORM c59s9_fixture.ok(code='42501','actual_ACL_denied:'||role_name);END LOOP;END $acl$;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
SELECT c59s9_fixture.throws('SELECT public.answer_confirmed_workout_strength(NULL,NULL,NULL,NULL,NULL,NULL,NULL)','42501','trusted_guard_precedes_invalid_syntax');
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT c59s9_fixture.ok((SELECT md5(jsonb_agg(jsonb_build_object('oid',p.oid::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::text,'comment',obj_description(p.oid,'pg_proc')) ORDER BY p.oid)::text)
 FROM pg_proc p WHERE p.oid IN('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure,
 'public.get_workout_strength_catalogue_context()'::regprocedure,'private.workout_strength_fact_snapshot(uuid,uuid,uuid)'::regprocedure,
 'public.resolve_confirmed_workout_strength_capture(uuid,uuid,text,text)'::regprocedure,'public.read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb)'::regprocedure,
 'public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure,'private.assert_trusted_backend()'::regprocedure))=:'s9_fingerprint','legacy_capture_and_neighbors_definitions_ACL_owner_preserved');
SELECT c59s9_fixture.ok(md5((c59s9_fixture.object_fingerprint()->'relations')::text)=:'s9_relation_fingerprint','all_existing_relation_columns_constraints_indexes_ACL_preserved');
ROLLBACK;
SELECT to_regnamespace('c59s9_fixture') IS NULL AND to_regclass('public.workout_logs') IS NULL AND to_regclass('public.daily_snapshots') IS NULL
 AND to_regclass('public.workout_types') IS NULL AND to_regclass('private.workout_strength_facts') IS NULL
 AND to_regclass('private.workout_strength_commands') IS NULL AND to_regprocedure('public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)') IS NULL
 AND(SELECT count(*) FROM public.users)=:'s9_baseline_users'::bigint AS rollback_ok
\gset s9_
\if :s9_rollback_ok
\echo C59S9_ROLLBACK_CONFIRMED
\else
DO $$BEGIN RAISE EXCEPTION 'C59S9_ROLLBACK_MISMATCH';END$$;
\endif
\endif
\endif
