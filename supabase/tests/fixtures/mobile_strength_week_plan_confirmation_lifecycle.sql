-- Local QA only. S17D helpers below are copied literally from the reviewed
-- lifecycle fixture; no synthetic catalogue match or producer proof is seeded.
RESET ROLE;

SET LOCAL search_path=pg_catalog;
CREATE SCHEMA c59s17d_fixture AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA c59s17d_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE postgres;
CREATE FUNCTION c59s17d_fixture.uid(i integer) RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT ('c59d7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $f$;

CREATE FUNCTION c59s17d_fixture.key(i integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT 'wui1:'||c59s17d_fixture.uid(i)::text $f$;

CREATE FUNCTION c59s17d_fixture.input(duration integer DEFAULT 40,raw text DEFAULT 'c59s17d-treino',performed text DEFAULT NULL) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('kind','workout','workout_type',raw,'duration_min',duration,'intensity','moderada')||CASE WHEN performed IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('performed_at',performed)END $f$;

CREATE FUNCTION c59s17d_fixture.proposal(k text,v jsonb,kcal integer DEFAULT 400,ts text DEFAULT '2026-10-15T12:00:00.123Z') RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('kind','workout','workoutType',v->>'workout_type','durationMin',v->'duration_min','kcalEst',kcal,'intensity',v->>'intensity',
 'sourceContentType','mobile','source_provider_message_id',k,'source_timestamp',ts,'source_timezone','UTC','source_local_date',left(ts,10),
 'raw_args',jsonb_build_object('workout_type',v->>'workout_type','duration_min',v->'duration_min','intensity',v->>'intensity'),'express_eligible',false) $f$;

CREATE FUNCTION c59s17d_fixture.attempt(sql text,role_name text DEFAULT 'service_role') RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $f$
DECLARE r jsonb;s text;m text;BEGIN EXECUTE format('SET LOCAL ROLE %I',role_name);
 BEGIN EXECUTE sql INTO r;EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;END;
 SET LOCAL ROLE NONE;IF s IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'sqlstate',s,'message',m);END IF;
 RETURN jsonb_build_object('ok',true,'result',r);END $f$;

CREATE FUNCTION c59s17d_fixture.member(u uuid,k text,v jsonb,kcal integer DEFAULT 400) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE r jsonb;a jsonb;p jsonb:=c59s17d_fixture.proposal(k,v,kcal);e timestamptz:=clock_timestamp()+interval '6 hours';BEGIN
 r:=c59s17d_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_ADMIT:%',r;END IF;a:=r#>'{result,admission}';
 r:=c59s17d_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,a->>'admissionID',v,p,e));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'materialized' THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_MATERIALIZE:%',r;END IF;
 RETURN jsonb_build_object('ownerID',u,'requestKey',k,'input',v,'proposal',p,'expiresAt',e,'admission',a,'materialized',r->'result','registrationID',r#>'{result,pendingID}');END $f$;

CREATE FUNCTION c59s17d_fixture.confirm_sql(u uuid,pid uuid,expected integer,a jsonb,o jsonb,d jsonb)RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.confirm_mobile_workout_registration(%L::uuid,%L::uuid,%L::integer,%L::jsonb,%L::jsonb,%L::jsonb)',u,pid,expected,a,o,d) $f$;

CREATE FUNCTION c59s17d_fixture.legacy_arguments(u uuid,p jsonb,day text DEFAULT NULL,kcal integer DEFAULT 525)RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('p_user_id',u,'p_date',coalesce(day,p->>'source_local_date'),'p_workout_type',p->'workoutType','p_duration_min',p->'durationMin','p_estimated_kcal',kcal,'p_intensity',p->'intensity','p_notes','S17D café 🏋️','p_performed_at',p->'source_timestamp','p_provider_message_id',p->'source_provider_message_id','p_calories_target',2200,'p_protein_target',150.125,'p_replace_recent',false,'p_replace_since',NULL) $f$;

CREATE FUNCTION c59s17d_fixture.catalogue_decision(o jsonb,raw text)RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT CASE WHEN raw='c59s17d-treino'THEN jsonb_build_object('status','matched','observationKey',o->'observationKey','matcherVersion',o->'matcherVersion','originalOperationType',raw,'method','active_slug','selectedRowID',c59s17d_fixture.uid(9901))
 ELSE jsonb_build_object('status','unrecognized','observationKey',o->'observationKey','matcherVersion',o->'matcherVersion','originalOperationType',raw,'reason','no_active_match')END $f$;

CREATE FUNCTION c59s17d_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id'AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY to_jsonb(x)::text),''[]''::jsonb)FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c59s17d_fixture FROM PUBLIC,anon,authenticated,service_role;
RESET ROLE;
DO $plan_after_lifecycle_and_reset$
DECLARE
 u constant uuid:='c59d2c00-0000-4000-8000-000000000901';
 payload constant jsonb:='{"plan_type":"full_body","weekly_schedule":[{"day":"ter","focus":"full body","exercises":[]},{"day":"qui","focus":"full body","exercises":[]}]}';
 old_state jsonb;after_l jsonb;before_reset jsonb;after_reset jsonb;proof jsonb;
 ui jsonb;obs jsonb;result jsonb;d jsonb;answer jsonb;replayed jsonb;original_answer jsonb;
 generation uuid;lifecycle uuid;v_epoch uuid;plan uuid;valid timestamptz;sequence_before bigint;
 new_source private.strength_week_source_versions%ROWTYPE;
BEGIN
 SELECT (value#>>'{}')::uuid INTO STRICT generation FROM c59_plan_fixture.context WHERE key='generation';
 SELECT value INTO STRICT original_answer FROM c59_plan_fixture.context WHERE key='answer_a';
 old_state:=c59s17d_fixture.state(u);
 SELECT last_value INTO sequence_before FROM private.strength_week_source_versions_source_order_seq;
 ui:=c59s17d_fixture.member(u,c59s17d_fixture.key(7901),
  c59s17d_fixture.input(41,'c59plan-after-l-20261020'));
 obs:=public.get_workout_strength_catalogue_context();
 IF obs->>'status' IS DISTINCT FROM 'available' THEN RAISE EXCEPTION 'C59PLAN_AFTER_L_CATALOGUE_UNAVAILABLE'; END IF;
 result:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(ui->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(u,ui->'proposal'),obs,
  c59s17d_fixture.catalogue_decision(obs,ui#>>'{proposal,workoutType}')));
 IF result->'ok' IS DISTINCT FROM 'true'::jsonb OR result#>>'{result,status}' IS DISTINCT FROM 'confirmed'
  OR result#>>'{result,capture,strength,status}' IS DISTINCT FROM 'committed'
 THEN RAISE EXCEPTION 'C59PLAN_AFTER_L_WORKOUT_NOT_CONFIRMED:%',result; END IF;
 SELECT e.epoch,e.current_lifecycle_key INTO STRICT v_epoch,lifecycle FROM private.workout_strength_authority_epochs e WHERE e.user_id=u;
 after_l:=c59s17d_fixture.state(u);
 IF lifecycle IS NULL
  OR v_epoch IS DISTINCT FROM (old_state#>>'{private.workout_strength_authority_epochs,0,epoch}')::uuid
  OR NOT EXISTS(SELECT 1 FROM private.mobile_workout_proposal_admissions wa WHERE wa.user_id=u
    AND wa.admission_id=(ui#>>'{admission,admissionID}')::uuid AND wa.confirmed_lifecycle_key=lifecycle)
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles life WHERE life.user_id=u AND life.lifecycle_key=lifecycle AND life.closed_at IS NULL)
  OR after_l->'private.strength_week_source_versions' IS DISTINCT FROM old_state->'private.strength_week_source_versions'
  OR after_l->'private.mobile_signup_strength_completion_receipts' IS DISTINCT FROM old_state->'private.mobile_signup_strength_completion_receipts'
  OR (SELECT last_value FROM private.strength_week_source_versions_source_order_seq)<>sequence_before
 THEN RAISE EXCEPTION 'C59PLAN_AFTER_L_ORIGIN_CHANGED'; END IF;
 SET LOCAL ROLE service_role;
 d:=public.create_plan_draft_atomic(u,'training','flow_generated','ready_for_review',payload,NULL,NULL,NULL,NULL,NULL,NULL,'plan-after-real-lifecycle');
 valid:=clock_timestamp()+interval '42 days';
 answer:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,valid,'plan-after-real-lifecycle-key');
 RESET ROLE;
 plan:=(answer->>'confirmed_plan_id')::uuid;
 SELECT sv.* INTO STRICT new_source FROM private.strength_week_source_versions sv
  WHERE sv.user_id=u AND sv.operation_namespace='mobile_plan_confirmation_v1' AND sv.operation_key=(d->>'id')||':v:1';
 IF answer->>'status' IS DISTINCT FROM 'confirmed' OR new_source.generation IS DISTINCT FROM generation
  OR new_source.source_kind<>'accepted_plan' OR new_source.fact<>'value' OR new_source.planned_days<>2
  OR new_source.source_entity_id IS DISTINCT FROM plan OR new_source.source_valid_until IS DISTINCT FROM valid
  OR new_source.observed_timezone<>'UTC'
  OR new_source.observed_at>clock_timestamp()
  OR NOT EXISTS(SELECT 1 FROM public.plan_drafts pd JOIN public.training_plans tp ON tp.id=pd.confirmed_plan_id AND tp.user_id=pd.user_id
      WHERE pd.id=(d->>'id')::uuid AND pd.user_id=u AND pd.status='confirmed' AND tp.id=plan
       AND pd.resolved_at<=new_source.observed_at AND tp.generated_at=pd.resolved_at AND tp.valid_until=valid)
  OR new_source.effective_week_start IS DISTINCT FROM (date_trunc('week',new_source.observed_at AT TIME ZONE 'UTC')::date+7)
  OR (SELECT last_value FROM private.strength_week_source_versions_source_order_seq)<>sequence_before+1
  OR (SELECT jsonb_agg(to_jsonb(sv) ORDER BY to_jsonb(sv)::text) FROM private.strength_week_source_versions sv
      WHERE sv.user_id=u AND sv.source_version_id<>new_source.source_version_id) IS DISTINCT FROM after_l->'private.strength_week_source_versions'
  OR (c59s17d_fixture.state(u)->'private.mobile_signup_strength_completion_receipts') IS DISTINCT FROM after_l->'private.mobile_signup_strength_completion_receipts'
  OR (c59s17d_fixture.state(u)-ARRAY['public.training_plans','public.plan_drafts','private.strength_week_source_versions'])
      IS DISTINCT FROM (after_l-ARRAY['public.training_plans','public.plan_drafts','private.strength_week_source_versions'])
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs e WHERE e.user_id=u AND e.epoch=v_epoch AND e.current_lifecycle_key=lifecycle)
 THEN RAISE EXCEPTION 'C59PLAN_AFTER_L_ACCEPTED_SOURCE_INVALID'; END IF;
 before_reset:=c59s17d_fixture.state(u);
 SET LOCAL ROLE service_role;
 replayed:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,99,clock_timestamp()+interval '99 days','plan-after-L-replay');
 RESET ROLE;
 IF replayed IS DISTINCT FROM (answer||'{"already_confirmed":true}'::jsonb)
  OR c59s17d_fixture.state(u) IS DISTINCT FROM before_reset
  OR (SELECT last_value FROM private.strength_week_source_versions_source_order_seq)<>sequence_before+1
 THEN RAISE EXCEPTION 'C59PLAN_AFTER_L_REPLAY_CHANGED_OWNER'; END IF;
 RAISE NOTICE 'C59PLAN_AFTER_REAL_LIFECYCLE_CAPTURES_ONCE_SAME_GENERATION';

 SET LOCAL ROLE service_role;
 result:=public.reset_user_conversation_atomic(u,true);
 RESET ROLE;
 after_reset:=c59s17d_fixture.state(u);
 IF result->'reset' IS DISTINCT FROM 'true'::jsonb OR result->'kept_plans' IS DISTINCT FROM 'true'::jsonb
  OR EXISTS(SELECT 1 FROM private.strength_week_scopes s WHERE s.user_id=u AND s.closed_at IS NULL)
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles life WHERE life.user_id=u AND life.lifecycle_key=lifecycle AND life.closed_at IS NOT NULL)
  OR NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs e WHERE e.user_id=u AND e.epoch<>v_epoch AND e.current_lifecycle_key IS NULL)
  OR after_reset->'private.strength_week_source_versions' IS DISTINCT FROM before_reset->'private.strength_week_source_versions'
  OR after_reset->'private.mobile_signup_strength_completion_receipts' IS DISTINCT FROM before_reset->'private.mobile_signup_strength_completion_receipts'
  OR after_reset->'public.training_plans' IS DISTINCT FROM before_reset->'public.training_plans'
  OR after_reset->'public.plan_drafts' IS DISTINCT FROM before_reset->'public.plan_drafts'
  OR (SELECT last_value FROM private.strength_week_source_versions_source_order_seq)<>sequence_before+1
 THEN RAISE EXCEPTION 'C59PLAN_RESET_DID_NOT_RETAIN_OLD_PROOF'; END IF;
 SET LOCAL ROLE service_role;
 d:=public.create_plan_draft_atomic(u,'training','flow_generated','ready_for_review',payload,NULL,NULL,NULL,NULL,NULL,NULL,'plan-after-reset-without-new-Y');
 answer:=public.confirm_plan_draft_atomic(u,(d->>'id')::uuid,1,NULL,'plan-after-reset-without-new-Y-key');
 RESET ROLE;
 proof:=c59s17d_fixture.state(u);
 IF answer->>'status' IS DISTINCT FROM 'confirmed'
  OR NOT EXISTS(SELECT 1 FROM public.plan_drafts pd JOIN public.training_plans tp ON tp.id=pd.confirmed_plan_id AND tp.user_id=pd.user_id
      WHERE pd.id=(d->>'id')::uuid AND pd.user_id=u AND pd.status='confirmed' AND tp.id=(answer->>'confirmed_plan_id')::uuid AND tp.active
       AND tp.days_per_week=2 AND tp.valid_until IS NULL AND pd.resolved_at=tp.generated_at)
  OR (proof-ARRAY['public.training_plans','public.plan_drafts']) IS DISTINCT FROM (after_reset-ARRAY['public.training_plans','public.plan_drafts'])
  OR proof->'private.strength_week_source_versions' IS DISTINCT FROM after_reset->'private.strength_week_source_versions'
  OR proof->'private.mobile_signup_strength_completion_receipts' IS DISTINCT FROM after_reset->'private.mobile_signup_strength_completion_receipts'
  OR proof->'private.strength_week_scopes' IS DISTINCT FROM after_reset->'private.strength_week_scopes'
  OR proof->'private.workout_strength_authority_epochs' IS DISTINCT FROM after_reset->'private.workout_strength_authority_epochs'
  OR proof->'private.workout_strength_lifecycles' IS DISTINCT FROM after_reset->'private.workout_strength_lifecycles'
  OR (SELECT last_value FROM private.strength_week_source_versions_source_order_seq)<>sequence_before+1
 THEN RAISE EXCEPTION 'C59PLAN_AFTER_RESET_ADOPTED_OLD_Y'; END IF;
 SET LOCAL ROLE service_role;
 replayed:=public.confirm_plan_draft_atomic(u,(original_answer->>'id')::uuid,99,clock_timestamp()+interval '99 days','plan-old-replay-after-reset');
 RESET ROLE;
 IF replayed IS DISTINCT FROM (original_answer||'{"already_confirmed":true}'::jsonb)
  OR c59s17d_fixture.state(u) IS DISTINCT FROM proof
  OR (SELECT last_value FROM private.strength_week_source_versions_source_order_seq)<>sequence_before+1
 THEN RAISE EXCEPTION 'C59PLAN_RESET_REPLAY_RENEWED_ORIGIN'; END IF;
 RAISE NOTICE 'C59PLAN_RESET_RETAINS_PROOFS_WITHOUT_ADOPTING_OLD_Y';
END $plan_after_lifecycle_and_reset$;
RESET ROLE;
