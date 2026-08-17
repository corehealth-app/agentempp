BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000222';
  v_result jsonb;
  v_log_count integer;
  v_snapshot_kcal integer;
BEGIN
  INSERT INTO public.users (id, wpp, name)
  VALUES (v_user_id, '18888888888', 'atomic-workout-test')
  ON CONFLICT (id) DO NOTHING;

  v_result := public.register_workout_atomic(
    p_user_id => v_user_id,
    p_date => DATE '2026-07-11',
    p_workout_type => 'caminhada',
    p_duration_min => 60,
    p_estimated_kcal => 100,
    p_intensity => 'moderada',
    p_performed_at => timestamptz '2026-07-11 13:00:00+00',
    p_provider_message_id => 'provider-workout-1',
    p_calories_target => 1900,
    p_protein_target => 140
  );

  IF NOT (v_result->>'inserted')::boolean
    OR (v_result->>'exercise_calories')::integer <> 100 THEN
    RAISE EXCEPTION 'first workout insert failed: %', v_result;
  END IF;

  -- A different workout type from the same source message is legitimate.
  v_result := public.register_workout_atomic(
    p_user_id => v_user_id,
    p_date => DATE '2026-07-11',
    p_workout_type => 'bicicleta',
    p_duration_min => 20,
    p_estimated_kcal => 50,
    p_provider_message_id => 'provider-workout-1'
  );

  IF NOT (v_result->>'inserted')::boolean
    OR (v_result->>'exercise_calories')::integer <> 150 THEN
    RAISE EXCEPTION 'second workout type failed: %', v_result;
  END IF;

  -- Same provider/type retry is idempotent.
  v_result := public.register_workout_atomic(
    p_user_id => v_user_id,
    p_date => DATE '2026-07-11',
    p_workout_type => 'caminhada',
    p_duration_min => 60,
    p_estimated_kcal => 100,
    p_provider_message_id => 'provider-workout-1'
  );

  IF (v_result->>'inserted')::boolean
    OR (v_result->>'exercise_calories')::integer <> 150 THEN
    RAISE EXCEPTION 'workout retry was not idempotent: %', v_result;
  END IF;

  -- Correction replaces only the recent workout of the same type and derives
  -- the aggregate from remaining source rows in one transaction.
  v_result := public.register_workout_atomic(
    p_user_id => v_user_id,
    p_date => DATE '2026-07-11',
    p_workout_type => 'caminhada',
    p_duration_min => 30,
    p_estimated_kcal => 40,
    p_provider_message_id => 'provider-workout-2',
    p_replace_recent => true,
    p_replace_since => timestamptz '2026-07-10 00:00:00+00'
  );

  SELECT count(*), max(snapshot.exercise_calories)
  INTO v_log_count, v_snapshot_kcal
  FROM public.workout_logs AS workout
  JOIN public.daily_snapshots AS snapshot ON snapshot.id = workout.snapshot_id
  WHERE workout.user_id = v_user_id;

  IF (v_result->>'replaced_count')::integer <> 1
    OR NOT (v_result->>'inserted')::boolean
    OR v_log_count <> 2
    OR v_snapshot_kcal <> 90 THEN
    RAISE EXCEPTION 'workout replace invariant failed: result %, logs %, kcal %',
      v_result, v_log_count, v_snapshot_kcal;
  END IF;

  BEGIN
    PERFORM public.register_workout_atomic(
      p_user_id => v_user_id,
      p_date => DATE '2026-07-11',
      p_workout_type => 'inválido',
      p_duration_min => 30,
      p_estimated_kcal => -1
    );
    RAISE EXCEPTION 'invalid workout payload was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'invalid workout payload was accepted' THEN
        RAISE;
      END IF;
  END;

  SELECT count(*), max(snapshot.exercise_calories)
  INTO v_log_count, v_snapshot_kcal
  FROM public.workout_logs AS workout
  JOIN public.daily_snapshots AS snapshot ON snapshot.id = workout.snapshot_id
  WHERE workout.user_id = v_user_id;

  IF v_log_count <> 2 OR v_snapshot_kcal <> 90 THEN
    RAISE EXCEPTION 'invalid call changed workout state: logs %, kcal %',
      v_log_count, v_snapshot_kcal;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute register_workout_atomic';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.register_workout_atomic(uuid,date,text,integer,integer,text,text,timestamptz,text,integer,numeric,boolean,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute register_workout_atomic';
  END IF;
END;
$test$;

ROLLBACK;
