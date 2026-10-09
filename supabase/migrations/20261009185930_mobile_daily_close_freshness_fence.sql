-- Opt-in mobile finalization. The legacy finalizer/worker keep their contract.
-- Expected rows are captured by the trusted backend from the reads/writes
-- that produced the payload, never supplied as authority by the iOS client.
CREATE FUNCTION public.finalize_mobile_daily_close_atomic(
  p_user_id uuid, p_snapshot_id uuid, p_day_status text,
  p_xp_total integer, p_level integer, p_current_streak integer,
  p_longest_streak integer, p_blocks_completed integer, p_deficit_block integer,
  p_badges_earned text[], p_last_active_date date, p_closed_at timestamptz,
  p_expected_timezone text, p_expected_snapshot jsonb,
  p_expected_profile jsonb, p_expected_progress jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
SET lock_timeout = '2000ms'
AS $$
DECLARE
  v_user public.users%ROWTYPE;
  v_profile jsonb;
  v_expected_profile public.user_profiles%ROWTYPE;
  v_expected_snapshot public.daily_snapshots%ROWTYPE;
  v_expected_progress public.user_progress%ROWTYPE;
  v_snapshot public.daily_snapshots%ROWTYPE;
  v_progress jsonb;
  v_created_progress uuid;
  v_now timestamptz;
  v_today date;
  v_start timestamptz;
  v_latest date;
  v_result jsonb;
  v_refusal jsonb := jsonb_build_object(
    'applied', false, 'already_closed', false, 'snapshot_id', p_snapshot_id);
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_snapshot_id IS NULL OR p_last_active_date IS NULL
    OR jsonb_typeof(p_expected_snapshot) IS DISTINCT FROM 'object'
    OR p_expected_snapshot->>'id' IS DISTINCT FROM p_snapshot_id::text
    OR p_expected_snapshot->>'user_id' IS DISTINCT FROM p_user_id::text
    OR p_expected_snapshot->>'date' IS DISTINCT FROM p_last_active_date::text
    OR p_expected_timezone IS NULL OR p_expected_timezone = '' THEN
    RAISE EXCEPTION 'invalid mobile daily close context' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_user FROM public.users WHERE id = p_user_id FOR SHARE NOWAIT;
  IF NOT FOUND OR v_user.status::text IS DISTINCT FROM 'active' OR v_user.wpp IS NOT NULL
    OR v_user.timezone IS DISTINCT FROM p_expected_timezone
    OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = v_user.timezone) THEN
    RETURN v_refusal || jsonb_build_object('reason', 'context_changed');
  END IF;
  SELECT to_jsonb(p) INTO v_profile FROM public.user_profiles p
    WHERE p.user_id = p_user_id FOR SHARE NOWAIT;
  IF NOT FOUND OR jsonb_typeof(p_expected_profile) IS DISTINCT FROM 'object' THEN
    RETURN v_refusal || jsonb_build_object('reason', 'profile_changed');
  END IF;
  -- Require every original key and reject extras. Typed records normalize
  -- equivalent timestamps/numerics without discarding precision or columns.
  IF NOT p_expected_profile ?& ARRAY(SELECT jsonb_object_keys(v_profile))
    OR (p_expected_profile - ARRAY(SELECT jsonb_object_keys(v_profile))) <> '{}'::jsonb THEN
    RETURN v_refusal || jsonb_build_object('reason', 'profile_changed');
  END IF;
  v_expected_profile := jsonb_populate_record(NULL::public.user_profiles, p_expected_profile);
  IF to_jsonb(v_expected_profile) IS DISTINCT FROM v_profile THEN
    RETURN v_refusal || jsonb_build_object('reason', 'profile_changed');
  END IF;

  -- Both existing advisory namespaces precede the snapshot row. Never wait
  -- holding that row for a registrar or the legacy finalizer's advisory.
  IF NOT pg_try_advisory_xact_lock(hashtextextended(
    p_user_id::text || ':' || p_last_active_date::text, 0))
    OR NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text || ':daily-close', 0)) THEN
    RAISE EXCEPTION 'mobile daily close busy' USING ERRCODE = '55P03';
  END IF;
  SELECT * INTO v_snapshot FROM public.daily_snapshots
    WHERE id = p_snapshot_id AND user_id = p_user_id FOR UPDATE NOWAIT;
  IF NOT FOUND OR v_snapshot.date IS DISTINCT FROM p_last_active_date THEN
    RETURN v_refusal || jsonb_build_object('reason', 'snapshot_changed');
  END IF;
  IF v_snapshot.day_closed THEN
    RETURN jsonb_build_object('applied', false, 'already_closed', true,
      'snapshot_id', p_snapshot_id, 'reason', 'already_closed');
  END IF;
  IF NOT p_expected_snapshot ?& ARRAY(SELECT jsonb_object_keys(to_jsonb(v_snapshot)))
    OR (p_expected_snapshot - ARRAY(SELECT jsonb_object_keys(to_jsonb(v_snapshot)))) <> '{}'::jsonb THEN
    RETURN v_refusal || jsonb_build_object('reason', 'snapshot_changed');
  END IF;
  v_expected_snapshot := jsonb_populate_record(NULL::public.daily_snapshots, p_expected_snapshot);
  IF to_jsonb(v_snapshot) IS DISTINCT FROM to_jsonb(v_expected_snapshot) THEN
    RETURN v_refusal || jsonb_build_object('reason', 'snapshot_changed');
  END IF;

  SELECT jsonb_build_object(
    'xp_total', p.xp_total, 'level', p.level, 'current_streak', p.current_streak,
    'longest_streak', p.longest_streak, 'blocks_completed', p.blocks_completed,
    'deficit_block', p.deficit_block, 'badges_earned', p.badges_earned,
    'last_active_date', p.last_active_date, 'updated_at', p.updated_at
  ) INTO v_progress FROM public.user_progress p
    WHERE p.user_id = p_user_id FOR UPDATE NOWAIT;
  IF v_progress IS NULL THEN
    IF p_expected_progress IS NOT NULL THEN
      RETURN v_refusal || jsonb_build_object('reason', 'progress_changed');
    END IF;
  ELSE
    IF jsonb_typeof(p_expected_progress) IS DISTINCT FROM 'object'
      OR NOT p_expected_progress ?& ARRAY(SELECT jsonb_object_keys(v_progress))
      OR (p_expected_progress - ARRAY(SELECT jsonb_object_keys(v_progress))) <> '{}'::jsonb THEN
      RETURN v_refusal || jsonb_build_object('reason', 'progress_changed');
    END IF;
    v_expected_progress := jsonb_populate_record(NULL::public.user_progress, p_expected_progress);
    IF v_progress IS DISTINCT FROM jsonb_build_object(
      'xp_total', v_expected_progress.xp_total, 'level', v_expected_progress.level,
      'current_streak', v_expected_progress.current_streak,
      'longest_streak', v_expected_progress.longest_streak,
      'blocks_completed', v_expected_progress.blocks_completed,
      'deficit_block', v_expected_progress.deficit_block,
      'badges_earned', v_expected_progress.badges_earned,
      'last_active_date', v_expected_progress.last_active_date,
      'updated_at', v_expected_progress.updated_at
    ) THEN RETURN v_refusal || jsonb_build_object('reason', 'progress_changed'); END IF;
  END IF;

  -- The post-lock server clock supplies eligibility, including the real UTC
  -- instant of local midnight (DST); no client timestamp can authorize today.
  v_now := clock_timestamp();
  v_today := (v_now AT TIME ZONE v_user.timezone)::date;
  v_start := v_today::timestamp AT TIME ZONE v_user.timezone;
  v_latest := v_today - CASE WHEN v_now - v_start >= interval '30 minutes' THEN 1 ELSE 2 END;
  IF p_last_active_date > v_latest THEN
    RETURN v_refusal || jsonb_build_object('reason', 'not_closable');
  END IF;

  IF v_progress IS NULL THEN
    -- Absence cannot be locked. Only our own insert permits delegation; a
    -- concurrent initializer is never adopted or overwritten. Any exception
    -- below rolls this insert back with the entire finalization transaction.
    INSERT INTO public.user_progress(user_id) VALUES (p_user_id)
      ON CONFLICT (user_id) DO NOTHING RETURNING user_id INTO v_created_progress;
    IF v_created_progress IS NULL THEN
      RAISE EXCEPTION 'mobile daily close progress appeared' USING ERRCODE = '40001';
    END IF;
  END IF;
  v_result := public.finalize_daily_close_atomic(
    p_user_id, p_snapshot_id, p_day_status, p_xp_total, p_level,
    p_current_streak, p_longest_streak, p_blocks_completed, p_deficit_block,
    p_badges_earned, p_last_active_date, v_now);
  IF v_result->'applied' IS DISTINCT FROM 'true'::jsonb
    OR v_result->'already_closed' IS DISTINCT FROM 'false'::jsonb
    OR v_result->>'snapshot_id' IS DISTINCT FROM p_snapshot_id::text
    OR v_result->>'day_status' IS DISTINCT FROM p_day_status THEN
    RAISE EXCEPTION 'mobile daily close delegation failed' USING ERRCODE = '40001';
  END IF;
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_mobile_daily_close_atomic(
  uuid, uuid, text, integer, integer, integer, integer, integer, integer,
  text[], date, timestamptz, text, jsonb, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_mobile_daily_close_atomic(
  uuid, uuid, text, integer, integer, integer, integer, integer, integer,
  text[], date, timestamptz, text, jsonb, jsonb, jsonb) TO service_role;
COMMENT ON FUNCTION public.finalize_mobile_daily_close_atomic(
  uuid, uuid, text, integer, integer, integer, integer, integer, integer,
  text[], date, timestamptz, text, jsonb, jsonb, jsonb) IS
  'Backend-only mobile finalization fence; preserves legacy defaults and rejects stale official state.';

-- Empty discovery also reaches inactivity. Use the same official calendar
-- discipline without changing the default legacy UPDATE or initializing rows.
CREATE FUNCTION public.reset_mobile_inactive_streak_atomic(
  p_user_id uuid, p_expected_timezone text,
  p_expected_progress jsonb, p_expected_latest_date date
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
SET lock_timeout = '2000ms'
AS $$
DECLARE
  v_user public.users%ROWTYPE;
  v_progress public.user_progress%ROWTYPE;
  v_expected public.user_progress%ROWTYPE;
  v_now timestamptz;
  v_today date;
  v_start timestamptz;
  v_latest date;
  v_gap integer;
  v_refusal jsonb := jsonb_build_object('applied',false,'user_id',p_user_id);
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_user_id IS NULL OR p_expected_latest_date IS NULL OR
    p_expected_timezone IS NULL OR p_expected_timezone = '' OR
    jsonb_typeof(p_expected_progress) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'invalid mobile inactivity context' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_user FROM public.users WHERE id=p_user_id FOR SHARE NOWAIT;
  IF NOT FOUND OR v_user.status::text IS DISTINCT FROM 'active' OR v_user.wpp IS NOT NULL
    OR v_user.timezone IS DISTINCT FROM p_expected_timezone
    OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=v_user.timezone) THEN
    RETURN v_refusal || jsonb_build_object('reason','context_changed');
  END IF;
  IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text || ':daily-close',0)) THEN
    RAISE EXCEPTION 'mobile inactivity busy' USING ERRCODE='55P03';
  END IF;
  SELECT * INTO v_progress FROM public.user_progress WHERE user_id=p_user_id FOR UPDATE NOWAIT;
  IF NOT FOUND OR NOT p_expected_progress ?& ARRAY['current_streak','last_active_date','updated_at']
    OR (p_expected_progress - ARRAY['current_streak','last_active_date','updated_at']) <> '{}'::jsonb THEN
    RETURN v_refusal || jsonb_build_object('reason','progress_changed');
  END IF;
  v_expected := jsonb_populate_record(NULL::public.user_progress,p_expected_progress);
  IF v_progress.current_streak IS DISTINCT FROM v_expected.current_streak OR
    v_progress.last_active_date IS DISTINCT FROM v_expected.last_active_date OR
    v_progress.updated_at IS DISTINCT FROM v_expected.updated_at THEN
    RETURN v_refusal || jsonb_build_object('reason','progress_changed');
  END IF;
  v_now := clock_timestamp();
  v_today := (v_now AT TIME ZONE v_user.timezone)::date;
  v_start := v_today::timestamp AT TIME ZONE v_user.timezone;
  v_latest := v_today - CASE WHEN v_now-v_start >= interval '30 minutes' THEN 1 ELSE 2 END;
  IF v_latest IS DISTINCT FROM p_expected_latest_date THEN
    RETURN v_refusal || jsonb_build_object('reason','context_changed');
  END IF;
  v_gap := v_latest-v_progress.last_active_date;
  IF v_progress.current_streak <= 0 OR v_progress.last_active_date IS NULL OR v_gap < 2 THEN
    RETURN v_refusal || jsonb_build_object('reason','not_inactive');
  END IF;
  UPDATE public.user_progress SET current_streak=0,updated_at=v_now WHERE user_id=p_user_id;
  RETURN jsonb_build_object('applied',true,'user_id',p_user_id,
    'previous_streak',v_progress.current_streak,'last_active_date',v_progress.last_active_date,
    'gap_days',v_gap,'latest_closable_date',v_latest);
END;
$$;
REVOKE ALL ON FUNCTION public.reset_mobile_inactive_streak_atomic(uuid,text,jsonb,date)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reset_mobile_inactive_streak_atomic(uuid,text,jsonb,date)
  TO service_role;
