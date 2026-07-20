DROP FUNCTION public.list_due_reminder_rules(timestamptz, integer, integer);

CREATE FUNCTION public.list_due_reminder_rules(
  p_fired_at timestamptz,
  p_lookback_minutes integer DEFAULT 5,
  p_limit integer DEFAULT 500,
  p_after_scheduled_for timestamptz DEFAULT NULL,
  p_after_rule_id uuid DEFAULT NULL
)
RETURNS TABLE (
  reminder_rule_id uuid,
  scheduled_for timestamptz
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
    OR (p_after_scheduled_for IS NULL) <> (p_after_rule_id IS NULL)
    OR (p_after_scheduled_for IS NOT NULL AND NOT isfinite(p_after_scheduled_for)) THEN
    RAISE EXCEPTION 'invalid due reminder lookup payload' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH lookup_window AS (
    SELECT
      date_trunc('minute', p_fired_at) - make_interval(mins => p_lookback_minutes)
        AS starts_at,
      date_trunc('minute', p_fired_at) AS ends_at
  ),
  active_rules AS (
    SELECT
      rule.id AS reminder_rule_id,
      rule.local_time,
      rule.weekdays,
      timezone_name.name AS timezone_name,
      timezone(timezone_name.name, lookup.starts_at)::date AS starts_on,
      timezone(timezone_name.name, lookup.ends_at)::date AS ends_on
    FROM public.reminder_rules rule
    JOIN public.users domain_user
      ON domain_user.id = rule.user_id
      AND domain_user.status = 'active'
      AND domain_user.timezone IS NOT NULL
    JOIN pg_catalog.pg_timezone_names timezone_name
      ON timezone_name.name = domain_user.timezone
    CROSS JOIN lookup_window lookup
    WHERE rule.active
  ),
  candidate_local_dates AS (
    SELECT
      rule.reminder_rule_id,
      rule.local_time,
      rule.weekdays,
      rule.timezone_name,
      rule.starts_on AS local_date
    FROM active_rules rule
    UNION
    SELECT
      rule.reminder_rule_id,
      rule.local_time,
      rule.weekdays,
      rule.timezone_name,
      rule.ends_on AS local_date
    FROM active_rules rule
  ),
  candidates AS (
    SELECT
      candidate.reminder_rule_id,
      candidate.local_time,
      candidate.timezone_name,
      candidate.local_date,
      (candidate.local_date + candidate.local_time) AT TIME ZONE candidate.timezone_name
        AS scheduled_for
    FROM candidate_local_dates candidate
    WHERE extract(dow FROM candidate.local_date)::smallint = ANY(candidate.weekdays)
  )
  SELECT candidate.reminder_rule_id, candidate.scheduled_for
  FROM candidates candidate
  CROSS JOIN lookup_window lookup
  WHERE candidate.scheduled_for BETWEEN lookup.starts_at AND lookup.ends_at
    AND timezone(candidate.timezone_name, candidate.scheduled_for)::date = candidate.local_date
    AND to_char(timezone(candidate.timezone_name, candidate.scheduled_for), 'HH24:MI')
      = to_char(candidate.local_time, 'HH24:MI')
    AND (
      p_after_scheduled_for IS NULL
      OR (candidate.scheduled_for, candidate.reminder_rule_id)
        > (p_after_scheduled_for, p_after_rule_id)
    )
  ORDER BY candidate.scheduled_for, candidate.reminder_rule_id
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.list_due_reminder_rules(
  timestamptz,
  integer,
  integer,
  timestamptz,
  uuid
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_due_reminder_rules(
  timestamptz,
  integer,
  integer,
  timestamptz,
  uuid
) TO service_role;

COMMENT ON FUNCTION public.list_due_reminder_rules(
  timestamptz,
  integer,
  integer,
  timestamptz,
  uuid
) IS 'Lists due BodyFlow reminders with deterministic keyset pagination; service_role only.';
