BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000779';
  v_subscription_id uuid;
  v_message_id uuid;
  v_result jsonb;
  v_count integer;
  v_profile public.user_profiles%ROWTYPE;
  v_progress public.user_progress%ROWTYPE;
  v_user public.users%ROWTYPE;
BEGIN
  INSERT INTO public.users (
    id,
    wpp,
    email,
    name,
    timezone,
    country,
    country_confirmed,
    metadata,
    summary,
    tags
  ) VALUES (
    v_user_id,
    '17777777779',
    'reset-test@example.invalid',
    'reset-test',
    'America/New_York',
    'US',
    true,
    '{"buttons_enabled":true}'::jsonb,
    'old summary',
    ARRAY['old-tag']
  );

  INSERT INTO public.user_profiles (
    user_id,
    sex,
    birth_date,
    weight_kg,
    body_fat_percent,
    body_fat_measured_at,
    bf_percent_estimated,
    bf_estimated_at,
    bf_source,
    current_protocol,
    cycle_start_weight_kg,
    cycle_start_bf_percent,
    cycle_start_training_freq,
    cycle_start_at,
    food_organization,
    onboarding_completed,
    onboarding_step
  ) VALUES (
    v_user_id,
    'masculino',
    date '1980-01-01',
    90,
    20,
    now(),
    21,
    now(),
    'vision',
    'recomposicao',
    90,
    20,
    4,
    now(),
    'sim',
    true,
    9
  );

  INSERT INTO public.user_progress (
    user_id,
    xp_total,
    level,
    current_streak,
    longest_streak,
    blocks_completed,
    deficit_block,
    current_weight,
    current_bf_percent,
    badges_earned,
    last_active_date,
    next_reevaluation
  ) VALUES (
    v_user_id,
    500,
    4,
    7,
    10,
    2,
    3100,
    89,
    19,
    ARRAY['old-badge'],
    date '2026-07-11',
    date '2026-07-20'
  );

  INSERT INTO public.messages (
    user_id,
    direction,
    role,
    content_type,
    content,
    provider
  ) VALUES (
    v_user_id,
    'in',
    'user',
    'text',
    'old message',
    'whatsapp_cloud'
  ) RETURNING id INTO v_message_id;

  INSERT INTO public.pending_registrations (
    user_id,
    proposal,
    proposal_msg_id,
    expires_at
  ) VALUES (
    v_user_id,
    '{"kind":"meal","mealType":"jantar"}'::jsonb,
    v_message_id,
    now() + interval '1 hour'
  );

  INSERT INTO public.prescriptions (user_id, type, payload)
  VALUES (v_user_id, 'combined', '{}'::jsonb);

  INSERT INTO public.training_plans (
    user_id,
    plan_type,
    days_per_week,
    weekly_schedule
  ) VALUES (
    v_user_id,
    'split',
    3,
    '[]'::jsonb
  );

  INSERT INTO public.subscriptions (
    user_id,
    provider,
    provider_subscription_id,
    plan,
    status
  ) VALUES (
    v_user_id,
    'stripe',
    'sub_reset_test',
    'mensal',
    'active'
  ) RETURNING id INTO v_subscription_id;

  INSERT INTO public.subscription_events (
    subscription_id,
    user_id,
    event_type,
    provider_event_id
  ) VALUES (
    v_subscription_id,
    v_user_id,
    'invoice.payment_succeeded',
    'evt_reset_test'
  );

  v_result := public.reset_user_conversation_atomic(v_user_id);
  IF NOT (v_result->>'reset')::boolean THEN
    RAISE EXCEPTION 'reset did not report success: %', v_result;
  END IF;

  SELECT count(*) INTO v_count FROM public.messages WHERE user_id = v_user_id;
  IF v_count <> 0 THEN RAISE EXCEPTION 'messages survived reset'; END IF;
  SELECT count(*) INTO v_count FROM public.pending_registrations WHERE user_id = v_user_id;
  IF v_count <> 0 THEN RAISE EXCEPTION 'pending survived reset'; END IF;
  SELECT count(*) INTO v_count FROM public.prescriptions WHERE user_id = v_user_id;
  IF v_count <> 0 THEN RAISE EXCEPTION 'prescription survived reset'; END IF;
  SELECT count(*) INTO v_count FROM public.training_plans WHERE user_id = v_user_id;
  IF v_count <> 0 THEN RAISE EXCEPTION 'training plan survived reset'; END IF;

  SELECT count(*) INTO v_count FROM public.subscriptions WHERE user_id = v_user_id;
  IF v_count <> 1 THEN RAISE EXCEPTION 'subscription was removed by reset'; END IF;
  SELECT count(*) INTO v_count FROM public.subscription_events WHERE user_id = v_user_id;
  IF v_count <> 1 THEN RAISE EXCEPTION 'billing event was removed by reset'; END IF;

  SELECT * INTO v_profile FROM public.user_profiles WHERE user_id = v_user_id;
  IF v_profile.onboarding_completed
    OR v_profile.onboarding_step <> 0
    OR v_profile.weight_kg IS NOT NULL
    OR v_profile.body_fat_measured_at IS NOT NULL
    OR v_profile.bf_percent_estimated IS NOT NULL
    OR v_profile.cycle_start_at IS NOT NULL
    OR v_profile.food_organization IS NOT NULL THEN
    RAISE EXCEPTION 'profile was only partially reset: %', row_to_json(v_profile);
  END IF;

  SELECT * INTO v_progress FROM public.user_progress WHERE user_id = v_user_id;
  IF v_progress.xp_total <> 0
    OR v_progress.level <> 1
    OR v_progress.current_streak <> 0
    OR v_progress.deficit_block <> 0
    OR v_progress.current_weight IS NOT NULL
    OR cardinality(v_progress.badges_earned) <> 0 THEN
    RAISE EXCEPTION 'progress was only partially reset: %', row_to_json(v_progress);
  END IF;

  SELECT * INTO v_user FROM public.users WHERE id = v_user_id;
  IF v_user.wpp <> '17777777779'
    OR v_user.email <> 'reset-test@example.invalid'
    OR v_user.timezone <> 'America/New_York'
    OR v_user.country <> 'US'
    OR v_user.name IS NOT NULL
    OR v_user.country_confirmed
    OR v_user.metadata <> '{}'::jsonb THEN
    RAISE EXCEPTION 'identity/basics reset is inconsistent: %', row_to_json(v_user);
  END IF;

  IF has_function_privilege(
    'anon',
    'public.reset_user_conversation_atomic(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not reset conversations';
  END IF;
END;
$test$;

ROLLBACK;
