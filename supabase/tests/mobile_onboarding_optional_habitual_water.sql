\set ON_ERROR_STOP on
-- Water omission/null, historical enums, replay, and real photo delegates.
-- Test-only synthetic local target; every fixture and effect rolls back.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';
DO $target$
BEGIN
  IF session_user <> 'c5_local_admin' OR current_user <> 'c5_local_admin'
    OR current_database() <> 'c5_reset_default_20261009'
    OR current_setting('port') <> '55489'
    OR current_setting('server_version_num') <> '170011'
    OR current_setting('data_directory') <>
      '/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
    OR current_setting('unix_socket_directories') <> '/private/tmp/performe-c5-osecmg7_'
    OR inet_server_addr() IS NOT NULL
    OR current_setting('listen_addresses') <> '' THEN
    RAISE EXCEPTION 'OW1_SETUP_WRONG_LOCAL_TARGET';
  END IF;
  IF to_regprocedure('public.complete_mobile_onboarding_atomic(uuid,jsonb)') IS NULL
    OR to_regprocedure('public.publish_onboarding_legal_document(uuid)') IS NULL
    OR to_regprocedure('public.publish_onboarding_legal_requirement_set(uuid)') IS NULL
    OR to_regprocedure('public.complete_mobile_onboarding_with_body_photo_confirmation(uuid,jsonb,jsonb,boolean,timestamptz,bigint)') IS NULL
    OR to_regprocedure('public.complete_mobile_onboarding_with_cleanup_scope(uuid,jsonb,jsonb,boolean,timestamptz,bigint)') IS NULL THEN
    RAISE EXCEPTION 'OW1_SETUP_MISSING_EXISTING_SUBSTRATE';
  END IF;
END $target$;
SET LOCAL ROLE postgres;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
DO $baseline$
DECLARE
  owner_id constant uuid := 'c59c2a00-0000-4000-8000-000000000101';
  document_id constant uuid := 'c59c2a00-0000-4000-8000-000000000201';
  requirement_id constant uuid := 'c59c2a00-0000-4000-8000-000000000301';
  document_body constant text := 'C59 signup synthetic requirement. Local test only.';
  document_hash text := encode(extensions.digest(document_body, 'sha256'), 'hex');
  submission jsonb;
  result jsonb;
  selected_requirement uuid;
  actor_id uuid; expected public.water_enum; mode integer; patch jsonb; replay jsonb;
BEGIN
  IF current_user <> 'postgres'
    OR EXISTS (SELECT 1 FROM public.users WHERE id = owner_id
      OR email = 'ow-water-101@example.invalid')
    OR EXISTS (SELECT 1 FROM public.onboarding_legal_documents
      WHERE id = document_id OR version = 'ow-water-20261022')
    OR EXISTS (SELECT 1 FROM public.onboarding_legal_requirement_sets
      WHERE id = requirement_id OR version = 'ow-water-20261022') THEN
    RAISE EXCEPTION 'OW1_SETUP_ROLE_OR_FIXTURE_COLLISION';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.coach_personalities
    WHERE code = 'focus' AND active AND selectable) THEN
    RAISE EXCEPTION 'OW1_SETUP_EXISTING_PERSONA_MISSING';
  END IF;

  INSERT INTO public.users (id, email, name, locale, timezone, country, status)
    VALUES (owner_id, 'ow-water-101@example.invalid', 'C59 synthetic QA',
      'pt-BR', 'America/Sao_Paulo', 'BR', 'active');
  INSERT INTO public.user_profiles (user_id, onboarding_completed)
    VALUES (owner_id, false);
  INSERT INTO public.onboarding_legal_documents (
    id, document_key, version, locale, body, content_hash, purpose,
    action_type, required, effective_at
  ) VALUES (document_id, 'ow_water_test', 'ow-water-20261022', 'pt-BR',
    document_body, document_hash, 'synthetic_local_test', 'acceptance', true,
    clock_timestamp() - interval '1 second');
  PERFORM public.publish_onboarding_legal_document(document_id);
  INSERT INTO public.onboarding_legal_requirement_sets (
    id, version, locale, document_keys, effective_at
  ) VALUES (requirement_id, 'ow-water-20261022', 'pt-BR',
    ARRAY['ow_water_test'], clock_timestamp() - interval '1 second');
  -- Real publication may archive local sets inside this rollback-only transaction.
  PERFORM public.publish_onboarding_legal_requirement_set(requirement_id);
  SELECT s.id INTO selected_requirement
    FROM public.onboarding_legal_requirement_sets s
    WHERE s.locale = 'pt-BR' AND s.publication_status = 'published'
      AND s.effective_at <= clock_timestamp() AND s.published_at <= clock_timestamp()
    ORDER BY s.effective_at DESC, s.published_at DESC, s.id DESC LIMIT 1;
  IF selected_requirement IS DISTINCT FROM requirement_id THEN
    RAISE EXCEPTION 'OW1_SETUP_SYNTHETIC_REQUIREMENT_NOT_CURRENT';
  END IF;
  submission := jsonb_build_object(
    'name', 'C59 synthetic QA', 'locale', 'pt-BR', 'country', 'BR',
    'timezone', 'America/Sao_Paulo', 'sex', 'masculino', 'birth_date', '1990-01-01',
    'height_cm', 180, 'weight_kg', 80, 'body_fat_percent', 24,
    'objective', 'recomposicao', 'activity_level', 'moderado', 'training_frequency', 4,
    'water_intake', 'moderado', 'hunger_level', 'moderada', 'wake_time', '07:00',
    'bedtime', '23:00', 'food_organization', 'sim', 'persona', 'focus',
    'document_actions', jsonb_build_array(jsonb_build_object(
      'document_key', 'ow_water_test', 'version', 'ow-water-20261022',
      'locale', 'pt-BR', 'content_hash', document_hash, 'action', 'acceptance')));
  IF NOT EXISTS (SELECT 1 FROM public.user_profiles
    WHERE user_id = owner_id AND onboarding_completed IS FALSE
      AND onboarding_completed_at IS NULL) THEN
    RAISE EXCEPTION 'OW1_SETUP_NOT_STRICT_FRESH';
  END IF;

  FOR mode IN 1..8 LOOP
    actor_id := ('c59c2a00-0000-4000-8000-' || lpad((300 + mode)::text, 12, '0'))::uuid;
    INSERT INTO public.users (id,email,name,locale,timezone,country,status)
      VALUES (actor_id,'ow-water-'||mode||'@example.invalid','C59 synthetic QA',
        'pt-BR','America/Sao_Paulo','BR','active');
    INSERT INTO public.user_profiles(user_id,onboarding_completed,water_intake)
      VALUES(actor_id,false,CASE WHEN mode=6 THEN 'bastante'::public.water_enum ELSE NULL END);
    patch := submission - 'water_intake';
    IF mode=2 THEN patch := patch || '{"water_intake":null}'::jsonb; END IF;
    IF mode BETWEEN 3 AND 5 THEN
      patch := patch || jsonb_build_object('water_intake',(ARRAY['pouco','moderado','bastante'])[mode-2]);
    END IF;
    expected := CASE WHEN mode BETWEEN 3 AND 5 THEN (ARRAY['pouco','moderado','bastante'])[mode-2]::public.water_enum
      WHEN mode=6 THEN 'bastante'::public.water_enum ELSE NULL END;
    IF mode=7 THEN
      result := public.complete_mobile_onboarding_with_body_photo_confirmation(actor_id,patch,NULL,false,NULL,0);
    ELSIF mode=8 THEN
      result := public.complete_mobile_onboarding_with_cleanup_scope(actor_id,patch,NULL,false,NULL,0);
    ELSE
      result := public.complete_mobile_onboarding_atomic(actor_id,patch);
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.user_profiles WHERE user_id=actor_id
      AND onboarding_completed AND water_intake IS NOT DISTINCT FROM expected) THEN
      RAISE EXCEPTION 'OW_ASSERT:first_completion_water_%',mode;
    END IF;
    replay := public.complete_mobile_onboarding_atomic(actor_id,patch || '{"water_intake":null}'::jsonb);
    IF replay IS DISTINCT FROM result THEN RAISE EXCEPTION 'OW_ASSERT:replay_%',mode; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.user_profiles WHERE user_id=actor_id
      AND water_intake IS NOT DISTINCT FROM expected) THEN RAISE EXCEPTION 'OW_ASSERT:preservation_%',mode; END IF;
    BEGIN
      PERFORM public.complete_mobile_onboarding_atomic(actor_id,patch || jsonb_build_object('water_intake',
        CASE WHEN expected='bastante' THEN 'pouco' ELSE 'bastante' END));
      RAISE EXCEPTION 'OW_ASSERT:changed_old_answer_accepted';
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM <> 'onboarding_already_completed' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'OW_PASS:first_replay_and_preservation_%',mode;
  END LOOP;
  FOR patch IN SELECT value FROM jsonb_array_elements('[0,true,"invalid","",{},[]]'::jsonb) LOOP
    BEGIN
      PERFORM public.complete_mobile_onboarding_atomic(owner_id,submission || jsonb_build_object('water_intake',patch));
      RAISE EXCEPTION 'OW_ASSERT:invalid_water_accepted';
    EXCEPTION WHEN invalid_parameter_value THEN
      IF SQLERRM <> 'invalid_onboarding_submission' THEN RAISE; END IF;
    END;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM public.user_profiles WHERE user_id=owner_id AND NOT onboarding_completed
    AND water_intake IS NULL) THEN RAISE EXCEPTION 'OW_ASSERT:invalid_input_mutated_profile'; END IF;
  RAISE NOTICE 'OW_PASS:invalid_types_before_mutation';
  -- Publish a new immutable version, then re-accept with unknown water.
  INSERT INTO public.onboarding_legal_documents (
    id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at
  ) VALUES ('c59c2a00-0000-4000-8000-000000000202','ow_water_test','ow-water-20261022-v2',
    'pt-BR',document_body,document_hash,'synthetic_local_test','acceptance',true,clock_timestamp());
  PERFORM public.publish_onboarding_legal_document('c59c2a00-0000-4000-8000-000000000202');
  patch := (submission - 'water_intake') || jsonb_build_object('document_actions',jsonb_build_array(
    jsonb_build_object('document_key','ow_water_test','version','ow-water-20261022-v2',
      'locale','pt-BR','content_hash',document_hash,'action','acceptance')));
  FOR mode IN 1..6 LOOP
    actor_id := ('c59c2a00-0000-4000-8000-' || lpad((300 + mode)::text, 12, '0'))::uuid;
    result := public.complete_mobile_onboarding_atomic(actor_id,patch);
    replay := public.complete_mobile_onboarding_atomic(actor_id,patch || '{"water_intake":null}'::jsonb);
    IF result IS DISTINCT FROM replay OR NOT EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions
      WHERE user_id=actor_id AND legal_document_id='c59c2a00-0000-4000-8000-000000000202') THEN
      RAISE EXCEPTION 'OW_ASSERT:real_reconsent_%',mode;
    END IF;
    expected := CASE WHEN mode BETWEEN 3 AND 5 THEN (ARRAY['pouco','moderado','bastante'])[mode-2]::public.water_enum
      WHEN mode=6 THEN 'bastante'::public.water_enum ELSE NULL END;
    IF NOT EXISTS(SELECT 1 FROM public.user_profiles WHERE user_id=actor_id
      AND water_intake IS NOT DISTINCT FROM expected) THEN RAISE EXCEPTION 'OW_ASSERT:reconsent_erased_%',mode; END IF;
  END LOOP;
  RAISE NOTICE 'OW_PASS:new_document_reconsent_unknown_and_historical';
END $baseline$;
ROLLBACK;
