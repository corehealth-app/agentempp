-- Resolve a push's opaque link for the authenticated Flow session.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE FUNCTION public.read_flow_meal_gap_notice(p_user_id uuid, p_notice_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  notice private.flow_meal_gap_notices%ROWTYPE;
  zone text;
  now_at timestamptz := statement_timestamp();
  state text;
BEGIN
  PERFORM private.assert_trusted_backend();
  SELECT n.* INTO notice FROM private.flow_meal_gap_notices n
    WHERE n.id = p_notice_id AND n.user_id = p_user_id
      AND (n.status = 'accepted' OR (n.status = 'claimed' AND n.claim_until > now_at));
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT u.timezone INTO zone FROM public.users u
    JOIN pg_catalog.pg_timezone_names z ON z.name = u.timezone
    WHERE u.id = p_user_id AND u.status = 'active';
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF NOT private.flow_meal_gap_missing(p_user_id, notice.local_date, zone, notice.meal_type) THEN
    state := 'resolved';
  ELSIF notice.local_date <> (now_at AT TIME ZONE zone)::date OR EXISTS (
    SELECT 1 FROM public.daily_snapshots s
    WHERE s.user_id = p_user_id AND s.date = notice.local_date AND s.day_closed
  ) THEN state := 'expired';
  ELSIF private.flow_meal_gap_blocked(p_user_id, notice.local_date, zone, now_at) THEN
    state := 'processing';
  ELSE
    state := 'pending';
  END IF;

  RETURN jsonb_build_object('id', notice.id, 'local_date', notice.local_date,
    'meal_type', notice.meal_type, 'state', state);
END $$;

REVOKE ALL ON FUNCTION public.read_flow_meal_gap_notice(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.read_flow_meal_gap_notice(uuid,uuid) TO service_role;
COMMIT;
