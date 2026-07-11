-- Register or replace one meal in a single database transaction.
-- The function inserts meal_logs and derives snapshot nutrition from the rows,
-- so retries and partial failures cannot leave aggregate drift behind.

CREATE OR REPLACE FUNCTION public.register_meal_atomic(
  p_user_id uuid,
  p_date date,
  p_meal_type public.meal_type_enum,
  p_items jsonb,
  p_replace boolean DEFAULT false,
  p_replace_meal_types public.meal_type_enum[] DEFAULT NULL,
  p_consumed_at timestamptz DEFAULT now(),
  p_provider_message_id text DEFAULT NULL,
  p_calories_target integer DEFAULT NULL,
  p_protein_target numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_snapshot_id uuid;
  v_inserted_count integer := 0;
  v_inserted_food_names text[] := ARRAY[]::text[];
  v_replaced_count integer := 0;
  v_replace_types public.meal_type_enum[];
  v_result jsonb;
BEGIN
  IF p_user_id IS NULL OR p_date IS NULL THEN
    RAISE EXCEPTION 'user and date are required';
  END IF;
  IF jsonb_typeof(p_items) <> 'array'
    OR jsonb_array_length(p_items) = 0
    OR jsonb_array_length(p_items) > 30 THEN
    RAISE EXCEPTION 'items must be a non-empty array with at most 30 entries';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS item(
      food_name text,
      quantity_g numeric,
      kcal numeric,
      protein_g numeric,
      carbs_g numeric,
      fat_g numeric,
      source text,
      confidence numeric
    )
    WHERE NULLIF(btrim(item.food_name), '') IS NULL
      OR item.quantity_g IS NULL OR item.quantity_g <= 0 OR item.quantity_g > 9999
      OR item.kcal IS NULL OR item.kcal < 0 OR item.kcal > 99999
      OR item.protein_g IS NULL OR item.protein_g < 0 OR item.protein_g > 9999
      OR item.carbs_g IS NULL OR item.carbs_g < 0 OR item.carbs_g > 9999
      OR item.fat_g IS NULL OR item.fat_g < 0 OR item.fat_g > 9999
      OR (item.confidence IS NOT NULL AND (item.confidence < 0 OR item.confidence > 1))
  ) THEN
    RAISE EXCEPTION 'invalid meal item payload';
  END IF;

  -- Serializes writes for one user/local day while keeping the transaction
  -- short. Every caller acquires the same lock before touching snapshot/logs.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || p_date::text, 0));

  INSERT INTO public.daily_snapshots (
    user_id,
    date,
    calories_consumed,
    protein_g,
    carbs_g,
    fat_g,
    calories_target,
    protein_target
  ) VALUES (
    p_user_id,
    p_date,
    0,
    0,
    0,
    0,
    p_calories_target,
    p_protein_target
  )
  ON CONFLICT (user_id, date) DO UPDATE SET
    calories_target = COALESCE(public.daily_snapshots.calories_target, EXCLUDED.calories_target),
    protein_target = COALESCE(public.daily_snapshots.protein_target, EXCLUDED.protein_target),
    updated_at = now()
  RETURNING id INTO v_snapshot_id;

  IF p_replace THEN
    v_replace_types := COALESCE(
      p_replace_meal_types,
      CASE
        WHEN p_meal_type IS NULL THEN ARRAY[]::public.meal_type_enum[]
        ELSE ARRAY[p_meal_type]::public.meal_type_enum[]
      END
    );
    IF cardinality(v_replace_types) = 0 THEN
      RAISE EXCEPTION 'replace requires at least one meal type';
    END IF;

    DELETE FROM public.meal_logs
    WHERE user_id = p_user_id
      AND snapshot_id = v_snapshot_id
      AND meal_type = ANY(v_replace_types);
    GET DIAGNOSTICS v_replaced_count = ROW_COUNT;
  END IF;

  WITH parsed AS (
    SELECT *
    FROM jsonb_to_recordset(p_items) AS item(
      food_name text,
      quantity_g numeric,
      kcal numeric,
      protein_g numeric,
      carbs_g numeric,
      fat_g numeric,
      source text,
      confidence numeric
    )
  ), inserted AS (
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
      confidence,
      consumed_at,
      raw_provider_message_id
    )
    SELECT
      p_user_id,
      v_snapshot_id,
      p_meal_type,
      btrim(parsed.food_name),
      parsed.quantity_g,
      parsed.kcal,
      parsed.protein_g,
      parsed.carbs_g,
      parsed.fat_g,
      parsed.source,
      parsed.confidence,
      p_consumed_at,
      p_provider_message_id
    FROM parsed
    ON CONFLICT DO NOTHING
    RETURNING food_name
  )
  SELECT
    count(*)::integer,
    COALESCE(array_agg(food_name ORDER BY food_name), ARRAY[]::text[])
  INTO v_inserted_count, v_inserted_food_names
  FROM inserted;

  -- The aggregate is always derived from its source rows. Exercise and other
  -- snapshot fields are intentionally untouched.
  UPDATE public.daily_snapshots AS snapshot
  SET
    calories_consumed = totals.calories_consumed,
    protein_g = totals.protein_g,
    carbs_g = totals.carbs_g,
    fat_g = totals.fat_g,
    updated_at = now()
  FROM (
    SELECT
      round(COALESCE(sum(kcal), 0))::integer AS calories_consumed,
      round(COALESCE(sum(protein_g), 0), 2) AS protein_g,
      round(COALESCE(sum(carbs_g), 0), 2) AS carbs_g,
      round(COALESCE(sum(fat_g), 0), 2) AS fat_g
    FROM public.meal_logs
    WHERE snapshot_id = v_snapshot_id
  ) AS totals
  WHERE snapshot.id = v_snapshot_id;

  SELECT jsonb_build_object(
    'snapshot_id', snapshot.id,
    'inserted_count', v_inserted_count,
    'inserted_food_names', to_jsonb(v_inserted_food_names),
    'replaced_count', v_replaced_count,
    'calories_consumed', snapshot.calories_consumed,
    'protein_g', snapshot.protein_g,
    'carbs_g', snapshot.carbs_g,
    'fat_g', snapshot.fat_g,
    'calories_target', snapshot.calories_target,
    'protein_target', snapshot.protein_target,
    'daily_balance', snapshot.daily_balance
  ) INTO v_result
  FROM public.daily_snapshots AS snapshot
  WHERE snapshot.id = v_snapshot_id;

  RETURN v_result;
END;
$$;
