\set ON_ERROR_STOP on
-- PRIVATE TEST-FIRST SOURCE ONLY. Root must review before adoption/runtime.
\if :{?prepare_fixture}
\else
\set prepare_fixture false
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
SELECT (:'prepare_fixture')::boolean::integer+(:'setup_concurrency')::boolean::integer+(:'teardown_concurrency')::boolean::integer+(:'dry_cleanup_baseline')::boolean::integer<=1 AS one_mode \gset s17i_
\if :s17i_one_mode
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17I_SETUP_CONFLICTING_MODES';END$$;
\endif
DO $target$BEGIN
 IF session_user<>'c5_local_admin'OR current_database()<>'c5_reset_default_20261009'OR current_setting('port')<>'55489'OR current_setting('listen_addresses')<>''OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'THEN RAISE EXCEPTION 'C59S17I_SETUP_WRONG_LOCAL_TARGET';END IF;
 IF to_regprocedure('public.admit_workout_strength_request(uuid,text,text)')IS NULL THEN RAISE EXCEPTION 'C59S17I_SETUP_S15_ABSENT';END IF;
END $target$;
\if :prepare_fixture
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='60s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';
DO $clean$BEGIN
 IF to_regnamespace('c59s17i_fixture')IS NOT NULL OR EXISTS(SELECT 1 FROM ONLY public.users WHERE id::text LIKE 'c59f1700-%'OR email LIKE 'c59s17i-%@example.invalid'OR wpp LIKE '155527%')THEN RAISE EXCEPTION 'C59S17I_SETUP_FIXTURE_OR_OWNER_COLLISION';END IF;
END $clean$;
\ir fixtures/flow_inbound_authority_fixture.sql
DO $prepare$DECLARE p jsonb;BEGIN p:=c59s17i_fixture.seed(4999);p:=p||jsonb_build_object('initialState',c59s17i_fixture.state(c59s17i_fixture.uid(4999)));INSERT INTO c59s17i_fixture.cases VALUES('sentinel',c59s17i_fixture.uid(4999),p);INSERT INTO c59s17i_fixture.ownership VALUES('c59s17i_atomic_in_v1',session_user,c59s17i_fixture.fingerprint());END $prepare$;
COMMIT;
\echo C59S17I_FIXTURE_PREPARED
\else
DO $owned$DECLARE o record;BEGIN SELECT * INTO STRICT o FROM c59s17i_fixture.ownership WHERE tag='c59s17i_atomic_in_v1';IF o.owner_name<>session_user OR o.fixture_fingerprint IS DISTINCT FROM c59s17i_fixture.fingerprint()OR(SELECT count(*)FROM c59s17i_fixture.ownership)<>1 THEN RAISE EXCEPTION 'C59S17I_FIXTURE_DRIFT';END IF;END $owned$;
\if :teardown_concurrency
\set cleanup true
\else
\set cleanup :dry_cleanup_baseline
\endif
\if :cleanup
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='60s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';
-- Evidence precedes deletion; unknown state fails closed below.
SELECT jsonb_build_object('tag','C59S17I_OWNED_CLEANUP_CAPTURE','cases',(SELECT jsonb_agg(jsonb_build_object('caseID',case_id,'ownerID',owner_id,'initialState',payload->'initialState','observedState',c59s17i_fixture.state(owner_id),'outsideFingerprint',c59s17i_fixture.outside(owner_id))ORDER BY owner_id)FROM c59s17i_fixture.cases))::text;
DO $cleanup$DECLARE ids text[]:=ARRAY['persist-reset-commit','persist-reset-rollback','reset-persist-commit','reset-persist-rollback','persist-persist-commit','persist-persist-rollback','probe-reset','reset-probe'];c record;i integer;s jsonb;t jsonb;a jsonb;b jsonb;m jsonb;raw jsonb;can_reset boolean;phase text;BEGIN
 IF(SELECT count(*)FROM c59s17i_fixture.cases)NOT IN(1,9)OR NOT EXISTS(SELECT 1 FROM c59s17i_fixture.cases WHERE case_id='sentinel'AND owner_id=c59s17i_fixture.uid(4999))OR EXISTS(SELECT 1 FROM c59s17i_fixture.cases WHERE case_id<>'sentinel'AND NOT(case_id=ANY(ids)))THEN RAISE EXCEPTION 'C59S17I_CLEANUP_CASESET';END IF;
 FOR c IN SELECT * FROM c59s17i_fixture.cases ORDER BY owner_id LOOP
 i:=CASE c.case_id WHEN 'sentinel'THEN 4999 ELSE 4300+array_position(ids,c.case_id)END;s:=c.payload->'initialState';t:=c59s17i_fixture.state(c.owner_id);
 IF c.owner_id IS DISTINCT FROM c59s17i_fixture.uid(i)OR c.payload->>'ownerID'IS DISTINCT FROM c.owner_id::text OR s IS NULL OR s#>>'{user,name}'IS DISTINCT FROM 'C59S17I synthetic'OR s#>'{user,metadata}'IS DISTINCT FROM '{"c59s17i_fixture":"c59s17i_atomic_in_v1"}'::jsonb OR NOT EXISTS(SELECT 1 FROM ONLY public.users WHERE id=c.owner_id AND email='c59s17i-'||i||'@example.invalid'AND wpp='155527'||lpad(i::text,7,'0'))THEN RAISE EXCEPTION 'C59S17I_CLEANUP_OWNER_SCOPE';END IF;
 IF t=s THEN phase:='initial_unchanged';
 ELSIF c.case_id='sentinel'THEN RAISE EXCEPTION 'C59S17I_CLEANUP_SENTINEL';
 ELSE
 a:=t#>'{private.workout_strength_request_admissions,0}';b:=s#>'{private.workout_strength_request_admissions,0}';
 IF jsonb_array_length(t->'private.workout_strength_request_admissions')<>1 OR a IS DISTINCT FROM b||jsonb_build_object('flow_inbound_id',a->'flow_inbound_id')OR a->'flow_inbound_refusal'IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'C59S17I_CLEANUP_RECEIPT_SCOPE';END IF;
 can_reset:=c.case_id=ANY(ARRAY['persist-reset-commit','persist-reset-rollback','reset-persist-commit','probe-reset','reset-probe']);
 IF t#>>'{private.workout_strength_authority_epochs,0,epoch}'IS DISTINCT FROM s#>>'{private.workout_strength_authority_epochs,0,epoch}'THEN
 IF NOT can_reset THEN RAISE EXCEPTION 'C59S17I_CLEANUP_UNPLANNED_RESET';END IF;
 IF a->>'flow_inbound_id'IS NOT NULL AND c.case_id<>'persist-reset-commit'THEN RAISE EXCEPTION 'C59S17I_CLEANUP_UNPLANNED_RESET_RECEIPT';END IF;
 PERFORM c59s17i_fixture.assert_reset(jsonb_set(s,'{private.workout_strength_request_admissions}',t->'private.workout_strength_request_admissions'),t);phase:='committed_reset';
 ELSE
 IF c.case_id=ANY(ARRAY['probe-reset','reset-probe'])OR a->>'flow_inbound_id'IS NULL OR jsonb_array_length(t->'public.messages')<>1 THEN RAISE EXCEPTION 'C59S17I_CLEANUP_PERSIST_PHASE';END IF;
 m:=t#>'{public.messages,0}';raw:=m->'raw_payload';
 IF NOT((raw=jsonb_build_object('request_id','s17i-original-request','conversation_id','flow','attempt_started_at','2026-10-15T12:00:00.123Z','provider_started_at',NULL,'retry_started_at','[]'::jsonb)AND c.case_id=ANY(ARRAY['persist-reset-commit','persist-reset-rollback','persist-persist-commit','persist-persist-rollback']))OR(raw=jsonb_build_object('request_id','s17i-second-request','conversation_id','flow','attempt_started_at','2026-10-15T12:01:00.456Z','provider_started_at',NULL,'retry_started_at','[]'::jsonb)AND c.case_id=ANY(ARRAY['reset-persist-commit','reset-persist-rollback','persist-persist-commit','persist-persist-rollback'])))THEN RAISE EXCEPTION 'C59S17I_CLEANUP_CAPTURED_REQUEST_CLOCK';END IF;
 IF t-ARRAY['user','public.messages','private.workout_strength_request_admissions']IS DISTINCT FROM s-ARRAY['user','public.messages','private.workout_strength_request_admissions']OR t->'user'IS DISTINCT FROM(s->'user')||jsonb_build_object('last_active_at',m->'created_at')OR m->>'id'IS DISTINCT FROM a->>'flow_inbound_id'OR m->>'user_id'IS DISTINCT FROM c.owner_id::text OR m->>'direction'IS DISTINCT FROM 'in'OR m->>'role'IS DISTINCT FROM 'user'OR m->>'content_type'IS DISTINCT FROM 'text'OR m->>'provider'IS DISTINCT FROM 'mobile_flow'OR m->>'provider_message_id'IS DISTINCT FROM 'mobile_flow/'||c.owner_id::text||'/'||(c.payload->>'requestKey')OR m->>'content'IS DISTINCT FROM c.payload->>'text'OR(m->>'created_at')::timestamptz IS DISTINCT FROM(raw->>'attempt_started_at')::timestamptz OR m->>'delivery_status'IS DISTINCT FROM 'processing'OR EXISTS(SELECT 1 FROM jsonb_each(m-ARRAY['id','user_id','direction','role','content_type','content','provider','provider_message_id','raw_payload','delivery_status','created_at'])x WHERE x.value<>'null'::jsonb)THEN RAISE EXCEPTION 'C59S17I_CLEANUP_EXACT_PERSIST_DELTA';END IF;phase:='committed_writer_A_or_B';
 END IF;END IF;
 RAISE NOTICE 'C59S17I_CLEANUP_OWNED_PHASE:%:%',c.case_id,phase;
 END LOOP;
 -- Every owner and complete permitted state has been checked before any DELETE.
 FOR c IN SELECT owner_id FROM c59s17i_fixture.cases LOOP DELETE FROM public.users WHERE id=c.owner_id;END LOOP;
END $cleanup$;
DO $drop$DECLARE f record;BEGIN FOR f IN SELECT oid FROM pg_proc WHERE pronamespace='c59s17i_fixture'::regnamespace ORDER BY oid LOOP EXECUTE format('DROP FUNCTION %s',f.oid::regprocedure);END LOOP;END $drop$;
DROP TABLE c59s17i_fixture.cases,c59s17i_fixture.ownership;DROP SCHEMA c59s17i_fixture;
\if :dry_cleanup_baseline
\if :{?dry_fingerprint_path}
\i :dry_fingerprint_path
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17I_DRY_FINGERPRINT_PATH_REQUIRED';END$$;
\endif
ROLLBACK;
\echo C59S17I_DRY_CLEAN_BASELINE_ROLLBACK_CONFIRMED
\else
COMMIT;
\echo C59S17I_TEARDOWN_CONFIRMED
\endif
\else
DO $api$BEGIN IF to_regprocedure('public.access_workout_strength_flow_inbound(uuid,uuid,text,text,text,timestamp with time zone)')IS NULL THEN RAISE EXCEPTION 'C59S17I_SETUP_API_ABSENT_NOT_PRODUCT_RED' USING ERRCODE='42883';END IF;END $api$;
\if :setup_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';
DO $cases$DECLARE ids text[]:=ARRAY['persist-reset-commit','persist-reset-rollback','reset-persist-commit','reset-persist-rollback','persist-persist-commit','persist-persist-rollback','probe-reset','reset-probe'];i integer;p jsonb;BEGIN
 IF(SELECT array_agg(case_id)FROM c59s17i_fixture.cases)IS DISTINCT FROM ARRAY['sentinel']THEN RAISE EXCEPTION 'C59S17I_SETUP_CASES_COLLISION';END IF;
 FOR i IN 4301..4308 LOOP p:=c59s17i_fixture.seed(i);p:=p||jsonb_build_object('initialState',c59s17i_fixture.state(c59s17i_fixture.uid(i)));INSERT INTO c59s17i_fixture.cases VALUES(ids[i-4300],c59s17i_fixture.uid(i),p);END LOOP;
END $cases$;
COMMIT;
\echo C59S17I_CONCURRENCY_SETUP_CONFIRMED
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $rr$BEGIN PERFORM c59s17i_fixture.expect_error(format('SELECT public.access_workout_strength_flow_inbound(%L::uuid,%L::uuid,''x'',''probe'',NULL,NULL)',c59s17i_fixture.uid(4199),c59s17i_fixture.uid(9199)),c59s17i_fixture.uid(4199),'22023');PERFORM c59s17i_fixture.ok(true,'RR_rejected_before_missing_owner');END $rr$;
ROLLBACK;
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='120s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $capability$DECLARE f oid:='public.access_workout_strength_flow_inbound(uuid,uuid,text,text,text,timestamp with time zone)'::regprocedure;v boolean;u uuid:=c59s17i_fixture.uid(4199);BEGIN
 SELECT prosecdef AND proowner='postgres'::regrole AND proconfig=ARRAY['search_path=pg_catalog']AND pronargdefaults=0 AND pronargs=6 AND prorettype='jsonb'::regtype INTO v FROM pg_proc WHERE oid=f;
 PERFORM c59s17i_fixture.ok(v AND(SELECT count(*)=1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'AND p.proname='access_workout_strength_flow_inbound'),'RPC_exact_signature_definer_owner_path_no_defaults_or_overload');
 PERFORM c59s17i_fixture.ok(has_function_privilege('service_role',f,'EXECUTE')AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce((SELECT proacl FROM pg_proc WHERE oid=f),acldefault('f','postgres'::regrole)))a WHERE a.grantee NOT IN('postgres'::regrole,'service_role'::regrole)OR(a.grantee='service_role'::regrole AND(a.privilege_type<>'EXECUTE'OR a.is_grantable)))AND NOT has_function_privilege('anon',f,'EXECUTE')AND NOT has_function_privilege('authenticated',f,'EXECUTE'),'RPC_canonical_owner_service_ACL');
 PERFORM c59s17i_fixture.ok((SELECT count(*)=2 AND bool_and(NOT a.attnotnull AND d.oid IS NULL AND CASE a.attname WHEN 'flow_inbound_id'THEN a.atttypid='uuid'::regtype AND a.attnum=10 ELSE a.atttypid='text'::regtype AND a.attcollation='pg_catalog."C"'::regcollation AND a.attnum=11 END)FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid='private.workout_strength_request_admissions'::regclass AND a.attname IN('flow_inbound_id','flow_inbound_refusal')AND NOT a.attisdropped)AND NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.workout_strength_request_admissions'::regclass AND contype='f'AND(conkey&&ARRAY[10,11]::smallint[])),'two_new_nullable_columns_exact_types_C_no_defaults_or_live_FK');
 PERFORM c59s17i_fixture.ok(NOT has_table_privilege('service_role','private.workout_strength_request_admissions','INSERT,UPDATE,DELETE')AND NOT has_column_privilege('service_role','private.workout_strength_request_admissions','flow_inbound_id','UPDATE')AND NOT has_column_privilege('service_role','private.workout_strength_request_admissions','flow_inbound_refusal','UPDATE')AND(SELECT relrowsecurity AND NOT relforcerowsecurity FROM pg_class WHERE oid='private.workout_strength_request_admissions'::regclass),'private_DML_not_granted_and_RLS_preserved');
 PERFORM c59s17i_fixture.expect_error('SELECT public.access_workout_strength_flow_inbound(NULL,NULL,NULL,NULL,NULL,NULL)',u,'42501','anon');PERFORM c59s17i_fixture.expect_error('SELECT public.access_workout_strength_flow_inbound(NULL,NULL,NULL,NULL,NULL,NULL)',u,'42501','authenticated');PERFORM c59s17i_fixture.ok(true,'actual_anon_authenticated_EXECUTE_denied');
END $capability$;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
DO $guard$BEGIN PERFORM c59s17i_fixture.expect_error('SELECT public.access_workout_strength_flow_inbound(NULL,NULL,NULL,NULL,NULL,NULL)',c59s17i_fixture.uid(4199),'42501');PERFORM c59s17i_fixture.ok(true,'trusted_guard_precedes_invalid_shape');END $guard$;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $inputs$DECLARE p jsonb:=c59s17i_fixture.seed(4101);u uuid:=(p->>'ownerID')::uuid;q jsonb;s text;k text;BEGIN
 PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p||jsonb_build_object('admission',jsonb_build_object('admissionID',c59s17i_fixture.uid(9101))),'probe'),u,'{"status":"forbidden","reason":"invalid_admission"}');q:=c59s17i_fixture.seed(4108);PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p||jsonb_build_object('admission',q->'admission'),'probe'),u,'{"status":"forbidden","reason":"invalid_admission"}');PERFORM c59s17i_fixture.ok(true,'missing_admission_no_implicit_creation');
 PERFORM c59s17i_fixture.expect_error(format('SELECT public.access_workout_strength_flow_inbound(NULL,%L,%L,''probe'',NULL,NULL)',p#>>'{admission,admissionID}',p->>'text'),u,'22023');PERFORM c59s17i_fixture.expect_error(format('SELECT public.access_workout_strength_flow_inbound(%L,NULL,%L,''probe'',NULL,NULL)',u,p->>'text'),u,'22023');
 FOREACH s IN ARRAY ARRAY[NULL::text,'','PROBE',' persist','unknown']LOOP PERFORM c59s17i_fixture.expect_error(c59s17i_fixture.access_sql(p,s),u,'22023');END LOOP;PERFORM c59s17i_fixture.ok(true,'literal_mode_and_NULL_shape_validation');
 FOREACH k IN ARRAY ARRAY[NULL::text,'','short','has space 0001','á23456789',repeat('x',129)]LOOP PERFORM c59s17i_fixture.expect_error(c59s17i_fixture.access_sql(p,'persist',k),u,'22023');END LOOP;PERFORM c59s17i_fixture.ok(true,'request_ID_ASCII_bounds_no_silent_trim');
 FOREACH s IN ARRAY ARRAY[NULL::text,'infinity','-infinity','2026-10-15T12:00:00.123001Z','0001-01-01 00:00:00 BC','10000-01-01 00:00:00+00']LOOP PERFORM c59s17i_fixture.expect_error(c59s17i_fixture.access_sql(p,'persist','s17i-valid-request',s),u,'22023');END LOOP;PERFORM c59s17i_fixture.ok(true,'started_at_finite_exact_ms_UTC_year_range');
 FOREACH s IN ARRAY ARRAY[NULL::text,'',repeat('x',4001)]LOOP PERFORM c59s17i_fixture.expect_error(c59s17i_fixture.access_sql(p||jsonb_build_object('text',s),'probe'),u,'22023');END LOOP;PERFORM c59s17i_fixture.ok(true,'text_NULL_empty_and_character_bound');
 PERFORM c59s17i_fixture.expect_error(format('SELECT public.access_workout_strength_flow_inbound(%L,%L,%L,''probe'',''s17i-not-null'',NULL)',u,p#>>'{admission,admissionID}',p->>'text'),u,'22023');PERFORM c59s17i_fixture.expect_error(format('SELECT public.access_workout_strength_flow_inbound(%L,%L,%L,''probe'',NULL,%L)',u,p#>>'{admission,admissionID}',p->>'text',p->>'startedAt'),u,'22023');PERFORM c59s17i_fixture.ok(true,'probe_requires_NULL_request_and_started');
 UPDATE public.users SET status='blocked'WHERE id=u;PERFORM c59s17i_fixture.expect_error(c59s17i_fixture.access_sql(p,'probe'),u,'P0002');PERFORM c59s17i_fixture.ok(true,'inactive_owner_precedes_admission');
 PERFORM c59s17i_fixture.expect_error(c59s17i_fixture.access_sql(p||jsonb_build_object('ownerID',c59s17i_fixture.uid(4199)),'probe'),c59s17i_fixture.uid(4199),'P0002');PERFORM c59s17i_fixture.ok(true,'absent_owner_is_P0002');
END $inputs$;
DO $positive$DECLARE p jsonb:=c59s17i_fixture.seed(4102);u uuid:=(p->>'ownerID')::uuid;s jsonb:=c59s17i_fixture.state(u);o jsonb:=c59s17i_fixture.outside(u);r jsonb;t jsonb;j jsonb;m uuid;BEGIN
 PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p,'probe'),u,'{"status":"unbound"}');PERFORM c59s17i_fixture.ok(true,'probe_unbound_zero_IN_attempt_lifecycle_or_clocks');
 r:=c59s17i_fixture.inserted(p);m:=(r#>>'{inbound,id}')::uuid;t:=c59s17i_fixture.state(u);
 PERFORM c59s17i_fixture.ok((SELECT array_agg(k ORDER BY k)FROM jsonb_object_keys(r)k)=ARRAY['inbound','status']AND(SELECT array_agg(k ORDER BY k)FROM jsonb_object_keys(r->'inbound')k)=ARRAY['content','created_at','delivery_status','direction','id','raw_payload']AND r->'inbound'=jsonb_build_object('id',m,'direction','in','content',p->'text','delivery_status','processing','created_at','2026-10-15T12:00:00.123Z','raw_payload',jsonb_build_object('request_id','s17i-original-request','conversation_id','flow','attempt_started_at','2026-10-15T12:00:00.123Z','provider_started_at',NULL,'retry_started_at','[]'::jsonb)),'inserted_exact_internal_wire_ISO3_and_initial_attempt');
 SELECT to_jsonb(a)INTO STRICT j FROM private.workout_strength_request_admissions a WHERE user_id=u;PERFORM c59s17i_fixture.ok(j=(s#>'{private.workout_strength_request_admissions,0}')||jsonb_build_object('flow_inbound_id',m)AND t-ARRAY['user','public.messages','private.workout_strength_request_admissions']=s-ARRAY['user','public.messages','private.workout_strength_request_admissions']AND c59s17i_fixture.outside(u)=o,'one_receipt_only_original_S15_fields_epoch_lifecycle_and_neighbors_unchanged');
 PERFORM c59s17i_fixture.ok(t->'user'=(s->'user')||jsonb_build_object('last_active_at',t#>'{user,last_active_at}')AND(t#>>'{user,last_active_at}')::timestamptz=(p->>'startedAt')::timestamptz AND jsonb_array_length(t->'public.messages')=1,'real_last_active_trigger_uses_original_started_at');
 PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p),u,r||'{"status":"reused"}'::jsonb);PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p,'persist','s17i-later-request','2026-10-16T13:00:00.999Z'),u,r||'{"status":"reused"}'::jsonb);PERFORM c59s17i_fixture.ok(true,'lost_response_reuses_UUID_attempt_request_and_all_timestamps');
 PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p,'probe'),u,r||'{"status":"bound"}'::jsonb);PERFORM c59s17i_fixture.ok(true,'probe_bound_never_rewrites_existing_IN');
 UPDATE public.messages SET delivery_status='failed',raw_payload='{"request_id":17,"conversation_id":null,"attempt_started_at":{"x":1},"provider_started_at":false,"retry_started_at":"not-array","last_retry_at":[1],"authority":"synthetic-private","media_url":"synthetic-private"}'::jsonb WHERE id=m;
 s:=c59s17i_fixture.state(u);r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p,'probe'));PERFORM c59s17i_fixture.ok(r#>'{result,inbound,raw_payload}'='{"request_id":17,"conversation_id":null,"attempt_started_at":{"x":1},"provider_started_at":false,"retry_started_at":"not-array","last_retry_at":[1]}'::jsonb AND r#>>'{result,inbound,delivery_status}'='failed'AND c59s17i_fixture.state(u)=s AND(SELECT raw_payload ? 'authority'FROM public.messages WHERE id=m),'whitelist_removes_private_keys_but_preserves_existing_JSON_values_and_state');
 UPDATE public.messages SET created_at='2026-10-15T12:00:00.123456Z'WHERE id=m;r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p,'probe'));PERFORM c59s17i_fixture.ok(r#>>'{result,inbound,created_at}'='2026-10-15T12:00:00.123456Z','subms_existing_created_at_preserved_US6_not_truncated');
END $positive$;
DO $lexical$DECLARE p jsonb:=c59s17i_fixture.seed(4103,E' café 🏋️\nUnicode é ');u uuid:=(p->>'ownerID')::uuid;r jsonb;s text;BEGIN
 FOREACH s IN ARRAY ARRAY[btrim(p->>'text'),normalize(p->>'text',NFC),to_jsonb(p->>'text')::text]LOOP PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p||jsonb_build_object('text',s),'probe'),u,'{"status":"conflict","reason":"request_content_conflict"}');END LOOP;PERFORM c59s17i_fixture.ok(true,'UTF8_hash_not_JSON_NFC_or_second_trim_and_conflict_no_refusal');
 r:=c59s17i_fixture.inserted(p);PERFORM c59s17i_fixture.ok(r#>>'{inbound,content}'=p->>'text','literal_unicode_newline_spaces_preserved');
 p:=c59s17i_fixture.seed(4104);r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p,'persist','s17i-offset-request','2026-10-15T15:00:00.123000+03:00'));IF r#>>'{result,inbound,created_at}'IS DISTINCT FROM '2026-10-15T12:00:00.123Z'OR r#>>'{result,inbound,raw_payload,attempt_started_at}'IS DISTINCT FROM '2026-10-15T12:00:00.123Z'THEN RAISE EXCEPTION 'C59S17I_OFFSET_ISO3';END IF;
 p:=c59s17i_fixture.seed(4105);r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p,'persist','s17i-zero-ms-request','2026-10-15T12:00:00Z'));PERFORM c59s17i_fixture.ok(r#>>'{result,inbound,created_at}'='2026-10-15T12:00:00.000Z'AND r#>>'{result,inbound,raw_payload,attempt_started_at}'='2026-10-15T12:00:00.000Z','started_offset_and_six_zero_tail_canonicalize_to_UTC_ISO3');
 p:=c59s17i_fixture.seed(4106);r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p,'persist','s17i-year-one-request','0001-01-01T00:00:00.000Z'));IF r#>>'{result,inbound,created_at}'IS DISTINCT FROM '0001-01-01T00:00:00.000Z'THEN RAISE EXCEPTION 'C59S17I_MIN_YEAR';END IF;
 p:=c59s17i_fixture.seed(4107);r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p,'persist','s17i-year-max-request','9999-12-31T23:59:59.999Z'));PERFORM c59s17i_fixture.ok(r#>>'{result,inbound,created_at}'='9999-12-31T23:59:59.999Z','valid_UTC_years_0001_and_9999_accept_exact_ISO3');
 p:=c59s17i_fixture.seed(4109,repeat('é',4000));r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p,'persist',repeat('x',128)));PERFORM c59s17i_fixture.ok(r#>>'{result,status}'='inserted'AND char_length(r#>>'{result,inbound,content}')=4000 AND octet_length(r#>>'{result,inbound,content}')=8000,'valid_4000_characters_not_bytes_and_128_ASCII_request_ID');
END $lexical$;
DO $collisions$DECLARE p jsonb;q jsonb;u uuid;m uuid;r jsonb;s jsonb;i integer;direction text;owner uuid;BEGIN
 FOR i IN 4110..4112 LOOP p:=c59s17i_fixture.seed(i);u:=(p->>'ownerID')::uuid;direction:=CASE WHEN i=4111 THEN 'out'ELSE 'in'END;owner:=CASE WHEN i=4112 THEN c59s17i_fixture.owner(4113)ELSE u END;
 INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id)VALUES(owner,direction::public.direction_enum,'user','text',p->>'text','mobile_flow','mobile_flow/'||u::text||'/'||(p->>'requestKey'))RETURNING id INTO m;s:=c59s17i_fixture.state(u);
 r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p,'probe'));PERFORM c59s17i_fixture.ok(r='{"ok":true,"result":{"status":"forbidden","reason":"unproved_inbound"}}'::jsonb AND(c59s17i_fixture.state(u)-'private.workout_strength_request_admissions')=(s-'private.workout_strength_request_admissions')AND(SELECT to_jsonb(a)=(s#>'{private.workout_strength_request_admissions,0}')||'{"flow_inbound_refusal":"unproved_inbound"}'::jsonb FROM private.workout_strength_request_admissions a WHERE user_id=u),'unproved_collision_'||CASE i WHEN 4110 THEN 'own_IN'WHEN 4111 THEN 'own_OUT'ELSE 'foreign_IN'END);
 DELETE FROM public.messages WHERE id=m;PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p),u,'{"status":"forbidden","reason":"unproved_inbound"}');END LOOP;
 p:=c59s17i_fixture.seed(4116);u:=(p->>'ownerID')::uuid;INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id)VALUES(u,'in','user','text',p->>'text','mobile_flow','mobile_flow/'||u::text||'/'||(p->>'requestKey'))RETURNING id INTO m;
 r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p));IF r#>'{result}'IS DISTINCT FROM '{"status":"forbidden","reason":"unproved_inbound"}'::jsonb OR NOT EXISTS(SELECT 1 FROM private.workout_strength_request_admissions WHERE user_id=u AND flow_inbound_refusal='unproved_inbound'AND flow_inbound_id IS NULL)THEN RAISE EXCEPTION 'C59S17I_PERSIST_COLLISION_NOT_REFUSED';END IF;DELETE FROM public.messages WHERE id=m;PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p,'probe'),u,'{"status":"forbidden","reason":"unproved_inbound"}');PERFORM c59s17i_fixture.ok(true,'collision_refusal_persists_after_delete_no_new_UUID_adopted');
 p:=c59s17i_fixture.seed(4114);u:=(p->>'ownerID')::uuid;INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id)VALUES(u,'in','user','text',p->>'text','mobile_flow',p->>'requestKey')RETURNING id INTO m;r:=c59s17i_fixture.inserted(p);PERFORM c59s17i_fixture.ok((r#>>'{inbound,id}')::uuid<>m AND(SELECT count(*)=2 FROM public.messages WHERE user_id=u),'bare_legacy_key_never_supplies_receipt_or_blocks_scoped_insert');
END $collisions$;
DO $legacy_pair$DECLARE p jsonb:=c59s17i_fixture.seed(4115);u uuid:=(p->>'ownerID')::uuid;m uuid;r jsonb;BEGIN
 INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id)VALUES(u,'in','user','text',p->>'text','mobile_flow','mobile_flow/'||u::text||'/'||(p->>'requestKey'))RETURNING id INTO m;
 r:=c59s17i_fixture.attempt(format('SELECT public.initialize_workout_strength_lifecycle(%L,%L,%L)',u,p#>>'{admission,admissionID}',m));IF r#>>'{result,status}'IS DISTINCT FROM 'initialized'THEN RAISE EXCEPTION 'C59S17I_SETUP_LEGACY_PAIR';END IF;
 DELETE FROM public.messages WHERE id=m;r:=c59s17i_fixture.attempt(c59s17i_fixture.access_sql(p));PERFORM c59s17i_fixture.ok(r#>'{result}'='{"status":"forbidden","reason":"unproved_inbound"}'::jsonb AND(SELECT flow_inbound_id IS NULL AND flow_inbound_refusal='unproved_inbound'AND original_inbound_id=m AND lifecycle_key IS NOT NULL FROM private.workout_strength_request_admissions WHERE user_id=u),'S15_pair_without_new_receipt_is_persistently_unproved');
END $legacy_pair$;
DO $missing$DECLARE p jsonb:=c59s17i_fixture.seed(4120);u uuid:=(p->>'ownerID')::uuid;r jsonb:=c59s17i_fixture.inserted(p);m uuid:=(r#>>'{inbound,id}')::uuid;n uuid;BEGIN
 DELETE FROM public.messages WHERE id=m;PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p,'probe'),u,'{"status":"forbidden","reason":"inbound_mismatch"}');PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p),u,'{"status":"forbidden","reason":"inbound_mismatch"}');PERFORM c59s17i_fixture.ok(true,'bound_UUID_missing_no_recreation');
 INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id,raw_payload,created_at)VALUES(u,'in','user','text',p->>'text','mobile_flow','mobile_flow/'||u::text||'/'||(p->>'requestKey'),r#>'{inbound,raw_payload}',(p->>'startedAt')::timestamptz)RETURNING id INTO n;
 PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p),u,'{"status":"forbidden","reason":"inbound_mismatch"}');PERFORM c59s17i_fixture.ok(n<>m AND(SELECT flow_inbound_id=m FROM private.workout_strength_request_admissions WHERE user_id=u),'identical_recreated_row_never_replaces_original_receipt_UUID');
END $missing$;
DO $identity$DECLARE p jsonb;r jsonb;u uuid;m uuid;i integer;BEGIN
 FOR i IN 4130..4137 LOOP p:=c59s17i_fixture.seed(i);u:=(p->>'ownerID')::uuid;r:=c59s17i_fixture.inserted(p);m:=(r#>>'{inbound,id}')::uuid;
 CASE i WHEN 4130 THEN UPDATE public.messages SET user_id=c59s17i_fixture.owner(4138)WHERE id=m;
 WHEN 4131 THEN UPDATE public.messages SET direction='out'WHERE id=m;
 WHEN 4132 THEN UPDATE public.messages SET role='assistant'WHERE id=m;
 WHEN 4133 THEN UPDATE public.messages SET content_type='image'WHERE id=m;
 WHEN 4134 THEN UPDATE public.messages SET provider='whatsapp_cloud'WHERE id=m;
 WHEN 4135 THEN UPDATE public.messages SET provider_message_id=p->>'requestKey'WHERE id=m;
 WHEN 4136 THEN UPDATE public.messages SET content='different bytes'WHERE id=m;
 ELSE UPDATE public.messages SET content=NULL WHERE id=m;END CASE;
 PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p,'probe'),u,'{"status":"forbidden","reason":"inbound_mismatch"}');PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p),u,'{"status":"forbidden","reason":"inbound_mismatch"}');END LOOP;PERFORM c59s17i_fixture.ok(true,'bound_UUID_identity_owner_direction_role_type_provider_key_hash_NULL_fences');
 p:=c59s17i_fixture.seed(4140);u:=(p->>'ownerID')::uuid;r:=c59s17i_fixture.inserted(p);INSERT INTO private.workout_strength_lifecycles(user_id,lifecycle_key,opened_at)VALUES(u,c59s17i_fixture.uid(9140),clock_timestamp());UPDATE private.workout_strength_request_admissions SET original_inbound_id=c59s17i_fixture.uid(9141),lifecycle_key=c59s17i_fixture.uid(9140)WHERE user_id=u;
 PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p),u,'{"status":"forbidden","reason":"inbound_mismatch"}');PERFORM c59s17i_fixture.ok(true,'bound_S15_original_UUID_mismatch_no_lifecycle_rebind');
END $identity$;
DO $reset$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;i integer;mode text;BEGIN
 FOR i IN 4150..4152 LOOP p:=c59s17i_fixture.seed(i);u:=(p->>'ownerID')::uuid;IF i=4150 THEN r:=c59s17i_fixture.inserted(p);ELSIF i=4151 THEN UPDATE private.workout_strength_request_admissions SET flow_inbound_refusal='unproved_inbound'WHERE user_id=u;END IF;s:=c59s17i_fixture.state(u);
 IF i=4152 THEN r:=c59s17i_fixture.attempt(format('SELECT public.reset_user_conversation_atomic(%L)',u));ELSE r:=c59s17i_fixture.attempt(c59s17i_fixture.reset_sql(p,i=4150));END IF;
 IF r#>>'{result,reset}'IS DISTINCT FROM 'true'THEN RAISE EXCEPTION 'C59S17I_SETUP_REAL_RESET';END IF;PERFORM c59s17i_fixture.assert_reset(s,c59s17i_fixture.state(u));
 FOREACH mode IN ARRAY ARRAY['probe','persist']LOOP PERFORM c59s17i_fixture.expect_result(c59s17i_fixture.access_sql(p||jsonb_build_object('text','changed hash'),mode),u,'{"status":"forbidden","reason":"stale_epoch"}');END LOOP;END LOOP;PERFORM c59s17i_fixture.ok(true,'reset_keep_true_false_wrapper_preserves_receipts_and_stale_precedes_hash_refusal_replay_insert');
 r:=c59s17i_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L,%L,%L)',u,'s17i-fresh-after-reset',p->>'requestHash'));q:=p||jsonb_build_object('requestKey','s17i-fresh-after-reset','admission',r#>'{result,admission}');r:=c59s17i_fixture.inserted(q);PERFORM c59s17i_fixture.ok(r->>'status'='inserted'AND q#>>'{admission,epoch}'<>p#>>'{admission,epoch}','new_key_after_reset_may_create_one_fresh_IN_without_lifecycle');
END $reset$;
CREATE TRIGGER c59s17i_fault_before_binding BEFORE UPDATE ON private.workout_strength_request_admissions FOR EACH ROW EXECUTE FUNCTION c59s17i_fixture.fault_before_binding();
DO $fault$DECLARE p jsonb:=c59s17i_fixture.seed(4170);u uuid:=(p->>'ownerID')::uuid;BEGIN PERFORM c59s17i_fixture.expect_error(c59s17i_fixture.access_sql(p),u,'P0001','service_role','C59S17I_AFTER_INSERT_BEFORE_BINDING');PERFORM c59s17i_fixture.ok(true,'after_INSERT_before_receipt_fault_proves_order_then_rolls_back_IN_receipt_last_active');END $fault$;
DROP TRIGGER c59s17i_fault_before_binding ON private.workout_strength_request_admissions;
CREATE TRIGGER c59s17i_unrelated_unique AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION c59s17i_fixture.unrelated_unique();
DO $unique$DECLARE p jsonb:=c59s17i_fixture.seed(4171);u uuid:=(p->>'ownerID')::uuid;BEGIN PERFORM c59s17i_fixture.expect_error(c59s17i_fixture.access_sql(p),u,'23505','service_role','C59S17I_UNRELATED_UNIQUE');PERFORM c59s17i_fixture.ok(true,'unrelated_unique_violation_propagates_full_rollback_not_durable_refusal');END $unique$;
DROP TRIGGER c59s17i_unrelated_unique ON public.messages;
DO $constraint$DECLARE p jsonb:=c59s17i_fixture.seed(4172);u uuid:=(p->>'ownerID')::uuid;r jsonb:=c59s17i_fixture.inserted(p);BEGIN PERFORM c59s17i_fixture.expect_error(format('UPDATE private.workout_strength_request_admissions SET flow_inbound_refusal=''unproved_inbound''WHERE user_id=%L RETURNING to_jsonb(workout_strength_request_admissions)',u),u,'23514','postgres');PERFORM c59s17i_fixture.expect_error(format('UPDATE private.workout_strength_request_admissions SET flow_inbound_id=NULL,flow_inbound_refusal=''other''WHERE user_id=%L RETURNING to_jsonb(workout_strength_request_admissions)',u),u,'23514','postgres');PERFORM c59s17i_fixture.ok(true,'storage_rejects_UUID_and_refusal_simultaneously');END $constraint$;
DO $sentinel$BEGIN PERFORM c59s17i_fixture.ok((SELECT payload->'initialState'=c59s17i_fixture.state(owner_id)FROM c59s17i_fixture.cases WHERE case_id='sentinel'),'all_sequential_sentinel_fullstate_preserved');END $sentinel$;
ROLLBACK;
\echo C59S17I_SEQUENTIAL_ROLLBACK_CONFIRMED
\endif
\endif
\endif
