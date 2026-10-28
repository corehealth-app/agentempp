\ir mobile_clinical_full_fixture.sql
-- Typed transport fixture only. Formula values here are synthetic; the actual
-- evaluator is qualified separately through the BFF bridge.
CREATE FUNCTION m3b_cycle_test.command_input(c jsonb,preference jsonb DEFAULT 'null'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE context jsonb;candidate jsonb;form jsonb;intent jsonb;proposal jsonb;command jsonb;
BEGIN
 context:=public.get_mobile_clinical_full_context((c->>'user')::uuid,'REGULAR',(c->>'cycle')::uuid);
 candidate:=context#>'{facts,protocol_authority,body_fat_candidate}';
 form:=jsonb_build_object('version',1,'phase','recomposicao','kind','REGULAR','activityPurpose','normal','preference',preference,
  'answers',jsonb_build_object('weightKg',84,'strengthSessions',4,'hunger','moderada','energy','boa',
  'adherence','bem_consistente','strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,
  'activity',NULL,'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',NULL));
 intent:=jsonb_build_object('principalConfirmed',false,'bodyFat',jsonb_build_object('confirmed',true,
  'sourceHash',candidate->'source_hash','meanHundredths',candidate->'mean_hundredths'));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',false,
  'profile',jsonb_build_object('current_protocol','recomposicao','deficit_level',500,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',1700,'beforeProtein',120,'afterKcal',1599,'afterProtein',126,'formulaAfterKcal',1599),
  'episode',jsonb_build_object('difficultyCount',0,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL));
 command:=jsonb_build_object('form',form,'choice',jsonb_build_object('kind','keep'),'measureConfirmed',false,'bodyFat',intent->'bodyFat');
 RETURN jsonb_build_object('context',context,'form',form,'intent',intent,'proposal',proposal,'command',command);
END $$;
REVOKE ALL ON FUNCTION m3b_cycle_test.command_input(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
