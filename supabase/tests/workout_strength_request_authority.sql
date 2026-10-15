\set ON_ERROR_STOP on
-- Real S15 entrypoints only. Their absence today is a SETUP gate, not a product RED.
DO $target$BEGIN IF session_user<>'c5_local_admin' OR current_database()<>'c5_reset_default_20261009'
 OR current_setting('port')<>'55489' OR current_setting('listen_addresses')<>''
 OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
 THEN RAISE EXCEPTION 'C59S15_SETUP_WRONG_LOCAL_TARGET';END IF;
 IF to_regprocedure('public.admit_workout_strength_request(uuid,text,text)') IS NULL OR to_regprocedure('public.initialize_workout_strength_lifecycle(uuid,uuid,uuid)') IS NULL
 THEN RAISE EXCEPTION 'C59S15_SETUP_ENTRYPOINT_ABSENT' USING ERRCODE='42883';END IF;
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
DO $$BEGIN RAISE EXCEPTION 'C59S15_SETUP_CONFLICTING_MODES';END$$;
\endif
\endif
\if :teardown_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $owned$DECLARE o record;r record;BEGIN
 SELECT * INTO STRICT o FROM c59s15_fixture.ownership WHERE tag='c59s15_authority_v1';
 IF o.owner_name<>session_user OR o.object_oids IS DISTINCT FROM c59s15_fixture.object_oids() OR o.object_fingerprint IS DISTINCT FROM c59s15_fixture.object_fingerprint()
 OR(SELECT count(*) FROM c59s15_fixture.ownership)<>1 OR(SELECT count(*) FROM c59s15_fixture.cases)<>9
 OR(SELECT array_agg(owner_id ORDER BY owner_id) FROM c59s15_fixture.cases) IS DISTINCT FROM ARRAY(SELECT c59s15_fixture.uid(i) FROM generate_series(501,509)i ORDER BY i)
 THEN RAISE EXCEPTION 'C59S15_TEARDOWN_OBJECT_DRIFT';END IF;
 IF c59s15_fixture.state(c59s15_fixture.uid(999)) IS DISTINCT FROM o.sentinel THEN RAISE EXCEPTION 'C59S15_TEARDOWN_SENTINEL_CHANGED';END IF;
 FOR r IN SELECT owner_id FROM c59s15_fixture.cases UNION ALL SELECT c59s15_fixture.uid(999) LOOP
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=r.owner_id AND wpp='155515'||lpad(right(r.owner_id::text,12)::int::text,7,'0') AND email='c59s15-'||right(r.owner_id::text,12)::int||'@example.invalid')
 THEN RAISE EXCEPTION 'C59S15_TEARDOWN_OWNER_DRIFT';END IF;
 DELETE FROM public.users WHERE id=r.owner_id;
 END LOOP;
END $owned$;
DROP FUNCTION c59s15_fixture.seed(integer,boolean,boolean);DROP FUNCTION c59s15_fixture.owner(integer);
DROP FUNCTION c59s15_fixture.inbound(uuid,text,text);DROP FUNCTION c59s15_fixture.hash(text);
DROP FUNCTION c59s15_fixture.admission_wire(jsonb,uuid,text,text,text);DROP FUNCTION c59s15_fixture.lifecycle_wire(jsonb,uuid,text);
DROP FUNCTION c59s15_fixture.fail_after_close();DROP FUNCTION c59s15_fixture.state(uuid);
DROP FUNCTION c59s15_fixture.object_fingerprint();DROP FUNCTION c59s15_fixture.object_oids();
DROP FUNCTION c59s15_fixture.uid(integer);DROP FUNCTION c59s15_fixture.attempt(text);DROP FUNCTION c59s15_fixture.ok(boolean,text);
DROP TABLE c59s15_fixture.cases;DROP TABLE c59s15_fixture.ownership;DROP SCHEMA c59s15_fixture;
COMMIT;
\echo C59S15_CONCURRENCY_TEARDOWN_CONFIRMED
\else
\if :setup_concurrency
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $rr$DECLARE s1 text;s2 text;BEGIN
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id='c59b5000-0000-0000-0000-000000000700'::uuid) THEN RAISE EXCEPTION 'C59S15_SETUP_RR_OWNER_COLLISION';END IF;
 BEGIN PERFORM public.admit_workout_strength_request('c59b5000-0000-0000-0000-000000000700'::uuid,'s15-rr-valid',repeat('a',64));EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s1=RETURNED_SQLSTATE;END;
 BEGIN PERFORM public.initialize_workout_strength_lifecycle('c59b5000-0000-0000-0000-000000000700'::uuid,'c59b5000-0000-0000-0000-000000000801'::uuid,'c59b5000-0000-0000-0000-000000000802'::uuid);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s2=RETURNED_SQLSTATE;END;
 IF s1 IS DISTINCT FROM '22023' OR s2 IS DISTINCT FROM '22023' THEN RAISE EXCEPTION 'C59S15_ASSERT:RC_guard_precedes_absent_owner';END IF;
 RAISE NOTICE 'C59S15_PASS:RC_guard_precedes_absent_owner';END $rr$;
ROLLBACK;
\endif
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO, YMD';
DO $preflight$BEGIN
 IF to_regnamespace('c59s15_fixture') IS NOT NULL THEN RAISE EXCEPTION 'C59S15_SETUP_FIXTURE_COLLISION';END IF;
 IF EXISTS(SELECT 1 FROM public.users WHERE id IN(SELECT ('c59b5000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(501,509)i UNION ALL SELECT ('c59b5000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(701,730)i UNION ALL SELECT 'c59b5000-0000-0000-0000-000000000999'::uuid)
 OR email IN(SELECT 'c59s15-'||i||'@example.invalid' FROM generate_series(501,509)i UNION ALL SELECT 'c59s15-'||i||'@example.invalid' FROM generate_series(701,730)i UNION ALL SELECT 'c59s15-999@example.invalid')
 OR wpp IN(SELECT '155515'||lpad(i::text,7,'0') FROM generate_series(501,509)i UNION ALL SELECT '155515'||lpad(i::text,7,'0') FROM generate_series(701,730)i UNION ALL SELECT '1555150000999')) THEN RAISE EXCEPTION 'C59S15_SETUP_OWNER_COLLISION';END IF;
END $preflight$;
\ir fixtures/workout_strength_request_authority_fixture.sql
\if :setup_concurrency
DO $seed$DECLARE i integer;p jsonb;q jsonb;t text:='C59S15 second request';k text:='s15-second-509';r jsonb;m uuid;ids text[]:=ARRAY['admission-reset-commit','admission-reset-rollback','reset-admission-commit','reset-admission-rollback','init-reset-commit','init-reset-rollback','reset-init-commit','reset-init-rollback','two-admissions-one-life'];BEGIN
 FOR i IN 501..509 LOOP
 p:=c59s15_fixture.seed(i,i>=503,false);
 IF i=509 THEN
 r:=public.admit_workout_strength_request((p->>'ownerID')::uuid,k,c59s15_fixture.hash(t));m:=c59s15_fixture.inbound((p->>'ownerID')::uuid,k,t);
 IF r->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S15_SETUP_SECOND_ADMISSION';END IF;
 q:=jsonb_build_object('ownerID',p->>'ownerID','requestKey',k,'requestHash',c59s15_fixture.hash(t),'content',t,'admission',r->'admission','inboundID',m::text);p:=p||jsonb_build_object('second',q);
 END IF;
 INSERT INTO c59s15_fixture.cases VALUES(ids[i-500],(p->>'ownerID')::uuid,p);
 END LOOP;
 PERFORM c59s15_fixture.seed(999,true,true);
END $seed$;
INSERT INTO c59s15_fixture.ownership VALUES('c59s15_authority_v1',session_user,c59s15_fixture.object_oids(),c59s15_fixture.object_fingerprint(),c59s15_fixture.state(c59s15_fixture.uid(999)));
COMMIT;
\echo C59S15_CONCURRENCY_SETUP_CONFIRMED
\else
SELECT c59s15_fixture.object_fingerprint() AS fingerprint
\gset s15_
DO $schema$DECLARE v boolean;BEGIN
SELECT count(*)=2 AND bool_and(c.relowner='postgres'::regrole AND c.relrowsecurity AND NOT c.relforcerowsecurity AND NOT EXISTS(SELECT 1 FROM pg_policy p WHERE p.polrelid=c.oid)
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner)))a WHERE a.grantee<>c.relowner)) INTO v
FROM pg_class c WHERE c.oid IN('private.workout_strength_authority_epochs'::regclass,'private.workout_strength_request_admissions'::regclass);
PERFORM c59s15_fixture.ok(v,'two_private_postgres_owned_RLS_owner_only_tables');
SELECT count(*)=2 AND bool_and(p.prosecdef AND p.proowner='postgres'::regrole AND p.proconfig=ARRAY['search_path=pg_catalog'] AND p.pronargdefaults=0
 AND has_function_privilege('service_role',p.oid,'EXECUTE') AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a WHERE a.privilege_type='EXECUTE' AND a.grantee NOT IN(p.proowner,'service_role'::regrole))) INTO v
FROM pg_proc p WHERE p.oid IN('public.admit_workout_strength_request(uuid,text,text)'::regprocedure,'public.initialize_workout_strength_lifecycle(uuid,uuid,uuid)'::regprocedure);
PERFORM c59s15_fixture.ok(v AND NOT has_function_privilege('anon','public.admit_workout_strength_request(uuid,text,text)','EXECUTE') AND NOT has_function_privilege('authenticated','public.initialize_workout_strength_lifecycle(uuid,uuid,uuid)','EXECUTE'),'two_RPCs_service_owner_only_definer_fixed_search_path');
END $schema$;
DO $replay$DECLARE u uuid:=c59s15_fixture.owner(701);k text:='s15-literal-701';t text:=E'C59S15 café 🏋️\nUnicode é';r jsonb;q jsonb;s jsonb;m uuid;lower_clock timestamptz;BEGIN
lower_clock:=clock_timestamp();r:=public.admit_workout_strength_request(u,k,'b2a8d9f243f7a71320f41f7dc465f82a89ccc396f0f8bd306ba93d050ff0ff84');
PERFORM c59s15_fixture.ok(c59s15_fixture.hash(t)='b2a8d9f243f7a71320f41f7dc465f82a89ccc396f0f8bd306ba93d050ff0ff84' AND c59s15_fixture.hash(t)<>'4e6400347b698feaccef2478d187c02102aec68756628e365e17c3bcad476888' AND c59s15_fixture.admission_wire(r,u,k,'b2a8d9f243f7a71320f41f7dc465f82a89ccc396f0f8bd306ba93d050ff0ff84','admitted'),'UTF8_text_literal_digest_not_JSON_or_normalized');
PERFORM c59s15_fixture.ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u) AND (SELECT current_lifecycle_key IS NULL FROM private.workout_strength_authority_epochs WHERE user_id=u)
 AND (SELECT admitted_at>=lower_clock AND admitted_at<=clock_timestamp() AND original_inbound_id IS NULL AND lifecycle_key IS NULL FROM private.workout_strength_request_admissions WHERE user_id=u),'admit_creates_fence_and_admission_without_lifecycle_post_lock_clock');
s:=c59s15_fixture.state(u);q:=public.admit_workout_strength_request(u,k,'b2a8d9f243f7a71320f41f7dc465f82a89ccc396f0f8bd306ba93d050ff0ff84');
PERFORM c59s15_fixture.ok(q=jsonb_build_object('status','reused','admission',r->'admission') AND c59s15_fixture.state(u)=s,'same_request_reuses_exact_receipt_no_mutation');
q:=public.admit_workout_strength_request(u,k,repeat('b',64));
PERFORM c59s15_fixture.ok(q='{"status":"conflict","reason":"request_content_conflict"}'::jsonb AND c59s15_fixture.state(u)=s,'changed_hash_conflicts_without_overwriting_original');
q:=public.admit_workout_strength_request(u,upper(k),'b2a8d9f243f7a71320f41f7dc465f82a89ccc396f0f8bd306ba93d050ff0ff84');
PERFORM c59s15_fixture.ok(q->>'status'='admitted' AND q#>>'{admission,admissionID}'<>r#>>'{admission,admissionID}' AND (SELECT count(*)=2 FROM private.workout_strength_request_admissions WHERE user_id=u),'request_keys_are_literal_case_sensitive');
m:=c59s15_fixture.inbound(u,k,t);q:=public.initialize_workout_strength_lifecycle(u,(r#>>'{admission,admissionID}')::uuid,m);
PERFORM c59s15_fixture.ok(c59s15_fixture.lifecycle_wire(q,u,'initialized'),'UTF8_decomposed_newline_content_matches_literal_digest_on_init');
END $replay$;
DO $invalid$DECLARE u uuid:=c59s15_fixture.owner(702);s jsonb:=c59s15_fixture.state(u);r jsonb;BEGIN
r:=c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',u,'short',repeat('a',64)));
PERFORM c59s15_fixture.ok(r='{"ok":false,"sqlstate":"22023"}'::jsonb AND c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',u,repeat('x',129),repeat('a',64)))=r
 AND c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',u,'s15 key 702',repeat('a',64)))=r
 AND c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',u,'s15-é-702',repeat('a',64)))=r
 AND c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',u,' s15-valid-702',repeat('a',64)))=r,'invalid_key_shape_bounds_ASCII_no_silent_trim');
PERFORM c59s15_fixture.ok(c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',u,'s15-valid-702',repeat('A',64)))=r
 AND c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',u,'s15-valid-702',repeat('a',63)))=r
 AND c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,NULL)',u,'s15-valid-702'))=r
 AND c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(NULL::uuid,%L,%L)','s15-valid-702',repeat('a',64)))=r
 AND c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,NULL,%L)',u,repeat('a',64)))=r
 AND c59s15_fixture.attempt(format('SELECT public.initialize_workout_strength_lifecycle(NULL::uuid,%L::uuid,%L::uuid)',c59s15_fixture.uid(1702),c59s15_fixture.uid(2702)))=r
 AND c59s15_fixture.attempt(format('SELECT public.initialize_workout_strength_lifecycle(%L::uuid,NULL::uuid,NULL::uuid)',u))=r AND c59s15_fixture.state(u)=s,'invalid_hash_NULL_inputs_no_authority_writes');
UPDATE public.users SET status='blocked' WHERE id=u;s:=c59s15_fixture.state(u);
r:=c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',u,'s15-valid-702',repeat('a',64)));
PERFORM c59s15_fixture.ok(r='{"ok":false,"sqlstate":"P0002"}'::jsonb AND c59s15_fixture.attempt(format('SELECT public.initialize_workout_strength_lifecycle(%L::uuid,%L::uuid,%L::uuid)',u,c59s15_fixture.uid(1702),c59s15_fixture.uid(2702)))=r AND c59s15_fixture.state(u)=s,'inactive_owner_denies_both_RPCs');
r:=c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',c59s15_fixture.uid(730),'s15-absent-730',repeat('a',64)));
PERFORM c59s15_fixture.ok(r='{"ok":false,"sqlstate":"P0002"}'::jsonb,'missing_owner_is_P0002');
END $invalid$;
DO $init$DECLARE p jsonb:=c59s15_fixture.seed(703);u uuid:=(p->>'ownerID')::uuid;r jsonb;q jsonb;s jsonb;lower_clock timestamptz;BEGIN
lower_clock:=clock_timestamp();r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(c59s15_fixture.lifecycle_wire(r,u,'initialized') AND (SELECT opened_at>=lower_clock AND opened_at<=clock_timestamp() FROM private.workout_strength_lifecycles WHERE user_id=u),'first_explicit_init_owned_lifecycle_DB_clock_exact_wire');
PERFORM c59s15_fixture.ok((SELECT e.current_lifecycle_key=(r#>>'{lifecycle,lifecycleKey}')::uuid AND a.lifecycle_key=e.current_lifecycle_key AND a.original_inbound_id=(p->>'inboundID')::uuid FROM private.workout_strength_authority_epochs e JOIN private.workout_strength_request_admissions a USING(user_id) WHERE e.user_id=u),'fence_and_admission_snapshots_bound_atomically');
s:=c59s15_fixture.state(u);q:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(q=jsonb_build_object('status','reused','lifecycle',r->'lifecycle') AND c59s15_fixture.state(u)=s,'init_retry_preserves_UUID_openedAt_and_all_state');
q:=public.admit_workout_strength_request(u,'s15-second-703',c59s15_fixture.hash('second'));p:=jsonb_build_object('admission',q->'admission','inboundID',c59s15_fixture.inbound(u,'s15-second-703','second'));
q:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(q=jsonb_build_object('status','initialized','lifecycle',r->'lifecycle') AND (SELECT count(*)=1 FROM private.workout_strength_lifecycles WHERE user_id=u),'first_binding_second_admission_initialized_same_current_lifecycle');
END $init$;
SAVEPOINT in_direction;
DO $in_direction$DECLARE p jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(704);u:=(p->>'ownerID')::uuid;UPDATE public.messages SET direction='out' WHERE id=(p->>'inboundID')::uuid;s:=c59s15_fixture.state(u);
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s,'inbound_direction_mismatch_no_bind');
END $in_direction$;
ROLLBACK TO SAVEPOINT in_direction;RELEASE SAVEPOINT in_direction;
SAVEPOINT in_role;
DO $in_role$DECLARE p jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(704);u:=(p->>'ownerID')::uuid;UPDATE public.messages SET role='assistant' WHERE id=(p->>'inboundID')::uuid;s:=c59s15_fixture.state(u);
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s,'inbound_role_mismatch_no_bind');
END $in_role$;
ROLLBACK TO SAVEPOINT in_role;RELEASE SAVEPOINT in_role;
SAVEPOINT in_provider;
DO $in_provider$DECLARE p jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(704);u:=(p->>'ownerID')::uuid;UPDATE public.messages SET provider='whatsapp' WHERE id=(p->>'inboundID')::uuid;s:=c59s15_fixture.state(u);
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s,'inbound_provider_mismatch_no_bind');
END $in_provider$;
ROLLBACK TO SAVEPOINT in_provider;RELEASE SAVEPOINT in_provider;
SAVEPOINT in_content_type;
DO $in_content_type$DECLARE p jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(704);u:=(p->>'ownerID')::uuid;UPDATE public.messages SET content_type='image' WHERE id=(p->>'inboundID')::uuid;s:=c59s15_fixture.state(u);
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s,'inbound_content_type_mismatch_no_bind');
END $in_content_type$;
ROLLBACK TO SAVEPOINT in_content_type;RELEASE SAVEPOINT in_content_type;
SAVEPOINT in_hash;
DO $in_hash$DECLARE p jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(704);u:=(p->>'ownerID')::uuid;UPDATE public.messages SET content='different content' WHERE id=(p->>'inboundID')::uuid;s:=c59s15_fixture.state(u);
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s,'inbound_hash_mismatch_no_bind');
END $in_hash$;
ROLLBACK TO SAVEPOINT in_hash;RELEASE SAVEPOINT in_hash;
SAVEPOINT in_NULL_content;
DO $in_NULL_content$DECLARE p jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(704);u:=(p->>'ownerID')::uuid;UPDATE public.messages SET content=NULL WHERE id=(p->>'inboundID')::uuid;s:=c59s15_fixture.state(u);
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s,'inbound_NULL_content_mismatch_no_bind');
END $in_NULL_content$;
ROLLBACK TO SAVEPOINT in_NULL_content;RELEASE SAVEPOINT in_NULL_content;
SAVEPOINT in_bare_provider;
DO $in_bare_provider$DECLARE p jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(704);u:=(p->>'ownerID')::uuid;UPDATE public.messages SET provider_message_id='s15-request-704' WHERE id=(p->>'inboundID')::uuid;s:=c59s15_fixture.state(u);
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s,'inbound_bare_provider_mismatch_no_bind');
END $in_bare_provider$;
ROLLBACK TO SAVEPOINT in_bare_provider;RELEASE SAVEPOINT in_bare_provider;
DO $foreign$DECLARE p jsonb:=c59s15_fixture.seed(705);q jsonb:=c59s15_fixture.seed(706);u uuid:=(p->>'ownerID')::uuid;r jsonb;s jsonb:=c59s15_fixture.state(u);other_state jsonb:=c59s15_fixture.state((q->>'ownerID')::uuid);m uuid;BEGIN
r:=public.initialize_workout_strength_lifecycle(u,(q#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND c59s15_fixture.state(u)=s AND c59s15_fixture.state((q->>'ownerID')::uuid)=other_state,'foreign_admission_is_invalid_owned_lookup');
r:=public.initialize_workout_strength_lifecycle(u,c59s15_fixture.uid(1705),(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"invalid_admission"}'::jsonb AND c59s15_fixture.state(u)=s,'missing_admission_is_invalid');
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(q->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s AND c59s15_fixture.state((q->>'ownerID')::uuid)=other_state,'foreign_inbound_no_adoption');
m:=c59s15_fixture.inbound(u,'s15-other-705',p->>'content');s:=c59s15_fixture.state(u);
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,m);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s,'same_owner_other_request_inbound_is_not_authority');
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);DELETE FROM public.messages WHERE id=(p->>'inboundID')::uuid;m:=c59s15_fixture.inbound(u,p->>'requestKey',p->>'content');s:=c59s15_fixture.state(u);
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,m);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"inbound_mismatch"}'::jsonb AND c59s15_fixture.state(u)=s,'bound_inbound_UUID_never_replaced_by_new_identical_message');
END $foreign$;
DO $stale$DECLARE p jsonb:=c59s15_fixture.seed(707);u uuid:=(p->>'ownerID')::uuid;r jsonb;e uuid;d jsonb;m uuid;BEGIN
SELECT to_jsonb(a) INTO STRICT d FROM private.workout_strength_request_admissions a WHERE user_id=u;e:=(p#>>'{admission,epoch}')::uuid;
r:=public.reset_user_conversation_atomic(u,true);
PERFORM c59s15_fixture.ok(r->>'reset'='true' AND (SELECT epoch<>e AND current_lifecycle_key IS NULL FROM private.workout_strength_authority_epochs WHERE user_id=u)
 AND NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.messages WHERE user_id=u)
 AND (SELECT to_jsonb(a) FROM private.workout_strength_request_admissions a WHERE user_id=u)=d,'reset_without_lifecycle_advances_epoch_keeps_admission_tombstone');
r:=public.admit_workout_strength_request(u,p->>'requestKey',p->>'requestHash');
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"stale_epoch"}'::jsonb AND NOT EXISTS(SELECT 1 FROM public.messages WHERE user_id=u),'same_key_after_reset_denied_before_new_inbound');
r:=public.admit_workout_strength_request(u,p->>'requestKey',repeat('b',64));
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"stale_epoch"}'::jsonb,'stale_epoch_precedes_changed_hash_conflict');
m:=c59s15_fixture.inbound(u,p->>'requestKey',p->>'content');r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,m);
PERFORM c59s15_fixture.ok(m<>(p->>'inboundID')::uuid AND r='{"status":"forbidden","reason":"stale_epoch"}'::jsonb AND NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u)
 AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u) AND (SELECT to_jsonb(a) FROM private.workout_strength_request_admissions a WHERE user_id=u)=d,'late_inserted_new_UUID_same_key_never_reauthorizes_X');
END $stale$;
SAVEPOINT pointer_orphan;
DO $pointer_orphan$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(708);u:=(p->>'ownerID')::uuid;INSERT INTO private.workout_strength_lifecycles VALUES(u,c59s15_fixture.uid(1708),clock_timestamp(),NULL,NULL);s:=c59s15_fixture.state(u);r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb AND c59s15_fixture.state(u)=s,'unbound_fence_orphan_negative_exact_no_adoption');
END $pointer_orphan$;
ROLLBACK TO SAVEPOINT pointer_orphan;RELEASE SAVEPOINT pointer_orphan;
SAVEPOINT pointer_missing;
DO $pointer_missing$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(708);u:=(p->>'ownerID')::uuid;UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=c59s15_fixture.uid(1708) WHERE user_id=u;s:=c59s15_fixture.state(u);r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb AND c59s15_fixture.state(u)=s,'unbound_fence_missing_negative_exact_no_adoption');
END $pointer_missing$;
ROLLBACK TO SAVEPOINT pointer_missing;RELEASE SAVEPOINT pointer_missing;
SAVEPOINT pointer_foreign;
DO $pointer_foreign$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(708);u:=(p->>'ownerID')::uuid;q:=c59s15_fixture.seed(709,true,true);UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=(q#>>'{lifecycle,lifecycleKey}')::uuid WHERE user_id=u;s:=c59s15_fixture.state(u);r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb AND c59s15_fixture.state(u)=s,'unbound_fence_foreign_negative_exact_no_adoption');
END $pointer_foreign$;
ROLLBACK TO SAVEPOINT pointer_foreign;RELEASE SAVEPOINT pointer_foreign;
SAVEPOINT pointer_closed;
DO $pointer_closed$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(708);u:=(p->>'ownerID')::uuid;INSERT INTO private.workout_strength_lifecycles VALUES(u,c59s15_fixture.uid(1708),clock_timestamp()-interval '1 hour',clock_timestamp(),'s15-storage-closed');UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=c59s15_fixture.uid(1708) WHERE user_id=u;s:=c59s15_fixture.state(u);r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb AND c59s15_fixture.state(u)=s,'unbound_fence_closed_negative_exact_no_adoption');
END $pointer_closed$;
ROLLBACK TO SAVEPOINT pointer_closed;RELEASE SAVEPOINT pointer_closed;
SAVEPOINT bound_null;
DO $bound_null$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(710,true,true);u:=(p->>'ownerID')::uuid;UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=NULL WHERE user_id=u;s:=c59s15_fixture.state(u);r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb AND c59s15_fixture.state(u)=s,'bound_lifecycle_null_negative_exact_no_rebind');
END $bound_null$;
ROLLBACK TO SAVEPOINT bound_null;RELEASE SAVEPOINT bound_null;
SAVEPOINT bound_different;
DO $bound_different$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(710,true,true);u:=(p->>'ownerID')::uuid;UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=c59s15_fixture.uid(1710) WHERE user_id=u;s:=c59s15_fixture.state(u);r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb AND c59s15_fixture.state(u)=s,'bound_lifecycle_different_negative_exact_no_rebind');
END $bound_different$;
ROLLBACK TO SAVEPOINT bound_different;RELEASE SAVEPOINT bound_different;
SAVEPOINT bound_missing;
DO $bound_missing$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(710,true,true);u:=(p->>'ownerID')::uuid;UPDATE private.workout_strength_request_admissions SET lifecycle_key=c59s15_fixture.uid(1710) WHERE user_id=u;s:=c59s15_fixture.state(u);r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb AND c59s15_fixture.state(u)=s,'bound_lifecycle_missing_negative_exact_no_rebind');
END $bound_missing$;
ROLLBACK TO SAVEPOINT bound_missing;RELEASE SAVEPOINT bound_missing;
SAVEPOINT bound_foreign;
DO $bound_foreign$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(710,true,true);u:=(p->>'ownerID')::uuid;UPDATE private.workout_strength_request_admissions SET lifecycle_key=c59s15_fixture.uid(1710) WHERE user_id=u;q:=c59s15_fixture.seed(711,true,true);UPDATE private.workout_strength_request_admissions SET lifecycle_key=(q#>>'{lifecycle,lifecycleKey}')::uuid WHERE user_id=u;s:=c59s15_fixture.state(u);r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"unproved_lifecycle"}'::jsonb AND c59s15_fixture.state(u)=s,'bound_lifecycle_foreign_negative_exact_no_rebind');
END $bound_foreign$;
ROLLBACK TO SAVEPOINT bound_foreign;RELEASE SAVEPOINT bound_foreign;
SAVEPOINT bound_closed;
DO $bound_closed$DECLARE p jsonb;q jsonb;u uuid;r jsonb;s jsonb;BEGIN
p:=c59s15_fixture.seed(710,true,true);u:=(p->>'ownerID')::uuid;UPDATE private.workout_strength_lifecycles SET closed_at=clock_timestamp(),close_operation_key='s15-storage-closed' WHERE user_id=u;s:=c59s15_fixture.state(u);r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(p->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb AND c59s15_fixture.state(u)=s,'bound_lifecycle_closed_negative_exact_no_rebind');
END $bound_closed$;
ROLLBACK TO SAVEPOINT bound_closed;RELEASE SAVEPOINT bound_closed;
DO $epoch_before_live$DECLARE p jsonb:=c59s15_fixture.seed(712,true,true);u uuid:=(p->>'ownerID')::uuid;q jsonb;r jsonb;s jsonb;BEGIN
PERFORM public.reset_user_conversation_atomic(u,false);r:=public.admit_workout_strength_request(u,'s15-new-712',c59s15_fixture.hash('new'));q:=jsonb_build_object('admission',r->'admission','inboundID',c59s15_fixture.inbound(u,'s15-new-712','new'));
r:=public.initialize_workout_strength_lifecycle(u,(q#>>'{admission,admissionID}')::uuid,(q->>'inboundID')::uuid);s:=c59s15_fixture.state(u);
PERFORM c59s15_fixture.ok(r->>'status'='initialized' AND r#>>'{lifecycle,lifecycleKey}'<>p#>>'{lifecycle,lifecycleKey}','new_authorized_request_new_epoch_different_lifecycle');
r:=public.initialize_workout_strength_lifecycle(u,(p#>>'{admission,admissionID}')::uuid,(q->>'inboundID')::uuid);
PERFORM c59s15_fixture.ok(r='{"status":"forbidden","reason":"stale_epoch"}'::jsonb AND c59s15_fixture.state(u)=s,'old_epoch_precedes_live_new_lifecycle_and_inbound_mismatch');
END $epoch_before_live$;
DO $storage$DECLARE p jsonb:=c59s15_fixture.seed(713);u uuid:=(p->>'ownerID')::uuid;r jsonb;s jsonb:=c59s15_fixture.state(u);BEGIN
r:=c59s15_fixture.attempt(format('UPDATE private.workout_strength_request_admissions SET original_inbound_id=%L::uuid WHERE user_id=%L::uuid RETURNING to_jsonb(workout_strength_request_admissions)',p->>'inboundID',u));
PERFORM c59s15_fixture.ok(r='{"ok":false,"sqlstate":"23514"}'::jsonb AND c59s15_fixture.state(u)=s,'snapshot_pair_constraint_no_half_binding');
r:=c59s15_fixture.attempt(format('UPDATE private.workout_strength_authority_epochs SET changed_at=''infinity''::timestamptz WHERE user_id=%L::uuid RETURNING to_jsonb(workout_strength_authority_epochs)',u));
PERFORM c59s15_fixture.ok(r='{"ok":false,"sqlstate":"23514"}'::jsonb AND c59s15_fixture.state(u)=s,'epoch_clock_must_be_finite');
r:=c59s15_fixture.attempt(format('UPDATE private.workout_strength_request_admissions SET admitted_at=''infinity''::timestamptz WHERE user_id=%L::uuid RETURNING to_jsonb(workout_strength_request_admissions)',u));
PERFORM c59s15_fixture.ok(r='{"ok":false,"sqlstate":"23514"}'::jsonb AND c59s15_fixture.state(u)=s,'admission_clock_must_be_finite');
END $storage$;
DO $reset_variants$DECLARE p jsonb;q jsonb;u uuid;r jsonb;e uuid;d jsonb;i integer;BEGIN
FOR i IN 714..716 LOOP
 p:=c59s15_fixture.seed(i,true,true);u:=(p->>'ownerID')::uuid;e:=(p#>>'{admission,epoch}')::uuid;SELECT to_jsonb(a) INTO d FROM private.workout_strength_request_admissions a WHERE user_id=u;
 IF i=714 THEN r:=public.reset_user_conversation_atomic(u,true);ELSIF i=715 THEN r:=public.reset_user_conversation_atomic(u,false);ELSE r:=public.reset_user_conversation_atomic(u);END IF;
 IF r->>'reset' IS DISTINCT FROM 'true' OR(SELECT epoch<>e AND current_lifecycle_key IS NULL FROM private.workout_strength_authority_epochs WHERE user_id=u)IS DISTINCT FROM true
 OR(SELECT closed_at IS NOT NULL FROM private.workout_strength_lifecycles WHERE user_id=u)IS DISTINCT FROM true OR(SELECT to_jsonb(a) FROM private.workout_strength_request_admissions a WHERE user_id=u)IS DISTINCT FROM d
 THEN RAISE EXCEPTION 'C59S15_RESET_VARIANT_FAILED:%',i;END IF;
 END LOOP;
PERFORM c59s15_fixture.ok(true,'both_keepPlans_and_wrapper_advance_epoch_close_keep_admission');
u:=c59s15_fixture.owner(717);r:=public.reset_user_conversation_atomic(u,false);
PERFORM c59s15_fixture.ok(r->>'reset'='true' AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=u),'reset_never_registered_owner_does_not_create_fence');
END $reset_variants$;
DO $fault_seed$DECLARE p jsonb;u uuid;BEGIN p:=c59s15_fixture.seed(718,true,true);u:=(p->>'ownerID')::uuid;
 INSERT INTO public.pending_registrations(user_id,proposal,proposal_msg_id,expires_at) VALUES(u,'{"kind":"meal","mealType":"jantar"}',(p->>'inboundID')::uuid,clock_timestamp()+interval '1 hour');
 IF(SELECT count(*) FROM ONLY public.pending_registrations WHERE user_id=u)<>1 THEN RAISE EXCEPTION 'C59S15_SETUP_REAL_EARLY_DELETE_REQUIRED';END IF;
END $fault_seed$;
DO $$BEGIN IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.messages'::regclass AND tgname='c59s15_after_epoch_fault') THEN RAISE EXCEPTION 'C59S15_SETUP_TRIGGER_COLLISION';END IF;END$$;
CREATE TRIGGER c59s15_after_epoch_fault BEFORE DELETE ON public.messages FOR EACH ROW EXECUTE FUNCTION c59s15_fixture.fail_after_close();
DO $fault$DECLARE u uuid:=c59s15_fixture.uid(718);s jsonb:=c59s15_fixture.state(u);ec text;em text;BEGIN
BEGIN PERFORM public.reset_user_conversation_atomic(u,false);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS ec=RETURNED_SQLSTATE,em=MESSAGE_TEXT;END;
PERFORM c59s15_fixture.ok(ec='P0001' AND em='C59S15_INJECTED_AFTER_EPOCH_AND_CLOSE' AND c59s15_fixture.state(u)=s,'failure_after_epoch_close_and_deletes_reverts_whole_reset');
END $fault$;
DROP TRIGGER c59s15_after_epoch_fault ON public.messages;
DO $delete$DECLARE p jsonb:=c59s15_fixture.seed(719,true,true);q jsonb:=c59s15_fixture.seed(720,true,true);u uuid:=(p->>'ownerID')::uuid;s jsonb:=c59s15_fixture.state((q->>'ownerID')::uuid);BEGIN
DELETE FROM public.users WHERE id=u;
PERFORM c59s15_fixture.ok(NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.workout_strength_request_admissions WHERE user_id=u)
 AND NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u) AND c59s15_fixture.state((q->>'ownerID')::uuid)=s,'hard_delete_owned_cascades_preserves_other_owner');
END $delete$;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
DO $guard$DECLARE r jsonb;BEGIN
r:=c59s15_fixture.attempt(format('SELECT public.admit_workout_strength_request(%L::uuid,%L,%L)',c59s15_fixture.uid(720),'s15-guard-valid',repeat('a',64)));
PERFORM c59s15_fixture.ok(r='{"ok":false,"sqlstate":"42501"}'::jsonb AND c59s15_fixture.attempt(format('SELECT public.initialize_workout_strength_lifecycle(%L::uuid,%L::uuid,%L::uuid)',c59s15_fixture.uid(720),c59s15_fixture.uid(1720),c59s15_fixture.uid(2720)))=r,'real_trusted_guard_rejects_authenticated_claim');
END $guard$;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT c59s15_fixture.object_fingerprint() AS after_fingerprint
\gset s15_
SELECT c59s15_fixture.ok(:'s15_after_fingerprint'::jsonb=:'s15_fingerprint'::jsonb,'no_product_schema_ACL_or_trigger_drift');
ROLLBACK;
\echo C59S15_ROLLBACK_CONFIRMED
\endif
\endif
