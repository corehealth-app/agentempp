BEGIN;

SELECT pg_advisory_xact_lock(hashtext('repair-kumis-meal-loss-2026-07-13'));

CREATE TEMP TABLE repair_params ON COMMIT DROP AS
SELECT
  '118587e3-e752-4a23-b304-57231d7ef40f'::uuid AS target_user_id,
  'bedf93c8-740f-479e-bb31-f9d87d030892'::uuid AS target_snapshot_id,
  '6639635c-d6a4-4852-90b4-eb0ec403d4b2'::uuid AS lunch_pending_id,
  '74277632-0a95-4f06-b523-53ecc0859c3a'::uuid AS kumis_pending_id,
  'a7afa128-e724-4626-b176-c2ce660afcd0'::uuid AS milk_pending_id,
  '2df3141f-32ff-4ef6-8169-432a1829b770'::uuid AS milk_log_id,
  DATE '2026-07-13' AS target_date;

CREATE TEMP TABLE repair_expected_lunch (
  food_name text NOT NULL,
  food_db_id integer,
  quantity_g numeric NOT NULL,
  kcal numeric NOT NULL,
  protein_g numeric NOT NULL,
  carbs_g numeric NOT NULL,
  fat_g numeric NOT NULL,
  source text NOT NULL
) ON COMMIT DROP;

INSERT INTO repair_expected_lunch VALUES
  ('frango em molho cremoso', NULL, 180, 297, 50.4, 0, 9, 'llm_estimate'),
  ('arroz branco cozido', 1, 150, 192, 3.75, 42.15, 0.3, 'canonical_exact'),
  ('batata palha', 268, 20, 62.4, 0.6, 8.2, 3, 'canonical_fuzzy'),
  ('mix de folhas para salada', 471, 80, 14.4, 1.2, 2.4, 0.24, 'canonical_fuzzy'),
  ('cenoura ralada crua', NULL, 60, 21, 1.2, 4.2, 0.18, 'llm_estimate'),
  ('tomate cereja', 426, 80, 14.4, 0.72, 3.12, 0.16, 'canonical_exact'),
  ('uva vermelha', 428, 55, 38, 0.39, 9.9, 0.11, 'canonical_fuzzy');

-- Same lock key used by register_meal_atomic for this user/date.
SELECT pg_advisory_xact_lock(
  hashtextextended(target_user_id::text || ':' || target_date::text, 0)
)
FROM repair_params;

DO $lock_rows$
BEGIN
  PERFORM 1
  FROM public.users AS users
  JOIN repair_params AS params ON params.target_user_id = users.id
  FOR UPDATE OF users;

  PERFORM 1
  FROM public.user_profiles AS profile
  JOIN repair_params AS params ON params.target_user_id = profile.user_id
  FOR UPDATE OF profile;

  PERFORM 1
  FROM public.user_progress AS progress
  JOIN repair_params AS params ON params.target_user_id = progress.user_id
  FOR UPDATE OF progress;

  PERFORM 1
  FROM public.daily_snapshots AS snapshot
  JOIN repair_params AS params ON params.target_user_id = snapshot.user_id
  WHERE snapshot.day_closed = true OR snapshot.id = params.target_snapshot_id
  FOR UPDATE OF snapshot;

  PERFORM 1
  FROM public.pending_registrations AS pending
  JOIN repair_params AS params
    ON pending.id IN (params.lunch_pending_id, params.kumis_pending_id, params.milk_pending_id)
  FOR UPDATE OF pending;

  PERFORM 1
  FROM public.meal_logs AS meal
  JOIN repair_params AS params ON params.target_user_id = meal.user_id
  JOIN public.users AS users ON users.id = params.target_user_id
  WHERE (meal.consumed_at AT TIME ZONE users.timezone)::date = params.target_date
  FOR UPDATE OF meal;
END;
$lock_rows$;

CREATE TEMP TABLE repair_expected_progress_before ON COMMIT DROP AS
WITH profile AS (
  SELECT CASE
    WHEN user_profile.current_protocol = 'recomposicao'
      THEN coalesce(user_profile.deficit_level, 500)
    ELSE 0
  END::numeric AS design_deficit
  FROM public.user_profiles AS user_profile
  JOIN repair_params AS params ON params.target_user_id = user_profile.user_id
),
credits AS (
  SELECT CASE
    WHEN NOT (
      EXISTS (SELECT 1 FROM public.meal_logs AS meal WHERE meal.snapshot_id = snapshot.id)
      OR coalesce(snapshot.exercise_calories, 0) > 0
      OR snapshot.training_done
    ) THEN 0
    WHEN snapshot.day_status = 'user_skipped'
      THEN profile.design_deficit - snapshot.daily_balance
    WHEN snapshot.calories_target IS NOT NULL
      AND snapshot.calories_target > 0
      AND snapshot.calories_consumed < 0.5 * snapshot.calories_target
      THEN CASE WHEN snapshot.day_status = 'complete' OR snapshot.day_status IS NULL
        THEN profile.design_deficit ELSE 0 END
    WHEN snapshot.day_status = 'incomplete_no_response' THEN 0
    ELSE profile.design_deficit - snapshot.daily_balance
  END AS credit
  FROM public.daily_snapshots AS snapshot
  JOIN repair_params AS params ON params.target_user_id = snapshot.user_id
  CROSS JOIN profile
  WHERE snapshot.day_closed = true
),
total AS (
  SELECT greatest(0, round(coalesce(sum(credit), 0)))::integer AS value
  FROM credits
)
SELECT
  (total.value / 7700)::smallint AS blocks_completed,
  total.value % 7700 AS deficit_block
FROM total;

DO $preconditions$
DECLARE
  v_lunch_provider_message_id text;
  v_kumis_provider_message_id text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.users AS users
    JOIN repair_params AS params ON params.target_user_id = users.id
    WHERE users.country = 'US'
      AND users.timezone = 'America/New_York'
      AND users.status = 'active'
  ) THEN
    RAISE EXCEPTION 'precondition failed: target user state changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.food_db AS food
    WHERE food.name_norm = 'iogurte kumis'
      AND food.country_code = 'US'
      AND food.kcal_per_100g = 83.33
      AND food.protein_g = 3.33
      AND food.carbs_g = 9.58
      AND food.fat_g = 3.33
  ) THEN
    RAISE EXCEPTION 'precondition failed: canonical Kumis reference missing or changed';
  END IF;

  IF NOT EXISTS (
    WITH totals AS (
      SELECT
        round(coalesce(sum(meal.kcal), 0))::integer AS kcal,
        round(coalesce(sum(meal.protein_g), 0), 2) AS protein_g,
        round(coalesce(sum(meal.carbs_g), 0), 2) AS carbs_g,
        round(coalesce(sum(meal.fat_g), 0), 2) AS fat_g
      FROM repair_params AS params
      JOIN public.users AS users ON users.id = params.target_user_id
      LEFT JOIN public.meal_logs AS meal
        ON meal.user_id = params.target_user_id
       AND (meal.consumed_at AT TIME ZONE users.timezone)::date = params.target_date
    )
    SELECT 1
    FROM public.daily_snapshots AS snapshot
    JOIN repair_params AS params ON params.target_snapshot_id = snapshot.id
    CROSS JOIN totals
    WHERE snapshot.user_id = params.target_user_id
      AND snapshot.date = params.target_date
      AND snapshot.calories_consumed = totals.kcal
      -- Legacy confirmations accumulated card totals rounded to 0.1g. Accept
      -- only the observed rounding residue; any material drift still blocks.
      AND abs(snapshot.protein_g - totals.protein_g) <= 0.05
      AND abs(snapshot.carbs_g - totals.carbs_g) <= 0.05
      AND abs(snapshot.fat_g - totals.fat_g) <= 0.05
  ) THEN
    RAISE EXCEPTION 'precondition failed: snapshot no longer matches meal logs';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.pending_registrations AS pending
    JOIN repair_params AS params ON params.lunch_pending_id = pending.id
    WHERE pending.user_id = params.target_user_id
      AND pending.status = 'confirmed'
      AND pending.proposal->>'kind' = 'meal'
      AND pending.proposal->>'mealType' = 'almoco'
      AND pending.proposal->>'source_local_date' = params.target_date::text
      AND pending.proposal->>'source_timezone' = 'America/New_York'
      AND jsonb_array_length(pending.proposal->'items') = 7
      AND (pending.proposal->'totals'->>'kcal')::numeric = 639.2
  ) THEN
    RAISE EXCEPTION 'precondition failed: lunch pending changed';
  END IF;

  IF EXISTS (
    WITH actual AS (
      SELECT
        item->>'name' AS food_name,
        NULLIF(item->>'food_db_id', '')::integer AS food_db_id,
        (item->>'quantity_g')::numeric AS quantity_g,
        (item->>'kcal')::numeric AS kcal,
        (item->>'protein_g')::numeric AS protein_g,
        (item->>'carbs_g')::numeric AS carbs_g,
        (item->>'fat_g')::numeric AS fat_g,
        item->>'nutrition_source' AS source
      FROM public.pending_registrations AS pending
      JOIN repair_params AS params ON params.lunch_pending_id = pending.id
      CROSS JOIN LATERAL jsonb_array_elements(pending.proposal->'items') AS item
    ),
    difference AS (
      (SELECT * FROM repair_expected_lunch EXCEPT SELECT * FROM actual)
      UNION ALL
      (SELECT * FROM actual EXCEPT SELECT * FROM repair_expected_lunch)
    )
    SELECT 1 FROM difference
  ) THEN
    RAISE EXCEPTION 'precondition failed: lunch pending items changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.pending_registrations AS pending
    JOIN repair_params AS params ON params.kumis_pending_id = pending.id
    WHERE pending.user_id = params.target_user_id
      AND pending.status = 'confirmed'
      AND pending.proposal->>'kind' = 'meal'
      AND pending.proposal->>'mealType' = 'lanche'
      AND pending.proposal->>'source_local_date' = params.target_date::text
      AND pending.proposal->>'source_timezone' = 'America/New_York'
      AND jsonb_array_length(pending.proposal->'items') = 1
      AND pending.proposal->'items'->0->>'name' = 'iogurte kumis'
      AND (pending.proposal->'items'->0->>'quantity_g')::numeric = 150
      AND (pending.proposal->'items'->0->>'food_db_id')::integer = 259
      AND (pending.proposal->'items'->0->>'kcal')::numeric = 145.5
      AND (pending.proposal->'items'->0->>'protein_g')::numeric = 13.5
      AND (pending.proposal->'items'->0->>'carbs_g')::numeric = 6
      AND (pending.proposal->'items'->0->>'fat_g')::numeric = 7.5
  ) THEN
    RAISE EXCEPTION 'precondition failed: Kumis pending changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.pending_registrations AS pending
    JOIN repair_params AS params ON params.milk_pending_id = pending.id
    WHERE pending.user_id = params.target_user_id
      AND pending.status = 'confirmed'
      AND pending.proposal->>'mealType' = 'lanche'
      AND jsonb_array_length(pending.proposal->'items') = 1
      AND pending.proposal->'items'->0->>'name' = 'leite em pó desnatado'
      AND (pending.proposal->'items'->0->>'quantity_g')::numeric = 30
      AND (pending.proposal->'items'->0->>'user_kcal')::numeric = 85
  ) THEN
    RAISE EXCEPTION 'precondition failed: milk pending changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.milk_log_id = meal.id
    JOIN public.pending_registrations AS pending ON pending.id = params.milk_pending_id
    WHERE meal.user_id = params.target_user_id
      AND meal.snapshot_id = params.target_snapshot_id
      AND meal.food_name = 'leite em pó desnatado'
      AND meal.quantity_g = 30
      AND meal.kcal = 85
      AND meal.protein_g = 8.26
      AND meal.carbs_g = 12.28
      AND meal.fat_g = 0.24
      AND meal.meal_type = 'lanche'
      AND meal.raw_provider_message_id = pending.proposal->>'source_provider_message_id'
  ) THEN
    RAISE EXCEPTION 'precondition failed: corrected milk log changed';
  END IF;

  SELECT pending.proposal->>'source_provider_message_id'
  INTO STRICT v_lunch_provider_message_id
  FROM public.pending_registrations AS pending
  JOIN repair_params AS params ON params.lunch_pending_id = pending.id;

  SELECT pending.proposal->>'source_provider_message_id'
  INTO STRICT v_kumis_provider_message_id
  FROM public.pending_registrations AS pending
  JOIN repair_params AS params ON params.kumis_pending_id = pending.id;

  IF NULLIF(v_lunch_provider_message_id, '') IS NULL
    OR NULLIF(v_kumis_provider_message_id, '') IS NULL
    OR v_lunch_provider_message_id = v_kumis_provider_message_id THEN
    RAISE EXCEPTION 'precondition failed: source provider ids are invalid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.target_user_id = meal.user_id
    WHERE meal.raw_provider_message_id IN (
      v_lunch_provider_message_id,
      v_kumis_provider_message_id
    )
  ) THEN
    RAISE EXCEPTION 'precondition failed: missing registrations already exist';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.product_events AS event
    JOIN repair_params AS params ON params.target_user_id = event.user_id
    WHERE event.event = 'admin.kumis_meal_loss_repaired'
      AND event.properties->>'repair_id' = 'kumis-meal-loss-2026-07-13'
  ) THEN
    RAISE EXCEPTION 'precondition failed: repair already applied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_progress AS progress
    JOIN repair_params AS params ON params.target_user_id = progress.user_id
    CROSS JOIN repair_expected_progress_before AS expected
    WHERE progress.blocks_completed = expected.blocks_completed
      AND progress.deficit_block = expected.deficit_block
  ) THEN
    RAISE EXCEPTION 'precondition failed: block progress no longer matches replay';
  END IF;
END;
$preconditions$;

CREATE TEMP TABLE repair_before ON COMMIT DROP AS
WITH totals AS (
  SELECT
    round(coalesce(sum(meal.kcal), 0))::integer AS kcal,
    round(coalesce(sum(meal.protein_g), 0), 2) AS protein_g,
    round(coalesce(sum(meal.carbs_g), 0), 2) AS carbs_g,
    round(coalesce(sum(meal.fat_g), 0), 2) AS fat_g,
    count(meal.id)::integer AS item_count
  FROM repair_params AS params
  JOIN public.users AS users ON users.id = params.target_user_id
  LEFT JOIN public.meal_logs AS meal
    ON meal.user_id = params.target_user_id
   AND (meal.consumed_at AT TIME ZONE users.timezone)::date = params.target_date
)
SELECT
  jsonb_build_object(
    'kcal', totals.kcal,
    'protein_g', totals.protein_g,
    'carbs_g', totals.carbs_g,
    'fat_g', totals.fat_g,
    'item_count', totals.item_count
  ) AS snapshot,
  jsonb_build_object(
    'blocks_completed', progress.blocks_completed,
    'deficit_block', progress.deficit_block
  ) AS block,
  jsonb_build_object(
    'kcal', (pending.proposal->'items'->0->>'kcal')::numeric,
    'protein_g', (pending.proposal->'items'->0->>'protein_g')::numeric,
    'carbs_g', (pending.proposal->'items'->0->>'carbs_g')::numeric,
    'fat_g', (pending.proposal->'items'->0->>'fat_g')::numeric,
    'food_db_id', (pending.proposal->'items'->0->>'food_db_id')::integer
  ) AS kumis_pending
FROM totals
CROSS JOIN repair_params AS params
JOIN public.user_progress AS progress ON progress.user_id = params.target_user_id
JOIN public.pending_registrations AS pending ON pending.id = params.kumis_pending_id;

CREATE TEMP TABLE repair_rpc_results (
  kind text PRIMARY KEY,
  result jsonb NOT NULL
) ON COMMIT DROP;

INSERT INTO repair_rpc_results (kind, result)
WITH pending AS (
  SELECT registration.proposal
  FROM public.pending_registrations AS registration
  JOIN repair_params AS params ON params.lunch_pending_id = registration.id
),
items AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'food_name', item.value->>'name',
      'food_db_id', NULLIF(item.value->>'food_db_id', '')::integer,
      'quantity_g', (item.value->>'quantity_g')::numeric,
      'kcal', (item.value->>'kcal')::numeric,
      'protein_g', (item.value->>'protein_g')::numeric,
      'carbs_g', (item.value->>'carbs_g')::numeric,
      'fat_g', (item.value->>'fat_g')::numeric,
      'source', item.value->>'nutrition_source',
      'confidence', NULL
    ) ORDER BY item.ordinality
  ) AS payload
  FROM pending
  CROSS JOIN LATERAL jsonb_array_elements(pending.proposal->'items')
    WITH ORDINALITY AS item(value, ordinality)
)
SELECT
  'lunch',
  public.register_meal_atomic(
    p_user_id => params.target_user_id,
    p_date => params.target_date,
    p_meal_type => 'almoco'::public.meal_type_enum,
    p_items => items.payload,
    p_replace => false,
    p_replace_meal_types => NULL,
    p_consumed_at => (pending.proposal->>'source_timestamp')::timestamptz,
    p_provider_message_id => pending.proposal->>'source_provider_message_id',
    p_calories_target => snapshot.calories_target,
    p_protein_target => snapshot.protein_target
  )
FROM repair_params AS params
CROSS JOIN pending
CROSS JOIN items
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id;

INSERT INTO repair_rpc_results (kind, result)
SELECT
  'kumis',
  public.register_meal_atomic(
    p_user_id => params.target_user_id,
    p_date => params.target_date,
    p_meal_type => 'lanche'::public.meal_type_enum,
    p_items => jsonb_build_array(jsonb_build_object(
      'food_name', 'iogurte kumis',
      'food_db_id', food.id,
      'quantity_g', 150,
      'kcal', 125,
      'protein_g', 5,
      'carbs_g', 14.38,
      'fat_g', 5,
      'source', 'canonical_exact',
      'confidence', 1
    )),
    p_replace => false,
    p_replace_meal_types => NULL,
    p_consumed_at => (pending.proposal->>'source_timestamp')::timestamptz,
    p_provider_message_id => pending.proposal->>'source_provider_message_id',
    p_calories_target => snapshot.calories_target,
    p_protein_target => snapshot.protein_target
  )
FROM repair_params AS params
JOIN public.pending_registrations AS pending ON pending.id = params.kumis_pending_id
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id
JOIN public.food_db AS food
  ON food.name_norm = 'iogurte kumis'
 AND food.country_code = 'US';

DO $rpc_results$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM repair_rpc_results
    WHERE kind = 'lunch'
      AND (result->>'inserted_count')::integer = 7
      AND (result->>'replaced_count')::integer = 0
  ) THEN
    RAISE EXCEPTION 'repair failed: lunch RPC did not insert exactly seven items';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM repair_rpc_results
    WHERE kind = 'kumis'
      AND (result->>'inserted_count')::integer = 1
      AND (result->>'replaced_count')::integer = 0
  ) THEN
    RAISE EXCEPTION 'repair failed: Kumis RPC did not insert exactly one item';
  END IF;
END;
$rpc_results$;

UPDATE public.pending_registrations AS pending
SET proposal = jsonb_set(
  jsonb_set(
    pending.proposal,
    '{items}',
    jsonb_build_array(
      (pending.proposal->'items'->0) || jsonb_build_object(
        'food_db_id', food.id,
        'kcal', 125,
        'protein_g', 5,
        'carbs_g', 14.38,
        'fat_g', 5,
        'nutrition_source', 'canonical_exact'
      )
    ),
    true
  ),
  '{totals}',
  jsonb_build_object(
    'kcal', 125,
    'protein_g', 5,
    'carbs_g', 14.38,
    'fat_g', 5
  ),
  true
) || jsonb_build_object(
  'historical_repair', jsonb_build_object(
    'repair_id', 'kumis-meal-loss-2026-07-13',
    'reason', 'nutrition_label_reference'
  )
)
FROM repair_params AS params
JOIN public.food_db AS food
  ON food.name_norm = 'iogurte kumis'
 AND food.country_code = 'US'
WHERE pending.id = params.kumis_pending_id;

CREATE TEMP TABLE repair_expected_progress ON COMMIT DROP AS
WITH profile AS (
  SELECT CASE
    WHEN user_profile.current_protocol = 'recomposicao'
      THEN coalesce(user_profile.deficit_level, 500)
    ELSE 0
  END::numeric AS design_deficit
  FROM public.user_profiles AS user_profile
  JOIN repair_params AS params ON params.target_user_id = user_profile.user_id
),
credits AS (
  SELECT CASE
    WHEN NOT (
      EXISTS (SELECT 1 FROM public.meal_logs AS meal WHERE meal.snapshot_id = snapshot.id)
      OR coalesce(snapshot.exercise_calories, 0) > 0
      OR snapshot.training_done
    ) THEN 0
    WHEN snapshot.day_status = 'user_skipped'
      THEN profile.design_deficit - snapshot.daily_balance
    WHEN snapshot.calories_target IS NOT NULL
      AND snapshot.calories_target > 0
      AND snapshot.calories_consumed < 0.5 * snapshot.calories_target
      THEN CASE WHEN snapshot.day_status = 'complete' OR snapshot.day_status IS NULL
        THEN profile.design_deficit ELSE 0 END
    WHEN snapshot.day_status = 'incomplete_no_response' THEN 0
    ELSE profile.design_deficit - snapshot.daily_balance
  END AS credit
  FROM public.daily_snapshots AS snapshot
  JOIN repair_params AS params ON params.target_user_id = snapshot.user_id
  CROSS JOIN profile
  WHERE snapshot.day_closed = true
),
total AS (
  SELECT greatest(0, round(coalesce(sum(credit), 0)))::integer AS value
  FROM credits
)
SELECT
  (total.value / 7700)::smallint AS blocks_completed,
  total.value % 7700 AS deficit_block
FROM total;

UPDATE public.user_progress AS progress
SET blocks_completed = expected.blocks_completed,
    deficit_block = expected.deficit_block,
    updated_at = now()
FROM repair_expected_progress AS expected
CROSS JOIN repair_params AS params
WHERE progress.user_id = params.target_user_id;

INSERT INTO public.product_events (user_id, event, properties)
SELECT
  params.target_user_id,
  'admin.kumis_meal_loss_repaired',
  jsonb_build_object(
    'repair_id', 'kumis-meal-loss-2026-07-13',
    'snapshot_id', params.target_snapshot_id,
    'date', params.target_date,
    'lunch_pending_id', params.lunch_pending_id,
    'kumis_pending_id', params.kumis_pending_id,
    'milk_pending_id', params.milk_pending_id,
    'restored_items', 8,
    'restored_kcal', 764.2,
    'snapshot_before', before.snapshot,
    'snapshot_after', jsonb_build_object(
      'kcal', snapshot.calories_consumed,
      'protein_g', snapshot.protein_g,
      'carbs_g', snapshot.carbs_g,
      'fat_g', snapshot.fat_g,
      'item_count', (
        SELECT count(*)
        FROM public.meal_logs AS meal
        WHERE meal.snapshot_id = params.target_snapshot_id
      )
    ),
    'kumis_pending_before', before.kumis_pending,
    'kumis_pending_after', jsonb_build_object(
      'kcal', 125,
      'protein_g', 5,
      'carbs_g', 14.38,
      'fat_g', 5,
      'food_db_id', food.id
    ),
    'block_before', before.block,
    'block_after', jsonb_build_object(
      'blocks_completed', progress.blocks_completed,
      'deficit_block', progress.deficit_block
    ),
    'authorization', 'user_requested_full_correction_2026-07-13'
  )
FROM repair_params AS params
CROSS JOIN repair_before AS before
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id
JOIN public.user_progress AS progress ON progress.user_id = params.target_user_id
JOIN public.food_db AS food
  ON food.name_norm = 'iogurte kumis'
 AND food.country_code = 'US';

DO $postconditions$
DECLARE
  v_expected_snapshot record;
  v_lunch_count integer;
  v_lunch_kcal numeric;
  v_lunch_protein numeric;
  v_lunch_carbs numeric;
  v_lunch_fat numeric;
  v_lunch_type_ok boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM repair_rpc_results
    WHERE kind = 'lunch' AND (result->>'inserted_count')::integer = 7
  ) OR NOT EXISTS (
    SELECT 1
    FROM repair_rpc_results
    WHERE kind = 'kumis' AND (result->>'inserted_count')::integer = 1
  ) THEN
    RAISE EXCEPTION 'postcondition failed: insertion result mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.pending_registrations AS pending
    JOIN repair_params AS params ON params.kumis_pending_id = pending.id
    JOIN public.food_db AS food
      ON food.name_norm = 'iogurte kumis'
     AND food.country_code = 'US'
    WHERE pending.proposal->'items'->0->>'name' = 'iogurte kumis'
      AND (pending.proposal->'items'->0->>'food_db_id')::integer = food.id
      AND (pending.proposal->'items'->0->>'kcal')::numeric = 125
      AND (pending.proposal->'items'->0->>'protein_g')::numeric = 5
      AND (pending.proposal->'items'->0->>'carbs_g')::numeric = 14.38
      AND (pending.proposal->'items'->0->>'fat_g')::numeric = 5
      AND pending.proposal->'items'->0->>'nutrition_source' = 'canonical_exact'
      AND pending.proposal->'historical_repair'->>'repair_id' = 'kumis-meal-loss-2026-07-13'
  ) THEN
    RAISE EXCEPTION 'postcondition failed: corrected Kumis pending mismatch';
  END IF;

  SELECT
    count(*)::integer,
    coalesce(sum(meal.kcal), 0),
    coalesce(sum(meal.protein_g), 0),
    coalesce(sum(meal.carbs_g), 0),
    coalesce(sum(meal.fat_g), 0),
    coalesce(bool_and(meal.meal_type = 'almoco'), false)
  INTO
    v_lunch_count,
    v_lunch_kcal,
    v_lunch_protein,
    v_lunch_carbs,
    v_lunch_fat,
    v_lunch_type_ok
  FROM public.meal_logs AS meal
  JOIN repair_params AS params ON params.target_user_id = meal.user_id
  JOIN public.pending_registrations AS pending ON pending.id = params.lunch_pending_id
  WHERE meal.raw_provider_message_id = pending.proposal->>'source_provider_message_id';

  IF v_lunch_count <> 7
    OR v_lunch_kcal <> 639.2
    OR v_lunch_protein <> 58.26
    OR v_lunch_carbs <> 69.97
    OR v_lunch_fat <> 12.99
    OR NOT v_lunch_type_ok THEN
    RAISE EXCEPTION
      'postcondition failed: restored lunch mismatch (count %, kcal %, protein %, carbs %, fat %, type_ok %)',
      v_lunch_count,
      v_lunch_kcal,
      v_lunch_protein,
      v_lunch_carbs,
      v_lunch_fat,
      v_lunch_type_ok;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.target_user_id = meal.user_id
    JOIN public.pending_registrations AS pending ON pending.id = params.kumis_pending_id
    JOIN public.food_db AS food
      ON food.name_norm = 'iogurte kumis'
     AND food.country_code = 'US'
    WHERE meal.raw_provider_message_id = pending.proposal->>'source_provider_message_id'
      AND meal.snapshot_id = params.target_snapshot_id
      AND meal.food_name = 'iogurte kumis'
      AND meal.quantity_g = 150
      AND meal.kcal = 125
      AND meal.protein_g = 5
      AND meal.carbs_g = 14.38
      AND meal.fat_g = 5
      AND meal.meal_type = 'lanche'
      AND meal.source = 'canonical_exact'
      AND meal.food_db_id = food.id
  ) THEN
    RAISE EXCEPTION 'postcondition failed: restored Kumis log mismatch';
  END IF;

  SELECT
    round(coalesce(sum(meal.kcal), 0))::integer AS kcal,
    round(coalesce(sum(meal.protein_g), 0), 2) AS protein_g,
    round(coalesce(sum(meal.carbs_g), 0), 2) AS carbs_g,
    round(coalesce(sum(meal.fat_g), 0), 2) AS fat_g
  INTO STRICT v_expected_snapshot
  FROM repair_params AS params
  JOIN public.users AS users ON users.id = params.target_user_id
  LEFT JOIN public.meal_logs AS meal
    ON meal.user_id = params.target_user_id
   AND (meal.consumed_at AT TIME ZONE users.timezone)::date = params.target_date;

  IF NOT EXISTS (
    SELECT 1
    FROM public.daily_snapshots AS snapshot
    JOIN repair_params AS params ON params.target_snapshot_id = snapshot.id
    WHERE snapshot.calories_consumed = v_expected_snapshot.kcal
      AND snapshot.protein_g = v_expected_snapshot.protein_g
      AND snapshot.carbs_g = v_expected_snapshot.carbs_g
      AND snapshot.fat_g = v_expected_snapshot.fat_g
  ) THEN
    RAISE EXCEPTION 'postcondition failed: snapshot totals mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_progress AS progress
    JOIN repair_params AS params ON params.target_user_id = progress.user_id
    CROSS JOIN repair_expected_progress AS expected
    WHERE progress.blocks_completed = expected.blocks_completed
      AND progress.deficit_block = expected.deficit_block
  ) THEN
    RAISE EXCEPTION 'postcondition failed: block replay mismatch';
  END IF;

  IF (
    SELECT count(*)
    FROM public.product_events AS event
    JOIN repair_params AS params ON params.target_user_id = event.user_id
    WHERE event.event = 'admin.kumis_meal_loss_repaired'
      AND event.properties->>'repair_id' = 'kumis-meal-loss-2026-07-13'
  ) <> 1 THEN
    RAISE EXCEPTION 'postcondition failed: repair audit event mismatch';
  END IF;
END;
$postconditions$;

SELECT jsonb_build_object(
  'mode', 'apply',
  'repair_id', 'kumis-meal-loss-2026-07-13',
  'snapshot_id', params.target_snapshot_id,
  'date', params.target_date,
  'restored_items', 8,
  'restored_kcal', 764.2,
  'snapshot_after', jsonb_build_object(
    'kcal', snapshot.calories_consumed,
    'protein_g', snapshot.protein_g,
    'carbs_g', snapshot.carbs_g,
    'fat_g', snapshot.fat_g
  ),
  'block_after', jsonb_build_object(
    'blocks_completed', progress.blocks_completed,
    'deficit_block', progress.deficit_block
  )
) AS repair_result
FROM repair_params AS params
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id
JOIN public.user_progress AS progress ON progress.user_id = params.target_user_id;

COMMIT;
