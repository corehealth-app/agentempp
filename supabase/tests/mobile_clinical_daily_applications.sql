BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_daily_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('private.apply_mobile_clinical_daily_at(uuid,uuid,text,jsonb,timestamptz)') IS NOT NULL,
 'separate daily application writer exists');
DO $late_n5$
DECLARE c jsonb;a uuid;context jsonb;calculation jsonb;result jsonb;replay jsonb;k uuid:=gen_random_uuid();
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;closed jsonb;before_rows jsonb;anchor jsonb;
 body text:='SYNTHETIC LOCAL DAILY NEW GENERATION';digest text;fresh jsonb;
BEGIN
 c:=m3b_cycle_test.scheduled(1900,'recomp_to_maintenance',clock_timestamp()-interval '28 days');a:=(c->>'user')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,calories_consumed,exercise_calories)
  VALUES(a,day,2100,144,'manutencao',500,200);
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,day_closed,closed_at,calories_consumed)
  VALUES(a,day-1,2200,144,'manutencao',true,clock_timestamp(),2300);
 SELECT to_jsonb(ds) INTO closed FROM public.daily_snapshots ds WHERE user_id=a AND date=day-1;
 anchor:=public.get_mobile_reevaluation_cycle(a)->'clock';
 context:=private.capture_mobile_clinical_context_at(a,'APPLICATION',NULL,NULL);calculation:=m3b_cycle_test.daily_calculation();
 result:=private.apply_mobile_clinical_daily_at(a,k,context->>'context_hash',calculation,NULL);
 PERFORM m3b_cycle_test.ok(result->>'availability'='applied' AND result->>'state'='completed'
  AND result#>>'{episode,maintenance_since}'=day::text,'late n5 reaches M with actual R today');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM private.mobile_clinical_daily_applications WHERE user_id=a)
  AND (SELECT calories_target=2400 AND protein_target=144 AND calories_consumed=500 AND exercise_calories=200
   FROM public.daily_snapshots WHERE user_id=a AND date=day)
  AND closed=(SELECT to_jsonb(ds) FROM public.daily_snapshots ds WHERE user_id=a AND date=day-1),
  'one late application updates only open targets and preserves closed history and aggregates');
 PERFORM m3b_cycle_test.ok(anchor=public.get_mobile_reevaluation_cycle(a)->'clock'
  AND (SELECT count(*)=1 FROM private.mobile_clinical_full_receipts WHERE user_id=a)
  AND (SELECT count(*)=0 FROM private.mobile_weight_measurements WHERE user_id=a),
  'daily application creates no FULL no calendar movement and no weight measurement');
 before_rows:=m3b_cycle_test.original_state(a);
 replay:=private.apply_mobile_clinical_daily_at(a,k,context->>'context_hash',calculation,NULL);
 PERFORM m3b_cycle_test.ok(replay=result AND before_rows=m3b_cycle_test.original_state(a),'same daily key replays exact original without writes');
 replay:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),calculation);
 PERFORM m3b_cycle_test.ok(replay=result AND (SELECT count(*)=1 FROM private.mobile_clinical_daily_applications WHERE user_id=a),
  'fresh repeated request acknowledges unchanged current application without another tick');
 UPDATE public.daily_snapshots SET calories_consumed=650,exercise_calories=250,updated_at=clock_timestamp() WHERE user_id=a AND date=day;
 replay:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),calculation);
 PERFORM m3b_cycle_test.ok(replay=result AND (SELECT count(*)=1 FROM private.mobile_clinical_daily_applications WHERE user_id=a),
  'consumption and exercise changes do not create another target application');
 replay:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),calculation,clock_timestamp()+interval '1 day');
 PERFORM m3b_cycle_test.ok(replay->>'state'='none' AND replay#>>'{episode,maintenance_since}'=day::text
  AND (SELECT count(*)=2 FROM private.mobile_clinical_daily_applications WHERE user_id=a),
  'next day retires the active plan and preserves the first actual R');
 PERFORM public.reset_user_conversation_atomic(a,true);before_rows:=m3b_cycle_test.original_state(a);
 replay:=private.apply_mobile_clinical_daily_at(a,k,context->>'context_hash',calculation,NULL);
 PERFORM m3b_cycle_test.ok(replay=result AND before_rows=m3b_cycle_test.original_state(a)
  AND (SELECT current_protocol IS NULL FROM public.user_profiles WHERE user_id=a),'daily replay after reset cannot restore old phase target or R');
 PERFORM m3b_cycle_test.throws(format('SELECT private.apply_mobile_clinical_daily_at(%L,%L,%L,%L,NULL)',
  a,gen_random_uuid(),context->>'context_hash',calculation),'40001','old daily context cannot apply after reset');
 digest:=encode(extensions.digest(body,'sha256'),'hex');
 INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
  VALUES(m3b_cycle_test.uid(201),'m3b_local_test','m3b-local-1','pt-BR',body,digest,'synthetic_local_test','acceptance',true,clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_document(m3b_cycle_test.uid(201));
 INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
  VALUES(m3b_cycle_test.uid(202),'m3b-local-1','pt-BR',ARRAY['m3b_local_test'],clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_requirement_set(m3b_cycle_test.uid(202));
 PERFORM m3b_cycle_test.complete_again(a,'daily-after-reset-1900');
 fresh:=private.capture_mobile_clinical_context_at(a,'APPLICATION',NULL,NULL);
 PERFORM m3b_cycle_test.ok(fresh#>'{facts,protocol_authority,daily_application}'='null'::jsonb
  AND fresh#>'{facts,protocol_authority,episode}'='null'::jsonb
  AND fresh#>>'{facts,profile,current_protocol}'='recomposicao'
  AND fresh#>>'{facts,protocol_authority,signup_origin,maintenance_since}' IS NULL,
  'actual fresh signup generation inherits neither old daily head nor old episode R');
 replay:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),calculation);
 PERFORM m3b_cycle_test.ok(replay->>'availability'='applied' AND replay->>'source_kind'='signup'
  AND replay->>'source_signup_id'=fresh#>>'{facts,anchor,signup_generation}' AND replay->>'source_review_id' IS NULL
  AND (SELECT count(*)=2 FROM private.mobile_clinical_daily_applications WHERE user_id=a)
  AND (SELECT count(*)=1 FROM private.mobile_clinical_signup_applications WHERE user_id=a
   AND signup_generation=(fresh#>>'{facts,anchor,signup_generation}')::uuid)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_receipts WHERE user_id=a
   AND signup_generation=(fresh#>>'{facts,anchor,signup_generation}')::uuid)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a
   AND signup_generation=(fresh#>>'{facts,anchor,signup_generation}')::uuid),
  'new genuine signup can establish its first target without inheriting old heads or manufacturing a FULL/event');
 before_rows:=m3b_cycle_test.original_state(a);
 replay:=private.apply_mobile_clinical_daily_at(a,k,context->>'context_hash',calculation,NULL);
 PERFORM m3b_cycle_test.ok(replay=result AND before_rows=m3b_cycle_test.original_state(a),
  'old-generation acknowledgement cannot mutate the new signup');
END $late_n5$;
DO $closed_n18$
DECLARE c jsonb;a uuid;result jsonb;closed jsonb;later timestamptz:=clock_timestamp()+interval '2 days';
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;original_episode uuid;
BEGIN
 c:=m3b_cycle_test.scheduled(1901,'gain_exit',clock_timestamp()-interval '28 days');a:=(c->>'user')::uuid;
 SELECT episode_id INTO original_episode FROM private.mobile_clinical_episode_events WHERE user_id=a;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,day_closed,closed_at,calories_consumed,exercise_calories)
  VALUES(a,day,2600,144,'ganho_massa',true,clock_timestamp(),2500,200);
 SELECT to_jsonb(ds) INTO closed FROM public.daily_snapshots ds WHERE user_id=a AND date=day;
 result:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation(2700,2400));
 PERFORM m3b_cycle_test.ok(result->>'availability'='unavailable' AND result->>'reason'='day_closed'
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_daily_applications WHERE user_id=a)
  AND closed=(SELECT to_jsonb(ds) FROM public.daily_snapshots ds WHERE user_id=a AND date=day),
  'closed day receives no scheduled target no tick and no invented R');
 result:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation(2700,2400),later);
 PERFORM m3b_cycle_test.ok(result->>'state'='completed' AND result#>>'{episode,phase}'='manutencao'
  AND result#>>'{episode,maintenance_since}'=(day+2)::text
  AND (result#>>'{episode,episode_id}')::uuid<>original_episode,'late n18 changes phase and starts genuine maintenance episode with R on application');
 PERFORM m3b_cycle_test.ok((SELECT current_protocol='manutencao' FROM public.user_profiles WHERE user_id=a)
  AND (SELECT count(*)=1 AND bool_and(date=day+2 AND calories_target=2400 AND formula_target=2400)
   FROM private.mobile_clinical_daily_applications WHERE user_id=a)
  AND EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a AND date=day+2 AND calories_target=2400
   AND current_protocol='manutencao' AND NOT day_closed)
  AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a AND date>day AND date<>day+2)
  AND closed=(SELECT to_jsonb(ds) FROM public.daily_snapshots ds WHERE user_id=a AND date=day),
  'n18 materializes only its actual application day, without filling missed days or changing closed history');
END $closed_n18$;
DO $hold_and_clear$
DECLARE c jsonb;a uuid;context jsonb;result jsonb;form jsonb;proposal jsonb;preview jsonb;s jsonb;cycle uuid;
 original_clock jsonb;later timestamptz:=clock_timestamp()+interval '8 days';
BEGIN
 c:=m3b_cycle_test.scheduled(1902,'recomp_to_maintenance',clock_timestamp()-interval '6 days');a:=(c->>'user')::uuid;
 context:=private.capture_mobile_clinical_context_at(a,'APPLICATION',NULL,NULL);
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 PERFORM m3b_cycle_test.throws(format('SELECT private.apply_mobile_clinical_daily_at(%L,%L,%L,%L,NULL)',a,gen_random_uuid(),
  context->>'context_hash',m3b_cycle_test.daily_calculation()),'40001','new risk makes an earlier daily calculation stale');
 result:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation());
 PERFORM m3b_cycle_test.ok(result->>'state'='suspended' AND result#>>'{episode,schedule,state}'='suspended'
  AND result#>>'{episode,maintenance_since}' IS NULL AND result#>>'{targets,calories_target}'='2100',
  'new HOLD persists suspension at current target without applying a pending step');
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);cycle:=(s#>>'{cycle,id}')::uuid;
 context:=private.capture_mobile_clinical_context_at(a,'EARLY_FULL',cycle,NULL);
 form:=jsonb_build_object('version',1,'phase','manutencao','kind','EARLY_FULL','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',NULL,'strengthSessions',NULL,'hunger',NULL,'energy',NULL,'adherence',NULL,
   'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,'activity',NULL,
   'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',true));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',true,'profile',jsonb_build_object(
  'current_protocol','manutencao','deficit_level',NULL,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',2100,'beforeProtein',144,'afterKcal',2100,'afterProtein',144,'formulaAfterKcal',2400),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps','[]'::jsonb,
   'schedule',jsonb_set(c->'schedule','{state}','"suspended"'),'maintenanceSince',NULL));
 preview:=private.prepare_mobile_clinical_preview_at(a,'EARLY_FULL',cycle,gen_random_uuid(),context->>'context_hash',form,
  '{"principalConfirmed":false}',proposal,NULL);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),form,
  '{"principalConfirmed":false}',proposal,NULL);
 original_clock:=public.get_mobile_reevaluation_cycle(a)->'clock';
 result:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation(),later);
 PERFORM m3b_cycle_test.ok(public.get_mobile_health_hold_state(a)->>'hold_active'='false'
  AND result->>'state'='suspended' AND result#>>'{targets,calories_target}'='2100'
  AND result#>>'{episode,maintenance_since}' IS NULL AND original_clock=public.get_mobile_reevaluation_cycle(a)->'clock',
  'actual FULL clear does not resume suspended schedule or move calendar during a later tick');
END $hold_and_clear$;
DO $limits$
DECLARE c jsonb;a uuid;result jsonb;later timestamptz:=clock_timestamp()+interval '27 days';at_time timestamptz;
 old_context jsonb;new_context jsonb;day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.scheduled(1903,'recomp_to_maintenance',clock_timestamp()-interval '8 days');a:=(c->>'user')::uuid;
 result:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation(2700,2700));
 PERFORM m3b_cycle_test.ok(result#>>'{targets,calories_target}'='2200'
  AND result#>>'{episode,schedule,maintenanceTargetKcal}'='2400' AND result#>>'{episode,maintenance_since}' IS NULL,
  'a higher M today cannot increase the confirmed n5 steps');
 result:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation(2700,2700),later);
 PERFORM m3b_cycle_test.ok(result#>>'{targets,calories_target}'='2400' AND result->'needs_new_confirmation'='true'::jsonb
  AND result#>>'{episode,maintenance_since}' IS NULL,
  'past frozen end with a higher M requires new confirmation and does not extend values or invent R');
 c:=m3b_cycle_test.scheduled(1904,'gain_exit',clock_timestamp()-interval '8 days');a:=(c->>'user')::uuid;
 result:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation(2500,2200));
 PERFORM m3b_cycle_test.ok(result#>>'{targets,calories_target}'='2500' AND result#>>'{targets,formula_target}'='2400'
  AND result#>>'{targets,effective_adjustment}'='100' AND result#>>'{episode,phase}'='ganho_massa',
  'n18 uses frozen M for its target floor and expenditure while the ramp is active');
 c:=m3b_cycle_test.scheduled(1905,'gain_exit',clock_timestamp()-interval '8 days');a:=(c->>'user')::uuid;
 PERFORM public.record_weight_atomic(a,50,'kg',clock_timestamp(),'daily-A1-1905');
 result:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation(2500,2200));
 PERFORM m3b_cycle_test.ok(result->>'state'='suspended' AND result#>>'{targets,calories_target}'='2600'
  AND result#>>'{episode,maintenance_since}' IS NULL,'A1 suspends n18 without reducing the current target or assigning R');
 c:=m3b_cycle_test.scheduled(1906,'recomp_to_maintenance',clock_timestamp()-interval '8 days');a:=(c->>'user')::uuid;
 at_time:=((day+1)::timestamp AT TIME ZONE 'UTC')+interval '2 hours 30 minutes';
 old_context:=private.capture_mobile_clinical_context_at(a,'APPLICATION',NULL,at_time);
 UPDATE public.users SET timezone='Pacific/Kiritimati' WHERE id=a;
 PERFORM m3b_cycle_test.throws(format('SELECT private.apply_mobile_clinical_daily_at(%L,%L,%L,%L,%L)',a,gen_random_uuid(),
  old_context->>'context_hash',m3b_cycle_test.daily_calculation(),at_time),'40001','timezone change invalidates an earlier daily calculation');
 new_context:=private.capture_mobile_clinical_context_at(a,'APPLICATION',NULL,at_time);
 result:=private.apply_mobile_clinical_daily_at(a,gen_random_uuid(),new_context->>'context_hash',m3b_cycle_test.daily_calculation(),at_time);
 PERFORM m3b_cycle_test.ok(result->>'date'=(at_time AT TIME ZONE 'Pacific/Kiritimati')::date::text
  AND result#>>'{episode,schedule,startDate}'=c#>>'{schedule,startDate}'
  AND result#>>'{episode,schedule,plannedEndDate}'=c#>>'{schedule,plannedEndDate}',
  'fresh timezone uses its actual civil date without reinterpreting confirmed schedule dates');
END $limits$;
DO $pending_target$
DECLARE c jsonb;a uuid;result jsonb;new_risk boolean;n integer:=1907;
 later timestamptz:=clock_timestamp()+interval '1 day';day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 FOREACH new_risk IN ARRAY ARRAY[false,true] LOOP
  c:=m3b_cycle_test.closed_neutral(n);n:=n+1;a:=(c->>'user')::uuid;
  PERFORM m3b_cycle_test.ok((SELECT maintenance_since IS NULL FROM private.mobile_clinical_episode_events
   WHERE user_id=a ORDER BY event_no DESC LIMIT 1),'closed neutral exit has not established R');
  IF new_risk THEN PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['professional_diet']); END IF;
  result:=m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation(),later);
  PERFORM m3b_cycle_test.ok(result#>>'{targets,calories_target}'=CASE WHEN new_risk THEN '2100' ELSE '2400' END
   AND (result#>>'{episode,maintenance_since}') IS NOT DISTINCT FROM CASE WHEN new_risk THEN NULL ELSE (day+1)::text END
   AND public.get_mobile_health_hold_state(a)->>'hold_active'='true',
   CASE WHEN new_risk THEN 'new safety revision blocks the unapplied target and preserves actual prior target'
    ELSE 'same safety authority may apply only the previously confirmed direct target and actual R' END);
 END LOOP;
END $pending_target$;
DO $full_preview$
DECLARE c jsonb;a uuid;context jsonb;preview jsonb;before_profile jsonb;code text;message text;
BEGIN
 c:=m3b_cycle_test.scheduled(1909,'recomp_to_maintenance',clock_timestamp()-interval '8 days');a:=(c->>'user')::uuid;
 context:=private.capture_mobile_clinical_context_at(a,'SAFETY',NULL,NULL);
 -- Hash-only acknowledgement is deliberately not a valid clinical proposal.
 -- The stale-context check must precede proposal evaluation at confirmation.
 preview:=private.prepare_mobile_clinical_preview_at(a,'SAFETY',NULL,gen_random_uuid(),context->>'context_hash',
  '{}','{}','{}',NULL);
 SELECT to_jsonb(p) INTO before_profile FROM public.user_profiles p WHERE user_id=a;
 PERFORM m3b_cycle_test.daily_apply(a,gen_random_uuid(),m3b_cycle_test.daily_calculation());
 PERFORM m3b_cycle_test.ok(before_profile=(SELECT to_jsonb(p) FROM public.user_profiles p WHERE user_id=a)
  AND EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a AND NOT day_closed
   AND calories_target=2200 AND protein_target=144),
  'daily application materializes the approved current target without changing profile inputs');
 BEGIN
  PERFORM private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),'{}','{}','{}',NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
 END;
 PERFORM m3b_cycle_test.ok(code='40001' AND message='mobile_clinical_preview_stale',
  'a new daily application head invalidates the previous FULL acknowledgement before proposal evaluation');
END $full_preview$;
DO $private_authority$
DECLARE role_name text;code text;a uuid:=m3b_cycle_test.uid(1902);before_rows jsonb;calculation jsonb;
BEGIN
 calculation:=m3b_cycle_test.daily_calculation();
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_daily_applications SET state=''none'' WHERE user_id=%L',a),
  '55000','daily application evidence is immutable');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_daily_keys WHERE user_id=%L',a),
  '55000','daily operation acknowledgements are immutable');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  code:=NULL;
  BEGIN
   EXECUTE format('SET LOCAL ROLE %I',role_name);
   PERFORM 1 FROM private.mobile_clinical_daily_applications;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  PERFORM m3b_cycle_test.ok(code='42501',role_name||' cannot read private clinical daily journal');
  code:=NULL;
  BEGIN
   EXECUTE format('SET LOCAL ROLE %I',role_name);
   PERFORM private.apply_mobile_clinical_daily_at(a,gen_random_uuid(),repeat('a',64),calculation,NULL);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  PERFORM m3b_cycle_test.ok(code='42501',role_name||' cannot invoke the private application writer');
 END LOOP;
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT private.prepare_mobile_clinical_preview_at(%L,''APPLICATION'',NULL,%L,%L,''{}'',''{}'',''{}'',NULL)',
  a,gen_random_uuid(),repeat('a',64)),'22023','APPLICATION context cannot create a clinical review preview');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'refused application preview writes no clinical evidence');
END $private_authority$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT m3b_cycle_test.ok(true,'daily journal foreign keys satisfy actual final state');
ROLLBACK;
