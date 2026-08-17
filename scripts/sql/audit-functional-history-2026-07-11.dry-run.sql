-- READ-ONLY. Produces an audit plan for active users without exposing PII.
-- This file contains no mutating statement and intentionally has no apply pair.
WITH
active_users AS (
  SELECT id, coalesce(timezone, 'America/Sao_Paulo') AS timezone
  FROM public.users
  WHERE status = 'active'
),
food_reference_counts AS (
  SELECT
    name_norm,
    count(*) AS refs,
    min(name_pt) AS name_pt,
    min(kcal_per_100g) AS kcal_per_100g,
    min(protein_g) AS protein_g,
    min(carbs_g) AS carbs_g,
    min(fat_g) AS fat_g
  FROM public.food_db
  GROUP BY name_norm
),
unique_food_refs AS (
  SELECT *
  FROM food_reference_counts
  WHERE refs = 1
),
targeted_canonical_repairs AS (
  SELECT
    ml.id AS log_id,
    ml.user_id,
    (ml.consumed_at AT TIME ZONE au.timezone)::date AS local_date,
    ml.food_name,
    ml.quantity_g,
    ml.kcal AS kcal_before,
    ml.protein_g AS protein_before,
    ml.carbs_g AS carbs_before,
    ml.fat_g AS fat_before,
    round(ml.quantity_g * ref.kcal_per_100g / 100, 2) AS kcal_after,
    round(ml.quantity_g * ref.protein_g / 100, 2) AS protein_after,
    round(ml.quantity_g * ref.carbs_g / 100, 2) AS carbs_after,
    round(ml.quantity_g * ref.fat_g / 100, 2) AS fat_after,
    CASE
      WHEN ref.name_norm = 'goiaba' THEN 'goiaba_canonical'
      ELSE 'explicit_powdered_milk_canonical'
    END AS reason,
    10 AS priority
  FROM public.meal_logs ml
  JOIN active_users au ON au.id = ml.user_id
  JOIN unique_food_refs ref
    ON ref.name_norm = lower(public.f_unaccent(trim(ml.food_name)))
  WHERE ml.source = 'taco'
    AND ml.quantity_g > 0
    AND (
      ref.name_norm = 'goiaba'
      OR ref.name_norm IN ('leite em po integral', 'leite em po desnatado')
    )
    AND (
      abs(coalesce(ml.kcal, 0) - ml.quantity_g * ref.kcal_per_100g / 100) > 1
      OR abs(coalesce(ml.protein_g, 0) - ml.quantity_g * ref.protein_g / 100) > 0.5
      OR abs(coalesce(ml.carbs_g, 0) - ml.quantity_g * ref.carbs_g / 100) > 0.5
      OR abs(coalesce(ml.fat_g, 0) - ml.quantity_g * ref.fat_g / 100) > 0.5
    )
),
override_items AS (
  SELECT
    pr.id AS pending_id,
    pr.user_id,
    pr.status,
    pr.created_at,
    pr.resolved_at,
    item.ordinality AS item_ordinal,
    item.value AS item,
    lower(public.f_unaccent(trim(item.value->>'name'))) AS name_norm,
    (item.value->>'quantity_g')::numeric AS quantity_g,
    (item.value->>'kcal')::numeric AS kcal,
    (item.value->>'user_kcal')::numeric AS user_kcal
  FROM public.pending_registrations pr
  JOIN active_users au ON au.id = pr.user_id
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(pr.proposal->'items', '[]'::jsonb))
    WITH ORDINALITY AS item(value, ordinality)
  WHERE pr.created_at >= timestamptz '2026-07-10 00:00:00+00'
    AND item.value ? 'user_kcal'
    AND coalesce(item.value->>'user_kcal', '') ~ '^[0-9]+([.][0-9]+)?$'
    AND coalesce(item.value->>'quantity_g', '') ~ '^[0-9]+([.][0-9]+)?$'
    AND coalesce(item.value->>'kcal', '') ~ '^[0-9]+([.][0-9]+)?$'
    AND (item.value->>'user_kcal')::numeric = 70
    AND NOT (
      coalesce(pr.proposal->>'source_text', '')
        ~* '(^|[^0-9])70([,.]0+)?[[:space:]]*(kcal|caloria|calorias)'
      OR EXISTS (
        SELECT 1
        FROM public.messages m
        WHERE m.user_id = pr.user_id
          AND m.direction = 'in'
          AND m.created_at BETWEEN pr.created_at - interval '15 minutes'
                               AND coalesce(pr.resolved_at, pr.created_at) + interval '1 minute'
          AND coalesce(m.content, '')
            ~* '(^|[^0-9])70([,.]0+)?[[:space:]]*(kcal|caloria|calorias)'
      )
    )
),
override_log_candidates AS (
  SELECT
    oi.*,
    ml.id AS log_id,
    ml.food_name,
    ml.kcal AS kcal_before,
    ml.protein_g AS protein_before,
    ml.carbs_g AS carbs_before,
    ml.fat_g AS fat_before,
    (ml.consumed_at AT TIME ZONE au.timezone)::date AS local_date,
    row_number() OVER (
      PARTITION BY oi.pending_id, oi.item_ordinal
      ORDER BY abs(extract(epoch FROM (ml.created_at - coalesce(oi.resolved_at, oi.created_at)))), ml.id
    ) AS match_rank
  FROM override_items oi
  JOIN active_users au ON au.id = oi.user_id
  JOIN public.meal_logs ml
    ON ml.user_id = oi.user_id
   AND lower(public.f_unaccent(trim(ml.food_name))) = oi.name_norm
   AND ml.quantity_g = oi.quantity_g
   AND ml.kcal = oi.kcal
   AND ml.created_at BETWEEN oi.created_at - interval '5 minutes'
                         AND coalesce(oi.resolved_at, oi.created_at) + interval '30 minutes'
  WHERE oi.status = 'confirmed'
),
confirmed_override_logs AS (
  SELECT *
  FROM override_log_candidates
  WHERE match_rank = 1
),
override_canonical_repairs AS (
  SELECT
    col.log_id,
    col.user_id,
    col.local_date,
    col.food_name,
    col.quantity_g,
    col.kcal_before,
    col.protein_before,
    col.carbs_before,
    col.fat_before,
    round(col.quantity_g * ref.kcal_per_100g / 100, 2) AS kcal_after,
    round(col.quantity_g * ref.protein_g / 100, 2) AS protein_after,
    round(col.quantity_g * ref.carbs_g / 100, 2) AS carbs_after,
    round(col.quantity_g * ref.fat_g / 100, 2) AS fat_after,
    'unscoped_70_override_canonical'::text AS reason,
    20 AS priority
  FROM confirmed_override_logs col
  JOIN unique_food_refs ref ON ref.name_norm = col.name_norm
),
frango_peer_candidates AS (
  SELECT
    bad.*,
    peer.kcal / nullif(peer.quantity_g, 0) AS peer_kcal_per_g,
    peer.protein_g / nullif(peer.quantity_g, 0) AS peer_protein_per_g,
    peer.carbs_g / nullif(peer.quantity_g, 0) AS peer_carbs_per_g,
    peer.fat_g / nullif(peer.quantity_g, 0) AS peer_fat_per_g,
    row_number() OVER (
      PARTITION BY bad.log_id
      ORDER BY abs(extract(epoch FROM (peer.created_at - bad.created_at))), peer.id
    ) AS peer_rank
  FROM confirmed_override_logs bad
  JOIN active_users peer_user ON peer_user.id <> bad.user_id
  JOIN public.meal_logs peer
    ON peer.user_id = peer_user.id
   AND lower(public.f_unaccent(trim(peer.food_name))) = bad.name_norm
   AND (peer.consumed_at AT TIME ZONE peer_user.timezone)::date = bad.local_date
   AND peer.quantity_g > 0
   AND peer.kcal / peer.quantity_g BETWEEN 1 AND 3
  WHERE bad.name_norm = 'frango ao molho cremoso'
),
frango_peer_repairs AS (
  SELECT
    log_id,
    user_id,
    local_date,
    food_name,
    quantity_g,
    kcal_before,
    protein_before,
    carbs_before,
    fat_before,
    round(quantity_g * peer_kcal_per_g, 2) AS kcal_after,
    round(quantity_g * peer_protein_per_g, 2) AS protein_after,
    round(quantity_g * peer_carbs_per_g, 2) AS carbs_after,
    round(quantity_g * peer_fat_per_g, 2) AS fat_after,
    'frango_cremoso_peer_incident'::text AS reason,
    30 AS priority
  FROM frango_peer_candidates
  WHERE peer_rank = 1
),
repair_union AS (
  SELECT * FROM targeted_canonical_repairs
  UNION ALL
  SELECT * FROM override_canonical_repairs
  UNION ALL
  SELECT * FROM frango_peer_repairs
),
repair_rows AS (
  SELECT DISTINCT ON (log_id) *
  FROM repair_union
  ORDER BY log_id, priority
),
review_confirmed AS (
  SELECT col.*
  FROM confirmed_override_logs col
  WHERE NOT EXISTS (SELECT 1 FROM repair_rows rr WHERE rr.log_id = col.log_id)
),
effective_meals AS (
  SELECT
    ml.user_id,
    (ml.consumed_at AT TIME ZONE au.timezone)::date AS local_date,
    count(*) AS meal_items,
    round(sum(coalesce(rr.kcal_after, ml.kcal, 0)), 2) AS kcal,
    round(sum(coalesce(rr.protein_after, ml.protein_g, 0)), 2) AS protein_g,
    round(sum(coalesce(rr.carbs_after, ml.carbs_g, 0)), 2) AS carbs_g,
    round(sum(coalesce(rr.fat_after, ml.fat_g, 0)), 2) AS fat_g
  FROM public.meal_logs ml
  JOIN active_users au ON au.id = ml.user_id
  LEFT JOIN repair_rows rr ON rr.log_id = ml.id
  GROUP BY ml.user_id, (ml.consumed_at AT TIME ZONE au.timezone)::date
),
effective_workouts AS (
  SELECT
    wl.user_id,
    (wl.performed_at AT TIME ZONE au.timezone)::date AS local_date,
    round(sum(coalesce(wl.estimated_kcal, 0)), 2) AS exercise_calories
  FROM public.workout_logs wl
  JOIN active_users au ON au.id = wl.user_id
  GROUP BY wl.user_id, (wl.performed_at AT TIME ZONE au.timezone)::date
),
snapshot_comparison AS (
  SELECT
    ds.*,
    coalesce(em.meal_items, 0) AS meal_items_after,
    coalesce(em.kcal, 0) AS calories_after,
    coalesce(em.protein_g, 0) AS protein_after,
    coalesce(em.carbs_g, 0) AS carbs_after,
    coalesce(em.fat_g, 0) AS fat_after,
    coalesce(ew.exercise_calories, 0) AS exercise_after,
    EXISTS (
      SELECT 1
      FROM repair_rows rr
      WHERE rr.user_id = ds.user_id AND rr.local_date = ds.date
    ) AS contains_nutrition_repair
  FROM public.daily_snapshots ds
  JOIN active_users au ON au.id = ds.user_id
  LEFT JOIN effective_meals em ON em.user_id = ds.user_id AND em.local_date = ds.date
  LEFT JOIN effective_workouts ew ON ew.user_id = ds.user_id AND ew.local_date = ds.date
),
affected_snapshots AS (
  SELECT *
  FROM snapshot_comparison sc
  WHERE sc.contains_nutrition_repair
     OR abs(sc.calories_consumed - sc.calories_after) > 1
     OR abs(sc.protein_g - sc.protein_after) > 0.5
     OR abs(sc.carbs_g - sc.carbs_after) > 0.5
     OR abs(sc.fat_g - sc.fat_after) > 0.5
     OR abs(sc.exercise_calories - sc.exercise_after) > 1
),
affected_closed_users AS (
  SELECT DISTINCT user_id
  FROM affected_snapshots
  WHERE day_closed = true
),
profiles AS (
  SELECT
    acu.user_id,
    CASE
      WHEN up.current_protocol = 'recomposicao' THEN coalesce(up.deficit_level, 500)
      ELSE 0
    END::numeric AS design_deficit
  FROM affected_closed_users acu
  LEFT JOIN public.user_profiles up ON up.user_id = acu.user_id
),
closed_day_credits AS (
  SELECT
    sc.user_id,
    CASE
      WHEN NOT (sc.meal_items_after > 0 OR sc.exercise_after > 0 OR sc.training_done) THEN 0
      WHEN sc.day_status = 'user_skipped'
        THEN p.design_deficit
          - (sc.calories_after - coalesce(sc.calories_target, 0) - sc.exercise_after)
      WHEN sc.calories_target IS NOT NULL
        AND sc.calories_target > 0
        AND sc.calories_after < 0.5 * sc.calories_target
        THEN CASE WHEN sc.day_status = 'complete' OR sc.day_status IS NULL
          THEN p.design_deficit ELSE 0 END
      WHEN sc.day_status = 'incomplete_no_response' THEN 0
      ELSE p.design_deficit
        - (sc.calories_after - coalesce(sc.calories_target, 0) - sc.exercise_after)
    END AS credit
  FROM snapshot_comparison sc
  JOIN profiles p ON p.user_id = sc.user_id
  WHERE sc.day_closed = true
),
progress_after AS (
  SELECT
    user_id,
    greatest(0, round(sum(credit)))::int AS total_credit
  FROM closed_day_credits
  GROUP BY user_id
),
preconditions AS (
  SELECT
    (SELECT count(*) = 3
      FROM unique_food_refs
      WHERE name_norm IN ('goiaba', 'leite em po integral', 'leite em po desnatado'))
      AS canonical_targets_unique,
    (SELECT count(*) = count(DISTINCT log_id) FROM repair_rows) AS repair_ids_unique,
    (SELECT bool_and(
      kcal_after >= 0 AND protein_after >= 0 AND carbs_after >= 0 AND fat_after >= 0
    ) FROM repair_rows) AS repaired_values_nonnegative
)
SELECT jsonb_build_object(
  'mode', 'dry-run',
  'writes', 0,
  'scope', 'all_active_users',
  'preconditions_ok',
    p.canonical_targets_unique
    AND p.repair_ids_unique
    AND coalesce(p.repaired_values_nonnegative, true),
  'deterministic_repairs', jsonb_build_object(
    'count', (SELECT count(*) FROM repair_rows),
    'by_reason', (
      SELECT coalesce(jsonb_object_agg(reason, rows), '{}'::jsonb)
      FROM (SELECT reason, count(*) AS rows FROM repair_rows GROUP BY reason ORDER BY reason) grouped
    ),
    'items', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'user_ref', substr(md5(user_id::text), 1, 10),
        'log_ref', substr(log_id::text, 1, 8),
        'local_date', local_date,
        'food', food_name,
        'quantity_g', quantity_g,
        'kcal_before', kcal_before,
        'kcal_after', kcal_after,
        'reason', reason
      ) ORDER BY local_date, food_name, log_id), '[]'::jsonb)
      FROM repair_rows
    )
  ),
  'review_only', jsonb_build_object(
    'confirmed_without_objective_reference', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'user_ref', substr(md5(user_id::text), 1, 10),
        'log_ref', substr(log_id::text, 1, 8),
        'local_date', local_date,
        'food', food_name,
        'quantity_g', quantity_g,
        'kcal', kcal_before,
        'reason', 'no_unique_food_reference'
      ) ORDER BY local_date, food_name), '[]'::jsonb)
      FROM review_confirmed
    ),
    'nonconfirmed_contaminated_proposals', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'user_ref', substr(md5(user_id::text), 1, 10),
        'pending_ref', substr(pending_id::text, 1, 8),
        'status', status,
        'food', item->>'name',
        'quantity_g', quantity_g,
        'kcal', kcal
      ) ORDER BY created_at, pending_id), '[]'::jsonb)
      FROM override_items
      WHERE status <> 'confirmed'
    ),
    'confirmed_proposals_without_matching_log', (
      SELECT count(*)
      FROM override_items oi
      WHERE oi.status = 'confirmed'
        AND NOT EXISTS (
          SELECT 1 FROM confirmed_override_logs col
          WHERE col.pending_id = oi.pending_id AND col.item_ordinal = oi.item_ordinal
        )
    )
  ),
  'snapshots', jsonb_build_object(
    'count', (SELECT count(*) FROM affected_snapshots),
    'items', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'user_ref', substr(md5(user_id::text), 1, 10),
        'date', date,
        'closed', day_closed,
        'kcal_before', calories_consumed,
        'kcal_after', calories_after,
        'protein_before', protein_g,
        'protein_after', protein_after,
        'carbs_before', carbs_g,
        'carbs_after', carbs_after,
        'fat_before', fat_g,
        'fat_after', fat_after,
        'contains_nutrition_repair', contains_nutrition_repair
      ) ORDER BY date, user_id), '[]'::jsonb)
      FROM affected_snapshots
    )
  ),
  'block_progress', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'user_ref', substr(md5(pa.user_id::text), 1, 10),
      'before_blocks', coalesce(up.blocks_completed, 0),
      'before_deficit_block', coalesce(up.deficit_block, 0),
      'after_blocks', floor(pa.total_credit / 7700.0)::int,
      'after_deficit_block', pa.total_credit % 7700
    ) ORDER BY pa.user_id), '[]'::jsonb)
    FROM progress_after pa
    LEFT JOIN public.user_progress up ON up.user_id = pa.user_id
  ),
  'repair_rows_without_snapshot', (
    SELECT count(*)
    FROM repair_rows rr
    WHERE NOT EXISTS (
      SELECT 1 FROM public.daily_snapshots ds
      WHERE ds.user_id = rr.user_id AND ds.date = rr.local_date
    )
  )
) AS audit_preview
FROM preconditions p;
