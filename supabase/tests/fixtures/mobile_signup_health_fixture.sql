\ir mobile_reevaluation_cycle_fixture.sql
-- Synthetic legal content only. The purpose is the existing policy identity,
-- not a new legal text/approval. All callers keep these fixtures in ROLLBACK.
DO $$
DECLARE n integer; k text; body text;
BEGIN
 FOR n IN 201..204 LOOP
  k:=CASE n WHEN 201 THEN 'evaluation_1_terms_notice' WHEN 202 THEN 'evaluation_2_privacy_notice'
   WHEN 203 THEN 'evaluation_3_health_ai_notice' ELSE 'evaluation_4_sensitive_data_consent' END;
  body:='SYNTHETIC LOCAL SIGNUP HEALTH '||n;
  INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,
   purpose,action_type,required,effective_at)
  VALUES(m3b_cycle_test.uid(n),k,'synthetic-health-1','pt-BR',body,encode(extensions.digest(body,'sha256'),'hex'),
   CASE WHEN n=204 THEN 'closed_evaluation_sensitive_health_data_processing' ELSE 'synthetic_test_notice' END,
   CASE WHEN n=204 THEN 'consent' ELSE 'acknowledgement' END,true,clock_timestamp()-interval '1 second');
  PERFORM public.publish_onboarding_legal_document(m3b_cycle_test.uid(n));
 END LOOP;
 INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
 VALUES(m3b_cycle_test.uid(205),'synthetic-health-1','pt-BR',ARRAY['evaluation_1_terms_notice',
  'evaluation_2_privacy_notice','evaluation_3_health_ai_notice','evaluation_4_sensitive_data_consent'],
  clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_requirement_set(m3b_cycle_test.uid(205));
END $$;
CREATE FUNCTION m3b_cycle_test.signup_health_command(a uuid,k uuid,prep uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE i jsonb;actions jsonb;
BEGIN
 i:=public.begin_mobile_signup_completion_intent(a,prep);
 SELECT jsonb_agg(jsonb_build_object('document_key',d.document_key,'version',d.version,'locale',d.locale,
  'content_hash',d.content_hash,'action',d.action_type) ORDER BY d.document_key COLLATE "C") INTO actions
 FROM public.onboarding_legal_documents d WHERE d.id IN (SELECT m3b_cycle_test.uid(n) FROM generate_series(201,204) n);
 RETURN jsonb_build_object('version',1,'operation_key',k,'intent_id',i#>>'{intent,intentID}',
  'request_key',i#>>'{intent,requestKey}','locale','pt-BR','document_actions',actions,'risks',jsonb_build_array('reduced_intake'));
END $$;
REVOKE ALL ON FUNCTION m3b_cycle_test.signup_health_command(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
