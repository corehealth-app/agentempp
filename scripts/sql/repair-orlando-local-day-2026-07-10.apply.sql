BEGIN;

SELECT pg_advisory_xact_lock(hashtext('repair-orlando-local-day-2026-07-10'));

CREATE TEMP TABLE repair_params ON COMMIT DROP AS
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
  ] AS meal_type_log_ids;

-- Serializa as linhas que podem receber novos agregados durante o reparo.
SELECT 1 FROM users u, repair_params p
WHERE u.id IN (p.local_day_user, p.meal_type_user)
FOR UPDATE OF u;

SELECT 1 FROM daily_snapshots ds, repair_params p
WHERE ds.id IN (p.snapshot_09, p.snapshot_10)
FOR UPDATE OF ds;

SELECT 1 FROM user_progress up, repair_params p
WHERE up.user_id = p.local_day_user
FOR UPDATE OF up;

SELECT 1 FROM meal_logs ml, repair_params p
WHERE ml.id = ANY(p.local_day_log_ids) OR ml.id = ANY(p.meal_type_log_ids)
FOR UPDATE OF ml;

CREATE TEMP TABLE repair_before ON COMMIT DROP AS
SELECT
  (SELECT timezone FROM users u, repair_params p WHERE u.id = p.local_day_user) AS previous_timezone,
  (SELECT calories_consumed FROM daily_snapshots ds, repair_params p WHERE ds.id = p.snapshot_09) AS snapshot_09_kcal,
  (SELECT calories_consumed FROM daily_snapshots ds, repair_params p WHERE ds.id = p.snapshot_10) AS snapshot_10_kcal,
  (SELECT deficit_block FROM user_progress up, repair_params p WHERE up.user_id = p.local_day_user) AS deficit_block,
  (SELECT blocks_completed FROM user_progress up, repair_params p WHERE up.user_id = p.local_day_user) AS blocks_completed;

DO $$
DECLARE
  p repair_params%ROWTYPE;
  local_count int;
  local_kcal numeric;
  meal_count int;
  snack_count int;
  dinner_count int;
  provider_epoch bigint;
BEGIN
  SELECT * INTO p FROM repair_params;

  IF NOT EXISTS (
    SELECT 1 FROM users
    WHERE id = p.local_day_user AND country = 'US' AND country_confirmed = true
      AND timezone = 'America/Sao_Paulo'
  ) THEN
    RAISE EXCEPTION 'precondition failed: local-day user state changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM users
    WHERE id = p.meal_type_user AND country = 'US' AND country_confirmed = true
      AND timezone = 'America/New_York'
  ) THEN
    RAISE EXCEPTION 'precondition failed: meal-type user state changed';
  END IF;

  SELECT count(*), round(sum(kcal)) INTO local_count, local_kcal
  FROM meal_logs
  WHERE id = ANY(p.local_day_log_ids) AND snapshot_id = p.snapshot_10;
  IF local_count <> 2 OR local_kcal <> 73 THEN
    RAISE EXCEPTION 'precondition failed: local-day logs changed (count %, kcal %)', local_count, local_kcal;
  END IF;

  SELECT nullif(m.raw_payload->>'timestamp', '')::bigint INTO provider_epoch
  FROM messages m
  JOIN meal_logs ml ON ml.raw_provider_message_id = m.provider_message_id
  WHERE ml.id = p.local_day_log_ids[1]
  LIMIT 1;
  IF provider_epoch <> 1783653585 THEN
    RAISE EXCEPTION 'precondition failed: provider timestamp changed';
  END IF;

  SELECT count(*),
    count(*) FILTER (WHERE meal_type = 'lanche'),
    count(*) FILTER (WHERE meal_type = 'jantar')
  INTO meal_count, snack_count, dinner_count
  FROM meal_logs
  WHERE id = ANY(p.meal_type_log_ids);
  IF meal_count <> 4 OR snack_count <> 3 OR dinner_count <> 1 THEN
    RAISE EXCEPTION 'precondition failed: meal-type group changed (total %, snack %, dinner %)', meal_count, snack_count, dinner_count;
  END IF;
END $$;

-- Ambos residem em Orlando, FL.
UPDATE users u
SET timezone = 'America/New_York',
    metadata = coalesce(u.metadata, '{}'::jsonb) || jsonb_build_object(
      'residence_city', 'Orlando',
      'residence_region', 'FL',
      'timezone_confirmed', true,
      'timezone_source', 'admin_verified'
    ),
    updated_at = now()
FROM repair_params p
WHERE u.id IN (p.local_day_user, p.meal_type_user);

-- Preserva o instante real da mensagem e move os dois itens para o snapshot local correto.
UPDATE meal_logs ml
SET snapshot_id = p.snapshot_09,
    consumed_at = to_timestamp(1783653585)
FROM repair_params p
WHERE ml.id = ANY(p.local_day_log_ids);

-- Recalcula os dois snapshots diretamente dos logs pela data local de Orlando.
WITH totals AS (
  SELECT
    ds.id,
    round(coalesce(sum(ml.kcal), 0))::int AS kcal,
    round(coalesce(sum(ml.protein_g), 0)::numeric, 2) AS protein_g,
    round(coalesce(sum(ml.carbs_g), 0)::numeric, 2) AS carbs_g,
    round(coalesce(sum(ml.fat_g), 0)::numeric, 2) AS fat_g
  FROM daily_snapshots ds
  CROSS JOIN repair_params p
  LEFT JOIN meal_logs ml
    ON ml.user_id = p.local_day_user
   AND (ml.consumed_at AT TIME ZONE 'America/New_York')::date = ds.date
  WHERE ds.id IN (p.snapshot_09, p.snapshot_10)
  GROUP BY ds.id
)
UPDATE daily_snapshots ds
SET calories_consumed = t.kcal,
    protein_g = t.protein_g,
    carbs_g = t.carbs_g,
    fat_g = t.fat_g,
    updated_at = now()
FROM totals t
WHERE ds.id = t.id;

-- Replay canonico do bloco 7700 para todos os dias fechados.
WITH profile AS (
  SELECT CASE
    WHEN up.current_protocol = 'recomposicao' THEN coalesce(up.deficit_level, 500)
    ELSE 0
  END::numeric AS design_deficit
  FROM user_profiles up, repair_params p
  WHERE up.user_id = p.local_day_user
),
credits AS (
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
      THEN CASE WHEN ds.day_status = 'complete' OR ds.day_status IS NULL THEN pr.design_deficit ELSE 0 END
    WHEN ds.day_status = 'incomplete_no_response' THEN 0
    ELSE pr.design_deficit - ds.daily_balance
  END AS credit
  FROM daily_snapshots ds
  CROSS JOIN repair_params p
  CROSS JOIN profile pr
  WHERE ds.user_id = p.local_day_user AND ds.day_closed = true
),
total AS (
  SELECT greatest(0, round(coalesce(sum(credit), 0)))::int AS value FROM credits
)
UPDATE user_progress up
SET deficit_block = total.value % 7700,
    blocks_completed = total.value / 7700,
    updated_at = now()
FROM total, repair_params p
WHERE up.user_id = p.local_day_user;

-- O hint anterior moveu apenas um item; agora o registro inteiro fica jantar.
UPDATE meal_logs ml
SET meal_type = 'jantar'
FROM repair_params p
WHERE ml.id = ANY(p.meal_type_log_ids);

INSERT INTO product_events (user_id, event, properties)
SELECT
  p.local_day_user,
  'admin.local_day_timezone_repair',
  jsonb_build_object(
    'date_from', '2026-07-10',
    'date_to', '2026-07-09',
    'timezone_from', b.previous_timezone,
    'timezone_to', 'America/New_York',
    'logs_moved', 2,
    'kcal_moved', 73,
    'snapshot_09_before', b.snapshot_09_kcal,
    'snapshot_09_after', (SELECT calories_consumed FROM daily_snapshots WHERE id = p.snapshot_09),
    'snapshot_10_before', b.snapshot_10_kcal,
    'snapshot_10_after', (SELECT calories_consumed FROM daily_snapshots WHERE id = p.snapshot_10),
    'deficit_block_before', b.deficit_block,
    'deficit_block_after', (SELECT deficit_block FROM user_progress WHERE user_id = p.local_day_user),
    'authorization', 'user_approved_2026-07-10'
  )
FROM repair_params p CROSS JOIN repair_before b;

INSERT INTO product_events (user_id, event, properties)
SELECT
  p.meal_type_user,
  'admin.meal_registration_reclassified',
  jsonb_build_object(
    'date', '2026-07-09',
    'from_state', '3_lanche_1_jantar',
    'to', 'jantar',
    'items_moved', 4,
    'kcal_unchanged', (SELECT round(sum(kcal)) FROM meal_logs WHERE id = ANY(p.meal_type_log_ids)),
    'authorization', 'user_approved_2026-07-10'
  )
FROM repair_params p;

SELECT jsonb_build_object(
  'mode', 'applied',
  'local_day', jsonb_build_object(
    'timezone', (SELECT timezone FROM users u, repair_params p WHERE u.id = p.local_day_user),
    'snapshot_09_kcal', (SELECT calories_consumed FROM daily_snapshots ds, repair_params p WHERE ds.id = p.snapshot_09),
    'snapshot_10_kcal', (SELECT calories_consumed FROM daily_snapshots ds, repair_params p WHERE ds.id = p.snapshot_10),
    'deficit_block', (SELECT deficit_block FROM user_progress up, repair_params p WHERE up.user_id = p.local_day_user),
    'blocks_completed', (SELECT blocks_completed FROM user_progress up, repair_params p WHERE up.user_id = p.local_day_user)
  ),
  'meal_type', jsonb_build_object(
    'jantar_items', (SELECT count(*) FROM meal_logs ml, repair_params p WHERE ml.id = ANY(p.meal_type_log_ids) AND ml.meal_type = 'jantar'),
    'kcal', (SELECT round(sum(kcal)) FROM meal_logs ml, repair_params p WHERE ml.id = ANY(p.meal_type_log_ids))
  )
) AS repair_result;

COMMIT;
