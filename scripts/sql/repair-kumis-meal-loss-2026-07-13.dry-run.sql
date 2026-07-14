-- READ-ONLY. Nao altera dados nem expoe PII ou ids de mensagens do provedor.
WITH
params AS (
  SELECT
    '118587e3-e752-4a23-b304-57231d7ef40f'::uuid AS target_user_id,
    'bedf93c8-740f-479e-bb31-f9d87d030892'::uuid AS target_snapshot_id,
    '6639635c-d6a4-4852-90b4-eb0ec403d4b2'::uuid AS lunch_pending_id,
    '74277632-0a95-4f06-b523-53ecc0859c3a'::uuid AS kumis_pending_id,
    'a7afa128-e724-4626-b176-c2ce660afcd0'::uuid AS milk_pending_id,
    '2df3141f-32ff-4ef6-8169-432a1829b770'::uuid AS milk_log_id,
    DATE '2026-07-13' AS target_date
),
expected_lunch (
  food_name, food_db_id, quantity_g, kcal, protein_g, carbs_g, fat_g, source
) AS (
  VALUES
    ('frango em molho cremoso', NULL::integer, 180::numeric, 297::numeric, 50.4::numeric, 0::numeric, 9::numeric, 'llm_estimate'),
    ('arroz branco cozido', 1, 150, 192, 3.75, 42.15, 0.3, 'canonical_exact'),
    ('batata palha', 268, 20, 62.4, 0.6, 8.2, 3, 'canonical_fuzzy'),
    ('mix de folhas para salada', 471, 80, 14.4, 1.2, 2.4, 0.24, 'canonical_fuzzy'),
    ('cenoura ralada crua', NULL::integer, 60, 21, 1.2, 4.2, 0.18, 'llm_estimate'),
    ('tomate cereja', 426, 80, 14.4, 0.72, 3.12, 0.16, 'canonical_exact'),
    ('uva vermelha', 428, 55, 38, 0.39, 9.9, 0.11, 'canonical_fuzzy')
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
lunch_pending AS (
  SELECT pending.*
  FROM public.pending_registrations AS pending
  CROSS JOIN params
  WHERE pending.id = params.lunch_pending_id
),
kumis_pending AS (
  SELECT pending.*
  FROM public.pending_registrations AS pending
  CROSS JOIN params
  WHERE pending.id = params.kumis_pending_id
),
milk_pending AS (
  SELECT pending.*
  FROM public.pending_registrations AS pending
  CROSS JOIN params
  WHERE pending.id = params.milk_pending_id
),
lunch_actual AS (
  SELECT
    item->>'name' AS food_name,
    NULLIF(item->>'food_db_id', '')::integer AS food_db_id,
    (item->>'quantity_g')::numeric AS quantity_g,
    (item->>'kcal')::numeric AS kcal,
    (item->>'protein_g')::numeric AS protein_g,
    (item->>'carbs_g')::numeric AS carbs_g,
    (item->>'fat_g')::numeric AS fat_g,
    item->>'nutrition_source' AS source
  FROM lunch_pending
  CROSS JOIN LATERAL jsonb_array_elements(lunch_pending.proposal->'items') AS item
),
lunch_difference AS (
  (SELECT * FROM expected_lunch EXCEPT SELECT * FROM lunch_actual)
  UNION ALL
  (SELECT * FROM lunch_actual EXCEPT SELECT * FROM expected_lunch)
),
canonical_kumis AS (
  SELECT food.*
  FROM public.food_db AS food
  WHERE food.name_norm = 'iogurte kumis'
    AND food.country_code = 'US'
),
current_raw_totals AS (
  SELECT
    coalesce(sum(meal.kcal), 0)::numeric AS kcal,
    coalesce(sum(meal.protein_g), 0)::numeric AS protein_g,
    coalesce(sum(meal.carbs_g), 0)::numeric AS carbs_g,
    coalesce(sum(meal.fat_g), 0)::numeric AS fat_g,
    count(meal.id)::integer AS item_count
  FROM params
  CROSS JOIN target_user
  LEFT JOIN public.meal_logs AS meal
    ON meal.user_id = params.target_user_id
   AND (meal.consumed_at AT TIME ZONE target_user.timezone)::date = params.target_date
),
current_totals AS (
  SELECT
    round(kcal)::integer AS calories_consumed,
    round(protein_g, 2) AS protein_g,
    round(carbs_g, 2) AS carbs_g,
    round(fat_g, 2) AS fat_g,
    item_count
  FROM current_raw_totals
),
lunch_totals AS (
  SELECT
    sum(kcal)::numeric AS kcal,
    sum(protein_g)::numeric AS protein_g,
    sum(carbs_g)::numeric AS carbs_g,
    sum(fat_g)::numeric AS fat_g,
    count(*)::integer AS item_count
  FROM expected_lunch
),
proposed_snapshot AS (
  SELECT
    round(current_raw.kcal + lunch.kcal + 125)::integer AS calories_consumed,
    round(current_raw.protein_g + lunch.protein_g + 5, 2) AS protein_g,
    round(current_raw.carbs_g + lunch.carbs_g + 14.38, 2) AS carbs_g,
    round(current_raw.fat_g + lunch.fat_g + 5, 2) AS fat_g,
    current_raw.item_count + lunch.item_count + 1 AS item_count
  FROM current_raw_totals AS current_raw
  CROSS JOIN lunch_totals AS lunch
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
    CASE WHEN snapshot.date = params.target_date THEN true ELSE EXISTS (
      SELECT 1 FROM public.meal_logs AS meal WHERE meal.snapshot_id = snapshot.id
    ) END AS has_meal
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
       AND bool_and(kcal_per_100g = 83.33)
       AND bool_and(protein_g = 3.33)
       AND bool_and(carbs_g = 9.58)
       AND bool_and(fat_g = 3.33)
     FROM canonical_kumis) AS canonical_kumis_ok,
    (SELECT count(*) = 1
       AND bool_and(target_snapshot.user_id = params.target_user_id)
       AND bool_and(target_snapshot.date = params.target_date)
       AND bool_and(target_snapshot.calories_consumed = current.calories_consumed)
       AND bool_and(target_snapshot.protein_g = current.protein_g)
       AND bool_and(target_snapshot.carbs_g = current.carbs_g)
       AND bool_and(target_snapshot.fat_g = current.fat_g)
     FROM target_snapshot
     CROSS JOIN params
     CROSS JOIN current_totals AS current) AS snapshot_matches_logs,
    (SELECT count(*) = 1
       AND bool_and(lunch_pending.user_id = params.target_user_id)
       AND bool_and(lunch_pending.status = 'confirmed')
       AND bool_and(lunch_pending.proposal->>'kind' = 'meal')
       AND bool_and(lunch_pending.proposal->>'mealType' = 'almoco')
       AND bool_and(lunch_pending.proposal->>'source_local_date' = params.target_date::text)
       AND bool_and(lunch_pending.proposal->>'source_timezone' = 'America/New_York')
       AND bool_and(jsonb_array_length(lunch_pending.proposal->'items') = 7)
       AND bool_and((lunch_pending.proposal->'totals'->>'kcal')::numeric = 639.2)
     FROM lunch_pending CROSS JOIN params) AS lunch_pending_ok,
    NOT EXISTS (SELECT 1 FROM lunch_difference) AS lunch_items_exact,
    (SELECT count(*) = 1
       AND bool_and(kumis_pending.user_id = params.target_user_id)
       AND bool_and(kumis_pending.status = 'confirmed')
       AND bool_and(kumis_pending.proposal->>'kind' = 'meal')
       AND bool_and(kumis_pending.proposal->>'mealType' = 'lanche')
       AND bool_and(kumis_pending.proposal->>'source_local_date' = params.target_date::text)
       AND bool_and(kumis_pending.proposal->>'source_timezone' = 'America/New_York')
       AND bool_and(jsonb_array_length(kumis_pending.proposal->'items') = 1)
       AND bool_and(kumis_pending.proposal->'items'->0->>'name' = 'iogurte kumis')
       AND bool_and((kumis_pending.proposal->'items'->0->>'quantity_g')::numeric = 150)
       AND bool_and((kumis_pending.proposal->'items'->0->>'food_db_id')::integer = 259)
       AND bool_and((kumis_pending.proposal->'items'->0->>'kcal')::numeric = 145.5)
       AND bool_and((kumis_pending.proposal->'items'->0->>'protein_g')::numeric = 13.5)
       AND bool_and((kumis_pending.proposal->'items'->0->>'carbs_g')::numeric = 6)
       AND bool_and((kumis_pending.proposal->'items'->0->>'fat_g')::numeric = 7.5)
     FROM kumis_pending CROSS JOIN params) AS kumis_pending_original_ok,
    (SELECT count(*) = 1
       AND bool_and(milk_pending.user_id = params.target_user_id)
       AND bool_and(milk_pending.status = 'confirmed')
       AND bool_and(milk_pending.proposal->>'mealType' = 'lanche')
       AND bool_and(jsonb_array_length(milk_pending.proposal->'items') = 1)
       AND bool_and(milk_pending.proposal->'items'->0->>'name' = 'leite em pó desnatado')
       AND bool_and((milk_pending.proposal->'items'->0->>'quantity_g')::numeric = 30)
       AND bool_and((milk_pending.proposal->'items'->0->>'user_kcal')::numeric = 85)
     FROM milk_pending CROSS JOIN params) AS milk_pending_ok,
    (SELECT count(*) = 1
       AND bool_and(meal.user_id = params.target_user_id)
       AND bool_and(meal.snapshot_id = params.target_snapshot_id)
       AND bool_and(meal.food_name = 'leite em pó desnatado')
       AND bool_and(meal.quantity_g = 30)
       AND bool_and(meal.kcal = 85)
       AND bool_and(meal.protein_g = 8.26)
       AND bool_and(meal.carbs_g = 12.28)
       AND bool_and(meal.fat_g = 0.24)
       AND bool_and(meal.meal_type = 'lanche')
       AND bool_and(meal.raw_provider_message_id = milk_pending.proposal->>'source_provider_message_id')
     FROM public.meal_logs AS meal
     CROSS JOIN params
     CROSS JOIN milk_pending
     WHERE meal.id = params.milk_log_id) AS milk_log_ok,
    NOT EXISTS (
      SELECT 1
      FROM public.meal_logs AS meal
      CROSS JOIN params
      WHERE meal.user_id = params.target_user_id
        AND meal.raw_provider_message_id IN (
          (SELECT proposal->>'source_provider_message_id' FROM lunch_pending),
          (SELECT proposal->>'source_provider_message_id' FROM kumis_pending)
        )
    ) AS missing_logs_still_absent,
    NOT EXISTS (
      SELECT 1
      FROM public.product_events AS event
      CROSS JOIN params
      WHERE event.user_id = params.target_user_id
        AND event.event = 'admin.kumis_meal_loss_repaired'
        AND event.properties->>'repair_id' = 'kumis-meal-loss-2026-07-13'
    ) AS repair_not_applied,
    (SELECT count(*) = 1
       AND bool_and(progress.blocks_completed = current_progress.total / 7700)
       AND bool_and(progress.deficit_block = current_progress.total % 7700)
     FROM public.user_progress AS progress
     CROSS JOIN params
     CROSS JOIN current_progress
     WHERE progress.user_id = params.target_user_id) AS progress_matches_replay
)
SELECT jsonb_build_object(
  'mode', 'dry-run',
  'writes', 0,
  'preconditions_ok',
    checks.user_ok
    AND checks.canonical_kumis_ok
    AND checks.snapshot_matches_logs
    AND checks.lunch_pending_ok
    AND checks.lunch_items_exact
    AND checks.kumis_pending_original_ok
    AND checks.milk_pending_ok
    AND checks.milk_log_ok
    AND checks.missing_logs_still_absent
    AND checks.repair_not_applied
    AND checks.progress_matches_replay,
  'checks', to_jsonb(checks),
  'target', jsonb_build_object(
    'snapshot_id', params.target_snapshot_id,
    'date', params.target_date,
    'lunch_pending_id', params.lunch_pending_id,
    'kumis_pending_id', params.kumis_pending_id,
    'milk_pending_id', params.milk_pending_id
  ),
  'restore', jsonb_build_object(
    'lunch_items', lunch.item_count,
    'lunch_kcal', lunch.kcal,
    'kumis_items', 1,
    'kumis_kcal', 125,
    'total_items', lunch.item_count + 1,
    'total_kcal', lunch.kcal + 125
  ),
  'snapshot', jsonb_build_object(
    'before', to_jsonb(current),
    'after', to_jsonb(proposed)
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
CROSS JOIN current_totals AS current
CROSS JOIN proposed_snapshot AS proposed
CROSS JOIN lunch_totals AS lunch
CROSS JOIN proposed_progress;
