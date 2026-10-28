-- Actual private atomic writer, synthetic local owners only. No provider/Storage.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_full_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('private.confirm_mobile_clinical_preview_at(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)') IS NOT NULL,
 'typed FULL confirmation writer exists');
CREATE FUNCTION m3b_cycle_test.clinical_request(c jsonb,weight numeric DEFAULT 84,clear_hold boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE context jsonb;candidate jsonb;form jsonb;intent jsonb;proposal jsonb;preview jsonb;
BEGIN
 context:=private.capture_mobile_clinical_context_at((c->>'user')::uuid,'REGULAR',(c->>'cycle')::uuid,NULL);
 candidate:=context#>'{facts,protocol_authority,body_fat_candidate}';
 form:=jsonb_build_object('version',1,'phase','recomposicao','kind','REGULAR','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',weight,'strengthSessions',4,'hunger','moderada','energy','boa',
   'adherence','bem_consistente','strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,
   'activity',NULL,'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',CASE WHEN clear_hold THEN true ELSE NULL END));
 intent:=jsonb_build_object('principalConfirmed',false,'bodyFat',jsonb_build_object('confirmed',true,
  'sourceHash',candidate->'source_hash','meanHundredths',candidate->'mean_hundredths'));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',clear_hold,
  'profile',jsonb_build_object('current_protocol','recomposicao','deficit_level',500,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',context#>'{facts,day,calories_target}',
   'beforeProtein',context#>'{facts,day,protein_target}','afterKcal',1599,'afterProtein',126,'formulaAfterKcal',1599),
  'episode',jsonb_build_object('difficultyCount',0,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL));
 preview:=private.prepare_mobile_clinical_preview_at((c->>'user')::uuid,'REGULAR',(c->>'cycle')::uuid,
  gen_random_uuid(),context->>'context_hash',form,intent,proposal,NULL);
 RETURN jsonb_build_object('preview',preview,'form',form,'intent',intent,'proposal',proposal,'context',context);
END $$;
DO $$
DECLARE c jsonb;a uuid;cycle uuid;request jsonb;result jsonb;replay jsonb;operation uuid:=gen_random_uuid();
 observed timestamptz;day date;closed_before jsonb;before_rows jsonb;counter integer;
BEGIN
 c:=m3b_cycle_test.clinical_photos(1500);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
 day:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,
  calories_consumed,exercise_calories,day_closed) VALUES(a,day,1700,120,'recomposicao',200,50,false);
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,
  calories_consumed,exercise_calories,day_closed,closed_at) VALUES(a,day-1,1650,120,'recomposicao',1800,300,true,clock_timestamp());
 SELECT to_jsonb(s) INTO closed_before FROM public.daily_snapshots s WHERE user_id=a AND date=day-1;
 request:=m3b_cycle_test.clinical_request(c);
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,operation,
  request->'form',request->'intent',request->'proposal',NULL);
 observed:=(result->>'completed_at')::timestamptz;
 PERFORM m3b_cycle_test.ok(result->>'status'='confirmed' AND result->>'kind'='REGULAR',
  'actual FULL writer confirms a bound preview');
 PERFORM m3b_cycle_test.ok((SELECT weight_kg=84 AND body_fat_percent=24 AND weight_instant_source='recorded'
  AND body_fat_measured_at=observed FROM public.user_profiles WHERE user_id=a),
  'FULL stores reported weight and explicitly accepted three photo mean');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(weight_kg=84 AND instant_source='recorded' AND measured_at=observed)
  FROM private.mobile_weight_measurements WHERE user_id=a),'FULL creates genuine recorded weight, no fabricated measured instant');
 PERFORM m3b_cycle_test.ok((SELECT calories_target=1599 AND protein_target=126 AND calories_consumed=200
  AND exercise_calories=50 AND NOT day_closed FROM public.daily_snapshots WHERE user_id=a AND date=day),
  'open existing target changes atomically, consumption exercise and closure preserved');
 PERFORM m3b_cycle_test.ok(closed_before=(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE user_id=a AND date=day-1),
  'closed day remains byte equivalent');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(entry_origin='legacy_unknown' AND start_weight_kg IS NULL
  AND entry_date IS NULL AND ledger_steps IS NULL) FROM private.mobile_clinical_episode_events WHERE user_id=a),
  'legacy profile never manufactures episode baseline R or zero ledger');
 PERFORM m3b_cycle_test.ok((SELECT status='completed' AND revision=(result->>'cycle_revision')::bigint
  FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle)
  AND (SELECT count(*)=3 AND bool_and(invalidated_reason='completed') FROM private.mobile_reevaluation_photo_assets WHERE user_id=a)
  AND (SELECT manifest_count=3 FROM private.mobile_reevaluation_photo_dispositions WHERE user_id=a),
  'FULL saves final post seal revision and exact three asset cleanup manifest');
 PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)#>>'{clock,base_date}'=day::text
  AND public.get_mobile_reevaluation_cycle(a)#>>'{clock,due_date}'=(day+14)::text
  AND public.get_mobile_reevaluation_cycle(a)->'cycle'='null'::jsonb,
  'typed completed receipt moves base once and closes occurrence');
 before_rows:=m3b_cycle_test.original_state(a);
 replay:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,operation,
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(replay=result AND before_rows=m3b_cycle_test.original_state(a),
  'same operation replay is exact and has no effects');
 replay:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(replay=result AND (SELECT count(*)=1 FROM private.mobile_clinical_full_receipts WHERE user_id=a)
  AND (SELECT count(*)=1 FROM private.mobile_weight_measurements WHERE user_id=a),
  'second operation key for same preview acknowledges original without duplicated clinical facts');
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  request#>>'{preview,preview_id}',operation,jsonb_set(request->'form','{answers,weightKg}','83'),request->'intent',request->'proposal'),
  '40001','same confirmation key rejects changed input');
 PERFORM public.reset_user_conversation_atomic(a,true);before_rows:=m3b_cycle_test.original_state(a);
 replay:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,operation,
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(replay=result AND before_rows=m3b_cycle_test.original_state(a)
  AND (SELECT weight_kg IS NULL AND body_fat_percent IS NULL FROM public.user_profiles WHERE user_id=a),
  'durable FULL replay after reset cannot resurrect old profile or consent');
END $$;
DO $$
DECLARE c jsonb;a uuid;cycle uuid;request jsonb;result jsonb;before_rows jsonb;before_cycle jsonb;
 error_state text;day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.clinical_photos(1501);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,day,1700,120,'recomposicao');
 request:=m3b_cycle_test.clinical_request(c);
 before_rows:=m3b_cycle_test.original_state(a);
 SELECT to_jsonb(x) INTO before_cycle FROM private.mobile_reevaluation_cycles x WHERE cycle_id=cycle;
 EXECUTE 'CREATE FUNCTION m3b_cycle_test.fail_clinical_episode() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''synthetic clinical rollback''; END $f$';
 CREATE TRIGGER synthetic_clinical_rollback BEFORE INSERT ON private.mobile_clinical_episode_events
  FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_clinical_episode();
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  request#>>'{preview,preview_id}',gen_random_uuid(),request->'form',request->'intent',request->'proposal'),
  'P0001','failure after clinical and photo writes surfaces without suppression');
 DROP TRIGGER synthetic_clinical_rollback ON private.mobile_clinical_episode_events;
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a)
  AND before_cycle=(SELECT to_jsonb(x) FROM private.mobile_reevaluation_cycles x WHERE cycle_id=cycle),
  'failed conclusion rolls back profile targets weight consent manifest cycle and permits');
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(result->>'status'='confirmed','same unchanged preview succeeds after known rolled back failure');
 -- Actual service-role UPDATE must reach the named fence, not fail merely
 -- because an invoker trigger cannot read its private authority tables.
 BEGIN
  SET LOCAL ROLE service_role;
  UPDATE public.user_profiles SET training_frequency=2 WHERE user_id=a;
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS error_state=RETURNED_SQLSTATE;
 END;
 RESET ROLE;
 PERFORM m3b_cycle_test.ok(error_state='40001','service role completed activity update reaches review fence');
 SET LOCAL ROLE service_role;
 UPDATE public.user_profiles SET body_fat_percent=24 WHERE user_id=a;
 RESET ROLE;
 PERFORM m3b_cycle_test.ok((SELECT review_id IS NULL FROM private.mobile_clinical_body_fat_heads WHERE user_id=a)
  AND (SELECT count(*)=1 FROM private.mobile_clinical_body_fat_receipts WHERE user_id=a),
  'same manual BF write invalidates current photo origin but preserves immutable numeric receipt');
END $$;
DO $$
DECLARE c jsonb;a uuid;request jsonb;result jsonb;state jsonb;declaration_key uuid:=gen_random_uuid();
 first_receipt jsonb;replay jsonb;before_rows jsonb;
BEGIN
 c:=m3b_cycle_test.clinical_photos(1502);a:=(c->>'user')::uuid;
 UPDATE public.user_profiles SET sex='feminino' WHERE user_id=a;
 first_receipt:=public.declare_mobile_health_risk(a,declaration_key,ARRAY['reduced_intake','professional_diet','pregnant_or_breastfeeding'])->'receipt';
 request:=m3b_cycle_test.clinical_request(c,84,true);
 result:=private.confirm_mobile_clinical_preview_at(a,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  request->'form',request->'intent',request->'proposal',NULL);
 state:=public.get_mobile_health_hold_state(a);
 PERFORM m3b_cycle_test.ok(state->>'hold_active'='false' AND state->>'safety_revision'='2'
  AND result->>'safety_revision'='2' AND (SELECT count(*)=1 FROM private.mobile_clinical_health_clear_receipts WHERE user_id=a),
  'none plus professional declaration clears only through concluded FULL with next safety revision');
 before_rows:=m3b_cycle_test.original_state(a);
 replay:=public.declare_mobile_health_risk(a,declaration_key,ARRAY['reduced_intake','professional_diet','pregnant_or_breastfeeding']);
 PERFORM m3b_cycle_test.ok(replay->'receipt'=first_receipt AND replay->'state'=state
  AND before_rows=m3b_cycle_test.original_state(a),
  'old risk key after actual FULL clear cannot rearm flags or rewrite current state');
 PERFORM m3b_cycle_test.ok(state->>'declared_no_plan'='false' AND state->>'hide_protein'='false' AND state->'items'='[]'::jsonb,
  'actual confirmed clear removes pregnancy and protein presentation effects');
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['professional_diet']);
 state:=public.get_mobile_health_hold_state(a);
 PERFORM m3b_cycle_test.ok(state->>'hold_active'='true' AND state->>'safety_revision'='3'
  AND state->>'hide_protein'='true','new risk after FULL clear sets a later active HOLD');
END $$;
SELECT m3b_cycle_test.ok(to_regprocedure('private.start_mobile_clinical_full_at(uuid,uuid,text,text,timestamptz)') IS NOT NULL,
 'typed early FULL start exists');
SET CONSTRAINTS ALL IMMEDIATE;
SELECT m3b_cycle_test.ok(true,'completed clinical transactions satisfy all actual deferred foreign keys');
ROLLBACK;
