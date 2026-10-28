-- Actual private SQL, synthetic local rollback only. No HTTP/device/activation.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_signup_health_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('private.admit_mobile_signup_health(uuid,jsonb)') IS NOT NULL,
 'signup consent and risk admission exists');

DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2300,NULL);b uuid:=m3b_cycle_test.seed(2301,NULL);
 k uuid:=gen_random_uuid();c jsonb;other jsonb;first jsonb;r jsonb;before_rows jsonb;
 ordinary jsonb;actions_before jsonb;mutation jsonb;
BEGIN
 c:=m3b_cycle_test.signup_health_command(a,k,gen_random_uuid());
 other:=m3b_cycle_test.signup_health_command(b,gen_random_uuid(),gen_random_uuid());
 ordinary:=jsonb_build_object('user',(SELECT to_jsonb(u) FROM public.users u WHERE id=a),
  'profile',(SELECT to_jsonb(p) FROM public.user_profiles p WHERE user_id=a));
 first:=private.admit_mobile_signup_health(a,c);
 PERFORM m3b_cycle_test.ok(first#>>'{declaration,state,hold_active}'='true'
  AND first#>>'{declaration,receipt,items,0}'='reduced_intake'
  AND first#>>'{receipt,intent_id}'=c->>'intent_id'
  AND (SELECT count(*)=1 FROM private.mobile_signup_health_receipts WHERE user_id=a)
  AND (SELECT count(*)=1 FROM private.mobile_health_risk_receipts WHERE user_id=a),
  'fresh signup marks HOLD and binds one immutable consent/intent/risk receipt');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=4 FROM public.user_onboarding_legal_actions WHERE user_id=a)
  AND EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions WHERE user_id=a
   AND purpose='closed_evaluation_sensitive_health_data_processing' AND action_type='consent'),
  'exact current required legal actions and sensitive purpose are durable');
 PERFORM m3b_cycle_test.ok(ordinary=jsonb_build_object('user',(SELECT to_jsonb(u) FROM public.users u WHERE id=a),
   'profile',(SELECT to_jsonb(p) FROM public.user_profiles p WHERE user_id=a))
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_weight_measurements WHERE user_id=a),
  'early admission writes no ordinary signup answer, completion, episode or weight');
 before_rows:=m3b_cycle_test.original_state(a);
 r:=private.admit_mobile_signup_health(a,c);
 PERFORM m3b_cycle_test.ok(r=first AND before_rows=m3b_cycle_test.original_state(a),
  'identical replay has no repeated legal/risk/time side effect');
 r:=private.admit_mobile_signup_health(a,jsonb_set(c,'{document_actions}',
  (SELECT jsonb_agg(value ORDER BY ord DESC) FROM jsonb_array_elements(c->'document_actions') WITH ORDINALITY AS x(value,ord))));
 PERFORM m3b_cycle_test.ok(r=first AND before_rows=m3b_cycle_test.original_state(a),
  'document array ordering does not change the original canonical acknowledgement');
 FOREACH mutation IN ARRAY ARRAY[
  jsonb_build_object('risks',jsonb_build_array('professional_diet')),
  jsonb_build_object('intent_id',other->'intent_id'),jsonb_build_object('request_key',other->'request_key')
 ] LOOP
  PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,c||mutation),
   '40001','same operation with altered content conflicts');
 END LOOP;
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'conflicting replays preserve all evidence');
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',b,c),
  '40001','another person cannot reuse this intent');

 -- Even a coincident generic risk key cannot be adopted by signup admission.
 PERFORM public.declare_mobile_health_risk(b,(other->>'operation_key')::uuid,ARRAY['reduced_intake']);
 r:=private.admit_mobile_signup_health(b,other);
 PERFORM m3b_cycle_test.ok(r#>>'{receipt,health_operation_key}'<>other->>'operation_key'
  AND (SELECT count(*)=2 FROM private.mobile_health_risk_receipts WHERE user_id=b),
  'signup generates an independent internal risk key instead of relabeling an old generic receipt');

 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO actions_before FROM public.user_onboarding_legal_actions x WHERE user_id=a;
 r:=private.admit_mobile_signup_health(a,c||jsonb_build_object('operation_key',gen_random_uuid(),
  'risks',jsonb_build_array('professional_diet')));
 PERFORM m3b_cycle_test.ok(actions_before=(SELECT jsonb_agg(to_jsonb(x) ORDER BY id)
   FROM public.user_onboarding_legal_actions x WHERE user_id=a)
  AND r#>>'{declaration,state,safety_revision}'='2','new marked risks reuse existing legal acts without overwriting original consent time');
 PERFORM public.reset_user_conversation_atomic(a,true);
 before_rows:=m3b_cycle_test.original_state(a);
 r:=private.admit_mobile_signup_health(a,c);
 PERFORM m3b_cycle_test.ok(r->'receipt'=first->'receipt' AND r#>>'{declaration,state,safety_revision}'='2'
  AND before_rows=m3b_cycle_test.original_state(a),'original admission survives reset without any restoration or risk rearm');
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,
  c||jsonb_build_object('operation_key',gen_random_uuid())), '40001','new admission cannot use an old signup epoch');
END $$;

-- Actual fresh completion and EARLY_FULL clear. Targets are synthetic SQL
-- effects, not proof of the unfinished BFF FULL calculator.
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2304,NULL);c jsonb;first jsonb;admission jsonb;submission jsonb;
 s jsonb;cycle uuid;context jsonb;form jsonb;proposal jsonb;preview jsonb;reply jsonb;before_rows jsonb;
BEGIN
 c:=m3b_cycle_test.signup_health_command(a,gen_random_uuid(),gen_random_uuid());
 first:=private.admit_mobile_signup_health(a,c);
 submission:=jsonb_build_object('name','M3B synthetic QA','locale','pt-BR','country','BR',
  'timezone','America/Sao_Paulo','sex','masculino','birth_date','1990-01-01','height_cm',180,'weight_kg',80,
  'body_fat_percent',15,'objective','manutencao','activity_level','moderado','training_frequency',4,
  'hunger_level','moderada','wake_time','07:00','bedtime','23:00','food_organization','sim','persona','focus',
  'document_actions',c->'document_actions');
 admission:=public.admit_mobile_signup_strength_request(a,c->>'request_key',repeat('b',64),
  (first#>>'{receipt,epoch}')::uuid)->'admission';
 PERFORM public.complete_mobile_onboarding_keyed(a,submission,'atomic',c->>'request_key',repeat('b',64),
  (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
 s:=private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);
 cycle:=(s#>>'{cycle,id}')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,day_closed)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,2400,144,'manutencao',false);
 form:=jsonb_build_object('version',1,'phase','manutencao','kind','EARLY_FULL','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',NULL,'strengthSessions',NULL,'hunger',NULL,'energy',NULL,'adherence',NULL,
   'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,'activity',NULL,
   'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',true));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',true,
  'profile',jsonb_build_object('current_protocol','manutencao','deficit_level',NULL,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',2400,'beforeProtein',144,'afterKcal',2400,'afterProtein',144,'formulaAfterKcal',2400),
  -- A proven signup starts its difficulty counter at zero. EARLY must preserve it.
  'episode',jsonb_build_object('difficultyCount',0,'ledgerSteps',jsonb_build_array(),'schedule',NULL,'maintenanceSince',
   (SELECT maintenance_since FROM private.mobile_clinical_signup_origins WHERE user_id=a)));
 context:=private.capture_mobile_clinical_context_at(a,'EARLY_FULL',cycle,NULL);
 preview:=private.prepare_mobile_clinical_preview_at(a,'EARLY_FULL',cycle,gen_random_uuid(),context->>'context_hash',
  form,'{"principalConfirmed":false}',proposal,NULL);
 reply:=private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),
  form,'{"principalConfirmed":false}',proposal,NULL);
 PERFORM m3b_cycle_test.ok((private.mobile_health_state_wire(a)->>'hold_active')='false'
  AND (SELECT count(*)=1 FROM private.mobile_clinical_health_clear_receipts WHERE user_id=a),
  'signup risk can be cleared only through an actual concluded FULL none plus professional confirmation');
 before_rows:=m3b_cycle_test.original_state(a);
 reply:=private.admit_mobile_signup_health(a,c);
 PERFORM m3b_cycle_test.ok(reply->'receipt'=first->'receipt' AND reply#>>'{declaration,state,hold_active}'='false'
  AND before_rows=m3b_cycle_test.original_state(a),'signup replay after real FULL clear returns current safety without rearming');
END $$;

DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2302,NULL);c jsonb;patch jsonb;before_rows jsonb;
BEGIN
 c:=m3b_cycle_test.signup_health_command(a,gen_random_uuid(),gen_random_uuid());
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,
  c||jsonb_build_object('intent_id',gen_random_uuid())), '40001','an unissued intent cannot save consent or risks');
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,
  c||jsonb_build_object('request_key','osc1:'||gen_random_uuid())), '40001','another key cannot be paired with a valid intent');
 FOREACH patch IN ARRAY ARRAY[
  '{"weight_kg":80}','{"epoch":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}',
  '{"risks":[]}','{"risks":["none"]}','{"risks":["professional_diet","professional_diet"]}',
  '{"document_actions":[]}','{"version":2}','{"locale":null}','{"request_key":null}',
  '{"risks":[null]}','{"risks":[1]}'
 ]::jsonb[] LOOP
  PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,c||patch),
   '22023','strict marked-risk command rejects '||patch::text);
 END LOOP;
 patch:=jsonb_set(c,'{document_actions,3,content_hash}',to_jsonb(repeat('0',64)));
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,patch),
  '23514','wrong consent hash cannot record risks or legal acts');
 patch:=jsonb_set(c,'{document_actions,3,action}','"acceptance"');
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,patch),
  '23514','acceptance is not explicit sensitive consent');
 patch:=jsonb_set(c,'{document_actions}',(c->'document_actions')||jsonb_build_array(c#>'{document_actions,0}'));
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,patch),
  '22023','two versions/actions of one document key are forbidden');
 patch:=jsonb_set(c,'{document_actions,0,version}','null');
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,patch),
  '22023','JSON null cannot bypass identity validation');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'all refusals preserve every owner row');
 UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=a;
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,c),
  '40001','new signup admission is not an any-day bypass after signup');
END $$;

CREATE FUNCTION m3b_cycle_test.fail_signup_health_receipt() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN RAISE EXCEPTION 'synthetic late fail' USING ERRCODE='P0001'; END $$;
CREATE TRIGGER synthetic_signup_health_late_failure BEFORE INSERT ON private.mobile_signup_health_receipts
 FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_signup_health_receipt();
DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2303,NULL);c jsonb;before_rows jsonb;
BEGIN
 c:=m3b_cycle_test.signup_health_command(a,gen_random_uuid(),gen_random_uuid());
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,c),
  'P0001','late receipt failure rolls back earlier consent and risk writes');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'no partial legal/risk result survives late failure');
END $$;
DROP TRIGGER synthetic_signup_health_late_failure ON private.mobile_signup_health_receipts;

SELECT m3b_cycle_test.throws('UPDATE private.mobile_signup_health_receipts SET request_key=request_key||''-changed''',
 '55000','signup health receipts cannot be rewritten');
SELECT m3b_cycle_test.throws('DELETE FROM private.mobile_signup_health_receipts',
 '55000','signup health receipts cannot be silently discarded');
SELECT m3b_cycle_test.ok(NOT has_function_privilege('service_role','private.admit_mobile_signup_health(uuid,jsonb)','EXECUTE')
 AND NOT has_function_privilege('authenticated','private.admit_mobile_signup_health(uuid,jsonb)','EXECUTE')
 AND NOT has_table_privilege('service_role','private.mobile_signup_health_receipts','SELECT,INSERT,UPDATE,DELETE')
 AND (SELECT relrowsecurity FROM pg_class WHERE oid='private.mobile_signup_health_receipts'::regclass),
 'new authority remains private and RLS enabled without transport or route activation');

DO $$
DECLARE a uuid:=m3b_cycle_test.seed(2305,NULL);c jsonb;body text:='SYNTHETIC UNRELATED CONSENT';
 old_receipt private.mobile_signup_health_receipts%ROWTYPE;before_rows jsonb;r jsonb;
BEGIN
 c:=m3b_cycle_test.signup_health_command(a,gen_random_uuid(),gen_random_uuid());
 INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
 VALUES(m3b_cycle_test.uid(206),'synthetic_qa_unrelated_consent','synthetic-qa-1','pt-BR',body,
  encode(extensions.digest(body,'sha256'),'hex'),'synthetic_unrelated_purpose','consent',true,clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_document(m3b_cycle_test.uid(206));
 INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
 VALUES(m3b_cycle_test.uid(207),'synthetic-other-1','pt-BR',ARRAY['synthetic_qa_unrelated_consent'],clock_timestamp());
 PERFORM public.publish_onboarding_legal_requirement_set(m3b_cycle_test.uid(207));
 SELECT jsonb_set(c,'{document_actions}',jsonb_build_array(jsonb_build_object('document_key',d.document_key,
  'version',d.version,'locale',d.locale,'content_hash',d.content_hash,'action',d.action_type))) INTO c
 FROM public.onboarding_legal_documents d WHERE d.id=m3b_cycle_test.uid(206);
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT private.admit_mobile_signup_health(%L,%L)',a,c),
  '23514','even current arbitrary consent cannot substitute the sensitive health purpose');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'unavailable sensitive consent creates no legal act or risk');
 SELECT * INTO STRICT old_receipt FROM private.mobile_signup_health_receipts WHERE user_id=m3b_cycle_test.uid(2304);
 before_rows:=m3b_cycle_test.original_state(old_receipt.user_id);
 r:=private.admit_mobile_signup_health(old_receipt.user_id,old_receipt.command);
 PERFORM m3b_cycle_test.ok(r#>>'{receipt,id}'=old_receipt.id::text AND before_rows=m3b_cycle_test.original_state(old_receipt.user_id),
  'changed publication policy cannot replace or repeat an original acknowledgement');
END $$;
ROLLBACK;
