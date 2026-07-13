BEGIN;

SELECT pg_advisory_xact_lock(hashtext('repair-sorvete-aa557bdf-2026-07-13'));

CREATE TEMP TABLE repair_params ON COMMIT DROP AS
SELECT
  'aa557bdf-c13f-4383-a64a-9520430d58b9'::uuid AS target_log_id,
  '118587e3-e752-4a23-b304-57231d7ef40f'::uuid AS target_user_id,
  'f41fca76-8790-409f-b59e-e19f5c760fe4'::uuid AS target_snapshot_id,
  379::integer AS target_food_db_id,
  DATE '2026-07-12' AS target_date;

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
  FROM public.meal_logs AS meal
  JOIN repair_params AS params ON params.target_log_id = meal.id
  FOR UPDATE OF meal;
END;
$lock_rows$;

DO $preconditions$
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
    JOIN repair_params AS params ON params.target_food_db_id = food.id
    WHERE food.name_norm = 'sorvete'
      AND food.country_code = 'BR'
      AND food.kcal_per_100g = 210
      AND food.protein_g = 3.5
      AND food.carbs_g = 24
      AND food.fat_g = 11
  ) THEN
    RAISE EXCEPTION 'precondition failed: canonical sorvete reference changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.target_log_id = meal.id
    WHERE meal.user_id = params.target_user_id
      AND meal.snapshot_id = params.target_snapshot_id
      AND lower(trim(meal.food_name)) = 'sorvete'
      AND meal.quantity_g = 120
      AND meal.kcal = 78
      AND meal.protein_g = 4.8
      AND meal.carbs_g = 6
      AND meal.fat_g = 3.6
      AND meal.source = 'taco'
      AND meal.food_db_id IS NULL
      AND meal.meal_type = 'jantar'
  ) THEN
    RAISE EXCEPTION 'precondition failed: target meal log changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.daily_snapshots AS snapshot
    JOIN repair_params AS params ON params.target_snapshot_id = snapshot.id
    WHERE snapshot.user_id = params.target_user_id
      AND snapshot.date = params.target_date
      AND snapshot.calories_consumed = 1543
      AND snapshot.protein_g = 129.6
      AND snapshot.carbs_g = 103.5
      AND snapshot.fat_g = 61.9
      AND snapshot.day_closed = true
      AND snapshot.day_status = 'complete'
  ) THEN
    RAISE EXCEPTION 'precondition failed: target snapshot changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_profiles AS profile
    JOIN repair_params AS params ON params.target_user_id = profile.user_id
    WHERE profile.current_protocol = 'recomposicao'
      AND profile.deficit_level = 500
  ) THEN
    RAISE EXCEPTION 'precondition failed: target profile changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_progress AS progress
    JOIN repair_params AS params ON params.target_user_id = progress.user_id
    WHERE progress.deficit_block = 3581
      AND progress.blocks_completed = 6
  ) THEN
    RAISE EXCEPTION 'precondition failed: block progress changed';
  END IF;
END;
$preconditions$;

CREATE TEMP TABLE repair_before ON COMMIT DROP AS
SELECT
  jsonb_build_object(
    'quantity_g', meal.quantity_g,
    'kcal', meal.kcal,
    'protein_g', meal.protein_g,
    'carbs_g', meal.carbs_g,
    'fat_g', meal.fat_g,
    'source', meal.source,
    'food_db_id', meal.food_db_id
  ) AS meal_log,
  jsonb_build_object(
    'kcal', snapshot.calories_consumed,
    'protein_g', snapshot.protein_g,
    'carbs_g', snapshot.carbs_g,
    'fat_g', snapshot.fat_g
  ) AS snapshot,
  jsonb_build_object(
    'blocks_completed', progress.blocks_completed,
    'deficit_block', progress.deficit_block
  ) AS block
FROM repair_params AS params
JOIN public.meal_logs AS meal ON meal.id = params.target_log_id
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id
JOIN public.user_progress AS progress ON progress.user_id = params.target_user_id;

UPDATE public.meal_logs AS meal
SET kcal = 252,
    protein_g = 4.2,
    carbs_g = 28.8,
    fat_g = 13.2,
    source = 'canonical_exact',
    food_db_id = params.target_food_db_id
FROM repair_params AS params
WHERE meal.id = params.target_log_id;

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
UPDATE public.daily_snapshots AS snapshot
SET calories_consumed = totals.kcal,
    protein_g = totals.protein_g,
    carbs_g = totals.carbs_g,
    fat_g = totals.fat_g,
    updated_at = now()
FROM totals
CROSS JOIN repair_params AS params
WHERE snapshot.id = params.target_snapshot_id;

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
  'admin.sorvete_nutrition_repaired',
  jsonb_build_object(
    'repair_id', 'sorvete-aa557bdf-2026-07-13',
    'meal_log_id', params.target_log_id,
    'snapshot_id', params.target_snapshot_id,
    'date', params.target_date,
    'food_db_id', params.target_food_db_id,
    'meal_before', before.meal_log,
    'meal_after', jsonb_build_object(
      'quantity_g', 120,
      'kcal', 252,
      'protein_g', 4.2,
      'carbs_g', 28.8,
      'fat_g', 13.2,
      'source', 'canonical_exact',
      'food_db_id', params.target_food_db_id
    ),
    'snapshot_before', before.snapshot,
    'snapshot_after', jsonb_build_object(
      'kcal', snapshot.calories_consumed,
      'protein_g', snapshot.protein_g,
      'carbs_g', snapshot.carbs_g,
      'fat_g', snapshot.fat_g
    ),
    'block_before', before.block,
    'block_after', jsonb_build_object(
      'blocks_completed', progress.blocks_completed,
      'deficit_block', progress.deficit_block
    ),
    'authorization', 'user_approved_plan_2026-07-13'
  )
FROM repair_params AS params
CROSS JOIN repair_before AS before
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id
JOIN public.user_progress AS progress ON progress.user_id = params.target_user_id;

DO $postconditions$
DECLARE
  v_expected_snapshot record;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.target_log_id = meal.id
    WHERE meal.kcal = 252
      AND meal.protein_g = 4.2
      AND meal.carbs_g = 28.8
      AND meal.fat_g = 13.2
      AND meal.source = 'canonical_exact'
      AND meal.food_db_id = params.target_food_db_id
  ) THEN
    RAISE EXCEPTION 'postcondition failed: target meal log mismatch';
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
    WHERE event.event = 'admin.sorvete_nutrition_repaired'
      AND event.properties->>'meal_log_id' = params.target_log_id::text
  ) <> 1 THEN
    RAISE EXCEPTION 'postcondition failed: repair audit event mismatch';
  END IF;
END;
$postconditions$;

SELECT jsonb_build_object(
  'mode', 'apply',
  'repair_id', 'sorvete-aa557bdf-2026-07-13',
  'meal_log_id', params.target_log_id,
  'snapshot_id', params.target_snapshot_id,
  'date', params.target_date,
  'food_db_id', params.target_food_db_id,
  'meal_after', jsonb_build_object(
    'quantity_g', meal.quantity_g,
    'kcal', meal.kcal,
    'protein_g', meal.protein_g,
    'carbs_g', meal.carbs_g,
    'fat_g', meal.fat_g,
    'source', meal.source
  ),
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
JOIN public.meal_logs AS meal ON meal.id = params.target_log_id
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id
JOIN public.user_progress AS progress ON progress.user_id = params.target_user_id;

COMMIT;
