BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000778';
  v_subscription_id uuid;
  v_result jsonb;
  v_status text;
  v_attempt_count integer;
  v_amount integer;
  v_linked_user uuid;
  v_linked_subscription uuid;
BEGIN
  INSERT INTO public.users (id, wpp, name)
  VALUES (v_user_id, '17777777778', 'stripe-event-test')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.subscriptions (
    user_id,
    provider,
    provider_subscription_id,
    plan,
    status
  ) VALUES (
    v_user_id,
    'stripe',
    'sub_atomic_test',
    'mensal',
    'active'
  )
  RETURNING id INTO v_subscription_id;

  v_result := public.claim_subscription_event(
    'evt_atomic_test',
    'invoice.payment_succeeded',
    '{"id":"evt_atomic_test"}'::jsonb,
    timestamptz '2026-07-12 12:00:00+00'
  );
  IF v_result->>'status' <> 'claimed' THEN
    RAISE EXCEPTION 'first claim failed: %', v_result;
  END IF;

  v_result := public.claim_subscription_event(
    'evt_atomic_test',
    'invoice.payment_succeeded',
    '{"id":"evt_atomic_test"}'::jsonb,
    timestamptz '2026-07-12 12:01:00+00'
  );
  IF v_result->>'status' <> 'in_progress' THEN
    RAISE EXCEPTION 'concurrent claim was not blocked: %', v_result;
  END IF;

  PERFORM public.finish_subscription_event(
    'evt_atomic_test',
    false,
    '{}'::jsonb,
    'temporary write failure',
    timestamptz '2026-07-12 12:02:00+00'
  );

  v_result := public.claim_subscription_event(
    'evt_atomic_test',
    'invoice.payment_succeeded',
    '{"id":"evt_atomic_test"}'::jsonb,
    timestamptz '2026-07-12 12:03:00+00'
  );
  IF v_result->>'status' <> 'claimed' OR (v_result->>'attempt_count')::integer <> 2 THEN
    RAISE EXCEPTION 'failed event was not reclaimed: %', v_result;
  END IF;

  PERFORM public.finish_subscription_event(
    'evt_atomic_test',
    true,
    jsonb_build_object(
      'user_id', v_user_id,
      'subscription_id', v_subscription_id,
      'amount_cents', 3900,
      'currency', 'usd'
    ),
    null,
    timestamptz '2026-07-12 12:04:00+00'
  );

  SELECT processing_status, attempt_count, amount_cents, user_id, subscription_id
  INTO v_status, v_attempt_count, v_amount, v_linked_user, v_linked_subscription
  FROM public.subscription_events
  WHERE provider_event_id = 'evt_atomic_test';

  IF v_status <> 'processed'
    OR v_attempt_count <> 2
    OR v_amount <> 3900
    OR v_linked_user <> v_user_id
    OR v_linked_subscription <> v_subscription_id THEN
    RAISE EXCEPTION 'event finalization is inconsistent: %, %, %, %, %',
      v_status, v_attempt_count, v_amount, v_linked_user, v_linked_subscription;
  END IF;

  v_result := public.claim_subscription_event(
    'evt_atomic_test',
    'invoice.payment_succeeded',
    '{"id":"evt_atomic_test"}'::jsonb,
    timestamptz '2026-07-12 12:05:00+00'
  );
  IF v_result->>'status' <> 'duplicate' THEN
    RAISE EXCEPTION 'processed event was not deduplicated: %', v_result;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.claim_subscription_event(text,text,jsonb,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not claim subscription events';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.claim_subscription_event(text,text,jsonb,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must claim subscription events';
  END IF;
END;
$test$;

ROLLBACK;
