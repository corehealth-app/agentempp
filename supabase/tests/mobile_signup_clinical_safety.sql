-- Actual signup writer/wrappers. Local synthetic rollback; no clinical UI claim.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_signup_health_fixture.sql
CREATE FUNCTION m3b_cycle_test.clinical_signup_submission(patch jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('name','M3B synthetic QA','locale','pt-BR','country','BR','timezone','America/Sao_Paulo',
  'sex','masculino','birth_date','1990-01-01','height_cm',180,'weight_kg',80,'body_fat_percent',15,
  'objective','manutencao','activity_level','moderado','training_frequency',4,'hunger_level','moderada',
  'wake_time','07:00','bedtime','23:00','food_organization','sim','persona','focus','document_actions',
  (SELECT jsonb_agg(jsonb_build_object('document_key',d.document_key,'version',d.version,'locale',d.locale,
    'content_hash',d.content_hash,'action',d.action_type) ORDER BY d.document_key)
   FROM public.onboarding_legal_documents d WHERE d.id IN(SELECT m3b_cycle_test.uid(n) FROM generate_series(201,204) n)))||patch
$$;
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2600,NULL);before_rows jsonb;
BEGIN
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',a,
  m3b_cycle_test.clinical_signup_submission('{"objective":null}')),'23514','adult without A3/A4 cannot send objective null');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'null-objective refusal preserves profile and legal acts');
END $$;

DO $$
DECLARE a uuid;reply jsonb;submission jsonb;path text;objective text;n integer:=2601;
 minor text:=to_char(((clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-interval '17 years')::date,'YYYY-MM-DD');
 before_rows jsonb;choice jsonb;observation jsonb;admission jsonb;original jsonb;original_submission jsonb;
BEGIN
 FOREACH path IN ARRAY ARRAY['atomic','body_photo_confirmation','cleanup_scope'] LOOP
  a:=m3b_cycle_test.seed(n,NULL);n:=n+1;
  submission:=m3b_cycle_test.clinical_signup_submission(jsonb_build_object('birth_date',minor,'objective',NULL));
  IF path='atomic' THEN reply:=public.complete_mobile_onboarding_atomic(a,submission);
  ELSE EXECUTE format('SELECT public.complete_mobile_onboarding_with_%s(%L,%L,NULL,false,NULL,0)',path,a,submission) INTO reply; END IF;
  PERFORM m3b_cycle_test.ok(reply->'objective'='null'::jsonb AND reply#>>'{clinical_safety,no_plan}'='true'
   AND reply#>>'{clinical_safety,recording_allowed}'='true' AND reply#>>'{clinical_safety,hide_protein}'='true'
   AND (SELECT onboarding_completed AND onboarding_completed_at IS NOT NULL AND current_protocol IS NULL AND deficit_level IS NULL
     AND cycle_start_weight_kg IS NULL FROM public.user_profiles WHERE user_id=a),path||' completes minor signup without invented phase/deficit');
  PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a)
   AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=a)
   AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a),path||' no-plan creates no target/snapshot/episode/R');
  FOREACH objective IN ARRAY ARRAY['recomposicao','manutencao','ganho_massa'] LOOP
   a:=m3b_cycle_test.seed(n,NULL);n:=n+1;
   submission:=m3b_cycle_test.clinical_signup_submission(jsonb_build_object('birth_date',minor,'objective',objective));
   before_rows:=m3b_cycle_test.original_state(a);
   IF path='atomic' THEN
    PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',a,submission),
     '23514',path||' minor cannot start '||objective);
   ELSE
    PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_with_%s(%L,%L,NULL,false,NULL,0)',path,a,submission),
     '23514',path||' minor cannot start '||objective);
   END IF;
   PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),path||' minor refusal preserves all owner rows');
  END LOOP;
 END LOOP;

 a:=m3b_cycle_test.seed(n,NULL);n:=n+1;
 choice:=m3b_cycle_test.signup_health_command(a,gen_random_uuid(),gen_random_uuid());
 PERFORM private.admit_mobile_signup_health(a,choice);
 -- A newer flag must win over the earlier signup receipt's reduced_intake.
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['pregnant_or_breastfeeding']);
 submission:=m3b_cycle_test.clinical_signup_submission('{"sex":"feminino"}');before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',a,submission),
  '23514','newer pregnancy declaration vetoes even maintenance at fresh signup');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'A4 refusal does not conclude/alter ordinary answers');
 reply:=public.complete_mobile_onboarding_atomic(a,submission||'{"objective":null}'::jsonb);
 PERFORM m3b_cycle_test.ok(reply->'objective'='null'::jsonb AND reply#>>'{clinical_safety,no_plan}'='true'
  AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a),'current A4, not old receipt projection, permits only explicit no-plan completion');

 a:=m3b_cycle_test.seed(n,NULL);n:=n+1;
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['appetite_weight_treatment']);
 submission:=m3b_cycle_test.clinical_signup_submission('{"height_cm":160,"weight_kg":90,"body_fat_percent":35}');
 FOREACH objective IN ARRAY ARRAY['recomposicao','ganho_massa'] LOOP
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',a,
   submission||jsonb_build_object('objective',objective)), '23514','HOLD cannot start deficit or surplus even above automatic cut');
 END LOOP;
 reply:=public.complete_mobile_onboarding_atomic(a,submission);
 PERFORM m3b_cycle_test.ok(reply->>'objective'='manutencao' AND reply#>>'{clinical_safety,no_plan}'='false'
  AND reply#>>'{clinical_safety,hold_active}'='true','HOLD permits maintenance only by an explicit choice');

 FOREACH choice IN ARRAY ARRAY[
  '{"height_cm":160,"weight_kg":47.35}', '{"body_fat_percent":10}'
 ]::jsonb[] LOOP
  a:=m3b_cycle_test.seed(n,NULL);n:=n+1;submission:=m3b_cycle_test.clinical_signup_submission(choice||'{"objective":"recomposicao"}'::jsonb);
  before_rows:=m3b_cycle_test.original_state(a);
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',a,submission),
   '23514','A1/A2 forbid loss without assigning a replacement');
  PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'low-weight/fat guard leaves phase/history untouched');
 END LOOP;
 FOREACH choice IN ARRAY ARRAY[
  '{"height_cm":160,"weight_kg":47.36}', '{"body_fat_percent":10.01}'
 ]::jsonb[] LOOP
  a:=m3b_cycle_test.seed(n,NULL);n:=n+1;
  reply:=public.complete_mobile_onboarding_atomic(a,m3b_cycle_test.clinical_signup_submission(choice||'{"objective":"recomposicao"}'::jsonb));
  PERFORM m3b_cycle_test.ok(reply#>>'{clinical_safety,loss_guard}'='false','exact BMI18.5 / BF above10 do not retain a stale guard');
 END LOOP;

 -- Keyed acknowledgement is stable, and no-plan is not a fictitious episode.
 a:=m3b_cycle_test.seed(n,NULL);n:=n+1;
 submission:=m3b_cycle_test.clinical_signup_submission(jsonb_build_object('birth_date',minor,'objective',NULL));
 original_submission:=submission;
 observation:=public.observe_mobile_signup_strength_epoch(a);
 admission:=public.admit_mobile_signup_strength_request(a,'synthetic-no-plan',repeat('f',64),
  (observation#>>'{observation,epoch}')::uuid)->'admission';
 original:=public.complete_mobile_onboarding_keyed(a,submission,'atomic','synthetic-no-plan',repeat('f',64),
  (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
 PERFORM m3b_cycle_test.ok(original->'objective'='null'::jsonb
  AND EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a AND outcome='first_fresh')
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=a),
  'keyed no-plan records signup/frequency proof without manufacturing clinical phase authority');
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('UPDATE public.user_profiles SET current_protocol=''manutencao'' WHERE user_id=%L',a),
  '40001','ordinary profile writer cannot invent a phase after genuine no-plan signup');
 PERFORM m3b_cycle_test.throws(format('UPDATE public.user_profiles SET training_frequency=5 WHERE user_id=%L',a),
  '40001','genuine no-plan account requires structured routine confirmation');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'no-plan write fence preserves ordinary profile state');
 -- A corrected DOB lifts the current age guard but is not a new phase choice.
 UPDATE public.user_profiles SET birth_date='1990-01-01' WHERE user_id=a;
 submission:=submission||'{"birth_date":"1990-01-01"}'::jsonb;
 reply:=public.complete_mobile_onboarding_atomic(a,submission);
 PERFORM m3b_cycle_test.ok(reply->'objective'='null'::jsonb AND reply#>>'{clinical_safety,no_plan}'='false'
  AND reply->>'completed_at'=original->>'completed_at'
  AND (SELECT current_protocol IS NULL FROM public.user_profiles WHERE user_id=a),
  'historical null reaccept after corrected age preserves completion and assigns no phase');
 PERFORM public.reset_user_conversation_atomic(a,true);before_rows:=m3b_cycle_test.original_state(a);
 -- Signup keyed authority intentionally validates epoch before receipt replay;
 -- unlike a health declaration, reset forbids this old completion operation.
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_keyed(%L,%L,''atomic'',%L,%L,%L,%L,NULL,NULL,NULL,NULL)',
  a,original_submission,'synthetic-no-plan',repeat('f',64),admission->>'epoch',admission->>'admissionID'),
  '40001','old-epoch signup completion remains forbidden after reset');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),
  'refused old signup operation cannot recreate phase or ordinary signup answers');
END $$;

DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2690,NULL);s jsonb;before_birthday jsonb;on_birthday jsonb;patch jsonb;
BEGIN
 s:=m3b_cycle_test.clinical_signup_submission('{"birth_date":"2008-10-26"}');
 before_birthday:=private.mobile_signup_clinical_safety_at(a,s,'2026-10-26T02:59:59Z');
 on_birthday:=private.mobile_signup_clinical_safety_at(a,s,'2026-10-26T03:00:00Z');
 PERFORM m3b_cycle_test.ok(before_birthday->>'no_plan'='true' AND on_birthday->>'no_plan'='false'
  AND before_birthday->>'date'='2026-10-25' AND on_birthday->>'date'='2026-10-26',
  'age guard lifts at18 in the selected official civil zone, not UTC date');
 s:=m3b_cycle_test.clinical_signup_submission('{"birth_date":"2008-02-29"}');
 PERFORM m3b_cycle_test.ok((private.mobile_signup_clinical_safety_at(a,s,'2026-02-28T12:00Z')->>'no_plan')='true'
  AND (private.mobile_signup_clinical_safety_at(a,s,'2026-03-01T12:00Z')->>'no_plan')='false',
  'leap birthday matches shared core month/day comparison');
 FOREACH patch IN ARRAY ARRAY['{"objective":false}','{"objective":"unknown"}','{"birth_date":null}']::jsonb[] LOOP
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',a,
   m3b_cycle_test.clinical_signup_submission(patch)), '22023','invalid shape is not a no-plan decision');
 END LOOP;
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',a,
  m3b_cycle_test.clinical_signup_submission()-'objective'), '22023','missing objective differs from explicit JSON null');
END $$;
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2691,clock_timestamp()-interval '6 days');
BEGIN
 UPDATE public.user_profiles SET training_frequency=5 WHERE user_id=a;
 PERFORM m3b_cycle_test.ok((SELECT training_frequency=5 FROM public.user_profiles WHERE user_id=a),
  'NULL legacy profile without a typed no-plan marker is not reclassified by the new fence');
END $$;
ROLLBACK;
