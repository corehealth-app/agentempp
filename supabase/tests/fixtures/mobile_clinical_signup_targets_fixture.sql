\ir mobile_signup_health_fixture.sql
-- Actual keyed signup and origin trigger, using synthetic legal catalogue and
-- account data. No historical receipt insert, photo/provider or fake FULL.
CREATE FUNCTION m3b_cycle_test.signup_target_context(n integer,phase text,zone text DEFAULT 'America/Sao_Paulo')
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid;actions jsonb;submission jsonb;observation jsonb;admission jsonb;result jsonb;k text;
BEGIN
 IF n NOT BETWEEN 6300 AND 6399 OR (phase IS NOT NULL AND phase NOT IN('recomposicao','manutencao','ganho_massa')) THEN
  RAISE EXCEPTION 'invalid_signup_target_fixture';END IF;
 a:=m3b_cycle_test.seed(n,NULL,zone);k:='signup-target-'||n;
 SELECT jsonb_agg(jsonb_build_object('document_key',d.document_key,'version',d.version,'locale',d.locale,
  'content_hash',d.content_hash,'action',d.action_type) ORDER BY d.document_key COLLATE "C") INTO actions
 FROM public.onboarding_legal_documents d WHERE d.id IN(SELECT m3b_cycle_test.uid(i) FROM generate_series(201,204)i);
 submission:=jsonb_build_object('name','M3B synthetic first target','locale','pt-BR','country','BR','timezone',zone,
  'sex','masculino','birth_date',CASE WHEN phase IS NULL THEN '2012-01-01' ELSE '1990-01-01' END,
  'height_cm',180,'weight_kg',80,'body_fat_percent',CASE WHEN phase='ganho_massa' THEN 15 ELSE 24 END,
  'objective',phase,'activity_level','moderado','training_frequency',4,'water_intake',NULL,'hunger_level','moderada',
  'wake_time','07:00','bedtime','23:00','food_organization','sim','persona','focus','document_actions',actions);
 observation:=public.observe_mobile_signup_strength_epoch(a);
 admission:=public.admit_mobile_signup_strength_request(a,k,repeat('d',64),(observation#>>'{observation,epoch}')::uuid)->'admission';
 result:=public.complete_mobile_onboarding_keyed(a,submission,'atomic',k,repeat('d',64),
  (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
 RETURN jsonb_build_object('user',a,'signup',result,'generation',admission->'admissionID','epoch',admission->'epoch');
END $$;
REVOKE ALL ON FUNCTION m3b_cycle_test.signup_target_context(integer,text,text) FROM PUBLIC,anon,authenticated,service_role;
