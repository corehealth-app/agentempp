BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000111';
  v_result jsonb;
  v_log_count integer;
  v_snapshot_kcal integer;
BEGIN
  INSERT INTO public.users (id, wpp, name)
  VALUES (v_user_id, '19999999999', 'atomic-test')
  ON CONFLICT (id) DO NOTHING;

  v_result := public.register_meal_atomic(
    p_user_id => v_user_id,
    p_date => DATE '2026-07-11',
    p_meal_type => 'almoco'::public.meal_type_enum,
    p_items => '[
      {"food_name":"arroz","quantity_g":100,"kcal":100,"protein_g":2,"carbs_g":20,"fat_g":1,"source":"taco","confidence":1},
      {"food_name":"frango","quantity_g":120,"kcal":200,"protein_g":35,"carbs_g":0,"fat_g":7,"source":"taco","confidence":1}
    ]'::jsonb,
    p_provider_message_id => 'provider-atomic-1',
    p_calories_target => 1900,
    p_protein_target => 140
  );

  IF (v_result->>'inserted_count')::integer <> 2 THEN
    RAISE EXCEPTION 'first insert count mismatch: %', v_result;
  END IF;

  SELECT count(*), max(snapshot.calories_consumed)
  INTO v_log_count, v_snapshot_kcal
  FROM public.meal_logs AS meal
  JOIN public.daily_snapshots AS snapshot ON snapshot.id = meal.snapshot_id
  WHERE meal.user_id = v_user_id;

  IF v_log_count <> 2 OR v_snapshot_kcal <> 300 THEN
    RAISE EXCEPTION 'first insert invariant failed: logs %, kcal %', v_log_count, v_snapshot_kcal;
  END IF;

  -- Same provider/item retry must be idempotent and keep the derived total.
  v_result := public.register_meal_atomic(
    p_user_id => v_user_id,
    p_date => DATE '2026-07-11',
    p_meal_type => 'almoco'::public.meal_type_enum,
    p_items => '[
      {"food_name":"arroz","quantity_g":100,"kcal":100,"protein_g":2,"carbs_g":20,"fat_g":1,"source":"taco","confidence":1},
      {"food_name":"frango","quantity_g":120,"kcal":200,"protein_g":35,"carbs_g":0,"fat_g":7,"source":"taco","confidence":1}
    ]'::jsonb,
    p_provider_message_id => 'provider-atomic-1'
  );

  IF (v_result->>'inserted_count')::integer <> 0
    OR (v_result->>'calories_consumed')::integer <> 300 THEN
    RAISE EXCEPTION 'retry invariant failed: %', v_result;
  END IF;

  -- Replace removes and inserts in the same transaction, then derives totals.
  v_result := public.register_meal_atomic(
    p_user_id => v_user_id,
    p_date => DATE '2026-07-11',
    p_meal_type => 'almoco'::public.meal_type_enum,
    p_items => '[
      {"food_name":"frango grelhado","quantity_g":120,"kcal":150,"protein_g":34,"carbs_g":0,"fat_g":3,"source":"pending_approved","confidence":1}
    ]'::jsonb,
    p_replace => true,
    p_replace_meal_types => ARRAY['almoco'::public.meal_type_enum],
    p_provider_message_id => 'provider-atomic-2'
  );

  SELECT count(*), max(snapshot.calories_consumed)
  INTO v_log_count, v_snapshot_kcal
  FROM public.meal_logs AS meal
  JOIN public.daily_snapshots AS snapshot ON snapshot.id = meal.snapshot_id
  WHERE meal.user_id = v_user_id;

  IF (v_result->>'replaced_count')::integer <> 2
    OR (v_result->>'inserted_count')::integer <> 1
    OR v_log_count <> 1
    OR v_snapshot_kcal <> 150 THEN
    RAISE EXCEPTION 'replace invariant failed: result %, logs %, kcal %',
      v_result, v_log_count, v_snapshot_kcal;
  END IF;

  BEGIN
    PERFORM public.register_meal_atomic(
      p_user_id => v_user_id,
      p_date => DATE '2026-07-11',
      p_meal_type => 'lanche'::public.meal_type_enum,
      p_items => '[{"food_name":"inválido","quantity_g":0,"kcal":10,"protein_g":0,"carbs_g":1,"fat_g":0}]'::jsonb
    );
    RAISE EXCEPTION 'invalid payload was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'invalid payload was accepted' THEN
        RAISE;
      END IF;
  END;

  IF has_function_privilege(
    'anon',
    'public.register_meal_atomic(uuid,date,public.meal_type_enum,jsonb,boolean,public.meal_type_enum[],timestamptz,text,integer,numeric)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute register_meal_atomic';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.register_meal_atomic(uuid,date,public.meal_type_enum,jsonb,boolean,public.meal_type_enum[],timestamptz,text,integer,numeric)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute register_meal_atomic';
  END IF;
END;
$test$;

ROLLBACK;
