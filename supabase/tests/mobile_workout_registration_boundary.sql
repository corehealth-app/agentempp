\set ON_ERROR_STOP on
-- Explicit post-DDL continuation. The default 71-label path below is retained byte-for-byte.
\if :{?postddl_mode}
\else
\set postddl_mode false
\endif
\if :{?prepare_postddl}
\else
\set prepare_postddl false
\endif
-- Real Root-installed product only. Missing new entrypoints are SETUP, not product RED.
\if :{?prepare_historical}
\else
\set prepare_historical false
\endif
\if :{?setup_concurrency}
\else
\set setup_concurrency false
\endif
\if :{?teardown_concurrency}
\else
\set teardown_concurrency false
\endif
\if :{?dry_cleanup_baseline}
\else
\set dry_cleanup_baseline false
\endif
SELECT (:'prepare_historical')::boolean::integer+(:'setup_concurrency')::boolean::integer+(:'teardown_concurrency')::boolean::integer+(:'dry_cleanup_baseline')::boolean::integer<=1 AS one_mode
\gset s17b_
\if :s17b_one_mode
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17B_SETUP_CONFLICTING_MODES';END$$;
\endif
SELECT (NOT (:'prepare_postddl')::boolean OR ((:'postddl_mode')::boolean
 AND NOT ((:'prepare_historical')::boolean OR (:'setup_concurrency')::boolean OR (:'teardown_concurrency')::boolean OR (:'dry_cleanup_baseline')::boolean)))
 AND NOT ((:'postddl_mode')::boolean AND (:'prepare_historical')::boolean) AS postddl_modes_valid
\gset s17b_
\if :s17b_postddl_modes_valid
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17B_SETUP_CONFLICTING_POSTDDL_MODES';END$$;
\endif
\if :postddl_mode
\if :{?postddl_expected_four_json}
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17B_SETUP_POSTDDL_EXPECTED_FOUR_REQUIRED';END$$;
\endif
\else
DO $$BEGIN IF to_regclass('c59s17b_fixture.postddl_origin') IS NOT NULL THEN RAISE EXCEPTION 'C59S17B_SETUP_POSTDDL_SELECTOR_REQUIRED';END IF;END$$;
\endif
DO $target$ BEGIN
 IF session_user<>'c5_local_admin' OR current_database()<>'c5_reset_default_20261009' OR current_setting('port')<>'55489'
 OR current_setting('listen_addresses')<>'' OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
 THEN RAISE EXCEPTION 'C59S17B_SETUP_WRONG_LOCAL_TARGET';END IF;
 IF to_regprocedure('private.assert_trusted_backend()') IS NULL OR to_regprocedure('public.admit_mobile_workout_proposal(uuid,text,jsonb)') IS NULL
 OR to_regprocedure('public.materialize_mobile_workout_proposal(uuid,uuid,jsonb,jsonb,timestamp with time zone)') IS NULL
 OR to_regprocedure('public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)') IS NULL
 OR to_regprocedure('public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'C59S17B_SETUP_REAL_SUBSTRATE_ABSENT' USING ERRCODE='42883';END IF;
END $target$;
\if :prepare_postddl
\ir fixtures/mobile_workout_registration_boundary_postddl_fixture.sql
\else
\if :prepare_historical
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $pre$ BEGIN
 IF to_regnamespace('c59s17b_fixture') IS NOT NULL OR to_regprocedure('public.admit_mobile_workout_registration(uuid,text,jsonb)') IS NOT NULL
 OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.pending_registrations'::regclass AND attname='workout_ui_admission_id' AND NOT attisdropped)
 THEN RAISE EXCEPTION 'C59S17B_SETUP_PREPARE_COLLISION';END IF;
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id IN(SELECT('c59b7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(501,504)i UNION ALL SELECT('c59b7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(701,740)i UNION ALL SELECT('c59b7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM unnest(ARRAY[901,902,903,999])i)
 OR email IN(SELECT 'c59s17b-'||i||'@example.invalid' FROM generate_series(501,504)i UNION ALL SELECT 'c59s17b-'||i||'@example.invalid' FROM generate_series(701,740)i UNION ALL SELECT 'c59s17b-'||i||'@example.invalid' FROM unnest(ARRAY[901,902,903,999])i)
 OR wpp IN(SELECT '155517'||lpad(i::text,7,'0') FROM generate_series(501,504)i UNION ALL SELECT '155517'||lpad(i::text,7,'0') FROM generate_series(701,740)i UNION ALL SELECT '155517'||lpad(i::text,7,'0') FROM unnest(ARRAY[901,902,903,999])i))
 THEN RAISE EXCEPTION 'C59S17B_SETUP_OWNER_COLLISION';END IF;
 IF(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure) IS DISTINCT FROM 'e982fbe59c4f569e58211e646c1eb8d8'
 THEN RAISE EXCEPTION 'C59S17B_SETUP_OLD_WRITER_DRIFT';END IF;
END $pre$;
\ir fixtures/mobile_workout_registration_boundary_fixture.sql
DO $history$ DECLARE i integer;u uuid;k text;v jsonb:=c59s17b_fixture.input();a jsonb;r jsonb;pid uuid;payload jsonb; BEGIN
 FOR i IN 901..903 LOOP
 u:=c59s17b_fixture.owner(i);k:=c59s17b_fixture.key(i);
 IF i=902 THEN r:=public.replace_pending_registration_atomic(u,'{"kind":"meal","mealType":"jantar"}',clock_timestamp()+interval '1 hour',k);pid:=(r->>'pending_id')::uuid;END IF;
 a:=public.admit_mobile_workout_proposal(u,k,v);
 IF a->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S17B_SETUP_OLD_REAL_ADMIT';END IF;
 payload:=jsonb_build_object('ownerID',u,'requestKey',k,'input',v,'admission',a->'admission');
 IF i IN(901,902)THEN
 r:=public.materialize_mobile_workout_proposal(u,(a#>>'{admission,admissionID}')::uuid,v,c59s17b_fixture.proposal(k,v),clock_timestamp()+interval '1 hour');
 IF(i=901 AND r->>'status' IS DISTINCT FROM 'materialized')OR(i=902 AND r IS DISTINCT FROM '{"status":"conflict","reason":"unproved_pending"}'::jsonb)THEN RAISE EXCEPTION 'C59S17B_SETUP_OLD_REAL_MATERIALIZE';END IF;
 payload:=payload||jsonb_build_object('materialized',r);END IF;
 INSERT INTO c59s17b_fixture.historical VALUES(CASE i WHEN 901 THEN 'bound-null' WHEN 902 THEN 'collision-null' ELSE 'unbound-null' END,u,payload,c59s17b_fixture.state(u));
 END LOOP;
 INSERT INTO c59s17b_fixture.ownership VALUES('c59s17b_ui_boundary_v1',session_user,c59s17b_fixture.fingerprint(),c59s17b_fixture.functions());
END $history$;
COMMIT;
\echo C59S17B_HISTORICAL_PREPARED
\else
\if :teardown_concurrency
-- Cleanup is also valid after prepare COMMIT when product DDL was never applied.
\else
DO $installed$BEGIN
 IF to_regprocedure('public.admit_mobile_workout_registration(uuid,text,jsonb)') IS NULL OR to_regprocedure('public.materialize_mobile_workout_registration(uuid,uuid,jsonb,jsonb,timestamp with time zone)') IS NULL
 OR to_regprocedure('public.get_mobile_workout_registration(uuid,uuid)') IS NULL OR to_regclass('private.mobile_workout_registration_edit_receipts') IS NULL
 THEN RAISE EXCEPTION 'C59S17B_SETUP_NEW_ENTRYPOINT_ABSENT' USING ERRCODE='42883';END IF;
 IF to_regnamespace('c59s17b_fixture') IS NULL THEN RAISE EXCEPTION 'C59S17B_SETUP_HISTORICAL_PREPARE_ABSENT';END IF;
END $installed$;
\endif
\if :teardown_concurrency
\set cleanup true
\else
\set cleanup :dry_cleanup_baseline
\endif
\if :cleanup
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
\if :postddl_mode
\ir fixtures/mobile_workout_registration_boundary_postddl_fixture.sql
\endif
DO $cleanup$DECLARE o record;h record;c record;u uuid;n integer;count_cases integer;expected_admission jsonb;j record;BEGIN
 SELECT * INTO STRICT o FROM c59s17b_fixture.ownership WHERE tag='c59s17b_ui_boundary_v1';
 IF o.owner_name<>session_user OR o.fixture_fingerprint IS DISTINCT FROM c59s17b_fixture.fingerprint()
 OR(SELECT count(*)FROM c59s17b_fixture.ownership)<>1 OR(SELECT array_agg(case_id ORDER BY case_id)FROM c59s17b_fixture.historical)IS DISTINCT FROM ARRAY['bound-null','collision-null','unbound-null']
 THEN RAISE EXCEPTION 'C59S17B_TEARDOWN_OBJECT_DRIFT';END IF;
 FOR h IN SELECT * FROM c59s17b_fixture.historical ORDER BY owner_id LOOP
 IF h.owner_id IS DISTINCT FROM (CASE h.case_id WHEN 'bound-null' THEN c59s17b_fixture.uid(901) WHEN 'collision-null' THEN c59s17b_fixture.uid(902) ELSE c59s17b_fixture.uid(903) END)
 OR c59s17b_fixture.old_shape(c59s17b_fixture.state(h.owner_id)) IS DISTINCT FROM h.old_state THEN RAISE EXCEPTION 'C59S17B_TEARDOWN_HISTORICAL_DRIFT';END IF;
 END LOOP;
 SELECT count(*)INTO count_cases FROM c59s17b_fixture.cases;
 IF count_cases NOT IN(0,5)THEN RAISE EXCEPTION 'C59S17B_TEARDOWN_CASESET_DRIFT';END IF;
 IF count_cases=5 THEN
 IF(SELECT array_agg(case_id ORDER BY case_id)FROM c59s17b_fixture.cases)IS DISTINCT FROM ARRAY['membership-13-commit','membership-13-rollback','membership-s8-commit','membership-s8-rollback','sentinel']THEN RAISE EXCEPTION 'C59S17B_TEARDOWN_CASESET_DRIFT';END IF;
 FOR c IN SELECT * FROM c59s17b_fixture.cases ORDER BY owner_id LOOP
 n:=CASE c.case_id WHEN 'membership-13-commit' THEN 501 WHEN 'membership-13-rollback' THEN 502 WHEN 'membership-s8-commit' THEN 503 WHEN 'membership-s8-rollback' THEN 504 ELSE 999 END;u:=c59s17b_fixture.uid(n);
 IF c.owner_id IS DISTINCT FROM u OR c.payload->>'ownerID' IS DISTINCT FROM u::text OR c.payload->>'requestKey' IS DISTINCT FROM c59s17b_fixture.key(n)
 OR c.payload->'input' IS DISTINCT FROM c59s17b_fixture.input()
 OR NOT EXISTS(SELECT 1 FROM ONLY public.users WHERE id=u AND email='c59s17b-'||n||'@example.invalid'AND wpp='155517'||lpad(n::text,7,'0')AND name='C59S17B synthetic'AND country='US'AND timezone='UTC'AND country_confirmed AND flow_phrase_cursor_revision=17 AND metadata='{"c59s17b_fixture":"c59s17b_ui_boundary_v1"}'::jsonb)
 THEN RAISE EXCEPTION 'C59S17B_TEARDOWN_OWNER_DRIFT';END IF;
 IF n IN(502,504)THEN
 IF EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions WHERE user_id=u)THEN RAISE EXCEPTION 'C59S17B_TEARDOWN_ROLLBACK_ADMISSION_DRIFT';END IF;
 ELSE
 expected_admission:=c.payload->'admission';
 SELECT * INTO STRICT j FROM private.mobile_workout_proposal_admissions WHERE user_id=u;
 IF expected_admission IS NULL OR expected_admission->>'ownerID'IS DISTINCT FROM u::text OR expected_admission->>'admissionID'IS DISTINCT FROM j.admission_id::text
 OR expected_admission->>'epoch'IS DISTINCT FROM j.epoch::text OR expected_admission->>'requestHash'IS DISTINCT FROM j.request_hash OR expected_admission->>'requestKey'IS DISTINCT FROM j.request_key
 OR expected_admission->>'admittedAt'IS DISTINCT FROM to_char(j.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
 OR j.request_hash IS DISTINCT FROM private.mobile_workout_proposal_input_hash(c.payload->'input')OR j.request_key IS DISTINCT FROM c59s17b_fixture.key(n)OR j.content_revision IS DISTINCT FROM 0 OR j.pending_id IS NULL
 OR NOT EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE id=j.pending_id AND user_id=u AND workout_ui_admission_id=j.admission_id)
 THEN RAISE EXCEPTION 'C59S17B_TEARDOWN_ADMISSION_DRIFT';END IF;
 END IF;
 IF n=999 AND c.payload->'sentinelState'IS DISTINCT FROM c59s17b_fixture.state(u)THEN RAISE EXCEPTION 'C59S17B_TEARDOWN_SENTINEL_DRIFT';END IF;
 END LOOP;END IF;
 -- Validate every historical owner and case before any destructive statement.
 FOR u IN SELECT owner_id FROM c59s17b_fixture.historical UNION SELECT owner_id FROM c59s17b_fixture.cases LOOP DELETE FROM public.users WHERE id=u;END LOOP;
END $cleanup$;
DO $drop_helpers$DECLARE f record;BEGIN FOR f IN SELECT oid FROM pg_proc WHERE pronamespace='c59s17b_fixture'::regnamespace ORDER BY oid LOOP EXECUTE format('DROP FUNCTION %s',f.oid::regprocedure);END LOOP;END $drop_helpers$;
\if :postddl_mode
DROP TABLE c59s17b_fixture.postddl_origin;
\endif
DROP TABLE c59s17b_fixture.cases,c59s17b_fixture.historical,c59s17b_fixture.ownership;DROP SCHEMA c59s17b_fixture;
\if :dry_cleanup_baseline
\if :{?dry_fingerprint_path}
\i :dry_fingerprint_path
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17B_SETUP_DRY_FINGERPRINT_PATH_REQUIRED';END$$;
\endif
ROLLBACK;
\echo C59S17B_DRY_CLEAN_BASELINE_ROLLBACK_CONFIRMED
\else
COMMIT;
\echo C59S17B_CONCURRENCY_TEARDOWN_CONFIRMED
\endif
\else
\if :setup_concurrency
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\if :postddl_mode
\ir fixtures/mobile_workout_registration_boundary_postddl_fixture.sql
\endif
DO $rr$DECLARE r jsonb;sql text;u uuid:='c59b7000-0000-0000-0000-000000000740';v jsonb:=c59s17b_fixture.input();BEGIN
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id=u)THEN RAISE EXCEPTION 'C59S17B_SETUP_RR_OWNER_COLLISION';END IF;
 FOREACH sql IN ARRAY ARRAY[c59s17b_fixture.legacy_sql(c59s17b_fixture.arguments(u,'musculacao',NULL)),
 format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,c59s17b_fixture.key(740),v),
 format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,NULL,NULL)',u,c59s17b_fixture.uid(840),v)]LOOP
 r:=c59s17b_fixture.attempt(sql);IF r->>'sqlstate'IS DISTINCT FROM '22023'THEN RAISE EXCEPTION 'C59S17B_RR_NOT_REJECTED:%',r;END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'RR_public13_and_mutating_UI_wrappers_reject_before_missing_owner');
END $rr$;
ROLLBACK;
\endif
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
\if :postddl_mode
\ir fixtures/mobile_workout_registration_boundary_postddl_fixture.sql
\endif
DO $owned$DECLARE o record;BEGIN SELECT * INTO STRICT o FROM c59s17b_fixture.ownership WHERE tag='c59s17b_ui_boundary_v1';IF o.owner_name<>session_user OR o.fixture_fingerprint IS DISTINCT FROM c59s17b_fixture.fingerprint()THEN RAISE EXCEPTION 'C59S17B_SETUP_FIXTURE_DRIFT';END IF;END $owned$;
\if :setup_concurrency
DO $cases$DECLARE i integer;u uuid;p jsonb;v jsonb:=c59s17b_fixture.input();l uuid;ids text[]:=ARRAY['membership-13-commit','membership-13-rollback','membership-s8-commit','membership-s8-rollback'];BEGIN
 IF EXISTS(SELECT 1 FROM c59s17b_fixture.cases)THEN RAISE EXCEPTION 'C59S17B_SETUP_CASES_COLLISION';END IF;
 FOR i IN 501..504 LOOP u:=c59s17b_fixture.owner(i);l:=c59s17b_fixture.uid(i+100);p:=jsonb_build_object('ownerID',u,'requestKey',c59s17b_fixture.key(i),'input',v,'proposal',c59s17b_fixture.proposal(c59s17b_fixture.key(i),v),'expiresAt',clock_timestamp()+interval '1 hour','lifecycleKey',l,'operationKey','s17b-operation-'||i);
 IF i IN(503,504)THEN
 INSERT INTO private.workout_strength_lifecycles VALUES(u,l,'2026-10-15T00:00:00Z',NULL,NULL);
 PERFORM public.read_or_admit_workout_strength_command(u,l,p->>'operationKey','musculacao',c59s17b_fixture.arguments(u,'musculacao',p->>'requestKey'));
 END IF;
 INSERT INTO c59s17b_fixture.cases VALUES(ids[i-500],u,p);END LOOP;
 p:=c59s17b_fixture.ui(999,true);p:=p||jsonb_build_object('sentinelState',c59s17b_fixture.state(c59s17b_fixture.uid(999)));
 INSERT INTO c59s17b_fixture.cases VALUES('sentinel',c59s17b_fixture.uid(999),p);
END $cases$;
COMMIT;
\echo C59S17B_CONCURRENCY_SETUP_CONFIRMED
\else
DO $schema$DECLARE v boolean;t oid:='private.mobile_workout_registration_edit_receipts'::regclass;BEGIN
 PERFORM c59s17b_fixture.ok((SELECT count(*)=2 AND bool_and(NOT attnotnull AND NOT atthasdef AND atttypid=CASE attname WHEN 'content_revision' THEN 'integer'::regtype ELSE 'uuid'::regtype END)FROM pg_attribute WHERE attrelid='private.mobile_workout_proposal_admissions'::regclass AND attname IN('content_revision','confirmed_lifecycle_key')AND NOT attisdropped)
 AND(SELECT NOT attnotnull AND NOT atthasdef FROM pg_attribute WHERE attrelid='public.pending_registrations'::regclass AND attname='workout_ui_admission_id'AND NOT attisdropped),'additive_nullable_fields_no_default');
 PERFORM c59s17b_fixture.ok((SELECT array_agg(attname::text ORDER BY attnum)FROM pg_attribute WHERE attrelid=t AND attnum>0 AND NOT attisdropped)=ARRAY['user_id','admission_id','request_key','input_hash','expected_revision','result_revision']
 AND(SELECT bool_and(attnotnull)FROM pg_attribute WHERE attrelid=t AND attnum>0 AND NOT attisdropped)
 AND EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=t AND attname='request_key'AND attcollation='"C"'::regcollation)
 AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=t AND contype='f'AND confrelid='private.mobile_workout_proposal_admissions'::regclass AND confdeltype='c')
 AND(SELECT relowner='postgres'::regrole AND relrowsecurity AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=t)FROM pg_class WHERE oid=t)
 AND NOT has_table_privilege('service_role',t,'SELECT,INSERT,UPDATE,DELETE'),'edit_receipts_exact_six_owned_columns_C_key_RLS_private');
 PERFORM c59s17b_fixture.ok(EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.pending_registrations'::regclass AND contype='f'AND confrelid='private.mobile_workout_proposal_admissions'::regclass AND confdeltype='a'AND cardinality(conkey)=2)
 AND EXISTS(SELECT 1 FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=i.indkey[0]JOIN pg_attribute b ON b.attrelid=i.indrelid AND b.attnum=i.indkey[1]WHERE i.indrelid='public.pending_registrations'::regclass AND i.indnkeyatts=2 AND a.attname='user_id'AND b.attname='workout_ui_admission_id'AND pg_get_expr(i.indpred,i.indrelid)='(workout_ui_admission_id IS NOT NULL)'),'pending_owned_marker_FK_and_partial_index');
END $schema$;
DO $acl$DECLARE f oid;r jsonb;role_name text;all_ok boolean:=true;BEGIN
 FOREACH f IN ARRAY ARRAY['public.admit_mobile_workout_registration(uuid,text,jsonb)'::regprocedure::oid,'public.materialize_mobile_workout_registration(uuid,uuid,jsonb,jsonb,timestamp with time zone)'::regprocedure::oid,'public.get_mobile_workout_registration(uuid,uuid)'::regprocedure::oid]LOOP
 all_ok:=all_ok AND(SELECT proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog']AND pronargdefaults=0 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner)))a WHERE a.grantee NOT IN(proowner,'service_role'::regrole)OR(a.grantee<>proowner AND a.is_grantable))FROM pg_proc WHERE oid=f)
 AND has_function_privilege('service_role',f,'EXECUTE')AND NOT has_function_privilege('anon',f,'EXECUTE')AND NOT has_function_privilege('authenticated',f,'EXECUTE');END LOOP;
 PERFORM c59s17b_fixture.ok(all_ok,'three_new_RPCs_exact_owner_service_DEFINER_ACL');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated']LOOP
 r:=c59s17b_fixture.attempt('SELECT public.admit_mobile_workout_registration(NULL,NULL,NULL)',role_name);
 IF r->>'sqlstate'IS DISTINCT FROM '42501'THEN RAISE EXCEPTION 'C59S17B_CLIENT_EXECUTE_NOT_DENIED';END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'actual_anon_authenticated_new_entrypoint_denial');
 PERFORM c59s17b_fixture.ok(NOT has_table_privilege('service_role','public.workout_logs','INSERT')AND NOT has_table_privilege('service_role','public.workout_logs','UPDATE')
 AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid='public.workout_logs'::regclass AND a.attnum>0 AND NOT a.attisdropped AND(has_column_privilege('service_role',a.attrelid,a.attnum,'INSERT')OR has_column_privilege('service_role',a.attrelid,a.attnum,'UPDATE')))
 AND has_table_privilege('service_role','public.workout_logs','SELECT')AND has_table_privilege('service_role','public.workout_logs','DELETE'),'workout_service_effective_table_column_IU_denied_SELECT_DELETE_preserved');
 FOREACH f IN ARRAY ARRAY['private.register_workout_atomic_core(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure::oid,'private.register_workout_strength_core(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure::oid]LOOP
 IF(SELECT proowner='postgres'::regrole AND NOT prosecdef AND proconfig=ARRAY['search_path=pg_catalog']AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner)))a WHERE a.grantee<>proowner)FROM pg_proc WHERE oid=f)IS DISTINCT FROM true
 OR has_function_privilege('service_role',f,'EXECUTE')OR has_function_privilege('anon',f,'EXECUTE')OR has_function_privilege('authenticated',f,'EXECUTE')THEN RAISE EXCEPTION 'C59S17B_PRIVATE_CORE_ACL';END IF;END LOOP;
 r:=c59s17b_fixture.attempt('SELECT private.register_workout_atomic_core(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)');
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501','actual_private13_core_denied_before_body');
 r:=c59s17b_fixture.attempt('SELECT private.register_workout_strength_core(NULL,NULL,NULL,NULL,NULL,NULL)');
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501','actual_privateS8_core_denied_before_body');
 r:=c59s17b_fixture.attempt('SELECT public.admit_mobile_workout_proposal(NULL,NULL,NULL)');
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501','actual_oldS16_admit_denied_before_body');
 r:=c59s17b_fixture.attempt('SELECT public.materialize_mobile_workout_proposal(NULL,NULL,NULL,NULL,NULL)');
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501','actual_oldS16_materialize_denied_before_body');
END $acl$;
\if :postddl_mode
\ir fixtures/mobile_workout_registration_boundary_postddl_catalog.sql
\else
DO $upgrade$DECLARE h record;o record;old13 jsonb;old8 jsonb;key text;f jsonb;p record;v boolean:=true;r jsonb;s jsonb;BEGIN
 SELECT * INTO STRICT o FROM c59s17b_fixture.ownership;
 FOR h IN SELECT * FROM c59s17b_fixture.historical ORDER BY case_id LOOP
 PERFORM c59s17b_fixture.ok(c59s17b_fixture.old_shape(c59s17b_fixture.state(h.owner_id))=h.old_state,'historical_preserved_no_backfill:'||h.case_id);
 s:=c59s17b_fixture.state(h.owner_id);
 r:=c59s17b_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',h.owner_id,h.payload->>'requestKey',h.payload->'input'));
 IF r->'result'IS DISTINCT FROM '{"status":"forbidden","reason":"invalid_admission"}'::jsonb OR c59s17b_fixture.state(h.owner_id)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17B_NULL_ADMISSION_PROMOTED';END IF;
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,NULL,NULL)',h.owner_id,h.payload#>>'{admission,admissionID}',h.payload->'input'));
 IF r->'result'IS DISTINCT FROM '{"status":"forbidden","reason":"invalid_admission"}'::jsonb OR c59s17b_fixture.state(h.owner_id)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17B_NULL_MATERIALIZE_PROMOTED';END IF;
 END LOOP;
 PERFORM c59s17b_fixture.ok(true,'all_NULL_bound_refused_unbound_admissions_never_promoted');
 FOR key,f IN SELECT * FROM jsonb_each(o.old_functions)LOOP
 SELECT * INTO STRICT p FROM pg_proc WHERE oid=(f->>'oid')::oid;
 v:=v AND p.oid=key::regprocedure::oid AND p.proowner::text=f->>'owner'AND p.proargdefaults::text IS NOT DISTINCT FROM f->>'defaults'AND to_jsonb(p.proargnames)IS NOT DISTINCT FROM f->'names'AND p.proargtypes::text=f->>'args'AND p.prorettype::text=f->>'rettype';
 IF key LIKE 'public.admit_mobile_workout_proposal(%'OR key LIKE 'public.materialize_mobile_workout_proposal(%'THEN v:=v AND p.prosrc=f->>'prosrc'AND NOT has_function_privilege('service_role',p.oid,'EXECUTE');
 ELSIF key LIKE 'public.register_workout_atomic(%'THEN old13:=f;v:=v AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog']AND p.proacl::text IS NOT DISTINCT FROM f->>'acl';
 ELSE old8:=f;v:=v AND p.prosecdef AND p.proacl::text IS NOT DISTINCT FROM f->>'acl';END IF;
 END LOOP;
 PERFORM c59s17b_fixture.ok(v,'old_four_OIDs_defaults_signatures_and_allowed_security_ACL_changes_only');
 PERFORM c59s17b_fixture.ok((SELECT prosrc=old13->>'prosrc'AND md5(prosrc)='e982fbe59c4f569e58211e646c1eb8d8'AND proargdefaults::text IS NOT DISTINCT FROM old13->>'defaults'FROM pg_proc WHERE oid='private.register_workout_atomic_core(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)'::regprocedure),'private13_prosrc_and_defaults_byte_exact_old_writer');
 PERFORM c59s17b_fixture.ok((SELECT replace(prosrc,'private.register_workout_atomic_core(','public.register_workout_atomic(')=old8->>'prosrc'AND length(prosrc)-length(replace(prosrc,'private.register_workout_atomic_core(',''))=length('private.register_workout_atomic_core(')FROM pg_proc WHERE oid='private.register_workout_strength_core(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure),'privateS8_inverse_only_one_callee_change_recovers_exact_old_body');
END $upgrade$;
\endif
DO $null_check$DECLARE u uuid:=c59s17b_fixture.uid(901);r jsonb;s jsonb:=c59s17b_fixture.state(u);BEGIN
 r:=c59s17b_fixture.attempt(format('UPDATE private.mobile_workout_proposal_admissions SET confirmed_lifecycle_key=%L WHERE user_id=%L RETURNING to_jsonb(mobile_workout_proposal_admissions)',c59s17b_fixture.uid(891),u),'postgres');
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='23514'AND c59s17b_fixture.state(u)=s,'NULL_revision_cannot_gain_confirmed_lifecycle_snapshot');
END $null_check$;
DO $new$DECLARE u uuid:=c59s17b_fixture.owner(701);v jsonb:=c59s17b_fixture.input('C59S17B café 🏋️');k text:=c59s17b_fixture.key(701);a jsonb;r jsonb;s jsonb;m jsonb;j record;p record;expected jsonb;BEGIN
 r:=c59s17b_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));a:=r#>'{result,admission}';
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND r#>>'{result,status}'='admitted'AND(SELECT array_agg(x ORDER BY x)FROM jsonb_object_keys(r->'result')x)=ARRAY['admission','status']
 AND(SELECT array_agg(x ORDER BY x)FROM jsonb_object_keys(a)x)=ARRAY['admissionID','admittedAt','epoch','ownerID','requestHash','requestKey','requestNamespace']
 AND a->>'ownerID'=u::text AND a->>'requestKey'=k AND a->>'requestNamespace'='mobile_workout_proposal_v1'AND a->>'requestHash'=private.mobile_workout_proposal_input_hash(v)
 AND EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions WHERE user_id=u AND admission_id=(a->>'admissionID')::uuid AND content_revision=0 AND pending_id IS NULL AND confirmed_lifecycle_key IS NULL),'new_admit_exact_S16_receipt_and_revision0_same_transaction');
 s:=c59s17b_fixture.state(u);r:=c59s17b_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 PERFORM c59s17b_fixture.ok(r->'result'=jsonb_build_object('status','reused','admission',a)AND c59s17b_fixture.state(u)=s,'new_admit_retry_no_new_revision_or_authority');
 r:=c59s17b_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v||'{"duration_min":61}'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"conflict","reason":"request_content_conflict"}'::jsonb AND c59s17b_fixture.state(u)=s,'changed_input_never_overwrites_admission');
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,a->>'admissionID',v,c59s17b_fixture.proposal(k,v),clock_timestamp()+interval '1 hour'));m:=r->'result';
 SELECT * INTO STRICT j FROM private.mobile_workout_proposal_admissions WHERE user_id=u;SELECT * INTO STRICT p FROM ONLY public.pending_registrations WHERE user_id=u;
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND(SELECT array_agg(x ORDER BY x)FROM jsonb_object_keys(m)x)=ARRAY['cancelledCount','pendingID','pendingStatus','status']AND m->>'status'='materialized'AND m->>'pendingID'=p.id::text AND m->>'pendingStatus'='pending'AND m->'cancelledCount'='0'::jsonb
 AND p.workout_ui_admission_id=j.admission_id AND j.pending_id=p.id AND j.content_revision=0 AND j.confirmed_lifecycle_key IS NULL AND p.proposal=c59s17b_fixture.proposal(k,v),'materialize_exact_wire_original_pending_marked_and_bound');
 PERFORM c59s17b_fixture.ok((SELECT count(*)=0 FROM ONLY public.messages WHERE user_id=u)AND(SELECT count(*)=0 FROM private.workout_strength_lifecycles WHERE user_id=u)AND(SELECT count(*)=0 FROM ONLY public.workout_logs WHERE user_id=u)AND(SELECT count(*)=0 FROM ONLY public.daily_snapshots WHERE user_id=u)AND(SELECT count(*)=0 FROM private.workout_strength_commands WHERE user_id=u),'UI_producer_no_IN_life_command_workout_or_snapshot');
 s:=c59s17b_fixture.state(u);r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,NULL,NULL)',u,j.admission_id,v));
 PERFORM c59s17b_fixture.ok(r->'result'=jsonb_build_object('status','reused','pendingID',p.id,'pendingStatus','pending','cancelledCount',0)AND c59s17b_fixture.state(u)=s,'bound_replay_NULL_candidates_no_recalculation_or_new_pending');
 expected:=jsonb_build_object('status','available','registration',jsonb_build_object('id',p.id,'status',p.status,'created_at',p.created_at,'expires_at',p.expires_at,'resolved_at',p.resolved_at,'proposal',p.proposal,'workout_protocol','ui-v1','content_revision',0));
 r:=c59s17b_fixture.attempt(format('SELECT public.get_mobile_workout_registration(%L,%L)',u,p.id));
 PERFORM c59s17b_fixture.ok(r->'result'=expected AND c59s17b_fixture.state(u)=s,'projection_exact_six_owned_links_and_raw_server_proposal');
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_proposal(%L,%L,%L::jsonb,NULL,NULL)',u,j.admission_id,v));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND c59s17b_fixture.state(u)=s,'new_admit_cannot_use_old_S16_materializer_to_create_unmarked_row');
END $new$;
DO $keys$DECLARE u uuid:=c59s17b_fixture.owner(702);v jsonb:=c59s17b_fixture.input();r jsonb;k text;s jsonb:=c59s17b_fixture.state(u);BEGIN
 FOREACH k IN ARRAY ARRAY['bare-old-intention-key','WUI1:c59b7000-0000-0000-0000-000000000702','wui1:not-a-uuid',' wui1:c59b7000-0000-0000-0000-000000000702','wui1:c59b7000-0000-0000-0000-000000000702 ']LOOP
 r:=c59s17b_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));IF r->>'sqlstate'IS DISTINCT FROM '22023'THEN RAISE EXCEPTION 'C59S17B_INVALID_PREFIX_ACCEPTED';END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(c59s17b_fixture.state(u)=s,'new_protocol_rejects_old_malformed_or_padded_keys_without_promotion');
 k:='wui1:C59B7000-0000-0000-0000-000000000702';r:=c59s17b_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 PERFORM c59s17b_fixture.ok(r#>>'{result,status}'='admitted'AND r#>>'{result,admission,requestKey}'=k,'hex_case_accepted_preserved_not_normalized');
END $keys$;
DO $legacy$DECLARE u uuid:=c59s17b_fixture.owner(703);a jsonb:=c59s17b_fixture.arguments(u,'  C59S17B café 🏋️  ','legacy-703');r jsonb;s jsonb;w record;snap record;first_id uuid;BEGIN
 r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(a));SELECT * INTO STRICT w FROM ONLY public.workout_logs WHERE user_id=u;SELECT * INTO STRICT snap FROM ONLY public.daily_snapshots WHERE user_id=u;first_id:=w.id;
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND r#>>'{result,workout_log_id}'=w.id::text AND w.workout_type='C59S17B café 🏋️'AND w.duration_min=60 AND w.estimated_kcal=300 AND w.intensity='moderada'AND w.notes='S17B preserved café 🏋️'AND w.performed_at='2026-10-15T12:00:00.123456Z'AND w.raw_provider_message_id='legacy-703'
 AND snap.date='2026-10-15'AND snap.calories_target=2000 AND snap.protein_target=150.25 AND snap.exercise_calories=300 AND snap.training_done AND r#>>'{result,replaced_count}'='0','legacy13_all_literals_numeric_notes_trim_and_totals_preserved');
 r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(a));
 PERFORM c59s17b_fixture.ok(r#>>'{result,workout_log_id}'=first_id::text AND r#>'{result,inserted}'='false'::jsonb AND(SELECT count(*)=1 FROM ONLY public.workout_logs WHERE user_id=u),'legacy_provider_type_dedup_preserves_original_UUID');
 a:=a||'{"p_provider_message_id":null,"p_replace_recent":true,"p_replace_since":"2000-01-01T00:00:00Z","p_estimated_kcal":400,"p_workout_type":"C59S17B café 🏋️"}';r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(a));
 PERFORM c59s17b_fixture.ok(r#>>'{result,replaced_count}'='1'AND r#>>'{result,exercise_calories}'='400'AND(SELECT count(*)=1 AND bool_and(raw_provider_message_id IS NULL AND estimated_kcal=400)FROM ONLY public.workout_logs WHERE user_id=u),'legacy_NULL_provider_real_correction400_recomputes_totals');
END $legacy$;
DO $constraints$DECLARE p jsonb:=c59s17b_fixture.ui(712,true);u uuid:=(p->>'ownerID')::uuid;j uuid:=(p#>>'{admission,admissionID}')::uuid;s jsonb:=c59s17b_fixture.state(u);r jsonb;sql text;BEGIN
 FOREACH sql IN ARRAY ARRAY[format('UPDATE private.mobile_workout_proposal_admissions SET content_revision=-1 WHERE user_id=%L RETURNING to_jsonb(mobile_workout_proposal_admissions)',u),
 format('INSERT INTO private.mobile_workout_registration_edit_receipts VALUES(%L,%L,''invalid-edit-hash'',''bad'',0,1)RETURNING to_jsonb(mobile_workout_registration_edit_receipts)',u,j),
 format('INSERT INTO private.mobile_workout_registration_edit_receipts VALUES(%L,%L,''invalid-edit-revision'',%L,0,2)RETURNING to_jsonb(mobile_workout_registration_edit_receipts)',u,j,repeat('a',64)),
 format('INSERT INTO private.mobile_workout_registration_edit_receipts VALUES(%L,%L,''invalid-edit-overflow'',%L,2147483647,2147483647)RETURNING to_jsonb(mobile_workout_registration_edit_receipts)',u,j,repeat('a',64))]LOOP
 r:=c59s17b_fixture.attempt(sql,'postgres');IF r->>'sqlstate'IS DISTINCT FROM '23514'OR c59s17b_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17B_CHECK_NOT_ENFORCED:%',r;END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'membership_revision_and_edit_hash_successor_checks_NULL_safe');
END $constraints$;
DO $invalid_input$DECLARE u uuid:=c59s17b_fixture.uid(702);r jsonb;s jsonb:=c59s17b_fixture.state(u);sql text;BEGIN
 FOREACH sql IN ARRAY ARRAY[format('SELECT public.admit_mobile_workout_registration(%L,%L,NULL)',u,'wui1:c59b7000-0000-0000-0000-000000009702'),
 format('SELECT public.admit_mobile_workout_registration(%L,%L,''null''::jsonb)',u,'wui1:c59b7000-0000-0000-0000-000000009702'),
 format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,'wui1:c59b7000-0000-0000-0000-000000009702',c59s17b_fixture.input()||'{"extra":1}') ]LOOP
 r:=c59s17b_fixture.attempt(sql);IF r->>'sqlstate'IS DISTINCT FROM '22023'OR c59s17b_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17B_INVALID_INPUT_ACCEPTED';END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'new_admit_SQLNULL_JSONnull_extra_input_reject_without_authority_write');
END $invalid_input$;
DO $protection$DECLARE p jsonb:=c59s17b_fixture.ui(704,true);u uuid:=(p->>'ownerID')::uuid;j uuid:=(p#>>'{admission,admissionID}')::uuid;k text:=p->>'requestKey';r jsonb;s jsonb;key text;BEGIN
 INSERT INTO private.mobile_workout_registration_edit_receipts VALUES(u,j,'wui1:c59b7000-0000-0000-0000-000000008704',repeat('a',64),0,1);
 FOREACH key IN ARRAY ARRAY[k,'wui1:c59b7000-0000-0000-0000-000000008704']LOOP
 s:=c59s17b_fixture.state(u);r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(c59s17b_fixture.arguments(u,'DIFFERENT raw type',key)));
 IF r->>'sqlstate'IS DISTINCT FROM '42501'OR r->>'message'IS DISTINCT FROM 'mobile_workout_registration_requires_revision'OR c59s17b_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17B_PROTECTED_KEY_BYPASS:%',r;END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'initial_and_accepted_EDIT_keys_deny_any_type_before_snapshot');
 s:=c59s17b_fixture.state(u);r:=c59s17b_fixture.attempt(format('INSERT INTO public.workout_logs(user_id,workout_type,duration_min,estimated_kcal,raw_provider_message_id)VALUES(%L,''direct-valid'',60,300,%L)RETURNING to_jsonb(workout_logs)',u,k));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND c59s17b_fixture.state(u)=s,'direct_valid_service_INSERT_protected_key_denied_without_write');
 r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(c59s17b_fixture.arguments(u,'legacy-existing','other-704')));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'C59S17B_SETUP_LEGACY_CONTROL';END IF;s:=c59s17b_fixture.state(u);
 r:=c59s17b_fixture.attempt(format('UPDATE public.workout_logs SET raw_provider_message_id=%L WHERE user_id=%L RETURNING to_jsonb(workout_logs)',k,u));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND c59s17b_fixture.state(u)=s,'direct_valid_service_UPDATE_cannot_rekey_existing_workout');
END $protection$;
\if :postddl_mode
DO $null_legacy$DECLARE h record;u uuid;r jsonb;BEGIN
 FOR h IN SELECT * FROM c59s17b_fixture.historical WHERE case_id IN('bound-null','collision-null')LOOP
 u:=h.owner_id;r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(c59s17b_fixture.arguments(u,'legacy historical',h.payload->>'requestKey')));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb OR r#>'{result,inserted}'IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'C59S17B_LEGACY_NULL_FALSE_PROTECTION';END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'postDDL_NULL_bound_and_collision_keys_keep_legacy_writer');
END $null_legacy$;
\else
DO $null_legacy$DECLARE h record;u uuid;r jsonb;BEGIN
 FOR h IN SELECT * FROM c59s17b_fixture.historical WHERE case_id IN('bound-null','collision-null')LOOP
 u:=h.owner_id;r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(c59s17b_fixture.arguments(u,'legacy historical',h.payload->>'requestKey')));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb OR r#>'{result,inserted}'IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'C59S17B_LEGACY_NULL_FALSE_PROTECTION';END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'historical_NULL_bound_and_collision_keys_keep_legacy_writer');
END $null_legacy$;
\endif
DO $s8$DECLARE u uuid:=c59s17b_fixture.owner(714);l uuid:=c59s17b_fixture.uid(814);k text:=c59s17b_fixture.key(714);v jsonb:=c59s17b_fixture.input();r jsonb;a jsonb;s jsonb;BEGIN
 INSERT INTO private.workout_strength_lifecycles VALUES(u,l,'2026-10-15T00:00:00Z',NULL,NULL);
 PERFORM public.read_or_admit_workout_strength_command(u,l,'s17b-before-membership','musculacao',c59s17b_fixture.arguments(u,'musculacao',k));
 r:=c59s17b_fixture.attempt(format('SELECT public.register_workout_strength_atomic(%L,%L,''s17b-before-membership'',''musculacao'',NULL,''{"status":"unavailable","reason":"catalogue_read_error"}''::jsonb)',u,l));
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND r#>>'{result,strength,status}'='committed'AND r#>>'{result,legacy_result,exercise_calories}'='300'
 AND(SELECT count(*)=1 FROM private.workout_strength_facts WHERE user_id=u),'publicS8_legacy_real_capture_result_and_fact_preserved');
 a:=c59s17b_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 IF a#>>'{result,status}'IS DISTINCT FROM 'admitted'THEN RAISE EXCEPTION 'C59S17B_SETUP_S8_UI_ADMISSION';END IF;
 a:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,a#>>'{result,admission,admissionID}',v,c59s17b_fixture.proposal(k,v),clock_timestamp()+interval '1 hour'));
 IF a#>>'{result,status}'IS DISTINCT FROM 'materialized'THEN RAISE EXCEPTION 'C59S17B_SETUP_S8_UI_MATERIALIZE';END IF;s:=c59s17b_fixture.state(u);
 r:=c59s17b_fixture.attempt(format('SELECT public.register_workout_strength_atomic(%L,%L,''s17b-before-membership'',''musculacao'',NULL,NULL)',u,l));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND r->>'message'='mobile_workout_registration_requires_revision'AND c59s17b_fixture.state(u)=s,'publicS8_protected_key_denies_before_existing_F1_replay');
 PERFORM public.read_or_admit_workout_strength_command(u,l,'s17b-new-protected','changed raw type',c59s17b_fixture.arguments(u,'changed raw type',k));s:=c59s17b_fixture.state(u);
 r:=c59s17b_fixture.attempt(format('SELECT public.register_workout_strength_atomic(%L,%L,''s17b-new-protected'',''changed raw type'',NULL,NULL)',u,l));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND r->>'message'='mobile_workout_registration_requires_revision'AND c59s17b_fixture.state(u)=s,'publicS8_new_command_protected_provider_denies_before_core');
END $s8$;
DO $collision$DECLARE u uuid:=c59s17b_fixture.owner(715);v jsonb:=c59s17b_fixture.input();k text:=c59s17b_fixture.key(715);r jsonb;a jsonb;s jsonb;BEGIN
 PERFORM public.replace_pending_registration_atomic(u,'{"kind":"meal","mealType":"jantar"}',clock_timestamp()+interval '1 hour',k);
 a:=c59s17b_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,a#>>'{result,admission,admissionID}',v,c59s17b_fixture.proposal(k,v),clock_timestamp()+interval '1 hour'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"conflict","reason":"unproved_pending"}'::jsonb AND EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions WHERE user_id=u AND content_revision=0 AND pending_id IS NULL AND rejection_reason='unproved_pending')
 AND EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE user_id=u AND workout_ui_admission_id IS NULL),'new_NULL_collision_refusal_does_not_mark_or_adopt_legacy_pending');
 r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(c59s17b_fixture.arguments(u,'refused legacy control',k)));
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND r#>'{result,inserted}'='true'::jsonb,'revision0_without_historical_pending_does_not_false_protect_key');
END $collision$;
-- Positive controls use the same direct service DML as legacy BFF/WhatsApp.
DO $legacy_pending$DECLARE u uuid:=c59s17b_fixture.owner(716);v jsonb:='{"kind":"workout","durationMin":20}';e timestamptz:=clock_timestamp()+interval '1 hour';pid uuid;r jsonb;s jsonb;old_row jsonb;BEGIN
 s:=c59s17b_fixture.state(u);
 r:=c59s17b_fixture.attempt(format('INSERT INTO public.pending_registrations(user_id,proposal,expires_at)VALUES(%L,%L::jsonb,%L::timestamptz)RETURNING to_jsonb(pending_registrations)',u,v,e));pid:=(r#>>'{result,id}')::uuid;
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND r#>>'{result,user_id}'=u::text AND r#>>'{result,status}'='pending'AND r#>'{result,proposal}'=v AND(r#>>'{result,expires_at}')::timestamptz=e AND r#>'{result,workout_ui_admission_id}'='null'::jsonb AND c59s17b_fixture.state(u)=jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result')),'legacy_service_pending_INSERT_unmarked_without_authority');
 s:=c59s17b_fixture.state(u);old_row:=s->'public.pending_registrations'->0;v:=v||'{"durationMin":25}';e:=e+interval '1 hour';
 r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET proposal=%L::jsonb,expires_at=%L::timestamptz WHERE id=%L RETURNING to_jsonb(pending_registrations)',v,e,pid));
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND (r->'result')-ARRAY['proposal','expires_at']=old_row-ARRAY['proposal','expires_at']AND r#>'{result,proposal}'=v AND(r#>>'{result,expires_at}')::timestamptz=e AND c59s17b_fixture.state(u)=jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result')),'legacy_service_pending_EDIT_payload_expiry_preserves_other_state');
 s:=c59s17b_fixture.state(u);old_row:=s->'public.pending_registrations'->0;
 r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET status=''confirmed'',resolved_at=clock_timestamp()WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid));
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND r#>>'{result,status}'='confirmed'AND isfinite((r#>>'{result,resolved_at}')::timestamptz)AND (r->'result')-ARRAY['status','resolved_at']=old_row-ARRAY['status','resolved_at']AND c59s17b_fixture.state(u)=jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result')),'legacy_service_pending_CONFIRMED_preserves_other_state');
END $legacy_pending$;
DO $legacy_whatsapp$DECLARE u uuid:=c59s17b_fixture.owner(717);pid uuid;mid uuid:=c59s17b_fixture.uid(817);r jsonb;s jsonb;old_row jsonb;BEGIN
 r:=c59s17b_fixture.attempt(format('INSERT INTO public.pending_registrations(user_id,proposal,expires_at)VALUES(%L,''{"kind":"meal"}''::jsonb,clock_timestamp()+interval ''1 hour'')RETURNING to_jsonb(pending_registrations)',u));pid:=(r#>>'{result,id}')::uuid;
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'C59S17B_SETUP_LEGACY_WA_PENDING';END IF;
 INSERT INTO public.messages(id,user_id,direction,role,content_type,content)VALUES(mid,u,'out','assistant','text','C59S17B synthetic proposal');
 s:=c59s17b_fixture.state(u);old_row:=s->'public.pending_registrations'->0;
 r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET proposal_msg_id=%L WHERE id=%L RETURNING to_jsonb(pending_registrations)',mid,pid));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,proposal_msg_id}'IS DISTINCT FROM mid::text OR (r->'result')-'proposal_msg_id'IS DISTINCT FROM old_row-'proposal_msg_id'OR c59s17b_fixture.state(u)IS DISTINCT FROM jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result'))THEN RAISE EXCEPTION 'C59S17B_LEGACY_WA_PROPOSAL_LINK';END IF;
 s:=c59s17b_fixture.state(u);old_row:=s->'public.pending_registrations'->0;
 r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET status=''edited'',resolved_at=clock_timestamp()WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid));
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND r#>>'{result,status}'='edited'AND isfinite((r#>>'{result,resolved_at}')::timestamptz)AND (r->'result')-ARRAY['status','resolved_at']=old_row-ARRAY['status','resolved_at']AND c59s17b_fixture.state(u)=jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result')),'legacy_WhatsApp_service_proposal_link_and_EDITED_preserve_other_state');
END $legacy_whatsapp$;
-- Every mutation below executes as service_role against a member created by real UI RPCs.
DO $trigger$DECLARE p jsonb:=c59s17b_fixture.ui(705,true);u uuid:=(p->>'ownerID')::uuid;pid uuid:=(p#>>'{materialized,pendingID}')::uuid;aid uuid:=(p#>>'{admission,admissionID}')::uuid;s jsonb;r jsonb;sql text;BEGIN
 s:=c59s17b_fixture.state(u);
 FOREACH sql IN ARRAY ARRAY[format('UPDATE public.pending_registrations SET workout_ui_admission_id=NULL WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid),
 format('UPDATE public.pending_registrations SET workout_ui_admission_id=%L WHERE id=%L RETURNING to_jsonb(pending_registrations)',c59s17b_fixture.uid(888),pid)]LOOP
 r:=c59s17b_fixture.attempt(sql);IF r->>'sqlstate'IS DISTINCT FROM '42501'OR c59s17b_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17B_MARKER_MUTABLE';END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'service_cannot_clear_or_swap_protected_marker');
 FOREACH sql IN ARRAY ARRAY[format('UPDATE public.pending_registrations SET proposal=proposal||''{"kcalEst":999}''::jsonb WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid),
 format('UPDATE public.pending_registrations SET expires_at=expires_at+interval ''1 hour'' WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid),
 format('UPDATE public.pending_registrations SET status=''confirmed'',resolved_at=clock_timestamp()WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid),
 format('UPDATE public.pending_registrations SET status=''edited'' WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid),
 format('UPDATE public.pending_registrations SET created_at=created_at+interval ''1 second'' WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid),
 format('UPDATE public.pending_registrations SET id=''c59b7000-0000-0000-0000-000000000887''::uuid WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid),
 format('UPDATE public.pending_registrations SET user_id=''c59b7000-0000-0000-0000-000000000704''::uuid WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid),
 format('UPDATE public.pending_registrations SET proposal_msg_id=''c59b7000-0000-0000-0000-000000000886''::uuid WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid)]LOOP
 r:=c59s17b_fixture.attempt(sql);IF r->>'sqlstate'IS DISTINCT FROM '42501'OR c59s17b_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17B_PROTECTED_PENDING_DML';END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'service_noop_payload_expiry_confirmed_edited_link_mutations_denied');
 r:=c59s17b_fixture.attempt(format('INSERT INTO public.pending_registrations(user_id,proposal,expires_at,workout_ui_admission_id)VALUES(%L,%L::jsonb,clock_timestamp()+interval ''1 hour'',%L)RETURNING to_jsonb(pending_registrations)',u,p->'proposal',aid));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND c59s17b_fixture.state(u)=s,'service_cannot_assign_server_marker_on_INSERT');
 r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET status=''cancelled'',resolved_at=clock_timestamp()WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid));
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND r#>>'{result,status}'='cancelled'AND isfinite((r#>>'{result,resolved_at}')::timestamptz)AND jsonb_array_length(s->'public.pending_registrations')=1 AND (r->'result')-ARRAY['status','resolved_at']=(s->'public.pending_registrations'->0)-ARRAY['status','resolved_at']AND c59s17b_fixture.state(u)=jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result')),'legacy_pending_to_cancelled_preserves_marker_payload');
 s:=c59s17b_fixture.state(u);r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET status=''pending'',resolved_at=NULL WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND c59s17b_fixture.state(u)=s,'cancelled_protected_pending_cannot_reopen');
 r:=c59s17b_fixture.attempt(format('SELECT public.get_mobile_workout_registration(%L,%L)',u,pid));
 PERFORM c59s17b_fixture.ok(r#>>'{result,registration,status}'='cancelled'AND r#>>'{result,registration,content_revision}'='0'AND c59s17b_fixture.state(u)=s,'projection_reports_cancelled_without_reopening_or_authority_write');
END $trigger$;
DO $expiry$DECLARE p jsonb:=c59s17b_fixture.ui(706,true);u uuid:=(p->>'ownerID')::uuid;pid uuid:=(p#>>'{materialized,pendingID}')::uuid;r jsonb;s jsonb;BEGIN
 s:=c59s17b_fixture.state(u);r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET status=''expired'',resolved_at=''infinity''::timestamptz WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND c59s17b_fixture.state(u)=s,'terminal_requires_finite_resolved_at');
 r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET status=''expired'',resolved_at=clock_timestamp()WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid));
 PERFORM c59s17b_fixture.ok(r->'ok'='true'::jsonb AND r#>>'{result,status}'='expired'AND isfinite((r#>>'{result,resolved_at}')::timestamptz)AND jsonb_array_length(s->'public.pending_registrations')=1 AND (r->'result')-ARRAY['status','resolved_at']=(s->'public.pending_registrations'->0)-ARRAY['status','resolved_at']AND c59s17b_fixture.state(u)=jsonb_set(s,ARRAY['public.pending_registrations'],jsonb_build_array(r->'result')),'legacy_pending_to_expired_preserves_contents');
END $expiry$;
SAVEPOINT marker_corruption;
DO $marker_null$DECLARE p jsonb:=c59s17b_fixture.ui(707,true);u uuid:=(p->>'ownerID')::uuid;pid uuid:=(p#>>'{materialized,pendingID}')::uuid;r jsonb;s jsonb;BEGIN
 -- Controlled owner corruption ONLY to exercise detector independence from the public marker.
 SET LOCAL ROLE postgres;UPDATE public.pending_registrations SET workout_ui_admission_id=NULL WHERE id=pid;SET LOCAL ROLE NONE;s:=c59s17b_fixture.state(u);
 r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET proposal=proposal||''{"kcalEst":1}''::jsonb WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid));
 IF r->>'sqlstate'IS DISTINCT FROM '42501'OR c59s17b_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17B_MARKER_NULL_PAYLOAD_BYPASS';END IF;
 r:=c59s17b_fixture.attempt(format('UPDATE public.pending_registrations SET workout_ui_admission_id=%L WHERE id=%L RETURNING to_jsonb(pending_registrations)',p#>>'{admission,admissionID}',pid));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND c59s17b_fixture.state(u)=s,'historical_detector_blocks_DML_even_with_marker_NULL');
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,NULL,NULL)',u,p#>>'{admission,admissionID}',p->'input'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND c59s17b_fixture.state(u)=s,'bound_unmarked_replay_not_repaired_or_promoted');
 r:=c59s17b_fixture.attempt(format('SELECT public.get_mobile_workout_registration(%L,%L)',u,pid));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND c59s17b_fixture.state(u)=s,'projection_unmarked_original_link_denied');
END $marker_null$;
ROLLBACK TO marker_corruption;RELEASE SAVEPOINT marker_corruption;
DO $foreign$DECLARE p jsonb:=c59s17b_fixture.ui(708,true);q jsonb:=c59s17b_fixture.ui(709,true);u uuid:=(p->>'ownerID')::uuid;b uuid:=(q->>'ownerID')::uuid;r jsonb;s jsonb:=c59s17b_fixture.state(u);sb jsonb:=c59s17b_fixture.state(b);BEGIN
 r:=c59s17b_fixture.attempt(format('SELECT public.get_mobile_workout_registration(%L,%L)',b,p#>>'{materialized,pendingID}'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND c59s17b_fixture.state(u)=s AND c59s17b_fixture.state(b)=sb,'projection_foreign_owner_never_leaks_registration');
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,NULL,NULL)',b,p#>>'{admission,admissionID}',p->'input'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND c59s17b_fixture.state(u)=s AND c59s17b_fixture.state(b)=sb,'foreign_materialize_preserves_both_accounts');
END $foreign$;
-- Deliberately isolate stale epoch/blocked owner without deleting the pending row.
SAVEPOINT stale_projection;
DO $stale_projection$DECLARE p jsonb:=c59s17b_fixture.ui(718,true);u uuid:=(p->>'ownerID')::uuid;r jsonb;s jsonb;BEGIN
 UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid()WHERE user_id=u;s:=c59s17b_fixture.state(u);
 r:=c59s17b_fixture.attempt(format('SELECT public.get_mobile_workout_registration(%L,%L)',u,p#>>'{materialized,pendingID}'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND jsonb_array_length(s->'public.pending_registrations')=1 AND c59s17b_fixture.state(u)=s,'projection_stale_epoch_with_pending_preserved_denied');
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,NULL,NULL)',u,p#>>'{admission,admissionID}',p->'input'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"forbidden","reason":"stale_epoch"}'::jsonb AND c59s17b_fixture.state(u)=s,'materialize_stale_epoch_preserves_S16_negative_and_pending');
END $stale_projection$;
ROLLBACK TO stale_projection;RELEASE SAVEPOINT stale_projection;
SAVEPOINT blocked_projection;
DO $blocked_projection$DECLARE p jsonb:=c59s17b_fixture.ui(719,true);u uuid:=(p->>'ownerID')::uuid;r jsonb;s jsonb;BEGIN
 UPDATE public.users SET status='blocked'WHERE id=u;s:=c59s17b_fixture.state(u);
 r:=c59s17b_fixture.attempt(format('SELECT public.get_mobile_workout_registration(%L,%L)',u,p#>>'{materialized,pendingID}'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND jsonb_array_length(s->'public.pending_registrations')=1 AND c59s17b_fixture.state(u)=s,'projection_inactive_owner_with_pending_preserved_denied');
END $blocked_projection$;
ROLLBACK TO blocked_projection;RELEASE SAVEPOINT blocked_projection;
DO $deleted$DECLARE p jsonb:=c59s17b_fixture.ui(710,true);u uuid:=(p->>'ownerID')::uuid;pid uuid:=(p#>>'{materialized,pendingID}')::uuid;r jsonb;s jsonb;BEGIN
 r:=c59s17b_fixture.attempt(format('DELETE FROM public.pending_registrations WHERE id=%L RETURNING to_jsonb(pending_registrations)',pid));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'C59S17B_SETUP_REAL_DELETE';END IF;s:=c59s17b_fixture.state(u);
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,NULL,NULL)',u,p#>>'{admission,admissionID}',p->'input'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"forbidden","reason":"pending_missing"}'::jsonb AND c59s17b_fixture.state(u)=s,'deleted_pending_replay_gap_never_remints');
 r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(c59s17b_fixture.arguments(u,'after delete',p->>'requestKey')));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND r->>'message'='mobile_workout_registration_requires_revision'AND c59s17b_fixture.state(u)=s,'deleted_pending_keeps_original_key_protected');
END $deleted$;
DO $reset$DECLARE p jsonb:=c59s17b_fixture.ui(711,true);u uuid:=(p->>'ownerID')::uuid;j uuid:=(p#>>'{admission,admissionID}')::uuid;r jsonb;s jsonb;key text;BEGIN
 INSERT INTO private.mobile_workout_registration_edit_receipts VALUES(u,j,'wui1:c59b7000-0000-0000-0000-000000008711',repeat('b',64),0,1);
 r:=public.reset_user_conversation_atomic(u,true);s:=c59s17b_fixture.state(u);
 IF EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE user_id=u)OR NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions WHERE user_id=u AND admission_id=j AND content_revision=0 AND pending_id=(p#>>'{materialized,pendingID}')::uuid)THEN RAISE EXCEPTION 'C59S17B_SETUP_RESET_DURABILITY';END IF;
 FOREACH key IN ARRAY ARRAY[p->>'requestKey','wui1:c59b7000-0000-0000-0000-000000008711']LOOP
 r:=c59s17b_fixture.attempt(c59s17b_fixture.legacy_sql(c59s17b_fixture.arguments(u,'after reset',key)));IF r->>'sqlstate'IS DISTINCT FROM '42501'OR r->>'message'IS DISTINCT FROM 'mobile_workout_registration_requires_revision'OR c59s17b_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17B_RESET_RELEASED_PROTECTED_KEY';END IF;END LOOP;
 PERFORM c59s17b_fixture.ok(true,'real_reset_preserves_original_EDIT_key_fence_before_any_snapshot');
 r:=c59s17b_fixture.attempt(format('SELECT public.get_mobile_workout_registration(%L,%L)',u,p#>>'{materialized,pendingID}'));
 PERFORM c59s17b_fixture.ok(r->'result'='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND c59s17b_fixture.state(u)=s,'post_reset_projection_denied_without_recreating_profile_progress_or_pending');
 DELETE FROM public.users WHERE id=u;
 PERFORM c59s17b_fixture.ok(NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions WHERE user_id=u)AND NOT EXISTS(SELECT 1 FROM private.mobile_workout_registration_edit_receipts WHERE user_id=u)AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=u),'real_account_DELETE_cascades_private_admission_receipts_and_epoch');
END $reset$;
DO $fault_seed$DECLARE p jsonb:=c59s17b_fixture.ui(725,false);u uuid:=(p->>'ownerID')::uuid;BEGIN
 PERFORM public.replace_pending_registration_atomic(u,'{"kind":"meal","mealType":"jantar"}',clock_timestamp()+interval '1 hour','s17b-previous-725');
END $fault_seed$;
CREATE TRIGGER c59s17b_qa_after_bind AFTER UPDATE ON private.mobile_workout_proposal_admissions FOR EACH ROW EXECUTE FUNCTION c59s17b_fixture.fail_after_bind();
DO $fault$DECLARE u uuid:=c59s17b_fixture.uid(725);j uuid;r jsonb;s jsonb:=c59s17b_fixture.state(u);v jsonb:=c59s17b_fixture.input();BEGIN
 SELECT admission_id INTO STRICT j FROM private.mobile_workout_proposal_admissions WHERE user_id=u;
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,j,v,c59s17b_fixture.proposal(c59s17b_fixture.key(725),v),clock_timestamp()+interval '1 hour'));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='P0001'AND r->>'message'='C59S17B_INJECTED_AFTER_REAL_BIND'AND c59s17b_fixture.state(u)=s,'fault_after_real_bind_rolls_back_cancel_insert_binding');
END $fault$;
DROP TRIGGER c59s17b_qa_after_bind ON private.mobile_workout_proposal_admissions;
CREATE TRIGGER c59s17b_qa_after_marker AFTER UPDATE ON public.pending_registrations FOR EACH ROW EXECUTE FUNCTION c59s17b_fixture.fail_after_marker();
DO $fault$DECLARE u uuid:=c59s17b_fixture.uid(725);j uuid;r jsonb;s jsonb:=c59s17b_fixture.state(u);v jsonb:=c59s17b_fixture.input();BEGIN
 SELECT admission_id INTO STRICT j FROM private.mobile_workout_proposal_admissions WHERE user_id=u;
 r:=c59s17b_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,j,v,c59s17b_fixture.proposal(c59s17b_fixture.key(725),v),clock_timestamp()+interval '1 hour'));
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='P0001'AND r->>'message'='C59S17B_INJECTED_AFTER_REAL_MARKER'AND c59s17b_fixture.state(u)=s,'fault_after_real_marker_rolls_back_cancel_insert_bind_marker');
END $fault$;
DROP TRIGGER c59s17b_qa_after_marker ON public.pending_registrations;
DO $guard$DECLARE r jsonb;s jsonb:=c59s17b_fixture.state(c59s17b_fixture.uid(701));BEGIN
 SET LOCAL request.jwt.claims='{"role":"authenticated"}';
 r:=c59s17b_fixture.attempt('SELECT public.admit_mobile_workout_registration(NULL,NULL,NULL)');
 PERFORM c59s17b_fixture.ok(r->>'sqlstate'='42501'AND c59s17b_fixture.state(c59s17b_fixture.uid(701))=s,'trusted_guard_before_invalid_input');
 SET LOCAL request.jwt.claims='{"role":"service_role"}';
END $guard$;
ROLLBACK;
\if :postddl_mode
BEGIN ISOLATION LEVEL READ COMMITTED;
\ir fixtures/mobile_workout_registration_boundary_postddl_fixture.sql
ROLLBACK;
\endif
DO $rolled_back$DECLARE h record;BEGIN
 FOR h IN SELECT * FROM c59s17b_fixture.historical ORDER BY case_id LOOP IF c59s17b_fixture.old_shape(c59s17b_fixture.state(h.owner_id))IS DISTINCT FROM h.old_state THEN RAISE EXCEPTION 'C59S17B_ROLLBACK_HISTORICAL_MISMATCH';END IF;END LOOP;
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id IN(SELECT c59s17b_fixture.uid(i)FROM generate_series(701,740)i))OR EXISTS(SELECT 1 FROM c59s17b_fixture.cases)
 THEN RAISE EXCEPTION 'C59S17B_ROLLBACK_QA_ROWS_REMAIN';END IF;
END $rolled_back$;
\echo C59S17B_ROLLBACK_CONFIRMED
\endif
\endif
\endif
\endif
