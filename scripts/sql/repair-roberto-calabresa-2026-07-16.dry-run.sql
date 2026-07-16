-- READ-ONLY. Nao altera dados nem expoe PII ou ids de mensagens do provedor.
WITH
params AS (
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
    ] AS duplicate_log_ids
),
expected_duplicates (
  id, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, food_db_id, source
) AS (
  VALUES
    ('4d2cbe38-c3e8-446c-8416-cfba608c9a36'::uuid, 'rap10', 35::numeric, 52.5::numeric, 2.45::numeric, 6.3::numeric, 1.75::numeric, NULL::integer, 'pending_approved'),
    ('7245ce9f-b3be-4f3b-bf5f-135c1e82aab4'::uuid, 'ovo cozido', 100, 146, 13.3, 0.6, 9.5, 232, 'pending_approved'),
    ('cebaba6a-24d4-4a5f-8b4f-15e0b8810b89'::uuid, 'queijo derretido', 30, 87, 6, 0.9, 6.6, NULL::integer, 'pending_approved'),
    ('d2dd36bb-b99c-45da-8e72-a778b839f6b6'::uuid, 'tomate cereja', 40, 7.2, 0.36, 1.56, 0.08, 426, 'pending_approved')
),
expected_preserved (
  id, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, food_db_id, source
) AS (
  VALUES
    ('44b7457c-a54f-4a59-af5d-4d02e0993971'::uuid, 'tomate cereja', 40::numeric, 7.2::numeric, 0.36::numeric, 1.56::numeric, 0.08::numeric, 426, 'pending_approved'),
    ('a05d8c6f-3128-41c4-ba49-7988bfb216b2'::uuid, 'rap10', 35, 70, 3.27, 8.4, 2.33, NULL::integer, 'pending_approved'),
    ('cd6a0213-64f0-4546-8eb8-2cf27a523ca8'::uuid, 'ovo cozido', 100, 146, 13.3, 0.6, 9.5, 232, 'pending_approved'),
    ('ffbc4850-2141-4539-b787-cc2e934ad210'::uuid, 'queijo derretido', 30, 87, 6, 0.9, 6.6, NULL::integer, 'pending_approved')
),
target_user AS (
  SELECT users.id, users.country, users.timezone, users.status
  FROM public.users AS users
  CROSS JOIN params
  WHERE users.id = params.target_user_id
),
target_snapshot AS (
  SELECT snapshot.*
  FROM public.daily_snapshots AS snapshot
  CROSS JOIN params
  WHERE snapshot.id = params.target_snapshot_id
),
target_calabresa AS (
  SELECT meal.*
  FROM public.meal_logs AS meal
  CROSS JOIN params
  WHERE meal.id = params.calabresa_log_id
),
actual_duplicates AS (
  SELECT
    meal.id,
    meal.food_name,
    meal.quantity_g,
    meal.kcal,
    meal.protein_g,
    meal.carbs_g,
    meal.fat_g,
    meal.food_db_id,
    meal.source
  FROM public.meal_logs AS meal
  CROSS JOIN params
  WHERE meal.id = ANY(params.duplicate_log_ids)
),
actual_preserved AS (
  SELECT
    meal.id,
    meal.food_name,
    meal.quantity_g,
    meal.kcal,
    meal.protein_g,
    meal.carbs_g,
    meal.fat_g,
    meal.food_db_id,
    meal.source
  FROM public.meal_logs AS meal
  WHERE meal.id IN (
    '44b7457c-a54f-4a59-af5d-4d02e0993971',
    'a05d8c6f-3128-41c4-ba49-7988bfb216b2',
    'cd6a0213-64f0-4546-8eb8-2cf27a523ca8',
    'ffbc4850-2141-4539-b787-cc2e934ad210'
  )
),
proposed_snapshot AS (
  SELECT
    round(coalesce(sum(
      CASE WHEN meal.id = params.calabresa_log_id THEN 186 ELSE meal.kcal END
    ), 0))::integer AS calories_consumed,
    round(coalesce(sum(
      CASE WHEN meal.id = params.calabresa_log_id THEN 10.8 ELSE meal.protein_g END
    ), 0), 2) AS protein_g,
    round(coalesce(sum(
      CASE WHEN meal.id = params.calabresa_log_id THEN 1.2 ELSE meal.carbs_g END
    ), 0), 2) AS carbs_g,
    round(coalesce(sum(
      CASE WHEN meal.id = params.calabresa_log_id THEN 15.6 ELSE meal.fat_g END
    ), 0), 2) AS fat_g
  FROM params
  CROSS JOIN target_user
  LEFT JOIN public.meal_logs AS meal
    ON meal.user_id = params.target_user_id
   AND (meal.consumed_at AT TIME ZONE target_user.timezone)::date = params.target_date
   AND meal.id <> ALL(params.duplicate_log_ids)
),
profile AS (
  SELECT CASE
    WHEN user_profile.current_protocol = 'recomposicao'
      THEN coalesce(user_profile.deficit_level, 500)
    ELSE 0
  END::numeric AS design_deficit
  FROM public.user_profiles AS user_profile
  CROSS JOIN params
  WHERE user_profile.user_id = params.target_user_id
),
current_credits AS (
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
  CROSS JOIN params
  CROSS JOIN profile
  WHERE snapshot.user_id = params.target_user_id
    AND snapshot.day_closed = true
),
current_progress AS (
  SELECT greatest(0, round(coalesce(sum(credit), 0)))::integer AS total
  FROM current_credits
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
      SELECT 1
      FROM public.meal_logs AS meal
      WHERE meal.snapshot_id = snapshot.id
        AND meal.id <> ALL(params.duplicate_log_ids)
    ) AS has_meal
  FROM public.daily_snapshots AS snapshot
  CROSS JOIN params
  CROSS JOIN proposed_snapshot AS proposed
  WHERE snapshot.user_id = params.target_user_id
    AND snapshot.day_closed = true
),
proposed_credits AS (
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
  FROM proposed_credits
),
checks AS (
  SELECT
    (SELECT count(*) = 1
       AND bool_and(country = 'US')
       AND bool_and(timezone = 'America/New_York')
       AND bool_and(status = 'active')
     FROM target_user) AS user_ok,
    (SELECT count(*) = 1
       AND bool_and(name_norm = 'linguica calabresa')
       AND bool_and(country_code = 'BR')
       AND bool_and(kcal_per_100g = 310)
       AND bool_and(protein_g = 18)
       AND bool_and(carbs_g = 2)
       AND bool_and(fat_g = 26)
     FROM public.food_db AS food CROSS JOIN params
     WHERE food.id = params.calabresa_food_db_id) AS canonical_ok,
    (SELECT count(*) = 1
       AND bool_and(user_id = params.target_user_id)
       AND bool_and(snapshot_id = params.target_snapshot_id)
       AND bool_and(food_name = 'calabresa fatiada')
       AND bool_and(quantity_g = 60)
       AND bool_and(kcal = 168)
       AND bool_and(protein_g = 7.2)
       AND bool_and(carbs_g = 16.8)
       AND bool_and(fat_g = 7.8)
       AND bool_and(food_db_id = 304)
       AND bool_and(source = 'pending_approved')
       AND bool_and(meal_type = 'jantar')
     FROM target_calabresa CROSS JOIN params) AS calabresa_ok,
    NOT EXISTS (SELECT * FROM expected_duplicates EXCEPT SELECT * FROM actual_duplicates)
      AND NOT EXISTS (SELECT * FROM actual_duplicates EXCEPT SELECT * FROM expected_duplicates)
      AS duplicates_ok,
    NOT EXISTS (SELECT * FROM expected_preserved EXCEPT SELECT * FROM actual_preserved)
      AND NOT EXISTS (SELECT * FROM actual_preserved EXCEPT SELECT * FROM expected_preserved)
      AS preserved_ok,
    (SELECT count(*) = 1
       AND bool_and(user_id = params.target_user_id)
       AND bool_and(date = params.target_date)
       AND bool_and(calories_consumed = 1888)
       AND bool_and(protein_g = 135.5)
       AND bool_and(carbs_g = 172.4)
       AND bool_and(fat_g = 71.3)
       AND bool_and(calories_target = 1935)
       AND bool_and(exercise_calories = 563)
       AND bool_and(day_closed = true)
       AND bool_and(day_status = 'complete')
     FROM target_snapshot CROSS JOIN params) AS snapshot_ok,
    (SELECT count(*) = 24
       AND count(*) FILTER (WHERE meal.meal_type = 'jantar') = 9
       AND count(*) FILTER (WHERE meal.food_name = 'salame fatiado') = 0
     FROM public.meal_logs AS meal CROSS JOIN params CROSS JOIN target_user
     WHERE meal.user_id = params.target_user_id
       AND (meal.consumed_at AT TIME ZONE target_user.timezone)::date = params.target_date)
      AS day_shape_ok,
    (SELECT count(*) = 1
       AND bool_and(current_protocol = 'recomposicao')
       AND bool_and(deficit_level = 500)
     FROM public.user_profiles AS user_profile CROSS JOIN params
     WHERE user_profile.user_id = params.target_user_id) AS profile_ok,
    (SELECT count(*) = 1
       AND bool_and(deficit_block = current_progress.total % 7700)
       AND bool_and(blocks_completed = current_progress.total / 7700)
     FROM public.user_progress AS progress
     CROSS JOIN params
     CROSS JOIN current_progress
     WHERE progress.user_id = params.target_user_id) AS progress_ok,
    NOT EXISTS (
      SELECT 1
      FROM public.product_events AS event
      CROSS JOIN params
      WHERE event.user_id = params.target_user_id
        AND event.event = 'admin.roberto_calabresa_repaired'
        AND event.properties->>'repair_id' = 'roberto-calabresa-2026-07-16'
    ) AS not_already_applied
)
SELECT jsonb_build_object(
  'mode', 'dry-run',
  'writes', 0,
  'preconditions_ok',
    checks.user_ok AND checks.canonical_ok AND checks.calabresa_ok
    AND checks.duplicates_ok AND checks.preserved_ok AND checks.snapshot_ok
    AND checks.day_shape_ok AND checks.profile_ok AND checks.progress_ok
    AND checks.not_already_applied,
  'checks', to_jsonb(checks),
  'target', jsonb_build_object(
    'snapshot_id', params.target_snapshot_id,
    'date', params.target_date,
    'calabresa_log_id', params.calabresa_log_id,
    'duplicate_log_ids', to_jsonb(params.duplicate_log_ids),
    'food_db_id', params.calabresa_food_db_id
  ),
  'calabresa', jsonb_build_object(
    'before', jsonb_build_object(
      'kcal', target_calabresa.kcal,
      'protein_g', target_calabresa.protein_g,
      'carbs_g', target_calabresa.carbs_g,
      'fat_g', target_calabresa.fat_g,
      'food_db_id', target_calabresa.food_db_id,
      'source', target_calabresa.source
    ),
    'after', jsonb_build_object(
      'kcal', 186,
      'protein_g', 10.8,
      'carbs_g', 1.2,
      'fat_g', 15.6,
      'food_db_id', params.calabresa_food_db_id,
      'source', 'canonical_fuzzy'
    )
  ),
  'snapshot', jsonb_build_object(
    'before', jsonb_build_object(
      'kcal', target_snapshot.calories_consumed,
      'protein_g', target_snapshot.protein_g,
      'carbs_g', target_snapshot.carbs_g,
      'fat_g', target_snapshot.fat_g,
      'daily_balance', target_snapshot.daily_balance
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
    'replay_before', jsonb_build_object(
      'blocks_completed', current_progress.total / 7700,
      'deficit_block', current_progress.total % 7700
    ),
    'after', jsonb_build_object(
      'blocks_completed', proposed_progress.total / 7700,
      'deficit_block', proposed_progress.total % 7700
    )
  )
) AS repair_preview
FROM params
CROSS JOIN checks
CROSS JOIN target_snapshot
CROSS JOIN target_calabresa
CROSS JOIN proposed_snapshot
CROSS JOIN current_progress
CROSS JOIN proposed_progress;
