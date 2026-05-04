-- ============================================================================
-- Backfill: calories_target + protein_target em daily_snapshots históricos
-- ============================================================================
-- Snapshots criados antes do fix tinham calories_target=null →
-- daily_balance positivo sempre → bloco 7700 nunca incrementou.
--
-- Esta migration popula os valores históricos usando user_profiles atuais.
-- (Não tenta reconstruir blocos retroativamente — só ajusta os números pra
-- frente ficar coerente.)
-- ============================================================================

UPDATE daily_snapshots ds
SET
  calories_target = COALESCE(ds.calories_target, calc.cal_target),
  protein_target  = COALESCE(ds.protein_target,  calc.prot_target),
  updated_at = now()
FROM (
  SELECT
    p.user_id,
    -- BMR Mifflin-St Jeor (sem BF) ou Katch (com BF)
    CASE
      WHEN p.body_fat_percent IS NOT NULL AND p.body_fat_percent > 0
        THEN 370 + 21.6 * (p.weight_kg * (1 - p.body_fat_percent / 100.0))
      WHEN p.sex = 'masculino'
        THEN 10 * p.weight_kg + 6.25 * p.height_cm
             - 5 * extract(year from age(p.birth_date)) + 5
      ELSE
        10 * p.weight_kg + 6.25 * p.height_cm
        - 5 * extract(year from age(p.birth_date)) - 161
    END AS bmr,
    -- Activity factor
    CASE p.activity_level
      WHEN 'sedentario' THEN 1.2
      WHEN 'leve'       THEN 1.375
      WHEN 'moderado'   THEN 1.55
      WHEN 'alto'       THEN 1.725
      WHEN 'atleta'     THEN 1.9
      ELSE 1.2
    END AS activity_f,
    p.current_protocol,
    p.deficit_level,
    p.weight_kg,
    -- Protein factor
    CASE p.hunger_level
      WHEN 'pouca'    THEN 1.6
      WHEN 'moderada' THEN 1.8
      WHEN 'muita'    THEN 2.0
      ELSE 1.8
    END AS protein_f
  FROM user_profiles p
  WHERE p.weight_kg IS NOT NULL
    AND p.height_cm IS NOT NULL
    AND p.birth_date IS NOT NULL
    AND p.sex IS NOT NULL
    AND p.activity_level IS NOT NULL
) base
JOIN LATERAL (
  SELECT
    ROUND(base.bmr * base.activity_f
      - CASE base.current_protocol
          WHEN 'recomposicao' THEN COALESCE(base.deficit_level, 500)
          WHEN 'ganho_massa'  THEN -COALESCE(base.deficit_level, 300)
          ELSE 0
        END
    )::int AS cal_target,
    ROUND(base.weight_kg * base.protein_f * 10) / 10 AS prot_target
) calc ON true
WHERE ds.user_id = base.user_id
  AND (ds.calories_target IS NULL OR ds.protein_target IS NULL);

-- Quantos snapshots foram backfillados (output informativo no log)
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM daily_snapshots
  WHERE calories_target IS NOT NULL;
  RAISE NOTICE 'Snapshots com calories_target preenchido: %', v_count;
END $$;
