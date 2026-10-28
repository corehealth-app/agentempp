-- Approved n9/n39 at the actual app signup writer; synthetic local rollback.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_reevaluation_cycle_fixture.sql

CREATE FUNCTION m3b_cycle_test.signup_gain_submission(patch jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('name','M3B synthetic QA','locale','pt-BR','country','BR',
  'timezone','America/Sao_Paulo','sex','masculino','birth_date','1990-01-01',
  'height_cm',180,'weight_kg',80,'body_fat_percent',15,'objective','ganho_massa',
  'activity_level','moderado','training_frequency',3,'hunger_level','moderada',
  'wake_time','07:00','bedtime','23:00','food_organization','sim','persona','focus',
  'document_actions',jsonb_build_array(jsonb_build_object('document_key',d.document_key,
    'version',d.version,'locale',d.locale,'content_hash',d.content_hash,'action',d.action_type))) || patch
 FROM public.onboarding_legal_documents d WHERE d.id=m3b_cycle_test.uid(201)
$$;

DO $$
DECLARE body text:='SYNTHETIC SIGNUP N39'; digest text; owner_id uuid; submission jsonb;
 result jsonb; original jsonb; snapshot jsonb; observation jsonb; admission jsonb; k text;
 path text; i integer:=2100; patch jsonb;
BEGIN
 digest:=encode(extensions.digest(body,'sha256'),'hex');
 INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,
  purpose,action_type,required,effective_at)
 VALUES(m3b_cycle_test.uid(201),'m3b_gain_test','m3b-gain-1','pt-BR',body,digest,
  'synthetic_local_test','acceptance',true,clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_document(m3b_cycle_test.uid(201));
 INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
 VALUES(m3b_cycle_test.uid(202),'m3b-gain-1','pt-BR',ARRAY['m3b_gain_test'],clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_requirement_set(m3b_cycle_test.uid(202));

 FOREACH path IN ARRAY ARRAY['atomic','body_photo_confirmation','cleanup_scope'] LOOP
  owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
  submission:=m3b_cycle_test.signup_gain_submission('{"height_cm":160,"weight_kg":64}');
  snapshot:=m3b_cycle_test.original_state(owner_id);
  IF path='atomic' THEN
   PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',owner_id,submission),
    '23514',path||' BF15 cannot bypass exact BMI25');
  ELSE
   PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_with_%s(%L,%L,NULL,false,NULL,0)',
    path,owner_id,submission),'23514',path||' shares the actual final gain veto');
  END IF;
  PERFORM m3b_cycle_test.ok(snapshot=m3b_cycle_test.original_state(owner_id),
   path||' refusal preserves all owner/profile/legal/photo evidence');
 END LOOP;

 FOREACH path IN ARRAY ARRAY['atomic','body_photo_confirmation','cleanup_scope'] LOOP
  owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;k:='signup-gain-refused-'||i;
  observation:=public.observe_mobile_signup_strength_epoch(owner_id);
  admission:=public.admit_mobile_signup_strength_request(owner_id,k,repeat('e',64),
   (observation#>>'{observation,epoch}')::uuid)->'admission';
  snapshot:=m3b_cycle_test.original_state(owner_id);
  PERFORM m3b_cycle_test.throws(format(
   'SELECT public.complete_mobile_onboarding_keyed(%L,%L,%L,%L,%L,%L,%L,NULL,%s,NULL,%s)',
   owner_id,submission,path,k,repeat('e',64),admission->>'epoch',admission->>'admissionID',
   CASE WHEN path='atomic' THEN 'NULL' ELSE 'false' END,
   CASE WHEN path='atomic' THEN 'NULL' ELSE '0' END),
   '23514','keyed '||path||' cannot bypass the final exact BMI25 gain criterion');
  PERFORM m3b_cycle_test.ok(snapshot=m3b_cycle_test.original_state(owner_id),
   'keyed '||path||' refusal adds no scope/receipt/frequency/profile mutation');
 END LOOP;

 -- Completed=true with no completion instant still takes the writer branch.
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
 UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=owner_id;
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',owner_id,submission),
  '23514','completed boolean without instant cannot bypass n39');

 FOREACH patch IN ARRAY ARRAY[
  '{"weight_kg":84.24}', '{"training_frequency":2}', '{"body_fat_percent":19.01}',
  '{"sex":"feminino","body_fat_percent":27.01}', '{"weight_kg":80.999}'
 ]::jsonb[] LOOP
  owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',
   owner_id,m3b_cycle_test.signup_gain_submission(patch)), '23514','gain independent criterion refuses '||patch::text);
 END LOOP;

 -- An otherwise valid BMI just below the cut, and both BF equalities, pass.
 FOREACH patch IN ARRAY ARRAY[
  '{"height_cm":160,"weight_kg":63.99}', '{"body_fat_percent":19}',
  '{"sex":"feminino","body_fat_percent":27}'
 ]::jsonb[] LOOP
  owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
  result:=public.complete_mobile_onboarding_atomic(owner_id,m3b_cycle_test.signup_gain_submission(patch));
  PERFORM m3b_cycle_test.ok(result->>'objective'='ganho_massa'
   AND (SELECT current_protocol='ganho_massa' FROM public.user_profiles WHERE user_id=owner_id),
   'all gain criteria met '||patch::text);
 END LOOP;
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
 result:=public.complete_mobile_onboarding_atomic(owner_id,m3b_cycle_test.signup_gain_submission()-'body_fat_percent');
 PERFORM m3b_cycle_test.ok(result->>'objective'='ganho_massa','absent BF still requires BMI and training, not invented BF');

 -- Read configured NUMBERS exactly; JSON strings use existing code defaults.
 UPDATE public.global_config SET value='26' WHERE key='calc.imc_limit_recomp';
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
 result:=public.complete_mobile_onboarding_atomic(owner_id,m3b_cycle_test.signup_gain_submission('{"weight_kg":84.23}'));
 PERFORM m3b_cycle_test.ok(result->>'objective'='ganho_massa','configured BMI26 permits a genuinely lower BMI');
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',owner_id,
  m3b_cycle_test.signup_gain_submission('{"weight_kg":84.24}')), '23514','configured BMI26 equality is closed');
 UPDATE public.global_config SET value='"26"' WHERE key='calc.imc_limit_recomp';
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',owner_id,
  m3b_cycle_test.signup_gain_submission('{"weight_kg":84.23}')), '23514','text config is not numeric authority');
 UPDATE public.global_config SET value='25' WHERE key='calc.imc_limit_recomp';

 UPDATE public.global_config SET value='4' WHERE key='calc.training_min';
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',owner_id,
  m3b_cycle_test.signup_gain_submission()), '23514','new completion reads configured strength minimum');
 UPDATE public.global_config SET value='"4"' WHERE key='calc.training_min';
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
 result:=public.complete_mobile_onboarding_atomic(owner_id,m3b_cycle_test.signup_gain_submission());
 PERFORM m3b_cycle_test.ok(result->>'objective'='ganho_massa','text strength minimum uses number-only default');
 UPDATE public.global_config SET value='3' WHERE key='calc.training_min';

 UPDATE public.global_config SET value='{"masculino":{"gain":14,"recomp":20},"feminino":{"gain":27,"recomp":28}}'
  WHERE key='calc.bf_limits';
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',owner_id,
  m3b_cycle_test.signup_gain_submission()), '23514','new completion reads the independent configured BF gain limit');
 UPDATE public.global_config SET value='{"masculino":{"gain":"14","recomp":20},"feminino":{"gain":27,"recomp":28}}'
  WHERE key='calc.bf_limits';
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;
 result:=public.complete_mobile_onboarding_atomic(owner_id,m3b_cycle_test.signup_gain_submission());
 PERFORM m3b_cycle_test.ok(result->>'objective'='ganho_massa','text BF limit uses the existing field-specific default');
 UPDATE public.global_config SET value='{"masculino":{"gain":19,"recomp":20},"feminino":{"gain":27,"recomp":28}}'
  WHERE key='calc.bf_limits';

 -- A real keyed completion is replayed verbatim after a stricter new config.
 owner_id:=m3b_cycle_test.seed(i,NULL);i:=i+1;k:='signup-gain-'||i;
 submission:=m3b_cycle_test.signup_gain_submission();
 observation:=public.observe_mobile_signup_strength_epoch(owner_id);
 admission:=public.admit_mobile_signup_strength_request(owner_id,k,repeat('d',64),
  (observation#>>'{observation,epoch}')::uuid)->'admission';
 original:=public.complete_mobile_onboarding_keyed(owner_id,submission,'atomic',k,repeat('d',64),
  (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
 snapshot:=m3b_cycle_test.original_state(owner_id);
 UPDATE public.global_config SET value='8' WHERE key='calc.training_min';
 result:=public.complete_mobile_onboarding_keyed(owner_id,submission,'atomic',k,repeat('d',64),
  (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
 PERFORM m3b_cycle_test.ok(result=original AND snapshot=m3b_cycle_test.original_state(owner_id),
  'original keyed replay never recalculates phase or reruns the current gain check');
 result:=public.complete_mobile_onboarding_atomic(owner_id,submission);
 -- Unkeyed document reaccept now also observes current n10/civil time. Every
 -- preexisting completion field remains exact; only that new observation may
 -- be refreshed. Keyed original replay above remains byte-for-byte unchanged.
 PERFORM m3b_cycle_test.ok(result-'clinical_safety'=original-'clinical_safety'
  AND result#>>'{clinical_safety,no_plan}'='false'
  AND (result#>>'{clinical_safety,observed_at}')::timestamptz >= (original#>>'{clinical_safety,observed_at}')::timestamptz
  AND snapshot=m3b_cycle_test.original_state(owner_id),
  'document reacceptance with a completion instant does not move or refuse the saved objective');
END $$;
SELECT m3b_cycle_test.ok(NOT has_function_privilege(role,
 'private.assert_mobile_signup_gain_eligible(jsonb)','EXECUTE'),role||' no direct gain guard entry')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role;
ROLLBACK;
