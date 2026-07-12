-- Finalize one daily snapshot and its derived user_progress in one transaction.
-- A retry observes day_closed=true and cannot apply XP or bloco credit twice.

CREATE OR REPLACE FUNCTION public.finalize_daily_close_atomic(
  p_user_id uuid,
  p_snapshot_id uuid,
  p_day_status text,
  p_xp_total integer,
  p_level integer,
  p_current_streak integer,
  p_longest_streak integer,
  p_blocks_completed integer,
  p_deficit_block integer,
  p_badges_earned text[],
  p_last_active_date date,
  p_closed_at timestamptz DEFAULT now()
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_snapshot_closed boolean;
BEGIN
  IF p_user_id IS NULL OR p_snapshot_id IS NULL OR p_last_active_date IS NULL
    OR p_day_status IS NULL
    OR p_day_status NOT IN ('complete', 'user_skipped', 'incomplete_no_response')
    OR p_xp_total IS NULL OR p_xp_total < 0
    OR p_level IS NULL OR p_level < 1
    OR p_current_streak IS NULL OR p_current_streak < 0
    OR p_longest_streak IS NULL OR p_longest_streak < 0
    OR p_blocks_completed IS NULL OR p_blocks_completed < 0
    OR p_deficit_block IS NULL OR p_deficit_block < 0 THEN
    RAISE EXCEPTION 'invalid daily close payload';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':daily-close', 0));

  SELECT day_closed
  INTO v_snapshot_closed
  FROM public.daily_snapshots
  WHERE id = p_snapshot_id AND user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'daily snapshot not found';
  END IF;

  IF v_snapshot_closed THEN
    RETURN jsonb_build_object(
      'applied', false,
      'already_closed', true,
      'snapshot_id', p_snapshot_id
    );
  END IF;

  INSERT INTO public.user_progress (
    user_id,
    xp_total,
    level,
    current_streak,
    longest_streak,
    blocks_completed,
    deficit_block,
    badges_earned,
    last_active_date,
    updated_at
  ) VALUES (
    p_user_id,
    p_xp_total,
    p_level,
    p_current_streak,
    p_longest_streak,
    p_blocks_completed,
    p_deficit_block,
    COALESCE(p_badges_earned, ARRAY[]::text[]),
    p_last_active_date,
    now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    xp_total = EXCLUDED.xp_total,
    level = EXCLUDED.level,
    current_streak = EXCLUDED.current_streak,
    longest_streak = EXCLUDED.longest_streak,
    blocks_completed = EXCLUDED.blocks_completed,
    deficit_block = EXCLUDED.deficit_block,
    badges_earned = EXCLUDED.badges_earned,
    last_active_date = EXCLUDED.last_active_date,
    updated_at = now();

  UPDATE public.daily_snapshots
  SET
    day_status = p_day_status,
    day_closed = true,
    closed_at = COALESCE(p_closed_at, now()),
    updated_at = now()
  WHERE id = p_snapshot_id AND user_id = p_user_id;

  RETURN jsonb_build_object(
    'applied', true,
    'already_closed', false,
    'snapshot_id', p_snapshot_id,
    'day_status', p_day_status
  );
END;
$$;
