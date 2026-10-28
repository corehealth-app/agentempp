-- Real S17D + FULL producers on synthetic local owners, one outer rollback.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_legacy_transition_fixture.sql
\ir fixtures/mobile_workout_strength_clarification_fixture.sql
DO $test$
DECLARE
 c jsonb;a uuid;q jsonb;full_receipt jsonb;before_ui jsonb;after_ui jsonb;
 old_life uuid;old_workout jsonb;old_fact jsonb;observation jsonb;answer jsonb;read_proof jsonb;
 scope_id uuid;binding_before jsonb;future_context jsonb;frozen jsonb;projected jsonb;
 next_monday date;future_at timestamptz;plan_draft jsonb;plan_answer jsonb;plan_before jsonb;
 payload constant jsonb:='{"plan_type":"full_body","weekly_schedule":[{"day":"seg","focus":"full body","exercises":[]},{"day":"qua","focus":"full body","exercises":[]},{"day":"sex","focus":"full body","exercises":[]}]}';
BEGIN
 c:=m3b_cycle_test.legacy_photo_context(5480);a:=(c->>'user')::uuid;
 before_ui:=c59p10b_fixture.produce(a,9480,'qa-clinical-before-full-r348');
 old_life:=(before_ui#>>'{confirmation,capture,lifecycleKey}')::uuid;
 IF old_life IS NULL THEN
  SELECT confirmed_lifecycle_key INTO STRICT old_life FROM private.mobile_workout_proposal_admissions
   WHERE user_id=a AND admission_id=(before_ui#>>'{admission,admissionID}')::uuid;
 END IF;
 SELECT to_jsonb(w) INTO STRICT old_workout FROM public.workout_logs w WHERE user_id=a;
 SELECT to_jsonb(f) INTO STRICT old_fact FROM private.workout_strength_facts f WHERE user_id=a;
 -- The pending predates FULL; only its actual terminal capture may bind later.
 after_ui:=c59s17d_fixture.member(a,c59s17d_fixture.key(9481),c59s17d_fixture.input(41,'qa-clinical-after-full-r348'));
 c:=m3b_cycle_test.process_clinical_photos(c);q:=m3b_cycle_test.legacy_clinical_request(c);
 full_receipt:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  q->'form',q->'intent',q->'proposal',NULL);
 SELECT generation INTO STRICT scope_id FROM private.strength_week_scopes WHERE user_id=a AND closed_at IS NULL;
 PERFORM m3b_cycle_test.ok((SELECT opened_at<(full_receipt->>'completed_at')::timestamptz
  FROM private.workout_strength_lifecycles WHERE user_id=a AND lifecycle_key=old_life),
  'a real workout lifecycle already existed before FULL');
 PERFORM m3b_cycle_test.ok(private.bind_mobile_strength_week_lifecycle_v2(a,
  (before_ui#>>'{admission,admissionID}')::uuid,old_life)->>'status'='unavailable'
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_strength_week_bindings WHERE user_id=a),
  'a pre-FULL capture replay cannot manufacture the new binding');
 observation:=public.get_workout_strength_catalogue_context();
 answer:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(a,(after_ui->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(a,after_ui->'proposal'),observation,
  c59s17d_fixture.catalogue_decision(observation,after_ui#>>'{proposal,workoutType}')));
 PERFORM m3b_cycle_test.ok(answer->'ok'='true' AND answer#>>'{result,status}'='confirmed',
  'the actual post-FULL S17D confirmation succeeds');
 read_proof:=private.get_mobile_strength_week_lifecycle_binding_v2(a,scope_id,old_life);
 PERFORM m3b_cycle_test.ok(read_proof->>'status'='ready' AND read_proof#>>'{proof,kind}'='clinical_full'
  AND read_proof#>>'{proof,reviewID}'=full_receipt->>'review_id'
  AND read_proof#>>'{proof,lifecycleKey}'=old_life::text AND NOT(read_proof->'proof' ? 'signupAdmissionID'),
  'FULL gets its own proof and preserves the existing lifecycle without inventing signup');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.strength_week_lifecycle_bindings WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a)
  AND public.get_mobile_strength_week_lifecycle_binding(a,scope_id,old_life)->>'status'='unavailable',
  'v1 signup authority remains unavailable for this legacy owner');
 PERFORM m3b_cycle_test.ok(old_workout=(SELECT to_jsonb(w) FROM public.workout_logs w WHERE id=(old_workout->>'id')::uuid)
  AND old_fact=(SELECT to_jsonb(f) FROM private.workout_strength_facts f WHERE workout_log_id=(old_workout->>'id')::uuid),
  'the old workout and its proven fact remain byte equivalent');
 PERFORM m3b_cycle_test.ok((SELECT o.created_at>=f.completed_at AND o.created_at>=s.recorded_at
   AND o.created_at<=p.resolved_at AND p.resolved_at<=b.bound_at AND l.opened_at< f.completed_at
  FROM private.mobile_clinical_strength_week_bindings b
  JOIN private.mobile_clinical_strength_week_sources s ON s.user_id=b.user_id AND s.review_id=b.review_id
  JOIN private.mobile_clinical_full_receipts f ON f.user_id=b.user_id AND f.review_id=b.review_id
  JOIN private.mobile_workout_proposal_admissions m ON m.user_id=b.user_id AND m.admission_id=b.workout_admission_id
  JOIN public.pending_registrations p ON p.user_id=b.user_id AND p.id=m.pending_id
  JOIN private.workout_strength_operations o ON o.user_id=b.user_id AND o.lifecycle_key=b.lifecycle_key
   AND o.operation_kind='capture' AND o.operation_key='ui:'||m.admission_id::text||':r:'||m.content_revision::text
  JOIN private.workout_strength_lifecycles l ON l.user_id=b.user_id AND l.lifecycle_key=b.lifecycle_key
  WHERE b.user_id=a),'real clocks prove FULL then capture then terminal confirmation then immutable binding');
 SELECT to_jsonb(b) INTO STRICT binding_before FROM private.mobile_clinical_strength_week_bindings b WHERE user_id=a;
 answer:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(a,(after_ui->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(a,after_ui->'proposal'),observation,
  c59s17d_fixture.catalogue_decision(observation,after_ui#>>'{proposal,workoutType}')));
 PERFORM m3b_cycle_test.ok(answer->'ok'='true'
  AND binding_before=(SELECT to_jsonb(b) FROM private.mobile_clinical_strength_week_bindings b WHERE user_id=a)
  AND (SELECT count(*)=2 FROM private.workout_strength_operations WHERE user_id=a AND operation_kind='capture'),
  'S17D replay preserves original binding clock and does not capture another workout');
 plan_draft:=public.create_plan_draft_atomic(a,'training','flow_generated','ready_for_review',payload,
  NULL,NULL,NULL,NULL,NULL,NULL,'clinical-full-plan-source-r348');
 plan_answer:=public.confirm_plan_draft_atomic(a,(plan_draft->>'id')::uuid,1,clock_timestamp()+interval '42 days','clinical-full-plan-confirm-r348');
 PERFORM m3b_cycle_test.ok(plan_answer->>'status'='confirmed'
  AND (SELECT count(*)=1 AND bool_and(planned_days=3 AND fact='value')
   FROM private.strength_week_source_versions WHERE user_id=a AND operation_namespace='mobile_plan_confirmation_v1'),
  'a real accepted plan captures its source in the FULL generation');
 SELECT to_jsonb(v) INTO STRICT plan_before FROM private.strength_week_source_versions v
  WHERE user_id=a AND operation_namespace='mobile_plan_confirmation_v1';
 PERFORM public.confirm_plan_draft_atomic(a,(plan_draft->>'id')::uuid,1,NULL,'clinical-full-plan-replay-r348');
 PERFORM m3b_cycle_test.ok(plan_before=(SELECT to_jsonb(v) FROM private.strength_week_source_versions v
  WHERE user_id=a AND operation_namespace='mobile_plan_confirmation_v1'),
  'plan confirmation replay preserves the original weekly source');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.strength_week_targets WHERE user_id=a),
  'post-FULL writers never freeze or rewrite the current week');
 next_monday:=date_trunc('week',(full_receipt->>'completed_at')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date+7;
 future_at:=(next_monday+time '12:00') AT TIME ZONE 'America/Sao_Paulo';
 future_context:=private.get_mobile_strength_week_context_at(a,future_at);
 frozen:=private.freeze_mobile_strength_week_target_at(a,scope_id,'America/Sao_Paulo',next_monday,
  future_context#>'{context,source_proof}',jsonb_build_object('source','accepted_plan','planned_days',3,
   'source_key',plan_before->'source_version_id'),future_at);
 PERFORM m3b_cycle_test.ok(frozen->>'status'='frozen' AND frozen#>>'{target,planned_days}'='3',
  'next civil Monday resolves the real accepted plan ahead of confirmed frequency');
 projected:=private.get_mobile_strength_week_projection_v2_at(a,scope_id,(frozen#>>'{target,target_id}')::uuid,future_at+interval '1 microsecond');
 PERFORM m3b_cycle_test.ok(projected->>'status'='available' AND projected#>>'{binding,kind}'='clinical_full'
  AND projected#>'{projection,workouts}'='[]'::jsonb AND projected->'target'=frozen->'target',
  'the complete atomic v2 projector uses FULL proof and does not count old workouts as new');
 -- Use the actual legacy writer to produce an older row without S12 proof.
 -- Roll back just this known negative fixture after checking the real reader.
 BEGIN
  PERFORM public.register_workout_atomic(a,'2026-10-01','qa-legacy-calendar-gap-r348',10,100,'moderada',
   'synthetic local gap','2026-10-01T12:00:00Z','qa-legacy-calendar-gap-r348',2200,150.125,false,NULL);
  old_fact:=c59s17d_fixture.state(a);
  projected:=private.get_mobile_strength_week_projection_v2_at(a,scope_id,
   (frozen#>>'{target,target_id}')::uuid,future_at+interval '1 day');
  PERFORM m3b_cycle_test.ok(projected='{"status":"unavailable","reason":"calendar_unproved"}'::jsonb
   AND c59s17d_fixture.state(a)=old_fact,
   'v2 retains the unchanged S12 refusal for ambiguous history even outside the requested week');
  RAISE EXCEPTION 'qa rollback legacy gap only' USING ERRCODE='P34B0';
 EXCEPTION WHEN SQLSTATE 'P34B0' THEN
  IF SQLERRM<>'qa rollback legacy gap only' THEN RAISE; END IF;
 END;
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_strength_week_bindings SET epoch=epoch WHERE user_id=%L',a),
  '55000','FULL binding cannot be updated directly');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_strength_week_bindings WHERE user_id=%L',a),
  '55000','FULL binding cannot be deleted directly');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM m3b_cycle_test.ok(private.get_mobile_strength_week_lifecycle_binding_v2(a,scope_id,old_life)->>'status'='unavailable'
  AND binding_before=(SELECT to_jsonb(b) FROM private.mobile_clinical_strength_week_bindings b WHERE user_id=a),
  'reset invalidates authority without erasing or rebinding the durable FULL proof');
 PERFORM m3b_cycle_test.remove_photos(ARRAY[a]);
 SET LOCAL ROLE service_role;
 DELETE FROM public.users WHERE id=a;
 RESET ROLE;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_strength_week_bindings WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_strength_week_sources WHERE user_id=a),
  'real owner cascade removes the two derived FULL ledgers without disabling constraints');
END $test$;
DO $neighbors$
DECLARE a uuid;c jsonb;q jsonb;r jsonb;ui jsonb;obs jsonb;answer jsonb;life uuid;g uuid;
 original jsonb;current_proof jsonb;before_rows jsonb;count_before bigint;future_context jsonb;frozen jsonb;future_at timestamptz;
 body constant text:='SYNTHETIC LOCAL FULL WEEK SIGNUP CONTROL';digest text;
BEGIN
 digest:=encode(extensions.digest(body,'sha256'),'hex');
 INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,
  purpose,action_type,required,effective_at)
 VALUES(m3b_cycle_test.uid(201),'m3b_week_signup_test','m3b-week-signup-1','pt-BR',body,digest,
  'synthetic_local_test','acceptance',true,clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_document(m3b_cycle_test.uid(201));
 INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
 VALUES(m3b_cycle_test.uid(202),'m3b-week-signup-1','pt-BR',ARRAY['m3b_week_signup_test'],clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_requirement_set(m3b_cycle_test.uid(202));
 a:=m3b_cycle_test.seed(5481,NULL);r:=m3b_cycle_test.complete_again(a,'genuine-full-week-binding-control-r348');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(outcome='first_fresh')
  FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a),
  'the signup neighbor uses the real observe admit and complete producer');
 ui:=c59p10b_fixture.produce(a,9482,'qa-genuine-signup-binding-control-r348');
 SELECT confirmed_lifecycle_key INTO STRICT life FROM private.mobile_workout_proposal_admissions
  WHERE user_id=a AND admission_id=(ui#>>'{admission,admissionID}')::uuid;
 SELECT generation INTO STRICT g FROM private.strength_week_scopes WHERE user_id=a AND closed_at IS NULL;
 original:=public.get_mobile_strength_week_lifecycle_binding(a,g,life);
 current_proof:=private.get_mobile_strength_week_lifecycle_binding_v2(a,g,life);
 PERFORM m3b_cycle_test.ok(original->>'status'='ready' AND current_proof->>'status'='ready'
  AND current_proof#>>'{proof,kind}'='signup_receipt' AND (current_proof->'proof')-'kind'=original->'proof'
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_strength_week_bindings WHERE user_id=a),
  'the genuine signup v1 proof is preserved exactly and only tagged by v2');

 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(5482));a:=(c->>'user')::uuid;
 q:=m3b_cycle_test.legacy_clinical_request(c);
 r:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,gen_random_uuid(),q->'form',q->'intent',q->'proposal',NULL);
 ui:=c59s17d_fixture.member(a,c59s17d_fixture.key(9483),c59s17d_fixture.input(43,'qa-binding-rollback-r348'));
 obs:=public.get_workout_strength_catalogue_context();before_rows:=c59s17d_fixture.state(a);
 EXECUTE 'CREATE FUNCTION m3b_cycle_test.fail_new_week_binding() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''qa fail after real FULL binding''; END $f$';
 CREATE TRIGGER qa_fail_after_real_full_binding AFTER INSERT ON private.mobile_clinical_strength_week_bindings
  FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_new_week_binding();
 answer:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(a,(ui->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(a,ui->'proposal'),obs,c59s17d_fixture.catalogue_decision(obs,ui#>>'{proposal,workoutType}')));
 DROP TRIGGER qa_fail_after_real_full_binding ON private.mobile_clinical_strength_week_bindings;
 PERFORM m3b_cycle_test.ok(answer->'ok'='false' AND answer->>'sqlstate'='P0001'
  AND c59s17d_fixture.state(a)=before_rows,
  'a late failure after real FULL binding rolls back the entire S17D confirmation');
 answer:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(a,(ui->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(a,ui->'proposal'),obs,c59s17d_fixture.catalogue_decision(obs,ui#>>'{proposal,workoutType}')));
 PERFORM m3b_cycle_test.ok(answer->'ok'='true' AND answer#>>'{result,status}'='confirmed'
  AND (SELECT count(*)=1 FROM private.mobile_clinical_strength_week_bindings WHERE user_id=a),
  'the unchanged pending succeeds once after a verified rolled-back failure');

 c:=m3b_cycle_test.legacy_photo_context(5483);a:=(c->>'user')::uuid;
 ui:=c59p10b_fixture.produce(a,9484,'qa-old-workout-dedup-r348');
 SELECT confirmed_lifecycle_key INTO STRICT life FROM private.mobile_workout_proposal_admissions
  WHERE user_id=a AND admission_id=(ui#>>'{admission,admissionID}')::uuid;
 SELECT count(*) INTO count_before FROM public.workout_logs WHERE user_id=a;
 c:=m3b_cycle_test.process_clinical_photos(c);q:=m3b_cycle_test.legacy_clinical_request(c);
 r:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,gen_random_uuid(),q->'form',q->'intent',q->'proposal',NULL);
 ui:=c59s17d_fixture.member(a,c59s17d_fixture.key(9485),c59s17d_fixture.input(40,'qa-old-workout-dedup-r348'));
 obs:=public.get_workout_strength_catalogue_context();
 answer:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(a,(ui->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(a,ui->'proposal'),obs,c59s17d_fixture.catalogue_decision(obs,ui#>>'{proposal,workoutType}')));
 SELECT generation INTO STRICT g FROM private.strength_week_scopes WHERE user_id=a AND closed_at IS NULL;
 PERFORM m3b_cycle_test.ok(answer->'ok'='true' AND answer#>>'{result,status}'='confirmed'
  AND (SELECT count(*)=count_before FROM public.workout_logs WHERE user_id=a)
  AND (SELECT count(*)=1 FROM private.workout_strength_operations WHERE user_id=a AND resolution='recent6h_dedup')
  AND private.get_mobile_strength_week_lifecycle_binding_v2(a,g,life)->>'status'='ready',
  'a post-FULL dedup can confirm the handshake without creating another workout');
 future_at:=(date_trunc('week',(r->>'completed_at')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date+7+time '12:00') AT TIME ZONE 'America/Sao_Paulo';
 future_context:=private.get_mobile_strength_week_context_at(a,future_at);
 frozen:=private.freeze_mobile_strength_week_target_at(a,g,'America/Sao_Paulo',
  (future_context#>>'{context,week_start}')::date,future_context#>'{context,source_proof}',
  jsonb_build_object('source','informed_frequency','planned_days',4,
   'source_key',future_context#>'{context,frequency,receipt,source_version_id}'),future_at);
 PERFORM m3b_cycle_test.ok(private.get_mobile_strength_week_projection_v2_at(a,g,(frozen#>>'{target,target_id}')::uuid,
  future_at+interval '1 microsecond')#>'{projection,workouts}'='[]'::jsonb,
  'dedup retains the old performed date and contributes no new next-week credit');
END $neighbors$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

