CREATE OR REPLACE FUNCTION private.routine_clock_timestamp()
RETURNS timestamptz
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT pg_catalog.clock_timestamp();
$$;

REVOKE ALL ON FUNCTION private.routine_clock_timestamp()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.routine_clock_timestamp() TO service_role;

ALTER FUNCTION private.enforce_routine_adherence_correction() STABLE;
ALTER FUNCTION private.enforce_reminder_event_routine_action() STABLE;

CREATE OR REPLACE FUNCTION public.record_routine_occurrence_action_atomic(
  p_user_id uuid,
  p_item_id uuid,
  p_expected_item_type text,
  p_reminder_rule_id uuid,
  p_scheduled_for timestamptz,
  p_status text,
  p_occurred_at timestamptz,
  p_snoozed_until timestamptz,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_existing public.routine_adherence_logs%ROWTYPE;
  v_item public.routine_items%ROWTYPE;
  v_rule public.reminder_rules%ROWTYPE;
  v_latest public.routine_adherence_logs%ROWTYPE;
  v_snapshot private.routine_occurrence_finalizer_rules%ROWTYPE;
  v_local_scheduled timestamp;
  v_occurrence_day_end timestamptz;
  v_occurrence_key text;
  v_supersedes_log_id uuid;
  v_superseded_created_at timestamptz;
  v_log_id uuid;
  v_now timestamptz;
  v_effective_occurred_at timestamptz;
  v_arrived_after_day_end boolean;
  v_has_latest boolean := false;
  v_is_correction boolean := false;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR p_item_id IS NULL
    OR p_expected_item_type IS NULL
    OR p_expected_item_type NOT IN ('supplement', 'medication')
    OR p_reminder_rule_id IS NULL
    OR p_scheduled_for IS NULL
    OR NOT isfinite(p_scheduled_for)
    OR p_status IS NULL
    OR p_status NOT IN ('taken', 'snoozed', 'skipped')
    OR p_occurred_at IS NULL
    OR NOT isfinite(p_occurred_at)
    OR p_idempotency_key IS NULL
    OR char_length(p_idempotency_key) NOT BETWEEN 8 AND 128
    OR p_idempotency_key !~ '^[A-Za-z0-9._:-]+$'
    OR (p_status = 'snoozed' AND p_snoozed_until IS NULL)
    OR (p_status <> 'snoozed' AND p_snoozed_until IS NOT NULL)
    OR (p_snoozed_until IS NOT NULL AND NOT isfinite(p_snoozed_until)) THEN
    RAISE EXCEPTION 'invalid_routine_occurrence_action' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      p_user_id::text || ':routine-action:' || p_idempotency_key,
      0
    )
  );

  SELECT action.*
  INTO v_existing
  FROM public.routine_adherence_logs action
  WHERE action.user_id = p_user_id
    AND action.idempotency_key = p_idempotency_key;

  IF FOUND THEN
    IF v_existing.routine_item_id IS DISTINCT FROM p_item_id
      OR v_existing.item_type IS DISTINCT FROM p_expected_item_type
      OR v_existing.reminder_rule_id IS DISTINCT FROM p_reminder_rule_id
      OR v_existing.scheduled_for IS DISTINCT FROM p_scheduled_for
      OR v_existing.status IS DISTINCT FROM p_status
      OR v_existing.occurred_at IS DISTINCT FROM p_occurred_at
      OR v_existing.snoozed_until IS DISTINCT FROM p_snoozed_until
      OR v_existing.source IS DISTINCT FROM 'patient' THEN
      RAISE EXCEPTION 'routine_action_idempotency_conflict' USING ERRCODE = '23505';
    END IF;

    RETURN jsonb_build_object(
      'adherence_log_id', v_existing.id,
      'occurrence_key', v_existing.occurrence_key,
      'item_type', v_existing.item_type,
      'status', v_existing.status
    );
  END IF;

  BEGIN
    v_item := private.lock_routine_item(
      p_user_id,
      p_item_id,
      p_expected_item_type,
      false
    );
  EXCEPTION
    WHEN no_data_found THEN
      RAISE EXCEPTION 'routine_occurrence_not_found' USING ERRCODE = 'P0002';
  END;

  v_rule := private.lock_routine_occurrence_rule(
    p_user_id,
    p_item_id,
    p_expected_item_type,
    p_reminder_rule_id
  );

  IF v_rule.id IS NULL THEN
    RAISE EXCEPTION 'routine_occurrence_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_occurrence_key := private.derive_routine_occurrence_key(
    p_reminder_rule_id,
    p_scheduled_for
  );
  v_snapshot := private.lock_routine_occurrence_snapshot(
    p_user_id,
    p_item_id,
    p_expected_item_type,
    p_reminder_rule_id,
    v_occurrence_key,
    p_scheduled_for,
    NULL
  );

  IF v_snapshot.snapshot_id IS NULL THEN
    RAISE EXCEPTION 'routine_occurrence_not_found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM private.lock_routine_occurrence(p_user_id, v_occurrence_key);

  v_now := private.routine_clock_timestamp();
  v_effective_occurred_at := least(p_occurred_at, v_now);
  v_local_scheduled := timezone(v_snapshot.timezone_name, p_scheduled_for);
  v_occurrence_day_end := (
    (v_local_scheduled::date + 1)::timestamp
      AT TIME ZONE v_snapshot.timezone_name
  );
  v_arrived_after_day_end := v_now >= v_occurrence_day_end;

  IF p_scheduled_for > v_effective_occurred_at THEN
    RAISE EXCEPTION 'routine_occurrence_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_occurred_at < p_scheduled_for
    OR p_occurred_at < v_now - interval '7 days'
    OR p_occurred_at > v_now + interval '5 minutes'
    OR p_occurred_at > v_occurrence_day_end + interval '7 days'
    OR v_now > v_occurrence_day_end + interval '7 days' THEN
    RAISE EXCEPTION 'routine_occurrence_action_out_of_order' USING ERRCODE = '23514';
  END IF;

  IF p_status = 'snoozed' AND (
    p_snoozed_until <= p_occurred_at
    OR timezone(v_snapshot.timezone_name, p_snoozed_until)::date
      IS DISTINCT FROM v_local_scheduled::date
  ) THEN
    RAISE EXCEPTION 'invalid_routine_snooze_time' USING ERRCODE = '22023';
  END IF;

  SELECT action.*
  INTO v_latest
  FROM public.routine_adherence_logs action
  WHERE action.user_id = p_user_id
    AND action.routine_item_id = p_item_id
    AND action.item_type = p_expected_item_type
    AND action.occurrence_key = v_occurrence_key
  ORDER BY action.created_at DESC, action.id DESC
  LIMIT 1;
  v_has_latest := FOUND;

  IF v_has_latest THEN
    v_is_correction := v_latest.status = 'missed'
      AND v_latest.source = 'system'
      AND p_status = 'taken'
      AND v_arrived_after_day_end;

    IF v_is_correction THEN
      v_supersedes_log_id := v_latest.id;
    ELSIF v_latest.status IN ('taken', 'skipped', 'missed') THEN
      RAISE EXCEPTION 'routine_occurrence_terminal' USING ERRCODE = '23514';
    ELSIF p_occurred_at < v_latest.occurred_at THEN
      RAISE EXCEPTION 'routine_occurrence_action_out_of_order' USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_arrived_after_day_end
    AND NOT v_is_correction THEN
    IF p_status <> 'taken' THEN
      RAISE EXCEPTION 'routine_occurrence_terminal' USING ERRCODE = '23514';
    END IF;

    SELECT ensured.missed_log_id
    INTO v_supersedes_log_id
    FROM private.ensure_routine_occurrence_missed(
      p_user_id,
      p_item_id,
      p_expected_item_type,
      p_reminder_rule_id,
      v_occurrence_key,
      p_scheduled_for,
      v_occurrence_day_end
    ) ensured;
    v_is_correction := true;
  END IF;

  IF (
    NOT v_item.active
    OR v_item.archived_at IS NOT NULL
    OR NOT v_rule.active
    OR v_rule.deactivated_at IS NOT NULL
  ) AND NOT v_is_correction THEN
    RAISE EXCEPTION 'routine_occurrence_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_supersedes_log_id IS NOT NULL THEN
    SELECT superseded.created_at
    INTO v_superseded_created_at
    FROM public.routine_adherence_logs superseded
    WHERE superseded.id = v_supersedes_log_id
      AND superseded.user_id = p_user_id
      AND superseded.occurrence_key = v_occurrence_key;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'routine_occurrence_terminal' USING ERRCODE = '23514';
    END IF;
  END IF;

  INSERT INTO public.routine_adherence_logs (
    user_id,
    routine_item_id,
    item_type,
    status,
    idempotency_key,
    reminder_rule_id,
    occurrence_key,
    source,
    created_at,
    scheduled_for,
    occurred_at,
    snoozed_until,
    supersedes_log_id
  ) VALUES (
    p_user_id,
    p_item_id,
    p_expected_item_type,
    p_status,
    p_idempotency_key,
    p_reminder_rule_id,
    v_occurrence_key,
    'patient',
    CASE
      WHEN v_superseded_created_at IS NULL THEN private.routine_clock_timestamp()
      ELSE greatest(
        private.routine_clock_timestamp(),
        v_superseded_created_at + interval '1 microsecond'
      )
    END,
    p_scheduled_for,
    p_occurred_at,
    p_snoozed_until,
    v_supersedes_log_id
  )
  RETURNING id INTO v_log_id;

  RETURN jsonb_build_object(
    'adherence_log_id', v_log_id,
    'occurrence_key', v_occurrence_key,
    'item_type', p_expected_item_type,
    'status', p_status
  );
END;
$$;

COMMENT ON FUNCTION private.routine_clock_timestamp() IS
  'Internal authoritative clock for deterministic routine transition tests; not configurable by API callers.';
