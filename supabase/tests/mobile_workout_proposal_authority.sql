\set ON_ERROR_STOP on
-- Real Root-installed product only; missing substrate/entrypoints are SETUP, never product RED.
DO $target$BEGIN
 IF session_user<>'c5_local_admin' OR current_database()<>'c5_reset_default_20261009' OR current_setting('port')<>'55489'
 OR current_setting('listen_addresses')<>'' OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data' THEN RAISE EXCEPTION 'C59S16_SETUP_WRONG_LOCAL_TARGET';END IF;
 IF to_regprocedure('public.replace_pending_registration_atomic(uuid,jsonb,timestamp with time zone,text)')IS NULL
 OR to_regprocedure('public.admit_workout_strength_request(uuid,text,text)')IS NULL OR to_regprocedure('public.reset_user_conversation_atomic(uuid,boolean)')IS NULL OR to_regprocedure('private.assert_trusted_backend()')IS NULL
 OR to_regclass('public.pending_registrations')IS NULL OR to_regtype('public.pending_registration_status')IS NULL OR to_regclass('private.workout_strength_authority_epochs')IS NULL
 THEN RAISE EXCEPTION 'C59S16_SETUP_REAL_SUBSTRATE_ABSENT' USING ERRCODE='42P01';END IF;
 IF to_regprocedure('public.admit_mobile_workout_proposal(uuid,text,jsonb)')IS NULL
 OR to_regprocedure('public.materialize_mobile_workout_proposal(uuid,uuid,jsonb,jsonb,timestamp with time zone)')IS NULL
 OR to_regprocedure('private.mobile_workout_proposal_input_hash(jsonb)')IS NULL OR to_regclass('private.mobile_workout_proposal_admissions')IS NULL
 THEN RAISE EXCEPTION 'C59S16_SETUP_ENTRYPOINT_ABSENT' USING ERRCODE='42883';END IF;
END $target$;
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
DO $$BEGIN RAISE EXCEPTION 'C59S16_SETUP_CONFLICTING_MODES';END$$;
\endif
\endif
\if :teardown_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $owned$DECLARE o record;r record;c record;e record;u uuid;a jsonb;k text;BEGIN
 SELECT * INTO STRICT o FROM c59s16_fixture.ownership WHERE tag='c59s16_ui_proposal_v1';
 IF o.owner_name<>session_user OR o.object_oids IS DISTINCT FROM c59s16_fixture.object_oids() OR o.object_fingerprint IS DISTINCT FROM c59s16_fixture.object_fingerprint()
 OR(SELECT count(*)FROM c59s16_fixture.ownership)<>1 OR(SELECT count(*)FROM c59s16_fixture.cases)<>6
 OR(SELECT array_agg(owner_id ORDER BY owner_id)FROM c59s16_fixture.cases)IS DISTINCT FROM ARRAY(SELECT c59s16_fixture.uid(i)FROM generate_series(501,506)i ORDER BY i)
 THEN RAISE EXCEPTION 'C59S16_TEARDOWN_OBJECT_DRIFT';END IF;
 IF c59s16_fixture.state(c59s16_fixture.uid(999))IS DISTINCT FROM o.sentinel THEN RAISE EXCEPTION 'C59S16_TEARDOWN_SENTINEL_CHANGED';END IF;
 FOR r IN SELECT * FROM(VALUES
 (501,'materialize-reset-commit',true),(502,'materialize-reset-rollback',true),
 (503,'reset-materialize-commit',true),(504,'reset-materialize-rollback',false),
 (505,'materialize-materialize-commit',false),(506,'materialize-materialize-rollback',false),
 (999,NULL,false))x(n,case_id,was_reset)ORDER BY n LOOP
 u:=c59s16_fixture.uid(r.n);k:='s16-request-'||r.n;
 IF r.n=999 THEN
 a:=jsonb_build_object('ownerID',u::text,'admissionID',o.sentinel#>>'{private.mobile_workout_proposal_admissions,0,admission_id}',
 'epoch',o.sentinel#>>'{private.mobile_workout_proposal_admissions,0,epoch}','requestNamespace','mobile_workout_proposal_v1',
 'requestKey',o.sentinel#>>'{private.mobile_workout_proposal_admissions,0,request_key}','requestHash',o.sentinel#>>'{private.mobile_workout_proposal_admissions,0,request_hash}',
 'admittedAt',to_char((o.sentinel#>>'{private.mobile_workout_proposal_admissions,0,admitted_at}')::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
 ELSE
 SELECT owner_id,payload INTO c FROM c59s16_fixture.cases WHERE case_id=r.case_id;
 IF NOT FOUND OR c.owner_id IS DISTINCT FROM u OR c.payload->>'ownerID'IS DISTINCT FROM u::text
 OR c.payload->>'requestKey'IS DISTINCT FROM k OR c.payload->'input'IS DISTINCT FROM c59s16_fixture.input()
 THEN RAISE EXCEPTION 'C59S16_TEARDOWN_OWNER_DRIFT';END IF;a:=c.payload->'admission';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ONLY public.users WHERE id=u AND email='c59s16-'||r.n||'@example.invalid'
 AND wpp='155516'||lpad(r.n::text,7,'0')AND timezone='UTC'AND country='US'
 AND metadata IS NOT DISTINCT FROM CASE WHEN r.was_reset THEN '{}'::jsonb ELSE '{"c59s16_fixture":"c59s16_ui_proposal_v1"}'::jsonb END
 AND name IS NOT DISTINCT FROM CASE WHEN r.was_reset THEN NULL::text ELSE 'C59S16 synthetic' END
 AND country_confirmed IS NOT DISTINCT FROM (NOT r.was_reset)
 AND flow_phrase_cursor_revision IS NOT DISTINCT FROM CASE WHEN r.was_reset THEN 0::bigint ELSE 17::bigint END)
 THEN RAISE EXCEPTION 'C59S16_TEARDOWN_OWNER_DRIFT';END IF;
 IF jsonb_typeof(a)IS DISTINCT FROM 'object'THEN RAISE EXCEPTION 'C59S16_TEARDOWN_ADMISSION_DRIFT';END IF;
 IF(SELECT array_agg(key ORDER BY key)FROM jsonb_object_keys(a)key)IS DISTINCT FROM ARRAY['admissionID','admittedAt','epoch','ownerID','requestHash','requestKey','requestNamespace']
 OR a->>'ownerID'IS DISTINCT FROM u::text OR a->>'requestNamespace'IS DISTINCT FROM 'mobile_workout_proposal_v1'
 OR a->>'requestKey'IS DISTINCT FROM k OR a->>'requestHash'IS DISTINCT FROM private.mobile_workout_proposal_input_hash(c59s16_fixture.input())
 OR(SELECT count(*)FROM private.mobile_workout_proposal_admissions WHERE user_id=u)<>1
 OR NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions j WHERE j.user_id=u
 AND j.admission_id::text=a->>'admissionID'AND j.epoch::text=a->>'epoch'AND j.request_key=k AND j.request_hash=a->>'requestHash'
 AND to_char(j.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')=a->>'admittedAt')
 THEN RAISE EXCEPTION 'C59S16_TEARDOWN_ADMISSION_DRIFT';END IF;
 SELECT epoch,current_lifecycle_key INTO e FROM private.workout_strength_authority_epochs WHERE user_id=u;
 IF NOT FOUND OR e.current_lifecycle_key IS NOT NULL
 OR(r.was_reset AND e.epoch::text IS NOT DISTINCT FROM a->>'epoch')
 OR(NOT r.was_reset AND e.epoch::text IS DISTINCT FROM a->>'epoch')
 THEN RAISE EXCEPTION 'C59S16_TEARDOWN_AUTHORITY_DRIFT';END IF;
 END LOOP;
 -- Every owner/admission is validated before the first DELETE.
 FOR u IN SELECT c59s16_fixture.uid(n)FROM unnest(ARRAY[501,502,503,504,505,506,999])n LOOP
 DELETE FROM public.users WHERE id=u;END LOOP;
END $owned$;
DROP FUNCTION c59s16_fixture.seed(integer,boolean);DROP FUNCTION c59s16_fixture.proposal(text,jsonb,integer);
DROP FUNCTION c59s16_fixture.input();DROP FUNCTION c59s16_fixture.owner(integer);DROP FUNCTION c59s16_fixture.admission_wire(jsonb,uuid,text,text,text);
DROP FUNCTION c59s16_fixture.fail_after_cancel();DROP FUNCTION c59s16_fixture.fail_after_bind();DROP FUNCTION c59s16_fixture.state(uuid);
DROP FUNCTION c59s16_fixture.object_fingerprint();DROP FUNCTION c59s16_fixture.object_oids();
DROP FUNCTION c59s16_fixture.uid(integer);DROP FUNCTION c59s16_fixture.attempt(text);DROP FUNCTION c59s16_fixture.ok(boolean,text);
DROP TABLE c59s16_fixture.cases;DROP TABLE c59s16_fixture.ownership;DROP SCHEMA c59s16_fixture;
COMMIT;
\echo C59S16_CONCURRENCY_TEARDOWN_CONFIRMED
\else
\if :setup_concurrency
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $rr$DECLARE a text;b text;i jsonb:='{"kind":"workout","workout_type":"c59s16","duration_min":10,"intensity":"leve"}';BEGIN
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id='c59b6000-0000-0000-0000-000000000700')THEN RAISE EXCEPTION 'C59S16_SETUP_RR_OWNER_COLLISION';END IF;
 BEGIN PERFORM public.admit_mobile_workout_proposal('c59b6000-0000-0000-0000-000000000700','s16-rr-valid',i);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS a=RETURNED_SQLSTATE;END;
 BEGIN PERFORM public.materialize_mobile_workout_proposal('c59b6000-0000-0000-0000-000000000700','c59b6000-0000-0000-0000-000000000800',i,'{"kind":"workout","workoutType":"c59s16","durationMin":10,"kcalEst":0,"intensity":"leve","sourceContentType":"mobile","source_provider_message_id":"s16-rr-valid","source_timestamp":"2026-10-15T12:00:00Z","source_timezone":"UTC","source_local_date":"2026-10-15","raw_args":{"workout_type":"c59s16","duration_min":10,"intensity":"leve"},"express_eligible":false}',now());EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS b=RETURNED_SQLSTATE;END;
 IF a IS DISTINCT FROM '22023' OR b IS DISTINCT FROM '22023' THEN RAISE EXCEPTION 'C59S16_ASSERT:RC_guard_before_owner_lookup';END IF;
 RAISE NOTICE 'C59S16_PASS:RC_guard_before_owner_lookup';
END $rr$;
ROLLBACK;
\endif
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $preflight$BEGIN
 IF to_regnamespace('c59s16_fixture')IS NOT NULL THEN RAISE EXCEPTION 'C59S16_SETUP_FIXTURE_COLLISION';END IF;
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id IN(SELECT('c59b6000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(501,506)i UNION ALL SELECT('c59b6000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(701,730)i UNION ALL SELECT 'c59b6000-0000-0000-0000-000000000999')
 OR email IN(SELECT 'c59s16-'||i||'@example.invalid'FROM generate_series(501,506)i UNION ALL SELECT 'c59s16-'||i||'@example.invalid'FROM generate_series(701,730)i UNION ALL SELECT 'c59s16-999@example.invalid')
 OR wpp IN(SELECT '155516'||lpad(i::text,7,'0')FROM generate_series(501,506)i UNION ALL SELECT '155516'||lpad(i::text,7,'0')FROM generate_series(701,730)i UNION ALL SELECT '1555160000999'))THEN RAISE EXCEPTION 'C59S16_SETUP_OWNER_COLLISION';END IF;
END $preflight$;
\ir fixtures/mobile_workout_proposal_authority_fixture.sql
\if :setup_concurrency
DO $seed$DECLARE i integer;p jsonb;ids text[]:=ARRAY['materialize-reset-commit','materialize-reset-rollback','reset-materialize-commit','reset-materialize-rollback','materialize-materialize-commit','materialize-materialize-rollback'];BEGIN
 FOR i IN 501..506 LOOP p:=c59s16_fixture.seed(i,false);INSERT INTO c59s16_fixture.cases VALUES(ids[i-500],(p->>'ownerID')::uuid,p);END LOOP;
 PERFORM c59s16_fixture.seed(999,true);
END $seed$;
INSERT INTO c59s16_fixture.ownership VALUES('c59s16_ui_proposal_v1',session_user,c59s16_fixture.object_oids(),c59s16_fixture.object_fingerprint(),c59s16_fixture.state(c59s16_fixture.uid(999)));
COMMIT;
\echo C59S16_CONCURRENCY_SETUP_CONFIRMED
\else
SELECT c59s16_fixture.object_fingerprint()AS fingerprint
\gset s16_
DO $schema$DECLARE t oid:='private.mobile_workout_proposal_admissions'::regclass;f oid;v boolean:=true;BEGIN
 SELECT c.relowner='postgres'::regrole AND c.relrowsecurity AND NOT c.relforcerowsecurity AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=t)
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner)))a WHERE a.grantee<>c.relowner)INTO v FROM pg_class c WHERE c.oid=t;
 PERFORM c59s16_fixture.ok(v AND(SELECT array_agg(attname::text ORDER BY attnum)FROM pg_attribute WHERE attrelid=t AND attnum>0 AND NOT attisdropped)=ARRAY['user_id','admission_id','epoch','request_key','request_hash','admitted_at','pending_id','first_proposal_hash','bound_at','rejection_reason']
 AND EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=t AND attname='request_key'AND attcollation='"C"'::regcollation)
 AND(SELECT count(*)FROM pg_constraint WHERE conrelid=t AND contype='f')=1
 AND EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=t AND contype='f'AND confrelid='private.workout_strength_authority_epochs'::regclass AND confdeltype='c'),'journal_exact_ten_columns_RLS_owner_only_epoch_FK');
 v:=true;
 FOR f IN SELECT oid FROM pg_proc WHERE oid IN('public.admit_mobile_workout_proposal(uuid,text,jsonb)'::regprocedure,'public.materialize_mobile_workout_proposal(uuid,uuid,jsonb,jsonb,timestamp with time zone)'::regprocedure)LOOP
 v:=v AND(SELECT proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog']AND pronargdefaults=0 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner)))a WHERE a.grantee NOT IN(proowner,'service_role'::regrole))FROM pg_proc WHERE oid=f)
 AND has_function_privilege('service_role',f,'EXECUTE')AND NOT has_function_privilege('anon',f,'EXECUTE')AND NOT has_function_privilege('authenticated',f,'EXECUTE');END LOOP;
 PERFORM c59s16_fixture.ok(v AND(SELECT proowner='postgres'::regrole AND NOT prosecdef AND provolatile='s'AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner)))a WHERE a.grantee<>proowner)FROM pg_proc WHERE oid='private.mobile_workout_proposal_input_hash(jsonb)'::regprocedure),'RPCs_only_owner_service_helper_invoker_stable_owner_only');
END $schema$;
DO $hash$DECLARE v jsonb:=c59s16_fixture.input();h text;u uuid:=c59s16_fixture.owner(701);r jsonb;s jsonb;a jsonb;low timestamptz:=clock_timestamp();BEGIN
 h:=private.mobile_workout_proposal_input_hash(v);
 PERFORM c59s16_fixture.ok(h=encode(sha256(convert_to('{"kind": "workout", "intensity": "moderada", "duration_min": 10, "workout_type": "C59S16 café 🏋️"}','UTF8')),'hex')AND h=private.mobile_workout_proposal_input_hash(jsonb_set(v,'{duration_min}','10.0')),'SQL_JSONB_hash_golden_normalizes_integral_duration_only');
 r:=public.admit_mobile_workout_proposal(u,'s16-main-701',v);s:=c59s16_fixture.state(u);
 PERFORM c59s16_fixture.ok(c59s16_fixture.admission_wire(r,u,'s16-main-701',h,'admitted')AND(r#>>'{admission,admittedAt}')::timestamptz>=low
 AND s->'public.pending_registrations'='[]'::jsonb AND s->'public.messages'='[]'::jsonb AND s->'private.workout_strength_lifecycles'='[]'::jsonb,'admit_real_receipt_DB_clock_no_pending_IN_or_life');
 a:=public.admit_mobile_workout_proposal(u,'s16-main-701',jsonb_set(v,'{duration_min}','10.0'));
 PERFORM c59s16_fixture.ok(a=jsonb_set(r,'{status}','"reused"')AND c59s16_fixture.state(u)=s,'admit_retry_preserves_receipt_and_all_state');
 a:=public.admit_mobile_workout_proposal(u,'s16-main-701',jsonb_set(v,'{duration_min}','11'));
 PERFORM c59s16_fixture.ok(a='{"status":"conflict","reason":"request_content_conflict"}'::jsonb AND c59s16_fixture.state(u)=s,'same_key_changed_input_conflict_never_overwrites');
 a:=public.admit_mobile_workout_proposal(u,'S16-main-701',v);
 PERFORM c59s16_fixture.ok(a->>'status'='admitted'AND a#>>'{admission,admissionID}'<>r#>>'{admission,admissionID}','request_key_is_literal_case_sensitive');
 a:=public.admit_mobile_workout_proposal(u,'s16-unicode-701',jsonb_set(v,'{workout_type}',to_jsonb('C59S16 café 🏋️'::text)));
 PERFORM c59s16_fixture.ok(a->>'status'='admitted'AND a#>>'{admission,requestHash}'<>h,'raw_workout_Unicode_not_normalized');
END $hash$;
DO $invalid$DECLARE u uuid:=c59s16_fixture.uid(701);v jsonb:=c59s16_fixture.input();q jsonb;r jsonb;s jsonb:=c59s16_fixture.state(u);k text;BEGIN
 FOR q IN SELECT value FROM jsonb_array_elements(jsonb_build_array(NULL::jsonb,'null'::jsonb,'[]'::jsonb,v-'intensity',v||'{"extra":1}',v||'{"kind":"meal"}',v||'{"duration_min":0}',v||'{"duration_min":1441}',v||'{"duration_min":10.5}',v||'{"duration_min":"10"}',v||'{"intensity":"extrema"}',v||'{"workout_type":" padded "}',v||'{"workout_type":""}',v||jsonb_build_object('workout_type',repeat('x',81)),v||'{"performed_at":"2026-10-15T12:00:00"}',v||'{"performed_at":"not-a-date"}'))LOOP
 r:=c59s16_fixture.attempt(format('SELECT public.admit_mobile_workout_proposal(%L::uuid,%L,%L::jsonb)',u,'s16-invalid-input',q));
 IF r IS DISTINCT FROM '{"ok":false,"sqlstate":"22023"}'::jsonb THEN RAISE EXCEPTION 'C59S16_INVALID_INPUT_NOT_REJECTED';END IF;END LOOP;
 r:=c59s16_fixture.attempt(format('SELECT public.admit_mobile_workout_proposal(%L::uuid,%L,NULL)',u,'s16-invalid-NULL'));
 PERFORM c59s16_fixture.ok(r='{"ok":false,"sqlstate":"22023"}'::jsonb AND c59s16_fixture.state(u)=s,'invalid_input_shapes_bounds_no_authority_writes');
 FOREACH k IN ARRAY ARRAY['short',' padded-key','padded-key ','unicode-é-key',repeat('x',129)]LOOP
 r:=c59s16_fixture.attempt(format('SELECT public.admit_mobile_workout_proposal(%L::uuid,%L,%L::jsonb)',u,k,v));IF r IS DISTINCT FROM '{"ok":false,"sqlstate":"22023"}'::jsonb THEN RAISE EXCEPTION 'C59S16_INVALID_KEY_NOT_REJECTED';END IF;END LOOP;
 PERFORM c59s16_fixture.ok(c59s16_fixture.state(u)=s,'invalid_key_not_trimmed_or_normalized');
END $invalid$;
DO $material$DECLARE p jsonb:=c59s16_fixture.seed(702,false);u uuid:=(p->>'ownerID')::uuid;a uuid:=(p#>>'{admission,admissionID}')::uuid;old uuid;r jsonb;replay_null jsonb;s jsonb;j jsonb;low timestamptz;BEGIN
 old:=(public.replace_pending_registration_atomic(u,'{"kind":"meal","mealType":"jantar"}',clock_timestamp()+interval '1 hour','s16-previous-702')->>'pending_id')::uuid;low:=clock_timestamp();
 r:=public.materialize_mobile_workout_proposal(u,a,p->'input',p->'proposal',(p->>'expiresAt')::timestamptz);SELECT to_jsonb(x)INTO j FROM private.mobile_workout_proposal_admissions x WHERE user_id=u;s:=c59s16_fixture.state(u);
 PERFORM c59s16_fixture.ok((SELECT array_agg(key ORDER BY key)FROM jsonb_object_keys(r)key)=ARRAY['cancelledCount','pendingID','pendingStatus','status']AND r->>'status'='materialized'AND r->>'pendingStatus'='pending'AND r->>'cancelledCount'='1'
 AND EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE id=old AND status='cancelled')
 AND EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE id=(r->>'pendingID')::uuid AND user_id=u AND proposal=p->'proposal'AND expires_at=(p->>'expiresAt')::timestamptz),'materialize_real_legacy_cancel_insert_exact_wire');
 PERFORM c59s16_fixture.ok(j->>'pending_id'=r->>'pendingID'AND j->>'first_proposal_hash'=encode(sha256(convert_to((p->'proposal')::text,'UTF8')),'hex')AND(j->>'bound_at')::timestamptz>=low AND j->'rejection_reason'='null'::jsonb,'bind_receipt_triplet_records_first_proposal_and_DB_clock');
 r:=public.materialize_mobile_workout_proposal(u,a,p->'input',jsonb_set(p->'proposal','{kcalEst}','999999999'),clock_timestamp()+interval '7 days');
 replay_null:=public.materialize_mobile_workout_proposal(u,a,p->'input',NULL,NULL);
 PERFORM c59s16_fixture.ok(r=jsonb_build_object('status','reused','pendingID',j->>'pending_id','pendingStatus','pending','cancelledCount',0)AND replay_null=r AND c59s16_fixture.state(u)=s,'bound_replay_ignores_recalculation_expiry_even_NULL_and_cancels_nothing');
END $material$;
DO $performed$DECLARE p jsonb:=c59s16_fixture.seed(703,false);u uuid:=(p->>'ownerID')::uuid;v jsonb:=(p->'input')||'{"performed_at":"2026-10-15T09:00:00-03:00"}';a jsonb;r jsonb;BEGIN
 a:=public.admit_mobile_workout_proposal(u,'s16-offset-703',v);
 r:=public.materialize_mobile_workout_proposal(u,(a#>>'{admission,admissionID}')::uuid,v,c59s16_fixture.proposal('s16-offset-703',v),now()+interval '1 hour');
 PERFORM c59s16_fixture.ok(r->>'status'='materialized','performed_at_matches_source_timestamp_by_SQL_instant');
END $performed$;
DO $millisecond_precision$DECLARE u uuid:=c59s16_fixture.owner(722);v jsonb;a jsonb;p jsonb;r jsonb;s jsonb;t text;k text;i integer:=0;BEGIN
 FOREACH t IN ARRAY ARRAY['2026-10-15T09:00:00.123456-03:00','2026-10-15T09:00:00.123999999-03:00']LOOP
 i:=i+1;k:='s16-precision-722-'||i;v:=c59s16_fixture.input()||jsonb_build_object('performed_at',t);
 a:=public.admit_mobile_workout_proposal(u,k,v);
 IF a->>'status'IS DISTINCT FROM 'admitted'THEN RAISE EXCEPTION 'C59S16_SETUP_PRECISION_ADMISSION';END IF;
 -- The real JS builder truncates input fractions before SQL can round them.
 p:=jsonb_set(c59s16_fixture.proposal(k,v),'{source_timestamp}','"2026-10-15T12:00:00.123Z"');s:=c59s16_fixture.state(u);
 r:=c59s16_fixture.attempt(format('SELECT public.materialize_mobile_workout_proposal(%L::uuid,%L::uuid,%L::jsonb,%L::jsonb,%L::timestamptz)',u,a#>>'{admission,admissionID}',v,jsonb_set(p,'{source_timestamp}','"2026-10-15T12:00:00.124Z"'),now()+interval '1 hour'));
 IF r IS DISTINCT FROM '{"ok":false,"sqlstate":"22023"}'::jsonb OR c59s16_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S16_WRONG_ROUNDED_MILLISECOND_ACCEPTED';END IF;
 r:=public.materialize_mobile_workout_proposal(u,(a#>>'{admission,admissionID}')::uuid,v,p,now()+interval '1 hour');
 IF r->>'status'IS DISTINCT FROM 'materialized'OR NOT EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE id=(r->>'pendingID')::uuid AND proposal->>'source_timestamp'='2026-10-15T12:00:00.123Z')THEN RAISE EXCEPTION 'C59S16_JS_MILLISECOND_TRUNCATION_NOT_PRESERVED';END IF;
 END LOOP;
 PERFORM c59s16_fixture.ok(true,'performed_at_submilliseconds_match_real_JS_truncation_not_SQL_rounding');
END $millisecond_precision$;
DO $proposal_bad$DECLARE p jsonb:=c59s16_fixture.seed(704,false);u uuid:=(p->>'ownerID')::uuid;q jsonb;r jsonb;s jsonb:=c59s16_fixture.state(u);BEGIN
 FOR q IN SELECT value FROM jsonb_array_elements(jsonb_build_array((p->'proposal')-'raw_args',(p->'proposal')-'source_timezone',p->'proposal'||'{"extra":1}',p->'proposal'||'{"kind":"meal"}',p->'proposal'||'{"workoutType":"other"}',p->'proposal'||'{"durationMin":11}',p->'proposal'||'{"intensity":"alta"}',p->'proposal'||'{"sourceContentType":"text"}',p->'proposal'||'{"source_provider_message_id":"other-key"}',p->'proposal'||'{"raw_args":{"workout_type":"other","duration_min":10,"intensity":"moderada"}}',p->'proposal'||'{"express_eligible":true}',p->'proposal'||'{"kcalEst":-1}',p->'proposal'||'{"kcalEst":1.5}',p->'proposal'||'{"source_timestamp":"not-a-date"}',p->'proposal'||'{"source_timezone":""}',p->'proposal'||'{"source_local_date":"2026-02-30"}'))LOOP
 r:=c59s16_fixture.attempt(format('SELECT public.materialize_mobile_workout_proposal(%L::uuid,%L::uuid,%L::jsonb,%L::jsonb,%L::timestamptz)',u,p#>>'{admission,admissionID}',p->'input',q,p->>'expiresAt'));
 IF r IS DISTINCT FROM '{"ok":false,"sqlstate":"22023"}'::jsonb THEN RAISE EXCEPTION 'C59S16_INVALID_PROPOSAL_NOT_REJECTED';END IF;END LOOP;
 PERFORM c59s16_fixture.ok(c59s16_fixture.state(u)=s,'first_bind_rejects_mismatched_proposal_without_writes');
 r:=c59s16_fixture.attempt(format('SELECT public.materialize_mobile_workout_proposal(%L::uuid,%L::uuid,%L::jsonb,%L::jsonb,%L::timestamptz)',u,p#>>'{admission,admissionID}',p->'input',p->'proposal','infinity'));
 PERFORM c59s16_fixture.ok(r='{"ok":false,"sqlstate":"22023"}'::jsonb AND c59s16_fixture.state(u)=s,'nonfinite_expiry_rejected_without_new_deadline_rule');
 r:=public.materialize_mobile_workout_proposal(u,(p#>>'{admission,admissionID}')::uuid,p->'input',jsonb_set(p->'proposal','{kcalEst}','1000000000000000000000000000000'),now()-interval '1 hour');
 PERFORM c59s16_fixture.ok(r->>'status'='materialized','finite_past_expiry_and_large_nonnegative_kcal_no_new_limits');
END $proposal_bad$;
DO $edited$DECLARE p jsonb:=c59s16_fixture.seed(705,true);u uuid:=(p->>'ownerID')::uuid;pid uuid:=(p#>>'{materialized,pendingID}')::uuid;s jsonb;r jsonb;st text;BEGIN
 UPDATE public.pending_registrations SET proposal=proposal||'{"workoutType":"edited raw","source_provider_message_id":"s16-edited-key"}'WHERE id=pid;s:=c59s16_fixture.state(u);
 r:=public.materialize_mobile_workout_proposal(u,(p#>>'{admission,admissionID}')::uuid,p->'input',p->'proposal',now()+interval '2 hours');
 PERFORM c59s16_fixture.ok(r=jsonb_build_object('status','reused','pendingID',pid,'pendingStatus','pending','cancelledCount',0)AND c59s16_fixture.state(u)=s,'bound_replay_never_restores_edited_payload_or_key');
 FOREACH st IN ARRAY ARRAY['cancelled','expired','confirmed']LOOP
 UPDATE public.pending_registrations SET status=st::public.pending_registration_status,expires_at=now()-interval '1 hour',resolved_at=now()WHERE id=pid;s:=c59s16_fixture.state(u);
 r:=public.materialize_mobile_workout_proposal(u,(p#>>'{admission,admissionID}')::uuid,p->'input',p->'proposal',now()+interval '2 hours');
 IF r IS DISTINCT FROM jsonb_build_object('status','reused','pendingID',pid,'pendingStatus',st,'cancelledCount',0)OR c59s16_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S16_CLOSED_PENDING_REPLAY_REWRITES';END IF;END LOOP;
 PERFORM c59s16_fixture.ok(true,'bound_replay_reports_actual_cancelled_expired_confirmed_state');
 DELETE FROM public.pending_registrations WHERE id=pid;s:=c59s16_fixture.state(u);
 r:=public.materialize_mobile_workout_proposal(u,(p#>>'{admission,admissionID}')::uuid,p->'input',p->'proposal',now()+interval '2 hours');
 PERFORM c59s16_fixture.ok(r='{"status":"forbidden","reason":"pending_missing"}'::jsonb AND c59s16_fixture.state(u)=s,'missing_original_pending_never_recreated');
END $edited$;
DO $foreign$DECLARE p jsonb:=c59s16_fixture.seed(706,true);q jsonb:=c59s16_fixture.seed(707,true);u uuid:=(p->>'ownerID')::uuid;v uuid:=(q->>'ownerID')::uuid;s jsonb:=c59s16_fixture.state(u);b jsonb:=c59s16_fixture.state(v);r jsonb;BEGIN
 r:=public.materialize_mobile_workout_proposal(u,(q#>>'{admission,admissionID}')::uuid,p->'input',p->'proposal',now()+interval '1 hour');
 PERFORM c59s16_fixture.ok(r='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND c59s16_fixture.state(u)=s AND c59s16_fixture.state(v)=b,'foreign_admission_and_other_owner_unchanged');
 UPDATE private.mobile_workout_proposal_admissions SET pending_id=(q#>>'{materialized,pendingID}')::uuid WHERE user_id=u;s:=c59s16_fixture.state(u);
 r:=public.materialize_mobile_workout_proposal(u,(p#>>'{admission,admissionID}')::uuid,p->'input',p->'proposal',now()+interval '1 hour');
 PERFORM c59s16_fixture.ok(r='{"status":"forbidden","reason":"pending_missing"}'::jsonb AND c59s16_fixture.state(u)=s AND c59s16_fixture.state(v)=b,'foreign_pending_UUID_never_adopted');
END $foreign$;
DO $stale$DECLARE p jsonb:=c59s16_fixture.seed(708,false);q jsonb:=c59s16_fixture.seed(709,true);u uuid;s jsonb;r jsonb;x jsonb;BEGIN
 FOR x IN SELECT value FROM jsonb_array_elements(jsonb_build_array(p,q))LOOP
 u:=(x->>'ownerID')::uuid;r:=public.reset_user_conversation_atomic(u,false);IF r->>'reset'IS DISTINCT FROM 'true'THEN RAISE EXCEPTION 'C59S16_SETUP_REAL_RESET_FAILED';END IF;s:=c59s16_fixture.state(u);
 r:=public.materialize_mobile_workout_proposal(u,(x#>>'{admission,admissionID}')::uuid,(x->'input')||'{"duration_min":11}',x->'proposal',now()+interval '1 hour');
 IF r IS DISTINCT FROM '{"status":"forbidden","reason":"stale_epoch"}'::jsonb OR c59s16_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S16_STALE_MATERIALIZE_NOT_FIRST';END IF;
 r:=public.admit_mobile_workout_proposal(u,x->>'requestKey',(x->'input')||'{"duration_min":11}');
 IF r IS DISTINCT FROM '{"status":"forbidden","reason":"stale_epoch"}'::jsonb OR c59s16_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S16_STALE_ADMIT_NOT_FIRST';END IF;END LOOP;
 PERFORM c59s16_fixture.ok(true,'reset_before_materialize_and_bound_retry_stale_before_hash_or_pending');
END $stale$;
DO $collision$DECLARE p jsonb:=c59s16_fixture.seed(710,false);u uuid:=(p->>'ownerID')::uuid;pid uuid;r jsonb;s jsonb;j jsonb;BEGIN
 pid:=(public.replace_pending_registration_atomic(u,'{"kind":"meal","mealType":"jantar"}',now()+interval '1 hour',p->>'requestKey')->>'pending_id')::uuid;
 r:=public.materialize_mobile_workout_proposal(u,(p#>>'{admission,admissionID}')::uuid,p->'input',p->'proposal',(p->>'expiresAt')::timestamptz);
 SELECT to_jsonb(x)INTO j FROM private.mobile_workout_proposal_admissions x WHERE user_id=u;
 PERFORM c59s16_fixture.ok(r='{"status":"conflict","reason":"unproved_pending"}'::jsonb AND j->>'rejection_reason'='unproved_pending'AND j->'pending_id'='null'::jsonb AND j->'first_proposal_hash'='null'::jsonb AND j->'bound_at'='null'::jsonb
 AND EXISTS(SELECT 1 FROM ONLY public.pending_registrations WHERE id=pid AND proposal->>'kind'='meal'),'legacy_key_collision_refused_not_adopted');
 DELETE FROM public.pending_registrations WHERE id=pid;s:=c59s16_fixture.state(u);
 r:=public.materialize_mobile_workout_proposal(u,(p#>>'{admission,admissionID}')::uuid,p->'input',p->'proposal',now()+interval '1 hour');
 PERFORM c59s16_fixture.ok(r='{"status":"conflict","reason":"unproved_pending"}'::jsonb AND c59s16_fixture.state(u)=s,'removing_collision_never_reauthorizes_terminal_refusal');
 r:=public.admit_mobile_workout_proposal(u,p->>'requestKey',p->'input');
 PERFORM c59s16_fixture.ok(r=jsonb_build_object('status','reused','admission',p->'admission')AND c59s16_fixture.state(u)=s,'admit_retry_does_not_remint_refused_journal');
END $collision$;
DO $owner$DECLARE p jsonb:=c59s16_fixture.seed(711,false);u uuid:=(p->>'ownerID')::uuid;r jsonb;s jsonb;BEGIN
 UPDATE public.users SET status='blocked'WHERE id=u;s:=c59s16_fixture.state(u);
 r:=c59s16_fixture.attempt(format('SELECT public.admit_mobile_workout_proposal(%L::uuid,%L,%L::jsonb)',u,p->>'requestKey',p->'input'));
 PERFORM c59s16_fixture.ok(r='{"ok":false,"sqlstate":"P0002"}'::jsonb AND c59s16_fixture.attempt(format('SELECT public.materialize_mobile_workout_proposal(%L::uuid,%L::uuid,%L::jsonb,%L::jsonb,%L::timestamptz)',u,p#>>'{admission,admissionID}',p->'input',p->'proposal',p->>'expiresAt'))=r AND c59s16_fixture.state(u)=s,'inactive_owner_no_materialization');
 r:=c59s16_fixture.attempt(format('SELECT public.admit_mobile_workout_proposal(%L::uuid,%L,%L::jsonb)',c59s16_fixture.uid(730),'s16-owner-missing',p->'input'));
 PERFORM c59s16_fixture.ok(r='{"ok":false,"sqlstate":"P0002"}'::jsonb,'missing_owner_not_implicit_creation');
END $owner$;
DO $fault_seed$DECLARE p jsonb:=c59s16_fixture.seed(718,false);u uuid:=(p->>'ownerID')::uuid;v jsonb;BEGIN
 v:=public.replace_pending_registration_atomic(u,'{"kind":"meal","mealType":"jantar"}',now()+interval '1 hour','s16-old-before-fault');
 IF(SELECT count(*)FROM ONLY public.pending_registrations WHERE user_id=u AND status='pending')<>1 THEN RAISE EXCEPTION 'C59S16_SETUP_REAL_PENDING_REQUIRED';END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.pending_registrations'::regclass AND tgname='c59s16_materialize_fault')THEN RAISE EXCEPTION 'C59S16_SETUP_TRIGGER_COLLISION';END IF;
END $fault_seed$;
CREATE TRIGGER c59s16_materialize_fault BEFORE INSERT ON public.pending_registrations FOR EACH ROW EXECUTE FUNCTION c59s16_fixture.fail_after_cancel();
DO $fault$DECLARE u uuid:=c59s16_fixture.uid(718);a uuid;k text;s jsonb:=c59s16_fixture.state(u);ec text;em text;BEGIN
 SELECT admission_id,request_key INTO STRICT a,k FROM private.mobile_workout_proposal_admissions WHERE user_id=u;
 BEGIN PERFORM public.materialize_mobile_workout_proposal(u,a,c59s16_fixture.input(),c59s16_fixture.proposal(k,c59s16_fixture.input()),now()+interval '1 hour');EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS ec=RETURNED_SQLSTATE,em=MESSAGE_TEXT;END;
 PERFORM c59s16_fixture.ok(ec='P0001'AND em='C59S16_INJECTED_AFTER_REAL_CANCEL'AND c59s16_fixture.state(u)=s,'failure_before_insert_reverts_real_prior_cancel');
END $fault$;
DROP TRIGGER c59s16_materialize_fault ON public.pending_registrations;
DO $$BEGIN IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.mobile_workout_proposal_admissions'::regclass AND tgname='c59s16_bound_fault')THEN RAISE EXCEPTION 'C59S16_SETUP_BIND_TRIGGER_COLLISION';END IF;END$$;
CREATE TRIGGER c59s16_bound_fault AFTER UPDATE ON private.mobile_workout_proposal_admissions FOR EACH ROW EXECUTE FUNCTION c59s16_fixture.fail_after_bind();
DO $bind_fault$DECLARE u uuid:=c59s16_fixture.uid(718);a uuid;k text;s jsonb:=c59s16_fixture.state(u);ec text;em text;BEGIN
 SELECT admission_id,request_key INTO STRICT a,k FROM private.mobile_workout_proposal_admissions WHERE user_id=u;
 BEGIN PERFORM public.materialize_mobile_workout_proposal(u,a,c59s16_fixture.input(),c59s16_fixture.proposal(k,c59s16_fixture.input()),now()+interval '1 hour');EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS ec=RETURNED_SQLSTATE,em=MESSAGE_TEXT;END;
 PERFORM c59s16_fixture.ok(ec='P0001'AND em='C59S16_INJECTED_AFTER_INSERT_AND_BIND'AND c59s16_fixture.state(u)=s,'failure_after_real_insert_and_bind_reverts_all_three_effects');
END $bind_fault$;
DROP TRIGGER c59s16_bound_fault ON private.mobile_workout_proposal_admissions;
DO $delete$DECLARE p jsonb:=c59s16_fixture.seed(719,true);q jsonb:=c59s16_fixture.seed(720,true);u uuid:=(p->>'ownerID')::uuid;s jsonb:=c59s16_fixture.state((q->>'ownerID')::uuid);BEGIN
 DELETE FROM public.users WHERE id=u;
 PERFORM c59s16_fixture.ok(NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions WHERE user_id=u)AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=u)AND c59s16_fixture.state((q->>'ownerID')::uuid)=s,'hard_delete_journal_cascade_other_owner_preserved');
END $delete$;
DO $shared_fence$DECLARE u uuid:=c59s16_fixture.owner(721);flow jsonb;fence jsonb;r jsonb;BEGIN
 r:=public.admit_workout_strength_request(u,'s16-flow-before-UI',repeat('a',64));
 IF r->>'status'IS DISTINCT FROM 'admitted'THEN RAISE EXCEPTION 'C59S16_SETUP_REAL_FLOW_ADMISSION';END IF;
 SELECT to_jsonb(e)INTO fence FROM private.workout_strength_authority_epochs e WHERE user_id=u;
 SELECT to_jsonb(a)INTO flow FROM private.workout_strength_request_admissions a WHERE user_id=u;
 r:=public.admit_mobile_workout_proposal(u,'s16-UI-after-flow',c59s16_fixture.input());
 PERFORM c59s16_fixture.ok(r->>'status'='admitted'AND r#>>'{admission,epoch}'=fence->>'epoch'
 AND(SELECT to_jsonb(e)FROM private.workout_strength_authority_epochs e WHERE user_id=u)=fence
 AND(SELECT to_jsonb(a)FROM private.workout_strength_request_admissions a WHERE user_id=u)=flow,'UI_admit_reuses_existing_S15_fence_without_changing_Flow_admission');
END $shared_fence$;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
DO $guard$DECLARE r jsonb;BEGIN
 r:=c59s16_fixture.attempt('SELECT public.admit_mobile_workout_proposal(NULL,NULL,NULL)');
 PERFORM c59s16_fixture.ok(r='{"ok":false,"sqlstate":"42501"}'::jsonb AND c59s16_fixture.attempt('SELECT public.materialize_mobile_workout_proposal(NULL,NULL,NULL,NULL,NULL)')=r,'real_trusted_guard_precedes_null_shape');
END $guard$;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $no_X$BEGIN
 PERFORM c59s16_fixture.ok(NOT EXISTS(SELECT 1 FROM ONLY public.messages WHERE user_id IN(SELECT c59s16_fixture.uid(i)FROM generate_series(701,730)i))AND NOT EXISTS(SELECT 1 FROM ONLY public.workout_logs WHERE user_id IN(SELECT c59s16_fixture.uid(i)FROM generate_series(701,730)i))
 AND NOT EXISTS(SELECT 1 FROM ONLY public.daily_snapshots WHERE user_id IN(SELECT c59s16_fixture.uid(i)FROM generate_series(701,730)i))AND NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id IN(SELECT c59s16_fixture.uid(i)FROM generate_series(701,730)i)),'proposal_authority_never_creates_IN_life_workout_or_snapshot');
END $no_X$;
SELECT c59s16_fixture.object_fingerprint()AS after_fingerprint
\gset s16_
SELECT c59s16_fixture.ok(:'s16_after_fingerprint'::jsonb=:'s16_fingerprint'::jsonb,'no_product_schema_ACL_or_trigger_drift');
ROLLBACK;
\echo C59S16_ROLLBACK_CONFIRMED
\endif
\endif
