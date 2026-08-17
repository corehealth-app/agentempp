BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000333';
  v_snapshot_id uuid;
  v_result jsonb;
  v_snapshot record;
  v_progress record;
BEGIN
  INSERT INTO public.users (id, wpp, name)
  VALUES (v_user_id, '17777777777', 'atomic-close-test')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.daily_snapshots (user_id, date, calories_consumed, calories_target)
  VALUES (v_user_id, DATE '2026-07-11', 1500, 1900)
  RETURNING id INTO v_snapshot_id;

  INSERT INTO public.user_progress (user_id, xp_total, level, deficit_block)
  VALUES (v_user_id, 10, 1, 100)
  ON CONFLICT (user_id) DO UPDATE SET xp_total = 10, level = 1, deficit_block = 100;

  v_result := public.finalize_daily_close_atomic(
    p_user_id => v_user_id,
    p_snapshot_id => v_snapshot_id,
    p_day_status => 'user_skipped',
    p_xp_total => 125,
    p_level => 2,
    p_current_streak => 3,
    p_longest_streak => 4,
    p_blocks_completed => 1,
    p_deficit_block => 250,
    p_badges_earned => ARRAY['Primeiro Bloco'],
    p_last_active_date => DATE '2026-07-11',
    p_closed_at => timestamptz '2026-07-12 04:30:00+00'
  );

  SELECT day_closed, day_status, closed_at
  INTO v_snapshot
  FROM public.daily_snapshots
  WHERE id = v_snapshot_id;

  SELECT xp_total, level, current_streak, longest_streak,
    blocks_completed, deficit_block, badges_earned, last_active_date
  INTO v_progress
  FROM public.user_progress
  WHERE user_id = v_user_id;

  IF NOT (v_result->>'applied')::boolean
    OR NOT v_snapshot.day_closed
    OR v_snapshot.day_status <> 'user_skipped'
    OR v_snapshot.closed_at <> timestamptz '2026-07-12 04:30:00+00'
    OR v_progress.xp_total <> 125
    OR v_progress.level <> 2
    OR v_progress.current_streak <> 3
    OR v_progress.longest_streak <> 4
    OR v_progress.blocks_completed <> 1
    OR v_progress.deficit_block <> 250
    OR v_progress.badges_earned <> ARRAY['Primeiro Bloco']::text[]
    OR v_progress.last_active_date <> DATE '2026-07-11' THEN
    RAISE EXCEPTION 'atomic close failed: result %, snapshot %, progress %',
      v_result, v_snapshot, v_progress;
  END IF;

  -- A retry cannot apply progress twice or overwrite the completed result.
  v_result := public.finalize_daily_close_atomic(
    p_user_id => v_user_id,
    p_snapshot_id => v_snapshot_id,
    p_day_status => 'complete',
    p_xp_total => 999,
    p_level => 9,
    p_current_streak => 9,
    p_longest_streak => 9,
    p_blocks_completed => 9,
    p_deficit_block => 999,
    p_badges_earned => ARRAY['retry-must-not-win'],
    p_last_active_date => DATE '2026-07-11'
  );

  SELECT day_closed, day_status INTO v_snapshot
  FROM public.daily_snapshots WHERE id = v_snapshot_id;
  SELECT xp_total, blocks_completed, deficit_block INTO v_progress
  FROM public.user_progress WHERE user_id = v_user_id;

  IF (v_result->>'applied')::boolean
    OR v_snapshot.day_status <> 'user_skipped'
    OR v_progress.xp_total <> 125
    OR v_progress.blocks_completed <> 1
    OR v_progress.deficit_block <> 250 THEN
    RAISE EXCEPTION 'daily close retry was not idempotent: %, %, %',
      v_result, v_snapshot, v_progress;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.finalize_daily_close_atomic(uuid,uuid,text,integer,integer,integer,integer,integer,integer,text[],date,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute finalize_daily_close_atomic';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.finalize_daily_close_atomic(uuid,uuid,text,integer,integer,integer,integer,integer,integer,text[],date,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute finalize_daily_close_atomic';
  END IF;
END;
$test$;

ROLLBACK;
