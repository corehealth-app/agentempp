\ir mobile_reevaluation_cycle_fixture.sql

CREATE FUNCTION m3b_cycle_test.close_seed(n integer,p_phase text DEFAULT 'recomposicao',p_deficit integer DEFAULT 500) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid;d date;at_time timestamptz;s uuid;cycle uuid;context jsonb;form jsonb;proposal jsonb;preview jsonb;
BEGIN
 d:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-1;
 IF p_phase IS NULL OR p_phase NOT IN('recomposicao','manutencao','ganho_massa')
  OR (p_phase='recomposicao' AND (p_deficit IS NULL OR p_deficit NOT IN(400,500,600))) THEN
  RAISE EXCEPTION 'invalid_close_fixture';END IF;
 at_time:=d::timestamp AT TIME ZONE 'America/Sao_Paulo';
 a:=m3b_cycle_test.seed(n,at_time-interval '6 days');
 UPDATE public.users SET created_at=clock_timestamp()-interval '40 days' WHERE id=a;
 UPDATE public.user_profiles SET sex='masculino',birth_date='1990-01-01',height_cm=180,
  weight_kg=80,body_fat_percent=NULL,current_protocol=p_phase::public.protocol_enum,deficit_level=CASE WHEN p_phase='recomposicao' THEN p_deficit END,
  activity_level='moderado',training_frequency=4,hunger_level='moderada' WHERE user_id=a;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,water_consumed_ml,current_protocol)
 VALUES(a,d,2000,130,777,p_phase::public.protocol_enum) RETURNING id INTO s;
 -- Explicit historical QA clock + synthetic calculation, through the actual
 -- FULL writer/origin trigger. No direct origin INSERT or invented proof.
 cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',at_time)#>>'{cycle,id}')::uuid;
 context:=private.capture_mobile_clinical_context_at(a,'EARLY_FULL',cycle,at_time);
 form:=jsonb_build_object('version',1,'phase',p_phase,'kind','EARLY_FULL','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',NULL,'strengthSessions',4,'hunger',NULL,'energy',NULL,'adherence',NULL,
   'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,'activity',NULL,
   'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',NULL));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',false,
  'profile',jsonb_build_object('current_protocol',p_phase,'deficit_level',CASE WHEN p_phase='recomposicao' THEN p_deficit END,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',2000,'beforeProtein',130,'afterKcal',2000,'afterProtein',130,'formulaAfterKcal',2000),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL));
 preview:=private.prepare_mobile_clinical_preview_at(a,'EARLY_FULL',cycle,gen_random_uuid(),context->>'context_hash',form,
  '{"principalConfirmed":false,"bodyFat":null}',proposal,at_time);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),form,
  '{"principalConfirmed":false,"bodyFat":null}',proposal,at_time);
 INSERT INTO public.meal_logs(user_id,snapshot_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at)
 VALUES(a,s,'almoco','synthetic close meal',600,1600,100,90,20,(d+time '12:00') AT TIME ZONE 'America/Sao_Paulo');
 RETURN jsonb_build_object('user',a,'date',d,'from',d-10,'snapshot',s,'zone','America/Sao_Paulo');
END $$;
-- A real current FULL changes phase after the historical target was applied.
-- The target numbers are explicit synthetic server calculations, not an
-- evaluator/formula proof; the writer, provenance and current CAS are real.
CREATE FUNCTION m3b_cycle_test.close_switch_to_maintenance(q jsonb) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid:=(q->>'user')::uuid;at_time timestamptz:=clock_timestamp();cycle uuid;
 context jsonb;form jsonb;proposal jsonb;preview jsonb;intent jsonb:='{"principalConfirmed":true,"bodyFat":null}';
BEGIN
 cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',at_time)#>>'{cycle,id}')::uuid;
 context:=private.capture_mobile_clinical_context_at(a,'EARLY_FULL',cycle,at_time);
 form:=jsonb_build_object('version',1,'phase','recomposicao','kind','EARLY_FULL','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',NULL,'strengthSessions',4,'hunger',NULL,'energy',NULL,'adherence',NULL,
   'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,
   'activity',jsonb_build_object('activityLevel','moderado','activityLevelConfirmed',true),
   'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',NULL));
 proposal:=jsonb_build_object('version',1,'principal','phase_maintenance','clearHold',false,
  'profile',jsonb_build_object('current_protocol','manutencao','deficit_level',NULL,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',NULL,'beforeProtein',NULL,'afterKcal',2400,'afterProtein',144,'formulaAfterKcal',2400),
  'episode',jsonb_build_object('difficultyCount',0,'ledgerSteps','[]'::jsonb,'schedule',NULL,
   'maintenanceSince',(at_time AT TIME ZONE 'America/Sao_Paulo')::date));
 preview:=private.prepare_mobile_clinical_preview_at(a,'EARLY_FULL',cycle,gen_random_uuid(),context->>'context_hash',form,intent,proposal,at_time);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),form,intent,proposal,at_time);
END $$;
CREATE FUNCTION m3b_cycle_test.close_effect(q jsonb) RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('version',1,'kind','close','dayStatus','complete','blockCredit',400,
  'dailyBalance',-400,'gap',jsonb_build_array('cafe','jantar'),
  'telemetry',jsonb_build_array(jsonb_build_object('event','daily_closer.completed','properties',jsonb_build_object(
   'snapshot_date',q->'date','calories_consumed',1600,'calories_target',2000,'exercise_calories',0,
   'training_done',false,'day_status','complete','xp_earned',15,'blocks_completed',0,'blocks_completed_delta',0))),
  'fields',jsonb_build_object('calories_consumed',1600,'calories_target',2000,
   'protein_g',100,'protein_target',130,'carbs_g',90,'fat_g',20,'exercise_calories',0,
   'training_done',false,'xp_earned',15,'current_protocol','recomposicao'),
  'progress',jsonb_build_object('xpTotal',15,'level',1,'currentStreak',1,'longestStreak',1,
   'blocksCompleted',0,'deficitBlock',400,'badgesEarned',jsonb_build_array(),'lastActiveDate',q->'date'))
$$;
CREATE FUNCTION m3b_cycle_test.close_capture(q jsonb) RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT private.capture_mobile_clinical_day_close_at((q->>'user')::uuid,(q->>'from')::date,
  (q->>'date')::date,q->>'zone',NULL)
$$;
CREATE FUNCTION m3b_cycle_test.close_apply(q jsonb,c jsonb,k uuid DEFAULT gen_random_uuid(),effect jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT private.apply_mobile_clinical_day_close_at((q->>'user')::uuid,k,(q->>'from')::date,
  (q->>'date')::date,q->>'zone',c->>'context_hash',coalesce(effect,m3b_cycle_test.close_effect(q)),NULL)
$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
