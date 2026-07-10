-- READ-ONLY. Nao altera dados.
WITH
params AS (
  SELECT
    'fb0645a9-75b0-4902-a4c4-431cc6e30e98'::uuid AS local_day_user,
    '118587e3-e752-4a23-b304-57231d7ef40f'::uuid AS meal_type_user,
    'de5159e0-99a3-4f25-8c29-85941a8d5c98'::uuid AS snapshot_09,
    '01b4f28e-c175-4d2d-9fed-5933de5799d0'::uuid AS snapshot_10,
    ARRAY[
      '8f10d8f4-bc31-441e-9ee4-27df02c8b1da'::uuid,
      '91f7461a-902e-4de4-8498-a5db49347608'::uuid
    ] AS local_day_log_ids,
    ARRAY[
      '0bd66c87-8f93-4197-889e-ab87b0432907'::uuid,
      '6103c216-31b1-4b54-95c4-f2035c1099eb'::uuid,
      '9b51dcd2-a5ce-47b6-b65a-b0ea3a993e38'::uuid,
      'e7988306-66b2-45b7-b9a0-53202dc472a1'::uuid
    ] AS meal_type_log_ids
),
local_totals AS (
  SELECT
    (ml.consumed_at AT TIME ZONE 'America/New_York')::date AS local_date,
    round(sum(ml.kcal))::int AS kcal,
    round(sum(ml.protein_g)::numeric, 2) AS protein_g,
    round(sum(ml.carbs_g)::numeric, 2) AS carbs_g,
    round(sum(ml.fat_g)::numeric, 2) AS fat_g,
    count(*)::int AS item_count
  FROM meal_logs ml, params p
  WHERE ml.user_id = p.local_day_user
    AND (ml.consumed_at AT TIME ZONE 'America/New_York')::date IN (DATE '2026-07-09', DATE '2026-07-10')
  GROUP BY 1
),
profile AS (
  SELECT CASE
    WHEN up.current_protocol = 'recomposicao' THEN coalesce(up.deficit_level, 500)
    ELSE 0
  END::numeric AS design_deficit
  FROM user_profiles up, params p
  WHERE up.user_id = p.local_day_user
),
effective_closed AS (
  SELECT
    ds.id,
    CASE WHEN ds.id = p.snapshot_09 THEN t.kcal ELSE ds.calories_consumed END AS calories_consumed,
    ds.calories_target,
    ds.exercise_calories,
    CASE
      WHEN ds.id = p.snapshot_09
      THEN t.kcal - coalesce(ds.calories_target, 0) - coalesce(ds.exercise_calories, 0)
      ELSE ds.daily_balance
    END AS daily_balance,
    ds.day_status,
    ds.training_done,
    EXISTS (SELECT 1 FROM meal_logs ml WHERE ml.snapshot_id = ds.id) AS has_meal
  FROM daily_snapshots ds
  CROSS JOIN params p
  LEFT JOIN local_totals t ON t.local_date = DATE '2026-07-09'
  WHERE ds.user_id = p.local_day_user AND ds.day_closed = true
),
credits AS (
  SELECT CASE
    WHEN NOT (e.has_meal OR coalesce(e.exercise_calories, 0) > 0 OR e.training_done) THEN 0
    WHEN e.day_status = 'user_skipped' THEN pr.design_deficit - e.daily_balance
    WHEN e.calories_target IS NOT NULL
      AND e.calories_target > 0
      AND e.calories_consumed < 0.5 * e.calories_target
      THEN CASE WHEN e.day_status = 'complete' OR e.day_status IS NULL THEN pr.design_deficit ELSE 0 END
    WHEN e.day_status = 'incomplete_no_response' THEN 0
    ELSE pr.design_deficit - e.daily_balance
  END AS credit
  FROM effective_closed e CROSS JOIN profile pr
),
proposed_progress AS (
  SELECT greatest(0, round(coalesce(sum(credit), 0)))::int AS total FROM credits
),
checks AS (
  SELECT
    (SELECT count(*) = 1 FROM users u WHERE u.id = p.local_day_user AND u.country = 'US' AND u.timezone = 'America/Sao_Paulo') AS local_user_ok,
    (SELECT count(*) = 2 AND round(sum(kcal)) = 73 FROM meal_logs ml WHERE ml.id = ANY(p.local_day_log_ids) AND ml.snapshot_id = p.snapshot_10) AS local_logs_ok,
    (SELECT count(*) = 4 AND count(*) FILTER (WHERE meal_type = 'lanche') = 3 AND count(*) FILTER (WHERE meal_type = 'jantar') = 1 FROM meal_logs ml WHERE ml.id = ANY(p.meal_type_log_ids)) AS meal_type_logs_ok
  FROM params p
)
SELECT jsonb_build_object(
  'mode', 'dry-run',
  'writes', 0,
  'preconditions_ok', c.local_user_ok AND c.local_logs_ok AND c.meal_type_logs_ok,
  'local_day', jsonb_build_object(
    'logs_to_move', 2,
    'kcal_to_move', 73,
    'snapshot_2026_07_09_before', (SELECT calories_consumed FROM daily_snapshots ds, params p WHERE ds.id = p.snapshot_09),
    'snapshot_2026_07_09_after', (SELECT kcal FROM local_totals WHERE local_date = DATE '2026-07-09'),
    'snapshot_2026_07_10_before', (SELECT calories_consumed FROM daily_snapshots ds, params p WHERE ds.id = p.snapshot_10),
    'snapshot_2026_07_10_after', (SELECT kcal FROM local_totals WHERE local_date = DATE '2026-07-10'),
    'deficit_block_before', (SELECT deficit_block FROM user_progress up, params p WHERE up.user_id = p.local_day_user),
    'deficit_block_after', (SELECT total % 7700 FROM proposed_progress),
    'blocks_completed_after', (SELECT total / 7700 FROM proposed_progress)
  ),
  'meal_type', jsonb_build_object(
    'items_to_reclassify', 4,
    'target', 'jantar',
    'kcal_unchanged', (SELECT round(sum(kcal)) FROM meal_logs ml, params p WHERE ml.id = ANY(p.meal_type_log_ids))
  )
) AS repair_preview
FROM checks c;
