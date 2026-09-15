BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_relation text;
  v_function constant text := 'public.complete_mobile_onboarding_atomic(uuid,jsonb)';
  v_definition text;
BEGIN
  FOREACH v_relation IN ARRAY ARRAY[
    'public.onboarding_legal_documents',
    'public.onboarding_legal_requirement_sets',
    'public.user_onboarding_legal_actions'
  ]
  LOOP
    IF to_regclass(v_relation) IS NULL THEN
      RAISE EXCEPTION 'missing onboarding relation %', v_relation;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_class relation
      WHERE relation.oid = to_regclass(v_relation)
        AND relation.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'onboarding relation % is missing RLS', v_relation;
    END IF;

    IF has_table_privilege('anon', v_relation, 'SELECT,INSERT,UPDATE,DELETE')
      OR has_table_privilege('authenticated', v_relation, 'SELECT,INSERT,UPDATE,DELETE') THEN
      RAISE EXCEPTION 'client role can access onboarding relation % directly', v_relation;
    END IF;
  END LOOP;

  IF to_regprocedure(v_function) IS NULL THEN
    RAISE EXCEPTION 'missing onboarding completion function %', v_function;
  END IF;

  SELECT pg_get_functiondef(to_regprocedure(v_function)) INTO v_definition;
  IF v_definition NOT ILIKE '%SECURITY DEFINER%'
    OR v_definition NOT ILIKE '%SET search_path TO%pg_catalog%public%private%extensions%pg_temp%'
    OR v_definition NOT ILIKE '%assert_trusted_backend%' THEN
    RAISE EXCEPTION 'onboarding completion function is not hardened';
  END IF;

  IF has_function_privilege('anon', v_function, 'EXECUTE')
    OR has_function_privilege('authenticated', v_function, 'EXECUTE')
    OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
    RAISE EXCEPTION 'onboarding completion function grants are not service-only';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_profiles'
      AND column_name = 'onboarding_completed_at'
      AND is_nullable = 'YES'
  ) THEN
    RAISE EXCEPTION 'server completion timestamp column is missing';
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_user_id constant uuid := '00000000-0000-4000-8000-000000000951';
  v_other_user_id constant uuid := '00000000-0000-4000-8000-000000000952';
  v_legacy_user_id constant uuid := '00000000-0000-4000-8000-000000000953';
  v_terms_id uuid;
  v_privacy_id uuid;
  v_terms_hash text := encode(extensions.digest('Synthetic terms for tests only', 'sha256'), 'hex');
  v_privacy_hash text := repeat('b', 64);
  v_valid_submission jsonb;
  v_result jsonb;
  v_replay jsonb;
  v_before_name text;
  v_initial_completion timestamptz;
  v_reconsent_submission jsonb;
  v_revised_terms_hash text := encode(extensions.digest('Synthetic revised terms for tests only', 'sha256'), 'hex');
BEGIN
  INSERT INTO public.users (id, wpp, email, name, locale, timezone, country, country_confirmed, status)
  VALUES
    (v_user_id, NULL, 'onboarding-a@example.invalid', 'Before A', 'pt-BR', 'America/Sao_Paulo', 'BR', false, 'active'),
    (v_other_user_id, NULL, 'onboarding-b@example.invalid', 'Before B', 'pt-BR', 'America/Sao_Paulo', 'BR', false, 'active'),
    (v_legacy_user_id, NULL, 'onboarding-legacy@example.invalid', 'Legacy Complete', 'pt-BR', 'America/Sao_Paulo', 'BR', true, 'active');

  INSERT INTO public.user_profiles (user_id) VALUES (v_user_id), (v_other_user_id);
  INSERT INTO public.user_profiles (user_id, onboarding_completed, onboarding_step)
  VALUES (v_legacy_user_id, true, 6);

  INSERT INTO public.onboarding_legal_requirement_sets (
    version,
    locale,
    document_keys,
    effective_at,
    publication_status,
    published_at
  ) VALUES (
    '2026-09-15.1',
    'pt-BR',
    ARRAY['terms_of_service', 'privacy_policy'],
    clock_timestamp() - interval '1 day',
    'published',
    clock_timestamp() - interval '1 day'
  );

  INSERT INTO public.onboarding_legal_documents (
    document_key,
    version,
    locale,
    body,
    content_hash,
    purpose,
    action_type,
    required,
    effective_at,
    publication_status,
    published_at
  ) VALUES (
    'terms_of_service',
    '2026-09-01.1',
    'pt-BR',
    'Synthetic obsolete terms for tests only',
    encode(extensions.digest('Synthetic obsolete terms for tests only', 'sha256'), 'hex'),
    'synthetic_terms_test',
    'acceptance',
    true,
    clock_timestamp() - interval '2 days',
    'published',
    clock_timestamp() - interval '2 days'
  );

  INSERT INTO public.onboarding_legal_documents (
    document_key,
    version,
    locale,
    body,
    content_hash,
    purpose,
    action_type,
    required,
    effective_at,
    publication_status,
    published_at
  ) VALUES (
    'terms_of_service',
    '2026-09-15.1',
    'pt-BR',
    'Synthetic terms for tests only',
    v_terms_hash,
    'synthetic_terms_test',
    'acceptance',
    true,
    clock_timestamp() - interval '1 day',
    'published',
    clock_timestamp() - interval '1 day'
  ) RETURNING id INTO v_terms_id;

  INSERT INTO public.onboarding_legal_documents (
    document_key,
    version,
    locale,
    content_url,
    content_hash,
    purpose,
    action_type,
    required,
    effective_at,
    publication_status,
    published_at
  ) VALUES (
    'privacy_policy',
    '2026-09-15.1',
    'pt-BR',
    'https://legal.example.invalid/privacy/2026-09-15',
    v_privacy_hash,
    'synthetic_privacy_test',
    'acknowledgement',
    true,
    clock_timestamp() - interval '1 day',
    'published',
    clock_timestamp() - interval '1 day'
  ) RETURNING id INTO v_privacy_id;

  INSERT INTO public.onboarding_legal_documents (
    document_key,
    version,
    locale,
    body,
    content_hash,
    purpose,
    action_type,
    required,
    effective_at,
    publication_status,
    published_at
  ) VALUES (
    'future_specific_consent',
    '2026-10-01.1',
    'pt-BR',
    'Synthetic future consent for tests only',
    encode(extensions.digest('Synthetic future consent for tests only', 'sha256'), 'hex'),
    'synthetic_future_test',
    'consent',
    true,
    clock_timestamp() + interval '30 days',
    'published',
    clock_timestamp()
  );

  v_valid_submission := jsonb_build_object(
    'name', 'Completed A',
    'locale', 'pt-BR',
    'country', 'BR',
    'timezone', 'America/Sao_Paulo',
    'sex', 'feminino',
    'birth_date', '1990-06-15',
    'height_cm', 168,
    'weight_kg', 64,
    'body_fat_percent', 24,
    'objective', 'recomposicao',
    'activity_level', 'moderado',
    'training_frequency', 3,
    'water_intake', 'moderado',
    'hunger_level', 'moderada',
    'wake_time', '07:30',
    'bedtime', '23:00',
    'food_organization', 'sim',
    'persona', 'focus',
    'document_actions', jsonb_build_array(
      jsonb_build_object(
        'document_key', 'terms_of_service',
        'version', '2026-09-15.1',
        'locale', 'pt-BR',
        'content_hash', v_terms_hash,
        'action', 'acceptance'
      ),
      jsonb_build_object(
        'document_key', 'privacy_policy',
        'version', '2026-09-15.1',
        'locale', 'pt-BR',
        'content_hash', v_privacy_hash,
        'action', 'acknowledgement'
      )
    )
  );

  -- A historical flag without evidence does not fabricate history, but a new explicit
  -- submission may establish a new server timestamp and current legal actions.
  PERFORM public.complete_mobile_onboarding_atomic(v_legacy_user_id, v_valid_submission);
  IF (SELECT onboarding_completed_at FROM public.user_profiles WHERE user_id = v_legacy_user_id) IS NULL
    OR (
      SELECT count(*) FROM public.user_onboarding_legal_actions WHERE user_id = v_legacy_user_id
    ) <> 2 THEN
    RAISE EXCEPTION 'legacy user could not establish current explicit consent';
  END IF;

  -- A requirement manifest is authoritative: a partially published catalog is unavailable.
  BEGIN
    INSERT INTO public.onboarding_legal_requirement_sets (
      version,
      locale,
      document_keys,
      effective_at,
      publication_status,
      published_at
    ) VALUES (
      '2026-09-15.partial',
      'pt-BR',
      ARRAY['terms_of_service', 'privacy_policy', 'missing_required_document'],
      clock_timestamp(),
      'published',
      clock_timestamp()
    );
    PERFORM public.complete_mobile_onboarding_atomic(v_user_id, v_valid_submission);
    RAISE EXCEPTION 'partial legal catalog completed onboarding';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  -- A required action mismatch must roll the whole submission back.
  v_before_name := (SELECT name FROM public.users WHERE id = v_user_id);
  BEGIN
    PERFORM public.complete_mobile_onboarding_atomic(
      v_user_id,
      jsonb_set(v_valid_submission, '{document_actions,1,action}', '"consent"'::jsonb)
    );
    RAISE EXCEPTION 'wrong legal action completed onboarding';
  EXCEPTION
    WHEN check_violation OR invalid_parameter_value THEN NULL;
  END;

  IF (SELECT name FROM public.users WHERE id = v_user_id) IS DISTINCT FROM v_before_name
    OR (SELECT onboarding_completed FROM public.user_profiles WHERE user_id = v_user_id)
    OR EXISTS (
      SELECT 1 FROM public.user_onboarding_legal_actions WHERE user_id = v_user_id
    )
    OR EXISTS (
      SELECT 1 FROM public.user_coach_preferences WHERE user_id = v_user_id
    ) THEN
    RAISE EXCEPTION 'failed onboarding left partial state';
  END IF;

  -- A stale document identity must also fail closed.
  BEGIN
    PERFORM public.complete_mobile_onboarding_atomic(
      v_user_id,
      jsonb_set(v_valid_submission, '{document_actions,0,version}', '"2026-09-01.1"'::jsonb)
    );
    RAISE EXCEPTION 'stale legal version completed onboarding';
  EXCEPTION
    WHEN check_violation OR invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM public.complete_mobile_onboarding_atomic(
      v_user_id,
      jsonb_set(v_valid_submission, '{document_actions,0,content_hash}', to_jsonb(repeat('f', 64)))
    );
    RAISE EXCEPTION 'wrong legal hash completed onboarding';
  EXCEPTION
    WHEN check_violation OR invalid_parameter_value THEN NULL;
  END;

  -- Missing a currently required document must block completion.
  BEGIN
    PERFORM public.complete_mobile_onboarding_atomic(
      v_user_id,
      jsonb_set(
        v_valid_submission,
        '{document_actions}',
        jsonb_build_array(v_valid_submission #> '{document_actions,0}')
      )
    );
    RAISE EXCEPTION 'missing legal action completed onboarding';
  EXCEPTION
    WHEN check_violation OR invalid_parameter_value THEN NULL;
  END;

  -- Caller-owned fields and development identifiers are forbidden in depth.
  BEGIN
    PERFORM public.complete_mobile_onboarding_atomic(
      v_user_id,
      v_valid_submission || jsonb_build_object('onboarding_completed', true)
    );
    RAISE EXCEPTION 'caller-owned completion flag was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM public.complete_mobile_onboarding_atomic(
      v_user_id,
      jsonb_set(v_valid_submission, '{document_actions,0,document_key}', '"dev_terms_v1"'::jsonb)
    );
    RAISE EXCEPTION 'development legal identity was accepted';
  EXCEPTION
    WHEN check_violation OR invalid_parameter_value THEN NULL;
  END;

  v_result := public.complete_mobile_onboarding_atomic(v_user_id, v_valid_submission);
  v_replay := public.complete_mobile_onboarding_atomic(v_user_id, v_valid_submission);

  IF v_replay IS DISTINCT FROM v_result
    OR v_result ->> 'onboarding_completed' <> 'true'
    OR v_result ->> 'user_id' <> v_user_id::text
    OR v_result ->> 'persona' <> 'focus'
    OR v_result ->> 'objective' <> 'recomposicao'
    OR v_result ->> 'completed_at' IS NULL THEN
    RAISE EXCEPTION 'completion result or retry is not stable';
  END IF;

  BEGIN
    PERFORM public.complete_mobile_onboarding_atomic(
      v_user_id,
      jsonb_set(v_valid_submission, '{weight_kg}', '81'::jsonb)
    );
    RAISE EXCEPTION 'completed onboarding was rewritten by a different submission';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  IF (SELECT weight_kg FROM public.user_profiles WHERE user_id = v_user_id) <> 64 THEN
    RAISE EXCEPTION 'rejected post-completion rewrite changed profile state';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.users domain_user
    WHERE domain_user.id = v_user_id
      AND domain_user.name = 'Completed A'
      AND domain_user.locale = 'pt-BR'
      AND domain_user.timezone = 'America/Sao_Paulo'
      AND domain_user.country = 'BR'
      AND domain_user.country_confirmed
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.user_profiles profile
    WHERE profile.user_id = v_user_id
      AND profile.onboarding_completed
      AND profile.onboarding_completed_at IS NOT NULL
      AND profile.current_protocol = 'recomposicao'
      AND profile.deficit_level = 500
      AND profile.onboarding_step = 6
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.user_coach_preferences preference
    WHERE preference.user_id = v_user_id
      AND preference.personality_code = 'focus'
  ) THEN
    RAISE EXCEPTION 'successful onboarding did not persist official state';
  END IF;

  IF (
    SELECT count(*)
    FROM public.user_onboarding_legal_actions action
    WHERE action.user_id = v_user_id
  ) <> 2 OR EXISTS (
    SELECT 1
    FROM public.user_onboarding_legal_actions action
    WHERE action.user_id = v_user_id
      AND action.acted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'legal actions were duplicated or lack server time';
  END IF;

  -- A newly effective required version forces explicit reconsent without rewriting
  -- the original completion timestamp or duplicating prior immutable actions.
  SELECT onboarding_completed_at INTO v_initial_completion
  FROM public.user_profiles WHERE user_id = v_user_id;

  INSERT INTO public.onboarding_legal_documents (
    document_key,
    version,
    locale,
    body,
    content_hash,
    purpose,
    action_type,
    required,
    effective_at,
    publication_status,
    published_at
  ) VALUES (
    'terms_of_service',
    '2026-09-15.2',
    'pt-BR',
    'Synthetic revised terms for tests only',
    v_revised_terms_hash,
    'synthetic_terms_test',
    'acceptance',
    true,
    clock_timestamp(),
    'published',
    clock_timestamp()
  );

  INSERT INTO public.onboarding_legal_requirement_sets (
    version,
    locale,
    document_keys,
    effective_at,
    publication_status,
    published_at
  ) VALUES (
    '2026-09-15.2',
    'pt-BR',
    ARRAY['terms_of_service', 'privacy_policy'],
    clock_timestamp(),
    'published',
    clock_timestamp()
  );

  v_reconsent_submission := jsonb_set(
    jsonb_set(v_valid_submission, '{document_actions,0,version}', '"2026-09-15.2"'::jsonb),
    '{document_actions,0,content_hash}',
    to_jsonb(v_revised_terms_hash)
  );
  v_result := public.complete_mobile_onboarding_atomic(v_user_id, v_reconsent_submission);

  IF (v_result ->> 'completed_at')::timestamptz IS DISTINCT FROM v_initial_completion
    OR jsonb_array_length(v_result -> 'document_actions') <> 2
    OR NOT EXISTS (
      SELECT 1
      FROM public.user_onboarding_legal_actions action
      WHERE action.user_id = v_user_id
        AND action.document_key = 'terms_of_service'
        AND action.version = '2026-09-15.2'
    )
    OR (
      SELECT count(*) FROM public.user_onboarding_legal_actions WHERE user_id = v_user_id
    ) <> 3 THEN
    RAISE EXCEPTION 'new required version was not reconsented atomically';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.user_onboarding_legal_actions action
    WHERE action.user_id = v_other_user_id
  ) OR (SELECT name FROM public.users WHERE id = v_other_user_id) <> 'Before B'
    OR (SELECT onboarding_completed FROM public.user_profiles WHERE user_id = v_other_user_id) THEN
    RAISE EXCEPTION 'onboarding A mutated user B';
  END IF;

  BEGIN
    UPDATE public.onboarding_legal_documents
    SET body = 'Mutated copy'
    WHERE id = v_terms_id;
    RAISE EXCEPTION 'published onboarding document was mutable';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.onboarding_legal_requirement_sets
    SET version = 'mutated'
    WHERE locale = 'pt-BR';
    RAISE EXCEPTION 'published onboarding requirement set was mutable';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.user_onboarding_legal_actions
    SET action_type = 'consent'
    WHERE user_id = v_user_id
      AND legal_document_id = v_privacy_id;
    RAISE EXCEPTION 'onboarding legal history was mutable';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
END;
$test$;

RESET ROLE;
ROLLBACK;
