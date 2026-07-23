CREATE OR REPLACE FUNCTION private.derive_routine_occurrence_state(
  p_user_id uuid,
  p_routine_item_id uuid,
  p_item_type text,
  p_occurrence_key text,
  p_scheduled_for timestamptz,
  p_as_of timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_timezone text;
  v_occurrence_day_end timestamptz;
  v_status text;
  v_last_action_at timestamptz;
  v_snoozed_until timestamptz;
BEGIN
  IF p_user_id IS NULL
    OR p_routine_item_id IS NULL
    OR p_item_type IS NULL
    OR p_item_type NOT IN ('supplement', 'medication')
    OR p_occurrence_key IS NULL
    OR p_occurrence_key !~ '^[0-9a-f]{64}$'
    OR p_scheduled_for IS NULL
    OR p_as_of IS NULL THEN
    RAISE EXCEPTION 'invalid_routine_occurrence_state' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.routine_items item
    WHERE item.id = p_routine_item_id
      AND item.user_id = p_user_id
      AND item.item_type = p_item_type
  ) THEN
    RAISE EXCEPTION 'routine_item_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_timezone := private.routine_user_timezone(p_user_id);
  v_occurrence_day_end := (
    (timezone(v_timezone, p_scheduled_for)::date + 1)::timestamp
    AT TIME ZONE v_timezone
  );

  SELECT
    action.status,
    action.occurred_at,
    action.snoozed_until
  INTO
    v_status,
    v_last_action_at,
    v_snoozed_until
  FROM public.routine_adherence_logs action
  WHERE action.user_id = p_user_id
    AND action.routine_item_id = p_routine_item_id
    AND action.item_type = p_item_type
    AND action.occurrence_key = p_occurrence_key
  ORDER BY action.occurred_at DESC, action.created_at DESC, action.id DESC
  LIMIT 1;

  IF NOT FOUND
    OR (v_status = 'snoozed' AND p_as_of >= v_occurrence_day_end) THEN
    v_status := CASE
      WHEN p_as_of >= v_occurrence_day_end THEN 'missed'
      ELSE 'pending'
    END;

    IF v_status = 'missed' THEN
      v_last_action_at := v_occurrence_day_end;
      v_snoozed_until := NULL;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'status', v_status,
    'last_action_at', v_last_action_at,
    'snoozed_until', v_snoozed_until
  );
END;
$$;

CREATE OR REPLACE FUNCTION private.claim_routine_notification_event(
  p_reminder_rule_id uuid,
  p_original_scheduled_for timestamptz,
  p_event_scheduled_for timestamptz,
  p_claimed_at timestamptz,
  p_routine_action_log_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_rule public.reminder_rules%ROWTYPE;
  v_item public.routine_items%ROWTYPE;
  v_action public.routine_adherence_logs%ROWTYPE;
  v_latest_action_id uuid;
  v_preferences public.notification_preferences%ROWTYPE;
  v_timezone text;
  v_locale text;
  v_local_timestamp timestamp;
  v_claim_local_timestamp timestamp;
  v_occurrence_key text;
  v_occurrence_state jsonb;
  v_event_id uuid;
  v_status text := 'queued';
  v_reason text;
  v_events_today integer;
  v_delivery_count integer := 0;
  v_template_key text;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_reminder_rule_id IS NULL
    OR p_original_scheduled_for IS NULL
    OR p_event_scheduled_for IS NULL
    OR p_claimed_at IS NULL
    OR NOT isfinite(p_original_scheduled_for)
    OR NOT isfinite(p_event_scheduled_for)
    OR NOT isfinite(p_claimed_at) THEN
    RAISE EXCEPTION 'invalid routine reminder claim payload' USING ERRCODE = '22023';
  END IF;

  SELECT rule.*
  INTO v_rule
  FROM public.reminder_rules rule
  WHERE rule.id = p_reminder_rule_id
    AND rule.category IN ('supplement', 'medication')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reminder rule is missing' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      v_rule.id::text || ':routine-reminder:' || p_event_scheduled_for::text,
      0
    )
  );

  IF p_routine_action_log_id IS NULL THEN
    SELECT event.id, event.status, event.suppression_reason
    INTO v_event_id, v_status, v_reason
    FROM public.reminder_events event
    WHERE event.reminder_rule_id = v_rule.id
      AND event.scheduled_for = p_event_scheduled_for;
  ELSE
    SELECT event.id, event.status, event.suppression_reason
    INTO v_event_id, v_status, v_reason
    FROM public.reminder_events event
    WHERE event.routine_action_log_id = p_routine_action_log_id
      OR (
        event.reminder_rule_id = v_rule.id
        AND event.scheduled_for = p_event_scheduled_for
      )
    ORDER BY (event.routine_action_log_id = p_routine_action_log_id) DESC
    LIMIT 1;
  END IF;

  IF FOUND THEN
    SELECT count(*)
    INTO v_delivery_count
    FROM public.notification_deliveries delivery
    WHERE delivery.reminder_event_id = v_event_id;

    RETURN jsonb_build_object(
      'event_id', v_event_id,
      'status', v_status,
      'suppression_reason', v_reason,
      'delivery_count', v_delivery_count,
      'existing', true
    );
  END IF;

  v_status := 'queued';
  v_reason := NULL;

  SELECT item.*
  INTO v_item
  FROM public.routine_items item
  WHERE item.id = v_rule.routine_item_id
    AND item.user_id = v_rule.user_id
    AND item.item_type = v_rule.category
  FOR KEY SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'routine item is missing' USING ERRCODE = '22023';
  END IF;

  SELECT domain_user.timezone, COALESCE(NULLIF(domain_user.locale, ''), 'pt-BR')
  INTO v_timezone, v_locale
  FROM public.users domain_user
  WHERE domain_user.id = v_rule.user_id
    AND domain_user.status = 'active';

  IF v_timezone IS NULL THEN
    RAISE EXCEPTION 'active reminder user timezone is required' USING ERRCODE = '22023';
  END IF;

  v_local_timestamp := timezone(v_timezone, p_original_scheduled_for);
  v_claim_local_timestamp := timezone(v_timezone, p_claimed_at);

  IF (v_local_timestamp AT TIME ZONE v_timezone) IS DISTINCT FROM p_original_scheduled_for
    OR extract(dow FROM v_local_timestamp)::smallint <> ALL(v_rule.weekdays)
    OR v_local_timestamp::time IS DISTINCT FROM v_rule.local_time
    OR p_event_scheduled_for > p_claimed_at + interval '5 minutes' THEN
    RAISE EXCEPTION 'scheduled reminder does not match its exact routine occurrence'
      USING ERRCODE = '22023';
  END IF;

  v_occurrence_key := private.derive_routine_occurrence_key(
    v_rule.id,
    p_original_scheduled_for
  );
  PERFORM private.lock_routine_occurrence(v_rule.user_id, v_occurrence_key);

  IF p_routine_action_log_id IS NOT NULL THEN
    SELECT action.*
    INTO v_action
    FROM public.routine_adherence_logs action
    WHERE action.id = p_routine_action_log_id
      AND action.user_id = v_rule.user_id
      AND action.routine_item_id = v_rule.routine_item_id
      AND action.item_type = v_rule.category
      AND action.reminder_rule_id = v_rule.id
      AND action.occurrence_key = v_occurrence_key
      AND action.scheduled_for = p_original_scheduled_for
      AND action.status = 'snoozed'
      AND action.snoozed_until = p_event_scheduled_for;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'routine snooze action is missing' USING ERRCODE = '22023';
    END IF;

    SELECT action.id
    INTO v_latest_action_id
    FROM public.routine_adherence_logs action
    WHERE action.user_id = v_rule.user_id
      AND action.routine_item_id = v_rule.routine_item_id
      AND action.item_type = v_rule.category
      AND action.occurrence_key = v_occurrence_key
    ORDER BY action.occurred_at DESC, action.created_at DESC, action.id DESC
    LIMIT 1;
  END IF;

  v_occurrence_state := private.derive_routine_occurrence_state(
    v_rule.user_id,
    v_rule.routine_item_id,
    v_rule.category,
    v_occurrence_key,
    p_original_scheduled_for,
    p_claimed_at
  );

  IF NOT v_rule.active OR v_rule.deactivated_at IS NOT NULL THEN
    v_status := 'suppressed';
    v_reason := 'routine_rule_inactive';
  ELSIF NOT v_item.active OR v_item.archived_at IS NOT NULL THEN
    v_status := 'suppressed';
    v_reason := 'routine_item_inactive';
  ELSIF NOT v_item.reminders_enabled THEN
    v_status := 'suppressed';
    v_reason := 'routine_reminders_disabled';
  ELSIF p_event_scheduled_for < p_claimed_at - interval '15 minutes' THEN
    v_status := 'suppressed';
    v_reason := 'stale';
  ELSIF p_routine_action_log_id IS NULL
    AND v_occurrence_state ->> 'status' = 'snoozed' THEN
    v_status := 'suppressed';
    v_reason := 'snoozed';
  ELSIF p_routine_action_log_id IS NULL
    AND v_occurrence_state ->> 'status' <> 'pending' THEN
    v_status := 'resolved';
  ELSIF p_routine_action_log_id IS NOT NULL
    AND (
      v_latest_action_id IS DISTINCT FROM p_routine_action_log_id
      OR v_occurrence_state ->> 'status' <> 'snoozed'
    ) THEN
    v_status := 'resolved';
  END IF;

  IF v_status = 'queued' THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended(
        v_rule.user_id::text || ':reminders:' || v_claim_local_timestamp::date::text,
        0
      )
    );

    INSERT INTO public.notification_preferences (user_id)
    VALUES (v_rule.user_id)
    ON CONFLICT (user_id) DO NOTHING;

    SELECT preferences.*
    INTO v_preferences
    FROM public.notification_preferences preferences
    WHERE preferences.user_id = v_rule.user_id
    FOR UPDATE;

    IF NOT v_preferences.push_enabled THEN
      v_status := 'suppressed';
      v_reason := 'push_disabled';
    ELSIF NOT EXISTS (
      SELECT 1
      FROM public.mobile_devices device
      WHERE device.user_id = v_rule.user_id
        AND device.active
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
        AND (event.scheduled_for AT TIME ZONE v_timezone)::date
          = (p_event_scheduled_for AT TIME ZONE v_timezone)::date;

      IF v_events_today >= v_preferences.daily_push_limit THEN
        v_status := 'suppressed';
        v_reason := 'daily_limit';
      END IF;
    END IF;
  END IF;

  IF v_status = 'queued' AND v_locale NOT IN ('pt-BR', 'en-US') THEN
    v_status := 'suppressed';
    v_reason := 'unsupported_locale';
  END IF;

  IF v_status = 'queued' THEN
    PERFORM 1
    FROM public.mobile_devices device
    WHERE device.user_id = v_rule.user_id
      AND device.active
    FOR SHARE;

    IF NOT FOUND THEN
      v_status := 'suppressed';
      v_reason := 'no_active_device';
    END IF;
  END IF;

  INSERT INTO public.reminder_events (
    user_id,
    reminder_rule_id,
    scheduled_for,
    status,
    suppression_reason,
    resolved_at,
    routine_occurrence_key,
    routine_action_log_id
  ) VALUES (
    v_rule.user_id,
    v_rule.id,
    p_event_scheduled_for,
    v_status,
    v_reason,
    CASE WHEN v_status = 'resolved' THEN p_claimed_at ELSE NULL END,
    v_occurrence_key,
    p_routine_action_log_id
  )
  RETURNING id INTO v_event_id;

  IF v_status = 'queued' THEN
    v_template_key := concat(
      'bodyflow.routine.',
      v_rule.category,
      CASE
        WHEN p_routine_action_log_id IS NULL THEN '.reminder'
        ELSE '.snooze'
      END
    );

    INSERT INTO public.notification_deliveries (
      user_id,
      reminder_event_id,
      mobile_device_id,
      channel,
      provider,
      template_key,
      personality,
      status,
      scheduled_for,
      routine_preview_mode
    )
    SELECT
      v_rule.user_id,
      v_event_id,
      device.id,
      'push',
      'apns',
      v_template_key,
      'default',
      'queued',
      p_event_scheduled_for,
      v_preferences.routine_preview_mode
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

ALTER FUNCTION public.claim_reminder_event(uuid, timestamptz, timestamptz)
  SET SCHEMA private;
ALTER FUNCTION private.claim_reminder_event(uuid, timestamptz, timestamptz)
  RENAME TO claim_nonroutine_reminder_event;

REVOKE ALL ON FUNCTION private.claim_nonroutine_reminder_event(
  uuid,
  timestamptz,
  timestamptz
) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.claim_reminder_event(
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
  v_category text;
BEGIN
  PERFORM private.assert_trusted_backend();

  SELECT rule.category
  INTO v_category
  FROM public.reminder_rules rule
  WHERE rule.id = p_reminder_rule_id;

  IF v_category IN ('supplement', 'medication') THEN
    RETURN private.claim_routine_notification_event(
      p_reminder_rule_id,
      p_scheduled_for,
      p_scheduled_for,
      p_claimed_at,
      NULL
    );
  END IF;

  RETURN private.claim_nonroutine_reminder_event(
    p_reminder_rule_id,
    p_scheduled_for,
    p_claimed_at
  );
END;
$$;

CREATE FUNCTION public.list_due_routine_snoozes(
  p_fired_at timestamptz,
  p_lookback_minutes integer,
  p_limit integer,
  p_after_snoozed_until timestamptz DEFAULT NULL,
  p_after_log_id uuid DEFAULT NULL
)
RETURNS TABLE (
  adherence_log_id uuid,
  snoozed_until timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_fired_at IS NULL
    OR NOT isfinite(p_fired_at)
    OR p_lookback_minutes IS NULL
    OR p_lookback_minutes NOT BETWEEN 0 AND 15
    OR p_limit IS NULL
    OR p_limit NOT BETWEEN 1 AND 5000
    OR (p_after_snoozed_until IS NULL) <> (p_after_log_id IS NULL)
    OR (
      p_after_snoozed_until IS NOT NULL
      AND NOT isfinite(p_after_snoozed_until)
    ) THEN
    RAISE EXCEPTION 'invalid due routine snooze lookup payload'
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH lookup_window AS (
    SELECT
      date_trunc('minute', p_fired_at) - make_interval(mins => p_lookback_minutes)
        AS starts_at,
      date_trunc('minute', p_fired_at) AS ends_at
  ),
  latest_actions AS (
    SELECT DISTINCT ON (action.user_id, action.occurrence_key)
      action.id,
      action.user_id,
      action.routine_item_id,
      action.item_type,
      action.reminder_rule_id,
      action.occurrence_key,
      action.scheduled_for,
      action.snoozed_until,
      action.status
    FROM public.routine_adherence_logs action
    WHERE action.occurrence_key IS NOT NULL
    ORDER BY
      action.user_id,
      action.occurrence_key,
      action.occurred_at DESC,
      action.created_at DESC,
      action.id DESC
  ),
  eligible AS (
    SELECT
      action.id AS adherence_log_id,
      action.snoozed_until,
      private.derive_routine_occurrence_state(
        action.user_id,
        action.routine_item_id,
        action.item_type,
        action.occurrence_key,
        action.scheduled_for,
        p_fired_at
      ) AS occurrence_state
    FROM latest_actions action
    JOIN public.routine_items item
      ON item.id = action.routine_item_id
      AND item.user_id = action.user_id
      AND item.item_type = action.item_type
      AND item.active
      AND item.archived_at IS NULL
      AND item.reminders_enabled
    JOIN public.reminder_rules rule
      ON rule.id = action.reminder_rule_id
      AND rule.user_id = action.user_id
      AND rule.routine_item_id = action.routine_item_id
      AND rule.category = action.item_type
      AND rule.active
      AND rule.deactivated_at IS NULL
    WHERE action.status = 'snoozed'
      AND action.snoozed_until IS NOT NULL
  )
  SELECT candidate.adherence_log_id, candidate.snoozed_until
  FROM eligible candidate
  CROSS JOIN lookup_window lookup
  WHERE candidate.occurrence_state ->> 'status' = 'snoozed'
    AND candidate.snoozed_until BETWEEN lookup.starts_at AND lookup.ends_at
    AND (
      p_after_snoozed_until IS NULL
      OR (candidate.snoozed_until, candidate.adherence_log_id)
        > (p_after_snoozed_until, p_after_log_id)
    )
  ORDER BY candidate.snoozed_until, candidate.adherence_log_id
  LIMIT p_limit;
END;
$$;

CREATE FUNCTION public.claim_routine_snooze_event(
  p_adherence_log_id uuid,
  p_claimed_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_action public.routine_adherence_logs%ROWTYPE;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_adherence_log_id IS NULL
    OR p_claimed_at IS NULL
    OR NOT isfinite(p_claimed_at) THEN
    RAISE EXCEPTION 'invalid routine snooze claim payload' USING ERRCODE = '22023';
  END IF;

  SELECT action.*
  INTO v_action
  FROM public.routine_adherence_logs action
  WHERE action.id = p_adherence_log_id
    AND action.status = 'snoozed'
    AND action.reminder_rule_id IS NOT NULL
    AND action.occurrence_key IS NOT NULL
    AND action.scheduled_for IS NOT NULL
    AND action.snoozed_until IS NOT NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'routine snooze action is missing' USING ERRCODE = '22023';
  END IF;

  RETURN private.claim_routine_notification_event(
    v_action.reminder_rule_id,
    v_action.scheduled_for,
    v_action.snoozed_until,
    p_claimed_at,
    v_action.id
  );
END;
$$;

CREATE FUNCTION public.finalize_due_routine_occurrences(
  p_now timestamptz,
  p_limit integer,
  p_after_scheduled_for timestamptz DEFAULT NULL,
  p_after_user_id uuid DEFAULT NULL,
  p_after_rule_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_candidate record;
  v_occurrence_state jsonb;
  v_seen_count integer := 0;
  v_processed_count integer := 0;
  v_finalized_count integer := 0;
  v_inserted_count integer := 0;
  v_has_more boolean := false;
  v_last_scheduled_for timestamptz;
  v_last_user_id uuid;
  v_last_rule_id uuid;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_now IS NULL
    OR NOT isfinite(p_now)
    OR p_limit IS NULL
    OR p_limit NOT BETWEEN 1 AND 5000
    OR (
      num_nonnulls(
        p_after_scheduled_for,
        p_after_user_id,
        p_after_rule_id
      ) NOT IN (0, 3)
    )
    OR (
      p_after_scheduled_for IS NOT NULL
      AND NOT isfinite(p_after_scheduled_for)
    ) THEN
    RAISE EXCEPTION 'invalid routine finalizer payload' USING ERRCODE = '22023';
  END IF;

  FOR v_candidate IN
    WITH rule_bounds AS (
      SELECT
        rule.id AS rule_id,
        rule.user_id,
        rule.routine_item_id,
        rule.category AS item_type,
        rule.local_time,
        rule.weekdays,
        timezone_name.name AS timezone_name,
        -- Do not synthesize exact occurrences for pre-Task-7 legacy history.
        greatest(
          rule.created_at,
          item.created_at,
          timestamptz '2026-07-23 13:13:21+00'
        ) AS starts_at,
        least(
          p_now,
          COALESCE(rule.deactivated_at, p_now),
          COALESCE(item.archived_at, p_now)
        ) AS ends_at
      FROM public.reminder_rules rule
      JOIN public.routine_items item
        ON item.id = rule.routine_item_id
        AND item.user_id = rule.user_id
        AND item.item_type = rule.category
      JOIN public.users domain_user
        ON domain_user.id = rule.user_id
        AND domain_user.status = 'active'
        AND domain_user.timezone IS NOT NULL
      JOIN pg_catalog.pg_timezone_names timezone_name
        ON timezone_name.name = domain_user.timezone
      WHERE rule.category IN ('supplement', 'medication')
    ),
    local_days AS (
      SELECT
        bound.*,
        series.local_day::date AS local_date
      FROM rule_bounds bound
      CROSS JOIN LATERAL generate_series(
        timezone(bound.timezone_name, bound.starts_at)::date::timestamp,
        timezone(bound.timezone_name, bound.ends_at)::date::timestamp,
        interval '1 day'
      ) series(local_day)
      WHERE bound.starts_at < bound.ends_at
    ),
    instants AS (
      SELECT
        day.rule_id,
        day.user_id,
        day.routine_item_id,
        day.item_type,
        day.timezone_name,
        day.local_date,
        day.local_time,
        day.starts_at,
        day.ends_at,
        (day.local_date + day.local_time) AT TIME ZONE day.timezone_name
          AS scheduled_for,
        ((day.local_date + 1)::timestamp AT TIME ZONE day.timezone_name)
          AS occurrence_day_end
      FROM local_days day
      WHERE extract(dow FROM day.local_date)::smallint = ANY(day.weekdays)
    ),
    canonical AS (
      SELECT
        occurrence.*,
        private.derive_routine_occurrence_key(
          occurrence.rule_id,
          occurrence.scheduled_for
        ) AS occurrence_key
      FROM instants occurrence
      WHERE occurrence.scheduled_for >= occurrence.starts_at
        AND occurrence.scheduled_for < occurrence.ends_at
        AND occurrence.occurrence_day_end <= p_now
        AND timezone(
          occurrence.timezone_name,
          occurrence.scheduled_for
        )::date = occurrence.local_date
        AND timezone(
          occurrence.timezone_name,
          occurrence.scheduled_for
        )::time = occurrence.local_time
    ),
    unresolved AS (
      SELECT occurrence.*
      FROM canonical occurrence
      WHERE private.derive_routine_occurrence_state(
        occurrence.user_id,
        occurrence.routine_item_id,
        occurrence.item_type,
        occurrence.occurrence_key,
        occurrence.scheduled_for,
        p_now
      ) ->> 'status' = 'missed'
        AND NOT EXISTS (
          SELECT 1
          FROM public.routine_adherence_logs missed
          WHERE missed.user_id = occurrence.user_id
            AND missed.occurrence_key = occurrence.occurrence_key
            AND missed.status = 'missed'
            AND missed.source = 'system'
        )
        AND (
          p_after_scheduled_for IS NULL
          OR (
            occurrence.scheduled_for,
            occurrence.user_id,
            occurrence.rule_id
          ) > (
            p_after_scheduled_for,
            p_after_user_id,
            p_after_rule_id
          )
        )
      ORDER BY occurrence.scheduled_for, occurrence.user_id, occurrence.rule_id
      LIMIT (p_limit + 1)
    )
    SELECT *
    FROM unresolved
    ORDER BY scheduled_for, user_id, rule_id
  LOOP
    v_seen_count := v_seen_count + 1;

    IF v_seen_count > p_limit THEN
      v_has_more := true;
      EXIT;
    END IF;

    v_processed_count := v_processed_count + 1;
    v_last_scheduled_for := v_candidate.scheduled_for;
    v_last_user_id := v_candidate.user_id;
    v_last_rule_id := v_candidate.rule_id;

    PERFORM private.lock_routine_occurrence(
      v_candidate.user_id,
      v_candidate.occurrence_key
    );

    v_occurrence_state := private.derive_routine_occurrence_state(
      v_candidate.user_id,
      v_candidate.routine_item_id,
      v_candidate.item_type,
      v_candidate.occurrence_key,
      v_candidate.scheduled_for,
      p_now
    );

    IF v_occurrence_state ->> 'status' = 'missed'
      AND NOT EXISTS (
        SELECT 1
        FROM public.routine_adherence_logs missed
        WHERE missed.user_id = v_candidate.user_id
          AND missed.occurrence_key = v_candidate.occurrence_key
          AND missed.status = 'missed'
          AND missed.source = 'system'
      ) THEN
      INSERT INTO public.routine_adherence_logs (
        user_id,
        routine_item_id,
        item_type,
        status,
        idempotency_key,
        reminder_rule_id,
        occurrence_key,
        source,
        scheduled_for,
        occurred_at,
        snoozed_until
      ) VALUES (
        v_candidate.user_id,
        v_candidate.routine_item_id,
        v_candidate.item_type,
        'missed',
        'routine-missed:' || v_candidate.occurrence_key,
        v_candidate.rule_id,
        v_candidate.occurrence_key,
        'system',
        v_candidate.scheduled_for,
        v_candidate.occurrence_day_end,
        NULL
      )
      ON CONFLICT (user_id, idempotency_key) DO NOTHING;

      GET DIAGNOSTICS v_inserted_count = ROW_COUNT;
      v_finalized_count := v_finalized_count + v_inserted_count;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'processed_count', v_processed_count,
    'finalized_count', v_finalized_count,
    'next_cursor', CASE
      WHEN v_has_more THEN jsonb_build_object(
        'scheduled_for', v_last_scheduled_for,
        'user_id', v_last_user_id,
        'rule_id', v_last_rule_id
      )
      ELSE NULL
    END
  );
END;
$$;

REVOKE ALL ON FUNCTION private.derive_routine_occurrence_state(
  uuid,
  uuid,
  text,
  text,
  timestamptz,
  timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.derive_routine_occurrence_state(
  uuid,
  uuid,
  text,
  text,
  timestamptz,
  timestamptz
) TO service_role;

REVOKE ALL ON FUNCTION private.claim_routine_notification_event(
  uuid,
  timestamptz,
  timestamptz,
  timestamptz,
  uuid
) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.claim_reminder_event(uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_reminder_event(uuid, timestamptz, timestamptz)
  TO service_role;

REVOKE ALL ON FUNCTION public.list_due_routine_snoozes(
  timestamptz,
  integer,
  integer,
  timestamptz,
  uuid
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_due_routine_snoozes(
  timestamptz,
  integer,
  integer,
  timestamptz,
  uuid
) TO service_role;

REVOKE ALL ON FUNCTION public.claim_routine_snooze_event(uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_routine_snooze_event(uuid, timestamptz)
  TO service_role;

REVOKE ALL ON FUNCTION public.finalize_due_routine_occurrences(
  timestamptz,
  integer,
  timestamptz,
  uuid,
  uuid
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_due_routine_occurrences(
  timestamptz,
  integer,
  timestamptz,
  uuid,
  uuid
) TO service_role;

COMMENT ON FUNCTION private.claim_nonroutine_reminder_event(
  uuid,
  timestamptz,
  timestamptz
) IS 'Unchanged pre-Task-7 reminder claim implementation, callable only through the public category dispatcher.';
COMMENT ON FUNCTION public.claim_reminder_event(uuid, timestamptz, timestamptz) IS
  'Dispatches routine reminders to exact-occurrence resolution while preserving the prior non-routine claim implementation.';
COMMENT ON FUNCTION public.list_due_routine_snoozes(
  timestamptz,
  integer,
  integer,
  timestamptz,
  uuid
) IS 'Lists latest-open due routine snooze actions with complete service-only keyset pagination.';
COMMENT ON FUNCTION public.claim_routine_snooze_event(uuid, timestamptz) IS
  'Claims one technical routine snooze follow-up into the existing push outbox without provider sending.';
COMMENT ON FUNCTION public.finalize_due_routine_occurrences(
  timestamptz,
  integer,
  timestamptz,
  uuid,
  uuid
) IS 'Persists singleton missed actions after deterministic patient-local day boundaries with complete tuple pagination.';
