-- QA only; no outer transaction. Preflight/prefix must have passed first.
RESET ROLE;
SET LOCAL search_path=pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO,YMD';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $absence$
BEGIN
 IF to_regnamespace('c59_plan_fixture') IS NOT NULL
  OR to_regnamespace('c59s17d_fixture') IS NOT NULL
  OR EXISTS(SELECT 1 FROM public.users WHERE id='c59d2c00-0000-4000-8000-000000000901')
  OR EXISTS(SELECT 1 FROM public.onboarding_legal_documents
    WHERE id='c59d2c00-0000-4000-8000-000000000201' OR version='c59-plan-20261020')
  OR EXISTS(SELECT 1 FROM public.onboarding_legal_requirement_sets
    WHERE id='c59d2c00-0000-4000-8000-000000000301' OR version='c59-plan-20261020')
 THEN RAISE EXCEPTION 'C59PLAN_SETUP_COLLISION'; END IF;
END $absence$;
CREATE SCHEMA c59_plan_fixture AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA c59_plan_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE postgres;
CREATE TABLE c59_plan_fixture.context(key text PRIMARY KEY,value jsonb NOT NULL);
REVOKE ALL ON TABLE c59_plan_fixture.context FROM PUBLIC,anon,authenticated,service_role;

DO $signup$
DECLARE
 u constant uuid:='c59d2c00-0000-4000-8000-000000000901';
 body constant text:='C59 plan synthetic local requirement.';
 observation jsonb;admission jsonb;submission jsonb;result jsonb;receipt record;source record;scope record;
 hash text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.coach_personalities WHERE code='focus' AND active AND selectable)
 THEN RAISE EXCEPTION 'C59PLAN_SETUP_PERSONA'; END IF;
 INSERT INTO public.onboarding_legal_documents
  (id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
 VALUES('c59d2c00-0000-4000-8000-000000000201','c59_plan_test','c59-plan-20261020',
  'pt-BR',body,encode(extensions.digest(body,'sha256'),'hex'),'synthetic_local_test',
  'acceptance',true,clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_document('c59d2c00-0000-4000-8000-000000000201');
 INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
 VALUES('c59d2c00-0000-4000-8000-000000000301','c59-plan-20261020','pt-BR',
  ARRAY['c59_plan_test'],clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_requirement_set('c59d2c00-0000-4000-8000-000000000301');
 INSERT INTO public.users(id,email,name,locale,timezone,country,status)
 VALUES(u,'c59-plan-901@example.invalid','C59 plan synthetic','pt-BR','UTC','BR','active');
 INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_completed_at)
 VALUES(u,false,NULL);
 SELECT jsonb_build_object('name','C59 plan synthetic','locale','pt-BR','country','BR',
  'timezone','UTC','sex','masculino','birth_date','1990-01-01',
  'height_cm',180,'weight_kg',80,'body_fat_percent',24,'objective','recomposicao',
  'activity_level','moderado','training_frequency',4,'water_intake','moderado',
  'hunger_level','moderada','wake_time','07:00','bedtime','23:00',
  'food_organization','sim','persona','focus','document_actions',
  jsonb_build_array(jsonb_build_object('document_key',d.document_key,'version',d.version,
    'locale',d.locale,'content_hash',d.content_hash,'action',d.action_type)))
 INTO STRICT submission FROM public.onboarding_legal_documents d
 WHERE d.id='c59d2c00-0000-4000-8000-000000000201';
 -- Native synthetic hash; this is not an HTTP canonicalization/auth test.
 hash:=encode(extensions.digest(submission::text,'sha256'),'hex');
 observation:=public.observe_mobile_signup_strength_epoch(u);
 IF observation->>'status' IS DISTINCT FROM 'observed'
 THEN RAISE EXCEPTION 'C59PLAN_SETUP_OBSERVE'; END IF;
 admission:=public.admit_mobile_signup_strength_request(u,'plan-signup-20261020',hash,
  (observation#>>'{observation,epoch}')::uuid);
 IF admission->>'status' IS DISTINCT FROM 'admitted'
 THEN RAISE EXCEPTION 'C59PLAN_SETUP_ADMIT'; END IF;
 admission:=admission->'admission';
 result:=public.complete_mobile_onboarding_keyed(u,submission,'atomic',
  admission->>'requestKey',admission->>'requestHash',(admission->>'epoch')::uuid,
  (admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
 SELECT * INTO STRICT receipt FROM private.mobile_signup_strength_completion_receipts
  WHERE user_id=u AND admission_id=(admission->>'admissionID')::uuid;
 SELECT * INTO STRICT source FROM private.strength_week_source_versions
  WHERE user_id=u AND generation=receipt.generation AND source_version_id=receipt.frequency_source_version_id;
 SELECT * INTO STRICT scope FROM private.strength_week_scopes WHERE user_id=u AND generation=receipt.generation;
 IF receipt.outcome<>'first_fresh' OR receipt.epoch<>(admission->>'epoch')::uuid
  OR receipt.completion_result IS DISTINCT FROM result OR result->'onboarding_completed'<>'true'::jsonb
  OR receipt.completed_at<>(result->>'completed_at')::timestamptz
  OR source.source_kind<>'informed_frequency' OR source.fact<>'value' OR source.planned_days<>4
  OR source.observed_timezone<>'UTC'
  OR source.operation_namespace<>'mobile_signup_completion_v1' OR source.operation_key<>receipt.admission_id::text
  OR scope.open_operation_namespace<>'mobile_signup_completion_v1' OR scope.open_operation_key<>receipt.admission_id::text
  OR scope.predecessor_generation IS NOT NULL OR scope.closed_at IS NOT NULL
  OR scope.opened_at>source.observed_at OR source.observed_at>receipt.recorded_at
  OR EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u)
  OR EXISTS(SELECT 1 FROM public.messages WHERE user_id=u)
 THEN RAISE EXCEPTION 'C59PLAN_SETUP_REAL_KEYED_PROVENANCE'; END IF;
 INSERT INTO c59_plan_fixture.context VALUES
  ('owner',to_jsonb(u)),('signup_admission',admission),('signup_result',result),
  ('signup_receipt',to_jsonb(receipt)),('source',to_jsonb(source)),('generation',to_jsonb(receipt.generation)),('submission',submission);
 RAISE NOTICE 'C59PLAN_CONTROL_REAL_KEYED_FIRST_FRESH_NATURAL_SOURCE_NO_FLOW';
END $signup$;

RESET ROLE;
