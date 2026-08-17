ALTER TABLE public.training_plans
  ADD COLUMN IF NOT EXISTS source_request_key text;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_training_plans_request
  ON public.training_plans (user_id, source_request_key)
  WHERE source_request_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_training_plans_one_active
  ON public.training_plans (user_id)
  WHERE active = true;

CREATE OR REPLACE FUNCTION public.save_training_plan_atomic(
  p_user_id uuid,
  p_plan_type text,
  p_days_per_week integer,
  p_equipment_summary text,
  p_weekly_schedule jsonb,
  p_generated_by text,
  p_generated_at timestamptz,
  p_valid_until timestamptz,
  p_version integer,
  p_notes text,
  p_request_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_plan_id uuid;
  v_request_key text := NULLIF(btrim(p_request_key), '');
BEGIN
  IF p_user_id IS NULL
    OR p_plan_type IS NULL
    OR p_plan_type NOT IN ('split', 'full_body', 'custom')
    OR p_days_per_week IS NULL OR p_days_per_week < 1 OR p_days_per_week > 7
    OR jsonb_typeof(p_weekly_schedule) <> 'array'
    OR jsonb_array_length(p_weekly_schedule) < 1
    OR jsonb_array_length(p_weekly_schedule) > 7
    OR p_version IS NULL OR p_version < 1 THEN
    RAISE EXCEPTION 'invalid training plan payload';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':training-plan', 0));

  IF v_request_key IS NOT NULL THEN
    SELECT id
    INTO v_plan_id
    FROM public.training_plans
    WHERE user_id = p_user_id AND source_request_key = v_request_key
    LIMIT 1;

    IF v_plan_id IS NOT NULL THEN
      RETURN jsonb_build_object('plan_id', v_plan_id, 'inserted', false);
    END IF;
  END IF;

  UPDATE public.training_plans
  SET active = false
  WHERE user_id = p_user_id AND active = true;

  INSERT INTO public.training_plans (
    user_id,
    plan_type,
    days_per_week,
    equipment_summary,
    weekly_schedule,
    generated_by,
    generated_at,
    valid_until,
    active,
    version,
    notes,
    source_request_key
  ) VALUES (
    p_user_id,
    p_plan_type,
    p_days_per_week,
    p_equipment_summary,
    p_weekly_schedule,
    COALESCE(NULLIF(btrim(p_generated_by), ''), 'agent'),
    COALESCE(p_generated_at, now()),
    p_valid_until,
    true,
    p_version,
    p_notes,
    v_request_key
  )
  RETURNING id INTO v_plan_id;

  UPDATE public.users
  SET
    metadata = COALESCE(metadata, '{}'::jsonb) || '{"training_reminders": true}'::jsonb,
    updated_at = now()
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'training plan user not found';
  END IF;

  RETURN jsonb_build_object('plan_id', v_plan_id, 'inserted', true);
END;
$$;
