BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000701';
  v_other_user_id uuid := '00000000-0000-0000-0000-000000000702';
  v_auth_user_id uuid := '00000000-0000-0000-0000-000000000703';
  v_other_auth_user_id uuid := '00000000-0000-0000-0000-000000000704';
  v_device_id uuid;
  v_hydration_first jsonb;
  v_hydration_retry jsonb;
  v_adherence_first jsonb;
  v_adherence_retry jsonb;
  v_rule_id uuid;
  v_first_queue_rule_id uuid;
  v_limit_rule_id uuid;
  v_resolved_rule_id uuid;
  v_routine_rule_id uuid;
  v_item_id uuid;
  v_event_first jsonb;
  v_event_retry jsonb;
  v_event_id uuid;
  v_delivery_count integer;
  v_water_ml integer;
  v_status text;
  v_reason text;
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'mobile_devices',
    'notification_preferences',
    'reminder_rules',
    'routine_items',
    'hydration_logs',
    'routine_adherence_logs',
    'reminder_events',
    'notification_deliveries'
  ]
  LOOP
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
  END LOOP;

  IF has_table_privilege('anon', 'public.mobile_devices', 'SELECT')
    OR has_table_privilege('authenticated', 'public.mobile_devices', 'INSERT')
    OR has_table_privilege('authenticated', 'public.mobile_devices', 'UPDATE')
    OR has_table_privilege('authenticated', 'public.mobile_devices', 'DELETE')
    OR has_table_privilege('authenticated', 'public.notification_preferences', 'INSERT')
    OR has_table_privilege('authenticated', 'public.reminder_rules', 'UPDATE')
    OR has_table_privilege('authenticated', 'public.hydration_logs', 'INSERT')
    OR has_table_privilege('authenticated', 'public.routine_adherence_logs', 'DELETE')
    OR has_table_privilege('authenticated', 'public.notification_deliveries', 'SELECT') THEN
    RAISE EXCEPTION 'client role received a forbidden BodyFlow write or internal read grant';
  END IF;

  IF has_column_privilege('authenticated', 'public.mobile_devices', 'apns_token', 'SELECT')
    OR has_column_privilege('authenticated', 'public.mobile_devices', 'apns_token_hash', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated can select an APNs token or hash';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.upsert_mobile_device(uuid,text,text,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.deactivate_mobile_device(uuid,uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.record_hydration_atomic(uuid,date,integer,text,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.record_routine_adherence_atomic(uuid,uuid,text,text,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.claim_reminder_event(uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.update_notification_preferences_atomic(uuid,jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'authenticated can execute a mutable BodyFlow RPC';
  END IF;

  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_sso_user, is_anonymous
  ) VALUES
    (v_auth_user_id, 'authenticated', 'authenticated', 'bodyflow-push-a-auth@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_other_auth_user_id, 'authenticated', 'authenticated', 'bodyflow-push-b-auth@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false);

  INSERT INTO public.users (id, auth_user_id, email, timezone)
  VALUES
    (v_user_id, v_auth_user_id, 'bodyflow-push-a@example.com', 'America/Sao_Paulo'),
    (v_other_user_id, v_other_auth_user_id, 'bodyflow-push-b@example.com', 'America/Sao_Paulo');

  INSERT INTO public.daily_snapshots (user_id, date)
  VALUES (v_user_id, date '2026-07-20');

  INSERT INTO public.notification_preferences (
    user_id,
    push_enabled,
    quiet_hours_start,
    quiet_hours_end,
    daily_push_limit,
    hydration_target_ml
  ) VALUES (
    v_user_id,
    true,
    time '22:00',
    time '07:00',
    2,
    2000
  );

  PERFORM public.update_notification_preferences_atomic(
    v_user_id,
    '{"daily_push_limit":3}'::jsonb
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.notification_preferences
    WHERE user_id = v_user_id
      AND daily_push_limit = 3
      AND quiet_hours_start = time '22:00'
      AND quiet_hours_end = time '07:00'
      AND hydration_target_ml = 2000
  ) THEN
    RAISE EXCEPTION 'atomic preference patch overwrote fields outside the patch';
  END IF;

  PERFORM public.update_notification_preferences_atomic(
    v_user_id,
    '{"daily_push_limit":2}'::jsonb
  );

  v_device_id := public.upsert_mobile_device(
    v_user_id,
    'ios-installation-a',
    'sandbox',
    repeat('a', 64)
  );

  IF v_device_id IS NULL
    OR (SELECT count(*) FROM public.mobile_devices WHERE user_id = v_user_id) <> 1 THEN
    RAISE EXCEPTION 'device upsert did not create one owned installation';
  END IF;

  BEGIN
    PERFORM public.upsert_mobile_device(
      v_other_user_id,
      'ios-installation-a',
      'sandbox',
      repeat('d', 64)
    );
    RAISE EXCEPTION 'active installation was reassigned without matching token evidence';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  PERFORM public.upsert_mobile_device(
    v_other_user_id,
    'ios-installation-b',
    'sandbox',
    repeat('a', 64)
  );

  IF EXISTS (
    SELECT 1
    FROM public.mobile_devices
    WHERE user_id = v_user_id
      AND apns_token = repeat('a', 64)
      AND active
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.mobile_devices
    WHERE user_id = v_other_user_id
      AND apns_token = repeat('a', 64)
      AND active
  ) THEN
    RAISE EXCEPTION 'reassociated token remained active for the old account';
  END IF;

  PERFORM public.upsert_mobile_device(
    v_user_id,
    'ios-installation-a',
    'sandbox',
    repeat('b', 64)
  );
  PERFORM public.upsert_mobile_device(
    v_user_id,
    'ios-installation-c',
    'sandbox',
    repeat('c', 64)
  );

  v_hydration_first := public.record_hydration_atomic(
    v_user_id,
    date '2026-07-20',
    350,
    'hydration-0001',
    timestamptz '2026-07-20 12:00:00+00'
  );
  v_hydration_retry := public.record_hydration_atomic(
    v_user_id,
    date '2026-07-20',
    350,
    'hydration-0001',
    timestamptz '2026-07-20 12:00:00+00'
  );

  SELECT water_consumed_ml
  INTO v_water_ml
  FROM public.daily_snapshots
  WHERE user_id = v_user_id AND date = date '2026-07-20';

  IF NOT (v_hydration_first ->> 'inserted')::boolean
    OR (v_hydration_retry ->> 'inserted')::boolean
    OR v_water_ml <> 350
    OR (SELECT count(*) FROM public.hydration_logs WHERE user_id = v_user_id) <> 1 THEN
    RAISE EXCEPTION 'hydration atomic idempotency failed: first %, retry %, water %',
      v_hydration_first, v_hydration_retry, v_water_ml;
  END IF;

  INSERT INTO public.routine_items (user_id, item_type, name, active)
  VALUES (v_user_id, 'supplement', 'Vitamina D', true)
  RETURNING id INTO v_item_id;

  BEGIN
    INSERT INTO public.reminder_rules (
      user_id,
      routine_item_id,
      category,
      local_time,
      weekdays
    ) VALUES (
      v_other_user_id,
      v_item_id,
      'supplement',
      time '08:00',
      ARRAY[0, 1, 2, 3, 4, 5, 6]
    );
    RAISE EXCEPTION 'cross-user routine reminder was accepted';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO public.reminder_rules (
      user_id,
      routine_item_id,
      category,
      local_time,
      weekdays
    ) VALUES (
      v_user_id,
      v_item_id,
      'medication',
      time '08:00',
      ARRAY[0, 1, 2, 3, 4, 5, 6]
    );
    RAISE EXCEPTION 'routine reminder accepted an incompatible item type';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  v_adherence_first := public.record_routine_adherence_atomic(
    v_user_id,
    v_item_id,
    'supplement',
    'adherence-0001',
    timestamptz '2026-07-20 12:05:00+00'
  );
  v_adherence_retry := public.record_routine_adherence_atomic(
    v_user_id,
    v_item_id,
    'supplement',
    'adherence-0001',
    timestamptz '2026-07-20 12:05:00+00'
  );

  UPDATE public.routine_items
  SET active = false
  WHERE id = v_item_id;
  v_adherence_retry := public.record_routine_adherence_atomic(
    v_user_id,
    v_item_id,
    'supplement',
    'adherence-0001',
    timestamptz '2026-07-20 12:05:00+00'
  );
  UPDATE public.routine_items
  SET active = true
  WHERE id = v_item_id;

  IF NOT (v_adherence_first ->> 'inserted')::boolean
    OR (v_adherence_retry ->> 'inserted')::boolean
    OR (SELECT count(*) FROM public.routine_adherence_logs WHERE user_id = v_user_id) <> 1 THEN
    RAISE EXCEPTION 'routine adherence was not idempotent: first %, retry %',
      v_adherence_first, v_adherence_retry;
  END IF;

  BEGIN
    PERFORM public.record_routine_adherence_atomic(
      v_user_id,
      v_item_id,
      'medication',
      'adherence-wrong-type',
      timestamptz '2026-07-20 12:06:00+00'
    );
    RAISE EXCEPTION 'routine item type mismatch was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'routine item type mismatch was accepted' THEN
        RAISE;
      END IF;
  END;

  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays,
    active
  ) VALUES (
    v_user_id,
    'hydration',
    time '21:58',
    ARRAY[0, 1, 2, 3, 4, 5, 6],
    true
  ) RETURNING id INTO v_rule_id;

  v_event_first := public.claim_reminder_event(
    v_rule_id,
    timestamptz '2026-07-21 00:58:00+00',
    timestamptz '2026-07-21 01:01:00+00'
  );
  v_event_retry := public.claim_reminder_event(
    v_rule_id,
    timestamptz '2026-07-21 00:58:00+00',
    timestamptz '2026-07-21 01:01:00+00'
  );

  SELECT id, status, suppression_reason
  INTO v_event_id, v_status, v_reason
  FROM public.reminder_events
  WHERE reminder_rule_id = v_rule_id
    AND scheduled_for = timestamptz '2026-07-21 00:58:00+00';

  IF (v_event_first ->> 'event_id')::uuid <> v_event_id
    OR (v_event_retry ->> 'event_id')::uuid <> v_event_id
    OR v_status <> 'suppressed'
    OR v_reason <> 'quiet_hours'
    OR EXISTS (
      SELECT 1 FROM public.notification_deliveries WHERE reminder_event_id = v_event_id
    ) THEN
    RAISE EXCEPTION 'quiet-hours claim was not auditable and retry-safe: first %, retry %, status %, reason %',
      v_event_first, v_event_retry, v_status, v_reason;
  END IF;

  UPDATE public.reminder_rules
  SET active = false
  WHERE id = v_rule_id;
  v_event_retry := public.claim_reminder_event(
    v_rule_id,
    timestamptz '2026-07-21 00:58:00+00',
    timestamptz '2026-07-22 01:01:00+00'
  );

  IF (v_event_retry ->> 'event_id')::uuid <> v_event_id
    OR (v_event_retry ->> 'existing')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'historical reminder retry changed after rule deactivation: %', v_event_retry;
  END IF;

  BEGIN
    DELETE FROM public.reminder_rules WHERE id = v_rule_id;
    RAISE EXCEPTION 'reminder rule deletion erased or orphaned audit history';
  EXCEPTION
    WHEN foreign_key_violation THEN NULL;
  END;

  UPDATE public.notification_preferences
  SET quiet_hours_start = NULL,
      quiet_hours_end = NULL,
      daily_push_limit = 1
  WHERE user_id = v_user_id;

  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays,
    active
  ) VALUES (
    v_user_id,
    'hydration',
    time '15:00',
    ARRAY[0, 1, 2, 3, 4, 5, 6],
    true
  ) RETURNING id INTO v_first_queue_rule_id;

  v_event_first := public.claim_reminder_event(
    v_first_queue_rule_id,
    timestamptz '2026-07-20 18:00:00+00',
    timestamptz '2026-07-20 18:00:00+00'
  );
  v_event_retry := public.claim_reminder_event(
    v_first_queue_rule_id,
    timestamptz '2026-07-20 18:00:00+00',
    timestamptz '2026-07-20 18:01:00+00'
  );

  SELECT count(*)
  INTO v_delivery_count
  FROM public.notification_deliveries
  WHERE reminder_event_id = (v_event_first ->> 'event_id')::uuid;

  IF v_event_first ->> 'status' <> 'queued'
    OR v_event_retry ->> 'status' <> 'queued'
    OR (v_event_retry ->> 'existing')::boolean IS NOT TRUE
    OR v_delivery_count <> 2 THEN
    RAISE EXCEPTION 'queued reminder was not retry-safe per device: first %, retry %, deliveries %',
      v_event_first, v_event_retry, v_delivery_count;
  END IF;

  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays,
    active
  ) VALUES (
    v_user_id,
    'hydration',
    time '16:00',
    ARRAY[0, 1, 2, 3, 4, 5, 6],
    true
  ) RETURNING id INTO v_limit_rule_id;

  v_event_first := public.claim_reminder_event(
    v_limit_rule_id,
    timestamptz '2026-07-20 19:00:00+00',
    timestamptz '2026-07-20 19:00:00+00'
  );

  SELECT status, suppression_reason
  INTO v_status, v_reason
  FROM public.reminder_events
  WHERE id = (v_event_first ->> 'event_id')::uuid;

  IF v_status <> 'suppressed'
    OR v_reason <> 'daily_limit'
    OR EXISTS (
      SELECT 1
      FROM public.notification_deliveries
      WHERE reminder_event_id = (v_event_first ->> 'event_id')::uuid
    ) THEN
    RAISE EXCEPTION 'daily limit did not suppress the event safely: status %, reason %',
      v_status, v_reason;
  END IF;

  UPDATE public.notification_preferences
  SET daily_push_limit = 8
  WHERE user_id = v_user_id;
  UPDATE public.daily_snapshots
  SET water_consumed_ml = 2000
  WHERE user_id = v_user_id
    AND date = date '2026-07-20';

  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays
  ) VALUES (
    v_user_id,
    'hydration',
    time '17:00',
    ARRAY[0, 1, 2, 3, 4, 5, 6]
  ) RETURNING id INTO v_resolved_rule_id;

  v_event_first := public.claim_reminder_event(
    v_resolved_rule_id,
    timestamptz '2026-07-20 20:00:00+00',
    timestamptz '2026-07-20 20:00:00+00'
  );
  IF v_event_first ->> 'status' <> 'resolved'
    OR EXISTS (
      SELECT 1
      FROM public.notification_deliveries
      WHERE reminder_event_id = (v_event_first ->> 'event_id')::uuid
    ) THEN
    RAISE EXCEPTION 'resolved hydration produced a notification: %', v_event_first;
  END IF;

  INSERT INTO public.reminder_rules (
    user_id,
    routine_item_id,
    category,
    local_time,
    weekdays
  ) VALUES (
    v_user_id,
    v_item_id,
    'supplement',
    time '18:00',
    ARRAY[0, 1, 2, 3, 4, 5, 6]
  ) RETURNING id INTO v_routine_rule_id;

  v_event_first := public.claim_reminder_event(
    v_routine_rule_id,
    timestamptz '2026-07-20 21:00:00+00',
    timestamptz '2026-07-20 21:00:00+00'
  );
  IF v_event_first ->> 'status' <> 'resolved' THEN
    RAISE EXCEPTION 'taken supplement still produced a reminder: %', v_event_first;
  END IF;
END;
$test$;

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000703","role":"authenticated"}',
  true
);

DO $test$
DECLARE
  v_safe_device_count integer;
  v_cross_device_count integer;
  v_token_denied boolean := false;
BEGIN
  SELECT count(*) INTO v_safe_device_count
  FROM public.mobile_devices
  WHERE user_id = '00000000-0000-0000-0000-000000000701';

  SELECT count(*) INTO v_cross_device_count
  FROM public.mobile_devices
  WHERE user_id = '00000000-0000-0000-0000-000000000702';

  BEGIN
    PERFORM apns_token
    FROM public.mobile_devices
    WHERE id IS NOT NULL;
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_token_denied := true;
  END;

  IF v_safe_device_count <> 2
    OR v_cross_device_count <> 0
    OR NOT v_token_denied THEN
    RAISE EXCEPTION 'RLS or APNs column protections failed: own %, cross %, token denied %',
      v_safe_device_count, v_cross_device_count, v_token_denied;
  END IF;
END;
$test$;

ROLLBACK;
