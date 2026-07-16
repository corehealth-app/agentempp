-- Defense in depth for item-scoped corrections. The application already
-- sends only the replacement items; the database rejects an oversized payload
-- that also tries to reinsert an untouched item from the registration group.

CREATE OR REPLACE FUNCTION public.register_meal_atomic_scoped(
  p_user_id uuid,
  p_date date,
  p_meal_type public.meal_type_enum,
  p_items jsonb,
  p_replace boolean DEFAULT false,
  p_replace_meal_types public.meal_type_enum[] DEFAULT NULL,
  p_consumed_at timestamptz DEFAULT now(),
  p_provider_message_id text DEFAULT NULL,
  p_calories_target integer DEFAULT NULL,
  p_protein_target numeric DEFAULT NULL,
  p_replace_log_ids uuid[] DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_snapshot_id uuid;
  v_target_count integer;
  v_replaced_count integer;
  v_result jsonb;
BEGIN
  IF COALESCE(cardinality(p_replace_log_ids), 0) = 0 THEN
    RETURN public.register_meal_atomic(
      p_user_id => p_user_id,
      p_date => p_date,
      p_meal_type => p_meal_type,
      p_items => p_items,
      p_replace => p_replace,
      p_replace_meal_types => p_replace_meal_types,
      p_consumed_at => p_consumed_at,
      p_provider_message_id => p_provider_message_id,
      p_calories_target => p_calories_target,
      p_protein_target => p_protein_target
    );
  END IF;

  IF NOT p_replace THEN
    RAISE EXCEPTION 'replace_log_ids requires replace=true';
  END IF;
  IF p_replace_meal_types IS NOT NULL THEN
    RAISE EXCEPTION 'replace_log_ids and replace_meal_types are mutually exclusive';
  END IF;
  IF cardinality(p_replace_log_ids) > 30 THEN
    RAISE EXCEPTION 'replace_log_ids accepts at most 30 ids';
  END IF;

  SELECT count(DISTINCT target_id)
  INTO v_target_count
  FROM unnest(p_replace_log_ids) AS target(target_id);
  IF v_target_count <> cardinality(p_replace_log_ids) THEN
    RAISE EXCEPTION 'replace_log_ids must be unique';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || p_date::text, 0));

  SELECT id
  INTO v_snapshot_id
  FROM public.daily_snapshots
  WHERE user_id = p_user_id
    AND date = p_date;

  IF v_snapshot_id IS NULL THEN
    RAISE EXCEPTION 'replacement snapshot not found';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(p_replace_log_ids) AS target(target_id)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.meal_logs AS meal
      WHERE meal.id = target.target_id
        AND meal.user_id = p_user_id
        AND meal.snapshot_id = v_snapshot_id
    )
  ) THEN
    RAISE EXCEPTION 'replacement target is missing or belongs to another user/day';
  END IF;

  IF jsonb_array_length(p_items) > v_target_count AND EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS item(food_name text, quantity_g numeric)
    JOIN public.meal_logs AS remaining
      ON remaining.user_id = p_user_id
     AND remaining.snapshot_id = v_snapshot_id
     AND remaining.id <> ALL(p_replace_log_ids)
     AND remaining.quantity_g IS NOT NULL
     AND abs(remaining.quantity_g - item.quantity_g) <= 0.01
     AND lower(public.f_unaccent(btrim(remaining.food_name))) =
       lower(public.f_unaccent(btrim(item.food_name)))
    WHERE EXISTS (
      SELECT 1
      FROM public.meal_logs AS target
      WHERE target.id = ANY(p_replace_log_ids)
        AND (
          (
            target.raw_provider_message_id IS NOT NULL
            AND remaining.raw_provider_message_id = target.raw_provider_message_id
          )
          OR (
            target.raw_provider_message_id IS NULL
            AND remaining.raw_provider_message_id IS NULL
            AND remaining.consumed_at = target.consumed_at
          )
        )
    )
  ) THEN
    RAISE EXCEPTION 'scoped replacement payload duplicates an untouched meal item';
  END IF;

  DELETE FROM public.meal_logs
  WHERE user_id = p_user_id
    AND snapshot_id = v_snapshot_id
    AND id = ANY(p_replace_log_ids);
  GET DIAGNOSTICS v_replaced_count = ROW_COUNT;

  IF v_replaced_count <> v_target_count THEN
    RAISE EXCEPTION 'replacement target count changed during transaction';
  END IF;

  v_result := public.register_meal_atomic(
    p_user_id => p_user_id,
    p_date => p_date,
    p_meal_type => p_meal_type,
    p_items => p_items,
    p_replace => false,
    p_replace_meal_types => NULL,
    p_consumed_at => p_consumed_at,
    p_provider_message_id => p_provider_message_id,
    p_calories_target => p_calories_target,
    p_protein_target => p_protein_target
  );

  RETURN jsonb_set(v_result, '{replaced_count}', to_jsonb(v_replaced_count), true);
END;
$$;
