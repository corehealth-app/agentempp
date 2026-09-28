BEGIN;

SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $test$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-00000000e511';
  v_message uuid;
  v_plan uuid;
  v_prescription uuid;
  v_draft uuid;
  v_result jsonb;
BEGIN
  INSERT INTO public.users (id, wpp, name, status, metadata)
  VALUES (v_user, '15550000911', 'reset-keeps-plans', 'active',
          '{"buttons_enabled":true,"training_reminders":true,"training_delivery_hour":7}'::jsonb);
  INSERT INTO public.messages (user_id, direction, role, content_type, content, provider)
  VALUES (v_user, 'in', 'user', 'text', 'monte meu treino', 'mobile_flow')
  RETURNING id INTO v_message;
  INSERT INTO public.meal_logs (user_id, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, meal_type)
  VALUES (v_user, 'arroz', 100, 128, 2.5, 28, 0.2, 'almoco');
  INSERT INTO public.training_plans (user_id, plan_type, days_per_week, weekly_schedule, generated_by)
  VALUES (v_user, 'split', 2, '[{"day":"seg"}]'::jsonb, 'flow_draft')
  RETURNING id INTO v_plan;
  INSERT INTO public.prescriptions (user_id, type, payload, generated_by)
  VALUES (v_user, 'diet', '{"daily_meals":[]}'::jsonb, 'patient_import')
  RETURNING id INTO v_prescription;
  v_draft := (public.create_plan_draft_atomic(
    v_user, 'training', 'flow_generated', 'ready_for_review',
    '{"weekly_schedule":[{"day":"seg","focus":"a","duration_min":30,"exercises":[]}]}'::jsonb,
    NULL, NULL, NULL, NULL, v_message, NULL, 'reset/keeps-plans-0001')->>'id')::uuid;

  -- 1. The default reset keeps plans and drafts, and wipes the rest.
  v_result := public.reset_user_conversation_atomic(v_user);
  IF NOT (v_result->>'kept_plans')::boolean
    OR NOT EXISTS (SELECT 1 FROM public.training_plans WHERE id = v_plan AND active)
    OR NOT EXISTS (SELECT 1 FROM public.prescriptions WHERE id = v_prescription)
    OR NOT EXISTS (SELECT 1 FROM public.plan_drafts WHERE id = v_draft AND source_message_id IS NULL)
    OR EXISTS (SELECT 1 FROM public.messages WHERE user_id = v_user)
    OR EXISTS (SELECT 1 FROM public.meal_logs WHERE user_id = v_user)
    OR (SELECT metadata FROM public.users WHERE id = v_user)
       <> '{"training_reminders":true,"training_delivery_hour":7}'::jsonb
    OR (SELECT onboarding_completed FROM public.user_profiles WHERE user_id = v_user) THEN
    RAISE EXCEPTION 'default reset did not keep exactly the plans: %', v_result;
  END IF;

  -- 2. The kept draft is still reviewable and confirmable.
  v_result := public.confirm_plan_draft_atomic(v_user, v_draft, 1, NULL, 'confirm-after-reset-1');
  IF v_result->>'status' <> 'confirmed' THEN
    RAISE EXCEPTION 'draft kept by the reset could not be confirmed: %', v_result;
  END IF;

  -- 3. The explicit full reset removes plans and drafts too.
  v_result := public.reset_user_conversation_atomic(v_user, false);
  IF (v_result->>'kept_plans')::boolean
    OR EXISTS (SELECT 1 FROM public.training_plans WHERE user_id = v_user)
    OR EXISTS (SELECT 1 FROM public.prescriptions WHERE user_id = v_user)
    OR EXISTS (SELECT 1 FROM public.plan_drafts WHERE user_id = v_user)
    OR (SELECT metadata FROM public.users WHERE id = v_user) <> '{}'::jsonb THEN
    RAISE EXCEPTION 'full reset kept plans: %', v_result;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user) THEN
    RAISE EXCEPTION 'reset removed the account';
  END IF;

  -- 4. Privileges and the guard.
  IF has_function_privilege('authenticated', 'public.reset_user_conversation_atomic(uuid,boolean)', 'EXECUTE')
    OR has_function_privilege('anon', 'public.reset_user_conversation_atomic(uuid,boolean)', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.reset_user_conversation_atomic(uuid)', 'EXECUTE')
    OR NOT has_function_privilege('service_role', 'public.reset_user_conversation_atomic(uuid,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'reset privileges are wrong';
  END IF;
END;
$test$;

SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
DO $test$
DECLARE
  v_failed boolean := false;
BEGIN
  BEGIN
    PERFORM public.reset_user_conversation_atomic('00000000-0000-0000-0000-00000000e511', true);
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'reset ran without the trusted backend'; END IF;
END;
$test$;

ROLLBACK;
