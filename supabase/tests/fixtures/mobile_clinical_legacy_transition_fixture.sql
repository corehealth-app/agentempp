\ir mobile_clinical_full_fixture.sql

-- No first_fresh receipt, frequency scope or historical clinical conclusion is
-- manufactured. Only the local synthetic profile predates the actual admission.
CREATE FUNCTION m3b_cycle_test.legacy_photo_context(n integer, with_phase boolean DEFAULT true, known_marker boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid; c uuid; doc public.legal_documents%ROWTYPE; consent jsonb;
BEGIN
 a:=m3b_cycle_test.seed(n,CASE WHEN with_phase AND known_marker THEN '2026-10-01T23:00:00Z'::timestamptz END,
  'America/Sao_Paulo',false);
 UPDATE public.user_profiles SET onboarding_completed=true,sex='masculino',birth_date='1990-01-01',
  height_cm=180,weight_kg=80,body_fat_percent=24,activity_level='moderado',training_frequency=4,
  hunger_level='moderada',current_protocol=CASE WHEN with_phase THEN 'recomposicao'::public.protocol_enum END,
  deficit_level=CASE WHEN with_phase THEN 500 END WHERE user_id=a;
 PERFORM private.admit_mobile_clinical_legacy_generation_at(a,NULL);
 c:=(public.start_mobile_clinical_full(a,gen_random_uuid(),NULL)#>>'{cycle,id}')::uuid;
 SELECT * INTO doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(501);
 IF NOT FOUND THEN
  INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
   VALUES(m3b_cycle_test.uid(501),'body_photo_reevaluation_consent','asset-local-1','pt-BR',
    'SYNTHETIC LOCAL PHOTO ALLOCATION','2026-10-20T00:00:00Z') RETURNING * INTO doc;
  INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,
   locale,body_hash,idle_timeout_seconds,enabled)
   VALUES(doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,60,true);
 END IF;
 consent:=public.accept_mobile_reevaluation_photo_consent(a,c,1,doc.id,doc.document_key,
  doc.version,doc.locale,doc.body_hash,gen_random_uuid());
 RETURN jsonb_build_object('user',a,'cycle',c,'revision',consent->'cycle_revision',
  'acceptance',consent#>'{acceptance,acceptance_id}','accepted_at',consent#>'{acceptance,accepted_at}');
END $$;

CREATE FUNCTION m3b_cycle_test.legacy_clinical_request(c jsonb, weight numeric DEFAULT 84, clear_hold boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE context jsonb; candidate jsonb; form jsonb; intent jsonb; proposal jsonb; preview jsonb; phase text;
BEGIN
 context:=public.get_mobile_clinical_full_context((c->>'user')::uuid,'TRANSITION_FULL',(c->>'cycle')::uuid);
 candidate:=context#>'{facts,protocol_authority,body_fat_candidate}';
 phase:=context#>>'{facts,profile,current_protocol}';
 form:=jsonb_build_object('version',1,'phase',phase,'kind','TRANSITION_FULL','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',weight,'strengthSessions',CASE WHEN phase IS NOT NULL THEN 4 END,
   'hunger',CASE WHEN phase IS NOT NULL THEN 'moderada' END,'energy',CASE WHEN phase IS NOT NULL THEN 'boa' END,
   'adherence',CASE WHEN phase IS NOT NULL THEN 'bem_consistente' END,'strengthProgression',NULL,
   'fatPerception',NULL,'difficultToMaintain',NULL,'activity',NULL,
   'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',CASE WHEN clear_hold THEN true ELSE NULL END));
 IF phase IS NULL THEN form:=form||jsonb_build_object('legacyOrigin',context#>'{facts,protocol_authority,phase_origin}'); END IF;
 intent:=jsonb_build_object('principalConfirmed',false,'bodyFat',jsonb_build_object('confirmed',true,
  'sourceHash',candidate->'source_hash','meanHundredths',candidate->'mean_hundredths'));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',clear_hold,
  'profile',jsonb_build_object('current_protocol',phase,'deficit_level',CASE WHEN phase IS NOT NULL THEN 500 END,
   'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',context#>'{facts,day,calories_target}',
   'beforeProtein',context#>'{facts,day,protein_target}','afterKcal',CASE WHEN phase IS NOT NULL THEN 1599 ELSE (context#>>'{facts,day,calories_target}')::integer END,
   'afterProtein',CASE WHEN phase IS NOT NULL THEN 126 ELSE (context#>>'{facts,day,protein_target}')::numeric END,'formulaAfterKcal',CASE WHEN phase IS NOT NULL THEN 1599 END),
  'episode',jsonb_build_object('difficultyCount',NULL,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL));
 preview:=private.prepare_mobile_clinical_preview_at((c->>'user')::uuid,'TRANSITION_FULL',(c->>'cycle')::uuid,
  gen_random_uuid(),context->>'context_hash',form,intent,proposal,NULL);
 RETURN jsonb_build_object('preview',preview,'form',form,'intent',intent,'proposal',proposal,'context',context);
END $$;
CREATE FUNCTION m3b_cycle_test.legacy_initial_phase_request(c jsonb, weight numeric DEFAULT 84, clear_hold boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE q jsonb;f jsonb;i jsonb;p jsonb;preview jsonb;
BEGIN
 q:=m3b_cycle_test.legacy_clinical_request(c,weight,clear_hold);f:=q->'form';i:=q->'intent';p:=q->'proposal';
 f:=jsonb_set(jsonb_set(f,'{answers,hunger}','"moderada"'),'{answers,strengthSessions}','4');
 i:=jsonb_set(i,'{principalConfirmed}','true');
 p:=jsonb_set(jsonb_set(p,'{principal}','"phase_recomposition"'),'{profile,current_protocol}','"recomposicao"');
 p:=jsonb_set(p,'{profile,deficit_level}','500');
 p:=jsonb_set(p,'{targets,afterKcal}','1599');p:=jsonb_set(p,'{targets,afterProtein}','126');
 p:=jsonb_set(p,'{targets,formulaAfterKcal}','1599');p:=jsonb_set(p,'{episode,difficultyCount}','0');
 preview:=private.prepare_mobile_clinical_preview_at((c->>'user')::uuid,'TRANSITION_FULL',(c->>'cycle')::uuid,
  gen_random_uuid(),q#>>'{context,context_hash}',f,i,p,NULL);
 RETURN q||jsonb_build_object('preview',preview,'form',f,'intent',i,'proposal',p);
END $$;
REVOKE ALL ON FUNCTION m3b_cycle_test.legacy_photo_context(integer,boolean,boolean),m3b_cycle_test.legacy_clinical_request(jsonb,numeric,boolean)
 ,m3b_cycle_test.legacy_initial_phase_request(jsonb,numeric,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
