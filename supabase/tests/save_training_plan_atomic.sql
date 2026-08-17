BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000444';
  v_old_plan_id uuid;
  v_new_plan_id uuid;
  v_retry_plan_id uuid;
  v_result jsonb;
  v_active_count integer;
  v_plan_count integer;
  v_reminders boolean;
BEGIN
  INSERT INTO public.users (id, wpp, name, metadata)
  VALUES (v_user_id, '16666666666', 'atomic-training-plan-test', '{}'::jsonb)
  ON CONFLICT (id) DO UPDATE SET metadata = '{}'::jsonb;

  INSERT INTO public.training_plans (
    user_id, plan_type, days_per_week, equipment_summary,
    weekly_schedule, generated_at, active
  ) VALUES (
    v_user_id, 'full_body', 2, 'peso corporal',
    '[{"day":"seg","focus":"full body","duration_min":30,"exercises":[]}]'::jsonb,
    timestamptz '2026-07-01 12:00:00+00', true
  ) RETURNING id INTO v_old_plan_id;

  v_result := public.save_training_plan_atomic(
    p_user_id => v_user_id,
    p_plan_type => 'split',
    p_days_per_week => 3,
    p_equipment_summary => 'halteres, barra fixa',
    p_weekly_schedule => '[{"day":"seg","focus":"inferiores","duration_min":60,"exercises":[{"name":"agachamento"}]}]'::jsonb,
    p_generated_by => 'agent',
    p_generated_at => timestamptz '2026-07-12 12:00:00+00',
    p_valid_until => timestamptz '2026-08-23 12:00:00+00',
    p_version => 1,
    p_notes => 'plano teste',
    p_request_key => 'provider-training-1'
  );
  v_new_plan_id := (v_result->>'plan_id')::uuid;

  SELECT count(*) FILTER (WHERE active), count(*)
  INTO v_active_count, v_plan_count
  FROM public.training_plans
  WHERE user_id = v_user_id;
  SELECT COALESCE((metadata->>'training_reminders')::boolean, false)
  INTO v_reminders
  FROM public.users
  WHERE id = v_user_id;

  IF NOT (v_result->>'inserted')::boolean
    OR v_new_plan_id = v_old_plan_id
    OR v_active_count <> 1
    OR v_plan_count <> 2
    OR NOT v_reminders THEN
    RAISE EXCEPTION 'atomic training plan save failed: %, active %, plans %, reminders %',
      v_result, v_active_count, v_plan_count, v_reminders;
  END IF;

  -- Same request is idempotent and cannot create a third plan.
  v_result := public.save_training_plan_atomic(
    p_user_id => v_user_id,
    p_plan_type => 'custom',
    p_days_per_week => 5,
    p_equipment_summary => 'must not overwrite retry',
    p_weekly_schedule => '[{"day":"ter","focus":"retry","duration_min":20,"exercises":[{"name":"retry"}]}]'::jsonb,
    p_generated_by => 'agent',
    p_generated_at => timestamptz '2026-07-12 12:01:00+00',
    p_valid_until => timestamptz '2026-08-23 12:01:00+00',
    p_version => 1,
    p_notes => NULL,
    p_request_key => 'provider-training-1'
  );
  v_retry_plan_id := (v_result->>'plan_id')::uuid;

  SELECT count(*) FILTER (WHERE active), count(*)
  INTO v_active_count, v_plan_count
  FROM public.training_plans
  WHERE user_id = v_user_id;

  IF (v_result->>'inserted')::boolean
    OR v_retry_plan_id <> v_new_plan_id
    OR v_active_count <> 1
    OR v_plan_count <> 2 THEN
    RAISE EXCEPTION 'training plan retry was not idempotent: %, active %, plans %',
      v_result, v_active_count, v_plan_count;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.save_training_plan_atomic(uuid,text,integer,text,jsonb,text,timestamptz,timestamptz,integer,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute save_training_plan_atomic';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.save_training_plan_atomic(uuid,text,integer,text,jsonb,text,timestamptz,timestamptz,integer,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute save_training_plan_atomic';
  END IF;
END;
$test$;

ROLLBACK;
