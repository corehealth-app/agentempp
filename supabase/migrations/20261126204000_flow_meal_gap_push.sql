-- Push preferences and notices for the iOS Flow only. No scheduler or send is
-- enabled here. Old WhatsApp and manually scheduled reminders have separate state.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE private.flow_meal_gap_devices (
  device_id uuid PRIMARY KEY REFERENCES public.mobile_devices(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  topic text NOT NULL CHECK (topic ~ '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$' AND length(topic) <= 255),
  daytime_enabled boolean NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX flow_meal_gap_devices_topic_owner
  ON private.flow_meal_gap_devices(topic, user_id, updated_at DESC);
ALTER TABLE private.flow_meal_gap_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.flow_meal_gap_devices FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE private.flow_meal_gap_notices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES public.mobile_devices(id) ON DELETE SET NULL,
  local_date date NOT NULL,
  mode text NOT NULL CHECK (mode IN ('daytime', 'before_close')),
  meal_type public.meal_type_enum NOT NULL CHECK (meal_type::text IN ('cafe','almoco','lanche','jantar','ceia')),
  status text NOT NULL DEFAULT 'claimed'
    CHECK (status IN ('claimed','accepted','retry','rejected','suppressed')),
  claim_id uuid NOT NULL DEFAULT gen_random_uuid(),
  claim_until timestamptz NOT NULL,
  attempt_count smallint NOT NULL CHECK (attempt_count BETWEEN 1 AND 3),
  expires_at timestamptz NOT NULL,
  token_hash text NOT NULL,
  created_at timestamptz NOT NULL,
  accepted_at timestamptz,
  UNIQUE (user_id, local_date, mode, meal_type)
);
CREATE UNIQUE INDEX flow_meal_gap_one_before_close
  ON private.flow_meal_gap_notices(user_id, local_date)
  WHERE mode = 'before_close';
ALTER TABLE private.flow_meal_gap_notices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.flow_meal_gap_notices FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.configure_flow_meal_gap_device(
  p_user_id uuid, p_device_id uuid, p_topic text, p_enabled boolean, p_daytime_enabled boolean
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $$
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_enabled IS NULL OR p_daytime_enabled IS NULL OR p_topic IS NULL THEN
    RAISE EXCEPTION 'invalid flow meal gap preferences' USING ERRCODE = '22023';
  END IF;
  PERFORM 1 FROM public.mobile_devices
    WHERE id = p_device_id AND user_id = p_user_id AND (active OR NOT p_enabled)
    FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF NOT p_enabled THEN
    DELETE FROM private.flow_meal_gap_devices WHERE device_id = p_device_id AND user_id = p_user_id;
  ELSE
    INSERT INTO public.notification_preferences(user_id) VALUES (p_user_id) ON CONFLICT DO NOTHING;
    INSERT INTO private.flow_meal_gap_devices(device_id, user_id, topic, daytime_enabled)
    VALUES (p_device_id, p_user_id, p_topic, p_daytime_enabled)
    ON CONFLICT (device_id) DO UPDATE SET
      user_id = EXCLUDED.user_id, topic = EXCLUDED.topic,
      daytime_enabled = EXCLUDED.daytime_enabled, updated_at = clock_timestamp();
  END IF;
  RETURN true;
END $$;

CREATE FUNCTION public.register_flow_meal_gap_device(
  p_user_id uuid, p_installation_id text, p_apns_environment text, p_apns_token text,
  p_topic text, p_daytime_enabled boolean
) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE device_id uuid;
BEGIN
  PERFORM private.assert_trusted_backend();
  device_id := public.upsert_mobile_device(p_user_id, p_installation_id, p_apns_environment, p_apns_token);
  IF NOT public.configure_flow_meal_gap_device(p_user_id, device_id, p_topic, true, p_daytime_enabled)
    THEN RAISE EXCEPTION 'flow meal gap device changed' USING ERRCODE = '40001'; END IF;
  RETURN device_id;
END $$;

CREATE FUNCTION private.flow_meal_gap_blocked(p_user_id uuid, p_date date, p_timezone text, p_now timestamptz)
RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.daily_snapshots s
    WHERE s.user_id = p_user_id AND s.date = p_date AND s.day_closed
  ) OR EXISTS (
    SELECT 1 FROM private.conversation_intake_ids i
    JOIN private.conversation_intake_inputs x USING (user_id, intake_id)
    LEFT JOIN private.conversation_intake_routing_results r USING (user_id, intake_id)
    WHERE i.user_id = p_user_id AND i.invalidated_at IS NULL
      AND i.admitted_at >= p_now - interval '30 minutes'
      AND i.admitted_at <= p_now
      AND coalesce(x.admitted_local_date, (i.admitted_at AT TIME ZONE p_timezone)::date) = p_date
      AND (
        r.decision IS NULL OR (
          r.decision->>'kind' = 'meal.report'
          AND NOT EXISTS (
            SELECT 1 FROM private.conversation_meal_effects e
            WHERE e.user_id = i.user_id AND e.command_id = i.reserved_child_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM private.conversation_meal_decisions d
            WHERE d.user_id = i.user_id AND d.command_id = i.reserved_child_id
          )
        )
      )
  );
$$;

CREATE FUNCTION private.flow_meal_gap_missing(
  p_user_id uuid, p_date date, p_timezone text, p_meal public.meal_type_enum
) RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.meal_logs l
    WHERE l.user_id = p_user_id AND l.meal_type = p_meal
      AND l.consumed_at >= (p_date::timestamp AT TIME ZONE p_timezone)
      AND l.consumed_at < ((p_date + 1)::timestamp AT TIME ZONE p_timezone)
  ) AND NOT EXISTS (
    SELECT 1 FROM public.product_events e
    WHERE e.user_id = p_user_id AND e.event = 'meal.user_skipped'
      AND e.properties->>'meal_type' = p_meal::text
      AND (
        e.properties->>'local_date' = p_date::text OR (
          e.properties->>'local_date' IS NULL
          AND e.occurred_at >= (p_date::timestamp AT TIME ZONE p_timezone)
          AND e.occurred_at < ((p_date + 1)::timestamp AT TIME ZONE p_timezone)
        )
      )
  );
$$;

-- Only the worker discovers endpoints, and this listing never exposes tokens.
CREATE FUNCTION public.list_flow_meal_gap_targets(p_topic text, p_after uuid, p_limit integer)
RETURNS TABLE(user_id uuid, device_id uuid, timezone text, locale text, daytime_enabled boolean,
              daily_limit integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid flow meal gap batch' USING ERRCODE = '22023';
  END IF;
  RETURN QUERY SELECT DISTINCT ON (s.user_id)
    s.user_id, s.device_id, u.timezone, u.locale, s.daytime_enabled, p.daily_push_limit
  FROM private.flow_meal_gap_devices s
  JOIN public.mobile_devices d ON d.id = s.device_id AND d.user_id = s.user_id AND d.active
  JOIN public.users u ON u.id = s.user_id AND u.status = 'active'
  JOIN pg_catalog.pg_timezone_names z ON z.name = u.timezone
  JOIN public.notification_preferences p ON p.user_id = s.user_id AND p.push_enabled
  WHERE s.topic = p_topic AND p.daily_push_limit > 0
    AND (p_after IS NULL OR s.user_id > p_after)
  ORDER BY s.user_id, s.updated_at DESC, s.device_id
  LIMIT p_limit;
END $$;

-- Snapshot of the app's intake lane and prior accepted notices, without media
-- content, device credentials or the notification text.
CREATE FUNCTION public.read_flow_meal_gap_activity(p_user_id uuid, p_date date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE zone text; now_at timestamptz := statement_timestamp();
BEGIN
  PERFORM private.assert_trusted_backend();
  SELECT u.timezone INTO zone FROM public.users u
    JOIN pg_catalog.pg_timezone_names z ON z.name = u.timezone
    WHERE u.id = p_user_id AND u.status = 'active';
  IF NOT FOUND OR p_date IS DISTINCT FROM (now_at AT TIME ZONE zone)::date THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'blocked', private.flow_meal_gap_blocked(p_user_id, p_date, zone, now_at),
    'last_intake_at', (SELECT max(i.admitted_at) FROM private.conversation_intake_ids i
      WHERE i.user_id = p_user_id AND i.invalidated_at IS NULL
        AND i.admitted_at BETWEEN now_at - interval '1 hour' AND now_at),
    'accepted', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'mode', n.mode, 'meal', n.meal_type, 'at', n.accepted_at) ORDER BY n.accepted_at), '[]'::jsonb)
      FROM private.flow_meal_gap_notices n
      WHERE n.user_id = p_user_id AND n.local_date = p_date AND n.status = 'accepted')
  );
END $$;

-- The scheduler evaluates habits. The transaction reads current facts again
-- immediately before handing out the device token and holds a short lease.
CREATE FUNCTION public.claim_flow_meal_gap_notice(
  p_user_id uuid, p_device_id uuid, p_topic text, p_date date, p_mode text,
  p_meal public.meal_type_enum
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  u public.users%ROWTYPE;
  device public.mobile_devices%ROWTYPE;
  prefs public.notification_preferences%ROWTYPE;
  subscription private.flow_meal_gap_devices%ROWTYPE;
  notice private.flow_meal_gap_notices%ROWTYPE;
  now_at timestamptz := clock_timestamp();
  local_now timestamp;
  local_hour integer;
  due_until timestamptz;
  other_pushes integer;
  flow_pushes integer;
  daytime_pushes integer;
  recent_daytime boolean;
  snapshot public.daily_snapshots%ROWTYPE;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_date IS NULL OR p_mode IS NULL OR p_mode NOT IN ('daytime','before_close')
    OR p_meal IS NULL OR p_meal::text NOT IN ('cafe','almoco','lanche','jantar','ceia') THEN
    RAISE EXCEPTION 'invalid flow meal gap notice' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':reminders:' || p_date::text, 0));
  SELECT * INTO u FROM public.users WHERE id = p_user_id AND status = 'active';
  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = u.timezone)
    THEN RETURN NULL; END IF;
  local_now := now_at AT TIME ZONE u.timezone;
  local_hour := extract(hour FROM local_now)::integer;
  IF local_now::date <> p_date
    OR (p_mode = 'daytime' AND local_hour NOT BETWEEN 10 AND 19)
    OR (p_mode = 'before_close' AND local_hour NOT BETWEEN 21 AND 23)
    THEN RETURN NULL; END IF;

  SELECT * INTO device FROM public.mobile_devices WHERE id = p_device_id AND user_id = p_user_id AND active;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO subscription FROM private.flow_meal_gap_devices
  WHERE device_id = device.id AND user_id = p_user_id AND topic = p_topic;
  IF NOT FOUND OR (p_mode = 'daytime' AND NOT subscription.daytime_enabled) THEN RETURN NULL; END IF;
  SELECT * INTO prefs FROM public.notification_preferences WHERE user_id = p_user_id AND push_enabled;
  IF NOT FOUND OR prefs.daily_push_limit = 0 OR coalesce(
    CASE WHEN prefs.quiet_hours_start <= prefs.quiet_hours_end THEN
      local_now::time >= prefs.quiet_hours_start AND local_now::time < prefs.quiet_hours_end
    ELSE local_now::time >= prefs.quiet_hours_start OR local_now::time < prefs.quiet_hours_end END, false
  ) THEN RETURN NULL; END IF;

  IF NOT coalesce((public.resolve_user_entitlement(p_user_id, 'bodyflow_full', now_at)->>'has_active_access')::boolean, false)
    OR private.flow_meal_gap_blocked(p_user_id, p_date, u.timezone, now_at)
    OR NOT private.flow_meal_gap_missing(p_user_id, p_date, u.timezone, p_meal)
    THEN RETURN NULL; END IF;

  IF p_mode = 'daytime' THEN
    SELECT * INTO snapshot FROM public.daily_snapshots WHERE user_id = p_user_id AND date = p_date;
    IF NOT FOUND OR snapshot.protein_target IS NULL OR snapshot.protein_target <= 0
      OR snapshot.protein_g IS NULL OR snapshot.protein_g >= snapshot.protein_target * 0.6
      OR EXISTS (SELECT 1 FROM public.meal_logs l WHERE l.user_id = p_user_id AND l.created_at > now_at - interval '4 hours')
      OR EXISTS (SELECT 1 FROM private.conversation_intake_ids i WHERE i.user_id = p_user_id
                 AND i.invalidated_at IS NULL AND i.admitted_at > now_at - interval '1 hour')
      THEN RETURN NULL; END IF;
  END IF;

  SELECT * INTO notice FROM private.flow_meal_gap_notices
    WHERE user_id = p_user_id AND local_date = p_date AND mode = p_mode
      AND (p_mode = 'before_close' OR meal_type = p_meal)
    FOR UPDATE;
  SELECT count(*) INTO other_pushes FROM public.reminder_events e
  WHERE e.user_id = p_user_id AND e.status = 'queued'
    AND (e.scheduled_for AT TIME ZONE u.timezone)::date = p_date;
  SELECT count(*), count(*) FILTER (WHERE n.mode = 'daytime'),
    coalesce(bool_or(n.mode = 'daytime' AND n.created_at > now_at - interval '4 hours'), false)
  INTO flow_pushes, daytime_pushes, recent_daytime FROM private.flow_meal_gap_notices n
  WHERE n.user_id = p_user_id AND n.local_date = p_date
    AND n.id IS DISTINCT FROM notice.id AND n.status IN ('claimed','retry','accepted');
  IF flow_pushes + other_pushes >= prefs.daily_push_limit
    OR (p_mode = 'daytime' AND (daytime_pushes >= 2 OR recent_daytime))
    THEN RETURN NULL; END IF;

  IF notice.id IS NOT NULL THEN
    IF notice.status NOT IN ('retry','claimed') OR notice.claim_until > now_at
      OR notice.attempt_count >= 3 OR notice.expires_at <= now_at
      OR notice.device_id IS DISTINCT FROM device.id OR notice.token_hash <> device.apns_token_hash
      OR notice.meal_type <> p_meal
      THEN RETURN NULL; END IF;
    UPDATE private.flow_meal_gap_notices SET status = 'claimed', claim_id = gen_random_uuid(),
      claim_until = now_at + interval '2 minutes', attempt_count = attempt_count + 1
      WHERE id = notice.id RETURNING * INTO notice;
  ELSE
    due_until := least(
      now_at + interval '2 hours',
      ((p_date + CASE WHEN p_mode = 'before_close' THEN 1 ELSE 0 END)::timestamp +
        CASE WHEN p_mode = 'before_close' THEN interval '0 hours' ELSE interval '20 hours' END)
        AT TIME ZONE u.timezone
    );
    INSERT INTO private.flow_meal_gap_notices(user_id, device_id, local_date, mode, meal_type,
      claim_until, attempt_count, expires_at, token_hash, created_at)
    VALUES (p_user_id, device.id, p_date, p_mode, p_meal, now_at + interval '2 minutes',
      1, due_until, device.apns_token_hash, now_at) RETURNING * INTO notice;
  END IF;

  RETURN jsonb_build_object('id', notice.id, 'claim_id', notice.claim_id, 'token', device.apns_token,
    'environment', device.apns_environment,
    'expires_at', least(notice.expires_at, now_at + interval '10 minutes'));
END $$;

CREATE FUNCTION public.finish_flow_meal_gap_notice(p_id uuid, p_claim_id uuid, p_outcome text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE notice private.flow_meal_gap_notices%ROWTYPE;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_outcome IS NULL OR p_outcome NOT IN ('accepted','retry','unregistered','rejected','expired') THEN
    RAISE EXCEPTION 'invalid flow meal gap delivery outcome' USING ERRCODE = '22023';
  END IF;
  UPDATE private.flow_meal_gap_notices SET
    status = CASE WHEN p_outcome IN ('unregistered','rejected') THEN 'rejected'
      WHEN p_outcome = 'expired' THEN 'suppressed' ELSE p_outcome END,
    accepted_at = CASE WHEN p_outcome = 'accepted' THEN clock_timestamp() ELSE NULL END
  WHERE id = p_id AND claim_id = p_claim_id AND status = 'claimed'
    RETURNING * INTO notice;
  IF NOT FOUND THEN RETURN false; END IF;
  IF p_outcome = 'unregistered' THEN
    UPDATE public.mobile_devices SET active = false, updated_at = clock_timestamp()
      WHERE id = notice.device_id AND user_id = notice.user_id AND apns_token_hash = notice.token_hash;
  END IF;
  RETURN true;
END $$;

REVOKE ALL ON FUNCTION private.flow_meal_gap_blocked(uuid,date,text,timestamptz),
  private.flow_meal_gap_missing(uuid,date,text,public.meal_type_enum)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.configure_flow_meal_gap_device(uuid,uuid,text,boolean,boolean),
  public.list_flow_meal_gap_targets(text,uuid,integer),
  public.register_flow_meal_gap_device(uuid,text,text,text,text,boolean),
  public.read_flow_meal_gap_activity(uuid,date),
  public.claim_flow_meal_gap_notice(uuid,uuid,text,date,text,public.meal_type_enum),
  public.finish_flow_meal_gap_notice(uuid,uuid,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.configure_flow_meal_gap_device(uuid,uuid,text,boolean,boolean),
  public.list_flow_meal_gap_targets(text,uuid,integer),
  public.register_flow_meal_gap_device(uuid,text,text,text,text,boolean),
  public.read_flow_meal_gap_activity(uuid,date),
  public.claim_flow_meal_gap_notice(uuid,uuid,text,date,text,public.meal_type_enum),
  public.finish_flow_meal_gap_notice(uuid,uuid,text) TO service_role;
COMMIT;
