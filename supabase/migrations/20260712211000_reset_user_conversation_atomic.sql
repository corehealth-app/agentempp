CREATE OR REPLACE FUNCTION public.reset_user_conversation_atomic(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted integer;
  v_deleted_total integer := 0;
BEGIN
  PERFORM 1
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user % not found', p_user_id;
  END IF;

  DELETE FROM public.pending_registrations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.message_dispatch_outbox WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.message_buffer WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.tools_audit WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.llm_evaluations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.daily_gap_reminder_attempts WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.engagement_delivery_attempts WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.attention_dismissals WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.user_phrase_cooldown WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.user_food_corrections WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.prescriptions WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.training_plans WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.reevaluations WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.meal_logs WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.workout_logs WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.daily_snapshots WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.messages WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  DELETE FROM public.product_events WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  v_deleted_total := v_deleted_total + v_deleted;

  INSERT INTO public.user_profiles (
    user_id,
    onboarding_completed,
    onboarding_step
  ) VALUES (
    p_user_id,
    false,
    0
  )
  ON CONFLICT (user_id) DO UPDATE
  SET sex = null,
      birth_date = null,
      height_cm = null,
      weight_kg = null,
      body_fat_percent = null,
      body_fat_measured_at = null,
      activity_level = null,
      training_frequency = null,
      water_intake = null,
      hunger_level = null,
      wake_time = null,
      bedtime = null,
      current_protocol = null,
      goal_type = null,
      goal_value = null,
      deficit_level = null,
      food_organization = null,
      bf_percent_estimated = null,
      bf_source = null,
      bf_estimated_at = null,
      cycle_start_weight_kg = null,
      cycle_start_bf_percent = null,
      cycle_start_training_freq = null,
      cycle_start_at = null,
      onboarding_completed = false,
      onboarding_step = 0,
      updated_at = now();

  INSERT INTO public.user_progress (
    user_id,
    xp_total,
    level,
    current_streak,
    longest_streak,
    blocks_completed,
    deficit_block,
    badges_earned
  ) VALUES (
    p_user_id,
    0,
    1,
    0,
    0,
    0,
    0,
    '{}'::text[]
  )
  ON CONFLICT (user_id) DO UPDATE
  SET xp_total = 0,
      level = 1,
      current_streak = 0,
      longest_streak = 0,
      blocks_completed = 0,
      deficit_block = 0,
      current_weight = null,
      current_bf_percent = null,
      badges_earned = '{}'::text[],
      last_active_date = null,
      next_reevaluation = null,
      updated_at = now();

  UPDATE public.users
  SET name = null,
      summary = null,
      summary_updated_at = null,
      tags = '{}'::text[],
      admin_notes = null,
      country_confirmed = false,
      last_active_at = null,
      metadata = '{}'::jsonb,
      updated_at = now()
  WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'reset', true,
    'user_id', p_user_id,
    'deleted_rows', v_deleted_total
  );
END;
$$;
