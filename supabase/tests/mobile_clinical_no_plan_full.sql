-- Actual keyed signup and private FULL writers, local synthetic ROLLBACK only.
-- Explicit future clocks qualify local fortnight/photo boundaries, not live QA.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_no_plan_fixture.sql


DO $$
DECLARE signup jsonb;a uuid;started jsonb;cycle uuid;q jsonb;r jsonb;state jsonb;before_rows jsonb;
 k uuid:=gen_random_uuid();day date;replay jsonb;future_at timestamptz;regular_key uuid:=gen_random_uuid();regular_reply jsonb;
BEGIN
 signup:=m3b_cycle_test.no_plan_signup(2800);a:=(signup->>'user')::uuid;
 PERFORM m3b_cycle_test.ok(signup#>'{completed,objective}'='null'::jsonb
  AND signup#>>'{completed,clinical_safety,no_plan}'='true','genuine keyed no-plan signup, not a synthetic receipt marker');
 started:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);
 cycle:=(started#>>'{cycle,id}')::uuid;
 q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle);
 r:=m3b_cycle_test.no_plan_confirm(a,q,k);
 day:=((r->>'completed_at')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date;
 state:=public.get_mobile_health_hold_state(a);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed' AND state->>'hold_active'='false'
  AND state->>'safety_revision'='2' AND (SELECT count(*)=1 FROM private.mobile_clinical_health_clear_receipts WHERE user_id=a),
  'actual health-only FULL clears current HOLD with typed clear receipt and CAS');
 PERFORM m3b_cycle_test.ok(q#>>'{context,facts,protocol_authority,phase_origin,kind}'='confirmed_no_plan',
  'capture classifies the genuine no-plan origin before hashing');
 PERFORM m3b_cycle_test.ok((SELECT current_protocol IS NULL AND deficit_level IS NULL AND activity_level='moderado'
  AND training_frequency=4 AND hunger_level='moderada' AND weight_kg=81 FROM public.user_profiles WHERE user_id=a),
  'clear does not choose a phase or change routine; optional weight is official');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(weight_kg=81 AND instant_source='recorded')
  FROM private.mobile_weight_measurements WHERE user_id=a),'health-only FULL records exactly one real weight measurement');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a),
  'no phase means no fabricated episode R ledger schedule day target or snapshot');
 PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)#>>'{clock,base_date}'=day::text
  AND public.get_mobile_reevaluation_cycle(a)#>>'{clock,due_date}'=(day+14)::text
  AND (SELECT status='completed' FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle),
  'same actual FULL receipt closes the occurrence and moves the calendar once');
 before_rows:=m3b_cycle_test.original_state(a);
 replay:=m3b_cycle_test.no_plan_confirm(a,q,k);
 PERFORM m3b_cycle_test.ok(replay=r AND before_rows=m3b_cycle_test.original_state(a),
  'exact no-plan FULL replay is effect free after clearing HOLD');
 replay:=private.admit_mobile_signup_health(a,signup->'command');
 PERFORM m3b_cycle_test.ok(replay#>>'{declaration,state,hold_active}'='false' AND before_rows=m3b_cycle_test.original_state(a),
  'old signup risk receipt acknowledges current cleared state without rearming A4');
 PERFORM m3b_cycle_test.throws(format('UPDATE public.user_profiles SET current_protocol=''manutencao'' WHERE user_id=%L',a),
  '40001','clear is not permission for an ordinary writer to invent the first phase');

 future_at:=(r->>'completed_at')::timestamptz+interval '15 days';
 started:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'REGULAR',NULL,future_at);
 cycle:=(started#>>'{cycle,id}')::uuid;
 q:=m3b_cycle_test.no_plan_request(a,'REGULAR',cycle,'{}','{}',future_at);
 PERFORM m3b_cycle_test.no_plan_refuse(a,q,'40001','regular health-only FULL still requires three NEW processed photos',future_at);
 PERFORM m3b_cycle_test.no_plan_photos(a,cycle,future_at);
 q:=m3b_cycle_test.no_plan_request(a,'REGULAR',cycle,'{}','{}',future_at);
 regular_reply:=m3b_cycle_test.no_plan_confirm(a,q,regular_key,future_at);
 PERFORM m3b_cycle_test.ok(regular_reply->>'kind'='REGULAR' AND (regular_reply->>'body_fat_percent')::numeric=24
  AND (SELECT count(*)=3 AND bool_and(invalidated_reason='completed') FROM private.mobile_reevaluation_photo_assets WHERE user_id=a)
  AND (SELECT manifest_count=3 FROM private.mobile_reevaluation_photo_dispositions WHERE user_id=a),
  'actual regular photo allocation processing mean seal and manifest remain common');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=2 AND count(previous_full_id)=1 FROM private.mobile_clinical_full_receipts WHERE user_id=a)
  AND private.mobile_reevaluation_context_at(a,future_at)#>>'{clock,base_date}'=(future_at AT TIME ZONE 'America/Sao_Paulo')::date::text
  AND (SELECT current_protocol IS NULL AND deficit_level IS NULL AND body_fat_percent=24 FROM public.user_profiles WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a),
  'second real FULL keeps no-plan, numeric BF provenance and chained calendar without clinical targets');
 PERFORM public.reset_user_conversation_atomic(a,true);before_rows:=m3b_cycle_test.original_state(a);
 replay:=m3b_cycle_test.no_plan_confirm(a,q,regular_key);
 PERFORM m3b_cycle_test.ok(replay=regular_reply AND before_rows=m3b_cycle_test.original_state(a)
  AND (SELECT current_protocol IS NULL AND weight_kg IS NULL AND body_fat_percent IS NULL FROM public.user_profiles WHERE user_id=a),
  'original no-plan FULL acknowledgement after reset never resurrects photos profile or health');
END $$;

DO $$
DECLARE signup jsonb;a uuid;cycle uuid;q jsonb;patch jsonb;form jsonb;profile jsonb;state jsonb;
BEGIN
 signup:=m3b_cycle_test.no_plan_signup(2801);a:=(signup->>'user')::uuid;
 cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>>'{cycle,id}')::uuid;
 q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle);
 form:=q->'form';profile:=q#>'{proposal,profile}';
 FOREACH patch IN ARRAY ARRAY[
  jsonb_build_object('profile',profile||'{"current_protocol":"manutencao"}'::jsonb),
  jsonb_build_object('profile',profile||'{"deficit_level":500}'::jsonb),
  jsonb_build_object('profile',profile||'{"training_frequency":3}'::jsonb),
  jsonb_build_object('profile',profile||'{"hunger_level":"muita"}'::jsonb),
  '{"targets":{"beforeKcal":null,"beforeProtein":null,"afterKcal":1800,"afterProtein":null,"formulaAfterKcal":null}}'::jsonb,
  '{"episode":{"difficultyCount":0,"ledgerSteps":null,"schedule":null,"maintenanceSince":null}}'::jsonb,
  '{"episode":{"difficultyCount":null,"ledgerSteps":[],"schedule":null,"maintenanceSince":null}}'::jsonb
 ] LOOP
  q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle,'{}',patch);
  PERFORM m3b_cycle_test.no_plan_refuse(a,q,'22023','health-only forbids substituted phase targets routine or episode '||patch::text);
 END LOOP;
 FOREACH patch IN ARRAY ARRAY[
  jsonb_build_object('answers',(form->'answers')||'{"strengthSessions":4}'::jsonb),
  jsonb_build_object('answers',(form->'answers')||'{"hunger":"moderada"}'::jsonb),
  jsonb_build_object('answers',(form->'answers')||'{"extra":true}'::jsonb),
  jsonb_build_object('answers',(form->'answers')||'{"weightKg":"81"}'::jsonb),
  jsonb_build_object('answers',(form->'answers')||'{"weightKg":29}'::jsonb),
  jsonb_build_object('answers',(form->'answers')||'{"weightKg":81.001}'::jsonb),
  jsonb_build_object('answers',(form->'answers')||'{"healthCheck":{"kind":"none","items":[]}}'::jsonb),
  jsonb_build_object('answers',(form->'answers')||'{"healthCheck":{"kind":"risks","items":["unknown"]}}'::jsonb),
  '{"preference":{"action":"keep"}}'::jsonb,
  '{"activityPurpose":"end_deficit"}'::jsonb
 ] LOOP
  q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle,patch);
  PERFORM m3b_cycle_test.no_plan_refuse(a,q,'22023','health-only rejects unrelated or malformed answers '||patch::text);
 END LOOP;
 FOREACH patch IN ARRAY ARRAY[jsonb_build_object('signupEpoch',gen_random_uuid()),
  jsonb_build_object('signupGeneration',gen_random_uuid()),jsonb_build_object('completedAt','2026-10-01T00:00:00.000001Z')] LOOP
  q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle,jsonb_build_object('noPlanOrigin',(form->'noPlanOrigin')||patch));
  PERFORM m3b_cycle_test.no_plan_refuse(a,q,'40001','client-like provenance cannot substitute captured origin '||patch::text);
 END LOOP;
 q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle);
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['professional_diet']);
 PERFORM m3b_cycle_test.no_plan_refuse(a,q,'40001','risk after preview wins instead of being cleared by the old form');
 state:=public.get_mobile_health_hold_state(a);
 PERFORM m3b_cycle_test.ok(state->>'hold_active'='true' AND state->>'safety_revision'='2'
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_health_clear_receipts WHERE user_id=a),'stale preview preserves the later risk and has no clear effects');
END $$;

DO $$
DECLARE a uuid;cycle uuid;q jsonb;signup jsonb;form jsonb;answer jsonb;result jsonb;n integer:=2802;day date;
 old_day jsonb;
BEGIN
 -- A legacy NULL has a real calendar anchor, but not the new no-plan marker.
 a:=m3b_cycle_test.seed(n,clock_timestamp());n:=n+1;
 UPDATE public.user_profiles SET birth_date='1990-01-01',sex='feminino',height_cm=180,weight_kg=80,
  body_fat_percent=24,activity_level='moderado',training_frequency=4,hunger_level='moderada' WHERE user_id=a;
 cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>>'{cycle,id}')::uuid;
 q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle);
 PERFORM m3b_cycle_test.ok(q#>>'{context,facts,protocol_authority,phase_origin,kind}'='legacy_unassigned',
  'legacy NULL is explicitly unassigned, not corrupt or declared no-plan');
 PERFORM m3b_cycle_test.no_plan_refuse(a,q,'40001','legacy NULL cannot use forged health-only origin metadata');

 FOREACH answer IN ARRAY ARRAY['{"healthCheck":{"kind":"none"},"professionalConversationConfirmed":false}'::jsonb,
  '{"healthCheck":null,"professionalConversationConfirmed":true}'::jsonb,
  '{"healthCheck":{"kind":"risks","items":["pregnant_or_breastfeeding"]},"professionalConversationConfirmed":true}'::jsonb] LOOP
  signup:=m3b_cycle_test.no_plan_signup(n);n:=n+1;a:=(signup->>'user')::uuid;
  cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>>'{cycle,id}')::uuid;
  q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle);form:=q->'form';
  q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle,jsonb_build_object('answers',(form->'answers')||answer||'{"weightKg":null}'::jsonb));
  result:=m3b_cycle_test.no_plan_confirm(a,q);
  PERFORM m3b_cycle_test.ok(result->>'status'='confirmed' AND public.get_mobile_health_hold_state(a)->>'hold_active'='true'
   AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_health_clear_receipts WHERE user_id=a)
   AND NOT EXISTS(SELECT 1 FROM private.mobile_weight_measurements WHERE user_id=a),
   'none alone opt-out or marked risks never clear HOLD or invent a missing weight');
 END LOOP;

 signup:=m3b_cycle_test.no_plan_signup(n,true);a:=(signup->>'user')::uuid;
 -- A DOB correction lifts A3 but is not permission to create the first phase.
 UPDATE public.user_profiles SET birth_date='1990-01-01' WHERE user_id=a;
 day:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,calories_consumed,exercise_calories)
 VALUES(a,day,1900,120,700,50);
 SELECT to_jsonb(s) INTO old_day FROM public.daily_snapshots s WHERE user_id=a;
 cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>>'{cycle,id}')::uuid;
 q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle);
 EXECUTE 'CREATE FUNCTION m3b_cycle_test.fail_no_plan_full() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''synthetic no-plan rollback''; END $f$';
 CREATE TRIGGER synthetic_no_plan_rollback BEFORE INSERT ON private.mobile_clinical_full_receipts
  FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_no_plan_full();
 PERFORM m3b_cycle_test.no_plan_refuse(a,q,'P0001','late failure rolls back health weight calendar and the FULL receipt together');
 DROP TRIGGER synthetic_no_plan_rollback ON private.mobile_clinical_full_receipts;
 result:=m3b_cycle_test.no_plan_confirm(a,q);
 PERFORM m3b_cycle_test.ok((SELECT current_protocol IS NULL AND deficit_level IS NULL FROM public.user_profiles WHERE user_id=a)
  AND old_day=(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=a),
  'after age/health guard lifts health-only FULL preserves old numeric history without recommending or changing it');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT m3b_cycle_test.ok(true,'health-only receipts satisfy actual deferred foreign keys');
ROLLBACK;
