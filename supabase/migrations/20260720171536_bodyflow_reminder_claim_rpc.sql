CREATE OR REPLACE FUNCTION public.claim_reminder_event(
  p_reminder_rule_id uuid,
  p_scheduled_for timestamptz,
  p_claimed_at timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_rule record;
  v_preferences record;
  v_timezone text;
  v_local_timestamp timestamp;
  v_claim_local_timestamp timestamp;
  v_event_id uuid;
  v_status text := 'queued';
  v_reason text;
  v_events_today integer;
  v_water_ml integer;
  v_next_reevaluation date;
  v_delivery_count integer := 0;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_reminder_rule_id IS NULL OR p_scheduled_for IS NULL OR p_claimed_at IS NULL THEN
    RAISE EXCEPTION 'reminder rule and timestamps are required' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_rule
  FROM public.reminder_rules
  WHERE id = p_reminder_rule_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reminder rule is missing' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      v_rule.id::text || ':reminder-event:' || p_scheduled_for::text,
      0
    )
  );

  SELECT id, status, suppression_reason
  INTO v_event_id, v_status, v_reason
  FROM public.reminder_events
  WHERE reminder_rule_id = v_rule.id
    AND scheduled_for = p_scheduled_for;

  IF FOUND THEN
    SELECT count(*)
    INTO v_delivery_count
    FROM public.notification_deliveries
    WHERE reminder_event_id = v_event_id;

    RETURN jsonb_build_object(
      'event_id', v_event_id,
      'status', v_status,
      'suppression_reason', v_reason,
      'delivery_count', v_delivery_count,
      'existing', true
    );
  END IF;

  IF NOT v_rule.active THEN
    RAISE EXCEPTION 'reminder rule is inactive' USING ERRCODE = '22023';
  END IF;

  SELECT timezone
  INTO v_timezone
  FROM public.users
  WHERE id = v_rule.user_id
    AND status = 'active';

  IF v_timezone IS NULL THEN
    RAISE EXCEPTION 'active reminder user timezone is required' USING ERRCODE = '22023';
  END IF;

  v_local_timestamp := timezone(v_timezone, p_scheduled_for);
  v_claim_local_timestamp := timezone(v_timezone, p_claimed_at);
  IF extract(dow FROM v_local_timestamp)::smallint <> ALL(v_rule.weekdays)
    OR to_char(v_local_timestamp, 'HH24:MI') <> to_char(v_rule.local_time, 'HH24:MI')
    OR p_scheduled_for > p_claimed_at + interval '5 minutes'
    OR p_scheduled_for < p_claimed_at - interval '15 minutes' THEN
    RAISE EXCEPTION 'scheduled reminder does not match its active rule'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      v_rule.user_id::text || ':reminders:' || v_local_timestamp::date::text,
      0
    )
  );

  v_status := 'queued';
  v_reason := NULL;

  INSERT INTO public.notification_preferences (user_id)
  VALUES (v_rule.user_id)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT *
  INTO v_preferences
  FROM public.notification_preferences
  WHERE user_id = v_rule.user_id
  FOR UPDATE;

  IF NOT v_preferences.push_enabled THEN
    v_status := 'suppressed';
    v_reason := 'push_disabled';
  ELSIF NOT EXISTS (
    SELECT 1
    FROM public.mobile_devices
    WHERE user_id = v_rule.user_id
      AND active
  ) THEN
    v_status := 'suppressed';
    v_reason := 'no_active_device';
  ELSIF v_preferences.quiet_hours_start IS NOT NULL AND (
    (
      v_preferences.quiet_hours_start < v_preferences.quiet_hours_end
      AND v_claim_local_timestamp::time >= v_preferences.quiet_hours_start
      AND v_claim_local_timestamp::time < v_preferences.quiet_hours_end
    ) OR (
      v_preferences.quiet_hours_start > v_preferences.quiet_hours_end
      AND (
        v_claim_local_timestamp::time >= v_preferences.quiet_hours_start
        OR v_claim_local_timestamp::time < v_preferences.quiet_hours_end
      )
    )
  ) THEN
    v_status := 'suppressed';
    v_reason := 'quiet_hours';
  ELSE
    SELECT count(*)
    INTO v_events_today
    FROM public.reminder_events event
    WHERE event.user_id = v_rule.user_id
      AND event.status = 'queued'
      AND (event.scheduled_for AT TIME ZONE v_timezone)::date = v_local_timestamp::date;

    IF v_events_today >= v_preferences.daily_push_limit THEN
      v_status := 'suppressed';
      v_reason := 'daily_limit';
    ELSIF v_rule.category = 'hydration' THEN
      SELECT water_consumed_ml
      INTO v_water_ml
      FROM public.daily_snapshots
      WHERE user_id = v_rule.user_id
        AND date = v_local_timestamp::date;

      IF v_preferences.hydration_target_ml IS NULL OR v_water_ml IS NULL THEN
        v_status := 'suppressed';
        v_reason := 'missing_official_context';
      ELSIF v_water_ml >= v_preferences.hydration_target_ml THEN
        v_status := 'resolved';
      END IF;
    ELSIF v_rule.category = 'meal' THEN
      IF EXISTS (
        SELECT 1
        FROM public.meal_logs meal
        WHERE meal.user_id = v_rule.user_id
          AND meal.meal_type::text = v_rule.meal_type
          AND (meal.consumed_at AT TIME ZONE v_timezone)::date = v_local_timestamp::date
      ) OR EXISTS (
        SELECT 1
        FROM public.product_events event
        WHERE event.user_id = v_rule.user_id
          AND event.event = 'meal.user_skipped'
          AND event.properties ->> 'meal_type' = v_rule.meal_type
          AND event.properties ->> 'local_date' = v_local_timestamp::date::text
      ) THEN
        v_status := 'resolved';
      END IF;
    ELSIF v_rule.category IN ('supplement', 'medication') THEN
      IF NOT EXISTS (
        SELECT 1
        FROM public.routine_items item
        WHERE item.id = v_rule.routine_item_id
          AND item.user_id = v_rule.user_id
          AND item.item_type = v_rule.category
          AND item.active
      ) THEN
        v_status := 'suppressed';
        v_reason := 'routine_item_inactive';
      ELSIF EXISTS (
        SELECT 1
        FROM public.routine_adherence_logs adherence
        WHERE adherence.user_id = v_rule.user_id
          AND adherence.routine_item_id = v_rule.routine_item_id
          AND adherence.status IN ('taken', 'skipped')
          AND (adherence.occurred_at AT TIME ZONE v_timezone)::date = v_local_timestamp::date
      ) THEN
        v_status := 'resolved';
      ELSIF EXISTS (
        SELECT 1
        FROM public.routine_adherence_logs adherence
        WHERE adherence.user_id = v_rule.user_id
          AND adherence.routine_item_id = v_rule.routine_item_id
          AND adherence.status = 'snoozed'
          AND adherence.snoozed_until > p_claimed_at
      ) THEN
        v_status := 'suppressed';
        v_reason := 'snoozed';
      END IF;
    ELSIF v_rule.category = 'workout' THEN
      IF EXISTS (
        SELECT 1
        FROM public.workout_logs workout
        WHERE workout.user_id = v_rule.user_id
          AND (workout.performed_at AT TIME ZONE v_timezone)::date = v_local_timestamp::date
      ) THEN
        v_status := 'resolved';
      END IF;
    ELSIF v_rule.category = 'reevaluation' THEN
      SELECT next_reevaluation
      INTO v_next_reevaluation
      FROM public.user_progress
      WHERE user_id = v_rule.user_id;

      IF v_next_reevaluation IS NULL THEN
        v_status := 'suppressed';
        v_reason := 'missing_official_context';
      ELSIF v_next_reevaluation > v_local_timestamp::date THEN
        v_status := 'resolved';
      END IF;
    ELSE
      v_status := 'suppressed';
      v_reason := 'missing_official_context';
    END IF;
  END IF;

  INSERT INTO public.reminder_events (
    user_id,
    reminder_rule_id,
    scheduled_for,
    status,
    suppression_reason,
    resolved_at
  ) VALUES (
    v_rule.user_id,
    v_rule.id,
    p_scheduled_for,
    v_status,
    v_reason,
    CASE WHEN v_status = 'resolved' THEN p_claimed_at ELSE NULL END
  )
  RETURNING id INTO v_event_id;

  IF v_status = 'queued' THEN
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
    )
    SELECT
      v_rule.user_id,
      v_event_id,
      device.id,
      'push',
      'apns',
      COALESCE(v_rule.template_key, 'bodyflow.' || v_rule.category || '.reminder'),
      'default',
      'queued',
      p_scheduled_for
    FROM public.mobile_devices device
    WHERE device.user_id = v_rule.user_id
      AND device.active;

    GET DIAGNOSTICS v_delivery_count = ROW_COUNT;
    IF v_delivery_count = 0 THEN
      UPDATE public.reminder_events
      SET status = 'suppressed',
          suppression_reason = 'no_active_device',
          updated_at = clock_timestamp()
      WHERE id = v_event_id;
      v_status := 'suppressed';
      v_reason := 'no_active_device';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'event_id', v_event_id,
    'status', v_status,
    'suppression_reason', v_reason,
    'delivery_count', v_delivery_count,
    'existing', false
  );
END;
$$;
