BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000550';
  v_result jsonb;
  v_event_count integer;
  v_next date;
BEGIN
  INSERT INTO public.users (id, wpp, status)
  VALUES (v_user_id, '15550000550', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_progress (user_id, next_reevaluation)
  VALUES (v_user_id, NULL)
  ON CONFLICT (user_id) DO UPDATE SET next_reevaluation = NULL;

  INSERT INTO public.daily_snapshots (user_id, date, calories_consumed)
  VALUES
    (v_user_id, DATE '2026-06-01', 1000),
    (v_user_id, DATE '2026-06-05', 1100)
  ON CONFLICT (user_id, date) DO NOTHING;

  v_result := public.advance_reevaluation_schedule(v_user_id, DATE '2026-06-05');
  SELECT next_reevaluation INTO v_next
  FROM public.user_progress WHERE user_id = v_user_id;

  IF v_result->>'status' <> 'bootstrapped' OR v_next <> DATE '2026-06-15' THEN
    RAISE EXCEPTION 'reevaluation bootstrap failed: result %, next %', v_result, v_next;
  END IF;

  v_result := public.advance_reevaluation_schedule(v_user_id, DATE '2026-06-15');
  SELECT next_reevaluation INTO v_next
  FROM public.user_progress WHERE user_id = v_user_id;
  SELECT count(*) INTO v_event_count
  FROM public.product_events
  WHERE user_id = v_user_id AND event = 'reevaluation.due';

  IF v_result->>'status' <> 'due'
    OR v_next <> DATE '2026-06-29'
    OR v_event_count <> 1 THEN
    RAISE EXCEPTION 'reevaluation due transition failed: result %, next %, events %',
      v_result, v_next, v_event_count;
  END IF;

  v_result := public.advance_reevaluation_schedule(v_user_id, DATE '2026-06-15');
  SELECT count(*) INTO v_event_count
  FROM public.product_events
  WHERE user_id = v_user_id AND event = 'reevaluation.due';
  IF v_result->>'status' <> 'not_due' OR v_event_count <> 1 THEN
    RAISE EXCEPTION 'reevaluation retry duplicated state: result %, events %',
      v_result, v_event_count;
  END IF;

  UPDATE public.user_progress
  SET next_reevaluation = DATE '2026-01-01'
  WHERE user_id = v_user_id;

  v_result := public.advance_reevaluation_schedule(v_user_id, DATE '2026-07-12');
  SELECT next_reevaluation INTO v_next
  FROM public.user_progress WHERE user_id = v_user_id;
  SELECT count(*) INTO v_event_count
  FROM public.product_events
  WHERE user_id = v_user_id AND event = 'reevaluation.due';

  IF v_result->>'status' <> 'due'
    OR v_next <= DATE '2026-07-12'
    OR v_event_count <> 2 THEN
    RAISE EXCEPTION 'overdue reevaluation did not catch up: result %, next %, events %',
      v_result, v_next, v_event_count;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.advance_reevaluation_schedule(uuid,date)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute advance_reevaluation_schedule';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.advance_reevaluation_schedule(uuid,date)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute advance_reevaluation_schedule';
  END IF;
END;
$test$;

ROLLBACK;
