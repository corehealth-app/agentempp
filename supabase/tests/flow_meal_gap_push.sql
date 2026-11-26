-- Synthetic owners, APNs tokens and a local database. Rolls back all test rows.
BEGIN;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';

DO $test$
DECLARE
  owner_id constant uuid := '19000000-0000-4000-8000-000000001001';
  other_id constant uuid := '19000000-0000-4000-8000-000000001002';
  device_id uuid;
  topic constant text := 'com.example.performe.gap-test';
  zone text;
  local_day date;
  now_at timestamptz := statement_timestamp();
BEGIN
  -- Pick a real IANA timezone currently in the middle of the evening window.
  SELECT name INTO STRICT zone FROM pg_catalog.pg_timezone_names
  WHERE extract(hour FROM now_at AT TIME ZONE name) = 22 ORDER BY name LIMIT 1;
  local_day := (now_at AT TIME ZONE zone)::date;
  INSERT INTO public.users(id, name, locale, timezone, status)
  VALUES (owner_id, 'Synthetic flow gap', 'pt-BR', zone, 'active'),
         (other_id, 'Synthetic flow gap other', 'pt-BR', zone, 'active');
  PERFORM public.apply_entitlement_event(
    'flow-gap-test-access', 'INITIAL_PURCHASE', owner_id, 'bodyflow_full', 'revenuecat',
    'flow-gap-test-subscription', 'active', 'mensal', 'sandbox', now_at - interval '1 day',
    now_at - interval '1 day', now_at + interval '1 day', NULL, false, NULL, NULL
  );

  device_id := public.upsert_mobile_device(owner_id, 'flow-gap-test-installation', 'sandbox', repeat('e8', 32));
  IF public.configure_flow_meal_gap_device(other_id, device_id, topic, true, true)
    OR (SELECT count(*) FROM public.list_flow_meal_gap_targets(topic, NULL, 5)) <> 0
    THEN RAISE EXCEPTION 'A device without opt-in must not be discovered'; END IF;
  IF NOT public.configure_flow_meal_gap_device(owner_id, device_id, topic, true, false)
    THEN RAISE EXCEPTION 'Opt-in should succeed for its own device'; END IF;
  IF (SELECT count(*) FROM public.list_flow_meal_gap_targets(topic, NULL, 5)) <> 1
    OR (SELECT count(*) FROM public.list_flow_meal_gap_targets('com.example.other', NULL, 5)) <> 0
    THEN RAISE EXCEPTION 'Target opt-in must be scoped to its owner and app topic'; END IF;

  INSERT INTO public.product_events(user_id, event, occurred_at, properties)
  VALUES (owner_id, 'meal.user_skipped', now_at, jsonb_build_object('local_date', local_day, 'meal_type', 'almoco'));
  IF public.claim_flow_meal_gap_notice(owner_id, device_id, topic, local_day, 'before_close','almoco') IS NOT NULL
    THEN RAISE EXCEPTION 'An explicitly skipped meal must not produce a notification'; END IF;

  INSERT INTO public.meal_logs(user_id, meal_type, food_name, consumed_at)
  VALUES (owner_id, 'lanche', 'Synthetic snack', now_at);
  IF public.claim_flow_meal_gap_notice(owner_id, device_id, topic, local_day, 'before_close','lanche') IS NOT NULL
    THEN RAISE EXCEPTION 'A meal already recorded for the local day must not produce a notification'; END IF;

  UPDATE public.notification_preferences SET quiet_hours_start = '21:00', quiet_hours_end = '07:00'
  WHERE user_id = owner_id;
  IF public.claim_flow_meal_gap_notice(owner_id, device_id, topic, local_day, 'before_close','jantar') IS NOT NULL
    THEN RAISE EXCEPTION 'Quiet hours spanning midnight must suppress delivery'; END IF;
  UPDATE public.notification_preferences SET quiet_hours_start = NULL, quiet_hours_end = NULL
  WHERE user_id = owner_id;

  INSERT INTO private.conversation_intake_ids(user_id, intake_id, input_hash, epoch, admitted_at, reserved_child_id)
  VALUES (owner_id, '19000000-0000-4000-8000-000000001011', repeat('a', 64), gen_random_uuid(), now_at, gen_random_uuid());
  INSERT INTO private.conversation_intake_inputs(user_id, intake_id, source_input, admitted_time_zone, admitted_local_date)
  VALUES (owner_id, '19000000-0000-4000-8000-000000001011', '{}'::jsonb, zone, local_day);
  IF public.claim_flow_meal_gap_notice(owner_id, device_id, topic, local_day, 'before_close','jantar') IS NOT NULL
    OR public.read_flow_meal_gap_activity(owner_id, local_day)->'blocked' IS DISTINCT FROM 'true'::jsonb
    THEN RAISE EXCEPTION 'An intake in progress must suppress reminders'; END IF;
  RAISE NOTICE 'flow reminder opt-in, timezone, recorded meal, skip, quiet hours and in-flight suppression passed';
END $test$;

DO $test$
DECLARE
  u constant uuid := '19000000-0000-4000-8000-000000001100';
  topic constant text := 'com.example.performe.gap-test-delivery';
  d uuid;
  zone text;
  local_day date;
  delivered jsonb;
  notice_id uuid;
  lease_id uuid;
  now_at timestamptz := clock_timestamp();
BEGIN
  SELECT name INTO STRICT zone FROM pg_catalog.pg_timezone_names
  WHERE extract(hour FROM now_at AT TIME ZONE name) = 22 ORDER BY name LIMIT 1;
  local_day := (now_at AT TIME ZONE zone)::date;
  INSERT INTO public.users(id, name, locale, timezone, status)
  VALUES (u, 'Synthetic flow gap delivery', 'pt-BR', zone, 'active');
  PERFORM public.apply_entitlement_event(
    'flow-gap-test-delivery-access', 'INITIAL_PURCHASE', u, 'bodyflow_full', 'revenuecat',
    'flow-gap-test-delivery-subscription', 'active', 'mensal', 'sandbox', now_at - interval '1 day',
    now_at - interval '1 day', now_at + interval '1 day', NULL, false, NULL, NULL
  );
  d := public.register_flow_meal_gap_device(
    u, 'flow-gap-test-delivery-installation', 'sandbox', repeat('e9', 32), topic, false
  );
  delivered := public.claim_flow_meal_gap_notice(u, d, topic, local_day, 'before_close','jantar');
  notice_id := (delivered->>'id')::uuid;
  lease_id := (delivered->>'claim_id')::uuid;
  IF notice_id IS NULL OR lease_id IS NULL
    OR public.claim_flow_meal_gap_notice(u, d, topic, local_day, 'before_close','jantar') IS NOT NULL
    OR public.finish_flow_meal_gap_notice(notice_id, gen_random_uuid(), 'accepted')
    THEN RAISE EXCEPTION 'A meal reminder can be leased only once and requires its own claim id'; END IF;
  IF NOT public.finish_flow_meal_gap_notice(notice_id, lease_id, 'accepted')
    THEN RAISE EXCEPTION 'The valid claim must finish'; END IF;
  IF public.read_flow_meal_gap_notice(u, notice_id) IS DISTINCT FROM jsonb_build_object(
      'id', notice_id, 'local_date', local_day, 'meal_type', 'jantar', 'state', 'pending'
    ) OR public.read_flow_meal_gap_notice(gen_random_uuid(), notice_id) IS NOT NULL
    THEN RAISE EXCEPTION 'Only the owner should be able to read the pending reminder'; END IF;
  INSERT INTO public.meal_logs(user_id, meal_type, food_name, consumed_at)
  VALUES (u, 'jantar', 'Synthetic dinner', now_at);
  IF public.read_flow_meal_gap_notice(u, notice_id)->>'state' IS DISTINCT FROM 'resolved'
    THEN RAISE EXCEPTION 'Opening a reminder should recheck the current diary first'; END IF;
  IF public.finish_flow_meal_gap_notice(notice_id, lease_id, 'accepted')
    OR public.claim_flow_meal_gap_notice(u, d, topic, local_day, 'before_close','almoco') IS NOT NULL
    OR jsonb_array_length(public.read_flow_meal_gap_activity(u, local_day)->'accepted') <> 1
    THEN RAISE EXCEPTION 'Only one before-close notification can count per civil day'; END IF;
  RAISE NOTICE 'flow reminder lease, delivery acknowledgment and daily deduplication passed';
END $test$;

DO $acl$
BEGIN
  IF has_function_privilege('authenticated', 'public.claim_flow_meal_gap_notice(uuid,uuid,text,date,text,public.meal_type_enum)', 'EXECUTE')
    OR has_function_privilege('anon', 'public.list_flow_meal_gap_targets(text,uuid,integer)', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.read_flow_meal_gap_notice(uuid,uuid)', 'EXECUTE')
    OR has_table_privilege('authenticated', 'private.flow_meal_gap_notices', 'SELECT')
    THEN RAISE EXCEPTION 'The reminders gateway must not expose device or notice data to clients'; END IF;
END $acl$;
ROLLBACK;
