BEGIN;

SELECT pg_advisory_xact_lock(hashtext('repair-nutrition-provenance-2026-07-11'));

CREATE TEMP TABLE repair_params ON COMMIT DROP AS
SELECT
  '118587e3-e752-4a23-b304-57231d7ef40f'::uuid AS target_user,
  timestamptz '2026-06-11 16:06:00+00' AS provenance_from,
  timestamptz '2026-07-11 16:06:00+00' AS provenance_to;

CREATE TEMP TABLE repair_target_grapes ON COMMIT DROP AS
SELECT ml.id
FROM meal_logs ml, repair_params p
WHERE ml.user_id = p.target_user
  AND lower(trim(ml.food_name)) = 'uvas roxas';

CREATE TEMP TABLE repair_target_rice ON COMMIT DROP AS
SELECT ml.id
FROM meal_logs ml
JOIN users u ON u.id = ml.user_id
CROSS JOIN repair_params p
WHERE ml.user_id = p.target_user
  AND (ml.consumed_at AT TIME ZONE u.timezone)::date = DATE '2026-07-10'
  AND ml.meal_type = 'almoco'
  AND lower(trim(ml.food_name)) = 'arroz branco cozido'
  AND ml.quantity_g = 100
  AND ml.kcal = 70;

CREATE TEMP TABLE repair_provenance_candidates ON COMMIT DROP AS
WITH generic_taco AS (
  SELECT ml.*
  FROM meal_logs ml
  JOIN users u ON u.id = ml.user_id
  CROSS JOIN repair_params p
  WHERE u.status = 'active'
    AND ml.created_at >= p.provenance_from
    AND ml.created_at <= p.provenance_to
    AND ml.source = 'taco'
    AND ml.quantity_g > 0
    AND abs((ml.kcal / ml.quantity_g * 100) - 150) < 0.01
    AND abs((ml.protein_g / ml.quantity_g * 100) - 7) < 0.01
    AND abs((ml.carbs_g / ml.quantity_g * 100) - 18) < 0.01
    AND abs((ml.fat_g / ml.quantity_g * 100) - 5) < 0.01
)
SELECT g.id, g.user_id
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
);

CREATE TEMP TABLE repair_provenance_relabel ON COMMIT DROP AS
SELECT p.id, p.user_id
FROM repair_provenance_candidates p
WHERE p.id NOT IN (SELECT id FROM repair_target_grapes);

CREATE TEMP TABLE repair_affected_dates (date date PRIMARY KEY) ON COMMIT DROP;
INSERT INTO repair_affected_dates(date)
VALUES (DATE '2026-06-15'), (DATE '2026-06-16'),
       (DATE '2026-07-08'), (DATE '2026-07-10');

-- Serializa todas as linhas que serao lidas ou alteradas.
DO $$
BEGIN
  PERFORM 1 FROM users
  WHERE id IN (
    SELECT target_user FROM repair_params
    UNION SELECT user_id FROM repair_provenance_relabel
  )
  FOR UPDATE;

  PERFORM 1 FROM user_profiles up, repair_params p
  WHERE up.user_id = p.target_user
  FOR UPDATE OF up;

  PERFORM 1 FROM user_progress up, repair_params p
  WHERE up.user_id = p.target_user
  FOR UPDATE OF up;

  PERFORM 1 FROM daily_snapshots ds, repair_params p
  WHERE ds.user_id = p.target_user
    AND (ds.day_closed = true OR ds.date IN (SELECT date FROM repair_affected_dates))
  FOR UPDATE OF ds;

  PERFORM 1 FROM meal_logs ml
  WHERE ml.id IN (
    SELECT id FROM repair_target_grapes
    UNION SELECT id FROM repair_target_rice
    UNION SELECT id FROM repair_provenance_relabel
  )
  FOR UPDATE OF ml;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM users u, repair_params p
    WHERE u.id = p.target_user AND u.country = 'US'
      AND u.timezone = 'America/New_York' AND u.status = 'active'
  ) THEN
    RAISE EXCEPTION 'precondition failed: target user state changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM user_profiles up, repair_params p
    WHERE up.user_id = p.target_user
      AND up.current_protocol = 'recomposicao' AND up.deficit_level = 500
  ) THEN
    RAISE EXCEPTION 'precondition failed: profile state changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM food_db
    WHERE lower(name_pt) = lower('uva roxa')
      AND kcal_per_100g = 69 AND protein_g = 0.7
      AND carbs_g = 18 AND fat_g = 0.2
  ) OR (SELECT count(*) FROM food_db WHERE lower(name_pt) = lower('uva roxa')) <> 1 THEN
    RAISE EXCEPTION 'precondition failed: canonical grape reference changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM food_db
    WHERE lower(name_pt) = lower('arroz branco cozido')
      AND kcal_per_100g = 128 AND protein_g = 2.5
      AND carbs_g = 28.1 AND fat_g = 0.2
  ) OR (SELECT count(*) FROM food_db WHERE lower(name_pt) = lower('arroz branco cozido')) <> 1 THEN
    RAISE EXCEPTION 'precondition failed: canonical rice reference changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM meal_logs ml
    JOIN repair_target_grapes t ON t.id = ml.id
    JOIN users u ON u.id = ml.user_id
    HAVING count(*) = 5
      AND sum(ml.quantity_g) = 406
      AND sum(ml.kcal) = 609
      AND count(*) FILTER (WHERE ml.source = 'llm_estimate') = 1
      AND count(*) FILTER (WHERE ml.source = 'taco') = 4
      AND count(*) FILTER (
        WHERE (ml.consumed_at AT TIME ZONE u.timezone)::date = DATE '2026-06-15'
      ) = 1
      AND count(*) FILTER (
        WHERE (ml.consumed_at AT TIME ZONE u.timezone)::date = DATE '2026-06-16'
      ) = 1
      AND count(*) FILTER (
        WHERE (ml.consumed_at AT TIME ZONE u.timezone)::date = DATE '2026-07-08'
      ) = 2
      AND count(*) FILTER (
        WHERE (ml.consumed_at AT TIME ZONE u.timezone)::date = DATE '2026-07-10'
      ) = 1
      AND bool_and(abs((ml.kcal / ml.quantity_g * 100) - 150) < 0.01)
      AND bool_and(abs((ml.protein_g / ml.quantity_g * 100) - 7) < 0.01)
      AND bool_and(abs((ml.carbs_g / ml.quantity_g * 100) - 18) < 0.01)
      AND bool_and(abs((ml.fat_g / ml.quantity_g * 100) - 5) < 0.01)
  ) THEN
    RAISE EXCEPTION 'precondition failed: target grape rows changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM meal_logs ml JOIN repair_target_rice t ON t.id = ml.id
    HAVING count(*) = 1 AND bool_and(ml.quantity_g = 100)
      AND bool_and(ml.kcal = 70) AND bool_and(ml.protein_g = 1.35)
      AND bool_and(ml.carbs_g = 15.08) AND bool_and(ml.fat_g = 0.16)
      AND bool_and(ml.source = 'taco')
  ) THEN
    RAISE EXCEPTION 'precondition failed: target rice row changed';
  END IF;

  IF (SELECT count(*) FROM repair_provenance_candidates) <> 45
    OR (SELECT count(*) FROM repair_provenance_candidates
        WHERE id IN (SELECT id FROM repair_target_grapes)) <> 4
    OR (SELECT count(*) FROM repair_provenance_relabel) <> 41
  THEN
    RAISE EXCEPTION 'precondition failed: provenance candidate set changed';
  END IF;

  IF EXISTS (
    SELECT 1 FROM meal_logs ml JOIN repair_provenance_relabel r ON r.id = ml.id
    WHERE ml.source <> 'taco'
  ) THEN
    RAISE EXCEPTION 'precondition failed: provenance row source changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM daily_snapshots ds, repair_params p
    WHERE ds.user_id = p.target_user
      AND ds.date = DATE '2026-06-15' AND ds.calories_consumed = 1857
      AND ds.day_closed = true AND ds.day_status = 'complete'
  ) OR NOT EXISTS (
    SELECT 1 FROM daily_snapshots ds, repair_params p
    WHERE ds.user_id = p.target_user
      AND ds.date = DATE '2026-06-16' AND ds.calories_consumed = 1624
      AND ds.day_closed = true AND ds.day_status = 'complete'
  ) OR NOT EXISTS (
    SELECT 1 FROM daily_snapshots ds, repair_params p
    WHERE ds.user_id = p.target_user
      AND ds.date = DATE '2026-07-08' AND ds.calories_consumed = 1994
      AND ds.day_closed = true AND ds.day_status = 'complete'
  ) OR NOT EXISTS (
    SELECT 1 FROM daily_snapshots ds, repair_params p
    WHERE ds.user_id = p.target_user
      AND ds.date = DATE '2026-07-10' AND ds.calories_consumed = 1685
      AND ds.day_closed = true AND ds.day_status = 'complete'
  ) THEN
    RAISE EXCEPTION 'precondition failed: affected snapshots changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM user_progress up, repair_params p
    WHERE up.user_id = p.target_user
      AND up.blocks_completed = 6 AND up.deficit_block = 1270
  ) THEN
    RAISE EXCEPTION 'precondition failed: block progress changed';
  END IF;
END $$;

CREATE TEMP TABLE repair_before ON COMMIT DROP AS
SELECT
  (SELECT jsonb_agg(jsonb_build_object(
    'date', ds.date,
    'kcal', ds.calories_consumed,
    'protein_g', ds.protein_g,
    'carbs_g', ds.carbs_g,
    'fat_g', ds.fat_g
  ) ORDER BY ds.date)
  FROM daily_snapshots ds, repair_params p
  WHERE ds.user_id = p.target_user
    AND ds.date IN (SELECT date FROM repair_affected_dates)) AS snapshots,
  (SELECT deficit_block FROM user_progress up, repair_params p
   WHERE up.user_id = p.target_user) AS deficit_block,
  (SELECT blocks_completed FROM user_progress up, repair_params p
   WHERE up.user_id = p.target_user) AS blocks_completed;

UPDATE meal_logs ml
SET source = 'history_estimate'
FROM repair_provenance_relabel r
WHERE ml.id = r.id;

UPDATE meal_logs ml
SET kcal = round(ml.quantity_g * f.kcal_per_100g / 100, 2),
    protein_g = round(ml.quantity_g * f.protein_g / 100, 2),
    carbs_g = round(ml.quantity_g * f.carbs_g / 100, 2),
    fat_g = round(ml.quantity_g * f.fat_g / 100, 2),
    source = 'taco'
FROM repair_target_grapes t
CROSS JOIN food_db f
WHERE ml.id = t.id AND lower(f.name_pt) = lower('uva roxa');

UPDATE meal_logs ml
SET kcal = round(ml.quantity_g * f.kcal_per_100g / 100, 2),
    protein_g = round(ml.quantity_g * f.protein_g / 100, 2),
    carbs_g = round(ml.quantity_g * f.carbs_g / 100, 2),
    fat_g = round(ml.quantity_g * f.fat_g / 100, 2),
    source = 'taco'
FROM repair_target_rice t
CROSS JOIN food_db f
WHERE ml.id = t.id AND lower(f.name_pt) = lower('arroz branco cozido');

-- Recalcula pelos instantes locais, incluindo logs legados com snapshot_id nulo.
WITH target_state AS (
  SELECT u.id, u.timezone FROM users u, repair_params p WHERE u.id = p.target_user
), totals AS (
  SELECT
    d.date,
    round(coalesce(sum(ml.kcal), 0))::int AS kcal,
    round(coalesce(sum(ml.protein_g), 0), 2) AS protein_g,
    round(coalesce(sum(ml.carbs_g), 0), 2) AS carbs_g,
    round(coalesce(sum(ml.fat_g), 0), 2) AS fat_g
  FROM repair_affected_dates d
  CROSS JOIN target_state ts
  LEFT JOIN meal_logs ml
    ON ml.user_id = ts.id
   AND (ml.consumed_at AT TIME ZONE ts.timezone)::date = d.date
  GROUP BY d.date
)
UPDATE daily_snapshots ds
SET calories_consumed = t.kcal,
    protein_g = t.protein_g,
    carbs_g = t.carbs_g,
    fat_g = t.fat_g,
    updated_at = now()
FROM totals t, repair_params p
WHERE ds.user_id = p.target_user AND ds.date = t.date;

-- Replay canonico do bloco 7700 para todos os dias fechados do usuario afetado.
WITH profile AS (
  SELECT CASE
    WHEN up.current_protocol = 'recomposicao' THEN coalesce(up.deficit_level, 500)
    ELSE 0
  END::numeric AS design_deficit
  FROM user_profiles up, repair_params p
  WHERE up.user_id = p.target_user
), credits AS (
  SELECT CASE
    WHEN NOT (
      EXISTS (SELECT 1 FROM meal_logs ml WHERE ml.snapshot_id = ds.id)
      OR coalesce(ds.exercise_calories, 0) > 0
      OR ds.training_done
    ) THEN 0
    WHEN ds.day_status = 'user_skipped' THEN pr.design_deficit - ds.daily_balance
    WHEN ds.calories_target IS NOT NULL
      AND ds.calories_target > 0
      AND ds.calories_consumed < 0.5 * ds.calories_target
      THEN CASE WHEN ds.day_status = 'complete' OR ds.day_status IS NULL
        THEN pr.design_deficit ELSE 0 END
    WHEN ds.day_status = 'incomplete_no_response' THEN 0
    ELSE pr.design_deficit - ds.daily_balance
  END AS credit
  FROM daily_snapshots ds
  CROSS JOIN repair_params p
  CROSS JOIN profile pr
  WHERE ds.user_id = p.target_user AND ds.day_closed = true
), total AS (
  SELECT greatest(0, round(coalesce(sum(credit), 0)))::int AS value FROM credits
)
UPDATE user_progress up
SET deficit_block = total.value % 7700,
    blocks_completed = (total.value / 7700)::smallint,
    updated_at = now()
FROM total, repair_params p
WHERE up.user_id = p.target_user;

INSERT INTO product_events (user_id, event, properties)
SELECT
  p.target_user,
  'admin.nutrition_incident_repaired',
  jsonb_build_object(
    'incident_date', '2026-07-10',
    'grape_rows_corrected', 5,
    'rice_rows_corrected', 1,
    'affected_dates', ARRAY['2026-06-15', '2026-06-16', '2026-07-08', '2026-07-10'],
    'snapshots_before', b.snapshots,
    'deficit_block_before', b.deficit_block,
    'blocks_completed_before', b.blocks_completed,
    'deficit_block_after', (SELECT deficit_block FROM user_progress WHERE user_id = p.target_user),
    'blocks_completed_after', (SELECT blocks_completed FROM user_progress WHERE user_id = p.target_user),
    'authorization', 'user_requested_full_correction_2026-07-11'
  )
FROM repair_params p CROSS JOIN repair_before b;

INSERT INTO product_events (user_id, event, properties)
SELECT
  r.user_id,
  'admin.nutrition_provenance_repaired',
  jsonb_build_object(
    'rows_relabelled', count(*),
    'source_from', 'taco',
    'source_to', 'history_estimate',
    'cutoff', '2026-07-11T16:06:00Z',
    'authorization', 'user_requested_full_correction_2026-07-11'
  )
FROM repair_provenance_relabel r
GROUP BY r.user_id;

DO $$
BEGIN
  IF (SELECT count(*) FROM meal_logs ml JOIN repair_target_grapes t ON t.id = ml.id
      WHERE ml.source = 'taco'
        AND abs((ml.kcal / ml.quantity_g * 100) - 69) < 0.01
        AND abs((ml.protein_g / ml.quantity_g * 100) - 0.7) < 0.01
        AND abs((ml.carbs_g / ml.quantity_g * 100) - 18) < 0.01
        AND abs((ml.fat_g / ml.quantity_g * 100) - 0.2) < 0.01) <> 5
  THEN
    RAISE EXCEPTION 'postcondition failed: grape repair mismatch';
  END IF;

  IF (SELECT count(*) FROM meal_logs ml JOIN repair_target_rice t ON t.id = ml.id
      WHERE ml.source = 'taco' AND ml.kcal = 128 AND ml.protein_g = 2.5
        AND ml.carbs_g = 28.1 AND ml.fat_g = 0.2) <> 1
  THEN
    RAISE EXCEPTION 'postcondition failed: rice repair mismatch';
  END IF;

  IF (SELECT count(*) FROM meal_logs ml JOIN repair_provenance_relabel r ON r.id = ml.id
      WHERE ml.source = 'history_estimate') <> 41
  THEN
    RAISE EXCEPTION 'postcondition failed: provenance relabel mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM daily_snapshots ds, repair_params p
    WHERE ds.user_id = p.target_user AND ds.date = DATE '2026-06-15'
      AND ds.calories_consumed = 1792 AND ds.protein_g = 139.41
      AND ds.carbs_g = 209.41 AND ds.fat_g = 42.19
  ) OR NOT EXISTS (
    SELECT 1 FROM daily_snapshots ds, repair_params p
    WHERE ds.user_id = p.target_user AND ds.date = DATE '2026-06-16'
      AND ds.calories_consumed = 1559 AND ds.protein_g = 106.91
      AND ds.carbs_g = 180.44 AND ds.fat_g = 42.60
  ) OR NOT EXISTS (
    SELECT 1 FROM daily_snapshots ds, repair_params p
    WHERE ds.user_id = p.target_user AND ds.date = DATE '2026-07-08'
      AND ds.calories_consumed = 1851 AND ds.protein_g = 146.56
      AND ds.carbs_g = 192.90 AND ds.fat_g = 54.43
  ) OR NOT EXISTS (
    SELECT 1 FROM daily_snapshots ds, repair_params p
    WHERE ds.user_id = p.target_user AND ds.date = DATE '2026-07-10'
      AND ds.calories_consumed = 1686 AND ds.protein_g = 118.10
      AND ds.carbs_g = 170.87 AND ds.fat_g = 57.00
  ) THEN
    RAISE EXCEPTION 'postcondition failed: snapshot totals mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM user_progress up, repair_params p
    WHERE up.user_id = p.target_user
      AND up.blocks_completed = 6 AND up.deficit_block = 1542
  ) THEN
    RAISE EXCEPTION 'postcondition failed: block replay mismatch';
  END IF;
END $$;

SELECT jsonb_build_object(
  'mode', 'applied',
  'nutrition_rows', jsonb_build_object(
    'grapes_corrected', (SELECT count(*) FROM repair_target_grapes),
    'rice_corrected', (SELECT count(*) FROM repair_target_rice),
    'provenance_relabelled', (SELECT count(*) FROM repair_provenance_relabel)
  ),
  'snapshots', (
    SELECT jsonb_agg(jsonb_build_object(
      'date', ds.date,
      'kcal', ds.calories_consumed,
      'protein_g', ds.protein_g,
      'carbs_g', ds.carbs_g,
      'fat_g', ds.fat_g
    ) ORDER BY ds.date)
    FROM daily_snapshots ds, repair_params p
    WHERE ds.user_id = p.target_user
      AND ds.date IN (SELECT date FROM repair_affected_dates)
  ),
  'block', (
    SELECT jsonb_build_object(
      'blocks_completed', up.blocks_completed,
      'deficit_block', up.deficit_block
    )
    FROM user_progress up, repair_params p WHERE up.user_id = p.target_user
  )
) AS repair_result;

COMMIT;
