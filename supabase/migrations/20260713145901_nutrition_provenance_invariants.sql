-- Canonical nutrition provenance and database-level invariants.
-- Additive rollout: legacy sources remain accepted while new canonical sources
-- carry an explicit food_db reference.

DO $deduplicate_food_db$
DECLARE
  v_duplicate_group_count integer;
  v_deleted integer;
BEGIN
  SELECT count(*)
  INTO v_duplicate_group_count
  FROM (
    SELECT name_norm, country_code
    FROM public.food_db
    GROUP BY name_norm, country_code
    HAVING count(*) > 1
  ) AS duplicate_groups;

  IF v_duplicate_group_count NOT IN (0, 4) THEN
    RAISE EXCEPTION 'food_db duplicate precondition failed: found % groups, expected 0 or 4',
      v_duplicate_group_count;
  END IF;

  IF v_duplicate_group_count = 4 THEN
    IF EXISTS (
      SELECT expected.name_norm, expected.country_code
      FROM (VALUES
        ('alcatra grelhada', 'BR'),
        ('batata doce cozida', 'BR'),
        ('mandioca cozida', 'BR'),
        ('pao de forma', 'BR')
      ) AS expected(name_norm, country_code)
      LEFT JOIN public.food_db AS food
        ON food.name_norm = expected.name_norm
       AND food.country_code = expected.country_code
      GROUP BY expected.name_norm, expected.country_code
      HAVING count(food.id) <> 2
        OR count(*) FILTER (WHERE food.source = 'alias') <> 1
        OR count(*) FILTER (WHERE food.source LIKE 'TACO%') <> 1
    ) THEN
      RAISE EXCEPTION 'food_db duplicate precondition failed: expected one alias and one TACO row per group';
    END IF;

    DELETE FROM public.food_db AS food
    WHERE food.source = 'alias'
      AND (food.name_norm, food.country_code) IN (
        ('alcatra grelhada', 'BR'),
        ('batata doce cozida', 'BR'),
        ('mandioca cozida', 'BR'),
        ('pao de forma', 'BR')
      );
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_deleted <> 4 THEN
      RAISE EXCEPTION 'food_db duplicate cleanup deleted %, expected 4', v_deleted;
    END IF;
  END IF;
END;
$deduplicate_food_db$;

CREATE UNIQUE INDEX food_db_name_norm_country_key
  ON public.food_db (name_norm, country_code);

ALTER TABLE public.food_db
  ADD CONSTRAINT food_db_nutrition_bounds_check
  CHECK (
    (kcal_per_100g IS NULL OR kcal_per_100g BETWEEN 0 AND 955)
    AND (protein_g IS NULL OR protein_g BETWEEN 0 AND 100)
    AND (carbs_g IS NULL OR carbs_g BETWEEN 0 AND 100)
    AND (fat_g IS NULL OR fat_g BETWEEN 0 AND 100)
    AND (fiber_g IS NULL OR fiber_g BETWEEN 0 AND 100)
    AND COALESCE(protein_g, 0) + COALESCE(carbs_g, 0) + COALESCE(fat_g, 0) <= 115
  ) NOT VALID;

ALTER TABLE public.food_db
  VALIDATE CONSTRAINT food_db_nutrition_bounds_check;

ALTER TABLE public.meal_logs
  ADD COLUMN food_db_id integer,
  ADD CONSTRAINT meal_logs_food_db_id_fkey
    FOREIGN KEY (food_db_id) REFERENCES public.food_db(id),
  ADD CONSTRAINT meal_logs_nutrition_payload_check
  CHECK (
    quantity_g IS NOT NULL
    AND quantity_g > 0
    AND kcal IS NOT NULL
    AND kcal >= 0
    AND kcal <= quantity_g * 9.5 + 5
    AND protein_g IS NOT NULL
    AND protein_g >= 0
    AND carbs_g IS NOT NULL
    AND carbs_g >= 0
    AND fat_g IS NOT NULL
    AND fat_g >= 0
    AND protein_g + carbs_g + fat_g <= quantity_g * 1.1 + 5
    AND (source NOT IN ('canonical_exact', 'canonical_fuzzy') OR food_db_id IS NOT NULL)
  ) NOT VALID;

CREATE INDEX idx_meal_logs_food_db_id
  ON public.meal_logs (food_db_id)
  WHERE food_db_id IS NOT NULL;

COMMENT ON COLUMN public.meal_logs.food_db_id IS
  'Nullable canonical food_db reference. Required for canonical_exact and canonical_fuzzy sources.';

COMMENT ON COLUMN public.meal_logs.source IS
  'Nutrition provenance, including canonical_exact, canonical_fuzzy, user_kcal, pending_approved and estimates; legacy values remain readable.';

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
      food_db_id integer,
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

  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS item(quantity_g numeric, kcal numeric)
    WHERE item.kcal > item.quantity_g * 9.5 + 5
  ) THEN
    RAISE EXCEPTION 'invalid meal item nutrition: kcal exceeds physical density';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS item(
      quantity_g numeric,
      protein_g numeric,
      carbs_g numeric,
      fat_g numeric
    )
    WHERE item.protein_g + item.carbs_g + item.fat_g > item.quantity_g * 1.1 + 5
  ) THEN
    RAISE EXCEPTION 'invalid meal item nutrition: macro mass exceeds quantity';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS item(source text, food_db_id integer)
    WHERE item.source IN ('canonical_exact', 'canonical_fuzzy')
      AND item.food_db_id IS NULL
  ) THEN
    RAISE EXCEPTION 'invalid meal item provenance: canonical source requires food_db_id';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS item(food_db_id integer)
    WHERE item.food_db_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.food_db AS food
        WHERE food.id = item.food_db_id
      )
  ) THEN
    RAISE EXCEPTION 'invalid meal item provenance: unknown food_db_id';
  END IF;

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
      food_db_id integer,
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
      food_db_id,
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
      parsed.food_db_id,
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
