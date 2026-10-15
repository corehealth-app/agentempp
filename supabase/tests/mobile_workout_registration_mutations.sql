\set ON_ERROR_STOP on
-- PRIVATE TEST-FIRST SOURCE. Dormant API missing = feature RED, not preexisting bug.
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
SELECT (:'prepare_fixture')::boolean::integer+(:'setup_concurrency')::boolean::integer+(:'teardown_concurrency')::boolean::integer+(:'dry_cleanup_baseline')::boolean::integer<=1 AS one_mode
\gset s17c_
\if :s17c_one_mode
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17C_SETUP_CONFLICTING_MODES';END$$;
\endif
DO $target$BEGIN
 IF session_user<>'c5_local_admin'OR current_database()<>'c5_reset_default_20261009'OR current_setting('port')<>'55489'OR current_setting('listen_addresses')<>''OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'THEN RAISE EXCEPTION 'C59S17C_SETUP_WRONG_LOCAL_TARGET';END IF;
 IF to_regprocedure('public.admit_mobile_workout_registration(uuid,text,jsonb)')IS NULL OR to_regprocedure('public.materialize_mobile_workout_registration(uuid,uuid,jsonb,jsonb,timestamp with time zone)')IS NULL OR to_regclass('private.mobile_workout_registration_edit_receipts')IS NULL THEN RAISE EXCEPTION 'C59S17C_SETUP_REAL_S17B_ABSENT';END IF;
END $target$;
\if :prepare_fixture
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='60s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $clean$BEGIN
 IF to_regnamespace('c59s17c_fixture')IS NOT NULL THEN RAISE EXCEPTION 'C59S17C_SETUP_SCHEMA_COLLISION';END IF;
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id IN(SELECT('c59c7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(1701,1816)i UNION ALL SELECT 'c59c7000-0000-0000-0000-000000001999'::uuid)
 OR email IN(SELECT 'c59s17c-'||i||'@example.invalid'FROM generate_series(1701,1816)i UNION ALL SELECT 'c59s17c-1999@example.invalid')OR wpp IN(SELECT '155518'||lpad(i::text,7,'0')FROM generate_series(1701,1816)i UNION ALL SELECT '1555180001999'))THEN RAISE EXCEPTION 'C59S17C_SETUP_OWNER_COLLISION';END IF;
END $clean$;
\ir fixtures/mobile_workout_registration_mutations_fixture.sql
DO $prepare$DECLARE p jsonb;BEGIN
 p:=c59s17c_fixture.ui(1999);p:=p||jsonb_build_object('initialState',c59s17c_fixture.state(c59s17c_fixture.uid(1999)));
 INSERT INTO c59s17c_fixture.cases VALUES('sentinel',c59s17c_fixture.uid(1999),p);
 INSERT INTO c59s17c_fixture.ownership VALUES('c59s17c_edit_cancel_v1',session_user,c59s17c_fixture.fingerprint());
END $prepare$;
COMMIT;
\echo C59S17C_FIXTURE_PREPARED
\else
DO $owned$DECLARE o record;BEGIN
 SELECT * INTO STRICT o FROM c59s17c_fixture.ownership WHERE tag='c59s17c_edit_cancel_v1';
 IF o.owner_name<>session_user OR o.fixture_fingerprint IS DISTINCT FROM c59s17c_fixture.fingerprint()OR(SELECT count(*)FROM c59s17c_fixture.ownership)<>1 THEN RAISE EXCEPTION 'C59S17C_SETUP_FIXTURE_DRIFT';END IF;
END $owned$;
\if :teardown_concurrency
\set cleanup true
\else
\set cleanup :dry_cleanup_baseline
\endif
\if :cleanup
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='60s';SET LOCAL lock_timeout='10s';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $cleanup$DECLARE c record;n integer;u uuid;s jsonb;initial jsonb;j jsonb;oldj jsonb;p jsonb;oldp jsonb;e jsonb;ids text[]:=ARRAY['edit-edit-commit','edit-edit-rollback','edit-cancel-commit','edit-cancel-rollback','cancel-edit-commit','cancel-edit-rollback','legacy-terminal-edit-commit','legacy-terminal-edit-rollback','legacy-terminal-cancel-commit','legacy-terminal-cancel-rollback','expiry-edit-after-rowlock','expiry-cancel-after-rowlock','reset-edit-commit','reset-edit-rollback','delete-pending-edit-commit','delete-pending-edit-rollback'];BEGIN
 IF(SELECT count(*)FROM c59s17c_fixture.cases)NOT IN(1,17)OR NOT EXISTS(SELECT 1 FROM c59s17c_fixture.cases WHERE case_id='sentinel'AND owner_id=c59s17c_fixture.uid(1999))THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_CASESET';END IF;
 IF EXISTS(SELECT 1 FROM c59s17c_fixture.cases WHERE case_id<>'sentinel'AND NOT(case_id=ANY(ids)))THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_CASESET';END IF;
 IF(SELECT count(*)FROM c59s17c_fixture.cases)=17 AND(SELECT count(*)FROM c59s17c_fixture.cases WHERE case_id=ANY(ids))<>16 THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_CASESET';END IF;
 -- Validate ALL scope/identities/reachable deltas before any DELETE. Failed AB may leave a partial known result.
 FOR c IN SELECT * FROM c59s17c_fixture.cases ORDER BY owner_id LOOP
 n:=CASE WHEN c.case_id='sentinel'THEN 1999 ELSE 1800+array_position(ids,c.case_id)END;u:=c59s17c_fixture.uid(n);s:=c59s17c_fixture.state(u);initial:=c.payload->'initialState';
 IF c.owner_id IS DISTINCT FROM u OR c.payload->>'ownerID'IS DISTINCT FROM u::text OR c.payload->>'requestKey'IS DISTINCT FROM c59s17c_fixture.key(n)
 OR c.payload->'input'IS DISTINCT FROM c59s17c_fixture.input()OR initial IS NULL
 OR NOT EXISTS(SELECT 1 FROM ONLY public.users WHERE id=u AND email='c59s17c-'||n||'@example.invalid'AND wpp='155518'||lpad(n::text,7,'0'))
 OR initial#>>'{user,name}'IS DISTINCT FROM 'C59S17C synthetic'OR initial#>'{user,metadata}'IS DISTINCT FROM '{"c59s17c_fixture":"c59s17c_edit_cancel_v1"}'::jsonb THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_OWNER_SCOPE';END IF;
 IF c.case_id='sentinel'THEN IF s IS DISTINCT FROM initial THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_SENTINEL_DRIFT';END IF;
 ELSE
 IF c.payload->>'editKeyA'IS DISTINCT FROM c59s17c_fixture.edit_key(n+1000)OR c.payload->>'editKeyB'IS DISTINCT FROM c59s17c_fixture.edit_key(n+2000)
 OR c.payload->'editInputA'IS DISTINCT FROM c59s17c_fixture.input(45)OR c.payload->'editInputB'IS DISTINCT FROM c59s17c_fixture.input(50)
 OR c.payload->'editProposalA'IS DISTINCT FROM c59s17c_fixture.proposal(c59s17c_fixture.edit_key(n+1000),c59s17c_fixture.input(45),450)
 OR c.payload->'editProposalB'IS DISTINCT FROM c59s17c_fixture.proposal(c59s17c_fixture.edit_key(n+2000),c59s17c_fixture.input(50),500)THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_PAYLOAD_SCOPE';END IF;
 IF jsonb_array_length(s->'private.mobile_workout_proposal_admissions')<>1 OR jsonb_array_length(s->'public.pending_registrations')>1 OR jsonb_array_length(s->'private.mobile_workout_registration_edit_receipts')>1 THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_MEMBERSHIP_CARDINALITY';END IF;
 j:=s#>'{private.mobile_workout_proposal_admissions,0}';oldj:=initial#>'{private.mobile_workout_proposal_admissions,0}';
 IF j-'content_revision'IS DISTINCT FROM oldj-'content_revision'OR(j->>'content_revision')::integer NOT IN(0,1)THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_ADMISSION_DRIFT';END IF;
 e:=s#>'{private.mobile_workout_registration_edit_receipts,0}';
 IF(j->>'content_revision')::integer=0 THEN IF e IS NOT NULL THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_UNEXPECTED_RECEIPT';END IF;
 ELSE IF e IS DISTINCT FROM jsonb_build_object('user_id',u,'admission_id',j->'admission_id','request_key',c.payload->'editKeyA','input_hash',c.payload->'inputHashA','expected_revision',0,'result_revision',1)
 AND e IS DISTINCT FROM jsonb_build_object('user_id',u,'admission_id',j->'admission_id','request_key',c.payload->'editKeyB','input_hash',c.payload->'inputHashB','expected_revision',0,'result_revision',1)THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_RECEIPT_DRIFT';END IF;END IF;
 p:=s#>'{public.pending_registrations,0}';oldp:=initial#>'{public.pending_registrations,0}';
 IF p IS NULL THEN IF c.case_id NOT IN('reset-edit-commit','delete-pending-edit-commit')THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_MISSING_PENDING';END IF;
 ELSE
 IF p-ARRAY['status','resolved_at','proposal','expires_at']IS DISTINCT FROM oldp-ARRAY['status','resolved_at','proposal','expires_at']OR p->>'status'NOT IN('pending','cancelled','expired')OR NOT isfinite((p->>'expires_at')::timestamptz)OR(p->>'status'<>'pending'AND(p->>'resolved_at'IS NULL OR NOT isfinite((p->>'resolved_at')::timestamptz)))THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_PENDING_SHAPE_DRIFT';END IF;
 IF(j->>'content_revision')::integer=0 AND p->'proposal'IS DISTINCT FROM oldp->'proposal'THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_UNEDITED_PROPOSAL';END IF;
 IF(j->>'content_revision')::integer=1 AND p->'proposal'IS DISTINCT FROM(CASE WHEN e->>'request_key'=c.payload->>'editKeyA'THEN c.payload->'editProposalA'ELSE c.payload->'editProposalB'END)THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_EDITED_PROPOSAL';END IF;
 END IF;
 IF c.case_id='reset-edit-commit'AND p IS NULL THEN
 -- Exact reachable effects from the closed REAL reset source, not a broad cleanup bypass.
 IF s->'user'IS DISTINCT FROM(initial->'user')||jsonb_build_object('name',NULL,'flow_phrase_cursor_revision',0,'summary',NULL,'summary_updated_at',NULL,'tags','[]'::jsonb,'admin_notes',NULL,'country_confirmed',false,'last_active_at',NULL,'metadata','{}'::jsonb,'updated_at',s#>'{user,updated_at}')
 OR jsonb_array_length(s->'public.user_profiles')<>1
 OR s#>'{public.user_profiles,0}'IS DISTINCT FROM(initial#>'{public.user_profiles,0}')||jsonb_build_object('weight_kg',NULL,'weight_measured_at',NULL,'weight_instant_source',NULL,'onboarding_completed',false,'onboarding_step',0,'updated_at',s#>'{public.user_profiles,0,updated_at}')
 OR jsonb_array_length(s->'public.user_progress')<>1
 OR s#>'{public.user_progress,0}'IS DISTINCT FROM jsonb_build_object('user_id',u,'xp_total',0,'level',1,'current_streak',0,'longest_streak',0,'blocks_completed',0,'deficit_block',0,'current_weight',NULL,'current_bf_percent',NULL,'badges_earned','[]'::jsonb,'last_active_date',NULL,'next_reevaluation',NULL,'updated_at',s#>'{public.user_progress,0,updated_at}')
 OR jsonb_array_length(s->'private.workout_strength_authority_epochs')<>1
 OR s#>>'{private.workout_strength_authority_epochs,0,epoch}'IS NOT DISTINCT FROM initial#>>'{private.workout_strength_authority_epochs,0,epoch}'
 OR s#>'{private.workout_strength_authority_epochs,0}'IS DISTINCT FROM(initial#>'{private.workout_strength_authority_epochs,0}')||jsonb_build_object('epoch',s#>'{private.workout_strength_authority_epochs,0,epoch}','changed_at',s#>'{private.workout_strength_authority_epochs,0,changed_at}','current_lifecycle_key',NULL)
 THEN RAISE EXCEPTION 'C59S17C_TEARDOWN_RESET_UNEXPECTED_DELTA';END IF;
 PERFORM c59s17c_fixture.assert_unchanged_except(initial,s,ARRAY['user','public.user_profiles','public.user_progress','private.workout_strength_authority_epochs','public.pending_registrations'],'teardown_real_reset_reachable');
 ELSE PERFORM c59s17c_fixture.assert_unchanged_except(initial,s,ARRAY['public.pending_registrations','private.mobile_workout_proposal_admissions','private.mobile_workout_registration_edit_receipts'],'teardown_reachable');END IF;
 END IF;END LOOP;
 -- All known fixtures have been validated. Never delete by prefix/range.
 FOR u IN SELECT owner_id FROM c59s17c_fixture.cases LOOP DELETE FROM public.users WHERE id=u;END LOOP;
END $cleanup$;
DO $drop_helpers$DECLARE f record;BEGIN FOR f IN SELECT oid FROM pg_proc WHERE pronamespace='c59s17c_fixture'::regnamespace ORDER BY oid LOOP EXECUTE format('DROP FUNCTION %s',f.oid::regprocedure);END LOOP;END $drop_helpers$;
DROP TABLE c59s17c_fixture.cases,c59s17c_fixture.ownership;DROP SCHEMA c59s17c_fixture;
\if :dry_cleanup_baseline
\if :{?dry_fingerprint_path}
\i :dry_fingerprint_path
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17C_SETUP_DRY_FINGERPRINT_PATH_REQUIRED';END$$;
\endif
ROLLBACK;
\echo C59S17C_DRY_CLEAN_BASELINE_ROLLBACK_CONFIRMED
\else
COMMIT;
\echo C59S17C_CONCURRENCY_TEARDOWN_CONFIRMED
\endif
\else
\if :setup_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='60s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $cases$DECLARE ids text[]:=ARRAY['edit-edit-commit','edit-edit-rollback','edit-cancel-commit','edit-cancel-rollback','cancel-edit-commit','cancel-edit-rollback','legacy-terminal-edit-commit','legacy-terminal-edit-rollback','legacy-terminal-cancel-commit','legacy-terminal-cancel-rollback','expiry-edit-after-rowlock','expiry-cancel-after-rowlock','reset-edit-commit','reset-edit-rollback','delete-pending-edit-commit','delete-pending-edit-rollback'];i integer;u uuid;p jsonb;v jsonb:=c59s17c_fixture.input(45);w jsonb:=c59s17c_fixture.input(50);BEGIN
 IF(SELECT array_agg(case_id)FROM c59s17c_fixture.cases)IS DISTINCT FROM ARRAY['sentinel']THEN RAISE EXCEPTION 'C59S17C_SETUP_CASES_COLLISION';END IF;
 FOR i IN 1801..1816 LOOP p:=c59s17c_fixture.ui(i);u:=(p->>'ownerID')::uuid;
 p:=p||jsonb_build_object('editKeyA',c59s17c_fixture.edit_key(i+1000),'editKeyB',c59s17c_fixture.edit_key(i+2000),'editInputA',v,'editInputB',w,
 'editProposalA',c59s17c_fixture.proposal(c59s17c_fixture.edit_key(i+1000),v,450),'editProposalB',c59s17c_fixture.proposal(c59s17c_fixture.edit_key(i+2000),w,500),
 'inputHashA',private.mobile_workout_proposal_input_hash(v),'inputHashB',private.mobile_workout_proposal_input_hash(w),'initialState',c59s17c_fixture.state(u));
 INSERT INTO c59s17c_fixture.cases VALUES(ids[i-1800],u,p);END LOOP;
END $cases$;
COMMIT;
\echo C59S17C_CONCURRENCY_SETUP_CONFIRMED
\else
-- The two public mutators are expected ABSENT before implementation: native42883 is RED.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $rr$DECLARE u uuid:=c59s17c_fixture.uid(1799);pid uuid:=c59s17c_fixture.uid(2799);v jsonb:=c59s17c_fixture.input(45);k text:=c59s17c_fixture.edit_key(1799);BEGIN
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,c59s17c_fixture.proposal(k,v,450)),u,'22023');
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.cancel_sql(u,pid,0),u,'22023');
 PERFORM c59s17c_fixture.ok(true,'RR_mutators_reject_before_missing_owner');END $rr$;
ROLLBACK;
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='60s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $capabilities$DECLARE f oid;v boolean:=true;r jsonb;u uuid:=c59s17c_fixture.uid(1799);BEGIN
 FOREACH f IN ARRAY ARRAY['public.edit_mobile_workout_registration(uuid,uuid,integer,text,jsonb,jsonb)'::regprocedure::oid,'public.cancel_mobile_workout_registration(uuid,uuid,integer)'::regprocedure::oid]LOOP
 v:=v AND(SELECT proowner='postgres'::regrole AND prosecdef AND provolatile='v'AND proconfig=ARRAY['search_path=pg_catalog']AND prorettype='jsonb'::regtype AND pronargdefaults=0
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner)))a WHERE a.grantee NOT IN(proowner,'service_role'::regrole)OR(a.grantee<>proowner AND a.is_grantable))FROM pg_proc WHERE oid=f)
 AND has_function_privilege('service_role',f,'EXECUTE')AND NOT has_function_privilege('anon',f,'EXECUTE')AND NOT has_function_privilege('authenticated',f,'EXECUTE');END LOOP;
 PERFORM c59s17c_fixture.ok(v AND NOT has_schema_privilege('service_role','private','USAGE'),'two_dormant_rpc_exact_owner_VOLATILE_DEFINER_ACL_search_path_private_usage_unchanged');
 PERFORM c59s17c_fixture.expect_sqlstate('SELECT public.edit_mobile_workout_registration(NULL,NULL,NULL,NULL,NULL,NULL)',u,'42501','anon');
 PERFORM c59s17c_fixture.expect_sqlstate('SELECT public.cancel_mobile_workout_registration(NULL,NULL,NULL)',u,'42501','authenticated');
 PERFORM c59s17c_fixture.expect_sqlstate('SELECT public.edit_mobile_workout_registration(NULL,NULL,NULL,NULL,NULL,NULL)',u,'42501','authenticated');
 PERFORM c59s17c_fixture.expect_sqlstate('SELECT public.cancel_mobile_workout_registration(NULL,NULL,NULL)',u,'42501','anon');
 SET LOCAL request.jwt.claims='{"role":"authenticated"}';
 PERFORM c59s17c_fixture.expect_sqlstate('SELECT public.edit_mobile_workout_registration(NULL,NULL,NULL,NULL,NULL,NULL)',u,'42501','service_role','trusted backend role required');
 PERFORM c59s17c_fixture.expect_sqlstate('SELECT public.cancel_mobile_workout_registration(NULL,NULL,NULL)',u,'42501','service_role','trusted backend role required');
 SET LOCAL request.jwt.claims='{"role":"service_role"}';
 PERFORM c59s17c_fixture.ok(true,'actual_anon_authenticated_denial_and_trust_before_invalid_input');
END $capabilities$;
DO $arguments$DECLARE i integer;u uuid:=c59s17c_fixture.uid(1799);pid uuid:=c59s17c_fixture.uid(2799);v jsonb:=c59s17c_fixture.input(45);k text:=c59s17c_fixture.edit_key(1799);sql text;bad jsonb;BEGIN
 FOREACH sql IN ARRAY ARRAY[c59s17c_fixture.edit_sql(u,pid,0,k,NULL,NULL),c59s17c_fixture.edit_sql(NULL,pid,0,k,v,NULL),c59s17c_fixture.edit_sql(u,NULL,0,k,v,NULL),c59s17c_fixture.edit_sql(u,pid,NULL,k,v,NULL),c59s17c_fixture.edit_sql(u,pid,-1,k,v,NULL),c59s17c_fixture.cancel_sql(NULL,pid,0),c59s17c_fixture.cancel_sql(u,NULL,0),c59s17c_fixture.cancel_sql(u,pid,NULL),c59s17c_fixture.cancel_sql(u,pid,-1)]LOOP PERFORM c59s17c_fixture.expect_sqlstate(sql,u,'22023');END LOOP;
 PERFORM c59s17c_fixture.ok(true,'null_UUID_revision_and_negative_revision_rejected_before_missing_owner');
 FOREACH k IN ARRAY ARRAY[NULL,'','wui1:'||c59s17c_fixture.uid(1799)::text,'WUE1:'||c59s17c_fixture.uid(1799)::text,'wue1:invalid','wue1:'||c59s17c_fixture.uid(1799)::text||' ',' wue1:'||c59s17c_fixture.uid(1799)::text]LOOP PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,NULL),u,'22023');END LOOP;
 PERFORM c59s17c_fixture.ok(true,'EDIT_namespace_literal_wue1_UUID_and_no_whitespace_normalization');
 k:=c59s17c_fixture.edit_key(1799);
 FOR bad IN SELECT x FROM jsonb_array_elements(jsonb_build_array(NULL,'null'::jsonb,'[]'::jsonb,'{}'::jsonb,v-'kind',v||'{"extra":1}',v||'{"duration_min":0}',v||'{"duration_min":1.5}',v||'{"duration_min":"45"}',v||'{"duration_min":1441}',v||'{"workout_type":"  "}',v||'{"intensity":"intensa"}',v||'{"performed_at":"infinity"}',v||'{"performed_at":null}'))x LOOP PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,bad,NULL),u,'22023');END LOOP;
 PERFORM c59s17c_fixture.ok(true,'invalid_INPUT_closed_S16_domain_rejected_before_missing_owner');
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,c59s17c_fixture.proposal(k,v)),u,'P0002','service_role','mobile_workout_proposal_patient_not_found');
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.cancel_sql(u,pid,0),u,'P0002','service_role','mobile_workout_proposal_patient_not_found');
 u:=c59s17c_fixture.owner(1798);UPDATE public.users SET status='blocked'WHERE id=u;
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,c59s17c_fixture.proposal(k,v)),u,'P0002','service_role','mobile_workout_proposal_patient_not_found');
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.cancel_sql(u,pid,0),u,'P0002','service_role','mobile_workout_proposal_patient_not_found');
 PERFORM c59s17c_fixture.ok(true,'missing_and_inactive_user_preserve_exact_S16_native_error');
END $arguments$;
DO $exact$DECLARE a jsonb:=c59s17c_fixture.ui(1701);u uuid:=(a->>'ownerID')::uuid;pid uuid:=(a->>'registrationID')::uuid;v jsonb:=c59s17c_fixture.input(45);k text:=c59s17c_fixture.edit_key(2701);p jsonb:=c59s17c_fixture.proposal(k,v,450);s jsonb;o jsonb;r jsonb;lo timestamptz;hi timestamptz;saved jsonb;w jsonb:=c59s17c_fixture.input(50);k2 text:=c59s17c_fixture.edit_key(3701);p2 jsonb:=c59s17c_fixture.proposal(k2,w,500);BEGIN
 r:=c59s17c_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,c59s17c_fixture.key(9701),c59s17c_fixture.input()));
 IF r#>>'{result,status}'IS DISTINCT FROM 'admitted'OR NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions WHERE user_id=u AND request_key=c59s17c_fixture.key(9701)AND pending_id IS NULL)THEN RAISE EXCEPTION 'C59S17C_SETUP_REAL_UNBOUND_NEIGHBOR';END IF;
 s:=c59s17c_fixture.state(u);o:=c59s17c_fixture.outside(u);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,0,k,v,p));hi:=clock_timestamp();
 PERFORM c59s17c_fixture.assert_edited(r,s,u,pid,k,v,p,0,lo,hi);PERFORM c59s17c_fixture.ok(c59s17c_fixture.outside(u)=o,'Natacao40_to45_expected0_exact_same_pending_raw_payload_receipt_and_24h_no_other_effect');
 UPDATE public.user_profiles SET weight_kg=85 WHERE user_id=u;
 -- Negative expiry/clock changed by fixture owner; replay must ignore invalid candidate and never renew.
 SET LOCAL ROLE postgres;UPDATE ONLY public.pending_registrations SET expires_at=clock_timestamp()-interval '1 second'WHERE user_id=u AND id=pid;SET LOCAL ROLE NONE;
 s:=c59s17c_fixture.state(u);o:=c59s17c_fixture.outside(u);saved:=c59s17c_fixture.registration(u,pid);
 r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,0,k,v,'{"invalid":"retry candidate must be ignored"}'));
 PERFORM c59s17c_fixture.ok(r=jsonb_build_object('ok',true,'result',jsonb_build_object('status','reused','registration',saved,'receipt',jsonb_build_object('requestKey',k,'expectedRevision',0,'resultRevision',1)))AND c59s17c_fixture.state(u)=s AND c59s17c_fixture.outside(u)=o,'accepted_EDIT_retry_ignores_invalid_candidate_changed_weight_and_expired_clock_without_renewal');
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid,0,k,w,NULL),u,pid,'request_content_conflict');
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid,1,k,v,NULL),u,pid,'request_content_conflict');
 PERFORM c59s17c_fixture.ok(true,'same_receipt_input_or_expected_divergence_conflicts_before_expiry');
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid,0,k2,w,p2),u,pid,'revision_conflict');
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid,1,k2,w,p2),u,pid,'expired');
 PERFORM c59s17c_fixture.ok(true,'wrong_revision_precedes_expired_timestamp_new_edit');
 SET LOCAL ROLE postgres;UPDATE ONLY public.pending_registrations SET expires_at=clock_timestamp()+interval '1 hour'WHERE user_id=u AND id=pid;SET LOCAL ROLE NONE;
 s:=c59s17c_fixture.state(u);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,1,k2,w,p2));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_edited(r,s,u,pid,k2,w,p2,1,lo,hi);
 s:=c59s17c_fixture.state(u);o:=c59s17c_fixture.outside(u);r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,0,k,v,NULL));
 PERFORM c59s17c_fixture.ok(r=jsonb_build_object('ok',true,'result',jsonb_build_object('status','reused','registration',c59s17c_fixture.registration(u,pid),'receipt',jsonb_build_object('requestKey',k,'expectedRevision',0,'resultRevision',1)))AND r#>>'{result,registration,content_revision}'='2'AND r#>'{result,registration,proposal}'=p2 AND c59s17c_fixture.state(u)=s AND c59s17c_fixture.outside(u)=o,'revision0_to1_to2_replay_first_receipt0_1_returns_CURRENT_payload2_without_revert');
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.cancel_sql(u,pid,1),u,pid,'revision_conflict');
 PERFORM c59s17c_fixture.ok(true,'CANCEL_stale_expected_cannot_cancel_unreviewed_revision2');
 lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.cancel_sql(u,pid,2));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_cancelled(r,s,u,pid,lo,hi);
 PERFORM c59s17c_fixture.ok(true,'CANCEL_only_status_resolved_at_no_revision_receipt_expiry_or_payload_change');
 s:=c59s17c_fixture.state(u);o:=c59s17c_fixture.outside(u);r:=c59s17c_fixture.attempt(c59s17c_fixture.cancel_sql(u,pid,2));
 PERFORM c59s17c_fixture.ok(r=jsonb_build_object('ok',true,'result',jsonb_build_object('status','reused','registration',c59s17c_fixture.registration(u,pid)))AND c59s17c_fixture.state(u)=s AND c59s17c_fixture.outside(u)=o,'CANCEL_same_revision_cancelled_reuses_exact_current_without_second_write');
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.cancel_sql(u,pid,1),u,pid,'revision_conflict');
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid,2,c59s17c_fixture.edit_key(4701),v,c59s17c_fixture.proposal(c59s17c_fixture.edit_key(4701),v)),u,pid,'not_pending');
 r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,0,k,v,'null'));
 PERFORM c59s17c_fixture.ok(r=jsonb_build_object('ok',true,'result',jsonb_build_object('status','reused','registration',c59s17c_fixture.registration(u,pid),'receipt',jsonb_build_object('requestKey',k,'expectedRevision',0,'resultRevision',1)))AND c59s17c_fixture.state(u)=s,'EDIT_receipt_replay_after_cancelled_returns_current_terminal_before_new_edit_rules');
END $exact$;
DO $candidates$DECLARE a jsonb:=c59s17c_fixture.ui(1702);u uuid:=(a->>'ownerID')::uuid;pid uuid:=(a->>'registrationID')::uuid;v jsonb:=c59s17c_fixture.input(45);k text:=c59s17c_fixture.edit_key(2702);p jsonb:=c59s17c_fixture.proposal(k,v,450);bad jsonb;s jsonb;r jsonb;lo timestamptz;hi timestamptz;BEGIN
 -- Every member is a NEW key/no receipt; every invalid candidate must preserve the whole owner/global state.
 FOR bad IN SELECT p-x FROM jsonb_object_keys(p)x LOOP PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,bad),u,'22023');END LOOP;
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,NULL),u,'22023');
 FOR bad IN SELECT x FROM jsonb_array_elements(jsonb_build_array('null'::jsonb,'[]'::jsonb,'{}'::jsonb,p-'raw_args',p||'{"extra":1}',p||'{"kind":"meal"}',p||'{"workoutType":"corrida"}',p||'{"durationMin":46}',p||'{"durationMin":"45"}',p||'{"kcalEst":-1}',p||'{"kcalEst":1.5}',p||'{"kcalEst":"450"}',p||'{"intensity":"alta"}',p||'{"sourceContentType":"whatsapp"}',p||jsonb_build_object('source_provider_message_id',a->'requestKey'),p||'{"source_timestamp":"infinity"}',p||'{"source_timestamp":"2026-10-15"}',p||'{"source_timezone":""}',p||'{"source_timezone":7}',p||'{"source_timestamp":7}',p||'{"source_local_date":7}',p||'{"raw_args":null}',p||'{"express_eligible":"false"}',p||'{"source_local_date":"2026-02-30"}',p||'{"raw_args":{"workout_type":"Natação","duration_min":40,"intensity":"moderada"}}',p||'{"raw_args":{"workout_type":"Natação","duration_min":45,"intensity":"moderada","extra":1}}',p||'{"express_eligible":true}'))x LOOP PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,bad),u,'22023');END LOOP;
 PERFORM c59s17c_fixture.ok(true,'new_EDIT_strict_twelve_candidate_fields_types_provider_raw_timestamp_date_kcal_flags_no_write');
 v:=c59s17c_fixture.input(45,'Natação','2026-10-15T12:00:00.123987Z');p:=c59s17c_fixture.proposal(k,v,450,'2026-10-15T12:00:00.123Z');
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,p||'{"source_timestamp":"2026-10-15T12:00:00.124Z"}'),u,'22023');
 s:=c59s17c_fixture.state(u);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,0,k,v,p));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_edited(r,s,u,pid,k,v,p,0,lo,hi);
 PERFORM c59s17c_fixture.ok(true,'explicit_performed_at_JS_millisecond_truncation_matches_candidate_not_rounding');
END $candidates$;
DO $terminal$DECLARE i integer;a jsonb;u uuid;pid uuid;v jsonb:=c59s17c_fixture.input(45);k text;s jsonb;r jsonb;lo timestamptz;hi timestamptz;v_terminal_status text;BEGIN
 FOR i IN 1703..1705 LOOP a:=c59s17c_fixture.ui(i);u:=(a->>'ownerID')::uuid;pid:=(a->>'registrationID')::uuid;k:=c59s17c_fixture.edit_key(i+1000);v_terminal_status:=CASE i WHEN 1703 THEN 'confirmed'WHEN 1704 THEN 'expired'ELSE 'pending'END;
 SET LOCAL ROLE postgres;UPDATE ONLY public.pending_registrations SET status=v_terminal_status::public.pending_registration_status,resolved_at=CASE WHEN v_terminal_status='pending'THEN NULL ELSE clock_timestamp()END,expires_at=clock_timestamp()-interval '1 second'WHERE id=pid AND user_id=u;SET LOCAL ROLE NONE;
 IF i=1703 THEN
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid,999,k,v,NULL),u,pid,'already_confirmed');PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.cancel_sql(u,pid,999),u,pid,'already_confirmed');
 PERFORM c59s17c_fixture.ok(true,'confirmed_with_historical_lifecycle_NULL_precedes_revision_and_expiry');
 ELSIF i=1704 THEN
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid,999,k,v,NULL),u,pid,'not_pending');PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.cancel_sql(u,pid,999),u,pid,'revision_conflict');PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.cancel_sql(u,pid,0),u,pid,'not_pending');
 PERFORM c59s17c_fixture.ok(true,'expired_STATUS_terminal_EDIT_before_revision_CANCEL_after_revision');
 ELSE s:=c59s17c_fixture.state(u);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.cancel_sql(u,pid,0));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_cancelled(r,s,u,pid,lo,hi);PERFORM c59s17c_fixture.ok(true,'timestamp_expired_STATUS_pending_can_CANCEL_without_new_TTL_veto');END IF;END LOOP;
END $terminal$;
DO $authority$DECLARE i integer;a jsonb;b jsonb;u uuid;pid uuid;aid uuid;k text;v jsonb:=c59s17c_fixture.input(45);sql text;reason text;foreign_pid uuid;BEGIN
 b:=c59s17c_fixture.ui(1720);foreign_pid:=(b->>'registrationID')::uuid;
 FOR i IN 1721..1731 LOOP a:=c59s17c_fixture.ui(i);u:=(a->>'ownerID')::uuid;pid:=(a->>'registrationID')::uuid;aid:=(a#>>'{admission,admissionID}')::uuid;k:=c59s17c_fixture.edit_key(i+1000);reason:='invalid_admission';
 SET LOCAL ROLE postgres;
 CASE i
 WHEN 1721 THEN pid:=c59s17c_fixture.uid(9721); -- unknown
 WHEN 1722 THEN pid:=foreign_pid; -- foreign, same exact wire as unknown
 WHEN 1723 THEN UPDATE ONLY public.pending_registrations SET workout_ui_admission_id=NULL WHERE user_id=u AND id=pid;
 WHEN 1724 THEN UPDATE private.mobile_workout_proposal_admissions SET content_revision=NULL WHERE user_id=u AND admission_id=aid;
 WHEN 1725 THEN DELETE FROM ONLY public.pending_registrations WHERE user_id=u AND id=pid;reason:='pending_missing';
 WHEN 1726 THEN UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid()WHERE user_id=u;reason:='stale_epoch';
 WHEN 1727 THEN UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid()WHERE user_id=u;DELETE FROM ONLY public.pending_registrations WHERE user_id=u AND id=pid;reason:='stale_epoch';
 WHEN 1728 THEN UPDATE private.mobile_workout_proposal_admissions SET confirmed_lifecycle_key=c59s17c_fixture.uid(9728)WHERE user_id=u AND admission_id=aid;
 WHEN 1729 THEN
 -- Explicit OWNER corruption negative: two journals point to the same pending. No product trigger bypass.
 INSERT INTO private.mobile_workout_proposal_admissions(user_id,admission_id,epoch,request_key,request_hash,admitted_at,pending_id,first_proposal_hash,bound_at,rejection_reason,content_revision,confirmed_lifecycle_key)
 SELECT user_id,c59s17c_fixture.uid(9729),epoch,c59s17c_fixture.key(9729),request_hash,admitted_at,pending_id,first_proposal_hash,bound_at,rejection_reason,content_revision,confirmed_lifecycle_key FROM private.mobile_workout_proposal_admissions WHERE user_id=u AND admission_id=aid;
 WHEN 1730 THEN
 -- Genuine legacy unmarked row: ordinary producer, then no journal owned for the requested id.
 b:=public.replace_pending_registration_atomic(u,'{"kind":"workout","workoutType":"Natação"}',clock_timestamp()+interval '1 hour','s17c-legacy-unmarked');pid:=(b->>'pending_id')::uuid;
 WHEN 1731 THEN
 b:=public.admit_mobile_workout_registration(u,c59s17c_fixture.key(9731),c59s17c_fixture.input());
 UPDATE ONLY public.pending_registrations SET workout_ui_admission_id=(b#>>'{admission,admissionID}')::uuid WHERE user_id=u AND id=pid;
 END CASE;SET LOCAL ROLE NONE;
 FOREACH sql IN ARRAY ARRAY[c59s17c_fixture.edit_sql(u,pid,0,k,v,c59s17c_fixture.proposal(k,v)),c59s17c_fixture.cancel_sql(u,pid,0)]LOOP PERFORM c59s17c_fixture.expect_forbidden(sql,u,reason);END LOOP;
 PERFORM c59s17c_fixture.ok(true,CASE i WHEN 1721 THEN 'authority_unknown_pending_exact_no_payload'WHEN 1722 THEN 'authority_foreign_pending_same_negative_no_leak'WHEN 1723 THEN 'authority_marker_NULL_not_repaired'WHEN 1724 THEN 'authority_legacy_revision_NULL_not_promoted'WHEN 1725 THEN 'authority_deleted_original_pending_missing_no_recreation'WHEN 1726 THEN 'authority_old_epoch_stale_no_mutation'WHEN 1727 THEN 'authority_stale_epoch_precedes_deleted_pending_missing'WHEN 1728 THEN 'authority_lifecycle_nonNULL_pending_inconsistent_no_initializer'WHEN 1729 THEN 'authority_ambiguous_owned_journal_invalid_no_arbitrary_selection'WHEN 1730 THEN 'authority_real_legacy_unmarked_pending_not_ui'ELSE 'authority_wrong_owned_marker_invalid'END);
 END LOOP;
END $authority$;
DO $collision$DECLARE a jsonb:=c59s17c_fixture.ui(1741);b jsonb;u uuid:=(a->>'ownerID')::uuid;pid uuid:=(a->>'registrationID')::uuid;k text:=c59s17c_fixture.edit_key(2741);v jsonb:=c59s17c_fixture.input(45);p jsonb:=c59s17c_fixture.proposal(k,v,450);s jsonb;r jsonb;lo timestamptz;hi timestamptz;pid2 uuid;u2 uuid;BEGIN
 s:=c59s17c_fixture.state(u);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,0,k,v,p));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_edited(r,s,u,pid,k,v,p,0,lo,hi);
 -- REAL second materialize cancels old pending, retaining its receipt. Never fabricate two active admissions.
 b:=c59s17c_fixture.member(u,c59s17c_fixture.key(9741),c59s17c_fixture.input());pid2:=(b->>'registrationID')::uuid;
 IF(SELECT status FROM ONLY public.pending_registrations WHERE user_id=u AND id=pid)<>'cancelled'THEN RAISE EXCEPTION 'C59S17C_SETUP_REAL_REPLACE_DID_NOT_CANCEL_OLD';END IF;
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid2,0,k,v,p),u,pid2,'request_key_conflict');
 PERFORM c59s17c_fixture.ok(true,'historical_other_admission_EDIT_receipt_key_conflicts_after_REAL_second_materialize');
 r:=c59s17c_fixture.attempt(format('SELECT public.reset_user_conversation_atomic(%L,true)',u));IF r#>>'{result,reset}'IS DISTINCT FROM 'true'THEN RAISE EXCEPTION 'C59S17C_SETUP_REAL_RESET';END IF;
 b:=c59s17c_fixture.member(u,c59s17c_fixture.key(9744),c59s17c_fixture.input());pid2:=(b->>'registrationID')::uuid;
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid2,0,k,v,p),u,pid2,'request_key_conflict');
 PERFORM c59s17c_fixture.ok(true,'other_admission_receipt_key_still_conflicts_after_REAL_reset_old_epoch_pending_deleted');
 -- Real S16 journal can historically own a wue1 literal; initial UI remains wui1 only.
 k:=c59s17c_fixture.edit_key(9742);r:=public.admit_mobile_workout_proposal(u,k,c59s17c_fixture.input());IF r->>'status'<>'admitted'THEN RAISE EXCEPTION 'C59S17C_SETUP_REAL_S16_ADMIT';END IF;
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid2,0,k,v,c59s17c_fixture.proposal(k,v)),u,pid2,'request_key_conflict');
 PERFORM c59s17c_fixture.ok(true,'historical_initial_journal_wue1_key_conflicts_without_changing_S16_domain');
 PERFORM c59s17c_fixture.expect_sqlstate(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v),u,'22023');
 PERFORM c59s17c_fixture.ok(true,'initial_UI_admit_rejects_EDIT_namespace_without_S17B_change');
 b:=c59s17c_fixture.ui(1742);u2:=(b->>'ownerID')::uuid;pid2:=(b->>'registrationID')::uuid;k:=c59s17c_fixture.edit_key(2741);p:=c59s17c_fixture.proposal(k,v,450);s:=c59s17c_fixture.state(u2);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u2,pid2,0,k,v,p));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_edited(r,s,u2,pid2,k,v,p,0,lo,hi);
 PERFORM c59s17c_fixture.ok(true,'same_EDIT_literal_other_owner_independent_accepts');
 b:=c59s17c_fixture.ui(1743);u2:=(b->>'ownerID')::uuid;pid2:=(b->>'registrationID')::uuid;k:='wue1:ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB';p:=c59s17c_fixture.proposal(k,v,450);s:=c59s17c_fixture.state(u2);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u2,pid2,0,k,v,p));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_edited(r,s,u2,pid2,k,v,p,0,lo,hi);
 k:=lower(k);p:=c59s17c_fixture.proposal(k,v,450);s:=c59s17c_fixture.state(u2);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u2,pid2,1,k,v,p));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_edited(r,s,u2,pid2,k,v,p,1,lo,hi);
 PERFORM c59s17c_fixture.ok(true,'UUID_hex_case_preserved_C_collation_distinct_receipts_no_key_normalization');
END $collision$;
DO $overflow$DECLARE a jsonb:=c59s17c_fixture.ui(1751);u uuid:=(a->>'ownerID')::uuid;pid uuid:=(a->>'registrationID')::uuid;k text:=c59s17c_fixture.edit_key(2751);v jsonb:=c59s17c_fixture.input(45);p jsonb:=c59s17c_fixture.proposal(k,v,450);s jsonb;r jsonb;lo timestamptz;hi timestamptz;BEGIN
 -- Explicit owner-only boundary fixture, never a positive membership shortcut.
 UPDATE private.mobile_workout_proposal_admissions SET content_revision=2147483646 WHERE user_id=u;
 s:=c59s17c_fixture.state(u);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,2147483646,k,v,p));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_edited(r,s,u,pid,k,v,p,2147483646,lo,hi);
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid,2147483647,c59s17c_fixture.edit_key(3751),v,c59s17c_fixture.proposal(c59s17c_fixture.edit_key(3751),v,450)),u,pid,'revision_exhausted');
 PERFORM c59s17c_fixture.ok(true,'INT_MAX_new_EDIT_conflict_no_overflow_no_receipt_no_write');
 s:=c59s17c_fixture.state(u);r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,2147483646,k,v,NULL));
 PERFORM c59s17c_fixture.ok(r=jsonb_build_object('ok',true,'result',jsonb_build_object('status','reused','registration',c59s17c_fixture.registration(u,pid),'receipt',jsonb_build_object('requestKey',k,'expectedRevision',2147483646,'resultRevision',2147483647)))AND c59s17c_fixture.state(u)=s,'accepted_receipt_ending_INT_MAX_replays_without_overflow_or_renewal');
END $overflow$;

DO $replay_authority$DECLARE i integer;a jsonb;u uuid;pid uuid;k text;v jsonb:=c59s17c_fixture.input(45);p jsonb;s jsonb;r jsonb;lo timestamptz;hi timestamptz;reason text;BEGIN
 FOR i IN 1752..1755 LOOP a:=c59s17c_fixture.ui(i);u:=(a->>'ownerID')::uuid;pid:=(a->>'registrationID')::uuid;k:=c59s17c_fixture.edit_key(i+1000);p:=c59s17c_fixture.proposal(k,v,450);s:=c59s17c_fixture.state(u);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,0,k,v,p));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_edited(r,s,u,pid,k,v,p,0,lo,hi);
 SET LOCAL ROLE postgres;
 CASE i WHEN 1752 THEN DELETE FROM ONLY public.pending_registrations WHERE user_id=u AND id=pid;reason:='pending_missing';
 WHEN 1753 THEN UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid()WHERE user_id=u;reason:='stale_epoch';
 WHEN 1754 THEN UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid()WHERE user_id=u;DELETE FROM ONLY public.pending_registrations WHERE user_id=u AND id=pid;reason:='stale_epoch';
 WHEN 1755 THEN UPDATE ONLY public.pending_registrations SET status='confirmed',resolved_at=clock_timestamp()WHERE user_id=u AND id=pid;END CASE;SET LOCAL ROLE NONE;
 IF i<1755 THEN PERFORM c59s17c_fixture.expect_forbidden(c59s17c_fixture.edit_sql(u,pid,0,k,v,NULL),u,reason);
 ELSE s:=c59s17c_fixture.state(u);r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,0,k,v,NULL));
 IF r IS DISTINCT FROM jsonb_build_object('ok',true,'result',jsonb_build_object('status','reused','registration',c59s17c_fixture.registration(u,pid),'receipt',jsonb_build_object('requestKey',k,'expectedRevision',0,'resultRevision',1)))OR c59s17c_fixture.state(u)IS DISTINCT FROM s THEN RAISE EXCEPTION 'C59S17C_REPLAY_CONFIRMED';END IF;
 PERFORM c59s17c_fixture.expect_conflict(c59s17c_fixture.edit_sql(u,pid,1,c59s17c_fixture.edit_key(i+2000),v,NULL),u,pid,'already_confirmed');END IF;
 END LOOP;
 PERFORM c59s17c_fixture.ok(true,'accepted_receipt_does_not_bypass_deleted_stale_combined_authority_but_replays_current_confirmed');
END $replay_authority$;
DO $writers$DECLARE i integer;a jsonb;u uuid;pid uuid;k text;v jsonb:=c59s17c_fixture.input(45);p jsonb;s jsonb;r jsonb;lo timestamptz;hi timestamptz;provider text;l uuid;op text;BEGIN
 FOR i IN 1761..1762 LOOP a:=c59s17c_fixture.ui(i);u:=(a->>'ownerID')::uuid;pid:=(a->>'registrationID')::uuid;k:=c59s17c_fixture.edit_key(i+1000);p:=c59s17c_fixture.proposal(k,v,450);s:=c59s17c_fixture.state(u);lo:=clock_timestamp();r:=c59s17c_fixture.attempt(c59s17c_fixture.edit_sql(u,pid,0,k,v,p));hi:=clock_timestamp();PERFORM c59s17c_fixture.assert_edited(r,s,u,pid,k,v,p,0,lo,hi);
 IF i=1761 THEN r:=c59s17c_fixture.attempt(format('SELECT public.reset_user_conversation_atomic(%L,true)',u));IF r#>>'{result,reset}'IS DISTINCT FROM 'true'THEN RAISE EXCEPTION 'C59S17C_SETUP_RESET_FOR_PROTECTED_KEYS';END IF;
 ELSE r:=c59s17c_fixture.attempt(format('DELETE FROM ONLY public.pending_registrations p WHERE user_id=%L AND id=%L RETURNING to_jsonb(p)',u,pid));IF r->'ok'IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'C59S17C_SETUP_DELETE_FOR_PROTECTED_KEYS';END IF;END IF;
 -- Closed unique-one-open lifecycle: one real fixture lifecycle per owner, two distinct commands.
 l:=gen_random_uuid();INSERT INTO private.workout_strength_lifecycles VALUES(u,l,'2026-10-15T00:00:00Z',NULL,NULL);
 FOREACH provider IN ARRAY ARRAY[a->>'requestKey',k]LOOP
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.legacy_sql(c59s17c_fixture.arguments(u,'Natação',provider)),u,'42501','service_role','mobile_workout_registration_requires_revision');
 op:='s17c-protected-'||i||'-'||provider;
 PERFORM public.read_or_admit_workout_strength_command(u,l,op,'Natação',c59s17c_fixture.arguments(u,'Natação',provider));
 PERFORM c59s17c_fixture.expect_sqlstate(format('SELECT public.register_workout_strength_atomic(%L,%L,%L,''Natação'',NULL,NULL)',u,l,op),u,'42501','service_role','mobile_workout_registration_requires_revision');
 END LOOP;END LOOP;
 PERFORM c59s17c_fixture.ok(true,'initial_and_accepted_EDIT_keys_protected_public13_S8_after_REAL_reset_and_pending_DELETE');
END $writers$;
DO $fault_seed$BEGIN PERFORM c59s17c_fixture.ui(1771);PERFORM c59s17c_fixture.ui(1772);END $fault_seed$;
CREATE TRIGGER c59s17c_qa_after_update AFTER UPDATE ON public.pending_registrations FOR EACH ROW EXECUTE FUNCTION c59s17c_fixture.fail_after_pending_update();
DO $fault$DECLARE u uuid:=c59s17c_fixture.uid(1771);pid uuid;k text:=c59s17c_fixture.edit_key(2771);v jsonb:=c59s17c_fixture.input(45);BEGIN
 SELECT pending_id INTO STRICT pid FROM private.mobile_workout_proposal_admissions WHERE user_id=u;
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,c59s17c_fixture.proposal(k,v,450)),u,'P0001','service_role','C59S17C_INJECTED_AFTER_PENDING_UPDATE');
 PERFORM c59s17c_fixture.ok(true,'fault_AFTER_real_pending_UPDATE_rolls_back_payload_expiry_revision_receipt_all_effects');END $fault$;
DROP TRIGGER c59s17c_qa_after_update ON public.pending_registrations;
CREATE TRIGGER c59s17c_qa_after_receipt AFTER INSERT ON private.mobile_workout_registration_edit_receipts FOR EACH ROW EXECUTE FUNCTION c59s17c_fixture.fail_after_receipt_insert();
DO $fault$DECLARE u uuid:=c59s17c_fixture.uid(1772);pid uuid;k text:=c59s17c_fixture.edit_key(2772);v jsonb:=c59s17c_fixture.input(45);BEGIN
 SELECT pending_id INTO STRICT pid FROM private.mobile_workout_proposal_admissions WHERE user_id=u;
 PERFORM c59s17c_fixture.expect_sqlstate(c59s17c_fixture.edit_sql(u,pid,0,k,v,c59s17c_fixture.proposal(k,v,450)),u,'P0001','service_role','C59S17C_INJECTED_AFTER_RECEIPT_INSERT');
 PERFORM c59s17c_fixture.ok(true,'fault_AFTER_real_receipt_INSERT_rolls_back_same_pending_revision_and_receipt_atomically');END $fault$;
DROP TRIGGER c59s17c_qa_after_receipt ON private.mobile_workout_registration_edit_receipts;
DO $sentinel$BEGIN PERFORM c59s17c_fixture.ok((SELECT payload->'initialState'=c59s17c_fixture.state(owner_id)FROM c59s17c_fixture.cases WHERE case_id='sentinel'),'all_sequential_sentinel_fullstate_preserved');END $sentinel$;
ROLLBACK;
\echo C59S17C_SEQUENTIAL_ROLLBACK_CONFIRMED
\endif
\endif
\endif
