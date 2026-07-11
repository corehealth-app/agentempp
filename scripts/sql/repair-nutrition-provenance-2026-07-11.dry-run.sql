-- READ-ONLY. Nao altera dados nem expoe PII.
WITH
params AS (
  SELECT
    '118587e3-e752-4a23-b304-57231d7ef40f'::uuid AS target_user,
    timestamptz '2026-06-11 16:06:00+00' AS provenance_from,
    timestamptz '2026-07-11 16:06:00+00' AS provenance_to
),
target_state AS (
  SELECT u.id, u.country, u.timezone, u.status
  FROM users u, params p
  WHERE u.id = p.target_user
),
grape_ref AS (
  SELECT * FROM food_db WHERE lower(name_pt) = lower('uva roxa')
),
rice_ref AS (
  SELECT * FROM food_db WHERE lower(name_pt) = lower('arroz branco cozido')
),
target_grapes AS (
  SELECT ml.*, (ml.consumed_at AT TIME ZONE ts.timezone)::date AS local_date
  FROM meal_logs ml
  JOIN target_state ts ON ts.id = ml.user_id
  WHERE lower(trim(ml.food_name)) = 'uvas roxas'
),
target_rice AS (
  SELECT ml.*, (ml.consumed_at AT TIME ZONE ts.timezone)::date AS local_date
  FROM meal_logs ml
  JOIN target_state ts ON ts.id = ml.user_id
  WHERE (ml.consumed_at AT TIME ZONE ts.timezone)::date = DATE '2026-07-10'
    AND ml.meal_type = 'almoco'
    AND lower(trim(ml.food_name)) = 'arroz branco cozido'
    AND ml.quantity_g = 100
    AND ml.kcal = 70
),
generic_taco AS (
  SELECT ml.*
  FROM meal_logs ml
  JOIN users u ON u.id = ml.user_id
  CROSS JOIN params p
  WHERE u.status = 'active'
    AND ml.created_at >= p.provenance_from
    AND ml.created_at <= p.provenance_to
    AND ml.source = 'taco'
    AND ml.quantity_g > 0
    AND abs((ml.kcal / ml.quantity_g * 100) - 150) < 0.01
    AND abs((ml.protein_g / ml.quantity_g * 100) - 7) < 0.01
    AND abs((ml.carbs_g / ml.quantity_g * 100) - 18) < 0.01
    AND abs((ml.fat_g / ml.quantity_g * 100) - 5) < 0.01
),
proven_laundered AS (
  SELECT g.*
  FROM generic_taco g
  WHERE EXISTS (
    SELECT 1
    FROM meal_logs e
    WHERE e.user_id = g.user_id
      AND lower(trim(e.food_name)) = lower(trim(g.food_name))
      AND e.created_at < g.created_at
      AND e.source = 'llm_estimate'
      AND e.quantity_g > 0
      AND abs((e.kcal / e.quantity_g * 100) - 150) < 0.01
      AND abs((e.protein_g / e.quantity_g * 100) - 7) < 0.01
      AND abs((e.carbs_g / e.quantity_g * 100) - 18) < 0.01
      AND abs((e.fat_g / e.quantity_g * 100) - 5) < 0.01
  )
),
provenance_relabel AS (
  SELECT p.*
  FROM proven_laundered p
  WHERE p.id NOT IN (SELECT id FROM target_grapes)
),
affected_dates(date) AS (
  VALUES (DATE '2026-06-15'), (DATE '2026-06-16'),
         (DATE '2026-07-08'), (DATE '2026-07-10')
),
proposed_totals AS (
  SELECT
    d.date,
    round(sum(CASE
      WHEN ml.id IN (SELECT id FROM target_grapes)
        THEN ml.quantity_g * gr.kcal_per_100g / 100
      WHEN ml.id IN (SELECT id FROM target_rice)
        THEN ml.quantity_g * rr.kcal_per_100g / 100
      ELSE ml.kcal
    END))::int AS kcal,
    round(sum(CASE
      WHEN ml.id IN (SELECT id FROM target_grapes)
        THEN ml.quantity_g * gr.protein_g / 100
      WHEN ml.id IN (SELECT id FROM target_rice)
        THEN ml.quantity_g * rr.protein_g / 100
      ELSE ml.protein_g
    END), 2) AS protein_g,
    round(sum(CASE
      WHEN ml.id IN (SELECT id FROM target_grapes)
        THEN ml.quantity_g * gr.carbs_g / 100
      WHEN ml.id IN (SELECT id FROM target_rice)
        THEN ml.quantity_g * rr.carbs_g / 100
      ELSE ml.carbs_g
    END), 2) AS carbs_g,
    round(sum(CASE
      WHEN ml.id IN (SELECT id FROM target_grapes)
        THEN ml.quantity_g * gr.fat_g / 100
      WHEN ml.id IN (SELECT id FROM target_rice)
        THEN ml.quantity_g * rr.fat_g / 100
      ELSE ml.fat_g
    END), 2) AS fat_g
  FROM affected_dates d
  CROSS JOIN target_state ts
  CROSS JOIN grape_ref gr
  CROSS JOIN rice_ref rr
  JOIN meal_logs ml
    ON ml.user_id = ts.id
   AND (ml.consumed_at AT TIME ZONE ts.timezone)::date = d.date
  GROUP BY d.date
),
profile AS (
  SELECT CASE
    WHEN up.current_protocol = 'recomposicao' THEN coalesce(up.deficit_level, 500)
    ELSE 0
  END::numeric AS design_deficit
  FROM user_profiles up, params p
  WHERE up.user_id = p.target_user
),
effective_closed AS (
  SELECT
    ds.id,
    coalesce(pt.kcal, ds.calories_consumed) AS calories_consumed,
    ds.calories_target,
    ds.exercise_calories,
    coalesce(pt.kcal, ds.calories_consumed)
      - coalesce(ds.calories_target, 0)
      - coalesce(ds.exercise_calories, 0) AS daily_balance,
    ds.day_status,
    ds.training_done,
    EXISTS (SELECT 1 FROM meal_logs ml WHERE ml.snapshot_id = ds.id) AS has_meal
  FROM daily_snapshots ds
  CROSS JOIN params p
  LEFT JOIN proposed_totals pt ON pt.date = ds.date
  WHERE ds.user_id = p.target_user AND ds.day_closed = true
),
credits AS (
  SELECT CASE
    WHEN NOT (e.has_meal OR coalesce(e.exercise_calories, 0) > 0 OR e.training_done) THEN 0
    WHEN e.day_status = 'user_skipped' THEN pr.design_deficit - e.daily_balance
    WHEN e.calories_target IS NOT NULL
      AND e.calories_target > 0
      AND e.calories_consumed < 0.5 * e.calories_target
      THEN CASE WHEN e.day_status = 'complete' OR e.day_status IS NULL
        THEN pr.design_deficit ELSE 0 END
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
    (SELECT count(*) = 1 AND bool_and(country = 'US')
      AND bool_and(timezone = 'America/New_York') AND bool_and(status = 'active')
      FROM target_state) AS user_ok,
    (SELECT count(*) = 1 AND bool_and(kcal_per_100g = 69)
      AND bool_and(protein_g = 0.7) AND bool_and(carbs_g = 18)
      AND bool_and(fat_g = 0.2) FROM grape_ref) AS grape_ref_ok,
    (SELECT count(*) = 1 AND bool_and(kcal_per_100g = 128)
      AND bool_and(protein_g = 2.5) AND bool_and(carbs_g = 28.1)
      AND bool_and(fat_g = 0.2) FROM rice_ref) AS rice_ref_ok,
    (SELECT count(*) = 5 AND sum(quantity_g) = 406 AND sum(kcal) = 609
      AND count(*) FILTER (WHERE source = 'llm_estimate') = 1
      AND count(*) FILTER (WHERE source = 'taco') = 4
      AND count(*) FILTER (WHERE local_date = DATE '2026-06-15') = 1
      AND count(*) FILTER (WHERE local_date = DATE '2026-06-16') = 1
      AND count(*) FILTER (WHERE local_date = DATE '2026-07-08') = 2
      AND count(*) FILTER (WHERE local_date = DATE '2026-07-10') = 1
      AND bool_and(abs((kcal / quantity_g * 100) - 150) < 0.01)
      AND bool_and(abs((protein_g / quantity_g * 100) - 7) < 0.01)
      AND bool_and(abs((carbs_g / quantity_g * 100) - 18) < 0.01)
      AND bool_and(abs((fat_g / quantity_g * 100) - 5) < 0.01)
      FROM target_grapes) AS grapes_ok,
    (SELECT count(*) = 1 AND bool_and(protein_g = 1.35)
      AND bool_and(carbs_g = 15.08) AND bool_and(fat_g = 0.16)
      FROM target_rice) AS rice_ok,
    (SELECT count(*) = 45 FROM proven_laundered) AS provenance_total_ok,
    (SELECT count(*) = 4 FROM proven_laundered
      WHERE id IN (SELECT id FROM target_grapes)) AS provenance_overlap_ok,
    (SELECT count(*) = 41 FROM provenance_relabel) AS provenance_relabel_ok,
    (SELECT count(*) = 4 AND count(*) FILTER (WHERE day_closed) = 4
      AND count(*) FILTER (WHERE day_status = 'complete') = 4
      FROM daily_snapshots ds, params p
      WHERE ds.user_id = p.target_user
        AND ds.date IN (SELECT date FROM affected_dates)) AS snapshots_ok,
    (SELECT count(*) = 1 AND bool_and(deficit_block = 1270)
      AND bool_and(blocks_completed = 6)
      FROM user_progress up, params p WHERE up.user_id = p.target_user) AS progress_ok
)
SELECT jsonb_build_object(
  'mode', 'dry-run',
  'writes', 0,
  'preconditions_ok',
    c.user_ok AND c.grape_ref_ok AND c.rice_ref_ok AND c.grapes_ok
    AND c.rice_ok AND c.provenance_total_ok AND c.provenance_overlap_ok
    AND c.provenance_relabel_ok AND c.snapshots_ok AND c.progress_ok,
  'nutrition_rows', jsonb_build_object(
    'grapes_to_correct', (SELECT count(*) FROM target_grapes),
    'rice_to_correct', (SELECT count(*) FROM target_rice),
    'provenance_rows_to_relabel', (SELECT count(*) FROM provenance_relabel)
  ),
  'snapshots', (
    SELECT jsonb_agg(jsonb_build_object(
      'date', ds.date,
      'kcal_before', ds.calories_consumed,
      'kcal_after', pt.kcal,
      'protein_after', pt.protein_g,
      'carbs_after', pt.carbs_g,
      'fat_after', pt.fat_g
    ) ORDER BY ds.date)
    FROM daily_snapshots ds
    JOIN proposed_totals pt ON pt.date = ds.date
    CROSS JOIN params p
    WHERE ds.user_id = p.target_user
  ),
  'block', jsonb_build_object(
    'before', (SELECT jsonb_build_object(
      'blocks_completed', blocks_completed, 'deficit_block', deficit_block)
      FROM user_progress up, params p WHERE up.user_id = p.target_user),
    'after', (SELECT jsonb_build_object(
      'blocks_completed', total / 7700, 'deficit_block', total % 7700)
      FROM proposed_progress)
  )
) AS repair_preview
FROM checks c;
