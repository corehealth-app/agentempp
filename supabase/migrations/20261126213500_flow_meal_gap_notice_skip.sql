-- A user's explicit "I skipped it" answer uses the same event read by day close.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE FUNCTION public.skip_flow_meal_gap_notice(p_user_id uuid, p_notice_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE
  current_notice jsonb;
  meal_day date;
  at_time timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();
  current_notice := public.read_flow_meal_gap_notice(p_user_id, p_notice_id);
  IF current_notice IS NULL OR current_notice->>'state' <> 'pending' THEN
    RETURN current_notice;
  END IF;

  -- Serialize against app registrations and the day-close reader/writer.
  -- Re-read after locking: a prior answer, a meal or a close may have won.
  PERFORM private.lock_conversation_command_owner(p_user_id);
  meal_day := (current_notice->>'local_date')::date;
  IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || meal_day::text, 0)) THEN
    RAISE EXCEPTION 'flow reminder day is busy' USING ERRCODE = '55P03';
  END IF;
  current_notice := public.read_flow_meal_gap_notice(p_user_id, p_notice_id);
  IF current_notice IS NULL OR current_notice->>'state' <> 'pending' THEN
    RETURN current_notice;
  END IF;

  at_time := clock_timestamp();
  IF meal_day IS DISTINCT FROM (SELECT (at_time AT TIME ZONE u.timezone)::date
                                 FROM public.users u WHERE u.id = p_user_id) THEN
    RETURN jsonb_set(current_notice, '{state}', '"expired"');
  END IF;
  INSERT INTO public.product_events(user_id, event, occurred_at, properties)
  VALUES (p_user_id, 'meal.user_skipped', at_time, jsonb_build_object(
    'local_date', meal_day, 'meal_type', current_notice->>'meal_type',
    'flow_notice_id', p_notice_id, 'source_timestamp', at_time
  ));
  RETURN jsonb_set(current_notice, '{state}', '"resolved"');
END $$;

REVOKE ALL ON FUNCTION public.skip_flow_meal_gap_notice(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.skip_flow_meal_gap_notice(uuid,uuid) TO service_role;
COMMIT;
