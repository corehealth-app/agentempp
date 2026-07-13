-- READ-ONLY. Nao altera dados nem expoe PII.
WITH
params AS (
  SELECT
    'aa557bdf-c13f-4383-a64a-9520430d58b9'::uuid AS target_log_id,
    '118587e3-e752-4a23-b304-57231d7ef40f'::uuid AS target_user_id,
    'f41fca76-8790-409f-b59e-e19f5c760fe4'::uuid AS target_snapshot_id,
    379::integer AS target_food_db_id,
    DATE '2026-07-12' AS target_date
),
target_user AS (
  SELECT users.id, users.country, users.timezone, users.status
  FROM public.users AS users
  CROSS JOIN params
  WHERE users.id = params.target_user_id
),
canonical AS (
  SELECT food.*
  FROM public.food_db AS food
  CROSS JOIN params
  WHERE food.id = params.target_food_db_id
),
target_log AS (
  SELECT meal.*
  FROM public.meal_logs AS meal
  CROSS JOIN params
  WHERE meal.id = params.target_log_id
),
target_snapshot AS (
  SELECT snapshot.*
  FROM public.daily_snapshots AS snapshot
  CROSS JOIN params
  WHERE snapshot.id = params.target_snapshot_id
),
proposed_snapshot AS (
  SELECT
    round(coalesce(sum(CASE WHEN meal.id = params.target_log_id THEN 252 ELSE meal.kcal END), 0))::integer AS calories_consumed,
    round(coalesce(sum(CASE WHEN meal.id = params.target_log_id THEN 4.2 ELSE meal.protein_g END), 0), 2) AS protein_g,
    round(coalesce(sum(CASE WHEN meal.id = params.target_log_id THEN 28.8 ELSE meal.carbs_g END), 0), 2) AS carbs_g,
    round(coalesce(sum(CASE WHEN meal.id = params.target_log_id THEN 13.2 ELSE meal.fat_g END), 0), 2) AS fat_g
  FROM params
  CROSS JOIN target_user
  LEFT JOIN public.meal_logs AS meal
    ON meal.user_id = params.target_user_id
   AND (meal.consumed_at AT TIME ZONE target_user.timezone)::date = params.target_date
),
profile AS (
  SELECT CASE
    WHEN profile.current_protocol = 'recomposicao' THEN coalesce(profile.deficit_level, 500)
    ELSE 0
  END::numeric AS design_deficit
  FROM public.user_profiles AS profile
  CROSS JOIN params
  WHERE profile.user_id = params.target_user_id
),
effective_closed AS (
  SELECT
    snapshot.id,
    snapshot.date,
    CASE WHEN snapshot.date = params.target_date
      THEN proposed.calories_consumed ELSE snapshot.calories_consumed END AS calories_consumed,
    snapshot.calories_target,
    snapshot.exercise_calories,
    CASE WHEN snapshot.date = params.target_date
      THEN proposed.calories_consumed
        - coalesce(snapshot.calories_target, 0)
        - coalesce(snapshot.exercise_calories, 0)
      ELSE snapshot.daily_balance END AS daily_balance,
    snapshot.day_status,
    snapshot.training_done,
    EXISTS (
      SELECT 1 FROM public.meal_logs AS meal WHERE meal.snapshot_id = snapshot.id
    ) AS has_meal
  FROM public.daily_snapshots AS snapshot
  CROSS JOIN params
  CROSS JOIN proposed_snapshot AS proposed
  WHERE snapshot.user_id = params.target_user_id
    AND snapshot.day_closed = true
),
credits AS (
  SELECT CASE
    WHEN NOT (closed.has_meal OR coalesce(closed.exercise_calories, 0) > 0 OR closed.training_done)
      THEN 0
    WHEN closed.day_status = 'user_skipped'
      THEN profile.design_deficit - closed.daily_balance
    WHEN closed.calories_target IS NOT NULL
      AND closed.calories_target > 0
      AND closed.calories_consumed < 0.5 * closed.calories_target
      THEN CASE WHEN closed.day_status = 'complete' OR closed.day_status IS NULL
        THEN profile.design_deficit ELSE 0 END
    WHEN closed.day_status = 'incomplete_no_response' THEN 0
    ELSE profile.design_deficit - closed.daily_balance
  END AS credit
  FROM effective_closed AS closed
  CROSS JOIN profile
),
proposed_progress AS (
  SELECT greatest(0, round(coalesce(sum(credit), 0)))::integer AS total
  FROM credits
),
checks AS (
  SELECT
    (SELECT count(*) = 1
       AND bool_and(country = 'US')
       AND bool_and(timezone = 'America/New_York')
       AND bool_and(status = 'active')
     FROM target_user) AS user_ok,
    (SELECT count(*) = 1
       AND bool_and(name_norm = 'sorvete')
       AND bool_and(country_code = 'BR')
       AND bool_and(kcal_per_100g = 210)
       AND bool_and(protein_g = 3.5)
       AND bool_and(carbs_g = 24)
       AND bool_and(fat_g = 11)
     FROM canonical) AS canonical_ok,
    (SELECT count(*) = 1
       AND bool_and(user_id = params.target_user_id)
       AND bool_and(snapshot_id = params.target_snapshot_id)
       AND bool_and(lower(trim(food_name)) = 'sorvete')
       AND bool_and(quantity_g = 120)
       AND bool_and(kcal = 78)
       AND bool_and(protein_g = 4.8)
       AND bool_and(carbs_g = 6)
       AND bool_and(fat_g = 3.6)
       AND bool_and(source = 'taco')
       AND bool_and(food_db_id IS NULL)
       AND bool_and(meal_type = 'jantar')
     FROM target_log CROSS JOIN params) AS log_ok,
    (SELECT count(*) = 1
       AND bool_and(user_id = params.target_user_id)
       AND bool_and(date = params.target_date)
       AND bool_and(calories_consumed = 1543)
       AND bool_and(protein_g = 129.6)
       AND bool_and(carbs_g = 103.5)
       AND bool_and(fat_g = 61.9)
       AND bool_and(day_closed = true)
       AND bool_and(day_status = 'complete')
     FROM target_snapshot CROSS JOIN params) AS snapshot_ok,
    (SELECT count(*) = 1
       AND bool_and(current_protocol = 'recomposicao')
       AND bool_and(deficit_level = 500)
     FROM public.user_profiles AS profile CROSS JOIN params
     WHERE profile.user_id = params.target_user_id) AS profile_ok,
    (SELECT count(*) = 1
       AND bool_and(deficit_block = 3581)
       AND bool_and(blocks_completed = 6)
     FROM public.user_progress AS progress CROSS JOIN params
     WHERE progress.user_id = params.target_user_id) AS progress_ok
)
SELECT jsonb_build_object(
  'mode', 'dry-run',
  'writes', 0,
  'preconditions_ok',
    checks.user_ok AND checks.canonical_ok AND checks.log_ok
    AND checks.snapshot_ok AND checks.profile_ok AND checks.progress_ok,
  'target', jsonb_build_object(
    'meal_log_id', params.target_log_id,
    'snapshot_id', params.target_snapshot_id,
    'date', params.target_date,
    'food_db_id', params.target_food_db_id
  ),
  'meal_log', jsonb_build_object(
    'before', jsonb_build_object(
      'quantity_g', target_log.quantity_g,
      'kcal', target_log.kcal,
      'protein_g', target_log.protein_g,
      'carbs_g', target_log.carbs_g,
      'fat_g', target_log.fat_g,
      'source', target_log.source,
      'food_db_id', target_log.food_db_id
    ),
    'after', jsonb_build_object(
      'quantity_g', 120,
      'kcal', 252,
      'protein_g', 4.2,
      'carbs_g', 28.8,
      'fat_g', 13.2,
      'source', 'canonical_exact',
      'food_db_id', params.target_food_db_id
    )
  ),
  'snapshot', jsonb_build_object(
    'before', jsonb_build_object(
      'kcal', target_snapshot.calories_consumed,
      'protein_g', target_snapshot.protein_g,
      'carbs_g', target_snapshot.carbs_g,
      'fat_g', target_snapshot.fat_g
    ),
    'after', to_jsonb(proposed_snapshot)
  ),
  'block', jsonb_build_object(
    'before', (
      SELECT jsonb_build_object(
        'blocks_completed', progress.blocks_completed,
        'deficit_block', progress.deficit_block
      )
      FROM public.user_progress AS progress
      WHERE progress.user_id = params.target_user_id
    ),
    'after', jsonb_build_object(
      'blocks_completed', proposed_progress.total / 7700,
      'deficit_block', proposed_progress.total % 7700
    )
  )
) AS repair_preview
FROM params
CROSS JOIN checks
CROSS JOIN target_log
CROSS JOIN target_snapshot
CROSS JOIN proposed_snapshot
CROSS JOIN proposed_progress;
