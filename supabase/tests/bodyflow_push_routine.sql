BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000701';
  v_other_user_id uuid := '00000000-0000-0000-0000-000000000702';
  v_auth_user_id uuid := '00000000-0000-0000-0000-000000000703';
  v_other_auth_user_id uuid := '00000000-0000-0000-0000-000000000704';
  v_history_user_id uuid := '00000000-0000-0000-0000-000000000705';
  v_history_new_user_id uuid := '00000000-0000-0000-0000-000000000706';
  v_history_auth_user_id uuid := '00000000-0000-0000-0000-000000000707';
  v_history_new_auth_user_id uuid := '00000000-0000-0000-0000-000000000708';
  v_device_id uuid;
  v_history_device_id uuid;
  v_reassigned_device_id uuid;
  v_history_rule_id uuid;
  v_history_event_id uuid;
  v_hydration_first jsonb;
  v_hydration_retry jsonb;
  v_adherence_first jsonb;
  v_adherence_retry jsonb;
  v_rule_id uuid;
  v_first_queue_rule_id uuid;
  v_limit_rule_id uuid;
  v_resolved_rule_id uuid;
  v_routine_rule_id uuid;
  v_routine_evening_rule_id uuid;
  v_snooze_item_id uuid;
  v_snooze_rule_id uuid;
  v_snooze_evening_rule_id uuid;
  v_item_id uuid;
  v_exact_item_id uuid;
  v_inactive_item_id uuid;
  v_inactive_rule_id uuid;
  v_dst_rule_id uuid;
  v_stale_rule_id uuid;
  v_page_rule_id_a uuid;
  v_page_rule_id_b uuid;
  v_page_cursor_rule_id uuid;
  v_page_cursor_scheduled_for timestamptz;
  v_no_device_rule_id uuid;
  v_no_device_claim jsonb;
  v_event_first jsonb;
  v_event_retry jsonb;
  v_event_id uuid;
  v_delivery_usage_id uuid;
  v_delivery_version_id uuid;
  v_delivery_personality text;
  v_delivery_locale text;
  v_delivery_count integer;
  v_water_ml integer;
  v_status text;
  v_reason text;
  v_due_count integer;
  v_due_scheduled_for timestamptz;
  v_dst_due_count integer;
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
  ) OR has_function_privilege(
    'authenticated',
    'public.list_due_reminder_rules(timestamptz,integer,integer,timestamptz,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'authenticated can execute a forbidden BodyFlow backend RPC';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.list_due_reminder_rules(timestamptz,integer,integer,timestamptz,uuid)',
    'EXECUTE'
  ) OR EXISTS (
    SELECT 1
    FROM pg_proc function_definition
    JOIN pg_namespace namespace ON namespace.oid = function_definition.pronamespace
    WHERE namespace.nspname = 'public'
      AND function_definition.proname = 'list_due_reminder_rules'
      AND function_definition.prosecdef
  ) THEN
    RAISE EXCEPTION 'due reminder discovery is not service-only SECURITY INVOKER';
  END IF;

  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_sso_user, is_anonymous
  ) VALUES
    (v_auth_user_id, 'authenticated', 'authenticated', 'bodyflow-push-a-auth@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_other_auth_user_id, 'authenticated', 'authenticated', 'bodyflow-push-b-auth@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_history_auth_user_id, 'authenticated', 'authenticated', 'bodyflow-push-history-a-auth@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false),
    (v_history_new_auth_user_id, 'authenticated', 'authenticated', 'bodyflow-push-history-b-auth@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), false, false);

  INSERT INTO public.users (id, auth_user_id, email, timezone)
  VALUES
    (v_user_id, v_auth_user_id, 'bodyflow-push-a@example.com', 'America/Sao_Paulo'),
    (v_other_user_id, v_other_auth_user_id, 'bodyflow-push-b@example.com', 'America/Sao_Paulo'),
    (v_history_user_id, v_history_auth_user_id, 'bodyflow-push-history-a@example.com', 'America/Sao_Paulo'),
    (v_history_new_user_id, v_history_new_auth_user_id, 'bodyflow-push-history-b@example.com', 'America/Sao_Paulo');

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
    repeat('A', 64)
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

  v_history_device_id := public.upsert_mobile_device(
    v_history_user_id,
    'ios-installation-history',
    'sandbox',
    repeat('e', 64)
  );
  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays
  ) VALUES (
    v_history_user_id,
    'hydration',
    time '12:00',
    ARRAY[0, 1, 2, 3, 4, 5, 6]
  ) RETURNING id INTO v_history_rule_id;
  INSERT INTO public.reminder_events (
    user_id,
    reminder_rule_id,
    scheduled_for,
    status
  ) VALUES (
    v_history_user_id,
    v_history_rule_id,
    timestamptz '2026-07-20 15:00:00+00',
    'queued'
  ) RETURNING id INTO v_history_event_id;
  INSERT INTO public.notification_deliveries (
    user_id,
    reminder_event_id,
    mobile_device_id,
    channel,
    provider,
    template_key,
    personality,
    status,
    scheduled_for
  ) VALUES (
    v_history_user_id,
    v_history_event_id,
    v_history_device_id,
    'push',
    'apns',
    'bodyflow.hydration.reminder',
    'default',
    'queued',
    timestamptz '2026-07-20 15:00:00+00'
  );

  v_reassigned_device_id := public.upsert_mobile_device(
    v_history_new_user_id,
    'ios-installation-history',
    'sandbox',
    repeat('e', 64)
  );

  IF v_reassigned_device_id = v_history_device_id
    OR NOT EXISTS (
      SELECT 1
      FROM public.mobile_devices
      WHERE id = v_history_device_id
        AND user_id = v_history_user_id
        AND NOT active
    ) OR NOT EXISTS (
      SELECT 1
      FROM public.mobile_devices
      WHERE id = v_reassigned_device_id
        AND user_id = v_history_new_user_id
        AND active
    ) OR (SELECT count(*) FROM public.mobile_devices
          WHERE installation_id = 'ios-installation-history' AND active) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM public.notification_deliveries
      WHERE reminder_event_id = v_history_event_id
        AND mobile_device_id = v_history_device_id
        AND user_id = v_history_user_id
    ) THEN
    RAISE EXCEPTION 'device reassignment rewrote or detached historical delivery ownership';
  END IF;

  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays
  ) VALUES (
    v_history_user_id,
    'workout',
    time '13:30',
    ARRAY[0, 1, 2, 3, 4, 5, 6]
  ) RETURNING id INTO v_no_device_rule_id;

  v_no_device_claim := public.claim_reminder_event(
    v_no_device_rule_id,
    timestamptz '2026-07-20 16:30:00+00',
    timestamptz '2026-07-20 16:30:00+00'
  );

  IF v_no_device_claim->>'status' <> 'suppressed'
    OR v_no_device_claim->>'suppression_reason' <> 'no_active_device'
    OR EXISTS (
      SELECT 1
      FROM public.coach_message_usage
      WHERE user_id = v_history_user_id
    ) THEN
    RAISE EXCEPTION 'no-device reminder claimed catalog copy or queued a delivery: %',
      v_no_device_claim;
  END IF;

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

  UPDATE public.routine_items SET active = false WHERE id = v_item_id;
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
      'supplement',
      time '07:30',
      ARRAY[1, 2, 3, 4, 5]
    );
    RAISE EXCEPTION 'active reminder accepted an inactive routine item';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
  UPDATE public.routine_items SET active = true WHERE id = v_item_id;

  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays
  ) VALUES (
    v_user_id,
    'hydration',
    time '06:30',
    ARRAY[2, 1]
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.reminder_rules
    WHERE user_id = v_user_id
      AND category = 'hydration'
      AND local_time = time '06:30'
      AND weekdays = ARRAY[1, 2]::smallint[]
  ) THEN
    RAISE EXCEPTION 'reminder weekdays were not canonicalized';
  END IF;

  BEGIN
    INSERT INTO public.reminder_rules (
      user_id,
      category,
      local_time,
      weekdays
    ) VALUES (
      v_user_id,
      'hydration',
      time '06:30',
      ARRAY[1, 2]
    );
    RAISE EXCEPTION 'duplicate active reminder was accepted';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

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
    WHEN foreign_key_violation OR check_violation THEN NULL;
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
    WHEN foreign_key_violation OR check_violation THEN NULL;
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
    active,
    template_key
  ) VALUES (
    v_user_id,
    'hydration',
    time '21:58',
    ARRAY[0, 1, 2, 3, 4, 5, 6],
    true,
    'bodyflow.hydration.discovery'
  ) RETURNING id INTO v_rule_id;

  SELECT count(*), min(due.scheduled_for)
  INTO v_due_count, v_due_scheduled_for
  FROM public.list_due_reminder_rules(
    timestamptz '2026-07-21 01:01:00+00',
    5,
    100
  ) due
  WHERE due.reminder_rule_id = v_rule_id;

  IF v_due_count <> 1
    OR v_due_scheduled_for <> timestamptz '2026-07-21 00:58:00+00' THEN
    RAISE EXCEPTION 'due reminder discovery did not convert local time safely: count %, instant %',
      v_due_count, v_due_scheduled_for;
  END IF;

  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays,
    active,
    template_key
  ) VALUES (
    v_user_id,
    'hydration',
    time '21:58',
    ARRAY[0, 1, 2, 3, 4, 5, 6],
    true,
    'bodyflow.hydration.page-a'
  )
  RETURNING id INTO v_page_rule_id_a;
  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays,
    active,
    template_key
  ) VALUES (
    v_user_id,
    'hydration',
    time '21:58',
    ARRAY[0, 1, 2, 3, 4, 5, 6],
    true,
    'bodyflow.hydration.page-b'
  )
  RETURNING id INTO v_page_rule_id_b;

  SELECT due.reminder_rule_id, due.scheduled_for
  INTO v_page_cursor_rule_id, v_page_cursor_scheduled_for
  FROM public.list_due_reminder_rules(
    timestamptz '2026-07-21 01:01:00+00',
    5,
    2,
    NULL,
    NULL
  ) due
  ORDER BY due.scheduled_for DESC, due.reminder_rule_id DESC
  LIMIT 1;

  SELECT count(*)
  INTO v_due_count
  FROM (
    SELECT *
    FROM public.list_due_reminder_rules(
      timestamptz '2026-07-21 01:01:00+00',
      5,
      2,
      NULL,
      NULL
    )
    UNION ALL
    SELECT *
    FROM public.list_due_reminder_rules(
      timestamptz '2026-07-21 01:01:00+00',
      5,
      2,
      v_page_cursor_scheduled_for,
      v_page_cursor_rule_id
    )
  ) paged_due;

  IF v_due_count <> 3
    OR v_page_rule_id_b IS NULL THEN
    RAISE EXCEPTION 'due reminder keyset pagination lost or duplicated rows: count %', v_due_count;
  END IF;

  UPDATE public.users
  SET timezone = 'America/New_York'
  WHERE id = v_other_user_id;

  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays
  ) VALUES (
    v_other_user_id,
    'hydration',
    time '01:30',
    ARRAY[0]
  ) RETURNING id INTO v_dst_rule_id;

  SELECT count(*)
  INTO v_dst_due_count
  FROM (
    SELECT *
    FROM public.list_due_reminder_rules(
      timestamptz '2026-11-01 05:32:00+00',
      5,
      100
    )
    UNION ALL
    SELECT *
    FROM public.list_due_reminder_rules(
      timestamptz '2026-11-01 06:32:00+00',
      5,
      100
    )
  ) due
  WHERE due.reminder_rule_id = v_dst_rule_id;

  IF v_dst_due_count <> 1 THEN
    RAISE EXCEPTION 'DST fallback scheduled one local reminder % times', v_dst_due_count;
  END IF;

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

  SELECT
    delivery.coach_message_usage_id,
    delivery.coach_template_version_id,
    delivery.personality,
    delivery.locale
  INTO
    v_delivery_usage_id,
    v_delivery_version_id,
    v_delivery_personality,
    v_delivery_locale
  FROM public.notification_deliveries delivery
  WHERE delivery.reminder_event_id = (v_event_first ->> 'event_id')::uuid
  ORDER BY delivery.id
  LIMIT 1;

  IF v_event_first ->> 'status' <> 'queued'
    OR v_event_retry ->> 'status' <> 'queued'
    OR (v_event_retry ->> 'existing')::boolean IS NOT TRUE
    OR v_delivery_count <> 2
    OR v_delivery_usage_id IS NULL
    OR v_delivery_version_id IS NULL
    OR v_delivery_personality = 'default'
    OR v_delivery_locale <> 'pt-BR'
    OR EXISTS (
      SELECT 1
      FROM public.notification_deliveries delivery
      WHERE delivery.reminder_event_id = (v_event_first ->> 'event_id')::uuid
        AND (
          delivery.coach_message_usage_id IS DISTINCT FROM v_delivery_usage_id
          OR delivery.coach_template_version_id IS DISTINCT FROM v_delivery_version_id
          OR delivery.personality IS DISTINCT FROM v_delivery_personality
          OR delivery.locale IS DISTINCT FROM v_delivery_locale
        )
    )
    OR NOT EXISTS (
      SELECT 1
      FROM public.coach_message_usage usage
      JOIN public.coach_message_templates template ON template.id = usage.template_id
      JOIN public.notification_deliveries delivery
        ON delivery.reminder_event_id = (v_event_first ->> 'event_id')::uuid
        AND delivery.coach_message_usage_id = usage.id
        AND delivery.coach_template_version_id = usage.template_version_id
        AND delivery.template_key = template.template_key
      WHERE usage.id = v_delivery_usage_id
        AND usage.user_id = v_user_id
        AND usage.outcome = 'selected'
        AND usage.channel = 'push'
        AND usage.effective_personality = v_delivery_personality
        AND usage.locale = v_delivery_locale
    ) THEN
    RAISE EXCEPTION 'queued reminder did not share one immutable catalog claim across devices: first %, retry %, deliveries %',
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

  UPDATE public.notification_preferences
  SET routine_preview_mode = 'name_and_dose'
  WHERE user_id = v_user_id;

  INSERT INTO public.routine_items (
    user_id,
    item_type,
    name,
    dose_text,
    active,
    reminders_enabled
  ) VALUES (
    v_user_id,
    'medication',
    'Private exact medication',
    '91 mg private',
    true,
    true
  ) RETURNING id INTO v_exact_item_id;

  INSERT INTO public.reminder_rules (
    user_id,
    routine_item_id,
    category,
    local_time,
    weekdays
  ) VALUES
    (
      v_user_id,
      v_exact_item_id,
      'medication',
      time '08:00',
      ARRAY[0, 1, 2, 3, 4, 5, 6]
    ),
    (
      v_user_id,
      v_exact_item_id,
      'medication',
      time '20:00',
      ARRAY[0, 1, 2, 3, 4, 5, 6]
    );

  SELECT id INTO v_routine_rule_id
  FROM public.reminder_rules
  WHERE routine_item_id = v_exact_item_id
    AND local_time = time '08:00';
  SELECT id INTO v_routine_evening_rule_id
  FROM public.reminder_rules
  WHERE routine_item_id = v_exact_item_id
    AND local_time = time '20:00';

  PERFORM public.record_routine_occurrence_action_atomic(
    v_user_id,
    v_exact_item_id,
    'medication',
    v_routine_rule_id,
    timestamptz '2026-07-20 11:00:00+00',
    'taken',
    timestamptz '2026-07-20 11:01:00+00',
    NULL,
    'exact-taken-0800'
  );

  v_event_first := public.claim_reminder_event(
    v_routine_rule_id,
    timestamptz '2026-07-20 11:00:00+00',
    timestamptz '2026-07-20 11:02:00+00'
  );
  v_event_retry := public.claim_reminder_event(
    v_routine_evening_rule_id,
    timestamptz '2026-07-20 23:00:00+00',
    timestamptz '2026-07-20 23:00:00+00'
  );

  IF v_event_first ->> 'status' <> 'resolved'
    OR v_event_retry ->> 'status' <> 'queued'
    OR NOT EXISTS (
      SELECT 1
      FROM public.reminder_events event
      JOIN public.notification_deliveries delivery
        ON delivery.reminder_event_id = event.id
      WHERE event.id = (v_event_retry ->> 'event_id')::uuid
        AND event.reminder_rule_id = v_routine_evening_rule_id
        AND event.routine_occurrence_key = private.derive_routine_occurrence_key(
          v_routine_evening_rule_id,
          timestamptz '2026-07-20 23:00:00+00'
        )
        AND delivery.template_key = 'bodyflow.routine.medication.reminder'
        AND delivery.personality = 'default'
        AND delivery.routine_preview_mode = 'name_and_dose'
        AND delivery.coach_message_usage_id IS NULL
        AND delivery.coach_template_version_id IS NULL
        AND delivery.locale IS NULL
    ) OR EXISTS (
      SELECT 1
      FROM public.reminder_events event
      LEFT JOIN public.notification_deliveries delivery
        ON delivery.reminder_event_id = event.id
      WHERE event.id = (v_event_retry ->> 'event_id')::uuid
        AND (
          to_jsonb(event)::text ILIKE '%Private exact medication%'
          OR to_jsonb(event)::text ILIKE '%91 mg private%'
          OR COALESCE(to_jsonb(delivery)::text, '') ILIKE '%Private exact medication%'
          OR COALESCE(to_jsonb(delivery)::text, '') ILIKE '%91 mg private%'
        )
    ) THEN
    RAISE EXCEPTION 'exact routine claim resolved another schedule or leaked private copy: morning %, evening %',
      v_event_first, v_event_retry;
  END IF;

  INSERT INTO public.routine_items (
    user_id,
    item_type,
    name,
    active,
    reminders_enabled
  ) VALUES (
    v_user_id,
    'supplement',
    'Private snoozed supplement',
    true,
    true
  ) RETURNING id INTO v_snooze_item_id;

  INSERT INTO public.reminder_rules (
    user_id,
    routine_item_id,
    category,
    local_time,
    weekdays
  ) VALUES
    (
      v_user_id,
      v_snooze_item_id,
      'supplement',
      time '08:00',
      ARRAY[0, 1, 2, 3, 4, 5, 6]
    ),
    (
      v_user_id,
      v_snooze_item_id,
      'supplement',
      time '20:00',
      ARRAY[0, 1, 2, 3, 4, 5, 6]
    );

  SELECT id INTO v_snooze_rule_id
  FROM public.reminder_rules
  WHERE routine_item_id = v_snooze_item_id
    AND local_time = time '08:00';
  SELECT id INTO v_snooze_evening_rule_id
  FROM public.reminder_rules
  WHERE routine_item_id = v_snooze_item_id
    AND local_time = time '20:00';

  PERFORM public.record_routine_occurrence_action_atomic(
    v_user_id,
    v_snooze_item_id,
    'supplement',
    v_snooze_rule_id,
    timestamptz '2026-07-20 11:00:00+00',
    'snoozed',
    timestamptz '2026-07-20 11:01:00+00',
    timestamptz '2026-07-20 11:15:00+00',
    'exact-snooze-08'
  );

  v_event_first := public.claim_reminder_event(
    v_snooze_rule_id,
    timestamptz '2026-07-20 11:00:00+00',
    timestamptz '2026-07-20 11:02:00+00'
  );
  v_event_retry := public.claim_reminder_event(
    v_snooze_evening_rule_id,
    timestamptz '2026-07-20 23:00:00+00',
    timestamptz '2026-07-20 23:00:00+00'
  );

  IF v_event_first ->> 'status' <> 'suppressed'
    OR v_event_first ->> 'suppression_reason' <> 'snoozed'
    OR v_event_retry ->> 'status' <> 'queued' THEN
    RAISE EXCEPTION 'snooze did not suppress only its original occurrence: morning %, evening %',
      v_event_first, v_event_retry;
  END IF;

  UPDATE public.routine_items
  SET reminders_enabled = false
  WHERE id = v_exact_item_id;

  v_event_first := public.claim_reminder_event(
    v_routine_rule_id,
    timestamptz '2026-07-21 11:00:00+00',
    timestamptz '2026-07-21 11:00:00+00'
  );

  IF v_event_first ->> 'status' <> 'suppressed'
    OR v_event_first ->> 'suppression_reason' <> 'routine_reminders_disabled' THEN
    RAISE EXCEPTION 'disabled routine item still queued an exact reminder: %', v_event_first;
  END IF;

  INSERT INTO public.routine_items (user_id, item_type, name, active)
  VALUES (v_user_id, 'medication', 'Synthetic medication', true)
  RETURNING id INTO v_inactive_item_id;
  INSERT INTO public.reminder_rules (
    user_id,
    routine_item_id,
    category,
    local_time,
    weekdays
  ) VALUES (
    v_user_id,
    v_inactive_item_id,
    'medication',
    time '19:00',
    ARRAY[0, 1, 2, 3, 4, 5, 6]
  ) RETURNING id INTO v_inactive_rule_id;
  UPDATE public.routine_items SET active = false WHERE id = v_inactive_item_id;

  v_event_first := public.claim_reminder_event(
    v_inactive_rule_id,
    timestamptz '2026-07-20 22:00:00+00',
    timestamptz '2026-07-20 22:00:00+00'
  );
  IF v_event_first ->> 'status' <> 'suppressed'
    OR v_event_first ->> 'suppression_reason' <> 'routine_item_inactive' THEN
    RAISE EXCEPTION 'inactive routine item still queued a reminder: %', v_event_first;
  END IF;

  INSERT INTO public.reminder_rules (
    user_id,
    category,
    local_time,
    weekdays,
    template_key
  ) VALUES (
    v_history_new_user_id,
    'hydration',
    time '14:00',
    ARRAY[0, 1, 2, 3, 4, 5, 6],
    'bodyflow.hydration.stale-test'
  ) RETURNING id INTO v_stale_rule_id;

  v_event_first := public.claim_reminder_event(
    v_stale_rule_id,
    timestamptz '2026-07-20 17:00:00+00',
    timestamptz '2026-07-20 18:00:00+00'
  );
  v_event_retry := public.claim_reminder_event(
    v_stale_rule_id,
    timestamptz '2026-07-20 17:00:00+00',
    timestamptz '2026-07-20 18:01:00+00'
  );

  IF v_event_first ->> 'status' <> 'suppressed'
    OR v_event_first ->> 'suppression_reason' <> 'stale'
    OR (v_event_first ->> 'existing')::boolean
    OR (v_event_retry ->> 'existing')::boolean IS NOT TRUE
    OR (v_event_retry ->> 'event_id') <> (v_event_first ->> 'event_id')
    OR EXISTS (
      SELECT 1
      FROM public.notification_deliveries
      WHERE reminder_event_id = (v_event_first ->> 'event_id')::uuid
    ) OR EXISTS (
      SELECT 1
      FROM public.notification_preferences
      WHERE user_id = v_history_new_user_id
    ) THEN
    RAISE EXCEPTION 'stale reminder was not audited without side effects: first %, retry %',
      v_event_first, v_event_retry;
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

  IF v_safe_device_count <> 3
    OR v_cross_device_count <> 0
    OR NOT v_token_denied THEN
    RAISE EXCEPTION 'RLS or APNs column protections failed: own %, cross %, token denied %',
      v_safe_device_count, v_cross_device_count, v_token_denied;
  END IF;
END;
$test$;

ROLLBACK;
