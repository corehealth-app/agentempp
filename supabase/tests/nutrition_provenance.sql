BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000112';
  v_food_id integer;
  v_snapshot_id uuid;
  v_result jsonb;
  v_log_count integer;
  v_snapshot_kcal integer;
BEGIN
  INSERT INTO public.users (id, wpp, name)
  VALUES (v_user_id, '18888888888', 'nutrition-provenance-test')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.food_db (
    name_pt,
    category,
    kcal_per_100g,
    protein_g,
    carbs_g,
    fat_g,
    fiber_g,
    source,
    country_code
  ) VALUES (
    'alimento canonico teste atomico',
    'testes',
    100,
    10,
    12,
    2,
    1,
    'test_fixture',
    'BR'
  )
  RETURNING id INTO v_food_id;

  v_result := public.register_meal_atomic(
    p_user_id => v_user_id,
    p_date => DATE '2026-07-13',
    p_meal_type => 'almoco'::public.meal_type_enum,
    p_items => jsonb_build_array(jsonb_build_object(
      'food_name', 'alimento canonico teste atomico',
      'food_db_id', v_food_id,
      'quantity_g', 100,
      'kcal', 100,
      'protein_g', 10,
      'carbs_g', 12,
      'fat_g', 2,
      'source', 'canonical_exact',
      'confidence', 1
    )),
    p_provider_message_id => 'provider-nutrition-valid'
  );

  SELECT meal.snapshot_id, count(*)
  INTO v_snapshot_id, v_log_count
  FROM public.meal_logs AS meal
  WHERE meal.user_id = v_user_id
    AND meal.food_db_id = v_food_id
  GROUP BY meal.snapshot_id;

  IF (v_result->>'inserted_count')::integer <> 1 OR v_log_count <> 1 THEN
    RAISE EXCEPTION 'canonical provenance was not persisted: result %, count %',
      v_result, v_log_count;
  END IF;

  BEGIN
    INSERT INTO public.food_db (
      name_pt,
      category,
      kcal_per_100g,
      protein_g,
      carbs_g,
      fat_g,
      fiber_g,
      source,
      country_code
    ) VALUES (
      'Alimento Canônico Teste Atômico',
      'testes',
      100,
      10,
      12,
      2,
      1,
      'duplicate_fixture',
      'BR'
    );
    RAISE EXCEPTION 'duplicate canonical food was accepted';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.register_meal_atomic(
      p_user_id => v_user_id,
      p_date => DATE '2026-07-13',
      p_meal_type => 'lanche'::public.meal_type_enum,
      p_items => '[{
        "food_name":"sem referencia canonica",
        "quantity_g":100,
        "kcal":100,
        "protein_g":10,
        "carbs_g":12,
        "fat_g":2,
        "source":"canonical_exact",
        "confidence":1
      }]'::jsonb,
      p_provider_message_id => 'provider-nutrition-missing-fk'
    );
    RAISE EXCEPTION 'canonical_exact without food_db_id was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'canonical_exact without food_db_id was accepted' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    PERFORM public.register_meal_atomic(
      p_user_id => v_user_id,
      p_date => DATE '2026-07-13',
      p_meal_type => 'lanche'::public.meal_type_enum,
      p_items => jsonb_build_array(jsonb_build_object(
        'food_name', 'alimento impossível',
        'food_db_id', v_food_id,
        'quantity_g', 15,
        'kcal', 593,
        'protein_g', 1,
        'carbs_g', 1,
        'fat_g', 1,
        'source', 'canonical_fuzzy',
        'confidence', 0.8
      )),
      p_provider_message_id => 'provider-nutrition-impossible-kcal'
    );
    RAISE EXCEPTION 'physically impossible kcal payload was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'physically impossible kcal payload was accepted' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    PERFORM public.register_meal_atomic(
      p_user_id => v_user_id,
      p_date => DATE '2026-07-13',
      p_meal_type => 'lanche'::public.meal_type_enum,
      p_items => jsonb_build_array(jsonb_build_object(
        'food_name', 'macros impossíveis',
        'food_db_id', v_food_id,
        'quantity_g', 100,
        'kcal', 100,
        'protein_g', 80,
        'carbs_g', 80,
        'fat_g', 20,
        'source', 'canonical_fuzzy',
        'confidence', 0.8
      )),
      p_provider_message_id => 'provider-nutrition-impossible-macros'
    );
    RAISE EXCEPTION 'physically impossible macro payload was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'physically impossible macro payload was accepted' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    INSERT INTO public.meal_logs (
      user_id,
      snapshot_id,
      meal_type,
      food_name,
      quantity_g,
      kcal,
      protein_g,
      carbs_g,
      fat_g,
      source,
      consumed_at
    ) VALUES (
      v_user_id,
      v_snapshot_id,
      'lanche'::public.meal_type_enum,
      'insert direto impossível',
      15,
      593,
      1,
      1,
      1,
      'manual',
      now()
    );
    RAISE EXCEPTION 'direct impossible meal log was accepted';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  SELECT count(*)
  INTO v_log_count
  FROM public.meal_logs
  WHERE user_id = v_user_id;

  SELECT calories_consumed
  INTO v_snapshot_kcal
  FROM public.daily_snapshots
  WHERE id = v_snapshot_id;

  IF v_log_count <> 1 OR v_snapshot_kcal <> 100 THEN
    RAISE EXCEPTION 'failed writes changed nutrition state: logs %, kcal %',
      v_log_count, v_snapshot_kcal;
  END IF;
END;
$test$;

ROLLBACK;
