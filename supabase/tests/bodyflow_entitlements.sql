BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_relation text;
  v_function regprocedure;
  v_definition text;
  v_forbidden_privilege text;
  v_relations constant text[] := ARRAY[
    'public.user_entitlements',
    'public.entitlement_events'
  ];
  v_functions constant text[] := ARRAY[
    'public.apply_entitlement_event(text,text,uuid,text,text,text,text,plan_enum,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone,boolean,text,uuid)',
    'public.sync_stripe_subscription_entitlement(uuid,text,timestamp with time zone,text)',
    'public.resolve_user_entitlement(uuid,text,timestamp with time zone)'
  ];
  v_forbidden_privileges constant text[] := ARRAY[
    'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
  ];
BEGIN
  FOREACH v_relation IN ARRAY v_relations
  LOOP
    IF to_regclass(v_relation) IS NULL THEN
      RAISE EXCEPTION 'missing entitlement relation %', v_relation;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_class relation
      WHERE relation.oid = to_regclass(v_relation)
        AND relation.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'entitlement relation % is missing RLS', v_relation;
    END IF;

    IF has_table_privilege('anon', v_relation, 'SELECT')
      OR has_table_privilege('authenticated', v_relation, 'SELECT') THEN
      RAISE EXCEPTION 'client role can read private entitlement relation %', v_relation;
    END IF;

    FOREACH v_forbidden_privilege IN ARRAY v_forbidden_privileges
    LOOP
      IF has_table_privilege('anon', v_relation, v_forbidden_privilege)
        OR has_table_privilege('authenticated', v_relation, v_forbidden_privilege)
        OR has_table_privilege('service_role', v_relation, v_forbidden_privilege) THEN
        RAISE EXCEPTION 'direct % remains on entitlement relation %',
          v_forbidden_privilege,
          v_relation;
      END IF;
    END LOOP;

    IF NOT has_table_privilege('service_role', v_relation, 'SELECT') THEN
      RAISE EXCEPTION 'service role cannot audit entitlement relation %', v_relation;
    END IF;
  END LOOP;

  FOREACH v_relation IN ARRAY ARRAY[
    'user_entitlements.user_id',
    'user_entitlements.entitlement_key',
    'user_entitlements.source',
    'user_entitlements.source_reference',
    'user_entitlements.status',
    'user_entitlements.environment',
    'user_entitlements.last_provider_event_id',
    'user_entitlements.last_provider_event_at',
    'entitlement_events.provider_event_id',
    'entitlement_events.processing_result'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = split_part(v_relation, '.', 1)
        AND column_name = split_part(v_relation, '.', 2)
        AND is_nullable = 'NO'
    ) THEN
      RAISE EXCEPTION 'missing required non-null entitlement column public.%', v_relation;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'user_entitlements'
      AND indexdef LIKE 'CREATE UNIQUE INDEX%source%source_reference%entitlement_key%'
  ) THEN
    RAISE EXCEPTION 'provider source reference is not unique';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'entitlement_events'
      AND indexdef LIKE 'CREATE UNIQUE INDEX%source%provider_event_id%'
  ) THEN
    RAISE EXCEPTION 'provider entitlement events are not idempotent';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'entitlement_events'
      AND indexdef LIKE '%(entitlement_id)%'
  ) THEN
    RAISE EXCEPTION 'entitlement event foreign key is not indexed';
  END IF;

  FOREACH v_relation IN ARRAY v_functions
  LOOP
    v_function := to_regprocedure(v_relation);
    IF v_function IS NULL THEN
      RAISE EXCEPTION 'missing entitlement function %', v_relation;
    END IF;

    SELECT pg_get_functiondef(v_function) INTO v_definition;
    IF v_definition NOT ILIKE '%SECURITY DEFINER%'
      OR v_definition NOT ILIKE '%SET search_path TO%pg_catalog%public%private%pg_temp%' THEN
      RAISE EXCEPTION 'entitlement function % is not hardened', v_relation;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_proc procedure
      CROSS JOIN LATERAL aclexplode(
        COALESCE(procedure.proacl, acldefault('f', procedure.proowner))
      ) privilege
      WHERE procedure.oid = v_function
        AND privilege.grantee = 0
        AND privilege.privilege_type = 'EXECUTE'
    )
      OR has_function_privilege('anon', v_function, 'EXECUTE')
      OR has_function_privilege('authenticated', v_function, 'EXECUTE')
      OR NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'invalid entitlement function grants for %', v_relation;
    END IF;
  END LOOP;
END;
$test$;

DO $test$
DECLARE
  v_user_id constant uuid := '00000000-0000-4000-8000-000000000801';
  v_other_user_id constant uuid := '00000000-0000-4000-8000-000000000802';
  v_decision jsonb;
  v_result jsonb;
  v_count integer;
BEGIN
  INSERT INTO public.users (id, wpp, email, name, locale, timezone, status, metadata)
  VALUES
    (v_user_id, NULL, NULL, 'Synthetic Entitlement A', 'pt-BR', 'America/Sao_Paulo', 'active', '{}'::jsonb),
    (v_other_user_id, NULL, NULL, 'Synthetic Entitlement B', 'pt-BR', 'America/Sao_Paulo', 'active', '{}'::jsonb);

  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-24T10:00:00Z'::timestamptz
  );
  IF v_decision <> jsonb_build_object(
    'entitlement', 'bodyflow_full',
    'has_active_access', false,
    'status', 'expired',
    'source', NULL,
    'plan', NULL,
    'access_expires_at', NULL,
    'grace_expires_at', NULL,
    'cancel_at_period_end', false,
    'reason', 'no_entitlement',
    'decision_at', '2026-07-24T10:00:00Z'::timestamptz
  ) THEN
    RAISE EXCEPTION 'new app user does not fail closed: %', v_decision;
  END IF;

  v_result := public.apply_entitlement_event(
    'rc-event-001',
    'INITIAL_PURCHASE',
    v_user_id,
    'bodyflow_full',
    'revenuecat',
    'rc-subscription-001',
    'active',
    'mensal',
    'sandbox',
    '2026-07-24T10:00:00Z',
    '2026-07-24T10:00:00Z',
    '2026-08-24T10:00:00Z',
    NULL,
    false,
    NULL,
    NULL
  );
  IF v_result->>'result' <> 'applied' THEN
    RAISE EXCEPTION 'first entitlement event was not applied: %', v_result;
  END IF;

  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-24T10:01:00Z'
  );
  IF v_decision->>'has_active_access' <> 'true'
    OR v_decision->>'status' <> 'active'
    OR v_decision->>'source' <> 'revenuecat'
    OR v_decision ? 'source_reference' THEN
    RAISE EXCEPTION 'active entitlement decision is unsafe or incorrect: %', v_decision;
  END IF;

  v_result := public.apply_entitlement_event(
    'rc-event-001',
    'INITIAL_PURCHASE',
    v_user_id,
    'bodyflow_full',
    'revenuecat',
    'rc-subscription-001',
    'active',
    'mensal',
    'sandbox',
    '2026-07-24T10:00:00Z',
    '2026-07-24T10:00:00Z',
    '2026-08-24T10:00:00Z',
    NULL,
    false,
    NULL,
    NULL
  );
  IF v_result->>'result' <> 'duplicate' THEN
    RAISE EXCEPTION 'duplicate entitlement event was not idempotent: %', v_result;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.entitlement_events
  WHERE source = 'revenuecat' AND provider_event_id = 'rc-event-001';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'duplicate provider event created % audit rows', v_count;
  END IF;

  v_result := public.apply_entitlement_event(
    'rc-event-000',
    'EXPIRATION',
    v_user_id,
    'bodyflow_full',
    'revenuecat',
    'rc-subscription-001',
    'expired',
    'mensal',
    'sandbox',
    '2026-07-24T09:59:00Z',
    '2026-07-01T10:00:00Z',
    '2026-07-24T09:59:00Z',
    NULL,
    false,
    NULL,
    NULL
  );
  IF v_result->>'result' <> 'stale' THEN
    RAISE EXCEPTION 'older provider event was not rejected as stale: %', v_result;
  END IF;

  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-24T10:02:00Z'
  );
  IF v_decision->>'status' <> 'active' THEN
    RAISE EXCEPTION 'stale event regressed active access: %', v_decision;
  END IF;

  v_result := public.apply_entitlement_event(
    'rc-event-002',
    'CANCELLATION',
    v_user_id,
    'bodyflow_full',
    'revenuecat',
    'rc-subscription-001',
    'canceled',
    'mensal',
    'sandbox',
    '2026-07-24T10:03:00Z',
    '2026-07-24T10:00:00Z',
    '2026-08-24T10:00:00Z',
    NULL,
    true,
    NULL,
    NULL
  );
  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-25T10:00:00Z'
  );
  IF v_decision->>'has_active_access' <> 'true'
    OR v_decision->>'status' <> 'canceled'
    OR v_decision->>'reason' <> 'canceled_until_expiry' THEN
    RAISE EXCEPTION 'canceled subscription lost paid-through access: %', v_decision;
  END IF;

  PERFORM public.apply_entitlement_event(
    'manual-event-001',
    'MANUAL_COMP',
    v_user_id,
    'bodyflow_full',
    'manual',
    'manual-comp-001',
    'manual_comp',
    'mensal',
    'internal',
    '2026-07-24T10:04:00Z',
    '2026-07-24T10:04:00Z',
    NULL,
    NULL,
    false,
    'support_comp',
    '00000000-0000-4000-8000-000000000899'
  );

  PERFORM public.apply_entitlement_event(
    'manual-event-002',
    'BLOCK',
    v_user_id,
    'bodyflow_full',
    'manual',
    'manual-block-001',
    'blocked',
    NULL,
    'internal',
    '2026-07-24T10:05:00Z',
    '2026-07-24T10:05:00Z',
    NULL,
    NULL,
    false,
    'abuse_review',
    '00000000-0000-4000-8000-000000000899'
  );

  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-25T10:00:00Z'
  );
  IF v_decision->>'has_active_access' <> 'false'
    OR v_decision->>'status' <> 'blocked'
    OR v_decision->>'reason' <> 'blocked' THEN
    RAISE EXCEPTION 'explicit block did not override valid sources: %', v_decision;
  END IF;

  BEGIN
    PERFORM public.apply_entitlement_event(
      'rc-event-003',
      'RENEWAL',
      v_other_user_id,
      'bodyflow_full',
      'revenuecat',
      'rc-subscription-001',
      'active',
      'mensal',
      'sandbox',
      '2026-07-24T10:06:00Z',
      '2026-07-24T10:00:00Z',
      '2026-08-24T10:00:00Z',
      NULL,
      false,
      NULL,
      NULL
    );
    RAISE EXCEPTION 'provider source reference was reassigned to another user';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;
END;
$test$;

DO $test$
DECLARE
  v_user_id constant uuid := '00000000-0000-4000-8000-000000000803';
  v_subscription_id constant uuid := '00000000-0000-4000-8000-000000000804';
  v_decision jsonb;
  v_result jsonb;
BEGIN
  INSERT INTO public.users (id, wpp, email, name, locale, timezone, status, metadata)
  VALUES (
    v_user_id, NULL, NULL, 'Synthetic Legacy Stripe', 'pt-BR',
    'America/Sao_Paulo', 'active', '{}'::jsonb
  );

  INSERT INTO public.subscriptions (
    id,
    user_id,
    provider,
    provider_subscription_id,
    plan,
    status,
    current_period_start,
    current_period_end,
    cancel_at_period_end
  ) VALUES (
    v_subscription_id,
    v_user_id,
    'stripe',
    'stripe-legacy-001',
    'anual',
    'active',
    '2026-07-01T00:00:00Z',
    '2027-07-01T00:00:00Z',
    false
  );

  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-24T10:00:00Z'
  );
  IF v_decision->>'has_active_access' <> 'true'
    OR v_decision->>'source' <> 'stripe'
    OR v_decision->>'reason' <> 'legacy_subscription' THEN
    RAISE EXCEPTION 'legacy Stripe read-through failed: %', v_decision;
  END IF;

  v_result := public.sync_stripe_subscription_entitlement(
    v_subscription_id,
    'stripe-event-001',
    '2026-07-24T10:01:00Z',
    'internal'
  );
  IF v_result->>'result' <> 'applied' THEN
    RAISE EXCEPTION 'Stripe subscription projection failed: %', v_result;
  END IF;

  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-24T10:02:00Z'
  );
  IF v_decision->>'has_active_access' <> 'true'
    OR v_decision->>'source' <> 'stripe'
    OR v_decision->>'reason' <> 'valid_entitlement' THEN
    RAISE EXCEPTION 'projected Stripe entitlement was not canonical: %', v_decision;
  END IF;

  UPDATE public.subscriptions
  SET status = 'trial',
      plan = 'trial',
      trial_ends_at = '2026-08-01T00:00:00Z',
      current_period_end = '2026-08-01T00:00:00Z'
  WHERE id = v_subscription_id;
  PERFORM public.sync_stripe_subscription_entitlement(
    v_subscription_id,
    'stripe-event-002',
    '2026-07-24T10:03:00Z',
    'internal'
  );
  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-24T10:03:01Z'
  );
  IF v_decision->>'status' <> 'trialing'
    OR v_decision->>'has_active_access' <> 'true' THEN
    RAISE EXCEPTION 'Stripe trial projection failed: %', v_decision;
  END IF;

  UPDATE public.subscriptions
  SET status = 'past_due',
      plan = 'mensal',
      trial_ends_at = NULL,
      current_period_end = '2026-07-30T00:00:00Z'
  WHERE id = v_subscription_id;
  PERFORM public.sync_stripe_subscription_entitlement(
    v_subscription_id,
    'stripe-event-003',
    '2026-07-24T10:04:00Z',
    'internal'
  );
  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-24T10:04:01Z'
  );
  IF v_decision->>'status' <> 'grace_period'
    OR v_decision->>'has_active_access' <> 'true'
    OR v_decision->>'grace_expires_at' IS NULL THEN
    RAISE EXCEPTION 'Stripe grace-period projection failed: %', v_decision;
  END IF;

  UPDATE public.subscriptions
  SET status = 'canceled',
      current_period_end = '2026-07-30T00:00:00Z',
      cancel_at_period_end = true
  WHERE id = v_subscription_id;
  PERFORM public.sync_stripe_subscription_entitlement(
    v_subscription_id,
    'stripe-event-004',
    '2026-07-24T10:05:00Z',
    'internal'
  );
  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-24T10:05:01Z'
  );
  IF v_decision->>'status' <> 'canceled'
    OR v_decision->>'has_active_access' <> 'true'
    OR v_decision->>'cancel_at_period_end' <> 'true' THEN
    RAISE EXCEPTION 'Stripe canceled paid-through projection failed: %', v_decision;
  END IF;

  UPDATE public.subscriptions
  SET status = 'expired',
      current_period_end = '2026-07-24T09:00:00Z',
      cancel_at_period_end = false
  WHERE id = v_subscription_id;
  PERFORM public.sync_stripe_subscription_entitlement(
    v_subscription_id,
    'stripe-event-005',
    '2026-07-24T10:06:00Z',
    'internal'
  );
  v_decision := public.resolve_user_entitlement(
    v_user_id,
    'bodyflow_full',
    '2026-07-24T10:06:01Z'
  );
  IF v_decision->>'status' <> 'expired'
    OR v_decision->>'has_active_access' <> 'false' THEN
    RAISE EXCEPTION 'Stripe expiry projection failed: %', v_decision;
  END IF;
END;
$test$;

ROLLBACK;
