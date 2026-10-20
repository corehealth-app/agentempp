-- Requires the real signup/confirmation controls in the parent test transaction.
RESET ROLE;
SET LOCAL ROLE postgres;
SET LOCAL search_path=pg_catalog;
CREATE FUNCTION c59_plan_fixture.plan_state(u uuid) RETURNS jsonb LANGUAGE sql STABLE
SET search_path=pg_catalog AS $state$
 SELECT jsonb_build_object(
  'user',(SELECT to_jsonb(pu) FROM public.users pu WHERE pu.id=u),
  'profiles',(SELECT coalesce(jsonb_agg(to_jsonb(up) ORDER BY up.user_id),'[]'::jsonb) FROM public.user_profiles up WHERE up.user_id=u),
  'messages',(SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY m.id),'[]'::jsonb) FROM public.messages m WHERE m.user_id=u),
  'workouts',(SELECT coalesce(jsonb_agg(to_jsonb(w) ORDER BY w.id),'[]'::jsonb) FROM public.workout_logs w WHERE w.user_id=u),
  'lifecycles',(SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY l.lifecycle_key),'[]'::jsonb) FROM private.workout_strength_lifecycles l WHERE l.user_id=u),
  'plans',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.id),'[]'::jsonb) FROM public.training_plans p WHERE p.user_id=u),
  'drafts',(SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY d.id),'[]'::jsonb) FROM public.plan_drafts d WHERE d.user_id=u),
  'sources',(SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.source_order),'[]'::jsonb) FROM private.strength_week_source_versions v WHERE v.user_id=u),
  'receipts',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.admission_id),'[]'::jsonb) FROM private.mobile_signup_strength_completion_receipts r WHERE r.user_id=u),
  'scopes',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.generation),'[]'::jsonb) FROM private.strength_week_scopes s WHERE s.user_id=u),
  'authority',(SELECT to_jsonb(e) FROM private.workout_strength_authority_epochs e WHERE e.user_id=u))
$state$;
REVOKE ALL ON FUNCTION c59_plan_fixture.plan_state(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59_plan_fixture.fail_after_capture() RETURNS trigger LANGUAGE plpgsql
SET search_path=pg_catalog AS $fail$
BEGIN
 IF NEW.source_kind='accepted_plan' AND current_setting('c59_plan_fixture.fail_after_capture',true)='on' THEN
  RAISE EXCEPTION 'C59PLAN_INJECTED_AFTER_SOURCE' USING ERRCODE='P0001';
 END IF;
 RETURN NEW;
END $fail$;
REVOKE ALL ON FUNCTION c59_plan_fixture.fail_after_capture() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER c59_plan_fail_after_capture AFTER INSERT ON private.strength_week_source_versions
 FOR EACH ROW EXECUTE FUNCTION c59_plan_fixture.fail_after_capture();

DO $replacement_and_atomicity$
DECLARE
 u constant uuid:='c59d2c00-0000-4000-8000-000000000901';
 payload constant jsonb:='{"plan_type":"full_body","weekly_schedule":[{"day":"ter","focus":"full body","exercises":[]},{"day":"qui","focus":"full body","exercises":[]}]}';
 a jsonb;d jsonb;answer jsonb;replayed jsonb;before_state jsonb;old_plan jsonb;old_draft jsonb;old_source jsonb;
 id_a uuid;plan_a uuid;id_c uuid;plan_c uuid;g uuid;source_count bigint;sequence_before bigint;
BEGIN
 SELECT value INTO STRICT a FROM c59_plan_fixture.context WHERE key='answer_a';
 SELECT (value#>>'{}')::uuid INTO STRICT g FROM c59_plan_fixture.context WHERE key='generation';
 id_a:=(a->>'id')::uuid;plan_a:=(a->>'confirmed_plan_id')::uuid;
 SELECT to_jsonb(p) INTO STRICT old_plan FROM public.training_plans p WHERE p.id=plan_a;
 SELECT to_jsonb(pd) INTO STRICT old_draft FROM public.plan_drafts pd WHERE pd.id=id_a;
 SELECT to_jsonb(v) INTO STRICT old_source FROM private.strength_week_source_versions v
  WHERE v.user_id=u AND v.source_kind='accepted_plan';
 SET LOCAL ROLE service_role;
 d:=public.create_plan_draft_atomic(u,'training','flow_generated','ready_for_review',payload,
  NULL,NULL,NULL,NULL,NULL,NULL,'plan-neighbor-replacement');
 answer:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,NULL,'plan-neighbor-replacement-key');
 RESET ROLE;
 id_c:=(d->>'id')::uuid;plan_c:=(answer->>'confirmed_plan_id')::uuid;
 IF answer->>'status' IS DISTINCT FROM 'confirmed'
  OR (SELECT to_jsonb(p)-'active' FROM public.training_plans p WHERE p.id=plan_a) IS DISTINCT FROM (old_plan-'active')
  OR (SELECT active FROM public.training_plans WHERE id=plan_a) IS NOT FALSE
  OR (SELECT to_jsonb(pd) FROM public.plan_drafts pd WHERE pd.id=id_a) IS DISTINCT FROM old_draft
  OR (SELECT to_jsonb(v) FROM private.strength_week_source_versions v WHERE v.source_version_id=(old_source->>'source_version_id')::uuid) IS DISTINCT FROM old_source
  OR NOT EXISTS(SELECT 1 FROM private.strength_week_source_versions v WHERE v.user_id=u AND v.generation=g
   AND v.source_kind='accepted_plan' AND v.fact='value' AND v.planned_days=2 AND v.source_entity_id=plan_c
   AND v.source_valid_until IS NULL AND v.operation_namespace='mobile_plan_confirmation_v1'
   AND v.operation_key=id_c::text||':v:1' AND v.source_order>(old_source->>'source_order')::bigint)
 THEN RAISE EXCEPTION 'C59PLAN_REPLACEMENT_CHANGED_OLD_ORIGIN'; END IF;
 before_state:=c59_plan_fixture.plan_state(u);
 SET LOCAL ROLE service_role;
 replayed:=public.confirm_plan_draft_atomic(u,id_a,99,clock_timestamp()+interval '99 days','plan-neighbor-old-replay');
 RESET ROLE;
 IF replayed IS DISTINCT FROM (a||'{"already_confirmed":true}'::jsonb)
  OR c59_plan_fixture.plan_state(u) IS DISTINCT FROM before_state
 THEN RAISE EXCEPTION 'C59PLAN_REPLAY_RENEWED_OR_REORDERED_SOURCE'; END IF;
 RAISE NOTICE 'C59PLAN_NEIGHBOR_REPLACEMENT_REPLAY_ORIGINAL_PROOF';

 SET LOCAL ROLE service_role;
 d:=public.create_plan_draft_atomic(u,'training','flow_generated','ready_for_review',payload,
  NULL,NULL,NULL,NULL,NULL,NULL,'plan-neighbor-atomic-failure');
 RESET ROLE;
 before_state:=c59_plan_fixture.plan_state(u);
 SELECT count(*) INTO source_count FROM private.strength_week_source_versions WHERE user_id=u AND source_kind='accepted_plan';
 SELECT last_value INTO sequence_before FROM private.strength_week_source_versions_source_order_seq;
 PERFORM set_config('c59_plan_fixture.fail_after_capture','on',true);
 BEGIN
  SET LOCAL ROLE service_role;
  PERFORM public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,clock_timestamp()+interval '42 days','plan-neighbor-failed-attempt');
  RAISE EXCEPTION 'C59PLAN_EXPECTED_INJECTED_FAILURE';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'C59PLAN_INJECTED_AFTER_SOURCE' THEN RAISE; END IF;
 END;
 RESET ROLE;
 IF c59_plan_fixture.plan_state(u) IS DISTINCT FROM before_state
  OR (SELECT last_value FROM private.strength_week_source_versions_source_order_seq)<>sequence_before+1
 THEN RAISE EXCEPTION 'C59PLAN_FAILED_CAPTURE_NOT_ATOMIC'; END IF;
 PERFORM set_config('c59_plan_fixture.fail_after_capture','off',true);
 SET LOCAL ROLE service_role;
 answer:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,clock_timestamp()+interval '42 days','plan-neighbor-failed-attempt');
 replayed:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,clock_timestamp()+interval '42 days','plan-neighbor-failed-attempt');
 RESET ROLE;
 IF answer->>'status' IS DISTINCT FROM 'confirmed' OR replayed IS DISTINCT FROM (answer||'{"already_confirmed":true}'::jsonb)
  OR (SELECT count(*) FROM private.strength_week_source_versions WHERE user_id=u AND source_kind='accepted_plan')<>source_count+1
  OR (SELECT last_value FROM private.strength_week_source_versions_source_order_seq)<>sequence_before+2
 THEN RAISE EXCEPTION 'C59PLAN_RETRY_DUPLICATED_SOURCE'; END IF;
 RAISE NOTICE 'C59PLAN_NEIGHBOR_FAILURE_ROLLS_BACK_AND_RETRY_CAPTURES_ONCE';
END $replacement_and_atomicity$;

DO $cross_generation_contradiction$
DECLARE
 u constant uuid:='c59d2c00-0000-4000-8000-000000000901';g uuid:=gen_random_uuid();
 d jsonb;before_state jsonb;payload jsonb;v private.strength_week_source_versions%ROWTYPE;
BEGIN
 SELECT pd.payload INTO STRICT payload FROM public.plan_drafts pd WHERE pd.id=(SELECT (value->>'id')::uuid FROM c59_plan_fixture.context WHERE key='draft_a');
 SET LOCAL ROLE service_role;
 d:=public.create_plan_draft_atomic(u,'training','flow_generated','ready_for_review',payload,NULL,NULL,NULL,NULL,NULL,NULL,'plan-neighbor-origin-conflict');
 RESET ROLE;
 INSERT INTO private.strength_week_scopes(user_id,generation,open_operation_namespace,open_operation_key,opened_at,closed_at)
  VALUES(u,g,'c59_plan_fixture','closed-old-generation',clock_timestamp()-interval '2 days',clock_timestamp()-interval '1 day');
 SELECT * INTO STRICT v FROM private.strength_week_source_versions s WHERE s.user_id=u AND s.source_kind='accepted_plan'
  ORDER BY source_order LIMIT 1;
 -- Deliberately contradictory QA history in another generation/version. It is
 -- never accepted as a real producer witness; only rejection is under test.
 INSERT INTO private.strength_week_source_versions(user_id,generation,source_kind,fact,planned_days,source_entity_id,
  source_valid_until,operation_namespace,operation_key,observed_at,observed_timezone,effective_week_start)
 VALUES(u,g,'accepted_plan','value',v.planned_days,v.source_entity_id,v.source_valid_until,'mobile_plan_confirmation_v1',
  (d->>'id')||':v:0',v.observed_at,v.observed_timezone,v.effective_week_start);
 before_state:=c59_plan_fixture.plan_state(u);
 BEGIN
  SET LOCAL ROLE service_role;
  PERFORM public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,NULL,'plan-neighbor-origin-conflict-key');
  RAISE EXCEPTION 'C59PLAN_EXPECTED_ORIGIN_CONFLICT';
 EXCEPTION WHEN SQLSTATE '40001' THEN
  IF SQLERRM<>'strength_week_plan_confirmation_origin_conflict' THEN RAISE; END IF;
 END;
 RESET ROLE;
 IF c59_plan_fixture.plan_state(u) IS DISTINCT FROM before_state THEN
  RAISE EXCEPTION 'C59PLAN_CONTRADICTION_CHANGED_PLAN_OR_HISTORY'; END IF;
 RAISE NOTICE 'C59PLAN_NEIGHBOR_CROSS_GENERATION_VERSION_CONFLICT_ATOMIC';
END $cross_generation_contradiction$;

DO $without_y_then_signup$
DECLARE
 u constant uuid:='c59d2c00-0000-4000-8000-000000000902';submission jsonb;observation jsonb;admission jsonb;
 result jsonb;d jsonb;replayed jsonb;old_draft public.plan_drafts%ROWTYPE;old_plan public.training_plans%ROWTYPE;
 before_state jsonb;hash text;
BEGIN
 SELECT * INTO STRICT old_draft FROM public.plan_drafts WHERE user_id=u AND status='confirmed';
 SELECT * INTO STRICT old_plan FROM public.training_plans WHERE user_id=u AND id=old_draft.confirmed_plan_id;
 SELECT value INTO STRICT submission FROM c59_plan_fixture.context WHERE key='submission';
 submission:=submission||'{"name":"C59 plan second synthetic"}'::jsonb;
 INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_completed_at) VALUES(u,false,NULL);
 hash:=encode(extensions.digest(submission::text,'sha256'),'hex');
 SET LOCAL ROLE postgres;
 observation:=public.observe_mobile_signup_strength_epoch(u);
 admission:=public.admit_mobile_signup_strength_request(u,'plan-later-signup-20261020',hash,(observation#>>'{observation,epoch}')::uuid);
 IF admission->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59PLAN_LATER_SIGNUP_ADMISSION'; END IF;
 admission:=admission->'admission';
 result:=public.complete_mobile_onboarding_keyed(u,submission,'atomic',admission->>'requestKey',admission->>'requestHash',
  (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
 IF result->'onboarding_completed' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'C59PLAN_LATER_SIGNUP_FAILED'; END IF;
 before_state:=c59_plan_fixture.plan_state(u);
 SET LOCAL ROLE service_role;
 replayed:=public.confirm_plan_draft_atomic(u,old_draft.id,1,clock_timestamp()+interval '42 days','plan-before-Y-replay');
 RESET ROLE;
 IF replayed->'already_confirmed' IS DISTINCT FROM 'true'::jsonb
  OR c59_plan_fixture.plan_state(u) IS DISTINCT FROM before_state
  OR (SELECT to_jsonb(p) FROM public.training_plans p WHERE p.id=old_plan.id) IS DISTINCT FROM to_jsonb(old_plan)
  OR EXISTS(SELECT 1 FROM private.strength_week_source_versions WHERE user_id=u AND source_kind='accepted_plan')
 THEN RAISE EXCEPTION 'C59PLAN_REPLAY_ADOPTED_PRE_SIGNUP_PLAN'; END IF;
 BEGIN
  SET LOCAL ROLE postgres;
  PERFORM private.capture_mobile_plan_strength_week_source(u,old_draft.id,old_plan.id);
  RAISE EXCEPTION 'C59PLAN_EXPECTED_DIRECT_HISTORICAL_REJECTION';
 EXCEPTION WHEN SQLSTATE 'XX001' THEN
  IF SQLERRM<>'strength_week_plan_confirmation_origin_invalid' THEN RAISE; END IF;
 END;
 RESET ROLE;
 IF c59_plan_fixture.plan_state(u) IS DISTINCT FROM before_state THEN
  RAISE EXCEPTION 'C59PLAN_HELPER_ADOPTED_PRE_SIGNUP_PLAN'; END IF;
 RAISE NOTICE 'C59PLAN_NEIGHBOR_LATER_SIGNUP_DOES_NOT_ADOPT_OLD_PLAN';
END $without_y_then_signup$;
RESET ROLE;
