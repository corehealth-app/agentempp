BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000111';
  v_result jsonb;
  v_log_count integer;
  v_snapshot_kcal integer;
  v_arroz_log_id uuid;
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

  SELECT id
  INTO v_arroz_log_id
  FROM public.meal_logs
  WHERE user_id = v_user_id
    AND food_name = 'arroz';

  -- Item-scoped replace must reject a full-meal payload that repeats an
  -- untouched row from the same registration group.
  BEGIN
    PERFORM public.register_meal_atomic_scoped(
      p_user_id => v_user_id,
      p_date => DATE '2026-07-11',
      p_meal_type => 'almoco'::public.meal_type_enum,
      p_items => '[
        {"food_name":"arroz integral","quantity_g":100,"kcal":90,"protein_g":2,"carbs_g":19,"fat_g":1,"source":"pending_approved","confidence":1},
        {"food_name":"frango","quantity_g":120,"kcal":200,"protein_g":35,"carbs_g":0,"fat_g":7,"source":"pending_approved","confidence":1}
      ]'::jsonb,
      p_replace => true,
      p_replace_log_ids => ARRAY[v_arroz_log_id],
      p_provider_message_id => 'provider-atomic-unsafe-full-payload'
    );
    RAISE EXCEPTION 'unsafe scoped full payload was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'unsafe scoped full payload was accepted' THEN
        RAISE;
      END IF;
  END;

  -- A one-for-one replacement may legitimately have the same name and
  -- quantity as an untouched item (for example, salame -> a second egg).
  -- Exercise it in a savepoint-like PL/pgSQL block and roll it back on purpose.
  BEGIN
    PERFORM public.register_meal_atomic_scoped(
      p_user_id => v_user_id,
      p_date => DATE '2026-07-11',
      p_meal_type => 'almoco'::public.meal_type_enum,
      p_items => '[
        {"food_name":"frango","quantity_g":120,"kcal":200,"protein_g":35,"carbs_g":0,"fat_g":7,"source":"pending_approved","confidence":1}
      ]'::jsonb,
      p_replace => true,
      p_replace_log_ids => ARRAY[v_arroz_log_id],
      p_provider_message_id => 'provider-atomic-legitimate-identical-item'
    );
    IF (
      SELECT count(*)
      FROM public.meal_logs
      WHERE user_id = v_user_id
        AND food_name = 'frango'
    ) <> 2 THEN
      RAISE EXCEPTION 'legitimate identical replacement did not insert one item';
    END IF;
    RAISE EXCEPTION 'rollback-legitimate-identical-replacement';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'rollback-legitimate-identical-replacement' THEN
        RAISE;
      END IF;
  END;

  -- An item correction must preserve the other item from the same meal.
  v_result := public.register_meal_atomic_scoped(
    p_user_id => v_user_id,
    p_date => DATE '2026-07-11',
    p_meal_type => 'almoco'::public.meal_type_enum,
    p_items => '[
      {"food_name":"arroz integral","quantity_g":100,"kcal":90,"protein_g":2,"carbs_g":19,"fat_g":1,"source":"pending_approved","confidence":1}
    ]'::jsonb,
    p_replace => true,
    p_replace_log_ids => ARRAY[v_arroz_log_id],
    p_provider_message_id => 'provider-atomic-scoped'
  );

  SELECT count(*), max(snapshot.calories_consumed)
  INTO v_log_count, v_snapshot_kcal
  FROM public.meal_logs AS meal
  JOIN public.daily_snapshots AS snapshot ON snapshot.id = meal.snapshot_id
  WHERE meal.user_id = v_user_id;

  IF (v_result->>'replaced_count')::integer <> 1
    OR v_log_count <> 2
    OR v_snapshot_kcal <> 290
    OR NOT EXISTS (
      SELECT 1 FROM public.meal_logs
      WHERE user_id = v_user_id AND food_name = 'frango'
    ) THEN
    RAISE EXCEPTION 'scoped replace removed unrelated items: result %, logs %, kcal %',
      v_result, v_log_count, v_snapshot_kcal;
  END IF;

  -- A stale/foreign target must fail before deleting any valid item.
  BEGIN
    PERFORM public.register_meal_atomic_scoped(
      p_user_id => v_user_id,
      p_date => DATE '2026-07-11',
      p_meal_type => 'almoco'::public.meal_type_enum,
      p_items => '[
        {"food_name":"arroz integral","quantity_g":100,"kcal":85,"protein_g":2,"carbs_g":18,"fat_g":1,"source":"pending_approved","confidence":1}
      ]'::jsonb,
      p_replace => true,
      p_replace_log_ids => ARRAY['00000000-0000-0000-0000-000000000999'::uuid],
      p_provider_message_id => 'provider-atomic-invalid-target'
    );
    RAISE EXCEPTION 'invalid scoped target was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'invalid scoped target was accepted' THEN
        RAISE;
      END IF;
  END;

  SELECT count(*), max(snapshot.calories_consumed)
  INTO v_log_count, v_snapshot_kcal
  FROM public.meal_logs AS meal
  JOIN public.daily_snapshots AS snapshot ON snapshot.id = meal.snapshot_id
  WHERE meal.user_id = v_user_id;

  IF v_log_count <> 2 OR v_snapshot_kcal <> 290 THEN
    RAISE EXCEPTION 'invalid scoped target changed state: logs %, kcal %',
      v_log_count, v_snapshot_kcal;
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

  IF has_function_privilege(
    'anon',
    'public.register_meal_atomic_scoped(uuid,date,public.meal_type_enum,jsonb,boolean,public.meal_type_enum[],timestamptz,text,integer,numeric,uuid[])',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute register_meal_atomic_scoped';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.register_meal_atomic_scoped(uuid,date,public.meal_type_enum,jsonb,boolean,public.meal_type_enum[],timestamptz,text,integer,numeric,uuid[])',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute register_meal_atomic_scoped';
  END IF;
END;
$test$;

-- Incident matrix 2026-09-28: a decimal quantity or kcal is stored as sent,
-- a legitimate 0 kcal item is a row (not a missing calculation), and the
-- patient-reported origin survives the write. The day total keeps the
-- existing integer rounding of calories_consumed.
DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000112';
  v_result jsonb;
  v_rows jsonb;
BEGIN
  INSERT INTO public.users (id, wpp, name)
  VALUES (v_user_id, '19999999998', 'atomic-decimal-test')
  ON CONFLICT (id) DO NOTHING;

  v_result := public.register_meal_atomic(
    p_user_id => v_user_id,
    p_date => DATE '2026-09-27',
    p_meal_type => 'almoco'::public.meal_type_enum,
    p_items => '[
      {"food_name":"Arroz branco cozido","quantity_g":150.5,"kcal":192.4,"protein_g":3.8,"carbs_g":42.1,"fat_g":0.3,"source":"taco","confidence":1},
      {"food_name":"Feijão carioca cozido","quantity_g":86.5,"kcal":66.1,"protein_g":4.1,"carbs_g":11.8,"fat_g":0.4,"source":"user_kcal","confidence":1},
      {"food_name":"Café sem açúcar","quantity_g":50,"kcal":0,"protein_g":0,"carbs_g":0,"fat_g":0,"source":"taco","confidence":1}
    ]'::jsonb,
    p_provider_message_id => 'provider-atomic-decimal-1'
  );

  IF (v_result->>'inserted_count')::integer <> 3 THEN
    RAISE EXCEPTION 'decimal/zero insert count mismatch: %', v_result;
  END IF;

  SELECT jsonb_object_agg(meal.food_name, jsonb_build_object(
           'quantity_g', meal.quantity_g, 'kcal', meal.kcal, 'source', meal.source))
  INTO v_rows
  FROM public.meal_logs AS meal
  WHERE meal.user_id = v_user_id;

  IF (v_rows->'Arroz branco cozido'->>'quantity_g')::numeric <> 150.5
    OR (v_rows->'Arroz branco cozido'->>'kcal')::numeric <> 192.4
    OR (v_rows->'Feijão carioca cozido'->>'quantity_g')::numeric <> 86.5 THEN
    RAISE EXCEPTION 'decimal quantity or kcal was not stored as sent: %', v_rows;
  END IF;

  IF NOT (v_rows ? 'Café sem açúcar')
    OR (v_rows->'Café sem açúcar'->>'kcal')::numeric <> 0 THEN
    RAISE EXCEPTION 'legitimate zero kcal item was not stored as a zero row: %', v_rows;
  END IF;

  IF v_rows->'Feijão carioca cozido'->>'source' <> 'user_kcal' THEN
    RAISE EXCEPTION 'patient-reported kcal origin was not preserved: %', v_rows;
  END IF;

  IF (v_result->>'calories_consumed')::integer <> 259 THEN
    RAISE EXCEPTION 'day total must be round(192.4 + 66.1 + 0) = 259: %', v_result;
  END IF;
END;
$test$;

ROLLBACK;
