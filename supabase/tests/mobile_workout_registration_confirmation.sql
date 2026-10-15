\set ON_ERROR_STOP on
-- PRIVATE S17D TEST-FIRST SOURCE. Root adopts/reviews before any body/runtime.
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
\gset s17d_
\if :s17d_one_mode
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17D_SETUP_CONFLICTING_MODES';END$$;
\endif
DO $target$BEGIN
 IF session_user<>'c5_local_admin'OR current_database()<>'c5_reset_default_20261009'OR current_setting('port')<>'55489'OR current_setting('listen_addresses')<>''OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'THEN RAISE EXCEPTION 'C59S17D_SETUP_WRONG_LOCAL_TARGET';END IF;
 IF to_regprocedure('public.edit_mobile_workout_registration(uuid,uuid,integer,text,jsonb,jsonb)')IS NULL OR to_regprocedure('private.register_workout_strength_core(uuid,uuid,text,text,jsonb,jsonb)')IS NULL OR to_regprocedure('public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)')IS NULL THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_S17C_S8_S9_ABSENT';END IF;
END $target$;
\if :prepare_fixture
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='90s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $clean$BEGIN
 IF to_regnamespace('c59s17d_fixture')IS NOT NULL OR EXISTS(SELECT 1 FROM ONLY public.workout_types WHERE id='c59d7000-0000-0000-0000-000000009901'OR slug='c59s17d-treino')THEN RAISE EXCEPTION 'C59S17D_SETUP_SCHEMA_CATALOGUE_COLLISION';END IF;
 IF EXISTS(SELECT 1 FROM ONLY public.users WHERE id IN(SELECT('c59d7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(2701,2819)i UNION ALL SELECT('c59d7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(2901,2910)i UNION ALL SELECT 'c59d7000-0000-0000-0000-000000003999'::uuid)
 OR email IN(SELECT 'c59s17d-'||i||'@example.invalid'FROM generate_series(2701,2819)i UNION ALL SELECT 'c59s17d-'||i||'@example.invalid'FROM generate_series(2901,2910)i UNION ALL SELECT 'c59s17d-3999@example.invalid')OR wpp IN(SELECT '155519'||lpad(i::text,7,'0')FROM generate_series(2701,2819)i UNION ALL SELECT '155519'||lpad(i::text,7,'0')FROM generate_series(2901,2910)i UNION ALL SELECT '1555190003999'))THEN RAISE EXCEPTION 'C59S17D_SETUP_OWNER_COLLISION';END IF;
END $clean$;
\ir fixtures/mobile_workout_registration_confirmation_fixture.sql
DO $prepare$DECLARE p jsonb;BEGIN
 INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min,is_active,created_at,updated_at)VALUES(c59s17d_fixture.uid(9901),'c59s17d-treino','S17D treino sintético','musculacao',5,true,'2026-10-15T00:00:00.000001Z','2026-10-15T00:00:00.000001Z');
 INSERT INTO c59s17d_fixture.catalogue_origin SELECT to_jsonb(t)FROM ONLY public.workout_types t WHERE id=c59s17d_fixture.uid(9901);
 p:=c59s17d_fixture.ui(3999);p:=p||jsonb_build_object('initialState',c59s17d_fixture.state(c59s17d_fixture.uid(3999)));INSERT INTO c59s17d_fixture.cases VALUES('sentinel',c59s17d_fixture.uid(3999),p);
 INSERT INTO c59s17d_fixture.ownership VALUES('c59s17d_confirm_v1',session_user,c59s17d_fixture.fingerprint());
END $prepare$;
COMMIT;
\echo C59S17D_FIXTURE_PREPARED
\else
DO $owned$DECLARE o record;BEGIN SELECT * INTO STRICT o FROM c59s17d_fixture.ownership WHERE tag='c59s17d_confirm_v1';IF o.owner_name<>session_user OR o.fixture_fingerprint IS DISTINCT FROM c59s17d_fixture.fingerprint()OR(SELECT count(*)FROM c59s17d_fixture.ownership)<>1 THEN RAISE EXCEPTION 'C59S17D_SETUP_FIXTURE_DRIFT';END IF;END $owned$;
\if :teardown_concurrency
\set cleanup true
\else
\set cleanup :dry_cleanup_baseline
\endif
\if :cleanup
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='60s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $cleanup$DECLARE ids text[]:=ARRAY['confirm-confirm-commit','confirm-confirm-rollback','confirm-edit-commit','confirm-edit-rollback','edit-confirm-commit','edit-confirm-rollback','confirm-cancel-commit','confirm-cancel-rollback','cancel-confirm-commit','cancel-confirm-rollback','legacy-terminal-confirm-commit','legacy-terminal-confirm-rollback','expiry-confirm-after-rowlock','reset-confirm-commit','reset-confirm-rollback','delete-pending-confirm-commit','delete-pending-confirm-rollback','catalogue-mutation-confirm-commit','catalogue-mutation-confirm-rollback'];c record;n integer;u uuid;origin jsonb;actual jsonb;BEGIN
 IF(SELECT count(*)FROM c59s17d_fixture.cases)NOT IN(1,20)OR NOT EXISTS(SELECT 1 FROM c59s17d_fixture.cases WHERE case_id='sentinel'AND owner_id=c59s17d_fixture.uid(3999))OR EXISTS(SELECT 1 FROM c59s17d_fixture.cases WHERE case_id<>'sentinel'AND NOT(case_id=ANY(ids)))OR EXISTS(SELECT 1 FROM c59s17d_fixture.faults)THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_CASESET';END IF;
 FOR c IN SELECT * FROM c59s17d_fixture.cases ORDER BY owner_id LOOP n:=CASE c.case_id WHEN 'sentinel'THEN 3999 ELSE 2800+array_position(ids,c.case_id)END;u:=c59s17d_fixture.uid(n);
 IF c.owner_id IS DISTINCT FROM u OR NOT EXISTS(SELECT 1 FROM ONLY public.users WHERE id=u AND email='c59s17d-'||n||'@example.invalid'AND wpp='155519'||lpad(n::text,7,'0'))THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_OWNER_SCOPE';END IF;
 PERFORM c59s17d_fixture.assert_cleanup_case(c.case_id,u,c.payload);END LOOP;
 SELECT row_data INTO STRICT origin FROM c59s17d_fixture.catalogue_origin;SELECT to_jsonb(t)INTO STRICT actual FROM ONLY public.workout_types t WHERE id=c59s17d_fixture.uid(9901);
 IF actual-ARRAY['display_name','updated_at']IS DISTINCT FROM origin-ARRAY['display_name','updated_at']OR(actual->>'display_name'IS DISTINCT FROM origin->>'display_name'AND actual->>'display_name'IS DISTINCT FROM 'S17D changed catalogue-mutation-confirm-commit')THEN RAISE EXCEPTION 'C59S17D_TEARDOWN_CATALOGUE_DRIFT';END IF;
 -- All case owners and the exact owned catalogue row validated before any destructive statement.
 FOR u IN SELECT owner_id FROM c59s17d_fixture.cases LOOP DELETE FROM public.users WHERE id=u;END LOOP;
 DELETE FROM ONLY public.workout_types WHERE id=c59s17d_fixture.uid(9901);
END $cleanup$;
DO $drop_helpers$DECLARE f record;BEGIN FOR f IN SELECT oid FROM pg_proc WHERE pronamespace='c59s17d_fixture'::regnamespace ORDER BY oid LOOP EXECUTE format('DROP FUNCTION %s',f.oid::regprocedure);END LOOP;END $drop_helpers$;
DROP TABLE c59s17d_fixture.cases,c59s17d_fixture.catalogue_origin,c59s17d_fixture.faults,c59s17d_fixture.ownership;DROP SCHEMA c59s17d_fixture;
\if :dry_cleanup_baseline
\if :{?dry_fingerprint_path}
\i :dry_fingerprint_path
\else
DO $$BEGIN RAISE EXCEPTION 'C59S17D_SETUP_DRY_FINGERPRINT_PATH_REQUIRED';END$$;
\endif
ROLLBACK;
\echo C59S17D_DRY_CLEAN_BASELINE_ROLLBACK_CONFIRMED
\else
COMMIT;
\echo C59S17D_CONCURRENCY_TEARDOWN_CONFIRMED
\endif
\else
\if :setup_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='90s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $cases$DECLARE ids text[]:=ARRAY['confirm-confirm-commit','confirm-confirm-rollback','confirm-edit-commit','confirm-edit-rollback','edit-confirm-commit','edit-confirm-rollback','confirm-cancel-commit','confirm-cancel-rollback','cancel-confirm-commit','cancel-confirm-rollback','legacy-terminal-confirm-commit','legacy-terminal-confirm-rollback','expiry-confirm-after-rowlock','reset-confirm-commit','reset-confirm-rollback','delete-pending-confirm-commit','delete-pending-confirm-rollback','catalogue-mutation-confirm-commit','catalogue-mutation-confirm-rollback'];i integer;u uuid;p jsonb;ep jsonb;o jsonb:=public.get_workout_strength_catalogue_context();v jsonb:=c59s17d_fixture.input(45);k text;BEGIN
 IF(SELECT array_agg(case_id)FROM c59s17d_fixture.cases)IS DISTINCT FROM ARRAY['sentinel']THEN RAISE EXCEPTION 'C59S17D_SETUP_CASES_COLLISION';END IF;
 FOR i IN 2801..2819 LOOP p:=c59s17d_fixture.ui(i);u:=(p->>'ownerID')::uuid;k:=c59s17d_fixture.edit_key(i+1000);ep:=c59s17d_fixture.proposal(k,v,450);
 p:=p||jsonb_build_object('editKeyA',k,'editInputA',v,'editProposalA',ep,'inputHashA',private.mobile_workout_proposal_input_hash(v),'legacyArguments',c59s17d_fixture.legacy_arguments(u,p->'proposal'),'legacyArgumentsEditedA',c59s17d_fixture.legacy_arguments(u,ep),'catalogueObservation',o,'catalogueDecision',c59s17d_fixture.catalogue_decision(o,p#>>'{proposal,workoutType}'),'operationKey0',c59s17d_fixture.operation_key((p#>>'{admission,admissionID}')::uuid,0),'operationKey1',c59s17d_fixture.operation_key((p#>>'{admission,admissionID}')::uuid,1),'initialState',c59s17d_fixture.state(u));
 INSERT INTO c59s17d_fixture.cases VALUES(ids[i-2800],u,p);END LOOP;
END $cases$;
COMMIT;
\echo C59S17D_CONCURRENCY_SETUP_CONFIRMED
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $rr$BEGIN PERFORM c59s17d_fixture.expect_sqlstate(c59s17d_fixture.confirm_sql(c59s17d_fixture.uid(2799),c59s17d_fixture.uid(9799),0,NULL,NULL,NULL),c59s17d_fixture.uid(2799),'22023');PERFORM c59s17d_fixture.ok(true,'RR_confirm_rejects_before_missing_owner');END $rr$;
ROLLBACK;
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='120s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
DO $capability$DECLARE f oid:='public.confirm_mobile_workout_registration(uuid,uuid,integer,jsonb,jsonb,jsonb)'::regprocedure;u uuid:=c59s17d_fixture.uid(2799);sql text;role_name text;BEGIN
 PERFORM c59s17d_fixture.ok((SELECT proowner='postgres'::regrole AND prosecdef AND provolatile='v'AND proconfig=ARRAY['search_path=pg_catalog']AND pronargdefaults=0 AND prorettype='jsonb'::regtype AND proargnames=ARRAY['p_user_id','p_registration_id','p_expected_revision','p_legacy_arguments','p_catalogue_observation','p_catalogue_decision']AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner)))a WHERE a.grantee NOT IN(proowner,'service_role'::regrole)OR a.is_grantable)FROM pg_proc WHERE oid=f)AND has_function_privilege('service_role',f,'EXECUTE')AND NOT has_schema_privilege('service_role','private','USAGE'),'one_dormant_confirm_RPC_signature_owner_VOLATILE_DEFINER_narrow_ACL_no_private_grant');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated']LOOP PERFORM c59s17d_fixture.expect_sqlstate('SELECT public.confirm_mobile_workout_registration(NULL,NULL,NULL,NULL,NULL,NULL)',u,'42501',role_name);END LOOP;
 SET LOCAL request.jwt.claims='{"role":"authenticated"}';PERFORM c59s17d_fixture.expect_sqlstate('SELECT public.confirm_mobile_workout_registration(NULL,NULL,NULL,NULL,NULL,NULL)',u,'42501','service_role','trusted backend role required');SET LOCAL request.jwt.claims='{"role":"service_role"}';
 PERFORM c59s17d_fixture.ok(true,'actual_anon_authenticated_and_backend_guard_before_invalid_input');
 FOREACH sql IN ARRAY ARRAY[c59s17d_fixture.confirm_sql(NULL,u,0,NULL,NULL,NULL),c59s17d_fixture.confirm_sql(u,NULL,0,NULL,NULL,NULL),c59s17d_fixture.confirm_sql(u,u,NULL,NULL,NULL,NULL),c59s17d_fixture.confirm_sql(u,u,-1,NULL,NULL,NULL)]LOOP PERFORM c59s17d_fixture.expect_sqlstate(sql,u,'22023');END LOOP;
 PERFORM c59s17d_fixture.expect_sqlstate(c59s17d_fixture.confirm_sql(u,u,0,NULL,NULL,NULL),u,'P0002','service_role','mobile_workout_proposal_patient_not_found');
 u:=c59s17d_fixture.owner(2798);UPDATE public.users SET status='blocked'WHERE id=u;PERFORM c59s17d_fixture.expect_sqlstate(c59s17d_fixture.confirm_sql(u,u,0,NULL,NULL,NULL),u,'P0002','service_role','mobile_workout_proposal_patient_not_found');
 PERFORM c59s17d_fixture.ok(true,'NULL_negative_revision_missing_inactive_user_exact_native_errors_no_effect');END $capability$;
DO $fresh$DECLARE x jsonb:=c59s17d_fixture.ui(2701);u uuid:=(x->>'ownerID')::uuid;pid uuid:=(x->>'registrationID')::uuid;args jsonb:=c59s17d_fixture.legacy_arguments(u,x->'proposal','2026-10-16',527);o jsonb:=public.get_workout_strength_catalogue_context();s jsonb;g jsonb;r jsonb;lo timestamptz;hi timestamptz;ev jsonb;BEGIN
 -- Adjacent unbound REAL UI admission exercises preservation of pending_id NULL, too.
 r:=c59s17d_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,c59s17d_fixture.key(9701),c59s17d_fixture.input()));IF r#>>'{result,status}'IS DISTINCT FROM 'admitted'THEN RAISE EXCEPTION 'C59S17D_SETUP_UNBOUND_NEIGHBOR';END IF;
 s:=c59s17d_fixture.state(u);g:=c59s17d_fixture.outside(u);lo:=clock_timestamp();r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,pid,0,args,o,c59s17d_fixture.catalogue_decision(o,x#>>'{proposal,workoutType}')));hi:=clock_timestamp();PERFORM c59s17d_fixture.assert_confirmed(r,s,g,u,pid,args,lo,hi,'sql_insert','fact');
 ev:=c59s17d_fixture.capture_evidence(u,pid);
 PERFORM c59s17d_fixture.ok(ev#>>'{workout,estimated_kcal}'='527'AND ev#>>'{snapshot,date}'='2026-10-16'AND ev#>>'{snapshot,protein_target}'='150.13'AND ev#>'{command,legacy_arguments}'=args AND ev#>>'{resolved,fact,calendar,status}'='unavailable'AND ev#>>'{resolved,fact,calendar,reason}'='calendar_conflict','fresh_real_UI_confirm_creates_one_life_S7_S8_13_fact_binding_no_IN_with_official_recalculated_kcal_date_targets_notes');
 -- Model lost response: recover only stored operation + current resolver; new inputs are intentionally invalid.
 UPDATE public.user_profiles SET weight_kg=88 WHERE user_id=u;
 UPDATE ONLY public.workout_types SET kcal_per_min=6 WHERE id=c59s17d_fixture.uid(9901);
 SET LOCAL ROLE postgres;UPDATE ONLY public.pending_registrations SET expires_at=clock_timestamp()-interval '1 hour'WHERE user_id=u AND id=pid;SET LOCAL ROLE NONE;
 ev:=c59s17d_fixture.capture_evidence(u,pid);
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,'null','null','{"bad":"new calculation"}'),u,jsonb_build_object('status','reused','registration',c59s17d_fixture.registration(u,pid),'capture',jsonb_build_object('legacy_result',ev#>'{operation,legacy_result}','strength',ev->'resolved')));
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,1,NULL,NULL,NULL),u,jsonb_build_object('status','conflict','reason','revision_conflict','registration',c59s17d_fixture.registration(u,pid)));
 PERFORM c59s17d_fixture.ok(true,'lost_response_confirmed_replay_ignores_new_invalid13_weight_catalogue_clock_preserves_receipt_clocks_wrong_expected_conflicts');
END $fresh$;
DO $flow$DECLARE x jsonb:=c59s17d_fixture.ui(2702);u uuid:=(x->>'ownerID')::uuid;pid uuid:=(x->>'registrationID')::uuid;flow jsonb:=c59s17d_fixture.flow(u);args jsonb:=c59s17d_fixture.legacy_arguments(u,x->'proposal');o jsonb:=public.get_workout_strength_catalogue_context();s jsonb:=c59s17d_fixture.state(u);g jsonb:=c59s17d_fixture.outside(u);r jsonb;lo timestamptz;hi timestamptz;BEGIN
 lo:=clock_timestamp();r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,pid,0,args,o,c59s17d_fixture.catalogue_decision(o,x#>>'{proposal,workoutType}')));hi:=clock_timestamp();PERFORM c59s17d_fixture.assert_confirmed(r,s,g,u,pid,args,lo,hi,'sql_insert','fact');
 PERFORM c59s17d_fixture.ok((SELECT confirmed_lifecycle_key=(flow#>>'{lifecycle,lifecycleKey}')::uuid FROM private.mobile_workout_proposal_admissions WHERE user_id=u),'existing_owned_life_from_REAL_Flow_admit_IN_init_reused_no_new_IN_or_Flow_admission');END $flow$;
DO $edited$DECLARE x jsonb:=c59s17d_fixture.ui(2703);u uuid:=(x->>'ownerID')::uuid;pid uuid:=(x->>'registrationID')::uuid;k text:=c59s17d_fixture.edit_key(3703);v jsonb:=c59s17d_fixture.input(45,'c59s17d-treino','2026-10-15T12:00:00.123987Z');p jsonb:=c59s17d_fixture.proposal(k,v,450);args jsonb;o jsonb;s jsonb;g jsonb;r jsonb;lo timestamptz;hi timestamptz;BEGIN
 r:=c59s17d_fixture.attempt(c59s17d_fixture.edit_sql(u,pid,0,k,v,p));IF r#>>'{result,status}'IS DISTINCT FROM 'edited'THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_EDIT';END IF;args:=c59s17d_fixture.legacy_arguments(u,p);o:=public.get_workout_strength_catalogue_context();s:=c59s17d_fixture.state(u);g:=c59s17d_fixture.outside(u);lo:=clock_timestamp();r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,pid,1,args,o,c59s17d_fixture.catalogue_decision(o,p->>'workoutType')));hi:=clock_timestamp();PERFORM c59s17d_fixture.assert_confirmed(r,s,g,u,pid,args,lo,hi,'sql_insert','fact');
 PERFORM c59s17d_fixture.ok((SELECT raw_provider_message_id=k AND duration_min=45 FROM ONLY public.workout_logs WHERE user_id=u)AND(SELECT operation_key=c59s17d_fixture.operation_key((x#>>'{admission,admissionID}')::uuid,1)FROM private.workout_strength_operations WHERE user_id=u),'REAL_EDIT_current_wue1_receipt_revision_operationKey1_raw_performed_hash_not_recomputed_from_proposal');END $edited$;
DO $lookup$DECLARE x jsonb:=c59s17d_fixture.ui(2704);u uuid:=(x->>'ownerID')::uuid;pid uuid:=(x->>'registrationID')::uuid;f jsonb;args jsonb:=c59s17d_fixture.legacy_arguments(u,x->'proposal');o jsonb;key text:=c59s17d_fixture.operation_key((x#>>'{admission,admissionID}')::uuid,0);s jsonb;g jsonb;r jsonb;lo timestamptz;hi timestamptz;BEGIN
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,NULL,NULL,NULL),u,jsonb_build_object('status','unavailable','reason','preparation_required','registration',c59s17d_fixture.registration(u,pid)));
 PERFORM c59s17d_fixture.expect_sqlstate(c59s17d_fixture.confirm_sql(u,pid,0,'null',NULL,NULL),u,'22023');
 PERFORM c59s17d_fixture.ok(true,'SQLNULL_lookup_missing_preparation_creates_no_life_command_or_write_JSONnull_is_invalid_candidate');
 f:=c59s17d_fixture.flow(u);PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,NULL,NULL,NULL),u,jsonb_build_object('status','unavailable','reason','preparation_required','registration',c59s17d_fixture.registration(u,pid)));
 r:=public.read_or_admit_workout_strength_command(u,(f#>>'{lifecycle,lifecycleKey}')::uuid,key,x#>>'{proposal,workoutType}',args);IF r->'legacyArguments'IS DISTINCT FROM args THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_PREPARED_COMMAND';END IF;
 o:=public.get_workout_strength_catalogue_context();s:=c59s17d_fixture.state(u);g:=c59s17d_fixture.outside(u);lo:=clock_timestamp();r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,pid,0,'{"invalid":"new candidate ignored"}',o,c59s17d_fixture.catalogue_decision(o,x#>>'{proposal,workoutType}')));hi:=clock_timestamp();PERFORM c59s17d_fixture.assert_confirmed(r,s,g,u,pid,args,lo,hi,'sql_insert','fact');
 PERFORM c59s17d_fixture.ok(true,'stored_REAL_S7_command_selected_before_new_invalid13_and_lookup_with_existing_life_no_partial_effect');END $lookup$;
DO $prep$DECLARE x jsonb:=c59s17d_fixture.ui(2705);u uuid:=(x->>'ownerID')::uuid;pid uuid:=(x->>'registrationID')::uuid;a jsonb:=c59s17d_fixture.legacy_arguments(u,x->'proposal');bad jsonb;o jsonb:=public.get_workout_strength_catalogue_context();d jsonb:=c59s17d_fixture.catalogue_decision(o,x#>>'{proposal,workoutType}');BEGIN
 FOR bad IN SELECT q FROM jsonb_array_elements(jsonb_build_array(a-'p_notes',a||'{"extra":1}',a||jsonb_build_object('p_user_id',c59s17d_fixture.uid(9995)),a||'{"p_workout_type":"C59S17D-TREINO"}',a||'{"p_duration_min":45}',a||'{"p_intensity":null}',a||'{"p_provider_message_id":"wrong-provider"}',a||'{"p_performed_at":null}',a||'{"p_performed_at":"2026-10-15T12:00:00.124Z"}',a||'{"p_replace_recent":true,"p_replace_since":"2026-10-15T00:00:00Z"}',a||'{"p_replace_recent":null}',a||'{"p_replace_since":"2026-10-15T00:00:00Z"}',a||'{"p_duration_min":40.5}',a||'{"p_estimated_kcal":"525"}'))q LOOP PERFORM c59s17d_fixture.expect_sqlstate(c59s17d_fixture.confirm_sql(u,pid,0,bad,o,d),u,'22023');END LOOP;
 PERFORM c59s17d_fixture.ok(true,'new13_S7_exact_fields_UI_owner_raw_duration_intensity_current_provider_instant_replace_false_NULL_semantic_bindings_rollback');
END $prep$;
DO $stored_bad_prep$DECLARE i integer;x jsonb;u uuid;pid uuid;f jsonb;a jsonb;o jsonb;key text;BEGIN
 FOR i IN 2770..2774 LOOP x:=c59s17d_fixture.ui(i);u:=(x->>'ownerID')::uuid;pid:=(x->>'registrationID')::uuid;f:=c59s17d_fixture.flow(u);a:=c59s17d_fixture.legacy_arguments(u,x->'proposal');key:=c59s17d_fixture.operation_key((x#>>'{admission,admissionID}')::uuid,0);
 a:=a||(CASE i WHEN 2770 THEN '{"p_duration_min":45}'WHEN 2771 THEN '{"p_intensity":"alta"}'WHEN 2772 THEN '{"p_provider_message_id":"other-key"}'WHEN 2773 THEN '{"p_performed_at":"2026-10-15T12:00:00.124Z"}'ELSE '{"p_replace_recent":true,"p_replace_since":"2026-10-15T00:00:00Z"}'END)::jsonb;
 PERFORM public.read_or_admit_workout_strength_command(u,(f#>>'{lifecycle,lifecycleKey}')::uuid,key,x#>>'{proposal,workoutType}',a);o:=public.get_workout_strength_catalogue_context();
 PERFORM c59s17d_fixture.expect_sqlstate(c59s17d_fixture.confirm_sql(u,pid,0,c59s17d_fixture.legacy_arguments(u,x->'proposal'),o,c59s17d_fixture.catalogue_decision(o,x#>>'{proposal,workoutType}')),u,'22023');END LOOP;
 PERFORM c59s17d_fixture.ok(true,'chosen_STORED_real_S7_prep_semantic_mismatch_denies_without_overwrite_even_new_candidate_valid');END $stored_bad_prep$;
DO $authority$DECLARE i integer;x jsonb;y jsonb;u uuid;pid uuid;aid uuid;foreign_pid uuid;reason text;BEGIN
 y:=c59s17d_fixture.ui(2730);foreign_pid:=(y->>'registrationID')::uuid;
 FOR i IN 2731..2743 LOOP x:=c59s17d_fixture.ui(i);u:=(x->>'ownerID')::uuid;pid:=(x->>'registrationID')::uuid;aid:=(x#>>'{admission,admissionID}')::uuid;reason:='invalid_admission';SET LOCAL ROLE postgres;
 CASE i WHEN 2731 THEN pid:=c59s17d_fixture.uid(9731);
 WHEN 2732 THEN pid:=foreign_pid;
 WHEN 2733 THEN UPDATE ONLY public.pending_registrations SET workout_ui_admission_id=NULL WHERE user_id=u AND id=pid;
 WHEN 2734 THEN UPDATE private.mobile_workout_proposal_admissions SET content_revision=NULL WHERE user_id=u AND admission_id=aid;
 WHEN 2735 THEN DELETE FROM ONLY public.pending_registrations WHERE user_id=u AND id=pid;reason:='pending_missing';
 WHEN 2736 THEN UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid()WHERE user_id=u;reason:='stale_epoch';
 WHEN 2737 THEN UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid()WHERE user_id=u;DELETE FROM ONLY public.pending_registrations WHERE user_id=u AND id=pid;reason:='stale_epoch';
 WHEN 2738 THEN UPDATE private.mobile_workout_proposal_admissions SET confirmed_lifecycle_key=c59s17d_fixture.uid(9738)WHERE user_id=u;
 WHEN 2739 THEN INSERT INTO private.mobile_workout_proposal_admissions(user_id,admission_id,epoch,request_key,request_hash,admitted_at,pending_id,first_proposal_hash,bound_at,rejection_reason,content_revision,confirmed_lifecycle_key)SELECT user_id,c59s17d_fixture.uid(9739),epoch,c59s17d_fixture.key(9739),request_hash,admitted_at,pending_id,first_proposal_hash,bound_at,rejection_reason,content_revision,confirmed_lifecycle_key FROM private.mobile_workout_proposal_admissions WHERE user_id=u;
 WHEN 2740 THEN UPDATE ONLY public.pending_registrations SET proposal=jsonb_set(proposal,'{source_provider_message_id}','"wrong-initial-key"')WHERE user_id=u;
 WHEN 2741 THEN UPDATE private.mobile_workout_proposal_admissions SET content_revision=1 WHERE user_id=u; -- no current receipt
 WHEN 2742 THEN
 y:=public.admit_mobile_workout_registration(u,c59s17d_fixture.key(9742),c59s17d_fixture.input());UPDATE ONLY public.pending_registrations SET workout_ui_admission_id=(y#>>'{admission,admissionID}')::uuid WHERE user_id=u;
 WHEN 2743 THEN
 y:=public.replace_pending_registration_atomic(u,'{"kind":"workout","workoutType":"legacy"}',clock_timestamp()+interval '1 hour','s17d-real-legacy');pid:=(y->>'pending_id')::uuid;
 END CASE;SET LOCAL ROLE NONE;
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,NULL,NULL,NULL),u,jsonb_build_object('status','forbidden','reason',reason));END LOOP;
 PERFORM c59s17d_fixture.ok(true,'all_UI_authority_unknown_foreign_marker_legacy_NULL_ambiguous_deleted_stale_combined_lifecycle_and_current_provider_negatives_exact_no_payload');END $authority$;
DO $provider_receipt$DECLARE x jsonb:=c59s17d_fixture.ui(2744);u uuid:=(x->>'ownerID')::uuid;pid uuid:=(x->>'registrationID')::uuid;k text:=c59s17d_fixture.edit_key(3744);v jsonb:=c59s17d_fixture.input(45);p jsonb:=c59s17d_fixture.proposal(k,v,450);r jsonb;BEGIN
 r:=c59s17d_fixture.attempt(c59s17d_fixture.edit_sql(u,pid,0,k,v,p));IF r#>>'{result,status}'IS DISTINCT FROM 'edited'THEN RAISE EXCEPTION 'C59S17D_SETUP_EDIT_PROVIDER';END IF;
 UPDATE private.mobile_workout_registration_edit_receipts SET expected_revision=2,result_revision=3 WHERE user_id=u;
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,1,NULL,NULL,NULL),u,'{"status":"forbidden","reason":"invalid_admission"}');
 PERFORM c59s17d_fixture.ok(true,'edited_provider_requires_same_owned_admission_receipt_result_revision_CURRENT_not_any_historical_key');END $provider_receipt$;
DO $life$DECLARE i integer;x jsonb;y jsonb;u uuid;pid uuid;l uuid;reason text;BEGIN
 y:=c59s17d_fixture.ui(2745);y:=c59s17d_fixture.flow((y->>'ownerID')::uuid);l:=(y#>>'{lifecycle,lifecycleKey}')::uuid;
 FOR i IN 2750..2753 LOOP x:=c59s17d_fixture.ui(i);u:=(x->>'ownerID')::uuid;pid:=(x->>'registrationID')::uuid;reason:='unproved_lifecycle';
 CASE i WHEN 2750 THEN INSERT INTO private.workout_strength_lifecycles VALUES(u,c59s17d_fixture.uid(9750),clock_timestamp(),NULL,NULL); -- explicit orphan corruption negative
 WHEN 2751 THEN UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=c59s17d_fixture.uid(9751)WHERE user_id=u;
 WHEN 2752 THEN UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=l WHERE user_id=u;
 WHEN 2753 THEN y:=c59s17d_fixture.flow(u);UPDATE private.workout_strength_lifecycles SET closed_at=clock_timestamp(),close_operation_key='s17d-corrupt-closed'WHERE user_id=u;reason:='stale_lifecycle';END CASE;
 SET LOCAL ROLE postgres;UPDATE ONLY public.pending_registrations SET expires_at=clock_timestamp()-interval '1 hour'WHERE user_id=u;SET LOCAL ROLE NONE;
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,NULL,NULL,NULL),u,jsonb_build_object('status','forbidden','reason',reason));END LOOP;
 PERFORM c59s17d_fixture.ok(true,'life_orphan_missing_foreign_closed_fail_before_expired_TTL_no_adoption_repair_or_new_life');END $life$;
DO $terminals$DECLARE i integer;x jsonb;u uuid;pid uuid;target public.pending_registration_status;BEGIN
 FOR i IN 2754..2756 LOOP x:=c59s17d_fixture.ui(i);u:=(x->>'ownerID')::uuid;pid:=(x->>'registrationID')::uuid;target:=CASE i WHEN 2754 THEN 'cancelled'::public.pending_registration_status WHEN 2755 THEN 'expired'::public.pending_registration_status ELSE 'pending'::public.pending_registration_status END;
 SET LOCAL ROLE postgres;UPDATE ONLY public.pending_registrations SET status=target,resolved_at=CASE WHEN target='pending'THEN NULL ELSE clock_timestamp()END,expires_at=clock_timestamp()-interval '1 second'WHERE user_id=u AND id=pid;SET LOCAL ROLE NONE;
 IF i<2756 THEN PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,99,NULL,NULL,NULL),u,jsonb_build_object('status','conflict','reason','not_pending','registration',c59s17d_fixture.registration(u,pid)));
 ELSE PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,99,NULL,NULL,NULL),u,jsonb_build_object('status','conflict','reason','revision_conflict','registration',c59s17d_fixture.registration(u,pid)));PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,NULL,NULL,NULL),u,jsonb_build_object('status','conflict','reason','expired','registration',c59s17d_fixture.registration(u,pid)));END IF;END LOOP;
 PERFORM c59s17d_fixture.ok(true,'terminal_before_expected_pending_revision_before_expired_then_TTL_no_preparation_or_life_writes');END $terminals$;
DO $S9$DECLARE u uuid:=c59s17d_fixture.owner(2707);x jsonb:=c59s17d_fixture.member(u,c59s17d_fixture.key(2707),c59s17d_fixture.input(40,'c59s17d-unrecognized'));pid uuid:=(x->>'registrationID')::uuid;a jsonb:=c59s17d_fixture.legacy_arguments(u,x->'proposal');o jsonb:=public.get_workout_strength_catalogue_context();s jsonb:=c59s17d_fixture.state(u);g jsonb:=c59s17d_fixture.outside(u);r jsonb;ev jsonb;lo timestamptz;hi timestamptz;BEGIN
 lo:=clock_timestamp();r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,pid,0,a,o,c59s17d_fixture.catalogue_decision(o,x#>>'{proposal,workoutType}')));hi:=clock_timestamp();PERFORM c59s17d_fixture.assert_confirmed(r,s,g,u,pid,a,lo,hi,'sql_insert','fact');ev:=c59s17d_fixture.capture_evidence(u,pid);
 r:=c59s17d_fixture.attempt(format('SELECT public.answer_confirmed_workout_strength(%L,%L,%L,0,%L,''yes'',''s17d-real-answer'')',u,ev#>>'{operation,lifecycle_key}',ev#>>'{workout,id}',ev#>>'{resolved,fact,clarification,questionKey}'));
 IF r#>>'{result,status}'IS DISTINCT FROM 'accepted'THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_S9:%',r;END IF;ev:=c59s17d_fixture.capture_evidence(u,pid);
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,NULL,'null','null'),u,jsonb_build_object('status','reused','registration',c59s17d_fixture.registration(u,pid),'capture',jsonb_build_object('legacy_result',ev#>'{operation,legacy_result}','strength',ev->'resolved')));
 PERFORM c59s17d_fixture.ok(ev#>>'{resolved,fact,revision}'='1'AND ev#>>'{resolved,fact,clarification,status}'='answered','confirmed_replay_returns_CURRENT_fact_after_REAL_S9_answer_not_frozen_capture_payload');END $S9$;
DO $replay_negatives$DECLARE i integer;x jsonb;u uuid;pid uuid;a jsonb;o jsonb;r jsonb;reason text;BEGIN
 FOR i IN 2780..2788 LOOP x:=c59s17d_fixture.ui(i);u:=(x->>'ownerID')::uuid;pid:=(x->>'registrationID')::uuid;a:=c59s17d_fixture.legacy_arguments(u,x->'proposal');o:=public.get_workout_strength_catalogue_context();r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,pid,0,a,o,c59s17d_fixture.catalogue_decision(o,x#>>'{proposal,workoutType}')));IF r#>>'{result,status}'IS DISTINCT FROM 'confirmed'THEN RAISE EXCEPTION 'C59S17D_SETUP_CONFIRMED';END IF;
 reason:='invalid_confirmation';SET LOCAL ROLE postgres;
 CASE i WHEN 2780 THEN UPDATE private.mobile_workout_proposal_admissions SET confirmed_lifecycle_key=NULL WHERE user_id=u;
 WHEN 2781 THEN DELETE FROM private.workout_strength_operations WHERE user_id=u AND operation_kind='capture';
 WHEN 2782 THEN DELETE FROM ONLY public.workout_logs WHERE user_id=u;reason:='stale_workout';
 WHEN 2783 THEN UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=NULL WHERE user_id=u;reason:='stale_lifecycle';
 WHEN 2784 THEN UPDATE private.workout_strength_lifecycles SET closed_at=clock_timestamp(),close_operation_key='s17d-owner-negative'WHERE user_id=u;reason:='stale_lifecycle';
 WHEN 2785 THEN UPDATE private.mobile_workout_proposal_admissions SET confirmed_lifecycle_key=c59s17d_fixture.uid(9785)WHERE user_id=u;reason:='unproved_lifecycle';
 WHEN 2786 THEN UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid()WHERE user_id=u;DELETE FROM ONLY public.pending_registrations WHERE user_id=u;reason:='stale_epoch';
 WHEN 2787 THEN DELETE FROM ONLY public.pending_registrations WHERE user_id=u;reason:='pending_missing';
 WHEN 2788 THEN UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=c59s17d_fixture.uid(9788)WHERE user_id=u;reason:='stale_lifecycle';END CASE;SET LOCAL ROLE NONE;
 IF i=2780 THEN PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,1,NULL,NULL,NULL),u,jsonb_build_object('status','conflict','reason','revision_conflict','registration',c59s17d_fixture.registration(u,pid)));END IF;
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,'null','null','null'),u,jsonb_build_object('status','forbidden','reason',reason));END LOOP;
 PERFORM c59s17d_fixture.ok(true,'confirmed_missing_link_binding_tombstone_pointer_NULL_different_closed_missing_life_stale_and_deleted_never_call_core_or_remint');END $replay_negatives$;
DO $resolutions$DECLARE i integer;u uuid;v jsonb;p jsonb;a jsonb;seedargs jsonb;seed jsonb;flow jsonb;l uuid;x jsonb;pid uuid;anchor uuid;res text;outcome text;s jsonb;g jsonb;r jsonb;lo timestamptz;hi timestamptz;BEGIN
 FOR i IN 2710..2713 LOOP u:=c59s17d_fixture.owner(i);v:=c59s17d_fixture.input();p:=c59s17d_fixture.proposal(c59s17d_fixture.key(i),v);seedargs:=c59s17d_fixture.legacy_arguments(u,p);
 IF i IN(2712,2713)THEN seedargs:=seedargs||'{"p_provider_message_id":"s17d-other-provider"}';END IF;
 IF i IN(2711,2713)THEN flow:=c59s17d_fixture.flow(u);l:=(flow#>>'{lifecycle,lifecycleKey}')::uuid;seed:=c59s17d_fixture.seed_capture(u,l,seedargs);anchor:=(seed#>>'{capture,legacy_result,workout_log_id}')::uuid;outcome:='fact';
 ELSE seed:=c59s17d_fixture.attempt(c59s17d_fixture.legacy_sql(seedargs));IF seed->'ok'IS DISTINCT FROM 'true'::jsonb OR seed#>>'{result,inserted}'IS DISTINCT FROM 'true'THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL13:%',seed;END IF;anchor:=(seed#>>'{result,workout_log_id}')::uuid;outcome:='legacy_provenance_gap';END IF;
 x:=c59s17d_fixture.member(u,c59s17d_fixture.key(i),v);pid:=(x->>'registrationID')::uuid;a:=c59s17d_fixture.legacy_arguments(u,x->'proposal');res:=CASE WHEN i<2712 THEN 'provider_type_dedup'ELSE 'recent6h_dedup'END;
 s:=c59s17d_fixture.state(u);g:=c59s17d_fixture.outside(u);lo:=clock_timestamp();r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,pid,0,a,NULL,'{"status":"unavailable","reason":"catalogue_read_error"}'));hi:=clock_timestamp();PERFORM c59s17d_fixture.assert_confirmed(r,s,g,u,pid,a,lo,hi,res,outcome,anchor);
 PERFORM c59s17d_fixture.ok(true,CASE i WHEN 2710 THEN 'provider_type_gap_REAL13_prior_UI_accepts_no_backfill_or_new_snapshot'WHEN 2711 THEN 'provider_type_fact_REAL_S7_S8_current_owned_fact_reused'WHEN 2712 THEN 'recent6h_gap_REAL13_reuses_UUID_no_new_workout_fact_or_snapshot'ELSE 'recent6h_fact_REAL_S7_S8_current_owned_fact_reused'END);
 END LOOP;END $resolutions$;
-- S16 deliberately rejects padded UI types. X26 remains closed-core compatibility,
-- exercised through REAL Flow IN/init + S7/public S8, never a fictitious UI member.
DO $core_X26$DECLARE i integer;u uuid;raw text:='  c59s17d-treino  ';v jsonb;p jsonb;a jsonb;seedargs jsonb;seed jsonb;flow jsonb;l uuid;anchor uuid;outcome text;key text;s jsonb;t jsonb;g jsonb;r jsonb;admitted jsonb;cmd jsonb;op jsonb;resolved jsonb;w jsonb;target jsonb;expected_legacy jsonb;lo timestamptz;hi timestamptz;BEGIN
 FOR i IN 2714..2715 LOOP u:=c59s17d_fixture.owner(i);v:=c59s17d_fixture.input(40,raw);p:=c59s17d_fixture.proposal(c59s17d_fixture.key(i),v);seedargs:=c59s17d_fixture.legacy_arguments(u,p);
 flow:=c59s17d_fixture.flow(u);l:=(flow#>>'{lifecycle,lifecycleKey}')::uuid;
 IF i=2714 THEN seed:=c59s17d_fixture.seed_capture(u,l,seedargs);anchor:=(seed#>>'{capture,legacy_result,workout_log_id}')::uuid;outcome:='fact';
 ELSE seed:=c59s17d_fixture.attempt(c59s17d_fixture.legacy_sql(seedargs));IF seed->'ok'IS DISTINCT FROM 'true'::jsonb OR seed#>>'{result,inserted}'IS DISTINCT FROM 'true'THEN RAISE EXCEPTION 'C59S17D_SETUP_X26_REAL13:%',seed;END IF;anchor:=(seed#>>'{result,workout_log_id}')::uuid;outcome:='legacy_provenance_gap';END IF;
 PERFORM c59s17d_fixture.expect_sqlstate(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,c59s17d_fixture.key(i),v),u,'22023','service_role','invalid_mobile_workout_proposal_input');
 a:=c59s17d_fixture.legacy_arguments(u,p,'2026-10-16');key:='s17d-X26-core-'||i;
 s:=c59s17d_fixture.state(u);g:=c59s17d_fixture.outside(u);
 IF s->'private.mobile_workout_proposal_admissions'IS DISTINCT FROM '[]'::jsonb OR s->'private.mobile_workout_registration_edit_receipts'IS DISTINCT FROM '[]'::jsonb OR s->'public.pending_registrations'IS DISTINCT FROM '[]'::jsonb OR EXISTS(SELECT 1 FROM ONLY public.daily_snapshots WHERE user_id=u AND date='2026-10-16')THEN RAISE EXCEPTION 'C59S17D_SETUP_X26_NO_UI_OR_ATTEMPT_SNAPSHOT';END IF;
 lo:=clock_timestamp();admitted:=c59s17d_fixture.attempt(format('SELECT public.read_or_admit_workout_strength_command(%L,%L,%L,%L,%L::jsonb)',u,l,key,raw,a));
 IF admitted->'ok'IS DISTINCT FROM 'true'::jsonb OR admitted#>>'{result,ownerID}'IS DISTINCT FROM u::text OR admitted#>>'{result,lifecycleKey}'IS DISTINCT FROM l::text OR admitted#>>'{result,operationKey}'IS DISTINCT FROM key OR admitted#>>'{result,originalOperationType}'IS DISTINCT FROM raw OR(admitted#>'{result,legacyArguments}')::text IS DISTINCT FROM a::text THEN RAISE EXCEPTION 'C59S17D_X26_REAL_S7:%',admitted;END IF;
 r:=c59s17d_fixture.attempt(format('SELECT public.register_workout_strength_atomic(%L,%L,%L,%L,NULL,''{"status":"unavailable","reason":"catalogue_read_error"}''::jsonb)',u,l,key,raw));hi:=clock_timestamp();
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'C59S17D_X26_REAL_S8:%',r;END IF;
 t:=c59s17d_fixture.state(u);
 SELECT to_jsonb(c)INTO STRICT cmd FROM private.workout_strength_commands c WHERE c.user_id=u AND c.lifecycle_key=l AND c.operation_key=(key COLLATE "C")AND c.original_operation_type=(raw COLLATE "C");
 SELECT to_jsonb(o)INTO STRICT op FROM private.workout_strength_operations o WHERE o.user_id=u AND o.lifecycle_key=l AND o.operation_kind='capture'AND o.operation_key=(key COLLATE "C")AND o.original_operation_type=(raw COLLATE "C");
 SELECT to_jsonb(x)INTO STRICT w FROM ONLY public.workout_logs x WHERE x.user_id=u AND x.id=anchor;
 SELECT to_jsonb(x)INTO STRICT target FROM ONLY public.daily_snapshots x WHERE x.user_id=u AND x.date='2026-10-16';
 resolved:=public.resolve_confirmed_workout_strength_capture(u,l,key,raw);
 IF cmd IS DISTINCT FROM jsonb_build_object('user_id',u,'lifecycle_key',l,'operation_key',key,'original_operation_type',raw,'legacy_arguments',a,'admitted_at',cmd->'admitted_at','recent_cutoff',cmd->'recent_cutoff')OR(cmd->'legacy_arguments')::text IS DISTINCT FROM a::text OR(cmd->>'admitted_at')::timestamptz<lo OR(cmd->>'admitted_at')::timestamptz>hi OR(cmd->>'recent_cutoff')::timestamptz IS DISTINCT FROM(cmd->>'admitted_at')::timestamptz-interval '6 hours'THEN RAISE EXCEPTION 'C59S17D_X26_LITERAL_COMMAND_OR_CLOCK';END IF;
 IF op IS DISTINCT FROM jsonb_build_object('user_id',u,'lifecycle_key',l,'operation_kind','capture','operation_key',key,'original_operation_type',raw,'original_workout_log_id',anchor,'live_workout_log_id',anchor,'created_at',op->'created_at','resolution','sql_replay','capture_outcome',outcome,'legacy_result',op->'legacy_result','answer_expected_revision',NULL,'answer_question_key',NULL,'answer_value',NULL,'answer_receipt',NULL)OR(op->>'created_at')::timestamptz<lo OR(op->>'created_at')::timestamptz>hi OR(op->>'created_at')::timestamptz<(cmd->>'admitted_at')::timestamptz THEN RAISE EXCEPTION 'C59S17D_X26_REAL_BINDING_OR_CLOCK';END IF;
 IF w->>'workout_type'IS DISTINCT FROM btrim(raw)OR(w->>'snapshot_id')::uuid=(target->>'id')::uuid OR NOT EXISTS(SELECT 1 FROM ONLY public.daily_snapshots WHERE user_id=u AND id=(w->>'snapshot_id')::uuid AND date='2026-10-15')THEN RAISE EXCEPTION 'C59S17D_X26_ANCHOR15_DISTINCT_ATTEMPT16';END IF;
 IF outcome='fact'THEN
 IF resolved->>'status'IS DISTINCT FROM 'reuse_existing'OR resolved#>>'{binding,ownerID}'IS DISTINCT FROM u::text OR resolved#>>'{binding,lifecycleKey}'IS DISTINCT FROM l::text OR resolved#>>'{binding,operationKey}'IS DISTINCT FROM key OR resolved#>>'{binding,originalOperationType}'IS DISTINCT FROM raw OR resolved#>>'{binding,resolution}'IS DISTINCT FROM 'sql_replay'OR resolved#>>'{binding,workoutLogID}'IS DISTINCT FROM anchor::text OR resolved#>>'{fact,anchor,snapshotID}'IS DISTINCT FROM w->>'snapshot_id'THEN RAISE EXCEPTION 'C59S17D_X26_REAL_FACT_RESOLVER';END IF;
 ELSE IF resolved IS DISTINCT FROM jsonb_build_object('status','unavailable','reason','legacy_provenance_gap','confirmedWorkoutLogID',anchor)OR EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=u AND workout_log_id=anchor)THEN RAISE EXCEPTION 'C59S17D_X26_GAP_NO_BACKFILL';END IF;END IF;
 IF target->'exercise_calories'IS DISTINCT FROM to_jsonb((SELECT coalesce(sum(estimated_kcal),0)::integer FROM ONLY public.workout_logs WHERE user_id=u AND snapshot_id=(target->>'id')::uuid))OR target->'training_done'IS DISTINCT FROM to_jsonb(EXISTS(SELECT 1 FROM ONLY public.workout_logs WHERE user_id=u AND snapshot_id=(target->>'id')::uuid))OR target->'calories_target'IS DISTINCT FROM a->'p_calories_target'OR target->'protein_target'IS DISTINCT FROM to_jsonb((a->>'p_protein_target')::numeric(6,2))THEN RAISE EXCEPTION 'C59S17D_X26_OFFICIAL_ATTEMPT_COUNTERS_TARGETS';END IF;
 expected_legacy:=jsonb_build_object('snapshot_id',target->'id','workout_log_id',anchor,'inserted',false,'replaced_count',0,'exercise_calories',target->'exercise_calories','training_done',target->'training_done','calories_target',target->'calories_target','protein_target',target->'protein_target');
 IF(op->'legacy_result')::text IS DISTINCT FROM expected_legacy::text OR r IS DISTINCT FROM jsonb_build_object('ok',true,'result',jsonb_build_object('legacy_result',op->'legacy_result','strength',resolved))OR(r#>'{result,legacy_result}')::text IS DISTINCT FROM(op->'legacy_result')::text THEN RAISE EXCEPTION 'C59S17D_X26_EXACT_ATTEMPT_LEGACY_RESULT_AND_WIRE:%',r;END IF;
 IF jsonb_array_length(t->'private.workout_strength_commands')<>jsonb_array_length(s->'private.workout_strength_commands')+1 OR(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'private.workout_strength_commands')x WHERE x<>cmd)IS DISTINCT FROM s->'private.workout_strength_commands'OR jsonb_array_length(t->'private.workout_strength_operations')<>jsonb_array_length(s->'private.workout_strength_operations')+1 OR(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'private.workout_strength_operations')x WHERE x<>op)IS DISTINCT FROM s->'private.workout_strength_operations'THEN RAISE EXCEPTION 'C59S17D_X26_ONLY_ONE_COMMAND_AND_OPERATION';END IF;
 IF jsonb_array_length(t->'public.daily_snapshots')<>jsonb_array_length(s->'public.daily_snapshots')+1 OR(SELECT coalesce(jsonb_agg(x ORDER BY x::text),'[]'::jsonb)FROM jsonb_array_elements(t->'public.daily_snapshots')x WHERE x->>'id'<>target->>'id')IS DISTINCT FROM s->'public.daily_snapshots'THEN RAISE EXCEPTION 'C59S17D_X26_ONLY_ATTEMPT_SNAPSHOT_OLD_ANCHOR_PRESERVED';END IF;
 PERFORM c59s17d_fixture.assert_unchanged_except(s,t,ARRAY['private.workout_strength_commands','private.workout_strength_operations','public.daily_snapshots'],'X26_core_compatibility_no_UI_confirm_no_new_workout_fact_life_Flow_or_pending');
 IF c59s17d_fixture.outside(u)IS DISTINCT FROM g THEN RAISE EXCEPTION 'C59S17D_X26_OUTSIDE_CHANGED';END IF;
 PERFORM c59s17d_fixture.ok(true,CASE i WHEN 2714 THEN 'core_compatibility_X26_UI_trim_rejected_sql_replay_fact_exact_attempt_snapshot16_anchor15'ELSE 'core_compatibility_X26_UI_trim_rejected_sql_replay_gap_no_UI_confirmation_or_fact_backfill'END);
 END LOOP;END $core_X26$;
DO $other_life$DECLARE u uuid:=c59s17d_fixture.owner(2716);v jsonb:=c59s17d_fixture.input();p jsonb:=c59s17d_fixture.proposal(c59s17d_fixture.key(2716),v);a jsonb:=c59s17d_fixture.legacy_arguments(u,p);f jsonb:=c59s17d_fixture.flow(u);seed jsonb:=c59s17d_fixture.seed_capture(u,(f#>>'{lifecycle,lifecycleKey}')::uuid,a);x jsonb;pid uuid;BEGIN
 -- Explicit owner corruption negative: preserve a REAL old fact while selecting another REAL life; do not fabricate a positive membership.
 UPDATE private.workout_strength_lifecycles SET closed_at=clock_timestamp(),close_operation_key='s17d-other-life-negative'WHERE user_id=u;
 UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=NULL WHERE user_id=u;f:=c59s17d_fixture.flow(u);
 x:=c59s17d_fixture.member(u,c59s17d_fixture.key(2716),v);pid:=(x->>'registrationID')::uuid;
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,a,NULL,NULL),u,jsonb_build_object('status','conflict','reason','capture_not_accepted','registration',c59s17d_fixture.registration(u,pid),'capture','{"legacy_result":null,"strength":{"status":"forbidden","reason":"stale_workout"}}'::jsonb));
 PERFORM c59s17d_fixture.ok(true,'other_life_fact_native_S8_negative_preserved_no_success_rebinding_or_new_command');END $other_life$;
DO $capture_negative$DECLARE x jsonb:=c59s17d_fixture.ui(2717);u uuid:=(x->>'ownerID')::uuid;pid uuid:=(x->>'registrationID')::uuid;a jsonb:=c59s17d_fixture.legacy_arguments(u,x->'proposal');o jsonb:=public.get_workout_strength_catalogue_context();d jsonb:=c59s17d_fixture.catalogue_decision(o,x#>>'{proposal,workoutType}');BEGIN
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,a,NULL,'{}'),u,jsonb_build_object('status','conflict','reason','capture_not_accepted','registration',c59s17d_fixture.registration(u,pid),'capture','{"legacy_result":null,"strength":{"status":"forbidden","reason":"invalid_authority"}}'::jsonb));
 UPDATE ONLY public.workout_types SET display_name='S17D default CAS changed'WHERE id=c59s17d_fixture.uid(9901);
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,a,o,d),u,jsonb_build_object('status','conflict','reason','capture_not_accepted','registration',c59s17d_fixture.registration(u,pid),'capture','{"legacy_result":null,"strength":{"status":"conflict","reason":"source_observation_changed"}}'::jsonb));
 PERFORM c59s17d_fixture.ok(true,'legitimate_invalid_authority_and_catalogue_CAS_negatives_rollback_new_life_pointer_S7_before_exact_capture_not_accepted');END $capture_negative$;
-- Root-approved owner-corruption negative only. Parent unique index/constraints/triggers remain intact.
CREATE TABLE c59s17d_fixture.workout_shadow()INHERITS(public.workout_logs);
REVOKE ALL ON TABLE c59s17d_fixture.workout_shadow FROM PUBLIC,anon,authenticated,service_role;
DO $ambiguous$DECLARE u uuid:=c59s17d_fixture.owner(2718);v jsonb:=c59s17d_fixture.input();p jsonb:=c59s17d_fixture.proposal(c59s17d_fixture.key(2718),v);a jsonb:=c59s17d_fixture.legacy_arguments(u,p);seed jsonb;x jsonb;pid uuid;before_child jsonb;index_def text:=pg_get_indexdef('public.uniq_workout_logs_provider_msg'::regclass);BEGIN
 seed:=c59s17d_fixture.attempt(c59s17d_fixture.legacy_sql(a));IF seed#>>'{result,inserted}'IS DISTINCT FROM 'true'THEN RAISE EXCEPTION 'C59S17D_SETUP_AMBIG_REAL13';END IF;
 INSERT INTO c59s17d_fixture.workout_shadow SELECT(jsonb_populate_record(NULL::c59s17d_fixture.workout_shadow,to_jsonb(w)||jsonb_build_object('id',c59s17d_fixture.uid(9718)))).*FROM ONLY public.workout_logs w WHERE w.user_id=u;
 IF(SELECT count(*)FROM public.workout_logs WHERE user_id=u AND raw_provider_message_id=c59s17d_fixture.key(2718)AND workout_type='c59s17d-treino')<>2 OR(SELECT count(*)FROM ONLY public.workout_logs WHERE user_id=u)<>1 OR(SELECT count(*)FROM ONLY c59s17d_fixture.workout_shadow WHERE user_id=u)<>1 THEN RAISE EXCEPTION 'C59S17D_SETUP_AMBIG_TWO_VISIBLE_ONE_EACH';END IF;
 SELECT jsonb_agg(to_jsonb(w)ORDER BY id)INTO before_child FROM ONLY c59s17d_fixture.workout_shadow w WHERE user_id=u;
 x:=c59s17d_fixture.member(u,c59s17d_fixture.key(2718),v);pid:=(x->>'registrationID')::uuid;
 PERFORM c59s17d_fixture.expect_result(c59s17d_fixture.confirm_sql(u,pid,0,a,NULL,NULL),u,jsonb_build_object('status','conflict','reason','capture_not_accepted','registration',c59s17d_fixture.registration(u,pid),'capture','{"legacy_result":null,"strength":{"status":"unavailable","reason":"identity_unproved","confirmedWorkoutLogID":null}}'::jsonb));
 PERFORM c59s17d_fixture.ok(index_def=pg_get_indexdef('public.uniq_workout_logs_provider_msg'::regclass)AND before_child=(SELECT jsonb_agg(to_jsonb(w)ORDER BY id)FROM ONLY c59s17d_fixture.workout_shadow w WHERE user_id=u),'ambiguous_provider_owner_corruption_child_only_parent_unique_intact_no_product_write_or_fact_backfill');END $ambiguous$;
DROP TABLE c59s17d_fixture.workout_shadow;
DO $precision$DECLARE x jsonb:=c59s17d_fixture.ui(2719);u uuid:=(x->>'ownerID')::uuid;pid uuid:=(x->>'registrationID')::uuid;a jsonb:=c59s17d_fixture.legacy_arguments(u,x->'proposal')||'{"p_date":"2026-10-12 AD","p_duration_min":40.000000,"p_estimated_kcal":525.000000,"p_notes":null,"p_calories_target":null,"p_protein_target":150.125000000000000000001,"p_performed_at":"2026-10-15 12:00:00.123+00"}'::jsonb;o jsonb:=public.get_workout_strength_catalogue_context();s jsonb:=c59s17d_fixture.state(u);g jsonb:=c59s17d_fixture.outside(u);r jsonb;lo timestamptz;hi timestamptz;BEGIN
 lo:=clock_timestamp();r:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,pid,0,a,o,c59s17d_fixture.catalogue_decision(o,x#>>'{proposal,workoutType}')));hi:=clock_timestamp();PERFORM c59s17d_fixture.assert_confirmed(r,s,g,u,pid,a,lo,hi,'sql_insert','fact');
 PERFORM c59s17d_fixture.ok((SELECT legacy_arguments::text=a::text FROM private.workout_strength_commands WHERE user_id=u)AND(SELECT date='2026-10-12'AND calories_target IS NULL AND protein_target=150.13 FROM ONLY public.daily_snapshots WHERE user_id=u),'S7_JSONB_literal_numeric_scale_large_fraction_explicit_NULLs_SQLcastable_date_timestamp_preserved_not_remounted_or_canonicalized');END $precision$;
DO $fault_seed$DECLARE i integer;events text[]:=ARRAY['life','pointer','S7','workout','fact','binding','journal','pending','workout'];BEGIN
 FOR i IN 2901..2909 LOOP PERFORM c59s17d_fixture.ui(i);INSERT INTO c59s17d_fixture.faults VALUES(c59s17d_fixture.uid(i),events[i-2900],CASE WHEN i=2909 THEN 'P17D0'ELSE 'P0001'END);END LOOP;END $fault_seed$;
CREATE TRIGGER c59s17d_qa_after_life AFTER INSERT ON private.workout_strength_lifecycles FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.fail_checkpoint('life');
CREATE TRIGGER c59s17d_qa_after_pointer AFTER UPDATE ON private.workout_strength_authority_epochs FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.fail_checkpoint('pointer');
CREATE TRIGGER c59s17d_qa_after_S7 AFTER INSERT ON private.workout_strength_commands FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.fail_checkpoint('S7');
CREATE TRIGGER c59s17d_qa_after_workout AFTER INSERT ON public.workout_logs FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.fail_checkpoint('workout');
CREATE TRIGGER c59s17d_qa_after_fact AFTER INSERT ON private.workout_strength_facts FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.fail_checkpoint('fact');
CREATE TRIGGER c59s17d_qa_after_binding AFTER INSERT ON private.workout_strength_operations FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.fail_checkpoint('binding');
CREATE TRIGGER c59s17d_qa_after_journal AFTER UPDATE ON private.mobile_workout_proposal_admissions FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.fail_checkpoint('journal');
CREATE TRIGGER c59s17d_qa_after_pending AFTER UPDATE ON public.pending_registrations FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.fail_checkpoint('pending');
DO $faults$DECLARE i integer;u uuid;pid uuid;p jsonb;a jsonb;o jsonb:=public.get_workout_strength_catalogue_context();events text[]:=ARRAY['life','pointer','S7','workout','fact','binding','journal','pending','workout'];BEGIN
 FOR i IN 2901..2909 LOOP u:=c59s17d_fixture.uid(i);SELECT id,proposal INTO STRICT pid,p FROM ONLY public.pending_registrations WHERE user_id=u;a:=c59s17d_fixture.legacy_arguments(u,p);
 PERFORM c59s17d_fixture.expect_sqlstate(c59s17d_fixture.confirm_sql(u,pid,0,a,o,c59s17d_fixture.catalogue_decision(o,p->>'workoutType')),u,CASE WHEN i=2909 THEN 'P17D0'ELSE 'P0001'END,'service_role','C59S17D_INJECTED_AFTER_'||events[i-2900]);
 PERFORM c59s17d_fixture.ok(true,CASE i WHEN 2901 THEN 'fault_AFTER_real_life_INSERT_rolls_back_entire_confirmation'WHEN 2902 THEN 'fault_AFTER_real_epoch_pointer_UPDATE_rolls_back_life_and_pointer'WHEN 2903 THEN 'fault_AFTER_real_S7_INSERT_rolls_back_life_pointer_command'WHEN 2904 THEN 'fault_AFTER_real_workout_INSERT_rolls_back_writer_snapshot_and_authority'WHEN 2905 THEN 'fault_AFTER_real_fact_INSERT_rolls_back_writer_fact_authority'WHEN 2906 THEN 'fault_AFTER_real_capture_binding_INSERT_rolls_back_all_capture_and_authority'WHEN 2907 THEN 'fault_AFTER_real_journal_link_UPDATE_rolls_back_capture_and_confirmation'WHEN 2908 THEN 'fault_AFTER_real_pending_confirmed_UPDATE_rolls_back_every_effect'ELSE 'external_P17D0_from_real_workout_trigger_propagates_not_swallowed_as_local_negative_sentinel'END);
 END LOOP;END $faults$;
DROP TRIGGER c59s17d_qa_after_life ON private.workout_strength_lifecycles;
DROP TRIGGER c59s17d_qa_after_pointer ON private.workout_strength_authority_epochs;
DROP TRIGGER c59s17d_qa_after_S7 ON private.workout_strength_commands;
DROP TRIGGER c59s17d_qa_after_workout ON public.workout_logs;
DROP TRIGGER c59s17d_qa_after_fact ON private.workout_strength_facts;
DROP TRIGGER c59s17d_qa_after_binding ON private.workout_strength_operations;
DROP TRIGGER c59s17d_qa_after_journal ON private.mobile_workout_proposal_admissions;
DROP TRIGGER c59s17d_qa_after_pending ON public.pending_registrations;
DO $bad_capture_seed$BEGIN PERFORM c59s17d_fixture.ui(2910);END $bad_capture_seed$;
CREATE TRIGGER c59s17d_qa_corrupt_binding AFTER INSERT ON private.workout_strength_operations FOR EACH ROW EXECUTE FUNCTION c59s17d_fixture.corrupt_binding_after_insert();
DO $bad_capture$DECLARE u uuid:=c59s17d_fixture.uid(2910);pid uuid;p jsonb;a jsonb;o jsonb:=public.get_workout_strength_catalogue_context();BEGIN
 SELECT id,proposal INTO STRICT pid,p FROM ONLY public.pending_registrations WHERE user_id=u;a:=c59s17d_fixture.legacy_arguments(u,p);
 -- S8 returns its real legacy_result while the scoped AFTER trigger corrupts only the stored comparison copy.
 PERFORM c59s17d_fixture.expect_sqlstate(c59s17d_fixture.confirm_sql(u,pid,0,a,o,c59s17d_fixture.catalogue_decision(o,p->>'workoutType')),u,'P0002');
 PERFORM c59s17d_fixture.ok(true,'unexpected_positive_S8_legacy_wire_vs_stored_operation_mismatch_is_operational_P0002_all_effects_rollback');END $bad_capture$;
DROP TRIGGER c59s17d_qa_corrupt_binding ON private.workout_strength_operations;
DO $sentinel$BEGIN PERFORM c59s17d_fixture.ok((SELECT payload->'initialState'=c59s17d_fixture.state(owner_id)FROM c59s17d_fixture.cases WHERE case_id='sentinel'),'all_sequential_other_owner_sentinel_fullstate_preserved');END $sentinel$;
ROLLBACK;
\echo C59S17D_SEQUENTIAL_ROLLBACK_CONFIRMED
\endif
\endif
\endif
