-- Register or replace one workout in a single database transaction.
-- Snapshot exercise totals are derived from workout_logs, preventing drift
-- when a retry, correction or partial failure happens during registration.

CREATE OR REPLACE FUNCTION public.register_workout_atomic(
  p_user_id uuid,
  p_date date,
  p_workout_type text,
  p_duration_min integer,
  p_estimated_kcal integer,
  p_intensity text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_performed_at timestamptz DEFAULT now(),
  p_provider_message_id text DEFAULT NULL,
  p_calories_target integer DEFAULT NULL,
  p_protein_target numeric DEFAULT NULL,
  p_replace_recent boolean DEFAULT false,
  p_replace_since timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_snapshot_id uuid;
  v_workout_log_id uuid;
  v_inserted boolean := false;
  v_replaced_count integer := 0;
  v_affected_snapshot_ids uuid[] := ARRAY[]::uuid[];
  v_affected_snapshot_id uuid;
  v_result jsonb;
BEGIN
  IF p_user_id IS NULL OR p_date IS NULL
    OR NULLIF(btrim(p_workout_type), '') IS NULL
    OR length(p_workout_type) > 200
    OR p_duration_min IS NULL OR p_duration_min < 1 OR p_duration_min > 1440
    OR p_estimated_kcal IS NULL OR p_estimated_kcal < 0 OR p_estimated_kcal > 10000 THEN
    RAISE EXCEPTION 'invalid workout payload';
  END IF;
  IF p_replace_recent AND p_replace_since IS NULL THEN
    RAISE EXCEPTION 'replace requires a lower time boundary';
  END IF;

  -- Corrections may affect a previous local day, so all workout writes for a
  -- user share one short transaction lock instead of locking only one date.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':workouts', 0));

  INSERT INTO public.daily_snapshots (
    user_id,
    date,
    exercise_calories,
    training_done,
    calories_target,
    protein_target
  ) VALUES (
    p_user_id,
    p_date,
    0,
    false,
    p_calories_target,
    p_protein_target
  )
  ON CONFLICT (user_id, date) DO UPDATE SET
    calories_target = COALESCE(public.daily_snapshots.calories_target, EXCLUDED.calories_target),
    protein_target = COALESCE(public.daily_snapshots.protein_target, EXCLUDED.protein_target),
    updated_at = now()
  RETURNING id INTO v_snapshot_id;

  IF p_replace_recent THEN
    SELECT COALESCE(
      array_agg(DISTINCT snapshot_id) FILTER (WHERE snapshot_id IS NOT NULL),
      ARRAY[]::uuid[]
    )
    INTO v_affected_snapshot_ids
    FROM public.workout_logs
    WHERE user_id = p_user_id
      AND workout_type = p_workout_type
      AND created_at >= p_replace_since;

    DELETE FROM public.workout_logs
    WHERE user_id = p_user_id
      AND workout_type = p_workout_type
      AND created_at >= p_replace_since;
    GET DIAGNOSTICS v_replaced_count = ROW_COUNT;
  END IF;

  INSERT INTO public.workout_logs (
    user_id,
    snapshot_id,
    workout_type,
    duration_min,
    estimated_kcal,
    intensity,
    notes,
    performed_at,
    raw_provider_message_id
  ) VALUES (
    p_user_id,
    v_snapshot_id,
    btrim(p_workout_type),
    p_duration_min,
    p_estimated_kcal,
    p_intensity,
    p_notes,
    COALESCE(p_performed_at, now()),
    p_provider_message_id
  )
  ON CONFLICT (user_id, raw_provider_message_id, workout_type)
    WHERE raw_provider_message_id IS NOT NULL
  DO NOTHING
  RETURNING id INTO v_workout_log_id;

  v_inserted := v_workout_log_id IS NOT NULL;
  IF NOT v_inserted AND p_provider_message_id IS NOT NULL THEN
    SELECT id
    INTO v_workout_log_id
    FROM public.workout_logs
    WHERE user_id = p_user_id
      AND raw_provider_message_id = p_provider_message_id
      AND workout_type = btrim(p_workout_type)
    LIMIT 1;
  END IF;

  SELECT ARRAY(
    SELECT DISTINCT affected.snapshot_id
    FROM unnest(v_affected_snapshot_ids || ARRAY[v_snapshot_id]) AS affected(snapshot_id)
    WHERE affected.snapshot_id IS NOT NULL
  ) INTO v_affected_snapshot_ids;

  FOREACH v_affected_snapshot_id IN ARRAY v_affected_snapshot_ids LOOP
    UPDATE public.daily_snapshots AS snapshot
    SET
      exercise_calories = (
        SELECT COALESCE(sum(workout.estimated_kcal), 0)::integer
        FROM public.workout_logs AS workout
        WHERE workout.snapshot_id = v_affected_snapshot_id
      ),
      training_done = EXISTS (
        SELECT 1
        FROM public.workout_logs AS workout
        WHERE workout.snapshot_id = v_affected_snapshot_id
      ),
      updated_at = now()
    WHERE snapshot.id = v_affected_snapshot_id;
  END LOOP;

  SELECT jsonb_build_object(
    'snapshot_id', snapshot.id,
    'workout_log_id', v_workout_log_id,
    'inserted', v_inserted,
    'replaced_count', v_replaced_count,
    'exercise_calories', snapshot.exercise_calories,
    'training_done', snapshot.training_done,
    'calories_target', snapshot.calories_target,
    'protein_target', snapshot.protein_target
  ) INTO v_result
  FROM public.daily_snapshots AS snapshot
  WHERE snapshot.id = v_snapshot_id;

  RETURN v_result;
END;
$$;
