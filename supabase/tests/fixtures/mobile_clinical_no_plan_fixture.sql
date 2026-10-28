\ir mobile_signup_health_fixture.sql

CREATE FUNCTION m3b_cycle_test.no_plan_signup(n integer,minor boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid:=m3b_cycle_test.seed(n,NULL);command jsonb;health jsonb;admission jsonb;submission jsonb;reply jsonb;
BEGIN
 command:=m3b_cycle_test.signup_health_command(a,gen_random_uuid(),gen_random_uuid());
 command:=jsonb_set(command,'{risks}',CASE WHEN minor THEN '["reduced_intake"]'::jsonb ELSE '["pregnant_or_breastfeeding"]'::jsonb END);
 health:=private.admit_mobile_signup_health(a,command);
 submission:=jsonb_build_object('name','M3B synthetic QA','locale','pt-BR','country','BR','timezone','America/Sao_Paulo',
  'sex','feminino','birth_date',CASE WHEN minor THEN to_char(((clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-interval '17 years')::date,'YYYY-MM-DD') ELSE '1990-01-01' END,
  'height_cm',180,'weight_kg',80,'body_fat_percent',24,'objective',NULL,'activity_level','moderado',
  'training_frequency',4,'hunger_level','moderada','wake_time','07:00','bedtime','23:00',
  'food_organization','sim','persona','focus','document_actions',command->'document_actions');
 admission:=public.admit_mobile_signup_strength_request(a,command->>'request_key',repeat('b',64),
  (health#>>'{receipt,epoch}')::uuid)->'admission';
 reply:=public.complete_mobile_onboarding_keyed(a,submission,'atomic',command->>'request_key',repeat('b',64),
  (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
 RETURN jsonb_build_object('user',a,'command',command,'completed',reply);
END $$;

CREATE FUNCTION m3b_cycle_test.no_plan_request(a uuid,kind text,cycle uuid,form_patch jsonb DEFAULT '{}',
 proposal_patch jsonb DEFAULT '{}',at_time timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE context jsonb;form jsonb;intent jsonb;proposal jsonb;preview jsonb;r record;p public.user_profiles%ROWTYPE;
BEGIN
 context:=private.capture_mobile_clinical_context_at(a,kind,cycle,at_time);
 SELECT * INTO STRICT p FROM public.user_profiles WHERE user_id=a;
 SELECT * INTO STRICT r FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a
  AND admission_id=(context#>>'{facts,anchor,signup_generation}')::uuid;
 form:=jsonb_build_object('version',1,'phase',NULL,'kind',kind,'activityPurpose','normal','preference',NULL,
  'noPlanOrigin',jsonb_build_object('kind','confirmed_no_plan','signupGeneration',r.admission_id,
   'signupEpoch',r.epoch,'completedAt',to_char(r.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),
  'answers',jsonb_build_object('weightKg',81,'strengthSessions',NULL,'adherence',NULL,'hunger',NULL,'energy',NULL,
   'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,'activity',NULL,
   'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',true))||form_patch;
 intent:=jsonb_build_object('principalConfirmed',false);
 IF kind='REGULAR' THEN intent:=intent||jsonb_build_object('bodyFat',jsonb_build_object('confirmed',true,
  'sourceHash',context#>'{facts,protocol_authority,body_fat_candidate,source_hash}',
  'meanHundredths',context#>'{facts,protocol_authority,body_fat_candidate,mean_hundredths}')); END IF;
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',coalesce(
   (context#>>'{facts,safety,hold_active}')::boolean AND form#>>'{answers,healthCheck,kind}'='none'
    AND form#>'{answers,professionalConversationConfirmed}'='true'::jsonb,false),
  'profile',jsonb_build_object('current_protocol',NULL,'deficit_level',NULL,'activity_level',p.activity_level,
   'training_frequency',p.training_frequency,'hunger_level',p.hunger_level),
  'targets',jsonb_build_object('beforeKcal',NULL,'beforeProtein',NULL,'afterKcal',NULL,'afterProtein',NULL,'formulaAfterKcal',NULL),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL))||proposal_patch;
 preview:=private.prepare_mobile_clinical_preview_at(a,kind,cycle,gen_random_uuid(),context->>'context_hash',form,intent,proposal,at_time);
 RETURN jsonb_build_object('context',context,'preview',preview,'form',form,'intent',intent,'proposal',proposal);
END $$;
CREATE FUNCTION m3b_cycle_test.no_plan_confirm(a uuid,q jsonb,k uuid DEFAULT gen_random_uuid(),at_time timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,k,q->'form',q->'intent',q->'proposal',at_time)
$$;
CREATE FUNCTION m3b_cycle_test.no_plan_refuse(a uuid,q jsonb,code text,label text,at_time timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE before_rows jsonb:=m3b_cycle_test.original_state(a);cycles jsonb;actual text;
BEGIN
 SELECT jsonb_agg(to_jsonb(c) ORDER BY c.cycle_id) INTO cycles FROM private.mobile_reevaluation_cycles c WHERE user_id=a;
 BEGIN PERFORM m3b_cycle_test.no_plan_confirm(a,q,gen_random_uuid(),at_time);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
 PERFORM m3b_cycle_test.ok(actual=code AND before_rows=m3b_cycle_test.original_state(a)
  AND cycles IS NOT DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.cycle_id) FROM private.mobile_reevaluation_cycles c WHERE user_id=a),
  label||' [code='||coalesce(actual,'NONE')||']');
END $$;
CREATE FUNCTION m3b_cycle_test.no_plan_photos(a uuid,cycle uuid,at_time timestamptz) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE doc public.legal_documents%ROWTYPE;consent jsonb;asset uuid;ticket uuid;request uuid;pose text;reading numeric:=18;
BEGIN
 INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
 VALUES(m3b_cycle_test.uid(501),'body_photo_reevaluation_consent','no-plan-local-1','pt-BR',
  'SYNTHETIC LOCAL PHOTO ALLOCATION','2026-10-20T00:00:00Z') RETURNING * INTO doc;
 INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds,enabled)
 VALUES(doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,60,true);
 consent:=private.accept_mobile_reevaluation_photo_consent_at(a,cycle,
  (SELECT revision FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle),doc.id,doc.document_key,
  doc.version,doc.locale,doc.body_hash,gen_random_uuid(),at_time);
 FOREACH pose IN ARRAY ARRAY['front','side','back'] LOOP
  asset:=(private.create_mobile_reevaluation_photo_asset_at(a,cycle,
   (SELECT revision FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle),
   (consent#>>'{acceptance,acceptance_id}')::uuid,pose,'image/jpeg',1200,gen_random_uuid(),at_time)#>>'{asset,id}')::uuid;
  ticket:=gen_random_uuid();request:=gen_random_uuid();
  PERFORM private.prepare_mobile_reevaluation_photo_upload_at(a,cycle,asset,ticket,at_time);
  PERFORM private.register_mobile_reevaluation_photo_upload_ticket_at(a,cycle,asset,ticket,at_time+interval '2 hours',at_time);
  PERFORM private.complete_mobile_reevaluation_photo_upload_at(a,cycle,asset,
   (SELECT source_revision FROM private.mobile_reevaluation_photo_sources WHERE user_id=a AND cycle_id=no_plan_photos.cycle AND requested_asset_id=asset),
   1200,'image/jpeg',NULL,at_time);
  PERFORM private.claim_mobile_reevaluation_photo_processing_at(a,cycle,asset,request,at_time);
  PERFORM private.authorize_mobile_reevaluation_photo_provider_at(a,cycle,asset,request,at_time);
  PERFORM private.complete_mobile_reevaluation_photo_processing_at(a,cycle,asset,request,
   jsonb_build_object('type','body','view',pose,'bf_percent_estimate',reading),at_time);
  reading:=reading+6;
 END LOOP;
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
