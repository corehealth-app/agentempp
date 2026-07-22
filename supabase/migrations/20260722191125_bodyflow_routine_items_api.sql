CREATE OR REPLACE FUNCTION private.routine_user_timezone(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_timezone text;
BEGIN
  SELECT domain_user.timezone
  INTO v_timezone
  FROM public.users domain_user
  WHERE domain_user.id = p_user_id
    AND domain_user.status = 'active';

  IF v_timezone IS NULL OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_timezone_names timezone_name
    WHERE timezone_name.name = v_timezone
  ) THEN
    RAISE EXCEPTION 'routine_user_context_invalid' USING ERRCODE = '22023';
  END IF;

  RETURN v_timezone;
END;
$$;

CREATE OR REPLACE FUNCTION private.canonicalize_routine_schedules(p_schedules jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF p_schedules IS NULL
    OR jsonb_typeof(p_schedules) IS DISTINCT FROM 'array'
    OR jsonb_array_length(p_schedules) NOT BETWEEN 1 AND 16 THEN
    RAISE EXCEPTION 'invalid_routine_schedules' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_schedules) schedule(value)
    WHERE jsonb_typeof(schedule.value) IS DISTINCT FROM 'object'
      OR (
        SELECT array_agg(property.key ORDER BY property.key)
        FROM jsonb_object_keys(schedule.value) property(key)
      ) IS DISTINCT FROM ARRAY['local_time', 'weekdays']::text[]
      OR jsonb_typeof(schedule.value -> 'local_time') IS DISTINCT FROM 'string'
      OR schedule.value ->> 'local_time' !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
      OR jsonb_typeof(schedule.value -> 'weekdays') IS DISTINCT FROM 'array'
      OR jsonb_array_length(schedule.value -> 'weekdays') NOT BETWEEN 1 AND 7
      OR EXISTS (
        SELECT 1
        FROM jsonb_array_elements(schedule.value -> 'weekdays') weekday(value)
        WHERE jsonb_typeof(weekday.value) IS DISTINCT FROM 'number'
          OR weekday.value #>> '{}' !~ '^[0-6]$'
      )
      OR (
        SELECT count(*)
        FROM jsonb_array_elements(schedule.value -> 'weekdays') weekday(value)
      ) <> (
        SELECT count(DISTINCT weekday.value #>> '{}')
        FROM jsonb_array_elements(schedule.value -> 'weekdays') weekday(value)
      )
  ) THEN
    RAISE EXCEPTION 'invalid_routine_schedules' USING ERRCODE = '22023';
  END IF;

  WITH normalized AS (
    SELECT
      schedule.value ->> 'local_time' AS local_time,
      ARRAY(
        SELECT (weekday.value #>> '{}')::smallint
        FROM jsonb_array_elements(schedule.value -> 'weekdays') weekday(value)
        ORDER BY (weekday.value #>> '{}')::smallint
      ) AS weekdays
    FROM jsonb_array_elements(p_schedules) schedule(value)
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'local_time', normalized.local_time,
      'weekdays', to_jsonb(normalized.weekdays)
    )
    ORDER BY normalized.local_time, normalized.weekdays
  )
  INTO v_result
  FROM normalized;

  IF (
    SELECT count(*)
    FROM jsonb_array_elements(v_result) schedule(value)
  ) <> (
    SELECT count(DISTINCT (
      schedule.value ->> 'local_time',
      schedule.value -> 'weekdays'
    ))
    FROM jsonb_array_elements(v_result) schedule(value)
  ) THEN
    RAISE EXCEPTION 'duplicate_routine_schedule' USING ERRCODE = '22023';
  END IF;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION private.routine_same_local_date(
  p_user_id uuid,
  p_left timestamptz,
  p_right timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_timezone text;
BEGIN
  IF p_left IS NULL OR p_right IS NULL THEN
    RETURN false;
  END IF;

  v_timezone := private.routine_user_timezone(p_user_id);
  RETURN timezone(v_timezone, p_left)::date = timezone(v_timezone, p_right)::date;
END;
$$;

CREATE OR REPLACE FUNCTION private.derive_routine_occurrence_key(
  p_reminder_rule_id uuid,
  p_original_scheduled_for timestamptz
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
STRICT
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_epoch_microseconds bigint;
BEGIN
  v_epoch_microseconds := (
    extract(epoch FROM p_original_scheduled_for) * 1000000
  )::bigint;

  RETURN encode(
    extensions.digest(
      convert_to(
        lower(p_reminder_rule_id::text) || ':' || v_epoch_microseconds::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
END;
$$;

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

  IF NOT FOUND THEN
    v_status := CASE
      WHEN p_as_of >= v_occurrence_day_end THEN 'missed'
      ELSE 'pending'
    END;
  END IF;

  RETURN jsonb_build_object(
    'status', v_status,
    'last_action_at', v_last_action_at,
    'snoozed_until', v_snoozed_until
  );
END;
$$;

CREATE OR REPLACE FUNCTION private.lock_routine_occurrence(
  p_user_id uuid,
  p_occurrence_key text
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  IF p_user_id IS NULL
    OR p_occurrence_key IS NULL
    OR p_occurrence_key !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_routine_occurrence_identity' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      p_user_id::text || ':routine-occurrence:' || p_occurrence_key,
      0
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION private.lock_routine_item(
  p_user_id uuid,
  p_item_id uuid,
  p_expected_item_type text,
  p_require_active boolean
)
RETURNS public.routine_items
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_item public.routine_items%ROWTYPE;
BEGIN
  IF p_user_id IS NULL
    OR p_item_id IS NULL
    OR p_require_active IS NULL
    OR (
      p_expected_item_type IS NOT NULL
      AND p_expected_item_type NOT IN ('supplement', 'medication')
    ) THEN
    RAISE EXCEPTION 'invalid_routine_item_identity' USING ERRCODE = '22023';
  END IF;

  SELECT item.*
  INTO v_item
  FROM public.routine_items item
  WHERE item.id = p_item_id
    AND item.user_id = p_user_id
    AND (
      p_expected_item_type IS NULL
      OR item.item_type = p_expected_item_type
    )
  FOR UPDATE;

  IF NOT FOUND OR (
    p_require_active
    AND (NOT v_item.active OR v_item.archived_at IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'routine_item_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_item;
END;
$$;

CREATE OR REPLACE FUNCTION private.read_routine_mutation_receipt(
  p_user_id uuid,
  p_idempotency_key text,
  p_operation text,
  p_request_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_receipt private.routine_mutation_receipts%ROWTYPE;
BEGIN
  IF p_user_id IS NULL
    OR p_idempotency_key IS NULL
    OR char_length(p_idempotency_key) NOT BETWEEN 8 AND 128
    OR p_idempotency_key !~ '^[A-Za-z0-9._:-]+$'
    OR p_operation NOT IN (
      'routine_item_create',
      'routine_item_update',
      'routine_item_archive',
      'legal_acceptance'
    )
    OR p_request_hash IS NULL
    OR p_request_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_routine_mutation_identity' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      p_user_id::text || ':routine-mutation:' || p_idempotency_key,
      0
    )
  );

  SELECT receipt.*
  INTO v_receipt
  FROM private.routine_mutation_receipts receipt
  WHERE receipt.user_id = p_user_id
    AND receipt.idempotency_key = p_idempotency_key
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_receipt.operation IS DISTINCT FROM p_operation
    OR v_receipt.request_hash IS DISTINCT FROM p_request_hash THEN
    RAISE EXCEPTION 'routine_mutation_idempotency_conflict' USING ERRCODE = '23505';
  END IF;

  RETURN v_receipt.result_payload;
END;
$$;

CREATE OR REPLACE FUNCTION private.write_routine_mutation_receipt(
  p_user_id uuid,
  p_idempotency_key text,
  p_operation text,
  p_request_hash text,
  p_result_payload jsonb
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  INSERT INTO private.routine_mutation_receipts (
    user_id,
    idempotency_key,
    operation,
    request_hash,
    result_payload
  ) VALUES (
    p_user_id,
    p_idempotency_key,
    p_operation,
    p_request_hash,
    p_result_payload
  );
EXCEPTION
  WHEN unique_violation THEN
    IF private.read_routine_mutation_receipt(
      p_user_id,
      p_idempotency_key,
      p_operation,
      p_request_hash
    ) IS DISTINCT FROM p_result_payload THEN
      RAISE EXCEPTION 'routine_mutation_idempotency_conflict' USING ERRCODE = '23505';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION private.assert_current_medication_legal_acceptance(
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_locale text;
  v_document_key constant text := 'medication_reminder_disclaimer';
  v_version text;
BEGIN
  SELECT domain_user.locale
  INTO v_locale
  FROM public.users domain_user
  WHERE domain_user.id = p_user_id
    AND domain_user.status = 'active'
    AND domain_user.locale IN ('pt-BR', 'en-US');

  IF v_locale IS NULL THEN
    RAISE EXCEPTION 'medication_legal_acceptance_required' USING ERRCODE = '23514';
  END IF;

  LOCK TABLE public.legal_documents IN SHARE MODE;

  SELECT document.version
  INTO v_version
  FROM public.legal_documents document
  WHERE document.document_key = v_document_key
    AND document.locale = v_locale
    AND document.required_from <= clock_timestamp()
  ORDER BY document.required_from DESC, document.created_at DESC, document.id DESC
  LIMIT 1;

  IF v_version IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.user_legal_acceptances acceptance
    WHERE acceptance.user_id = p_user_id
      AND acceptance.document_key = v_document_key
      AND acceptance.version = v_version
  ) THEN
    RAISE EXCEPTION 'medication_legal_acceptance_required' USING ERRCODE = '23514';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_mobile_routine_item(
  p_user_id uuid,
  p_item_type text,
  p_payload jsonb,
  p_idempotency_key text,
  p_request_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_replay jsonb;
  v_schedules jsonb;
  v_item_id uuid;
  v_result jsonb;
  v_now timestamptz := clock_timestamp();
BEGIN
  PERFORM private.assert_trusted_backend();

  v_replay := private.read_routine_mutation_receipt(
    p_user_id,
    p_idempotency_key,
    'routine_item_create',
    p_request_hash
  );
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  IF p_item_type IS NULL
    OR p_item_type NOT IN ('supplement', 'medication')
    OR p_payload IS NULL
    OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object'
    OR (
      SELECT array_agg(property.key ORDER BY property.key)
      FROM jsonb_object_keys(p_payload) property(key)
    ) IS DISTINCT FROM ARRAY[
      'dose_text',
      'name',
      'origin',
      'reminders_enabled',
      'schedules'
    ]::text[]
    OR jsonb_typeof(p_payload -> 'name') IS DISTINCT FROM 'string'
    OR char_length(btrim(p_payload ->> 'name')) NOT BETWEEN 1 AND 200
    OR jsonb_typeof(p_payload -> 'dose_text') IS DISTINCT FROM 'string'
    OR char_length(btrim(p_payload ->> 'dose_text')) NOT BETWEEN 1 AND 120
    OR jsonb_typeof(p_payload -> 'origin') IS DISTINCT FROM 'string'
    OR p_payload ->> 'origin' NOT IN ('user', 'professional', 'protocol', 'other')
    OR jsonb_typeof(p_payload -> 'reminders_enabled') IS DISTINCT FROM 'boolean' THEN
    RAISE EXCEPTION 'invalid_routine_item_payload' USING ERRCODE = '22023';
  END IF;

  v_schedules := private.canonicalize_routine_schedules(p_payload -> 'schedules');
  PERFORM private.routine_user_timezone(p_user_id);

  IF p_item_type = 'medication' THEN
    PERFORM private.assert_current_medication_legal_acceptance(p_user_id);
  END IF;

  INSERT INTO public.routine_items (
    user_id,
    item_type,
    name,
    dose_text,
    origin,
    reminders_enabled,
    active,
    version,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_item_type,
    btrim(p_payload ->> 'name'),
    btrim(p_payload ->> 'dose_text'),
    p_payload ->> 'origin',
    (p_payload ->> 'reminders_enabled')::boolean,
    true,
    1,
    v_now,
    v_now
  )
  RETURNING id INTO v_item_id;

  INSERT INTO public.reminder_rules (
    user_id,
    routine_item_id,
    category,
    local_time,
    weekdays,
    active,
    created_at,
    updated_at
  )
  SELECT
    p_user_id,
    v_item_id,
    p_item_type,
    (schedule.value ->> 'local_time')::time,
    ARRAY(
      SELECT (weekday.value #>> '{}')::smallint
      FROM jsonb_array_elements(schedule.value -> 'weekdays') weekday(value)
      ORDER BY (weekday.value #>> '{}')::smallint
    ),
    true,
    v_now,
    v_now
  FROM jsonb_array_elements(v_schedules) schedule(value);

  INSERT INTO public.product_events (user_id, event, properties, occurred_at)
  VALUES (
    p_user_id,
    'routine.item.created',
    jsonb_build_object(
      'routine_item_id', v_item_id,
      'item_type', p_item_type,
      'version', 1,
      'status', 'active'
    ),
    v_now
  );

  v_result := jsonb_build_object(
    'routine_item_id', v_item_id,
    'version', 1
  );
  PERFORM private.write_routine_mutation_receipt(
    p_user_id,
    p_idempotency_key,
    'routine_item_create',
    p_request_hash,
    v_result
  );

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_mobile_routine_item(
  p_user_id uuid,
  p_item_id uuid,
  p_expected_version integer,
  p_patch jsonb,
  p_idempotency_key text,
  p_request_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_replay jsonb;
  v_item public.routine_items%ROWTYPE;
  v_schedules jsonb;
  v_result jsonb;
  v_now timestamptz := clock_timestamp();
BEGIN
  PERFORM private.assert_trusted_backend();

  v_replay := private.read_routine_mutation_receipt(
    p_user_id,
    p_idempotency_key,
    'routine_item_update',
    p_request_hash
  );
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  IF p_item_id IS NULL
    OR p_expected_version IS NULL
    OR p_expected_version <= 0
    OR p_patch IS NULL
    OR jsonb_typeof(p_patch) IS DISTINCT FROM 'object'
    OR (
      SELECT count(*)
      FROM jsonb_object_keys(p_patch)
    ) = 0
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_patch) property(key)
      WHERE property.key <> ALL (ARRAY[
        'name',
        'dose_text',
        'origin',
        'reminders_enabled',
        'schedules'
      ]::text[])
    )
    OR (
      p_patch ? 'name'
      AND (
        jsonb_typeof(p_patch -> 'name') IS DISTINCT FROM 'string'
        OR char_length(btrim(p_patch ->> 'name')) NOT BETWEEN 1 AND 200
      )
    )
    OR (
      p_patch ? 'dose_text'
      AND (
        jsonb_typeof(p_patch -> 'dose_text') IS DISTINCT FROM 'string'
        OR char_length(btrim(p_patch ->> 'dose_text')) NOT BETWEEN 1 AND 120
      )
    )
    OR (
      p_patch ? 'origin'
      AND (
        jsonb_typeof(p_patch -> 'origin') IS DISTINCT FROM 'string'
        OR p_patch ->> 'origin' NOT IN ('user', 'professional', 'protocol', 'other')
      )
    )
    OR (
      p_patch ? 'reminders_enabled'
      AND jsonb_typeof(p_patch -> 'reminders_enabled') IS DISTINCT FROM 'boolean'
    ) THEN
    RAISE EXCEPTION 'invalid_routine_item_patch' USING ERRCODE = '22023';
  END IF;

  IF p_patch ? 'schedules' THEN
    v_schedules := private.canonicalize_routine_schedules(p_patch -> 'schedules');
  END IF;

  v_item := private.lock_routine_item(p_user_id, p_item_id, NULL, true);

  IF v_item.version IS DISTINCT FROM p_expected_version THEN
    RAISE EXCEPTION 'routine_item_version_conflict' USING ERRCODE = '40001';
  END IF;

  IF v_schedules IS NOT NULL THEN
    PERFORM rule.id
    FROM public.reminder_rules rule
    WHERE rule.user_id = p_user_id
      AND rule.routine_item_id = p_item_id
      AND rule.category = v_item.item_type
      AND rule.active
    FOR UPDATE;

    WITH desired AS (
      SELECT
        (schedule.value ->> 'local_time')::time AS local_time,
        ARRAY(
          SELECT (weekday.value #>> '{}')::smallint
          FROM jsonb_array_elements(schedule.value -> 'weekdays') weekday(value)
          ORDER BY (weekday.value #>> '{}')::smallint
        ) AS weekdays
      FROM jsonb_array_elements(v_schedules) schedule(value)
    ),
    ranked_rules AS (
      SELECT
        rule.id,
        row_number() OVER (
          PARTITION BY rule.local_time, rule.weekdays
          ORDER BY rule.created_at, rule.id
        ) AS duplicate_rank,
        EXISTS (
          SELECT 1
          FROM desired
          WHERE desired.local_time = rule.local_time
            AND desired.weekdays = rule.weekdays
        ) AS desired_match
      FROM public.reminder_rules rule
      WHERE rule.user_id = p_user_id
        AND rule.routine_item_id = p_item_id
        AND rule.category = v_item.item_type
        AND rule.active
    )
    UPDATE public.reminder_rules rule
    SET active = false,
        deactivated_at = v_now,
        updated_at = v_now
    FROM ranked_rules ranked
    WHERE rule.id = ranked.id
      AND (NOT ranked.desired_match OR ranked.duplicate_rank > 1);

    INSERT INTO public.reminder_rules (
      user_id,
      routine_item_id,
      category,
      local_time,
      weekdays,
      active,
      created_at,
      updated_at
    )
    SELECT
      p_user_id,
      p_item_id,
      v_item.item_type,
      desired.local_time,
      desired.weekdays,
      true,
      v_now,
      v_now
    FROM (
      SELECT
        (schedule.value ->> 'local_time')::time AS local_time,
        ARRAY(
          SELECT (weekday.value #>> '{}')::smallint
          FROM jsonb_array_elements(schedule.value -> 'weekdays') weekday(value)
          ORDER BY (weekday.value #>> '{}')::smallint
        ) AS weekdays
      FROM jsonb_array_elements(v_schedules) schedule(value)
    ) desired
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.reminder_rules rule
      WHERE rule.user_id = p_user_id
        AND rule.routine_item_id = p_item_id
        AND rule.category = v_item.item_type
        AND rule.active
        AND rule.local_time = desired.local_time
        AND rule.weekdays = desired.weekdays
    );
  END IF;

  UPDATE public.routine_items item
  SET name = CASE
        WHEN p_patch ? 'name' THEN btrim(p_patch ->> 'name')
        ELSE item.name
      END,
      dose_text = CASE
        WHEN p_patch ? 'dose_text' THEN btrim(p_patch ->> 'dose_text')
        ELSE item.dose_text
      END,
      origin = CASE
        WHEN p_patch ? 'origin' THEN p_patch ->> 'origin'
        ELSE item.origin
      END,
      reminders_enabled = CASE
        WHEN p_patch ? 'reminders_enabled'
          THEN (p_patch ->> 'reminders_enabled')::boolean
        ELSE item.reminders_enabled
      END,
      version = item.version + 1,
      updated_at = v_now
  WHERE item.id = p_item_id
    AND item.user_id = p_user_id
  RETURNING item.* INTO v_item;

  INSERT INTO public.product_events (user_id, event, properties, occurred_at)
  VALUES (
    p_user_id,
    'routine.item.updated',
    jsonb_build_object(
      'routine_item_id', p_item_id,
      'item_type', v_item.item_type,
      'version', v_item.version,
      'status', 'active'
    ),
    v_now
  );

  v_result := jsonb_build_object(
    'routine_item_id', p_item_id,
    'version', v_item.version
  );
  PERFORM private.write_routine_mutation_receipt(
    p_user_id,
    p_idempotency_key,
    'routine_item_update',
    p_request_hash,
    v_result
  );

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_mobile_routine_item(
  p_user_id uuid,
  p_item_id uuid,
  p_idempotency_key text,
  p_request_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_replay jsonb;
  v_item public.routine_items%ROWTYPE;
  v_result jsonb;
  v_now timestamptz := clock_timestamp();
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_item_id IS NULL THEN
    RAISE EXCEPTION 'invalid_routine_item_identity' USING ERRCODE = '22023';
  END IF;

  v_replay := private.read_routine_mutation_receipt(
    p_user_id,
    p_idempotency_key,
    'routine_item_archive',
    p_request_hash
  );
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  v_item := private.lock_routine_item(p_user_id, p_item_id, NULL, true);

  UPDATE public.reminder_rules rule
  SET active = false,
      deactivated_at = v_now,
      updated_at = v_now
  WHERE rule.user_id = p_user_id
    AND rule.routine_item_id = p_item_id
    AND rule.category = v_item.item_type
    AND rule.active;

  UPDATE public.routine_items item
  SET active = false,
      reminders_enabled = false,
      archived_at = v_now,
      version = item.version + 1,
      updated_at = v_now
  WHERE item.id = p_item_id
    AND item.user_id = p_user_id
  RETURNING item.* INTO v_item;

  INSERT INTO public.product_events (user_id, event, properties, occurred_at)
  VALUES (
    p_user_id,
    'routine.item.archived',
    jsonb_build_object(
      'routine_item_id', p_item_id,
      'item_type', v_item.item_type,
      'version', v_item.version,
      'status', 'archived'
    ),
    v_now
  );

  v_result := jsonb_build_object(
    'routine_item_id', p_item_id,
    'version', v_item.version,
    'archived_at', v_item.archived_at
  );
  PERFORM private.write_routine_mutation_receipt(
    p_user_id,
    p_idempotency_key,
    'routine_item_archive',
    p_request_hash,
    v_result
  );

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_mobile_routine_items(
  p_user_id uuid,
  p_item_type text,
  p_include_archived boolean DEFAULT false,
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_timezone text;
  v_local_date date;
  v_result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_item_type IS NULL
    OR p_item_type NOT IN ('supplement', 'medication')
    OR p_include_archived IS NULL
    OR p_now IS NULL THEN
    RAISE EXCEPTION 'invalid_routine_list_request' USING ERRCODE = '22023';
  END IF;

  v_timezone := private.routine_user_timezone(p_user_id);
  v_local_date := timezone(v_timezone, p_now)::date;

  WITH item_rows AS (
    SELECT item.*
    FROM public.routine_items item
    WHERE item.user_id = p_user_id
      AND item.item_type = p_item_type
      AND (
        p_include_archived
        OR (item.active AND item.archived_at IS NULL)
      )
  ),
  rule_rows AS (
    SELECT
      rule.id,
      rule.routine_item_id,
      rule.local_time,
      rule.weekdays,
      CASE
        WHEN extract(dow FROM v_local_date)::smallint = ANY(rule.weekdays)
          THEN v_local_date + rule.local_time
        ELSE NULL
      END AS local_scheduled_at
    FROM public.reminder_rules rule
    JOIN item_rows item ON item.id = rule.routine_item_id
    WHERE rule.user_id = p_user_id
      AND rule.category = p_item_type
      AND rule.active
  ),
  occurrence_rows AS (
    SELECT
      rule.*,
      CASE
        WHEN rule.local_scheduled_at IS NOT NULL
          THEN rule.local_scheduled_at AT TIME ZONE v_timezone
        ELSE NULL
      END AS candidate_scheduled_for
    FROM rule_rows rule
  ),
  canonical_occurrences AS (
    SELECT
      occurrence.*,
      CASE
        WHEN occurrence.candidate_scheduled_for IS NOT NULL
          AND timezone(v_timezone, occurrence.candidate_scheduled_for)
            = occurrence.local_scheduled_at
          THEN occurrence.candidate_scheduled_for
        ELSE NULL
      END AS scheduled_for
    FROM occurrence_rows occurrence
  ),
  schedule_rows AS (
    SELECT
      occurrence.id,
      occurrence.routine_item_id,
      occurrence.local_time,
      occurrence.weekdays,
      occurrence.scheduled_for,
      private.derive_routine_occurrence_key(
        occurrence.id,
        occurrence.scheduled_for
      ) AS occurrence_key
    FROM canonical_occurrences occurrence
  ),
  schedule_states AS (
    SELECT
      schedule.*,
      CASE
        WHEN schedule.occurrence_key IS NULL THEN NULL
        ELSE private.derive_routine_occurrence_state(
          p_user_id,
          schedule.routine_item_id,
          p_item_type,
          schedule.occurrence_key,
          schedule.scheduled_for,
          p_now
        )
      END AS occurrence_state
    FROM schedule_rows schedule
  )
  SELECT jsonb_build_object(
    'local_date', v_local_date,
    'items', COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', item.id,
          'item_type', item.item_type,
          'name', item.name,
          'dose_text', item.dose_text,
          'origin', item.origin,
          'reminders_enabled', item.reminders_enabled,
          'active', item.active,
          'archived_at', item.archived_at,
          'version', item.version,
          'created_at', item.created_at,
          'updated_at', item.updated_at,
          'schedules', COALESCE(
            (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'id', schedule.id,
                  'local_time', to_char(schedule.local_time, 'HH24:MI'),
                  'weekdays', to_jsonb(schedule.weekdays),
                  'occurrence', CASE
                    WHEN schedule.occurrence_key IS NULL THEN NULL
                    ELSE jsonb_build_object(
                      'occurrence_key', schedule.occurrence_key,
                      'scheduled_for', schedule.scheduled_for
                    ) || schedule.occurrence_state
                  END
                )
                ORDER BY schedule.local_time, schedule.weekdays, schedule.id
              )
              FROM schedule_states schedule
              WHERE schedule.routine_item_id = item.id
            ),
            '[]'::jsonb
          )
        )
        ORDER BY item.updated_at DESC, item.id DESC
      ),
      '[]'::jsonb
    )
  )
  INTO v_result
  FROM item_rows item;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_mobile_routine_history(
  p_user_id uuid,
  p_item_id uuid,
  p_item_type text,
  p_limit integer,
  p_before_occurred_at timestamptz DEFAULT NULL,
  p_before_log_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_item_id IS NULL
    OR p_item_type IS NULL
    OR p_item_type NOT IN ('supplement', 'medication')
    OR p_limit IS NULL
    OR p_limit NOT BETWEEN 1 AND 50
    OR (p_before_occurred_at IS NULL) <> (p_before_log_id IS NULL) THEN
    RAISE EXCEPTION 'invalid_routine_history_request' USING ERRCODE = '22023';
  END IF;

  PERFORM 1
  FROM public.routine_items item
  WHERE item.id = p_item_id
    AND item.user_id = p_user_id
    AND item.item_type = p_item_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'routine_item_not_found' USING ERRCODE = 'P0002';
  END IF;

  WITH page_with_sentinel AS (
    SELECT log.*
    FROM public.routine_adherence_logs log
    WHERE log.user_id = p_user_id
      AND log.routine_item_id = p_item_id
      AND log.item_type = p_item_type
      AND (
        p_before_occurred_at IS NULL
        OR (log.occurred_at, log.id) < (p_before_occurred_at, p_before_log_id)
      )
    ORDER BY log.occurred_at DESC, log.id DESC
    LIMIT p_limit + 1
  ),
  returned_page AS (
    SELECT page.*
    FROM page_with_sentinel page
    ORDER BY page.occurred_at DESC, page.id DESC
    LIMIT p_limit
  )
  SELECT jsonb_build_object(
    'items', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', log.id,
            'routine_item_id', log.routine_item_id,
            'item_type', log.item_type,
            'status', log.status,
            'reminder_rule_id', log.reminder_rule_id,
            'occurrence_key', log.occurrence_key,
            'scheduled_for', log.scheduled_for,
            'occurred_at', log.occurred_at,
            'snoozed_until', log.snoozed_until,
            'source', log.source,
            'supersedes_log_id', log.supersedes_log_id,
            'created_at', log.created_at
          )
          ORDER BY log.occurred_at DESC, log.id DESC
        )
        FROM returned_page log
      ),
      '[]'::jsonb
    ),
    'next_cursor', CASE
      WHEN (SELECT count(*) FROM page_with_sentinel) > p_limit THEN (
        SELECT jsonb_build_object(
          'occurred_at', cursor_log.occurred_at,
          'log_id', cursor_log.id
        )
        FROM returned_page cursor_log
        ORDER BY cursor_log.occurred_at DESC, cursor_log.id DESC
        OFFSET p_limit - 1
        LIMIT 1
      )
      ELSE NULL
    END
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

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
  v_timezone text;
  v_local_scheduled timestamp;
  v_occurrence_day_end timestamptz;
  v_occurrence_key text;
  v_supersedes_log_id uuid;
  v_log_id uuid;
  v_has_latest boolean := false;
  v_is_correction boolean := false;
  v_result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR p_item_id IS NULL
    OR p_expected_item_type IS NULL
    OR p_expected_item_type NOT IN ('supplement', 'medication')
    OR p_reminder_rule_id IS NULL
    OR p_scheduled_for IS NULL
    OR p_status IS NULL
    OR p_status NOT IN ('taken', 'snoozed', 'skipped')
    OR p_occurred_at IS NULL
    OR p_idempotency_key IS NULL
    OR char_length(p_idempotency_key) NOT BETWEEN 8 AND 128
    OR p_idempotency_key !~ '^[A-Za-z0-9._:-]+$'
    OR (p_status = 'snoozed' AND p_snoozed_until IS NULL)
    OR (p_status <> 'snoozed' AND p_snoozed_until IS NOT NULL) THEN
    RAISE EXCEPTION 'invalid_routine_occurrence_action' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      p_user_id::text || ':routine-action:' || p_idempotency_key,
      0
    )
  );

  SELECT log.*
  INTO v_existing
  FROM public.routine_adherence_logs log
  WHERE log.user_id = p_user_id
    AND log.idempotency_key = p_idempotency_key;

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

  v_item := private.lock_routine_item(
    p_user_id,
    p_item_id,
    p_expected_item_type,
    false
  );

  SELECT rule.*
  INTO v_rule
  FROM public.reminder_rules rule
  WHERE rule.id = p_reminder_rule_id
    AND rule.user_id = p_user_id
    AND rule.routine_item_id = p_item_id
    AND rule.category = p_expected_item_type
  FOR KEY SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'routine_item_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_timezone := private.routine_user_timezone(p_user_id);
  v_local_scheduled := timezone(v_timezone, p_scheduled_for);

  IF (v_local_scheduled AT TIME ZONE v_timezone) IS DISTINCT FROM p_scheduled_for
    OR extract(dow FROM v_local_scheduled)::smallint <> ALL(v_rule.weekdays)
    OR v_local_scheduled::time IS DISTINCT FROM v_rule.local_time THEN
    RAISE EXCEPTION 'routine_occurrence_schedule_mismatch' USING ERRCODE = '22023';
  END IF;

  v_occurrence_day_end := (
    (v_local_scheduled::date + 1)::timestamp AT TIME ZONE v_timezone
  );

  IF p_status = 'snoozed' AND (
    p_snoozed_until <= p_occurred_at
    OR NOT private.routine_same_local_date(
      p_user_id,
      p_scheduled_for,
      p_snoozed_until
    )
  ) THEN
    RAISE EXCEPTION 'invalid_routine_snooze_time' USING ERRCODE = '22023';
  END IF;

  v_occurrence_key := private.derive_routine_occurrence_key(
    p_reminder_rule_id,
    p_scheduled_for
  );
  PERFORM private.lock_routine_occurrence(p_user_id, v_occurrence_key);

  SELECT log.*
  INTO v_latest
  FROM public.routine_adherence_logs log
  WHERE log.user_id = p_user_id
    AND log.routine_item_id = p_item_id
    AND log.item_type = p_expected_item_type
    AND log.occurrence_key = v_occurrence_key
  ORDER BY log.occurred_at DESC, log.created_at DESC, log.id DESC
  LIMIT 1;
  v_has_latest := FOUND;

  IF v_has_latest THEN
    v_is_correction := v_latest.status = 'missed'
      AND v_latest.source = 'system'
      AND p_status = 'taken'
      AND p_occurred_at >= v_latest.occurred_at
      AND p_occurred_at <= v_occurrence_day_end + interval '7 days'
      AND clock_timestamp() <= v_occurrence_day_end + interval '7 days';

    IF v_is_correction THEN
      v_supersedes_log_id := v_latest.id;
    ELSIF v_latest.status IN ('taken', 'skipped', 'missed') THEN
      RAISE EXCEPTION 'routine_occurrence_terminal' USING ERRCODE = '23514';
    ELSIF p_occurred_at < v_latest.occurred_at THEN
      RAISE EXCEPTION 'routine_occurrence_action_out_of_order' USING ERRCODE = '23514';
    END IF;
  END IF;

  IF (NOT v_item.active OR v_item.archived_at IS NOT NULL OR NOT v_rule.active)
    AND NOT v_is_correction THEN
    RAISE EXCEPTION 'routine_item_not_found' USING ERRCODE = 'P0002';
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
    p_scheduled_for,
    p_occurred_at,
    p_snoozed_until,
    v_supersedes_log_id
  )
  RETURNING id INTO v_log_id;

  v_result := jsonb_build_object(
    'adherence_log_id', v_log_id,
    'occurrence_key', v_occurrence_key,
    'item_type', p_expected_item_type,
    'status', p_status
  );
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_mobile_legal_document(
  p_user_id uuid,
  p_document_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_locale text;
  v_result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR p_document_key IS NULL
    OR p_document_key !~ '^[a-z][a-z0-9_]{0,99}$' THEN
    RAISE EXCEPTION 'invalid_legal_document_request' USING ERRCODE = '22023';
  END IF;

  SELECT domain_user.locale
  INTO v_locale
  FROM public.users domain_user
  WHERE domain_user.id = p_user_id
    AND domain_user.status = 'active'
    AND domain_user.locale IN ('pt-BR', 'en-US');

  IF v_locale IS NULL THEN
    RAISE EXCEPTION 'legal_document_not_available' USING ERRCODE = 'P0002';
  END IF;

  SELECT jsonb_build_object(
    'document_key', document.document_key,
    'version', document.version,
    'locale', document.locale,
    'body', document.body,
    'body_hash', document.body_hash,
    'required_from', document.required_from
  )
  INTO v_result
  FROM public.legal_documents document
  WHERE document.document_key = p_document_key
    AND document.locale = v_locale
    AND document.required_from <= clock_timestamp()
  ORDER BY document.required_from DESC, document.created_at DESC, document.id DESC
  LIMIT 1;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'legal_document_not_available' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_mobile_legal_document(
  p_user_id uuid,
  p_document_key text,
  p_version text,
  p_body_hash text,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_request_hash text;
  v_replay jsonb;
  v_locale text;
  v_document public.legal_documents%ROWTYPE;
  v_accepted_at timestamptz;
  v_result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR p_document_key IS NULL
    OR p_version IS NULL
    OR p_body_hash IS NULL THEN
    RAISE EXCEPTION 'invalid_legal_acceptance' USING ERRCODE = '22023';
  END IF;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        p_document_key || ':' || p_version || ':' || p_body_hash,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
  v_replay := private.read_routine_mutation_receipt(
    p_user_id,
    p_idempotency_key,
    'legal_acceptance',
    v_request_hash
  );
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  IF p_document_key !~ '^[a-z][a-z0-9_]{0,99}$'
    OR p_version !~ '^[A-Za-z0-9._-]{1,64}$'
    OR p_body_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_legal_acceptance' USING ERRCODE = '22023';
  END IF;

  SELECT domain_user.locale
  INTO v_locale
  FROM public.users domain_user
  WHERE domain_user.id = p_user_id
    AND domain_user.status = 'active'
    AND domain_user.locale IN ('pt-BR', 'en-US');

  IF v_locale IS NULL THEN
    RAISE EXCEPTION 'legal_document_not_available' USING ERRCODE = 'P0002';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      p_user_id::text || ':legal-acceptance:' || p_document_key,
      0
    )
  );

  LOCK TABLE public.legal_documents IN SHARE MODE;

  SELECT document.*
  INTO v_document
  FROM public.legal_documents document
  WHERE document.document_key = p_document_key
    AND document.locale = v_locale
    AND document.required_from <= clock_timestamp()
  ORDER BY document.required_from DESC, document.created_at DESC, document.id DESC
  LIMIT 1
  FOR KEY SHARE;

  IF NOT FOUND
    OR v_document.version IS DISTINCT FROM p_version
    OR v_document.body_hash IS DISTINCT FROM p_body_hash THEN
    RAISE EXCEPTION 'legal_document_version_mismatch' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.user_legal_acceptances (
    user_id,
    legal_document_id,
    document_key,
    version,
    locale,
    body_hash
  ) VALUES (
    p_user_id,
    v_document.id,
    v_document.document_key,
    v_document.version,
    v_document.locale,
    v_document.body_hash
  )
  ON CONFLICT (user_id, document_key, version) DO NOTHING
  RETURNING accepted_at INTO v_accepted_at;

  IF v_accepted_at IS NULL THEN
    SELECT acceptance.accepted_at
    INTO v_accepted_at
    FROM public.user_legal_acceptances acceptance
    WHERE acceptance.user_id = p_user_id
      AND acceptance.document_key = v_document.document_key
      AND acceptance.version = v_document.version;

    IF v_accepted_at IS NULL THEN
      RAISE EXCEPTION 'legal_document_version_mismatch' USING ERRCODE = '22023';
    END IF;
  END IF;

  v_result := jsonb_build_object(
    'document_key', v_document.document_key,
    'accepted_version', v_document.version,
    'accepted_at', v_accepted_at
  );
  PERFORM private.write_routine_mutation_receipt(
    p_user_id,
    p_idempotency_key,
    'legal_acceptance',
    v_request_hash,
    v_result
  );

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION private.derive_routine_occurrence_key(uuid, timestamptz) IS
  'Canonical SHA-256 occurrence identity from rule UUID and UTC epoch microseconds.';
COMMENT ON FUNCTION private.derive_routine_occurrence_state(
  uuid, uuid, text, text, timestamptz, timestamptz
) IS
  'Derives row-backed or delayed-finalizer routine occurrence state at a trusted instant.';
COMMENT ON FUNCTION public.record_routine_occurrence_action_atomic(
  uuid, uuid, text, uuid, timestamptz, text, timestamptz, timestamptz, text
) IS
  'Appends one exact routine occurrence action after stored-timezone and transition validation.';
