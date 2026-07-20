-- Connect the app-first reminder outbox to immutable BodyFlow coach copy.
-- Existing legacy rows remain readable; every new catalog-backed row is fully linked.

ALTER TABLE public.coach_message_usage
  ADD CONSTRAINT coach_message_usage_id_user_version_unique
  UNIQUE (id, user_id, template_version_id);

ALTER TABLE public.notification_deliveries
  ADD COLUMN coach_message_usage_id uuid,
  ADD COLUMN coach_template_version_id uuid,
  ADD COLUMN locale text,
  ADD CONSTRAINT notification_deliveries_coach_version_fkey
    FOREIGN KEY (coach_template_version_id)
    REFERENCES public.coach_message_template_versions(id)
    ON DELETE RESTRICT,
  ADD CONSTRAINT notification_deliveries_coach_usage_owner_version_fkey
    FOREIGN KEY (coach_message_usage_id, user_id, coach_template_version_id)
    REFERENCES public.coach_message_usage(id, user_id, template_version_id)
    ON DELETE RESTRICT,
  ADD CONSTRAINT notification_deliveries_locale_check
    CHECK (locale IS NULL OR locale IN ('pt-BR', 'en-US')) NOT VALID,
  ADD CONSTRAINT notification_deliveries_coach_catalog_shape_check
    CHECK (
      (
        personality = 'default'
        AND coach_message_usage_id IS NULL
        AND coach_template_version_id IS NULL
        AND locale IS NULL
      ) OR (
        personality IN ('balanced', 'focus', 'impulse', 'zen')
        AND coach_message_usage_id IS NOT NULL
        AND coach_template_version_id IS NOT NULL
        AND locale IN ('pt-BR', 'en-US')
      )
    ) NOT VALID;

ALTER TABLE public.notification_deliveries
  DROP CONSTRAINT notification_deliveries_personality_check,
  ADD CONSTRAINT notification_deliveries_personality_check
    CHECK (personality IN ('default', 'balanced', 'focus', 'impulse', 'zen')) NOT VALID;

CREATE INDEX notification_deliveries_coach_usage_idx
  ON public.notification_deliveries (coach_message_usage_id)
  WHERE coach_message_usage_id IS NOT NULL;

CREATE INDEX notification_deliveries_coach_version_idx
  ON public.notification_deliveries (coach_template_version_id)
  WHERE coach_template_version_id IS NOT NULL;

COMMENT ON COLUMN public.notification_deliveries.coach_message_usage_id IS
  'One deterministic coach selection shared by every device delivery for the reminder event.';
COMMENT ON COLUMN public.notification_deliveries.coach_template_version_id IS
  'Immutable catalog version selected before the provider outbox row is queued.';
COMMENT ON COLUMN public.notification_deliveries.locale IS
  'Exact supported locale used for the immutable coach catalog selection.';

-- Integrated reminders already have one selected push usage. Count their queued
-- event only when it is legacy and therefore has no linked usage row.
CREATE OR REPLACE FUNCTION private.claim_coach_message_unchecked(
  p_user_id uuid,
  p_context text,
  p_channel text,
  p_locale text,
  p_event_key text,
  p_available_variables text[],
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, extensions, pg_temp
AS $$
DECLARE
  v_event_key_hash text;
  v_timezone text;
  v_local_date date;
  v_requested_personality text;
  v_effective_personality text;
  v_reason text;
  v_pack_id uuid;
  v_policy public.coach_message_context_policies%ROWTYPE;
  v_candidate record;
  v_usage_id uuid;
  v_result jsonb;
  v_latest_at timestamptz;
  v_selected_today integer;
  v_global_push_limit integer := 8;
  v_push_enabled boolean := true;
  v_global_push_count integer := 0;
  v_available_variables text[] := ARRAY[]::text[];
BEGIN
  IF p_user_id IS NULL
    OR p_context IS NULL
    OR p_channel IS NULL
    OR p_locale IS NULL
    OR p_event_key IS NULL
    OR p_now IS NULL
    OR char_length(btrim(p_event_key)) NOT BETWEEN 1 AND 512 THEN
    RAISE EXCEPTION 'valid user, context, channel, locale, event key, and time are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_locale NOT IN ('pt-BR', 'en-US') THEN
    RAISE EXCEPTION 'unsupported coach locale' USING ERRCODE = '22023';
  END IF;

  IF p_available_variables IS NOT NULL AND EXISTS (
    SELECT 1
    FROM unnest(p_available_variables) variable(name)
    WHERE variable.name !~ '^[a-z][a-z0-9_]*$'
  ) THEN
    RAISE EXCEPTION 'available variable names are invalid' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT variable.name ORDER BY variable.name), ARRAY[]::text[])
  INTO v_available_variables
  FROM unnest(COALESCE(p_available_variables, ARRAY[]::text[])) variable(name);

  SELECT domain_user.timezone
  INTO v_timezone
  FROM public.users domain_user
  WHERE domain_user.id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'domain user not found' USING ERRCODE = '23503';
  END IF;

  v_timezone := COALESCE(NULLIF(v_timezone, ''), 'UTC');
  v_local_date := timezone(v_timezone, p_now)::date;
  v_event_key_hash := encode(extensions.digest(btrim(p_event_key), 'sha256'), 'hex');

  SELECT *
  INTO v_policy
  FROM public.coach_message_context_policies policy
  WHERE policy.context = p_context
    AND policy.channel = p_channel;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unsupported coach context or channel' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(preference.personality_code, 'balanced')
  INTO v_requested_personality
  FROM (SELECT 1) singleton
  LEFT JOIN public.user_coach_preferences preference
    ON preference.user_id = p_user_id;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      concat_ws(':', 'coach-claim', p_user_id::text, p_context, p_channel),
      0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM public.coach_message_usage usage
    WHERE usage.user_id = p_user_id
      AND usage.context = p_context
      AND usage.channel = p_channel
      AND usage.event_key_hash = v_event_key_hash
      AND usage.locale <> p_locale
  ) THEN
    RAISE EXCEPTION 'event key was already claimed with another locale'
      USING ERRCODE = '23514';
  END IF;

  SELECT jsonb_build_object(
    'usage_id', usage.id,
    'outcome', usage.outcome,
    'reason', usage.reason,
    'pack_id', usage.pack_id,
    'template_id', usage.template_id,
    'template_version_id', usage.template_version_id,
    'requested_personality', usage.requested_personality,
    'effective_personality', usage.effective_personality,
    'context', usage.context,
    'channel', usage.channel,
    'locale', usage.locale,
    'title', version.title,
    'subject', version.subject,
    'body', version.body,
    'allowed_variables', COALESCE(to_jsonb(template.allowed_variables), '[]'::jsonb),
    'required_variables', COALESCE(to_jsonb(template.required_variables), '[]'::jsonb),
    'occurred_at', usage.occurred_at,
    'idempotent_replay', true
  )
  INTO v_result
  FROM public.coach_message_usage usage
  LEFT JOIN public.coach_message_template_versions version
    ON version.id = usage.template_version_id
  LEFT JOIN public.coach_message_templates template
    ON template.id = usage.template_id
  WHERE usage.user_id = p_user_id
    AND usage.context = p_context
    AND usage.channel = p_channel
    AND usage.event_key_hash = v_event_key_hash;

  IF v_result IS NOT NULL THEN
    RETURN v_result;
  END IF;

  SELECT pack.id
  INTO v_pack_id
  FROM public.coach_content_packs pack
  WHERE pack.status = 'active';

  IF NOT v_policy.delivery_enabled THEN
    INSERT INTO public.coach_message_usage (
      user_id, pack_id, context, channel, locale,
      requested_personality, effective_personality, outcome, reason,
      event_key_hash, local_date, occurred_at
    ) VALUES (
      p_user_id, v_pack_id, p_context, p_channel, p_locale,
      v_requested_personality, v_requested_personality, 'suppressed', 'delivery_disabled',
      v_event_key_hash, v_local_date, p_now
    ) RETURNING id INTO v_usage_id;

    RETURN jsonb_build_object(
      'usage_id', v_usage_id,
      'outcome', 'suppressed',
      'reason', 'delivery_disabled',
      'pack_id', v_pack_id,
      'requested_personality', v_requested_personality,
      'effective_personality', v_requested_personality,
      'context', p_context,
      'channel', p_channel,
      'locale', p_locale,
      'idempotent_replay', false
    );
  END IF;

  IF v_pack_id IS NULL THEN
    INSERT INTO public.coach_message_usage (
      user_id, context, channel, locale,
      requested_personality, effective_personality, outcome, reason,
      event_key_hash, local_date, occurred_at
    ) VALUES (
      p_user_id, p_context, p_channel, p_locale,
      v_requested_personality, v_requested_personality, 'failed', 'catalog_incomplete',
      v_event_key_hash, v_local_date, p_now
    ) RETURNING id INTO v_usage_id;

    RETURN jsonb_build_object(
      'usage_id', v_usage_id,
      'outcome', 'failed',
      'reason', 'catalog_incomplete',
      'requested_personality', v_requested_personality,
      'effective_personality', v_requested_personality,
      'context', p_context,
      'channel', p_channel,
      'locale', p_locale,
      'idempotent_replay', false
    );
  END IF;

  SELECT
    template.id AS template_id,
    version.id AS template_version_id,
    template.personality_code,
    template.allowed_variables,
    template.required_variables,
    version.title,
    version.subject,
    version.body
  INTO v_candidate
  FROM public.coach_content_pack_entries entry
  JOIN public.coach_message_templates template ON template.id = entry.template_id
  JOIN public.coach_message_template_versions version
    ON version.id = entry.template_version_id
    AND version.template_id = template.id
  WHERE entry.pack_id = v_pack_id
    AND version.status = 'active'
    AND template.context = p_context
    AND template.channel = p_channel
    AND template.locale = p_locale
    AND template.personality_code IN (v_requested_personality, 'balanced')
    AND template.required_variables <@ v_available_variables
  ORDER BY
    CASE WHEN template.personality_code = v_requested_personality THEN 0 ELSE 1 END,
    CASE WHEN template.id = (
      SELECT previous_usage.template_id
      FROM public.coach_message_usage previous_usage
      JOIN public.coach_message_templates previous_template
        ON previous_template.id = previous_usage.template_id
      WHERE previous_usage.user_id = p_user_id
        AND previous_usage.outcome = 'selected'
        AND previous_usage.context = p_context
        AND previous_usage.channel = p_channel
        AND previous_usage.locale = p_locale
        AND previous_template.personality_code = template.personality_code
      ORDER BY previous_usage.occurred_at DESC, previous_usage.id DESC
      LIMIT 1
    ) THEN 1 ELSE 0 END,
    (
      SELECT max(previous_usage.occurred_at)
      FROM public.coach_message_usage previous_usage
      WHERE previous_usage.user_id = p_user_id
        AND previous_usage.outcome = 'selected'
        AND previous_usage.template_id = template.id
    ) ASC NULLS FIRST,
    template.variant,
    template.template_key
  LIMIT 1;

  IF v_candidate.template_id IS NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.coach_content_pack_entries entry
      JOIN public.coach_message_templates template ON template.id = entry.template_id
      JOIN public.coach_message_template_versions version
        ON version.id = entry.template_version_id
      WHERE entry.pack_id = v_pack_id
        AND version.status = 'active'
        AND template.context = p_context
        AND template.channel = p_channel
        AND template.locale = p_locale
        AND template.personality_code IN (v_requested_personality, 'balanced')
    ) THEN
      v_reason := 'missing_variables';
    ELSE
      v_reason := 'catalog_incomplete';
    END IF;

    INSERT INTO public.coach_message_usage (
      user_id, pack_id, context, channel, locale,
      requested_personality, effective_personality, outcome, reason,
      event_key_hash, local_date, occurred_at
    ) VALUES (
      p_user_id, v_pack_id, p_context, p_channel, p_locale,
      v_requested_personality, v_requested_personality, 'failed', v_reason,
      v_event_key_hash, v_local_date, p_now
    ) RETURNING id INTO v_usage_id;

    RETURN jsonb_build_object(
      'usage_id', v_usage_id,
      'outcome', 'failed',
      'reason', v_reason,
      'pack_id', v_pack_id,
      'requested_personality', v_requested_personality,
      'effective_personality', v_requested_personality,
      'context', p_context,
      'channel', p_channel,
      'locale', p_locale,
      'idempotent_replay', false
    );
  END IF;

  v_effective_personality := v_candidate.personality_code;
  v_reason := CASE
    WHEN v_effective_personality = v_requested_personality THEN 'exact'
    ELSE 'balanced_fallback'
  END;

  IF p_channel = 'push' THEN
    SELECT preference.push_enabled, preference.daily_push_limit
    INTO v_push_enabled, v_global_push_limit
    FROM public.notification_preferences preference
    WHERE preference.user_id = p_user_id;

    v_push_enabled := COALESCE(v_push_enabled, true);
    v_global_push_limit := COALESCE(v_global_push_limit, 8);

    IF NOT v_push_enabled THEN
      INSERT INTO public.coach_message_usage (
        user_id, pack_id, context, channel, locale,
        requested_personality, effective_personality, outcome, reason,
        event_key_hash, local_date, occurred_at
      ) VALUES (
        p_user_id, v_pack_id, p_context, p_channel, p_locale,
        v_requested_personality, v_effective_personality, 'suppressed', 'user_push_disabled',
        v_event_key_hash, v_local_date, p_now
      ) RETURNING id INTO v_usage_id;

      RETURN jsonb_build_object(
        'usage_id', v_usage_id,
        'outcome', 'suppressed',
        'reason', 'user_push_disabled',
        'pack_id', v_pack_id,
        'requested_personality', v_requested_personality,
        'effective_personality', v_effective_personality,
        'context', p_context,
        'channel', p_channel,
        'locale', p_locale,
        'idempotent_replay', false
      );
    END IF;
  END IF;

  IF v_policy.cooldown_seconds > 0 THEN
    SELECT max(usage.occurred_at)
    INTO v_latest_at
    FROM public.coach_message_usage usage
    WHERE usage.user_id = p_user_id
      AND usage.context = p_context
      AND usage.channel = p_channel
      AND usage.outcome = 'selected';

    IF v_latest_at IS NOT NULL
      AND v_latest_at + make_interval(secs => v_policy.cooldown_seconds) > p_now THEN
      INSERT INTO public.coach_message_usage (
        user_id, pack_id, context, channel, locale,
        requested_personality, effective_personality, outcome, reason,
        event_key_hash, local_date, occurred_at
      ) VALUES (
        p_user_id, v_pack_id, p_context, p_channel, p_locale,
        v_requested_personality, v_effective_personality, 'suppressed', 'cooldown',
        v_event_key_hash, v_local_date, p_now
      ) RETURNING id INTO v_usage_id;

      RETURN jsonb_build_object(
        'usage_id', v_usage_id,
        'outcome', 'suppressed',
        'reason', 'cooldown',
        'pack_id', v_pack_id,
        'requested_personality', v_requested_personality,
        'effective_personality', v_effective_personality,
        'context', p_context,
        'channel', p_channel,
        'locale', p_locale,
        'idempotent_replay', false
      );
    END IF;
  END IF;

  IF v_policy.max_per_local_day IS NOT NULL THEN
    SELECT count(*)
    INTO v_selected_today
    FROM public.coach_message_usage usage
    WHERE usage.user_id = p_user_id
      AND usage.context = p_context
      AND usage.channel = p_channel
      AND usage.local_date = v_local_date
      AND usage.outcome = 'selected';

    IF v_selected_today >= v_policy.max_per_local_day THEN
      INSERT INTO public.coach_message_usage (
        user_id, pack_id, context, channel, locale,
        requested_personality, effective_personality, outcome, reason,
        event_key_hash, local_date, occurred_at
      ) VALUES (
        p_user_id, v_pack_id, p_context, p_channel, p_locale,
        v_requested_personality, v_effective_personality, 'suppressed', 'daily_limit',
        v_event_key_hash, v_local_date, p_now
      ) RETURNING id INTO v_usage_id;

      RETURN jsonb_build_object(
        'usage_id', v_usage_id,
        'outcome', 'suppressed',
        'reason', 'daily_limit',
        'pack_id', v_pack_id,
        'requested_personality', v_requested_personality,
        'effective_personality', v_effective_personality,
        'context', p_context,
        'channel', p_channel,
        'locale', p_locale,
        'idempotent_replay', false
      );
    END IF;
  END IF;

  IF p_channel = 'push' THEN
    SELECT
      (
        SELECT count(*)
        FROM public.coach_message_usage usage
        WHERE usage.user_id = p_user_id
          AND usage.channel = 'push'
          AND usage.local_date = v_local_date
          AND usage.outcome = 'selected'
      ) + (
        SELECT count(*)
        FROM public.reminder_events event
        WHERE event.user_id = p_user_id
          AND event.status = 'queued'
          AND timezone(v_timezone, event.scheduled_for)::date = v_local_date
          AND NOT EXISTS (
            SELECT 1
            FROM public.notification_deliveries delivery
            WHERE delivery.reminder_event_id = event.id
              AND delivery.coach_message_usage_id IS NOT NULL
          )
      )
    INTO v_global_push_count;

    IF v_global_push_count >= v_global_push_limit THEN
      INSERT INTO public.coach_message_usage (
        user_id, pack_id, context, channel, locale,
        requested_personality, effective_personality, outcome, reason,
        event_key_hash, local_date, occurred_at
      ) VALUES (
        p_user_id, v_pack_id, p_context, p_channel, p_locale,
        v_requested_personality, v_effective_personality, 'suppressed', 'global_push_limit',
        v_event_key_hash, v_local_date, p_now
      ) RETURNING id INTO v_usage_id;

      RETURN jsonb_build_object(
        'usage_id', v_usage_id,
        'outcome', 'suppressed',
        'reason', 'global_push_limit',
        'pack_id', v_pack_id,
        'requested_personality', v_requested_personality,
        'effective_personality', v_effective_personality,
        'context', p_context,
        'channel', p_channel,
        'locale', p_locale,
        'idempotent_replay', false
      );
    END IF;
  END IF;

  INSERT INTO public.coach_message_usage (
    user_id,
    pack_id,
    template_id,
    template_version_id,
    context,
    channel,
    locale,
    requested_personality,
    effective_personality,
    outcome,
    reason,
    event_key_hash,
    local_date,
    occurred_at
  ) VALUES (
    p_user_id,
    v_pack_id,
    v_candidate.template_id,
    v_candidate.template_version_id,
    p_context,
    p_channel,
    p_locale,
    v_requested_personality,
    v_effective_personality,
    'selected',
    v_reason,
    v_event_key_hash,
    v_local_date,
    p_now
  ) RETURNING id INTO v_usage_id;

  RETURN jsonb_build_object(
    'usage_id', v_usage_id,
    'outcome', 'selected',
    'reason', v_reason,
    'pack_id', v_pack_id,
    'template_id', v_candidate.template_id,
    'template_version_id', v_candidate.template_version_id,
    'requested_personality', v_requested_personality,
    'effective_personality', v_effective_personality,
    'context', p_context,
    'channel', p_channel,
    'locale', p_locale,
    'title', v_candidate.title,
    'subject', v_candidate.subject,
    'body', v_candidate.body,
    'allowed_variables', to_jsonb(v_candidate.allowed_variables),
    'required_variables', to_jsonb(v_candidate.required_variables),
    'occurred_at', p_now,
    'idempotent_replay', false
  );
END;
$$;


REVOKE ALL ON FUNCTION private.claim_coach_message_unchecked(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  timestamptz
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.claim_coach_message_unchecked(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  timestamptz
) TO service_role;

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
  v_locale text;
  v_coach_context text;
  v_coach_claim jsonb;
  v_coach_usage_id uuid;
  v_coach_template_version_id uuid;
  v_coach_personality text;
  v_coach_template_key text;
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

  SELECT timezone, COALESCE(NULLIF(locale, ''), 'pt-BR')
  INTO v_timezone, v_locale
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
    OR p_scheduled_for > p_claimed_at + interval '5 minutes' THEN
    RAISE EXCEPTION 'scheduled reminder does not match its active rule'
      USING ERRCODE = '22023';
  END IF;

  IF p_scheduled_for < p_claimed_at - interval '15 minutes' THEN
    INSERT INTO public.reminder_events (
      user_id,
      reminder_rule_id,
      scheduled_for,
      status,
      suppression_reason
    ) VALUES (
      v_rule.user_id,
      v_rule.id,
      p_scheduled_for,
      'suppressed',
      'stale'
    )
    RETURNING id INTO v_event_id;

    RETURN jsonb_build_object(
      'event_id', v_event_id,
      'status', 'suppressed',
      'suppression_reason', 'stale',
      'delivery_count', 0,
      'existing', false
    );
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
    ELSIF v_rule.category IN ('content', 'reengagement') THEN
      NULL;
    ELSE
      v_status := 'suppressed';
      v_reason := 'missing_official_context';
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

  IF v_status = 'queued' THEN
    v_coach_context := CASE v_rule.category
      WHEN 'meal' THEN 'meal_pending'
      WHEN 'hydration' THEN 'hydration'
      WHEN 'supplement' THEN 'supplement'
      WHEN 'medication' THEN 'medication'
      WHEN 'workout' THEN 'workout'
      WHEN 'reevaluation' THEN 'reevaluation'
      WHEN 'content' THEN 'progress'
      WHEN 'reengagement' THEN 'reengagement'
      ELSE NULL
    END;

    IF v_coach_context IS NULL THEN
      v_status := 'suppressed';
      v_reason := 'coach_message_context_unsupported';
    ELSE
      v_coach_claim := public.claim_coach_message(
        v_rule.user_id,
        v_coach_context,
        'push',
        v_locale,
        concat(
          'bodyflow.reminder:',
          v_rule.id::text,
          ':',
          to_char(
            p_scheduled_for AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
          )
        ),
        ARRAY[]::text[],
        p_claimed_at
      );

      IF v_coach_claim->>'outcome' <> 'selected' THEN
        v_status := 'suppressed';
        v_reason := 'coach_message_' || COALESCE(
          NULLIF(v_coach_claim->>'reason', ''),
          'selection_failed'
        );
      ELSE
        SELECT
          usage.id,
          usage.template_version_id,
          usage.effective_personality,
          template.template_key
        INTO
          v_coach_usage_id,
          v_coach_template_version_id,
          v_coach_personality,
          v_coach_template_key
        FROM public.coach_message_usage usage
        JOIN public.coach_message_templates template ON template.id = usage.template_id
        WHERE usage.id = (v_coach_claim->>'usage_id')::uuid
          AND usage.user_id = v_rule.user_id
          AND usage.outcome = 'selected'
          AND usage.context = v_coach_context
          AND usage.channel = 'push'
          AND usage.locale = v_locale
          AND usage.template_version_id = (v_coach_claim->>'template_version_id')::uuid;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'selected coach reminder claim is inconsistent'
            USING ERRCODE = '23514';
        END IF;
      END IF;
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
      coach_message_usage_id,
      coach_template_version_id,
      locale,
      status,
      scheduled_for
    )
    SELECT
      v_rule.user_id,
      v_event_id,
      device.id,
      'push',
      'apns',
      v_coach_template_key,
      v_coach_personality,
      v_coach_usage_id,
      v_coach_template_version_id,
      v_locale,
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


REVOKE ALL ON FUNCTION public.claim_reminder_event(uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_reminder_event(uuid, timestamptz, timestamptz)
  TO service_role;

COMMENT ON FUNCTION public.claim_reminder_event(uuid, timestamptz, timestamptz) IS
  'Claims an app-first reminder idempotently and shares one immutable coach catalog selection across all queued device deliveries.';
