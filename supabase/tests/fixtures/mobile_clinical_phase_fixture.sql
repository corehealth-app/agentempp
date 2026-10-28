\ir mobile_clinical_full_fixture.sql

-- Build an actual historical REGULAR through the existing private clock seams,
-- including3photo authorities and atomic FULL writer. Provider output and
-- calculated historical targets are synthetic QA inputs; no Storage is used.
CREATE FUNCTION m3b_cycle_test.phase_prior_regular(a uuid,mean numeric,target integer)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE at_time timestamptz:=clock_timestamp()-interval '14days';cycle uuid;doc public.legal_documents%ROWTYPE;
 consent jsonb;c jsonb;pose text;asset uuid;ticket uuid;request uuid;context jsonb;candidate jsonb;
 form jsonb;intent jsonb;proposal jsonb;preview jsonb;r date;
BEGIN
 cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'REGULAR',NULL,at_time)#>>'{cycle,id}')::uuid;
 SELECT * INTO doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(502);
 IF NOT FOUND THEN
  INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
  VALUES(m3b_cycle_test.uid(502),'body_photo_reevaluation_consent','phase-history-1','pt-BR',
   'SYNTHETIC HISTORICAL PHOTO AUTHORITY','2026-01-01T00:00:00Z') RETURNING * INTO doc;
  INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds,enabled)
  VALUES(doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,60,true);
 END IF;
 consent:=private.accept_mobile_reevaluation_photo_consent_at(a,cycle,1,doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,gen_random_uuid(),at_time);
 c:=jsonb_build_object('user',a,'cycle',cycle,'revision',consent->'cycle_revision','acceptance',consent#>'{acceptance,acceptance_id}');
 FOREACH pose IN ARRAY ARRAY['front','side','back'] LOOP
  c:=jsonb_set(c,'{revision}',to_jsonb((SELECT revision::text FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle)));
  asset:=(m3b_cycle_test.allocate(c,gen_random_uuid(),pose,1200,at_time)#>>'{asset,id}')::uuid;
  ticket:=gen_random_uuid();request:=gen_random_uuid();
  PERFORM private.prepare_mobile_reevaluation_photo_upload_at(a,cycle,asset,ticket,at_time);
  PERFORM private.register_mobile_reevaluation_photo_upload_ticket_at(a,cycle,asset,ticket,at_time+interval '2hours',at_time);
  PERFORM private.complete_mobile_reevaluation_photo_upload_at(a,cycle,asset,
   (SELECT source_revision FROM private.mobile_reevaluation_photo_sources WHERE user_id=a AND cycle_id=cycle AND requested_asset_id=asset),1200,'image/jpeg',NULL,at_time);
  PERFORM private.claim_mobile_reevaluation_photo_processing_at(a,cycle,asset,request,at_time);
  PERFORM private.authorize_mobile_reevaluation_photo_provider_at(a,cycle,asset,request,at_time);
  PERFORM private.complete_mobile_reevaluation_photo_processing_at(a,cycle,asset,request,
   jsonb_build_object('type','body','view',pose,'bf_percent_estimate',mean),at_time);
 END LOOP;
 context:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,at_time);
 candidate:=context#>'{facts,protocol_authority,body_fat_candidate}';
 r:=(context#>>'{facts,protocol_authority,signup_origin,maintenance_since}')::date;
 form:=jsonb_build_object('version',1,'phase','manutencao','kind','REGULAR','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',80,'strengthSessions',4,'hunger','moderada','energy','boa','adherence','bem_consistente',
   'strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain','nao','activity',NULL,
   'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',NULL));
 intent:=jsonb_build_object('principalConfirmed',false,'bodyFat',jsonb_build_object('confirmed',true,
  'sourceHash',candidate->'source_hash','meanHundredths',candidate->'mean_hundredths'));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',false,
  'profile',jsonb_build_object('current_protocol','manutencao','deficit_level',NULL,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',NULL,'beforeProtein',NULL,'afterKcal',target,'afterProtein',144,'formulaAfterKcal',target),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps','[]'::jsonb,'schedule',NULL,'maintenanceSince',r));
 preview:=private.prepare_mobile_clinical_preview_at(a,'REGULAR',cycle,gen_random_uuid(),context->>'context_hash',form,intent,proposal,at_time);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),form,intent,proposal,at_time);
END $$;

-- Explicit synthetic OLD signup evidence, not a customer import or proof of
-- actual historical onboarding. The existing receipt trigger captures the
-- origin at INSERT; no immutable row is rewritten or trigger disabled.
CREATE FUNCTION m3b_cycle_test.phase_context(n integer,phase text,mean numeric,target integer,days integer DEFAULT 56,with_prior boolean DEFAULT false,sparse boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid;epoch uuid:=gen_random_uuid();admission uuid:=gen_random_uuid();generation uuid:=gen_random_uuid();source uuid;
 at_time timestamptz:=clock_timestamp()-make_interval(days=>days);cycle uuid;doc public.legal_documents%ROWTYPE;
 consent jsonb;c jsonb;pose text;asset uuid;ticket uuid;request uuid;offset_days integer;measured timestamptz;
BEGIN
 IF n NOT BETWEEN 4500 AND 4599 OR phase NOT IN('recomposicao','manutencao','ganho_massa')
  OR mean NOT BETWEEN 12 AND 40 OR target<=0 OR days<14 THEN RAISE EXCEPTION 'invalid_phase_fixture'; END IF;
 a:=m3b_cycle_test.seed(n,NULL);
 UPDATE public.user_profiles SET onboarding_completed=true,onboarding_completed_at=at_time,
  sex='masculino',birth_date='1990-01-01',height_cm=180,weight_kg=80,body_fat_percent=mean,
  activity_level='moderado',training_frequency=4,hunger_level='moderada',
  current_protocol=phase::public.protocol_enum,deficit_level=CASE WHEN phase='recomposicao' THEN 500 END
 WHERE user_id=a;
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(a,epoch,at_time-interval '2 minutes');
 INSERT INTO private.mobile_signup_strength_request_admissions(user_id,request_key,request_hash,epoch,admission_id,admitted_at)
 VALUES(a,'phase-fixture-'||n,repeat('a',64),epoch,admission,at_time-interval '1 minute');
 INSERT INTO private.strength_week_scopes(user_id,generation,open_operation_namespace,open_operation_key,opened_at)
 VALUES(a,generation,'mobile_signup_completion_v1',admission::text,at_time);
 INSERT INTO private.strength_week_source_versions(user_id,generation,source_kind,fact,planned_days,
  operation_namespace,operation_key,observed_at,observed_timezone,effective_week_start)
 VALUES(a,generation,'informed_frequency','value',4,'mobile_signup_completion_v1',admission::text,
  at_time,'America/Sao_Paulo',date_trunc('week',at_time AT TIME ZONE 'America/Sao_Paulo')::date+7)
 RETURNING source_version_id INTO source;
 INSERT INTO private.mobile_signup_strength_completion_receipts(user_id,admission_id,epoch,outcome,completion_path,
  completed_at,generation,frequency_source_version_id,completion_result,recorded_at)
 VALUES(a,admission,epoch,'first_fresh','atomic',at_time,generation,source,
  jsonb_build_object('user_id',a,'onboarding_completed',true,'completed_at',at_time,'objective',phase),at_time);
 IF NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=a AND signup_generation=admission)
 THEN RAISE EXCEPTION 'phase_fixture_origin_missing';END IF;
 IF with_prior THEN
  IF phase<>'manutencao' THEN RAISE EXCEPTION 'historical_regular_requires_maintenance';END IF;
  PERFORM m3b_cycle_test.phase_prior_regular(a,mean,target);
 END IF;
 cycle:=(public.start_mobile_reevaluation_cycle(a,gen_random_uuid())#>>'{cycle,id}')::uuid;
 SELECT * INTO doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(501);
 IF NOT FOUND THEN
  INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
  VALUES(m3b_cycle_test.uid(501),'body_photo_reevaluation_consent','asset-local-1','pt-BR',
   'SYNTHETIC LOCAL PHOTO ALLOCATION','2026-10-20T00:00:00Z') RETURNING * INTO doc;
  INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds,enabled)
  VALUES(doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,60,true);
 END IF;
 consent:=public.accept_mobile_reevaluation_photo_consent(a,cycle,1,doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,gen_random_uuid());
 c:=jsonb_build_object('user',a,'cycle',cycle,'revision',consent->'cycle_revision','acceptance',consent#>'{acceptance,acceptance_id}');
 FOREACH pose IN ARRAY ARRAY['front','side','back'] LOOP
  c:=jsonb_set(c,'{revision}',to_jsonb((SELECT revision::text FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle)));
  asset:=(m3b_cycle_test.allocate(c,gen_random_uuid(),pose)#>>'{asset,id}')::uuid;ticket:=gen_random_uuid();request:=gen_random_uuid();
  PERFORM public.prepare_mobile_reevaluation_photo_upload(a,cycle,asset,ticket);
  PERFORM public.register_mobile_reevaluation_photo_upload_ticket(a,cycle,asset,ticket,clock_timestamp()+interval '2hours');
  PERFORM public.complete_mobile_reevaluation_photo_upload(a,cycle,asset,
   (SELECT source_revision FROM private.mobile_reevaluation_photo_sources WHERE user_id=a AND cycle_id=cycle AND requested_asset_id=asset),1200,'image/jpeg',NULL);
  PERFORM public.claim_mobile_reevaluation_photo_processing(a,cycle,asset,request);
  PERFORM public.authorize_mobile_reevaluation_photo_provider(a,cycle,asset,request);
  PERFORM public.complete_mobile_reevaluation_photo_processing(a,cycle,asset,request,
   jsonb_build_object('type','body','view',pose,'bf_percent_estimate',mean));
 END LOOP;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,calories_consumed,exercise_calories)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,target,144,phase::public.protocol_enum,200,50);
 FOREACH offset_days IN ARRAY ARRAY[27,24,21,20,17,14,13,10,7,6,3,0] LOOP
  IF sparse AND offset_days>=14 THEN CONTINUE;END IF;
  measured:=(((clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-offset_days)::timestamp AT TIME ZONE 'America/Sao_Paulo');
  -- Historical QA observations go through the existing PRIVATE clock seam;
  -- the public API correctly refuses backdating an entry by more than7days.
  PERFORM private.record_mobile_weight_at(a,80,'kg',measured,
   'phase-weight-'||n||'-'||offset_days,measured);
 END LOOP;
 RETURN c;
END $$;
REVOKE ALL ON FUNCTION m3b_cycle_test.phase_prior_regular(uuid,numeric,integer),
 m3b_cycle_test.phase_context(integer,text,numeric,integer,integer,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
