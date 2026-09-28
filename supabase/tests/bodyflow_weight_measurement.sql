BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_user_a uuid := '00000000-0000-0000-0000-00000000a501';
  v_user_b uuid := '00000000-0000-0000-0000-00000000a502';
  v_legacy uuid := '00000000-0000-0000-0000-00000000a503';
  v_inactive uuid := '00000000-0000-0000-0000-00000000a504';
  v_now timestamptz := clock_timestamp();
  v_t1 timestamptz := date_trunc('second', clock_timestamp() - interval '2 days');
  v_t2 timestamptz := date_trunc('second', clock_timestamp() - interval '1 day');
  v_result jsonb;
  v_weight numeric;
  v_at timestamptz;
  v_snapshots_before bigint;
  v_progress_before bigint;
  v_failed boolean;
BEGIN
  INSERT INTO public.users (id, wpp, name, status)
  VALUES
    (v_user_a, '15550000501', 'weight-a', 'active'),
    (v_user_b, '15550000502', 'weight-b', 'active'),
    (v_legacy, '15550000503', 'weight-legacy', 'active'),
    (v_inactive, '15550000504', 'weight-inactive', 'blocked')
  ON CONFLICT (id) DO NOTHING;

  -- Privileges: only the trusted backend may execute the entry point.
  IF has_function_privilege('authenticated',
      'public.record_weight_atomic(uuid,numeric,text,timestamptz,text)', 'EXECUTE')
    OR has_function_privilege('anon',
      'public.record_weight_atomic(uuid,numeric,text,timestamptz,text)', 'EXECUTE')
    OR NOT has_function_privilege('service_role',
      'public.record_weight_atomic(uuid,numeric,text,timestamptz,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'record_weight_atomic privileges are wrong';
  END IF;

  SELECT count(*) INTO v_snapshots_before FROM public.daily_snapshots
  WHERE user_id IN (v_user_a, v_user_b, v_legacy);
  SELECT count(*) INTO v_progress_before FROM public.user_progress
  WHERE user_id IN (v_user_a, v_user_b, v_legacy);

  -- 1. First measurement creates the profile row with value and instant.
  v_result := public.record_weight_atomic(v_user_a, 78.456, 'kg', v_t1, 'weight-key-0001');
  SELECT weight_kg, weight_measured_at INTO v_weight, v_at
  FROM public.user_profiles WHERE user_id = v_user_a;
  IF NOT (v_result->>'applied')::boolean OR v_weight <> 78.46 OR v_at <> v_t1 THEN
    RAISE EXCEPTION 'first measurement not applied with 2-decimal rounding: % / % / %',
      v_result, v_weight, v_at;
  END IF;
  IF (SELECT weight_instant_source FROM public.user_profiles WHERE user_id = v_user_a)
    IS DISTINCT FROM 'measured' THEN
    RAISE EXCEPTION 'an informed measurement was not recorded as measured';
  END IF;

  -- 2. Replay of the same measurement (any time later): no effect.
  v_result := public.record_weight_atomic(v_user_a, 78.456, 'kg', v_t1, 'weight-key-0002');
  IF (v_result->>'applied')::boolean OR v_result->>'reason' <> 'same_measurement' THEN
    RAISE EXCEPTION 'replay was not recognised: %', v_result;
  END IF;

  -- 3. Same instant, different value: conflict, nothing changes.
  v_failed := false;
  BEGIN
    PERFORM public.record_weight_atomic(v_user_a, 80, 'kg', v_t1, 'weight-key-0003');
  EXCEPTION WHEN unique_violation THEN
    v_failed := true;
  END;
  SELECT weight_kg INTO v_weight FROM public.user_profiles WHERE user_id = v_user_a;
  IF NOT v_failed OR v_weight <> 78.46 THEN
    RAISE EXCEPTION 'same instant with another value must conflict (weight %)', v_weight;
  END IF;

  -- 4. Newer measurement wins.
  v_result := public.record_weight_atomic(v_user_a, 77.9, 'kg', v_t2, 'weight-key-0004');
  SELECT weight_kg, weight_measured_at INTO v_weight, v_at
  FROM public.user_profiles WHERE user_id = v_user_a;
  IF NOT (v_result->>'applied')::boolean OR v_weight <> 77.90 OR v_at <> v_t2 THEN
    RAISE EXCEPTION 'newer measurement not applied: %', v_result;
  END IF;

  -- 5. An older measurement arriving late does not replace the newer one.
  v_result := public.record_weight_atomic(
    v_user_a, 90, 'kg', v_t1 + interval '1 hour', 'weight-key-0005');
  SELECT weight_kg, weight_measured_at INTO v_weight, v_at
  FROM public.user_profiles WHERE user_id = v_user_a;
  IF (v_result->>'applied')::boolean
    OR v_result->>'reason' <> 'older_than_current'
    OR v_weight <> 77.90 OR v_at <> v_t2 THEN
    RAISE EXCEPTION 'older measurement replaced the current one: %', v_result;
  END IF;

  -- 6. Pounds are converted and rounded before comparing: 170 lb = 77.11 kg;
  --    the same measurement in pounds again is a replay.
  v_result := public.record_weight_atomic(v_user_b, 170, 'lb', v_t1, 'weight-key-0006');
  SELECT weight_kg INTO v_weight FROM public.user_profiles WHERE user_id = v_user_b;
  IF NOT (v_result->>'applied')::boolean OR v_weight <> 77.11 THEN
    RAISE EXCEPTION 'pound conversion wrong: % / %', v_result, v_weight;
  END IF;
  v_result := public.record_weight_atomic(v_user_b, 170, 'lb', v_t1, 'weight-key-0007');
  IF (v_result->>'applied')::boolean OR v_result->>'reason' <> 'same_measurement' THEN
    RAISE EXCEPTION 'replay in pounds was not recognised: %', v_result;
  END IF;

  -- 7. A does not change B (each call is bound to p_user_id).
  SELECT weight_kg INTO v_weight FROM public.user_profiles WHERE user_id = v_user_a;
  IF v_weight <> 77.90 THEN
    RAISE EXCEPTION 'user B changed user A';
  END IF;

  -- 8. Legacy value without instant: nothing is presumed about its age; a
  --    dated measurement is applied.
  INSERT INTO public.user_profiles (user_id, weight_kg) VALUES (v_legacy, 82);
  UPDATE public.user_profiles SET weight_measured_at = NULL WHERE user_id = v_legacy;
  SELECT weight_measured_at INTO v_at FROM public.user_profiles WHERE user_id = v_legacy;
  IF v_at IS NOT NULL THEN
    RAISE EXCEPTION 'test setup: legacy row must have no instant';
  END IF;
  v_result := public.record_weight_atomic(v_legacy, 81.5, 'kg', v_t1, 'weight-key-0008');
  SELECT weight_kg, weight_measured_at INTO v_weight, v_at
  FROM public.user_profiles WHERE user_id = v_legacy;
  IF NOT (v_result->>'applied')::boolean OR v_weight <> 81.50 OR v_at <> v_t1 THEN
    RAISE EXCEPTION 'measurement over a legacy value not applied: %', v_result;
  END IF;

  -- 9. Legacy writers (direct update, as the WhatsApp tool and the onboarding
  --    RPC do): the instant follows the write; clearing the weight clears it.
  UPDATE public.user_profiles SET weight_kg = 83 WHERE user_id = v_legacy;
  SELECT weight_kg, weight_measured_at INTO v_weight, v_at
  FROM public.user_profiles WHERE user_id = v_legacy;
  IF v_weight <> 83 OR v_at IS NULL OR v_at < v_now THEN
    RAISE EXCEPTION 'legacy write did not date the weight: % / %', v_weight, v_at;
  END IF;
  -- The instant of a legacy write is the time of the write, and says so.
  IF (SELECT weight_instant_source FROM public.user_profiles WHERE user_id = v_legacy)
    IS DISTINCT FROM 'recorded' THEN
    RAISE EXCEPTION 'a legacy write was presented as a measurement instant';
  END IF;
  UPDATE public.user_profiles SET weight_kg = NULL WHERE user_id = v_legacy;
  SELECT weight_measured_at INTO v_at FROM public.user_profiles WHERE user_id = v_legacy;
  IF v_at IS NOT NULL
    OR (SELECT weight_instant_source FROM public.user_profiles WHERE user_id = v_legacy) IS NOT NULL THEN
    RAISE EXCEPTION 'cleared weight kept an instant';
  END IF;
  -- An unrelated profile update does not touch the instant.
  UPDATE public.user_profiles SET weight_kg = 83 WHERE user_id = v_legacy;
  SELECT weight_measured_at INTO v_at FROM public.user_profiles WHERE user_id = v_legacy;
  UPDATE public.user_profiles SET height_cm = 170 WHERE user_id = v_legacy;
  IF (SELECT weight_measured_at FROM public.user_profiles WHERE user_id = v_legacy) <> v_at THEN
    RAISE EXCEPTION 'unrelated update changed the weight instant';
  END IF;

  -- 9b. A legacy write never moves the instant backwards: the app recorded a
  --     measurement a few minutes ahead of this clock, and the write that
  --     follows is still the newest.
  v_at := date_trunc('second', clock_timestamp() + interval '4 minutes');
  v_result := public.record_weight_atomic(v_legacy, 84, 'kg', v_at, 'weight-key-0009');
  UPDATE public.user_profiles SET weight_kg = 85 WHERE user_id = v_legacy;
  IF (SELECT weight_measured_at FROM public.user_profiles WHERE user_id = v_legacy) <= v_at THEN
    RAISE EXCEPTION 'legacy write moved the instant backwards';
  END IF;
  v_result := public.record_weight_atomic(v_legacy, 84, 'kg', v_at, 'weight-key-0009');
  IF (v_result->>'applied')::boolean
    OR (SELECT weight_kg FROM public.user_profiles WHERE user_id = v_legacy) <> 85 THEN
    RAISE EXCEPTION 'replay was applied over a newer legacy write: %', v_result;
  END IF;

  -- 10. Invalid payloads are refused and change nothing.
  FOR v_result IN
    SELECT * FROM jsonb_array_elements('[
      {"v": 29.99, "u": "kg", "o": "-1 day"},
      {"v": 300.01, "u": "kg", "o": "-1 day"},
      {"v": 70, "u": "st", "o": "-1 day"},
      {"v": 70, "u": "kg", "o": "10 minutes"},
      {"v": 70, "u": "kg", "o": "-8 days"}
    ]'::jsonb)
  LOOP
    v_failed := false;
    BEGIN
      PERFORM public.record_weight_atomic(
        v_user_a, (v_result->>'v')::numeric, v_result->>'u',
        clock_timestamp() + (v_result->>'o')::interval, 'weight-key-0010');
    EXCEPTION WHEN invalid_parameter_value THEN
      v_failed := true;
    END;
    IF NOT v_failed THEN
      RAISE EXCEPTION 'invalid payload accepted: %', v_result;
    END IF;
  END LOOP;

  v_failed := false;
  BEGIN
    PERFORM public.record_weight_atomic(v_inactive, 70, 'kg', v_t1, 'weight-key-0011');
  EXCEPTION WHEN invalid_parameter_value THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'inactive user accepted';
  END IF;

  v_failed := false;
  BEGIN
    PERFORM public.record_weight_atomic(v_user_a, 70, 'kg', v_t1, 'short');
  EXCEPTION WHEN invalid_parameter_value THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'invalid idempotency key accepted';
  END IF;

  SELECT weight_kg INTO v_weight FROM public.user_profiles WHERE user_id = v_user_a;
  IF v_weight <> 77.90 THEN
    RAISE EXCEPTION 'refused payload changed the weight';
  END IF;

  -- 11. Nothing else was written: snapshots and progress are untouched.
  IF (SELECT count(*) FROM public.daily_snapshots
      WHERE user_id IN (v_user_a, v_user_b, v_legacy)) <> v_snapshots_before
    OR (SELECT count(*) FROM public.user_progress
      WHERE user_id IN (v_user_a, v_user_b, v_legacy)) <> v_progress_before THEN
    RAISE EXCEPTION 'weight recording wrote snapshots or progress';
  END IF;
END;
$test$;

-- 12a. The guard itself: with every privilege but without the trusted
--      backend's claim, the function refuses.
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
DO $test$
DECLARE
  v_failed boolean := false;
BEGIN
  BEGIN
    PERFORM public.record_weight_atomic(
      '00000000-0000-0000-0000-00000000a501', 70, 'kg', clock_timestamp(), 'weight-key-0013');
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'record_weight_atomic ran without the trusted backend';
  END IF;
END;
$test$;

-- 12b. As the backend's own role the entry point works.
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
DO $test$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public.record_weight_atomic(
    '00000000-0000-0000-0000-00000000a502', 171, 'lb',
    date_trunc('second', clock_timestamp()), 'weight-key-0014');
  IF NOT (v_result->>'applied')::boolean THEN
    RAISE EXCEPTION 'service_role could not record a weight: %', v_result;
  END IF;
END;
$test$;
RESET ROLE;

-- 12. Without the trusted backend the entry point refuses.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);

DO $test$
DECLARE
  v_failed boolean := false;
BEGIN
  BEGIN
    PERFORM public.record_weight_atomic(
      '00000000-0000-0000-0000-00000000a501', 70, 'kg', clock_timestamp(), 'weight-key-0012');
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'authenticated role executed record_weight_atomic';
  END IF;
END;
$test$;

ROLLBACK;
