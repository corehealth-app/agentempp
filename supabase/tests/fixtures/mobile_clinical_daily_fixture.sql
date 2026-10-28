\ir mobile_clinical_full_fixture.sql

-- Confirm a real private FULL with synthetic server-calculated effects. This
-- fixture does not prove the subsequent BFF calculator or remote activation.
CREATE FUNCTION m3b_cycle_test.scheduled(n integer,kind text,at_time timestamptz)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid;s jsonb;cycle uuid;context jsonb;preview jsonb;form jsonb;intent jsonb;proposal jsonb;plan jsonb;
 phase text:=CASE kind WHEN 'gain_exit' THEN 'ganho_massa' ELSE 'recomposicao' END;
 after_phase text:=CASE kind WHEN 'gain_exit' THEN 'ganho_massa' ELSE 'manutencao' END;
 day date:=(at_time AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 a:=m3b_cycle_test.seed(n,at_time-interval '6 days');
 UPDATE public.user_profiles SET sex='masculino',birth_date='1990-01-01',height_cm=180,weight_kg=80,
  body_fat_percent=18,activity_level='moderado',training_frequency=4,hunger_level='moderada',
  current_protocol=phase::public.protocol_enum,deficit_level=CASE WHEN phase='recomposicao' THEN 500 END WHERE user_id=a;
 -- A frozen schedule starts from an actual stored target. The former fixture
 -- supplied beforeKcal while no snapshot existed and did not prove that input.
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,day,CASE kind WHEN 'gain_exit' THEN 2700 ELSE 2000 END,144,phase::public.protocol_enum);
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',at_time);cycle:=(s#>>'{cycle,id}')::uuid;
 plan:=jsonb_build_object('version',1,'kind',kind,'state','running','startDate',day,
  'startTargetKcal',CASE kind WHEN 'gain_exit' THEN 2700 ELSE 2000 END,'maintenanceTargetKcal',2400,
  'plannedEndDate',CASE kind WHEN 'gain_exit' THEN day+14 ELSE day+21 END);
 form:=jsonb_build_object('version',1,'phase',phase,'kind','EARLY_FULL','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',NULL,'strengthSessions',4,'hunger',NULL,'energy',NULL,'adherence',NULL,
   'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,'healthCheck',jsonb_build_object('kind','none'),
   'professionalConversationConfirmed',NULL,'activity',jsonb_build_object('otherExerciseType',NULL,'otherExerciseDays',NULL,
    'sessionMinutes',NULL,'sessionIntensity',NULL,'mostlySitting',NULL,'activityLevel','moderado','activityLevelConfirmed',true)));
 intent:='{"principalConfirmed":true}';
 proposal:=jsonb_build_object('version',1,'principal',CASE kind WHEN 'gain_exit' THEN 'gain_exit' ELSE 'recomposition_transition' END,
  'clearHold',false,'profile',jsonb_build_object('current_protocol',after_phase,'deficit_level',NULL,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',CASE kind WHEN 'gain_exit' THEN 2700 ELSE 2000 END,'beforeProtein',144,
   'afterKcal',CASE kind WHEN 'gain_exit' THEN 2600 ELSE 2100 END,'afterProtein',144,'formulaAfterKcal',2400),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps',CASE WHEN kind='gain_exit' THEN NULL ELSE '[]'::jsonb END,
   'schedule',plan,'maintenanceSince',NULL));
 context:=private.capture_mobile_clinical_context_at(a,'EARLY_FULL',cycle,at_time);
 preview:=private.prepare_mobile_clinical_preview_at(a,'EARLY_FULL',cycle,gen_random_uuid(),context->>'context_hash',form,intent,proposal,at_time);
 s:=private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),form,intent,proposal,at_time);
 RETURN jsonb_build_object('user',a,'source_review',s->'review_id','schedule',plan,'result',s);
END $$;
CREATE FUNCTION m3b_cycle_test.closed_neutral(n integer) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c jsonb;a uuid;context jsonb;preview jsonb;form jsonb;proposal jsonb;result jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.scheduled(n,'recomp_to_maintenance',clock_timestamp()-interval '6 days');a:=(c->>'user')::uuid;
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,day_closed,closed_at)
  VALUES(a,day,2100,144,'manutencao',true,clock_timestamp());
 form:=jsonb_build_object('version',1,'phase','manutencao','kind','SAFETY','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',NULL,'strengthSessions',4,'hunger',NULL,'energy',NULL,'adherence',NULL,
   'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,'healthCheck',NULL,
   'professionalConversationConfirmed',NULL,'activity',jsonb_build_object('otherExerciseType',NULL,'otherExerciseDays',NULL,
    'sessionMinutes',NULL,'sessionIntensity',NULL,'mostlySitting',NULL,'activityLevel','moderado','activityLevelConfirmed',true)));
 proposal:=jsonb_build_object('version',1,'principal','neutral_exit','clearHold',false,
  'profile',jsonb_build_object('current_protocol','manutencao','deficit_level',NULL,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',2100,'beforeProtein',144,'afterKcal',2400,'afterProtein',144,'formulaAfterKcal',2400),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps','[]'::jsonb,'schedule',NULL,'maintenanceSince',NULL));
 context:=private.capture_mobile_clinical_context_at(a,'SAFETY',NULL,NULL);
 preview:=private.prepare_mobile_clinical_preview_at(a,'SAFETY',NULL,gen_random_uuid(),context->>'context_hash',form,
  '{"principalConfirmed":true}',proposal,NULL);
 result:=private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),form,
  '{"principalConfirmed":true}',proposal,NULL);
 RETURN jsonb_build_object('user',a,'result',result);
END $$;
CREATE FUNCTION m3b_cycle_test.daily_calculation(formula integer DEFAULT 2400,maintenance integer DEFAULT 2400)
RETURNS jsonb LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('version',1,'formulaKcal',formula,'maintenanceKcal',maintenance,
  'sedentaryKcal',1800,'proteinTarget',144,'maintenanceProteinTarget',144)
$$;
CREATE FUNCTION m3b_cycle_test.daily_apply(a uuid,operation uuid,calculation jsonb,at_time timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE context jsonb;
BEGIN
 context:=private.capture_mobile_clinical_context_at(a,'APPLICATION',NULL,at_time);
 RETURN private.apply_mobile_clinical_daily_at(a,operation,context->>'context_hash',calculation,at_time);
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
