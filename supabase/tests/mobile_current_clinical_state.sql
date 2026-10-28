-- Current read-only clinical capture; synthetic owned SQL and explicit clocks.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_no_plan_fixture.sql
CREATE FUNCTION m3b_cycle_test.clinical_body(patch jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT '{"locale":"pt-BR","timezone":"America/Sao_Paulo","sex":"masculino","birth_date":"1990-01-01","height_cm":180,"weight_kg":80,"body_fat_percent":24,"training_frequency":4}'::jsonb||patch
$$;
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2900,NULL);before_rows jsonb;capture jsonb;token jsonb;epoch uuid;
BEGIN
 before_rows:=m3b_cycle_test.original_state(a);
 capture:=private.capture_mobile_current_clinical_state_at(a,'signup',m3b_cycle_test.clinical_body(),NULL,NULL);
 PERFORM m3b_cycle_test.ok(capture->>'mode'='signup' AND capture->>'user_id'=a::text
  AND capture->>'assessment'='complete' AND capture->'epoch'='null'::jsonb
  AND capture#>>'{phase_origin,kind}'='not_completed' AND capture#>>'{generation_token,onboarding_completed}'='false',
  'signup capture binds current body owner and completion state without minting an epoch');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a)
  AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=a),
  'clinical capture is a read, never epoch observation/admission/claim/write');
 token:=capture->'generation_token';
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_current_clinical_state_at(%L,''signup'',%L,%L,NULL)',a,
  m3b_cycle_test.clinical_body(),jsonb_build_object('generation_token',token||'{"receipt_count":1}'::jsonb)),
  '40001','stale photo receipt count refuses before downstream claim');
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_current_clinical_state_at(%L,''signup'',%L,%L,NULL)',a,
  m3b_cycle_test.clinical_body(),jsonb_build_object('epoch',gen_random_uuid())),
  '40001','unobserved epoch cannot be substituted by the caller');
 UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=a;
 capture:=private.capture_mobile_current_clinical_state_at(a,'signup',m3b_cycle_test.clinical_body(),NULL,NULL);
 PERFORM m3b_cycle_test.ok(capture#>>'{generation_token,onboarding_completed}'='true'
  AND capture#>'{generation_token,onboarding_completed_at}'='null'::jsonb
  AND capture->>'first_completion'='true','true plus NULL remains first completion, never reaccept');
 UPDATE public.user_profiles SET onboarding_completed=false WHERE user_id=a;
 capture:=private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL);
 PERFORM m3b_cycle_test.ok(capture->>'assessment'='incomplete' AND capture->'safety'='null'::jsonb
  AND capture#>'{body,birth_date}'='null'::jsonb AND capture#>'{body,height_cm}'='null'::jsonb
  AND capture->'missing' @> '["birth_date","height_cm","weight_kg"]'::jsonb,
  'incomplete stored legacy fields are explicit, no fabricated body or guard');
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_current_clinical_state_at(%L,''profile'',%L,NULL,NULL)',a,m3b_cycle_test.clinical_body()),
  '22023','profile mode cannot accept a substitute body');
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_current_clinical_state_at(%L,''signup'',%L,NULL,NULL)',a,
  m3b_cycle_test.clinical_body('{"height_cm":"180"}')),'22023','new clinical capture does not coerce numeric strings');
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_current_clinical_state_at(%L,''signup'',%L,NULL,NULL)',a,
  m3b_cycle_test.clinical_body('{"no_plan":true}')),'22023','client safety flags are outside the captured body');
END $$;
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2901,NULL);r jsonb;before_rows jsonb;day date;
BEGIN
 r:=private.capture_mobile_current_clinical_state_at(a,'signup',m3b_cycle_test.clinical_body(
  '{"birth_date":"2008-10-26","timezone":"America/Sao_Paulo"}'),NULL,'2026-10-26T02:59:59.999999Z');
 PERFORM m3b_cycle_test.ok(r->>'date'='2026-10-25' AND r#>>'{safety,no_plan}'='true','civil birthday uses the selected body timezone before local midnight');
 r:=private.capture_mobile_current_clinical_state_at(a,'signup',m3b_cycle_test.clinical_body(
  '{"birth_date":"2008-10-26","timezone":"America/Sao_Paulo"}'),NULL,'2026-10-26T03:00:00.000000Z');
 PERFORM m3b_cycle_test.ok(r->>'date'='2026-10-26' AND r#>>'{safety,no_plan}'='false','age18 changes current guard, not a phase assignment');
 r:=private.capture_mobile_current_clinical_state_at(a,'signup',m3b_cycle_test.clinical_body('{"height_cm":160,"weight_kg":47.36,"body_fat_percent":10.01}'),NULL,NULL);
 PERFORM m3b_cycle_test.ok(r#>>'{safety,loss_guard}'='false','capture preserves exact BMI18.5 and BF above10');
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['professional_diet']);
 r:=private.capture_mobile_current_clinical_state_at(a,'signup',m3b_cycle_test.clinical_body(),NULL,NULL);
 PERFORM m3b_cycle_test.ok(r#>>'{health_state,safety_revision}'='1' AND r#>>'{safety,hold_active}'='true'
  AND r#>>'{safety,hide_protein}'='true','current private health revision, not an old ACK, drives current capture');
END $$;
DO $$
DECLARE signup jsonb;a uuid;started jsonb;cycle uuid;q jsonb;r jsonb;before_rows jsonb;old_hash text;token jsonb;
BEGIN
 signup:=m3b_cycle_test.no_plan_signup(2902);a:=(signup->>'user')::uuid;
 r:=private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL);
 PERFORM m3b_cycle_test.ok(r#>>'{phase_origin,kind}'='confirmed_no_plan'
  AND r->'signup_generation'=r#>'{phase_origin,signupGeneration}' AND r->'epoch'=r#>'{phase_origin,signupEpoch}'
  AND r#>>'{safety,no_plan}'='true','profile capture binds genuine no-plan origin separately from present guard');
 old_hash:=r->>'context_hash';token:=r->'generation_token';
 started:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);
 cycle:=(started#>>'{cycle,id}')::uuid;q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',cycle);
 PERFORM m3b_cycle_test.no_plan_confirm(a,q);
 before_rows:=m3b_cycle_test.original_state(a);
 r:=private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL);
 PERFORM m3b_cycle_test.ok(r#>>'{safety,no_plan}'='false' AND r#>>'{safety,hold_active}'='false'
  AND r#>>'{health_state,safety_revision}'='2' AND r#>>'{phase_origin,kind}'='confirmed_no_plan'
  AND r->>'context_hash'<>old_hash,'real FULL clear refreshes safety but never substitutes the first phase');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'current reader after actual clear writes no state');
 r:=private.capture_mobile_current_clinical_state_at(a,'signup',m3b_cycle_test.clinical_body(),NULL,NULL);
 PERFORM m3b_cycle_test.ok(r->>'first_completion'='false','reaccept eligibility recognizes actual completion timestamp separately from current guard');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_current_clinical_state_at(%L,''signup'',%L,%L,NULL)',a,
  m3b_cycle_test.clinical_body(),jsonb_build_object('generation_token',token)), '40001','reset invalidates the expected profile generation before claim');
END $$;
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2903,clock_timestamp());r jsonb;
BEGIN
 UPDATE public.user_profiles SET birth_date='1990-01-01',height_cm=180,weight_kg=80,body_fat_percent=24 WHERE user_id=a;
 r:=private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL);
 PERFORM m3b_cycle_test.ok(r#>>'{phase_origin,kind}'='legacy_unassigned' AND r#>>'{safety,no_plan}'='false',
  'bare legacy NULL is not reclassified as an A3/A4 no-plan completion');
END $$;
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2932,NULL);before_hash text;stamp timestamptz;
BEGIN
 UPDATE public.user_profiles SET activity_level='moderado',hunger_level='moderada',updated_at=transaction_timestamp() WHERE user_id=a;
 SELECT updated_at INTO stamp FROM public.user_profiles WHERE user_id=a;
 before_hash:=private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL)->>'profile_hash';
 UPDATE public.user_profiles SET activity_level='leve',updated_at=stamp WHERE user_id=a;
 PERFORM m3b_cycle_test.ok((SELECT updated_at=stamp FROM public.user_profiles WHERE user_id=a),
  'actual activity update shares the same timestamp revision in this transaction');
 PERFORM m3b_cycle_test.ok(before_hash<>private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL)->>'profile_hash',
  'current profile binding detects changed activity independently of updated_at');
 before_hash:=private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL)->>'profile_hash';
 UPDATE public.user_profiles SET hunger_level='muita',updated_at=stamp WHERE user_id=a;
 PERFORM m3b_cycle_test.ok((SELECT updated_at=stamp FROM public.user_profiles WHERE user_id=a),
  'actual hunger update shares the same timestamp revision in this transaction');
 PERFORM m3b_cycle_test.ok(before_hash<>private.capture_mobile_current_clinical_state_at(a,'profile',NULL,NULL,NULL)->>'profile_hash',
  'current profile binding detects changed hunger independently of updated_at');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT m3b_cycle_test.ok(true,'read-only capture preserves all actual constraints');
ROLLBACK;
