-- Only synthetic private SQL. FULL target effects below are fixtures, not the
-- future BFF clinical evaluator. No signup preference route is activated here.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_reevaluation_cycle_fixture.sql
SELECT m3b_cycle_test.ok(to_regclass('private.mobile_clinical_preference_receipts') IS NOT NULL,
 'separate n21 preference authority exists');
SELECT m3b_cycle_test.ok(private.mobile_clinical_preference_valid('{"action":"change","value":{"kind":"weight","kg":59.94}}',NULL,180)
 AND private.mobile_clinical_preference_valid('{"action":"change","value":{"kind":"weight","kg":61.95465}}',NULL,183)
 AND NOT private.mobile_clinical_preference_valid('{"action":"change","value":{"kind":"weight","kg":59.93999}}',NULL,180),
 'decimal BMI18.5 equality is accepted and the value strictly below is refused');
SELECT m3b_cycle_test.ok(NOT private.mobile_clinical_preference_valid('{"action":"change","value":{"kind":"body_fat","percent":11.99}}','feminino',NULL)
 AND NOT coalesce(private.mobile_clinical_preference_valid('{"action":"change","value":{"kind":"body_fat","percent":11}}',NULL,NULL),false)
 AND private.mobile_clinical_preference_valid('{"action":"change","value":{"kind":"body_fat","percent":12}}',NULL,NULL),
 'only the dependent sex guard closes a 10-12 percent preference');
SELECT m3b_cycle_test.ok(NOT private.mobile_clinical_preference_valid('{"action":"change","value":{"kind":"weight","kg":75}}',NULL,'NaN'::numeric)
 AND private.mobile_clinical_preference_valid('{"action":"change","value":{"kind":"body_fat","percent":11}}',NULL,NULL) IS FALSE,
 'nonfinite profile context and missing dependent evidence cannot produce a favorable NULL');
CREATE FUNCTION m3b_cycle_test.preference_prepare(a uuid,preference jsonb,weight numeric DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE started jsonb;cycle uuid;context jsonb;preview jsonb;form jsonb;proposal jsonb;
BEGIN
 started:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);
 cycle:=(started#>>'{cycle,id}')::uuid;
 form:=jsonb_build_object('version',1,'kind','EARLY_FULL','phase','recomposicao','activityPurpose','normal',
  'preference',preference,'answers',jsonb_build_object('weightKg',weight,'strengthSessions',NULL,'hunger',NULL,
  'energy',NULL,'adherence',NULL,'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,
  'activity',NULL,'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',NULL));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',false,
  'profile',jsonb_build_object('current_protocol','recomposicao','deficit_level',500,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',1700,'beforeProtein',120,'afterKcal',1700,'afterProtein',120,'formulaAfterKcal',1700),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL));
 context:=private.capture_mobile_clinical_context_at(a,'EARLY_FULL',cycle,NULL);
 preview:=private.prepare_mobile_clinical_preview_at(a,'EARLY_FULL',cycle,gen_random_uuid(),context->>'context_hash',
  form,'{"principalConfirmed":false}',proposal,NULL);
 RETURN jsonb_build_object('preview',preview,'form',form,'intent',jsonb_build_object('principalConfirmed',false),'proposal',proposal);
END $$;
CREATE FUNCTION m3b_cycle_test.preference_confirm(a uuid,request jsonb,operation uuid DEFAULT gen_random_uuid()) RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,operation,
  request->'form',request->'intent',request->'proposal',NULL)
$$;
CREATE FUNCTION m3b_cycle_test.preference_fail() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'synthetic_preference_write_failure' USING ERRCODE='40001'; END $$;
DO $$
DECLARE a uuid;other_id uuid;request jsonb;reply jsonb;replay jsonb;origin jsonb;current_preference jsonb;
 generation_id uuid;epoch_id uuid;key uuid:=gen_random_uuid();first_request jsonb;before_profile jsonb;
 invalid jsonb;prior_fulls integer;prior_preferences integer;
BEGIN
 a:=m3b_cycle_test.seed(1920,clock_timestamp()-interval '6 days');
 other_id:=m3b_cycle_test.seed(1921,clock_timestamp()-interval '6 days');
 UPDATE public.user_profiles SET sex='masculino',height_cm=200,weight_kg=80,body_fat_percent=NULL,
  current_protocol='recomposicao',deficit_level=500,activity_level='moderado',training_frequency=4,
  hunger_level='moderada',goal_type='BF',goal_value=10 WHERE user_id=a;
 SELECT admission_id,epoch INTO generation_id,epoch_id FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 SELECT to_jsonb(p) INTO before_profile FROM public.user_profiles p WHERE user_id=a;
 request:=m3b_cycle_test.preference_prepare(a,'{"action":"change","value":{"kind":"weight","kg":75}}');first_request:=request;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_preference_receipts WHERE user_id=a)
  AND private.mobile_clinical_preference_current(a,generation_id,epoch_id) IS NULL,
  'preparing hashes does not save a preference or ordinary answers');
 reply:=m3b_cycle_test.preference_confirm(a,request,key);
 PERFORM m3b_cycle_test.ok(reply#>>'{preference,status}'='saved' AND reply#>>'{preference,value,kind}'='weight'
  AND (reply#>>'{preference,value,kg}')::numeric=75,'conclusion returns the separately saved preference');
 current_preference:=private.mobile_clinical_preference_current(a,generation_id,epoch_id);
 PERFORM m3b_cycle_test.ok(current_preference#>>'{value,kg}'='75' AND current_preference->>'user_id'=a::text
  AND current_preference->>'signup_generation'=generation_id::text AND current_preference->>'signup_epoch'=epoch_id::text,
  'current preference is bound to the real owner generation and epoch');
 PERFORM m3b_cycle_test.ok(private.capture_mobile_clinical_context_at(a,'ROUTINE_REVIEW',NULL,NULL)
  #>'{facts,protocol_authority,preference}'=current_preference,'same clinical context hash includes current preference authority');
 PERFORM m3b_cycle_test.ok((SELECT goal_type::text='BF' AND goal_value=10 AND current_protocol::text='recomposicao'
  AND deficit_level=500 FROM public.user_profiles WHERE user_id=a)
  AND reply#>'{targets}'=first_request#>'{proposal,targets}',
  'preference never writes active goal phase deficit or calorie/protein effects');
 replay:=m3b_cycle_test.preference_confirm(a,first_request,key);
 PERFORM m3b_cycle_test.ok(replay=reply AND (SELECT count(*)=1 FROM private.mobile_clinical_preference_receipts WHERE user_id=a),
  'same conclusion replay does not create a second preference receipt');
 PERFORM m3b_cycle_test.ok(private.mobile_clinical_preference_current(other_id,generation_id,epoch_id) IS NULL
  AND private.mobile_clinical_preference_current(a,m3b_cycle_test.uid(1922),epoch_id) IS NULL,
  'another owner or generation cannot borrow this preference');
 SELECT to_jsonb(p) INTO before_profile FROM public.user_profiles p WHERE user_id=a;
 prior_fulls:=(SELECT count(*) FROM private.mobile_clinical_full_receipts WHERE user_id=a);
 prior_preferences:=(SELECT count(*) FROM private.mobile_clinical_preference_receipts WHERE user_id=a);
 request:=m3b_cycle_test.preference_prepare(a,'{"action":"change","value":{"kind":"follow_app"}}',81);
 CREATE TRIGGER synthetic_preference_failure BEFORE INSERT ON private.mobile_clinical_preference_receipts
  FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.preference_fail();
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.preference_confirm(%L,%L::jsonb)',a,request),
  '40001','preference write failure rolls back the already inserted FULL and weight effects');
 DROP TRIGGER synthetic_preference_failure ON private.mobile_clinical_preference_receipts;
 PERFORM m3b_cycle_test.ok(before_profile=(SELECT to_jsonb(p) FROM public.user_profiles p WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_weight_measurements WHERE user_id=a)
  AND (SELECT count(*)=prior_fulls FROM private.mobile_clinical_full_receipts WHERE user_id=a)
  AND (SELECT count(*)=prior_preferences FROM private.mobile_clinical_preference_receipts WHERE user_id=a)
  AND private.mobile_clinical_preference_current(a,generation_id,epoch_id)=current_preference,
  'late failure leaves profile measurement FULL and preference pointer exactly unchanged');
 prior_fulls:=(SELECT count(*) FROM private.mobile_clinical_full_receipts WHERE user_id=a);
 prior_preferences:=(SELECT count(*) FROM private.mobile_clinical_preference_receipts WHERE user_id=a);
 FOREACH invalid IN ARRAY ARRAY['{"action":"change","value":{"kind":"weight","kg":73.99}}'::jsonb,
  '{"action":"change","value":{"kind":"body_fat","percent":9.99}}'::jsonb,
  '{"action":"keep","goal_type":"peso_kg"}'::jsonb] LOOP
  request:=m3b_cycle_test.preference_prepare(a,invalid);
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.preference_confirm(%L,%L::jsonb)',a,request),
   '22023','raw disallowed preference is refused before any FULL or preference write');
 END LOOP;
 PERFORM m3b_cycle_test.ok((SELECT count(*)=prior_fulls FROM private.mobile_clinical_full_receipts WHERE user_id=a)
  AND (SELECT count(*)=prior_preferences FROM private.mobile_clinical_preference_receipts WHERE user_id=a),
  'rejected values do not survive in FULL forms or preference receipts');
 -- The BFF normalizer removes a refused optional value. This safe conclusion
 -- demonstrates the accepted SQL path without persisting the rejected value.
 request:=m3b_cycle_test.preference_prepare(a,NULL);
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.preference_confirm(a,request)#>>'{preference,status}'='unchanged'
  AND private.mobile_clinical_preference_current(a,generation_id,epoch_id)=current_preference,
  'dropping a refused optional value lets the rest of the review conclude');
 request:=m3b_cycle_test.preference_prepare(a,'{"action":"skip"}');
 PERFORM m3b_cycle_test.preference_confirm(a,request);
 PERFORM m3b_cycle_test.ok(private.mobile_clinical_preference_current(a,generation_id,epoch_id)=current_preference,
  'skip preserves the preference without moving its head');
 request:=m3b_cycle_test.preference_prepare(a,'{"action":"remove"}');
 reply:=m3b_cycle_test.preference_confirm(a,request);
 PERFORM m3b_cycle_test.ok(reply#>>'{preference,status}'='removed'
  AND private.mobile_clinical_preference_current(a,generation_id,epoch_id)->'value'='null'::jsonb,
  'remove affects only preference and preserves historical receipts');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_preference_receipts SET value=NULL WHERE user_id=%L',a),
  '55000','preference receipts are immutable');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM m3b_cycle_test.ok(private.mobile_clinical_preference_current(a,generation_id,epoch_id) IS NULL,
  'a reset does not relabel the old preference as current');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.preference_confirm(a,first_request,key)=replay
  AND private.mobile_clinical_preference_current(a,generation_id,epoch_id) IS NULL,
  'old FULL acknowledgement after reset cannot restore preference effects');
 PERFORM m3b_cycle_test.ok((SELECT email LIKE 'm3b-cycle-%@example.invalid' FROM public.users WHERE id=a),
  'purge target is the exact synthetic fixture owner');
 DELETE FROM private.mobile_reevaluation_cycles WHERE user_id=a;
 DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 DELETE FROM public.users WHERE id=a;
 SET CONSTRAINTS ALL IMMEDIATE;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_preference_receipts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_preference_heads WHERE user_id=a),
  'actual synthetic owner deletion cascades preference receipts and pointer without bypassing immutable triggers');
END $$;
SELECT m3b_cycle_test.ok(NOT has_table_privilege(role,'private.mobile_clinical_preference_receipts','SELECT,INSERT,UPDATE,DELETE')
 AND NOT has_table_privilege(role,'private.mobile_clinical_preference_heads','SELECT,INSERT,UPDATE,DELETE'),
 role||' has no direct preference access') FROM unnest(ARRAY['anon','authenticated','service_role']) role;
SELECT m3b_cycle_test.ok(NOT has_function_privilege(role,'private.mobile_clinical_preference_current(uuid,uuid,uuid)','EXECUTE')
 AND NOT has_function_privilege(role,'private.mobile_clinical_preference_decision(uuid,uuid,uuid,jsonb)','EXECUTE')
 AND NOT has_function_privilege(role,'private.apply_mobile_clinical_preference(uuid,uuid)','EXECUTE'),
 role||' cannot execute a private preference helper') FROM unnest(ARRAY['anon','authenticated','service_role']) role;
ROLLBACK;
