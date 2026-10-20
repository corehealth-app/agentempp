-- QA only; no outer transaction. Preflight/prefix must have passed first.
RESET ROLE;
SET LOCAL search_path=pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO,YMD';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $absence$
BEGIN
 IF to_regnamespace('c59_bridge_fixture') IS NOT NULL
  OR to_regnamespace('c59s17d_fixture') IS NOT NULL
  OR EXISTS(SELECT 1 FROM public.users WHERE id='c59b2600-0000-4000-8000-000000000901')
  OR EXISTS(SELECT 1 FROM public.onboarding_legal_documents
    WHERE id='c59b2600-0000-4000-8000-000000000201' OR version='c59-bridge-20261020')
  OR EXISTS(SELECT 1 FROM public.onboarding_legal_requirement_sets
    WHERE id='c59b2600-0000-4000-8000-000000000301' OR version='c59-bridge-20261020')
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_COLLISION'; END IF;
END $absence$;
CREATE SCHEMA c59_bridge_fixture AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA c59_bridge_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE postgres;
CREATE TABLE c59_bridge_fixture.context(key text PRIMARY KEY,value jsonb NOT NULL);
REVOKE ALL ON TABLE c59_bridge_fixture.context FROM PUBLIC,anon,authenticated,service_role;

DO $signup$
DECLARE
 u constant uuid:='c59b2600-0000-4000-8000-000000000901';
 body constant text:='C59 bridge synthetic local requirement.';
 observation jsonb;admission jsonb;submission jsonb;result jsonb;receipt record;source record;scope record;
 hash text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.coach_personalities WHERE code='focus' AND active AND selectable)
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_PERSONA'; END IF;
 INSERT INTO public.onboarding_legal_documents
  (id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
 VALUES('c59b2600-0000-4000-8000-000000000201','c59_bridge_test','c59-bridge-20261020',
  'pt-BR',body,encode(extensions.digest(body,'sha256'),'hex'),'synthetic_local_test',
  'acceptance',true,clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_document('c59b2600-0000-4000-8000-000000000201');
 INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
 VALUES('c59b2600-0000-4000-8000-000000000301','c59-bridge-20261020','pt-BR',
  ARRAY['c59_bridge_test'],clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_requirement_set('c59b2600-0000-4000-8000-000000000301');
 INSERT INTO public.users(id,email,name,locale,timezone,country,status)
 VALUES(u,'c59-bridge-901@example.invalid','C59 bridge synthetic','pt-BR','UTC','BR','active');
 INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_completed_at)
 VALUES(u,false,NULL);
 SELECT jsonb_build_object('name','C59 bridge synthetic','locale','pt-BR','country','BR',
  'timezone','UTC','sex','masculino','birth_date','1990-01-01',
  'height_cm',180,'weight_kg',80,'body_fat_percent',24,'objective','recomposicao',
  'activity_level','moderado','training_frequency',4,'water_intake','moderado',
  'hunger_level','moderada','wake_time','07:00','bedtime','23:00',
  'food_organization','sim','persona','focus','document_actions',
  jsonb_build_array(jsonb_build_object('document_key',d.document_key,'version',d.version,
    'locale',d.locale,'content_hash',d.content_hash,'action',d.action_type)))
 INTO STRICT submission FROM public.onboarding_legal_documents d
 WHERE d.id='c59b2600-0000-4000-8000-000000000201';
 -- Native synthetic hash; this is not an HTTP canonicalization/auth test.
 hash:=encode(extensions.digest(submission::text,'sha256'),'hex');
 observation:=public.observe_mobile_signup_strength_epoch(u);
 IF observation->>'status' IS DISTINCT FROM 'observed'
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_OBSERVE'; END IF;
 admission:=public.admit_mobile_signup_strength_request(u,'bridge-signup-20261020',hash,
  (observation#>>'{observation,epoch}')::uuid);
 IF admission->>'status' IS DISTINCT FROM 'admitted'
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_ADMIT'; END IF;
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
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_REAL_KEYED_PROVENANCE'; END IF;
 INSERT INTO c59_bridge_fixture.context VALUES
  ('owner',to_jsonb(u)),('signup_admission',admission),('signup_result',result),
  ('signup_receipt',to_jsonb(receipt)),('source',to_jsonb(source)),('generation',to_jsonb(receipt.generation)),('submission',submission);
 RAISE NOTICE 'C59BRIDGE_CONTROL_REAL_KEYED_FIRST_FRESH_NATURAL_SOURCE_NO_FLOW';
END $signup$;

RESET ROLE;
CREATE SCHEMA c59s17d_fixture AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA c59s17d_fixture FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE postgres;
CREATE FUNCTION c59s17d_fixture.uid(i integer) RETURNS uuid LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT ('c59d7000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid $f$;

CREATE FUNCTION c59s17d_fixture.key(i integer) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT 'wui1:'||c59s17d_fixture.uid(i)::text $f$;

CREATE FUNCTION c59s17d_fixture.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $f$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S17D_ASSERT:%',label;END IF;RAISE NOTICE 'C59S17D_PASS:%',label;END $f$;

CREATE FUNCTION c59s17d_fixture.input(duration integer DEFAULT 40,raw text DEFAULT 'c59s17d-treino',performed text DEFAULT NULL) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('kind','workout','workout_type',raw,'duration_min',duration,'intensity','moderada')||CASE WHEN performed IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('performed_at',performed)END $f$;

CREATE FUNCTION c59s17d_fixture.proposal(k text,v jsonb,kcal integer DEFAULT 400,ts text DEFAULT '2026-10-15T12:00:00.123Z') RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('kind','workout','workoutType',v->>'workout_type','durationMin',v->'duration_min','kcalEst',kcal,'intensity',v->>'intensity',
 'sourceContentType','mobile','source_provider_message_id',k,'source_timestamp',ts,'source_timezone','UTC','source_local_date',left(ts,10),
 'raw_args',jsonb_build_object('workout_type',v->>'workout_type','duration_min',v->'duration_min','intensity',v->>'intensity'),'express_eligible',false) $f$;

CREATE FUNCTION c59s17d_fixture.attempt(sql text,role_name text DEFAULT 'service_role') RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $f$
DECLARE r jsonb;s text;m text;BEGIN EXECUTE format('SET LOCAL ROLE %I',role_name);
 BEGIN EXECUTE sql INTO r;EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;END;
 SET LOCAL ROLE NONE;IF s IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'sqlstate',s,'message',m);END IF;
 RETURN jsonb_build_object('ok',true,'result',r);END $f$;

CREATE FUNCTION c59s17d_fixture.member(u uuid,k text,v jsonb,kcal integer DEFAULT 400) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $f$
DECLARE r jsonb;a jsonb;p jsonb:=c59s17d_fixture.proposal(k,v,kcal);e timestamptz:=clock_timestamp()+interval '6 hours';BEGIN
 r:=c59s17d_fixture.attempt(format('SELECT public.admit_mobile_workout_registration(%L,%L,%L::jsonb)',u,k,v));
 IF r->'ok' IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_ADMIT:%',r;END IF;a:=r#>'{result,admission}';
 r:=c59s17d_fixture.attempt(format('SELECT public.materialize_mobile_workout_registration(%L,%L,%L::jsonb,%L::jsonb,%L::timestamptz)',u,a->>'admissionID',v,p,e));
 IF r->'ok'IS DISTINCT FROM 'true'::jsonb OR r#>>'{result,status}'IS DISTINCT FROM 'materialized' THEN RAISE EXCEPTION 'C59S17D_SETUP_REAL_MATERIALIZE:%',r;END IF;
 RETURN jsonb_build_object('ownerID',u,'requestKey',k,'input',v,'proposal',p,'expiresAt',e,'admission',a,'materialized',r->'result','registrationID',r#>'{result,pendingID}');END $f$;

CREATE FUNCTION c59s17d_fixture.confirm_sql(u uuid,pid uuid,expected integer,a jsonb,o jsonb,d jsonb)RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT format('SELECT public.confirm_mobile_workout_registration(%L::uuid,%L::uuid,%L::integer,%L::jsonb,%L::jsonb,%L::jsonb)',u,pid,expected,a,o,d) $f$;

CREATE FUNCTION c59s17d_fixture.legacy_arguments(u uuid,p jsonb,day text DEFAULT NULL,kcal integer DEFAULT 525)RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT jsonb_build_object('p_user_id',u,'p_date',coalesce(day,p->>'source_local_date'),'p_workout_type',p->'workoutType','p_duration_min',p->'durationMin','p_estimated_kcal',kcal,'p_intensity',p->'intensity','p_notes','S17D café 🏋️','p_performed_at',p->'source_timestamp','p_provider_message_id',p->'source_provider_message_id','p_calories_target',2200,'p_protein_target',150.125,'p_replace_recent',false,'p_replace_since',NULL) $f$;

CREATE FUNCTION c59s17d_fixture.catalogue_decision(o jsonb,raw text)RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $f$
 SELECT CASE WHEN raw='c59s17d-treino'THEN jsonb_build_object('status','matched','observationKey',o->'observationKey','matcherVersion',o->'matcherVersion','originalOperationType',raw,'method','active_slug','selectedRowID',c59s17d_fixture.uid(9901))
 ELSE jsonb_build_object('status','unrecognized','observationKey',o->'observationKey','matcherVersion',o->'matcherVersion','originalOperationType',raw,'reason','no_active_match')END $f$;

CREATE FUNCTION c59s17d_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id'AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY to_jsonb(x)::text),''[]''::jsonb)FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c59s17d_fixture FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION c59_bridge_fixture.new_owner(u uuid) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $qa$
BEGIN
 IF EXISTS(SELECT 1 FROM public.users WHERE id=u) THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_OWNER_COLLISION'; END IF;
 INSERT INTO public.users(id,email,name,locale,timezone,country,status)
 VALUES(u,'c59-bridge-'||u::text||'@example.invalid','C59 bridge synthetic','pt-BR','UTC','BR','active');
 INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_completed_at) VALUES(u,false,NULL);
END $qa$;

CREATE FUNCTION c59_bridge_fixture.finish_signup(u uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $qa$
DECLARE submission jsonb;observation jsonb;admission jsonb;result jsonb;receipt record;source record;hash text;
BEGIN
 SELECT value INTO STRICT submission FROM c59_bridge_fixture.context WHERE key='submission';
 hash:=encode(extensions.digest(submission::text,'sha256'),'hex');
 observation:=public.observe_mobile_signup_strength_epoch(u);
 IF observation->>'status' IS DISTINCT FROM 'observed' THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_OBSERVE'; END IF;
 admission:=public.admit_mobile_signup_strength_request(u,'bridge-signup-'||u::text,hash,
  (observation#>>'{observation,epoch}')::uuid);
 IF admission->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_ADMIT'; END IF;
 admission:=admission->'admission';
 result:=public.complete_mobile_onboarding_keyed(u,submission,'atomic',admission->>'requestKey',
  admission->>'requestHash',(admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
 SELECT * INTO STRICT receipt FROM private.mobile_signup_strength_completion_receipts
  WHERE user_id=u AND admission_id=(admission->>'admissionID')::uuid;
 SELECT * INTO STRICT source FROM private.strength_week_source_versions
  WHERE user_id=u AND generation=receipt.generation AND source_version_id=receipt.frequency_source_version_id;
 IF receipt.outcome<>'first_fresh' OR receipt.completion_result IS DISTINCT FROM result
  OR receipt.epoch<>(admission->>'epoch')::uuid OR source.source_kind<>'informed_frequency'
  OR source.fact<>'value' OR source.planned_days<>4 OR source.observed_timezone<>'UTC'
  OR source.operation_namespace<>'mobile_signup_completion_v1' OR source.operation_key<>receipt.admission_id::text
  OR EXISTS(SELECT 1 FROM public.messages WHERE user_id=u)
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_ADDITIONAL_REAL_SIGNUP'; END IF;
 RETURN jsonb_build_object('admission',admission,'receipt',to_jsonb(receipt),'result',result);
END $qa$;

CREATE FUNCTION c59_bridge_fixture.confirm(u uuid,k integer) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $qa$
DECLARE x jsonb;obs jsonb;result jsonb;
BEGIN
 x:=c59s17d_fixture.member(u,c59s17d_fixture.key(k),
  c59s17d_fixture.input(40,'c59bridge-noncatalogue-'||k::text||'-20261020'));
 obs:=public.get_workout_strength_catalogue_context();
 result:=c59s17d_fixture.attempt(c59s17d_fixture.confirm_sql(u,(x->>'registrationID')::uuid,0,
  c59s17d_fixture.legacy_arguments(u,x->'proposal'),obs,
  c59s17d_fixture.catalogue_decision(obs,x#>>'{proposal,workoutType}')));
 IF result->'ok' IS DISTINCT FROM 'true'::jsonb OR result#>>'{result,status}' IS DISTINCT FROM 'confirmed'
  OR result#>>'{result,capture,strength,status}' IS DISTINCT FROM 'committed'
 THEN RAISE EXCEPTION 'C59BRIDGE_SETUP_ADDITIONAL_CONFIRMATION:%',result; END IF;
 RETURN x||jsonb_build_object('confirmed',result->'result');
END $qa$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c59_bridge_fixture FROM PUBLIC,anon,authenticated,service_role;
