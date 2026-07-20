BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_table text;
  v_function text;
  v_user_id uuid := '00000000-0000-0000-0000-000000000801';
  v_actor_id uuid := '00000000-0000-0000-0000-000000000802';
  v_pack_id uuid := '00000000-0000-0000-0000-000000000803';
  v_other_pack_id uuid := '00000000-0000-0000-0000-000000000804';
  v_first jsonb;
  v_retry jsonb;
  v_second jsonb;
  v_third jsonb;
  v_fourth jsonb;
  v_push_first jsonb;
  v_push_cooldown jsonb;
  v_daily_first jsonb;
  v_daily_limited jsonb;
  v_email_disabled jsonb;
  v_fallback jsonb;
  v_locale_isolated jsonb;
  v_mascot jsonb;
  v_version_id uuid;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'coach_personalities',
    'user_coach_preferences',
    'coach_message_context_policies',
    'coach_content_packs',
    'coach_message_templates',
    'coach_message_template_versions',
    'coach_content_pack_entries',
    'coach_message_usage',
    'user_mascot_state',
    'user_mascot_state_events'
  ]
  LOOP
    IF to_regclass(format('public.%I', v_table)) IS NULL THEN
      RAISE EXCEPTION 'missing relation public.%', v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_class relation
      JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
      WHERE namespace.nspname = 'public'
        AND relation.relname = v_table
        AND relation.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'RLS is not enabled on public.%', v_table;
    END IF;

    IF has_table_privilege('anon', format('public.%I', v_table), 'SELECT')
      OR has_table_privilege('authenticated', format('public.%I', v_table), 'INSERT')
      OR has_table_privilege('authenticated', format('public.%I', v_table), 'UPDATE')
      OR has_table_privilege('authenticated', format('public.%I', v_table), 'DELETE') THEN
      RAISE EXCEPTION 'client role has a forbidden privilege on public.%', v_table;
    END IF;
  END LOOP;

  FOREACH v_function IN ARRAY ARRAY[
    'public.set_user_coach_personality(uuid,text)',
    'public.claim_coach_message(uuid,text,text,text,text,text[],timestamp with time zone)',
    'public.activate_coach_content_pack(uuid,uuid,timestamp with time zone)',
    'public.activate_due_coach_content_pack(timestamp with time zone)',
    'public.transition_user_mascot_state(uuid,text,text,text)'
  ]
  LOOP
    IF to_regprocedure(v_function) IS NULL THEN
      RAISE EXCEPTION 'missing function %', v_function;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      CROSS JOIN LATERAL aclexplode(
        COALESCE(
          function_definition.proacl,
          acldefault('f', function_definition.proowner)
        )
      ) privilege
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND privilege.grantee = 0
        AND privilege.privilege_type = 'EXECUTE'
    ) OR has_function_privilege('anon', v_function, 'EXECUTE')
      OR has_function_privilege('authenticated', v_function, 'EXECUTE')
      OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'function privileges are not service-only for %', v_function;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc function_definition
      WHERE function_definition.oid = to_regprocedure(v_function)
        AND function_definition.prosecdef
    ) THEN
      RAISE EXCEPTION 'function must remain SECURITY INVOKER: %', v_function;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'coach_message_usage'
      AND column_name IN ('title', 'subject', 'body', 'rendered_body', 'event_key')
  ) THEN
    RAISE EXCEPTION 'coach_message_usage stores rendered copy or a raw event key';
  END IF;

  IF (SELECT count(*) FROM public.coach_personalities) <> 4
    OR NOT EXISTS (
      SELECT 1
      FROM public.coach_personalities
      WHERE code = 'balanced'
        AND NOT selectable
        AND active
    )
    OR (SELECT count(*) FROM public.coach_personalities WHERE selectable) <> 3 THEN
    RAISE EXCEPTION 'coach personality definitions are incomplete';
  END IF;

  IF (SELECT count(*) FROM public.coach_message_context_policies) <> 45
    OR EXISTS (
      SELECT 1
      FROM public.coach_message_context_policies
      WHERE channel = 'email'
        AND delivery_enabled
    ) THEN
    RAISE EXCEPTION 'context policy matrix is incomplete or email is enabled';
  END IF;

  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_sso_user, is_anonymous
  ) VALUES (
    v_actor_id,
    'authenticated',
    'authenticated',
    'bodyflow-coach-actor@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    false,
    false
  );

  INSERT INTO public.users (id, name, timezone, locale)
  VALUES (v_user_id, 'Synthetic Coach Test', 'America/New_York', 'pt-BR');

  IF public.set_user_coach_personality(v_user_id, 'focus')->>'effective_personality' <> 'focus' THEN
    RAISE EXCEPTION 'selectable coach personality was not persisted';
  END IF;

  BEGIN
    PERFORM public.set_user_coach_personality(v_user_id, 'balanced');
    RAISE EXCEPTION 'balanced was accepted as a patient-selectable personality';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_mascot := public.transition_user_mascot_state(
    v_user_id,
    'reactivating',
    'explicit_test_event',
    'mascot-event-1'
  );

  IF v_mascot->>'state' <> 'reactivating' THEN
    RAISE EXCEPTION 'valid mascot transition was not persisted';
  END IF;

  IF public.transition_user_mascot_state(
    v_user_id,
    'reactivating',
    'retry',
    'mascot-event-1'
  )->>'event_id' <> v_mascot->>'event_id' THEN
    RAISE EXCEPTION 'mascot transition retry was not idempotent';
  END IF;

  BEGIN
    PERFORM public.transition_user_mascot_state(
      v_user_id,
      'unknown_state',
      'invalid_test_event',
      'mascot-event-invalid'
    );
    RAISE EXCEPTION 'invalid mascot state was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  INSERT INTO public.coach_content_packs (
    id,
    slug,
    label,
    status,
    created_by,
    approved_by,
    approved_at
  ) VALUES (
    v_pack_id,
    'bodyflow-coach-sql-test',
    'BodyFlow coach SQL test',
    'draft',
    v_actor_id,
    v_actor_id,
    timestamptz '2026-07-20 12:00:00+00'
  );

  INSERT INTO public.coach_message_templates (
    template_key,
    personality_code,
    context,
    channel,
    locale,
    variant,
    allowed_variables,
    required_variables
  )
  SELECT
    format(
      'test.%s.%s.%s.%s.v%s',
      personality.code,
      context.code,
      channel.code,
      replace(lower(locale.code), '-', '_'),
      variant.value
    ),
    personality.code,
    context.code,
    channel.code,
    locale.code,
    variant.value,
    ARRAY[]::text[],
    ARRAY[]::text[]
  FROM unnest(ARRAY['balanced', 'focus', 'impulse', 'zen']) AS personality(code)
  CROSS JOIN unnest(ARRAY[
    'onboarding',
    'meal_pending',
    'registration_confirmed',
    'error_corrected',
    'hydration',
    'supplement',
    'medication',
    'workout',
    'progress',
    'day_incomplete',
    'reevaluation',
    'reengagement',
    'trial',
    'paywall',
    'return_after_abandonment'
  ]) AS context(code)
  CROSS JOIN unnest(ARRAY['in_app', 'push', 'email']) AS channel(code)
  CROSS JOIN unnest(ARRAY['pt-BR', 'en-US']) AS locale(code)
  CROSS JOIN generate_series(1, 3) AS variant(value);

  INSERT INTO public.coach_message_template_versions (
    template_id,
    version,
    title,
    subject,
    body,
    status,
    provenance,
    authored_by,
    approved_by,
    approved_at,
    content_hash
  )
  SELECT
    template.id,
    1,
    CASE WHEN template.channel = 'push' THEN 'BodyFlow' ELSE NULL END,
    CASE WHEN template.channel = 'email' THEN 'BodyFlow' ELSE NULL END,
    format('Safe synthetic copy for %s.', template.template_key),
    'draft',
    'human',
    v_actor_id,
    CASE
      WHEN template.template_key = 'test.focus.hydration.in_app.pt_br.v1' THEN NULL
      ELSE v_actor_id
    END,
    CASE
      WHEN template.template_key = 'test.focus.hydration.in_app.pt_br.v1' THEN NULL
      ELSE timestamptz '2026-07-20 12:00:00+00'
    END,
    encode(
      extensions.digest(
        format(
          '%s|%s|%s|%s',
          COALESCE(CASE WHEN template.channel = 'push' THEN 'BodyFlow' END, ''),
          COALESCE(CASE WHEN template.channel = 'email' THEN 'BodyFlow' END, ''),
          format('Safe synthetic copy for %s.', template.template_key),
          template.template_key
        ),
        'sha256'
      ),
      'hex'
    )
  FROM public.coach_message_templates template;

  INSERT INTO public.coach_content_pack_entries (pack_id, template_id, template_version_id)
  SELECT v_pack_id, version.template_id, version.id
  FROM public.coach_message_template_versions version;

  IF (SELECT count(*) FROM public.coach_content_pack_entries WHERE pack_id = v_pack_id) <> 1080 THEN
    RAISE EXCEPTION 'synthetic complete pack does not contain 1,080 entries';
  END IF;

  PERFORM public.activate_coach_content_pack(
    v_pack_id,
    v_actor_id,
    timestamptz '2026-07-20 12:05:00+00'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.coach_content_packs
    WHERE id = v_pack_id
      AND status = 'active'
      AND activated_at = timestamptz '2026-07-20 12:05:00+00'
  )
    OR (SELECT count(*) FROM public.coach_message_template_versions WHERE status = 'active') <> 1080
    OR (
      SELECT count(*)
      FROM public.coach_message_template_versions
      WHERE approved_by IS NOT NULL
        AND approved_at IS NOT NULL
    ) <> 1080 THEN
    RAISE EXCEPTION 'complete coach pack did not activate atomically';
  END IF;

  BEGIN
    INSERT INTO public.coach_content_packs (id, slug, label, status)
    VALUES (v_other_pack_id, 'bodyflow-second-active-test', 'Second active', 'active');
    RAISE EXCEPTION 'more than one active content pack was accepted';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  SELECT id
  INTO v_version_id
  FROM public.coach_message_template_versions
  ORDER BY id
  LIMIT 1;

  BEGIN
    UPDATE public.coach_message_template_versions
    SET body = body || ' mutated'
    WHERE id = v_version_id;
    RAISE EXCEPTION 'immutable coach copy was updated in place';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_first := public.claim_coach_message(
    v_user_id, 'hydration', 'in_app', 'pt-BR', 'claim-event-1', ARRAY[]::text[],
    timestamptz '2026-07-20 13:00:00+00'
  );
  v_retry := public.claim_coach_message(
    v_user_id, 'hydration', 'in_app', 'pt-BR', 'claim-event-1', ARRAY[]::text[],
    timestamptz '2026-07-20 13:01:00+00'
  );

  BEGIN
    PERFORM public.claim_coach_message(
      v_user_id, 'hydration', 'in_app', 'en-US', 'claim-event-1', ARRAY[]::text[],
      timestamptz '2026-07-20 13:01:30+00'
    );
    RAISE EXCEPTION 'one event key was accepted with two locales';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  v_second := public.claim_coach_message(
    v_user_id, 'hydration', 'in_app', 'pt-BR', 'claim-event-2', ARRAY[]::text[],
    timestamptz '2026-07-20 13:02:00+00'
  );
  v_third := public.claim_coach_message(
    v_user_id, 'hydration', 'in_app', 'pt-BR', 'claim-event-3', ARRAY[]::text[],
    timestamptz '2026-07-20 13:03:00+00'
  );
  v_fourth := public.claim_coach_message(
    v_user_id, 'hydration', 'in_app', 'pt-BR', 'claim-event-4', ARRAY[]::text[],
    timestamptz '2026-07-20 13:04:00+00'
  );

  IF v_first->>'outcome' <> 'selected'
    OR v_first->>'effective_personality' <> 'focus'
    OR v_first->>'reason' <> 'exact'
    OR v_retry->>'usage_id' <> v_first->>'usage_id'
    OR v_second->>'template_version_id' = v_first->>'template_version_id'
    OR v_third->>'template_version_id' IN (
      v_first->>'template_version_id',
      v_second->>'template_version_id'
    )
    OR v_fourth->>'template_version_id' = v_third->>'template_version_id' THEN
    RAISE EXCEPTION 'claim idempotency or three-variant LRU selection failed';
  END IF;

  UPDATE public.coach_message_template_versions version
  SET status = 'archived',
      archived_at = timestamptz '2026-07-20 13:05:00+00'
  FROM public.coach_message_templates template
  WHERE template.id = version.template_id
    AND template.personality_code = 'focus'
    AND template.context = 'onboarding'
    AND template.channel = 'in_app'
    AND template.locale = 'pt-BR';

  v_fallback := public.claim_coach_message(
    v_user_id, 'onboarding', 'in_app', 'pt-BR', 'fallback-event-1', ARRAY[]::text[],
    timestamptz '2026-07-20 13:06:00+00'
  );

  IF v_fallback->>'outcome' <> 'selected'
    OR v_fallback->>'reason' <> 'balanced_fallback'
    OR v_fallback->>'effective_personality' <> 'balanced'
    OR v_fallback->>'locale' <> 'pt-BR' THEN
    RAISE EXCEPTION 'same-locale balanced fallback failed';
  END IF;

  UPDATE public.coach_message_template_versions version
  SET status = 'archived',
      archived_at = timestamptz '2026-07-20 13:07:00+00'
  FROM public.coach_message_templates template
  WHERE template.id = version.template_id
    AND template.personality_code IN ('focus', 'balanced')
    AND template.context = 'supplement'
    AND template.channel = 'in_app'
    AND template.locale = 'pt-BR';

  v_locale_isolated := public.claim_coach_message(
    v_user_id, 'supplement', 'in_app', 'pt-BR', 'locale-event-1', ARRAY[]::text[],
    timestamptz '2026-07-20 13:08:00+00'
  );

  IF v_locale_isolated->>'outcome' <> 'failed'
    OR v_locale_isolated->>'reason' <> 'catalog_incomplete'
    OR NOT EXISTS (
      SELECT 1
      FROM public.coach_message_template_versions version
      JOIN public.coach_message_templates template ON template.id = version.template_id
      WHERE template.personality_code IN ('focus', 'balanced')
        AND template.context = 'supplement'
        AND template.channel = 'in_app'
        AND template.locale = 'en-US'
        AND version.status = 'active'
    ) THEN
    RAISE EXCEPTION 'claim crossed locales instead of failing closed';
  END IF;

  v_push_first := public.claim_coach_message(
    v_user_id, 'hydration', 'push', 'pt-BR', 'push-event-1', ARRAY[]::text[],
    timestamptz '2026-07-20 14:00:00+00'
  );
  v_push_cooldown := public.claim_coach_message(
    v_user_id, 'hydration', 'push', 'pt-BR', 'push-event-2', ARRAY[]::text[],
    timestamptz '2026-07-20 15:00:00+00'
  );

  IF v_push_first->>'outcome' <> 'selected'
    OR v_push_cooldown->>'outcome' <> 'suppressed'
    OR v_push_cooldown->>'reason' <> 'cooldown' THEN
    RAISE EXCEPTION 'push cooldown was not enforced';
  END IF;

  v_daily_first := public.claim_coach_message(
    v_user_id, 'progress', 'in_app', 'pt-BR', 'daily-event-1', ARRAY[]::text[],
    timestamptz '2026-07-20 16:00:00+00'
  );
  v_daily_limited := public.claim_coach_message(
    v_user_id, 'progress', 'in_app', 'pt-BR', 'daily-event-2', ARRAY[]::text[],
    timestamptz '2026-07-20 17:00:00+00'
  );

  IF v_daily_first->>'outcome' <> 'selected'
    OR v_daily_limited->>'outcome' <> 'suppressed'
    OR v_daily_limited->>'reason' <> 'daily_limit' THEN
    RAISE EXCEPTION 'local-day limit was not enforced';
  END IF;

  v_email_disabled := public.claim_coach_message(
    v_user_id, 'hydration', 'email', 'pt-BR', 'email-event-1', ARRAY[]::text[],
    timestamptz '2026-07-20 18:00:00+00'
  );

  IF v_email_disabled->>'outcome' <> 'suppressed'
    OR v_email_disabled->>'reason' <> 'delivery_disabled' THEN
    RAISE EXCEPTION 'disabled email delivery was not suppressed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.coach_message_usage
    WHERE event_key_hash IS NULL
      OR length(event_key_hash) <> 64
      OR event_key_hash IN ('claim-event-1', 'push-event-1', 'daily-event-1')
  ) THEN
    RAISE EXCEPTION 'event telemetry did not persist only a one-way key hash';
  END IF;

  BEGIN
    UPDATE public.coach_message_usage
    SET reason = 'mutated'
    WHERE id = (v_first->>'usage_id')::uuid;
    RAISE EXCEPTION 'append-only coach usage was updated';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
END;
$test$;

ROLLBACK;
