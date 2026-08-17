BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000777';
  v_old_id uuid;
  v_first_id uuid;
  v_retry_id uuid;
  v_second_id uuid;
  v_result jsonb;
  v_pending_count integer;
  v_total_count integer;
BEGIN
  INSERT INTO public.users (id, wpp, name, metadata)
  VALUES (v_user_id, '17777777777', 'atomic-pending-test', '{}'::jsonb)
  ON CONFLICT (id) DO UPDATE SET metadata = '{}'::jsonb;

  INSERT INTO public.pending_registrations (user_id, proposal, expires_at)
  VALUES (
    v_user_id,
    '{"kind":"meal","mealType":"cafe"}'::jsonb,
    timestamptz '2026-07-13 20:00:00+00'
  ) RETURNING id INTO v_old_id;

  v_result := public.replace_pending_registration_atomic(
    p_user_id => v_user_id,
    p_proposal => '{"kind":"meal","mealType":"almoco"}'::jsonb,
    p_expires_at => timestamptz '2026-07-13 21:00:00+00',
    p_request_key => 'provider-pending-1'
  );
  v_first_id := (v_result->>'pending_id')::uuid;

  SELECT count(*) FILTER (WHERE status = 'pending'), count(*)
  INTO v_pending_count, v_total_count
  FROM public.pending_registrations
  WHERE user_id = v_user_id;

  IF NOT (v_result->>'created')::boolean
    OR (v_result->>'cancelled_count')::integer <> 1
    OR v_first_id = v_old_id
    OR v_pending_count <> 1
    OR v_total_count <> 2 THEN
    RAISE EXCEPTION 'atomic pending replacement failed: %, pending %, total %',
      v_result, v_pending_count, v_total_count;
  END IF;

  v_result := public.replace_pending_registration_atomic(
    p_user_id => v_user_id,
    p_proposal => '{"kind":"meal","mealType":"jantar"}'::jsonb,
    p_expires_at => timestamptz '2026-07-13 22:00:00+00',
    p_request_key => 'provider-pending-1'
  );
  v_retry_id := (v_result->>'pending_id')::uuid;

  SELECT count(*) FILTER (WHERE status = 'pending'), count(*)
  INTO v_pending_count, v_total_count
  FROM public.pending_registrations
  WHERE user_id = v_user_id;

  IF (v_result->>'created')::boolean
    OR v_retry_id <> v_first_id
    OR v_pending_count <> 1
    OR v_total_count <> 2 THEN
    RAISE EXCEPTION 'pending retry was not idempotent: %, pending %, total %',
      v_result, v_pending_count, v_total_count;
  END IF;

  v_result := public.replace_pending_registration_atomic(
    p_user_id => v_user_id,
    p_proposal => '{"kind":"workout","workoutType":"musculacao"}'::jsonb,
    p_expires_at => timestamptz '2026-07-13 23:00:00+00',
    p_request_key => 'provider-pending-2'
  );
  v_second_id := (v_result->>'pending_id')::uuid;

  SELECT count(*) FILTER (WHERE status = 'pending'), count(*)
  INTO v_pending_count, v_total_count
  FROM public.pending_registrations
  WHERE user_id = v_user_id;

  IF NOT (v_result->>'created')::boolean
    OR v_second_id = v_first_id
    OR v_pending_count <> 1
    OR v_total_count <> 3 THEN
    RAISE EXCEPTION 'second pending replacement failed: %, pending %, total %',
      v_result, v_pending_count, v_total_count;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.replace_pending_registration_atomic(uuid,jsonb,timestamptz,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute replace_pending_registration_atomic';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.replace_pending_registration_atomic(uuid,jsonb,timestamptz,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute replace_pending_registration_atomic';
  END IF;
END;
$test$;

ROLLBACK;
