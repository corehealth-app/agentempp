CREATE TABLE public.mobile_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  installation_id text NOT NULL,
  platform text NOT NULL DEFAULT 'ios',
  apns_environment text NOT NULL,
  apns_token text NOT NULL,
  apns_token_hash text GENERATED ALWAYS AS (
    encode(extensions.digest(apns_token, 'sha256'), 'hex')
  ) STORED,
  active boolean NOT NULL DEFAULT true,
  last_seen_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT mobile_devices_id_user_unique UNIQUE (id, user_id),
  CONSTRAINT mobile_devices_installation_unique UNIQUE (installation_id),
  CONSTRAINT mobile_devices_platform_check CHECK (platform = 'ios'),
  CONSTRAINT mobile_devices_environment_check CHECK (apns_environment IN ('sandbox', 'production')),
  CONSTRAINT mobile_devices_installation_check CHECK (char_length(installation_id) BETWEEN 1 AND 128),
  CONSTRAINT mobile_devices_token_check CHECK (
    char_length(apns_token) BETWEEN 64 AND 512
    AND char_length(apns_token) % 2 = 0
    AND apns_token ~ '^[0-9A-Fa-f]+$'
    AND apns_token = lower(apns_token)
  ),
  CONSTRAINT mobile_devices_token_hash_check CHECK (apns_token_hash ~ '^[0-9a-f]{64}$')
);

CREATE UNIQUE INDEX mobile_devices_active_token_hash_unique
  ON public.mobile_devices (apns_token_hash)
  WHERE active;
CREATE INDEX mobile_devices_user_active_idx
  ON public.mobile_devices (user_id, updated_at DESC)
  WHERE active;

CREATE TABLE public.notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  push_enabled boolean NOT NULL DEFAULT true,
  quiet_hours_start time,
  quiet_hours_end time,
  daily_push_limit integer NOT NULL DEFAULT 8,
  hydration_target_ml integer,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT notification_preferences_quiet_hours_pair_check CHECK (
    (quiet_hours_start IS NULL) = (quiet_hours_end IS NULL)
    AND (quiet_hours_start IS NULL OR quiet_hours_start <> quiet_hours_end)
  ),
  CONSTRAINT notification_preferences_daily_limit_check CHECK (daily_push_limit BETWEEN 0 AND 20),
  CONSTRAINT notification_preferences_hydration_target_check CHECK (
    hydration_target_ml IS NULL OR hydration_target_ml BETWEEN 250 AND 10000
  )
);

CREATE TABLE public.routine_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  item_type text NOT NULL,
  name text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT routine_items_id_user_type_unique UNIQUE (id, user_id, item_type),
  CONSTRAINT routine_items_type_check CHECK (item_type IN ('supplement', 'medication')),
  CONSTRAINT routine_items_name_check CHECK (char_length(btrim(name)) BETWEEN 1 AND 200)
);

CREATE INDEX routine_items_user_active_idx
  ON public.routine_items (user_id, item_type, updated_at DESC)
  WHERE active;

CREATE TABLE public.reminder_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  routine_item_id uuid,
  category text NOT NULL,
  meal_type text,
  local_time time NOT NULL,
  weekdays smallint[] NOT NULL,
  active boolean NOT NULL DEFAULT true,
  template_key text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT reminder_rules_id_user_unique UNIQUE (id, user_id),
  CONSTRAINT reminder_rules_item_owner_type_fkey FOREIGN KEY (routine_item_id, user_id, category)
    REFERENCES public.routine_items(id, user_id, item_type) ON DELETE RESTRICT,
  CONSTRAINT reminder_rules_category_check CHECK (
    category IN (
      'meal', 'hydration', 'supplement', 'medication',
      'workout', 'reevaluation', 'content', 'reengagement'
    )
  ),
  CONSTRAINT reminder_rules_weekdays_check CHECK (
    cardinality(weekdays) BETWEEN 1 AND 7
    AND weekdays <@ ARRAY[0, 1, 2, 3, 4, 5, 6]::smallint[]
  ),
  CONSTRAINT reminder_rules_item_category_check CHECK (
    (category IN ('supplement', 'medication') AND routine_item_id IS NOT NULL)
    OR (category NOT IN ('supplement', 'medication') AND routine_item_id IS NULL)
  ),
  CONSTRAINT reminder_rules_meal_type_check CHECK (
    (category = 'meal' AND meal_type IN ('cafe', 'almoco', 'lanche', 'jantar', 'ceia'))
    OR (category <> 'meal' AND meal_type IS NULL)
  ),
  CONSTRAINT reminder_rules_template_key_check CHECK (
    template_key IS NULL OR char_length(template_key) BETWEEN 1 AND 100
  )
);

CREATE INDEX reminder_rules_active_schedule_idx
  ON public.reminder_rules (local_time, id)
  WHERE active;
CREATE INDEX reminder_rules_user_idx
  ON public.reminder_rules (user_id, updated_at DESC);

CREATE TABLE public.hydration_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  local_date date NOT NULL,
  amount_ml integer NOT NULL,
  idempotency_key text NOT NULL,
  occurred_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT hydration_logs_user_idempotency_unique UNIQUE (user_id, idempotency_key),
  CONSTRAINT hydration_logs_amount_check CHECK (amount_ml BETWEEN 1 AND 5000),
  CONSTRAINT hydration_logs_idempotency_check CHECK (
    char_length(idempotency_key) BETWEEN 8 AND 128
    AND idempotency_key ~ '^[A-Za-z0-9._:-]+$'
  )
);

CREATE INDEX hydration_logs_user_date_idx
  ON public.hydration_logs (user_id, local_date, occurred_at DESC);

CREATE TABLE public.routine_adherence_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  routine_item_id uuid NOT NULL,
  item_type text NOT NULL,
  status text NOT NULL DEFAULT 'taken',
  idempotency_key text NOT NULL,
  scheduled_for timestamptz,
  occurred_at timestamptz NOT NULL,
  snoozed_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT routine_adherence_logs_item_owner_type_fkey FOREIGN KEY (
    routine_item_id,
    user_id,
    item_type
  ) REFERENCES public.routine_items(id, user_id, item_type) ON DELETE RESTRICT,
  CONSTRAINT routine_adherence_logs_user_idempotency_unique UNIQUE (user_id, idempotency_key),
  CONSTRAINT routine_adherence_logs_type_check CHECK (item_type IN ('supplement', 'medication')),
  CONSTRAINT routine_adherence_logs_status_check CHECK (
    status IN ('taken', 'snoozed', 'skipped', 'missed')
  ),
  CONSTRAINT routine_adherence_logs_snooze_check CHECK (
    (status = 'snoozed' AND snoozed_until IS NOT NULL AND snoozed_until > occurred_at)
    OR (status <> 'snoozed' AND snoozed_until IS NULL)
  ),
  CONSTRAINT routine_adherence_logs_idempotency_check CHECK (
    char_length(idempotency_key) BETWEEN 8 AND 128
    AND idempotency_key ~ '^[A-Za-z0-9._:-]+$'
  )
);

CREATE INDEX routine_adherence_logs_item_occurred_idx
  ON public.routine_adherence_logs (routine_item_id, occurred_at DESC);

CREATE TABLE public.reminder_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reminder_rule_id uuid NOT NULL,
  scheduled_for timestamptz NOT NULL,
  status text NOT NULL,
  suppression_reason text,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT reminder_events_id_user_unique UNIQUE (id, user_id),
  CONSTRAINT reminder_events_rule_owner_fkey FOREIGN KEY (reminder_rule_id, user_id)
    REFERENCES public.reminder_rules(id, user_id) ON DELETE RESTRICT,
  CONSTRAINT reminder_events_rule_schedule_unique UNIQUE (reminder_rule_id, scheduled_for),
  CONSTRAINT reminder_events_status_check CHECK (status IN ('queued', 'suppressed', 'resolved')),
  CONSTRAINT reminder_events_suppression_check CHECK (
    (status = 'suppressed' AND suppression_reason IS NOT NULL)
    OR (status <> 'suppressed' AND suppression_reason IS NULL)
  ),
  CONSTRAINT reminder_events_resolved_check CHECK (
    (status = 'resolved' AND resolved_at IS NOT NULL)
    OR (status <> 'resolved' AND resolved_at IS NULL)
  )
);

CREATE INDEX reminder_events_user_scheduled_idx
  ON public.reminder_events (user_id, scheduled_for DESC);
CREATE INDEX reminder_events_queue_idx
  ON public.reminder_events (scheduled_for)
  WHERE status = 'queued';

CREATE TABLE public.notification_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reminder_event_id uuid NOT NULL,
  mobile_device_id uuid NOT NULL,
  channel text NOT NULL,
  provider text NOT NULL,
  template_key text NOT NULL,
  personality text NOT NULL,
  status text NOT NULL DEFAULT 'queued',
  scheduled_for timestamptz NOT NULL,
  attempt_count integer NOT NULL DEFAULT 0,
  provider_message_id text,
  error_code text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT notification_deliveries_event_device_unique UNIQUE (
    reminder_event_id,
    mobile_device_id
  ),
  CONSTRAINT notification_deliveries_event_owner_fkey FOREIGN KEY (reminder_event_id, user_id)
    REFERENCES public.reminder_events(id, user_id) ON DELETE RESTRICT,
  CONSTRAINT notification_deliveries_device_owner_fkey FOREIGN KEY (mobile_device_id, user_id)
    REFERENCES public.mobile_devices(id, user_id) ON DELETE RESTRICT,
  CONSTRAINT notification_deliveries_channel_check CHECK (channel = 'push'),
  CONSTRAINT notification_deliveries_provider_check CHECK (provider = 'apns'),
  CONSTRAINT notification_deliveries_template_key_check CHECK (char_length(template_key) BETWEEN 1 AND 100),
  CONSTRAINT notification_deliveries_personality_check CHECK (char_length(personality) BETWEEN 1 AND 100),
  CONSTRAINT notification_deliveries_status_check CHECK (
    status IN ('queued', 'sent', 'failed', 'cancelled')
  ),
  CONSTRAINT notification_deliveries_attempt_count_check CHECK (attempt_count >= 0),
  CONSTRAINT notification_deliveries_error_check CHECK (
    (status = 'failed' AND error_code IS NOT NULL)
    OR (status <> 'failed' AND error_code IS NULL)
  )
);

CREATE INDEX notification_deliveries_user_scheduled_idx
  ON public.notification_deliveries (user_id, scheduled_for DESC)
  WHERE status = 'queued';

ALTER TABLE public.mobile_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reminder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hydration_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_adherence_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reminder_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.mobile_devices,
  public.notification_preferences,
  public.reminder_rules,
  public.routine_items,
  public.hydration_logs,
  public.routine_adherence_logs,
  public.reminder_events,
  public.notification_deliveries
FROM PUBLIC, anon, authenticated;

GRANT SELECT (
  id, user_id, installation_id, apns_environment, active, last_seen_at, created_at, updated_at
) ON public.mobile_devices TO authenticated;
GRANT SELECT ON TABLE
  public.notification_preferences,
  public.reminder_rules,
  public.routine_items,
  public.hydration_logs,
  public.routine_adherence_logs
TO authenticated;
GRANT ALL ON TABLE
  public.mobile_devices,
  public.notification_preferences,
  public.reminder_rules,
  public.routine_items,
  public.hydration_logs,
  public.routine_adherence_logs,
  public.reminder_events,
  public.notification_deliveries
TO service_role;

CREATE POLICY mobile_devices_patient_own_read
  ON public.mobile_devices FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.users domain_user
    WHERE domain_user.id = mobile_devices.user_id
      AND domain_user.auth_user_id = (SELECT auth.uid())
  ));

CREATE POLICY notification_preferences_patient_own_read
  ON public.notification_preferences FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.users domain_user
    WHERE domain_user.id = notification_preferences.user_id
      AND domain_user.auth_user_id = (SELECT auth.uid())
  ));

CREATE POLICY reminder_rules_patient_own_read
  ON public.reminder_rules FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.users domain_user
    WHERE domain_user.id = reminder_rules.user_id
      AND domain_user.auth_user_id = (SELECT auth.uid())
  ));

CREATE POLICY routine_items_patient_own_read
  ON public.routine_items FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.users domain_user
    WHERE domain_user.id = routine_items.user_id
      AND domain_user.auth_user_id = (SELECT auth.uid())
  ));

CREATE POLICY hydration_logs_patient_own_read
  ON public.hydration_logs FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.users domain_user
    WHERE domain_user.id = hydration_logs.user_id
      AND domain_user.auth_user_id = (SELECT auth.uid())
  ));

CREATE POLICY routine_adherence_logs_patient_own_read
  ON public.routine_adherence_logs FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.users domain_user
    WHERE domain_user.id = routine_adherence_logs.user_id
      AND domain_user.auth_user_id = (SELECT auth.uid())
  ));

CREATE OR REPLACE FUNCTION public.upsert_mobile_device(
  p_user_id uuid,
  p_installation_id text,
  p_apns_environment text,
  p_apns_token text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_device_id uuid;
  v_installation_id text := NULLIF(btrim(p_installation_id), '');
  v_apns_token text := lower(p_apns_token);
  v_token_hash text;
  v_existing_user_id uuid;
  v_existing_token_hash text;
  v_existing_active boolean;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL
    OR v_installation_id IS NULL
    OR p_apns_environment NOT IN ('sandbox', 'production')
    OR v_apns_token IS NULL
    OR v_apns_token !~ '^[0-9a-f]+$'
    OR char_length(v_apns_token) NOT BETWEEN 64 AND 512
    OR char_length(v_apns_token) % 2 <> 0 THEN
    RAISE EXCEPTION 'invalid mobile device payload' USING ERRCODE = '22023';
  END IF;

  v_token_hash := encode(extensions.digest(v_apns_token, 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_token_hash || ':apns-token', 0));
  PERFORM pg_advisory_xact_lock(hashtextextended(v_installation_id || ':installation', 0));

  SELECT user_id, apns_token_hash, active
  INTO v_existing_user_id, v_existing_token_hash, v_existing_active
  FROM public.mobile_devices
  WHERE installation_id = v_installation_id
  FOR UPDATE;

  IF FOUND
    AND v_existing_user_id <> p_user_id
    AND v_existing_active
    AND v_existing_token_hash <> v_token_hash THEN
    RAISE EXCEPTION 'active installation belongs to another user' USING ERRCODE = '23505';
  END IF;

  UPDATE public.mobile_devices
  SET active = false,
      updated_at = clock_timestamp()
  WHERE apns_token_hash = v_token_hash
    AND installation_id <> v_installation_id
    AND active;

  INSERT INTO public.mobile_devices (
    user_id,
    installation_id,
    platform,
    apns_environment,
    apns_token,
    active,
    last_seen_at,
    updated_at
  ) VALUES (
    p_user_id,
    v_installation_id,
    'ios',
    p_apns_environment,
    v_apns_token,
    true,
    clock_timestamp(),
    clock_timestamp()
  )
  ON CONFLICT (installation_id) DO UPDATE
  SET user_id = EXCLUDED.user_id,
      platform = 'ios',
      apns_environment = EXCLUDED.apns_environment,
      apns_token = EXCLUDED.apns_token,
      active = true,
      last_seen_at = EXCLUDED.last_seen_at,
      updated_at = EXCLUDED.updated_at
  RETURNING id INTO v_device_id;

  RETURN v_device_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.deactivate_mobile_device(
  p_user_id uuid,
  p_device_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.mobile_devices
  SET active = false,
      updated_at = clock_timestamp()
  WHERE id = p_device_id
    AND user_id = p_user_id
    AND active;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_hydration_atomic(
  p_user_id uuid,
  p_local_date date,
  p_amount_ml integer,
  p_idempotency_key text,
  p_occurred_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_existing record;
  v_log_id uuid;
  v_timezone text;
  v_water_ml integer;
BEGIN
  PERFORM private.assert_trusted_backend();

  SELECT timezone
  INTO v_timezone
  FROM public.users
  WHERE id = p_user_id
    AND status = 'active';

  IF v_timezone IS NULL
    OR p_local_date IS NULL
    OR NOT (p_amount_ml BETWEEN 1 AND 5000)
    OR p_idempotency_key IS NULL
    OR p_occurred_at IS NULL
    OR timezone(v_timezone, p_occurred_at)::date <> p_local_date THEN
    RAISE EXCEPTION 'invalid hydration payload' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':hydration:' || p_local_date::text, 0)
  );

  SELECT *
  INTO v_existing
  FROM public.hydration_logs
  WHERE user_id = p_user_id
    AND idempotency_key = p_idempotency_key;

  IF FOUND THEN
    IF v_existing.local_date <> p_local_date
      OR v_existing.amount_ml <> p_amount_ml
      OR v_existing.occurred_at <> p_occurred_at THEN
      RAISE EXCEPTION 'hydration idempotency key conflict' USING ERRCODE = '23505';
    END IF;

    SELECT water_consumed_ml
    INTO v_water_ml
    FROM public.daily_snapshots
    WHERE user_id = p_user_id
      AND date = p_local_date;

    RETURN jsonb_build_object(
      'inserted', false,
      'hydration_log_id', v_existing.id,
      'water_consumed_ml', COALESCE(v_water_ml, 0)
    );
  END IF;

  INSERT INTO public.hydration_logs (
    user_id,
    local_date,
    amount_ml,
    idempotency_key,
    occurred_at
  ) VALUES (
    p_user_id,
    p_local_date,
    p_amount_ml,
    p_idempotency_key,
    p_occurred_at
  )
  RETURNING id INTO v_log_id;

  INSERT INTO public.daily_snapshots (user_id, date, water_consumed_ml, updated_at)
  VALUES (p_user_id, p_local_date, p_amount_ml, clock_timestamp())
  ON CONFLICT (user_id, date) DO UPDATE
  SET water_consumed_ml = public.daily_snapshots.water_consumed_ml + EXCLUDED.water_consumed_ml,
      updated_at = clock_timestamp()
  RETURNING water_consumed_ml INTO v_water_ml;

  RETURN jsonb_build_object(
    'inserted', true,
    'hydration_log_id', v_log_id,
    'water_consumed_ml', v_water_ml
  );
END;
$$;
