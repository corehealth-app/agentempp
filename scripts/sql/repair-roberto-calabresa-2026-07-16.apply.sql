BEGIN;

SELECT pg_advisory_xact_lock(hashtext('repair-roberto-calabresa-2026-07-16'));

CREATE TEMP TABLE repair_params ON COMMIT DROP AS
SELECT
  '118587e3-e752-4a23-b304-57231d7ef40f'::uuid AS target_user_id,
  '07f5196f-6604-4ad3-bab4-6b37743bed74'::uuid AS target_snapshot_id,
  'd09047ea-5726-4a97-b21b-798a10d63088'::uuid AS calabresa_log_id,
  317::integer AS calabresa_food_db_id,
  DATE '2026-07-15' AS target_date,
  ARRAY[
    '4d2cbe38-c3e8-446c-8416-cfba608c9a36'::uuid,
    '7245ce9f-b3be-4f3b-bf5f-135c1e82aab4'::uuid,
    'cebaba6a-24d4-4a5f-8b4f-15e0b8810b89'::uuid,
    'd2dd36bb-b99c-45da-8e72-a778b839f6b6'::uuid
  ] AS duplicate_log_ids;

CREATE TEMP TABLE repair_expected_duplicates (
  id uuid PRIMARY KEY,
  food_name text NOT NULL,
  quantity_g numeric NOT NULL,
  kcal numeric NOT NULL,
  protein_g numeric NOT NULL,
  carbs_g numeric NOT NULL,
  fat_g numeric NOT NULL,
  food_db_id integer,
  source text NOT NULL
) ON COMMIT DROP;

INSERT INTO repair_expected_duplicates VALUES
  ('4d2cbe38-c3e8-446c-8416-cfba608c9a36', 'rap10', 35, 52.5, 2.45, 6.3, 1.75, NULL, 'pending_approved'),
  ('7245ce9f-b3be-4f3b-bf5f-135c1e82aab4', 'ovo cozido', 100, 146, 13.3, 0.6, 9.5, 232, 'pending_approved'),
  ('cebaba6a-24d4-4a5f-8b4f-15e0b8810b89', 'queijo derretido', 30, 87, 6, 0.9, 6.6, NULL, 'pending_approved'),
  ('d2dd36bb-b99c-45da-8e72-a778b839f6b6', 'tomate cereja', 40, 7.2, 0.36, 1.56, 0.08, 426, 'pending_approved');

CREATE TEMP TABLE repair_expected_preserved (
  id uuid PRIMARY KEY,
  food_name text NOT NULL,
  quantity_g numeric NOT NULL,
  kcal numeric NOT NULL,
  protein_g numeric NOT NULL,
  carbs_g numeric NOT NULL,
  fat_g numeric NOT NULL,
  food_db_id integer,
  source text NOT NULL
) ON COMMIT DROP;

INSERT INTO repair_expected_preserved VALUES
  ('44b7457c-a54f-4a59-af5d-4d02e0993971', 'tomate cereja', 40, 7.2, 0.36, 1.56, 0.08, 426, 'pending_approved'),
  ('a05d8c6f-3128-41c4-ba49-7988bfb216b2', 'rap10', 35, 70, 3.27, 8.4, 2.33, NULL, 'pending_approved'),
  ('cd6a0213-64f0-4546-8eb8-2cf27a523ca8', 'ovo cozido', 100, 146, 13.3, 0.6, 9.5, 232, 'pending_approved'),
  ('ffbc4850-2141-4539-b787-cc2e934ad210', 'queijo derretido', 30, 87, 6, 0.9, 6.6, NULL, 'pending_approved');

-- Same locks used by the daily closer and meal registration paths.
SELECT pg_advisory_xact_lock(hashtextextended(target_user_id::text || ':daily-close', 0))
FROM repair_params;

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
  total.value,
  (total.value / 7700)::smallint AS blocks_completed,
  total.value % 7700 AS deficit_block
FROM total;

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
    JOIN repair_params AS params ON params.calabresa_food_db_id = food.id
    WHERE food.name_norm = 'linguica calabresa'
      AND food.country_code = 'BR'
      AND food.kcal_per_100g = 310
      AND food.protein_g = 18
      AND food.carbs_g = 2
      AND food.fat_g = 26
  ) THEN
    RAISE EXCEPTION 'precondition failed: canonical calabresa reference changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.calabresa_log_id = meal.id
    WHERE meal.user_id = params.target_user_id
      AND meal.snapshot_id = params.target_snapshot_id
      AND meal.food_name = 'calabresa fatiada'
      AND meal.quantity_g = 60
      AND meal.kcal = 168
      AND meal.protein_g = 7.2
      AND meal.carbs_g = 16.8
      AND meal.fat_g = 7.8
      AND meal.food_db_id = 304
      AND meal.source = 'pending_approved'
      AND meal.meal_type = 'jantar'
  ) THEN
    RAISE EXCEPTION 'precondition failed: calabresa meal log changed';
  END IF;

  IF EXISTS (
    SELECT * FROM repair_expected_duplicates
    EXCEPT
    SELECT
      meal.id, meal.food_name, meal.quantity_g, meal.kcal, meal.protein_g,
      meal.carbs_g, meal.fat_g, meal.food_db_id, meal.source
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON meal.id = ANY(params.duplicate_log_ids)
  ) OR EXISTS (
    SELECT
      meal.id, meal.food_name, meal.quantity_g, meal.kcal, meal.protein_g,
      meal.carbs_g, meal.fat_g, meal.food_db_id, meal.source
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON meal.id = ANY(params.duplicate_log_ids)
    EXCEPT
    SELECT * FROM repair_expected_duplicates
  ) THEN
    RAISE EXCEPTION 'precondition failed: duplicate meal rows changed';
  END IF;

  IF EXISTS (
    SELECT * FROM repair_expected_preserved
    EXCEPT
    SELECT
      meal.id, meal.food_name, meal.quantity_g, meal.kcal, meal.protein_g,
      meal.carbs_g, meal.fat_g, meal.food_db_id, meal.source
    FROM public.meal_logs AS meal
    JOIN repair_expected_preserved AS expected ON expected.id = meal.id
  ) OR EXISTS (
    SELECT
      meal.id, meal.food_name, meal.quantity_g, meal.kcal, meal.protein_g,
      meal.carbs_g, meal.fat_g, meal.food_db_id, meal.source
    FROM public.meal_logs AS meal
    JOIN repair_expected_preserved AS expected ON expected.id = meal.id
    EXCEPT
    SELECT * FROM repair_expected_preserved
  ) THEN
    RAISE EXCEPTION 'precondition failed: preserved meal rows changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.daily_snapshots AS snapshot
    JOIN repair_params AS params ON params.target_snapshot_id = snapshot.id
    WHERE snapshot.user_id = params.target_user_id
      AND snapshot.date = params.target_date
      AND snapshot.calories_consumed = 1888
      AND snapshot.protein_g = 135.5
      AND snapshot.carbs_g = 172.4
      AND snapshot.fat_g = 71.3
      AND snapshot.calories_target = 1935
      AND snapshot.exercise_calories = 563
      AND snapshot.day_closed = true
      AND snapshot.day_status = 'complete'
  ) THEN
    RAISE EXCEPTION 'precondition failed: target snapshot changed';
  END IF;

  IF (
    SELECT count(*)
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.target_user_id = meal.user_id
    JOIN public.users AS users ON users.id = params.target_user_id
    WHERE (meal.consumed_at AT TIME ZONE users.timezone)::date = params.target_date
  ) <> 24 OR (
    SELECT count(*)
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.target_user_id = meal.user_id
    JOIN public.users AS users ON users.id = params.target_user_id
    WHERE (meal.consumed_at AT TIME ZONE users.timezone)::date = params.target_date
      AND meal.meal_type = 'jantar'
  ) <> 9 OR EXISTS (
    SELECT 1
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.target_user_id = meal.user_id
    JOIN public.users AS users ON users.id = params.target_user_id
    WHERE (meal.consumed_at AT TIME ZONE users.timezone)::date = params.target_date
      AND meal.food_name = 'salame fatiado'
  ) THEN
    RAISE EXCEPTION 'precondition failed: target day shape changed';
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
    CROSS JOIN repair_expected_progress_before AS expected
    WHERE progress.deficit_block = expected.deficit_block
      AND progress.blocks_completed = expected.blocks_completed
  ) THEN
    RAISE EXCEPTION 'precondition failed: block progress differs from closed-day replay';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.product_events AS event
    JOIN repair_params AS params ON params.target_user_id = event.user_id
    WHERE event.event = 'admin.roberto_calabresa_repaired'
      AND event.properties->>'repair_id' = 'roberto-calabresa-2026-07-16'
  ) THEN
    RAISE EXCEPTION 'precondition failed: repair was already applied';
  END IF;
END;
$preconditions$;

CREATE TEMP TABLE repair_before ON COMMIT DROP AS
SELECT
  jsonb_build_object(
    'kcal', meal.kcal,
    'protein_g', meal.protein_g,
    'carbs_g', meal.carbs_g,
    'fat_g', meal.fat_g,
    'source', meal.source,
    'food_db_id', meal.food_db_id
  ) AS calabresa,
  jsonb_build_object(
    'kcal', snapshot.calories_consumed,
    'protein_g', snapshot.protein_g,
    'carbs_g', snapshot.carbs_g,
    'fat_g', snapshot.fat_g,
    'daily_balance', snapshot.daily_balance
  ) AS snapshot,
  jsonb_build_object(
    'blocks_completed', progress.blocks_completed,
    'deficit_block', progress.deficit_block
  ) AS block
FROM repair_params AS params
JOIN public.meal_logs AS meal ON meal.id = params.calabresa_log_id
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id
JOIN public.user_progress AS progress ON progress.user_id = params.target_user_id;

CREATE TEMP TABLE repair_deleted_logs (
  id uuid PRIMARY KEY,
  kcal numeric NOT NULL
) ON COMMIT DROP;

WITH deleted AS (
  DELETE FROM public.meal_logs AS meal
  USING repair_params AS params
  WHERE meal.id = ANY(params.duplicate_log_ids)
  RETURNING meal.id, meal.kcal
)
INSERT INTO repair_deleted_logs (id, kcal)
SELECT id, kcal FROM deleted;

DO $deleted_count$
BEGIN
  IF (SELECT count(*) FROM repair_deleted_logs) <> 4 THEN
    RAISE EXCEPTION 'mutation failed: expected four duplicate rows deleted';
  END IF;
END;
$deleted_count$;

UPDATE public.meal_logs AS meal
SET kcal = 186,
    protein_g = 10.8,
    carbs_g = 1.2,
    fat_g = 15.6,
    source = 'canonical_fuzzy',
    food_db_id = params.calabresa_food_db_id
FROM repair_params AS params
WHERE meal.id = params.calabresa_log_id;

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

CREATE TEMP TABLE repair_expected_progress_after ON COMMIT DROP AS
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
  total.value,
  (total.value / 7700)::smallint AS blocks_completed,
  total.value % 7700 AS deficit_block
FROM total;

DO $credit_delta$
BEGIN
  IF (
    SELECT after.value - before.value
    FROM repair_expected_progress_after AS after
    CROSS JOIN repair_expected_progress_before AS before
  ) <> 275 THEN
    RAISE EXCEPTION 'mutation failed: block replay delta is not 275 kcal';
  END IF;
END;
$credit_delta$;

UPDATE public.user_progress AS progress
SET blocks_completed = expected.blocks_completed,
    deficit_block = expected.deficit_block,
    updated_at = now()
FROM repair_expected_progress_after AS expected
CROSS JOIN repair_params AS params
WHERE progress.user_id = params.target_user_id;

INSERT INTO public.product_events (user_id, event, properties)
SELECT
  params.target_user_id,
  'admin.roberto_calabresa_repaired',
  jsonb_build_object(
    'repair_id', 'roberto-calabresa-2026-07-16',
    'snapshot_id', params.target_snapshot_id,
    'date', params.target_date,
    'calabresa_log_id', params.calabresa_log_id,
    'deleted_log_ids', to_jsonb(params.duplicate_log_ids),
    'deleted_kcal', (SELECT sum(kcal) FROM repair_deleted_logs),
    'calabresa_before', before.calabresa,
    'calabresa_after', jsonb_build_object(
      'kcal', meal.kcal,
      'protein_g', meal.protein_g,
      'carbs_g', meal.carbs_g,
      'fat_g', meal.fat_g,
      'source', meal.source,
      'food_db_id', meal.food_db_id
    ),
    'snapshot_before', before.snapshot,
    'snapshot_after', jsonb_build_object(
      'kcal', snapshot.calories_consumed,
      'protein_g', snapshot.protein_g,
      'carbs_g', snapshot.carbs_g,
      'fat_g', snapshot.fat_g,
      'daily_balance', snapshot.daily_balance
    ),
    'block_before', before.block,
    'block_after', jsonb_build_object(
      'blocks_completed', progress.blocks_completed,
      'deficit_block', progress.deficit_block
    ),
    'authorization', 'confirm=roberto-calabresa-2026-07-16'
  )
FROM repair_params AS params
CROSS JOIN repair_before AS before
JOIN public.meal_logs AS meal ON meal.id = params.calabresa_log_id
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id
JOIN public.user_progress AS progress ON progress.user_id = params.target_user_id;

DO $postconditions$
DECLARE
  v_expected_snapshot record;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON meal.id = ANY(params.duplicate_log_ids)
  ) THEN
    RAISE EXCEPTION 'postcondition failed: duplicate rows remain';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.calabresa_log_id = meal.id
    WHERE meal.kcal = 186
      AND meal.protein_g = 10.8
      AND meal.carbs_g = 1.2
      AND meal.fat_g = 15.6
      AND meal.source = 'canonical_fuzzy'
      AND meal.food_db_id = params.calabresa_food_db_id
  ) THEN
    RAISE EXCEPTION 'postcondition failed: calabresa row mismatch';
  END IF;

  IF EXISTS (
    SELECT * FROM repair_expected_preserved
    EXCEPT
    SELECT
      meal.id, meal.food_name, meal.quantity_g, meal.kcal, meal.protein_g,
      meal.carbs_g, meal.fat_g, meal.food_db_id, meal.source
    FROM public.meal_logs AS meal
    JOIN repair_expected_preserved AS expected ON expected.id = meal.id
  ) THEN
    RAISE EXCEPTION 'postcondition failed: an original dinner row changed';
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

  IF v_expected_snapshot.kcal <> 1613
    OR v_expected_snapshot.protein_g <> 116.98
    OR v_expected_snapshot.carbs_g <> 147.45
    OR v_expected_snapshot.fat_g <> 61.13 THEN
    RAISE EXCEPTION 'postcondition failed: meal log totals differ from audited target';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.daily_snapshots AS snapshot
    JOIN repair_params AS params ON params.target_snapshot_id = snapshot.id
    WHERE snapshot.calories_consumed = v_expected_snapshot.kcal
      AND snapshot.protein_g = v_expected_snapshot.protein_g
      AND snapshot.carbs_g = v_expected_snapshot.carbs_g
      AND snapshot.fat_g = v_expected_snapshot.fat_g
      AND snapshot.daily_balance = -885
  ) THEN
    RAISE EXCEPTION 'postcondition failed: snapshot totals mismatch';
  END IF;

  IF (
    SELECT count(*)
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.target_user_id = meal.user_id
    JOIN public.users AS users ON users.id = params.target_user_id
    WHERE (meal.consumed_at AT TIME ZONE users.timezone)::date = params.target_date
  ) <> 20 OR (
    SELECT count(*)
    FROM public.meal_logs AS meal
    JOIN repair_params AS params ON params.target_user_id = meal.user_id
    JOIN public.users AS users ON users.id = params.target_user_id
    WHERE (meal.consumed_at AT TIME ZONE users.timezone)::date = params.target_date
      AND meal.meal_type = 'jantar'
  ) <> 5 THEN
    RAISE EXCEPTION 'postcondition failed: repaired day shape mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_progress AS progress
    JOIN repair_params AS params ON params.target_user_id = progress.user_id
    CROSS JOIN repair_expected_progress_after AS expected
    WHERE progress.blocks_completed = expected.blocks_completed
      AND progress.deficit_block = expected.deficit_block
  ) THEN
    RAISE EXCEPTION 'postcondition failed: block replay mismatch';
  END IF;

  IF (
    SELECT count(*)
    FROM public.product_events AS event
    JOIN repair_params AS params ON params.target_user_id = event.user_id
    WHERE event.event = 'admin.roberto_calabresa_repaired'
      AND event.properties->>'repair_id' = 'roberto-calabresa-2026-07-16'
  ) <> 1 THEN
    RAISE EXCEPTION 'postcondition failed: repair audit event mismatch';
  END IF;
END;
$postconditions$;

SELECT jsonb_build_object(
  'mode', 'apply',
  'repair_id', 'roberto-calabresa-2026-07-16',
  'snapshot_id', params.target_snapshot_id,
  'date', params.target_date,
  'deleted_rows', (SELECT count(*) FROM repair_deleted_logs),
  'calabresa_after', jsonb_build_object(
    'kcal', meal.kcal,
    'protein_g', meal.protein_g,
    'carbs_g', meal.carbs_g,
    'fat_g', meal.fat_g,
    'food_db_id', meal.food_db_id,
    'source', meal.source
  ),
  'snapshot_after', jsonb_build_object(
    'kcal', snapshot.calories_consumed,
    'protein_g', snapshot.protein_g,
    'carbs_g', snapshot.carbs_g,
    'fat_g', snapshot.fat_g,
    'daily_balance', snapshot.daily_balance
  ),
  'block_after', jsonb_build_object(
    'blocks_completed', progress.blocks_completed,
    'deficit_block', progress.deficit_block
  )
) AS repair_result
FROM repair_params AS params
JOIN public.meal_logs AS meal ON meal.id = params.calabresa_log_id
JOIN public.daily_snapshots AS snapshot ON snapshot.id = params.target_snapshot_id
JOIN public.user_progress AS progress ON progress.user_id = params.target_user_id;

COMMIT;
