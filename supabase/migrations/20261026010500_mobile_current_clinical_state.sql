-- Dormant current mobile clinical observation. No public RPC/grant/consumer.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.mobile_signup_clinical_safety_at(uuid,jsonb,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'mobile_current_clinical_requires_signup_safety' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION private.capture_mobile_current_clinical_state_at(p_user_id uuid,p_mode text,
 p_body jsonb,p_expected jsonb,p_observed_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE p public.user_profiles%ROWTYPE;u public.users%ROWTYPE;present boolean;epoch uuid;
 body jsonb;expected_token jsonb;token jsonb;health jsonb;safety jsonb;config jsonb;origin jsonb;anchor jsonb;
 observed timestamptz;day date;zone text;receipt_count bigint;generation uuid;first_completion boolean;
 missing text[]:='{}';birth date;height numeric;weight numeric;fat numeric;wire jsonb;profile_hash text;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_mode IS NULL OR p_mode NOT IN('signup','profile')
  OR (p_mode='profile' AND p_body IS NOT NULL AND p_body<>'null'::jsonb)
  OR (p_expected IS NOT NULL AND (jsonb_typeof(p_expected)<>'object' OR p_expected-ARRAY['epoch','generation_token']<>'{}'::jsonb)) THEN
  RAISE EXCEPTION 'invalid_mobile_current_clinical_input' USING ERRCODE='22023';
 END IF;
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 BEGIN
  SELECT * INTO p FROM public.user_profiles WHERE user_id=p_user_id FOR SHARE NOWAIT;
  present:=FOUND;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'mobile_clinical_busy' USING ERRCODE='55P03'; END;
 SELECT * INTO STRICT u FROM public.users WHERE id=p_user_id;
 SELECT e.epoch INTO epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id;
 SELECT count(*) INTO receipt_count FROM private.signup_body_photo_receipts WHERE user_id=p_user_id;
 IF receipt_count>9007199254740991 THEN RAISE EXCEPTION 'mobile_current_clinical_token_overflow' USING ERRCODE='22003'; END IF;
 token:=CASE WHEN present THEN jsonb_build_object('onboarding_completed',p.onboarding_completed,
  'onboarding_completed_at',CASE WHEN p.onboarding_completed_at IS NOT NULL THEN
   to_char(p.onboarding_completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,'receipt_count',receipt_count) END;
 IF p_expected ? 'epoch' THEN
  IF p_expected->'epoch'<>'null'::jsonb AND (jsonb_typeof(p_expected->'epoch')<>'string'
   OR p_expected->>'epoch' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
   RAISE EXCEPTION 'invalid_mobile_current_clinical_input' USING ERRCODE='22023'; END IF;
  IF (p_expected->>'epoch')::uuid IS DISTINCT FROM epoch THEN
   RAISE EXCEPTION 'mobile_current_clinical_changed' USING ERRCODE='40001'; END IF;
 END IF;
 IF p_expected ? 'generation_token' THEN
  expected_token:=p_expected->'generation_token';
  IF jsonb_typeof(expected_token) IS DISTINCT FROM 'object'
   OR NOT(expected_token ?& ARRAY['onboarding_completed','onboarding_completed_at','receipt_count'])
   OR expected_token-ARRAY['onboarding_completed','onboarding_completed_at','receipt_count']<>'{}'::jsonb
   OR jsonb_typeof(expected_token->'onboarding_completed') IS DISTINCT FROM 'boolean'
   OR jsonb_typeof(expected_token->'onboarding_completed_at') NOT IN('string','null')
   OR jsonb_typeof(expected_token->'receipt_count') IS DISTINCT FROM 'number'
   OR (expected_token->>'receipt_count')::numeric<>trunc((expected_token->>'receipt_count')::numeric)
   OR (expected_token->>'receipt_count')::numeric NOT BETWEEN 0 AND 9007199254740991 THEN
   RAISE EXCEPTION 'invalid_mobile_current_clinical_input' USING ERRCODE='22023'; END IF;
  IF NOT present OR (expected_token->>'onboarding_completed')::boolean IS DISTINCT FROM p.onboarding_completed
   OR (expected_token->>'onboarding_completed_at')::timestamptz IS DISTINCT FROM p.onboarding_completed_at
   OR (expected_token->>'receipt_count')::bigint IS DISTINCT FROM receipt_count THEN
   RAISE EXCEPTION 'mobile_current_clinical_changed' USING ERRCODE='40001'; END IF;
 END IF;
 LOCK TABLE public.global_config IN SHARE MODE;
 observed:=coalesce(p_observed_at,clock_timestamp());
 zone:=CASE WHEN p_mode='signup' THEN p_body->>'timezone' ELSE u.timezone END;
 IF NOT isfinite(observed) OR extract(year FROM observed AT TIME ZONE 'UTC') NOT BETWEEN 1 AND 9999
  OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN
  RAISE EXCEPTION 'invalid_mobile_current_clinical_input' USING ERRCODE='22023'; END IF;
 day:=(observed AT TIME ZONE zone)::date;
 IF p_mode='signup' THEN
  IF jsonb_typeof(p_body) IS DISTINCT FROM 'object'
   OR NOT(p_body ?& ARRAY['locale','timezone','sex','birth_date','height_cm','weight_kg','body_fat_percent','training_frequency'])
   OR p_body-ARRAY['locale','timezone','sex','birth_date','height_cm','weight_kg','body_fat_percent','training_frequency']<>'{}'::jsonb
   OR jsonb_typeof(p_body->'birth_date') IS DISTINCT FROM 'string'
   OR jsonb_typeof(p_body->'locale') IS DISTINCT FROM 'string' OR p_body->>'locale' NOT IN('pt-BR','en-US')
   OR jsonb_typeof(p_body->'sex') IS DISTINCT FROM 'string' OR p_body->>'sex' NOT IN('masculino','feminino')
   OR jsonb_typeof(p_body->'height_cm') IS DISTINCT FROM 'number'
   OR jsonb_typeof(p_body->'weight_kg') IS DISTINCT FROM 'number'
   OR jsonb_typeof(p_body->'body_fat_percent') NOT IN('number','null')
   OR jsonb_typeof(p_body->'training_frequency') IS DISTINCT FROM 'number'
   OR (p_body->>'training_frequency')::numeric NOT BETWEEN 0 AND 7
   OR (p_body->>'training_frequency')::numeric<>trunc((p_body->>'training_frequency')::numeric) THEN
   RAISE EXCEPTION 'invalid_mobile_current_clinical_input' USING ERRCODE='22023'; END IF;
  body:=p_body||jsonb_build_object('height_cm',round((p_body->>'height_cm')::numeric,2),
   'weight_kg',round((p_body->>'weight_kg')::numeric,2),'body_fat_percent',round((p_body->>'body_fat_percent')::numeric,2));
  safety:=private.mobile_signup_clinical_safety_at(p_user_id,body,observed);
 ELSE
  -- Unsupported/missing legacy fields become explicit unknowns in this
  -- observation, never substitutions or writes to the persisted profile.
  birth:=p.birth_date;height:=p.height_cm;weight:=p.weight_kg;fat:=p.body_fat_percent;
  IF birth IS NULL OR NOT isfinite(birth) OR extract(year FROM birth) NOT BETWEEN 1 AND 9999 OR birth>day THEN
   missing:=array_append(missing,'birth_date');birth:=NULL; END IF;
  IF height IS NULL OR height NOT BETWEEN 100 AND 250 THEN missing:=array_append(missing,'height_cm');height:=NULL; END IF;
  IF weight IS NULL OR weight NOT BETWEEN 30 AND 300 THEN missing:=array_append(missing,'weight_kg');weight:=NULL; END IF;
  IF fat IS NOT NULL AND fat NOT BETWEEN 3 AND 60 THEN missing:=array_append(missing,'body_fat_percent');fat:=NULL; END IF;
  body:=jsonb_build_object('locale',u.locale,'timezone',zone,'sex',p.sex,'birth_date',birth,
   'height_cm',height,'weight_kg',weight,'body_fat_percent',fat,'training_frequency',p.training_frequency);
  IF cardinality(missing)=0 THEN safety:=private.mobile_signup_clinical_safety_at(p_user_id,body,observed); END IF;
 END IF;
 health:=private.mobile_health_state_wire(p_user_id);
 first_completion:=p.onboarding_completed_at IS NULL;
 IF present AND p.onboarding_completed AND p.onboarding_completed_at IS NOT NULL THEN
  anchor:=private.mobile_reevaluation_context_at(p_user_id,observed);
  generation:=(anchor->>'signup_generation')::uuid;
  IF p.current_protocol IS NOT NULL THEN origin:=jsonb_build_object('kind','assigned','phase',p.current_protocol);
  ELSE
   origin:=private.mobile_clinical_signup_no_plan_origin(p_user_id,generation,epoch);
   origin:=coalesce(origin,jsonb_build_object('kind','legacy_unassigned'));
  END IF;
 ELSE origin:=jsonb_build_object('kind','not_completed'); END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('key',c.key,'value',c.value,
  'updated_at',to_char(c.updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')) ORDER BY c.key),'[]'::jsonb)
 INTO config FROM public.global_config c WHERE c.key LIKE 'calc.%';
 profile_hash:=encode(extensions.digest(jsonb_build_object('present',present,'onboarding_completed',p.onboarding_completed,
  'onboarding_completed_at',p.onboarding_completed_at,'protocol',p.current_protocol,'deficit',p.deficit_level,
  'birth_date',p.birth_date,'height_cm',p.height_cm,'weight_kg',p.weight_kg,'body_fat_percent',p.body_fat_percent,
  'sex',p.sex,'training_frequency',p.training_frequency,'updated_at',p.updated_at)::text,'sha256'),'hex');
 wire:=jsonb_build_object('version',1,'user_id',p_user_id,'mode',p_mode,'profile_present',present,
  'epoch',epoch,'signup_generation',generation,'generation_token',token,'first_completion',first_completion,
  'observed_at',to_char(observed AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'date',day::text,
  'timezone',zone,'body',body,'assessment',CASE WHEN cardinality(missing)=0 THEN 'complete' ELSE 'incomplete' END,
  'missing',to_jsonb(missing),'health_state',health,'safety',safety,'phase_origin',origin,
  'calculation_config',config,'profile_hash',profile_hash);
 RETURN wire||jsonb_build_object('context_hash',encode(extensions.digest(wire::text,'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION private.capture_mobile_current_clinical_state_at(uuid,text,jsonb,jsonb,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
