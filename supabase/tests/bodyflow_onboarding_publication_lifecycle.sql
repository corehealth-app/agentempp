BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_function text;
  v_definition text;
BEGIN
  FOREACH v_function IN ARRAY ARRAY[
    'public.publish_onboarding_legal_document(uuid)',
    'public.archive_onboarding_legal_document(uuid)',
    'public.publish_onboarding_legal_requirement_set(uuid)',
    'public.archive_onboarding_legal_requirement_set(uuid)'
  ]
  LOOP
    IF to_regprocedure(v_function) IS NULL THEN
      RAISE EXCEPTION 'missing onboarding lifecycle function %', v_function;
    END IF;

    SELECT pg_get_functiondef(to_regprocedure(v_function)) INTO v_definition;
    IF v_definition NOT ILIKE '%SECURITY DEFINER%'
      OR v_definition NOT ILIKE '%SET search_path TO%pg_catalog%public%private%extensions%pg_temp%'
      OR v_definition NOT ILIKE '%assert_trusted_backend%' THEN
      RAISE EXCEPTION 'onboarding lifecycle function % is not hardened', v_function;
    END IF;

    IF has_function_privilege('anon', v_function, 'EXECUTE')
      OR has_function_privilege('authenticated', v_function, 'EXECUTE')
      OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'onboarding lifecycle function % has invalid grants', v_function;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'onboarding_legal_documents'
      AND column_name = 'archived_at'
      AND is_nullable = 'YES'
  ) OR NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'onboarding_legal_requirement_sets'
      AND column_name = 'archived_at'
      AND is_nullable = 'YES'
  ) THEN
    RAISE EXCEPTION 'onboarding lifecycle timestamps are missing';
  END IF;

  IF has_table_privilege('service_role', 'public.onboarding_legal_documents', 'INSERT,UPDATE,DELETE')
    OR has_table_privilege('service_role', 'public.onboarding_legal_requirement_sets', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'service role can bypass onboarding lifecycle RPCs';
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_terms_v1_id uuid;
  v_terms_v2_id uuid;
  v_privacy_id uuid;
  v_set_v1_id uuid;
  v_set_v2_id uuid;
  v_unpublishable_set_id uuid;
  v_archived_document_set_id uuid;
  v_user_id constant uuid := '00000000-0000-4000-8000-000000000971';
  v_terms_v1_hash text := encode(extensions.digest('Synthetic lifecycle terms v1', 'sha256'), 'hex');
  v_terms_v2_hash text := encode(extensions.digest('Synthetic lifecycle terms v2', 'sha256'), 'hex');
  v_privacy_hash text := encode(extensions.digest('Synthetic lifecycle privacy', 'sha256'), 'hex');
  v_published_at timestamptz;
  v_result jsonb;
  v_submission jsonb;
BEGIN
  INSERT INTO public.users (id, wpp, email, name, locale, timezone, country, country_confirmed, status)
  VALUES (
    v_user_id, NULL, 'onboarding-lifecycle@example.invalid', 'Lifecycle Before',
    'pt-BR', 'America/Sao_Paulo', 'BR', false, 'active'
  );
  INSERT INTO public.user_profiles (user_id) VALUES (v_user_id);

  INSERT INTO public.onboarding_legal_documents (
    document_key, version, locale, body, content_hash, purpose,
    action_type, required, effective_at
  ) VALUES (
    'terms_of_service', 'lifecycle-v1', 'pt-BR',
    'Synthetic lifecycle terms v1', v_terms_v1_hash,
    'synthetic_lifecycle_terms', 'acceptance', true,
    clock_timestamp() - interval '2 days'
  ) RETURNING id INTO v_terms_v1_id;

  IF (SELECT publication_status FROM public.onboarding_legal_documents WHERE id = v_terms_v1_id) <> 'inactive'
    OR (SELECT published_at FROM public.onboarding_legal_documents WHERE id = v_terms_v1_id) IS NOT NULL THEN
    RAISE EXCEPTION 'new onboarding document did not start inactive';
  END IF;

  BEGIN
    INSERT INTO public.onboarding_legal_documents (
      document_key, version, locale, body, content_hash, purpose,
      action_type, required, effective_at, publication_status, published_at
    ) VALUES (
      'direct_publish_forbidden', 'lifecycle-v1', 'pt-BR',
      'Synthetic direct publish attempt',
      encode(extensions.digest('Synthetic direct publish attempt', 'sha256'), 'hex'),
      'synthetic_direct_publish', 'acceptance', true,
      clock_timestamp(), 'published', clock_timestamp()
    );
    RAISE EXCEPTION 'direct document publication was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.onboarding_legal_documents (
      document_key, version, locale, body, content_hash, purpose,
      action_type, required, effective_at, publication_status, published_at, archived_at
    ) VALUES (
      'direct_archive_forbidden', 'lifecycle-v1', 'pt-BR',
      'Synthetic direct archive attempt',
      encode(extensions.digest('Synthetic direct archive attempt', 'sha256'), 'hex'),
      'synthetic_direct_archive', 'acceptance', true,
      clock_timestamp(), 'archived', clock_timestamp(), clock_timestamp()
    );
    RAISE EXCEPTION 'direct document archive insert was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  v_result := public.publish_onboarding_legal_document(v_terms_v1_id);
  v_published_at := (SELECT published_at FROM public.onboarding_legal_documents WHERE id = v_terms_v1_id);
  IF v_result ->> 'outcome' <> 'published'
    OR (SELECT publication_status FROM public.onboarding_legal_documents WHERE id = v_terms_v1_id) <> 'published'
    OR v_published_at IS NULL THEN
    RAISE EXCEPTION 'inactive document was not published';
  END IF;

  v_result := public.publish_onboarding_legal_document(v_terms_v1_id);
  IF v_result ->> 'outcome' <> 'already_published'
    OR (SELECT published_at FROM public.onboarding_legal_documents WHERE id = v_terms_v1_id) IS DISTINCT FROM v_published_at THEN
    RAISE EXCEPTION 'document publish is not idempotent';
  END IF;

  BEGIN
    UPDATE public.onboarding_legal_documents
    SET body = 'Mutated body'
    WHERE id = v_terms_v1_id;
    RAISE EXCEPTION 'published document content was mutable';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.onboarding_legal_documents
    SET publication_status = 'inactive', published_at = NULL
    WHERE id = v_terms_v1_id;
    RAISE EXCEPTION 'published document returned to inactive';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.onboarding_legal_documents (
    document_key, version, locale, body, content_hash, purpose,
    action_type, required, effective_at
  ) VALUES (
    'privacy_policy', 'lifecycle-v1', 'pt-BR',
    'Synthetic lifecycle privacy', v_privacy_hash,
    'synthetic_lifecycle_privacy', 'acknowledgement', true,
    clock_timestamp() - interval '2 days'
  ) RETURNING id INTO v_privacy_id;

  BEGIN
    PERFORM public.archive_onboarding_legal_document(v_privacy_id);
    RAISE EXCEPTION 'inactive document was archived';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.onboarding_legal_requirement_sets (
    version, locale, document_keys, effective_at
  ) VALUES (
    'lifecycle-unpublishable', 'en-US', ARRAY['privacy_policy'],
    clock_timestamp() - interval '1 day'
  ) RETURNING id INTO v_unpublishable_set_id;

  BEGIN
    PERFORM public.publish_onboarding_legal_requirement_set(v_unpublishable_set_id);
    RAISE EXCEPTION 'requirement set with unavailable document was published';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT publication_status FROM public.onboarding_legal_requirement_sets WHERE id = v_unpublishable_set_id) <> 'inactive' THEN
    RAISE EXCEPTION 'failed requirement set publication did not roll back';
  END IF;

  PERFORM public.publish_onboarding_legal_document(v_privacy_id);

  INSERT INTO public.onboarding_legal_requirement_sets (
    version, locale, document_keys, effective_at
  ) VALUES (
    'lifecycle-v1', 'pt-BR', ARRAY['terms_of_service', 'privacy_policy'],
    clock_timestamp() - interval '1 day'
  ) RETURNING id INTO v_set_v1_id;

  IF (SELECT publication_status FROM public.onboarding_legal_requirement_sets WHERE id = v_set_v1_id) <> 'inactive' THEN
    RAISE EXCEPTION 'new onboarding requirement set did not start inactive';
  END IF;

  BEGIN
    INSERT INTO public.onboarding_legal_requirement_sets (
      version, locale, document_keys, effective_at, publication_status, published_at
    ) VALUES (
      'lifecycle-direct-publish', 'en-US', ARRAY['privacy_policy'],
      clock_timestamp(), 'published', clock_timestamp()
    );
    RAISE EXCEPTION 'direct requirement set publication was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.archive_onboarding_legal_requirement_set(v_unpublishable_set_id);
    RAISE EXCEPTION 'inactive requirement set was archived';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  PERFORM public.publish_onboarding_legal_requirement_set(v_set_v1_id);
  IF (SELECT publication_status FROM public.onboarding_legal_requirement_sets WHERE id = v_set_v1_id) <> 'published' THEN
    RAISE EXCEPTION 'requirement set was not published';
  END IF;

  BEGIN
    PERFORM public.archive_onboarding_legal_document(v_terms_v1_id);
    RAISE EXCEPTION 'document used by a published requirement set was archived';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.onboarding_legal_documents (
    document_key, version, locale, body, content_hash, purpose,
    action_type, required, effective_at
  ) VALUES (
    'terms_of_service', 'lifecycle-v2', 'pt-BR',
    'Synthetic lifecycle terms v2', v_terms_v2_hash,
    'synthetic_lifecycle_terms', 'acceptance', true,
    clock_timestamp() - interval '1 hour'
  ) RETURNING id INTO v_terms_v2_id;
  PERFORM public.publish_onboarding_legal_document(v_terms_v2_id);

  INSERT INTO public.onboarding_legal_requirement_sets (
    version, locale, document_keys, effective_at
  ) VALUES (
    'lifecycle-v2', 'pt-BR', ARRAY['terms_of_service', 'privacy_policy'],
    clock_timestamp()
  ) RETURNING id INTO v_set_v2_id;
  PERFORM public.publish_onboarding_legal_requirement_set(v_set_v2_id);

  IF (SELECT publication_status FROM public.onboarding_legal_requirement_sets WHERE id = v_set_v1_id) <> 'archived'
    OR (SELECT publication_status FROM public.onboarding_legal_requirement_sets WHERE id = v_set_v2_id) <> 'published'
    OR (SELECT count(*) FROM public.onboarding_legal_requirement_sets WHERE locale = 'pt-BR' AND publication_status = 'published') <> 1 THEN
    RAISE EXCEPTION 'requirement set replacement was not atomic';
  END IF;

  BEGIN
    UPDATE public.onboarding_legal_requirement_sets
    SET publication_status = 'inactive', published_at = NULL
    WHERE id = v_set_v2_id;
    RAISE EXCEPTION 'published requirement set returned to inactive';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  v_submission := jsonb_build_object(
    'name', 'Lifecycle Complete',
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
        'version', 'lifecycle-v2',
        'locale', 'pt-BR',
        'content_hash', v_terms_v2_hash,
        'action', 'acceptance'
      ),
      jsonb_build_object(
        'document_key', 'privacy_policy',
        'version', 'lifecycle-v1',
        'locale', 'pt-BR',
        'content_hash', v_privacy_hash,
        'action', 'acknowledgement'
      )
    )
  );

  PERFORM public.complete_mobile_onboarding_atomic(v_user_id, v_submission);
  IF (SELECT count(*) FROM public.user_onboarding_legal_actions WHERE user_id = v_user_id) <> 2 THEN
    RAISE EXCEPTION 'published lifecycle catalog did not complete onboarding';
  END IF;

  PERFORM public.archive_onboarding_legal_requirement_set(v_set_v2_id);
  IF EXISTS (
    SELECT 1 FROM public.onboarding_legal_requirement_sets
    WHERE locale = 'pt-BR' AND publication_status = 'published'
  ) THEN
    RAISE EXCEPTION 'archived replacement fell back to an obsolete requirement set';
  END IF;

  BEGIN
    PERFORM public.complete_mobile_onboarding_atomic(v_user_id, v_submission);
    RAISE EXCEPTION 'archived requirement set remained eligible for completion';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  IF (SELECT count(*) FROM public.user_onboarding_legal_actions WHERE user_id = v_user_id) <> 2 THEN
    RAISE EXCEPTION 'requirement set archive rewrote historical legal actions';
  END IF;

  v_result := public.archive_onboarding_legal_requirement_set(v_set_v2_id);
  IF v_result ->> 'outcome' <> 'already_archived' THEN
    RAISE EXCEPTION 'requirement set archive is not idempotent';
  END IF;

  PERFORM public.archive_onboarding_legal_document(v_terms_v2_id);
  PERFORM public.archive_onboarding_legal_document(v_terms_v1_id);
  PERFORM public.archive_onboarding_legal_document(v_privacy_id);

  INSERT INTO public.onboarding_legal_requirement_sets (
    version, locale, document_keys, effective_at
  ) VALUES (
    'lifecycle-archived-documents', 'pt-BR', ARRAY['terms_of_service', 'privacy_policy'],
    clock_timestamp()
  ) RETURNING id INTO v_archived_document_set_id;
  BEGIN
    PERFORM public.publish_onboarding_legal_requirement_set(v_archived_document_set_id);
    RAISE EXCEPTION 'requirement set with archived documents was published';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  IF (SELECT count(*) FROM public.user_onboarding_legal_actions WHERE user_id = v_user_id) <> 2 THEN
    RAISE EXCEPTION 'document archive rewrote historical legal actions';
  END IF;

  v_result := public.archive_onboarding_legal_document(v_terms_v2_id);
  IF v_result ->> 'outcome' <> 'already_archived' THEN
    RAISE EXCEPTION 'document archive is not idempotent';
  END IF;

  BEGIN
    PERFORM public.publish_onboarding_legal_document(v_terms_v2_id);
    RAISE EXCEPTION 'archived document was republished';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.onboarding_legal_documents
    SET publication_status = 'inactive', published_at = NULL, archived_at = NULL
    WHERE id = v_terms_v2_id;
    RAISE EXCEPTION 'archived document returned to inactive';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.onboarding_legal_documents
    SET content_hash = repeat('f', 64)
    WHERE id = v_terms_v2_id;
    RAISE EXCEPTION 'archived document hash was mutable';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.onboarding_legal_documents
    SET version = 'lifecycle-mutated', locale = 'en-US', action_type = 'consent'
    WHERE id = v_terms_v2_id;
    RAISE EXCEPTION 'archived document identity or action was mutable';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.publish_onboarding_legal_requirement_set(v_set_v2_id);
    RAISE EXCEPTION 'archived requirement set was republished';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.onboarding_legal_requirement_sets
    SET document_keys = ARRAY['privacy_policy']
    WHERE id = v_set_v2_id;
    RAISE EXCEPTION 'archived requirement set composition was mutable';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.onboarding_legal_requirement_sets
    SET publication_status = 'inactive', published_at = NULL, archived_at = NULL
    WHERE id = v_set_v2_id;
    RAISE EXCEPTION 'archived requirement set returned to inactive';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    DELETE FROM public.onboarding_legal_documents WHERE id = v_terms_v2_id;
    RAISE EXCEPTION 'onboarding document was deleted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    DELETE FROM public.onboarding_legal_requirement_sets WHERE id = v_set_v2_id;
    RAISE EXCEPTION 'onboarding requirement set was deleted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END;
$test$;

ROLLBACK;
