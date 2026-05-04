-- ============================================================================
-- Fix de 5 bugs críticos identificados em auditoria 2026-05-04
-- ============================================================================
-- 1) workout_types — tabela determinística pra calcular kcal queimadas (ADR-007)
-- 2) RPC snapshot_add_meal — UPDATE atomico (sem race condition)
-- 3) DROP daily_close_user / daily_close_all (dead code que confunde)
-- 4) Cron housekeeping pra attention_dismissals antigos
-- 5) Multi-tick daily-closer (8 ticks/dia cobrindo todos timezones)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) workout_types: kcal/min por tipo + intensity factor
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workout_types (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug            text NOT NULL UNIQUE,
  display_name    text NOT NULL,
  category        text NOT NULL CHECK (category IN ('musculacao', 'cardio', 'esporte', 'mobilidade')),
  kcal_per_min    numeric(5,2) NOT NULL,  -- pra paciente médio (70kg, intensidade moderada)
  description     text,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE workout_types IS
  'Tipos de treino com kcal/min de referência. Replicação do ADR-007: cálculo determinístico em vez de LLM estimar.';

INSERT INTO workout_types (slug, display_name, category, kcal_per_min, description) VALUES
  -- Musculação (~5 kcal/min)
  ('peito_triceps',     'Peito e tríceps',          'musculacao', 5.5, 'Compostos pesados, séries longas'),
  ('costas_biceps',     'Costas e bíceps',          'musculacao', 5.5, 'Puxadas, remadas, rosca'),
  ('perna_completa',    'Perna completa',           'musculacao', 7.0, 'Agachamentos, leg press, stiff'),
  ('ombro_trapezio',    'Ombro e trapézio',         'musculacao', 5.0, 'Desenvolvimento, elevações'),
  ('abdomen',           'Abdômen',                  'musculacao', 4.5, 'Crunches, prancha, elevação de pernas'),
  ('full_body',         'Full body',                'musculacao', 6.5, 'Treino A+B+C combinado'),
  ('crossfit',          'CrossFit / Funcional',     'musculacao', 9.0, 'WOD, alta intensidade'),
  -- Cardio (~10 kcal/min)
  ('corrida',           'Corrida',                  'cardio',     11.0, '~9-12 km/h ritmo moderado'),
  ('caminhada',         'Caminhada',                'cardio',      4.5, '~5-6 km/h ritmo leve'),
  ('caminhada_rapida',  'Caminhada rápida',         'cardio',      6.0, '~7 km/h, inclinação leve'),
  ('bicicleta',         'Bicicleta',                'cardio',      8.0, 'Ergométrica ou estrada'),
  ('eliptico',          'Elíptico',                 'cardio',      8.5, 'Ergométrica do tipo elliptical'),
  ('escada',            'Escada / Stair',           'cardio',     10.0, 'Subir escadas ou stairmaster'),
  ('natacao',           'Natação',                  'cardio',     10.0, 'Crawl moderado'),
  ('hiit',              'HIIT',                     'cardio',     12.0, 'Intervalado de alta intensidade'),
  ('jumping_jacks',     'Polichinelos',             'cardio',      8.0, 'Aquecimento ou tabata'),
  -- Esportes (~7-9 kcal/min)
  ('futebol',           'Futebol',                  'esporte',     8.0, 'Pelada, society'),
  ('volei',             'Vôlei',                    'esporte',     6.5, 'Quadra ou praia'),
  ('beach_tennis',      'Beach tennis',             'esporte',     7.0, 'Recreativo'),
  ('tenis',             'Tênis',                    'esporte',     7.5, 'Single ou duplas'),
  ('basquete',          'Basquete',                 'esporte',     8.5, 'Pelada ou pickup'),
  ('luta',              'Luta / Jiu-jitsu / Boxe',  'esporte',    10.5, 'Treino técnico ou rolagem'),
  -- Mobilidade (~3 kcal/min)
  ('yoga',              'Yoga',                     'mobilidade',  3.0, 'Hatha, vinyasa moderado'),
  ('pilates',           'Pilates',                  'mobilidade',  4.0, 'Solo ou aparelhos'),
  ('alongamento',       'Alongamento',              'mobilidade',  2.5, 'Mobility / flex'),
  -- Genérico (fallback)
  ('outro',             'Outro',                    'cardio',      6.0, 'Tipo não classificado — média geral')
ON CONFLICT (slug) DO NOTHING;

GRANT SELECT ON workout_types TO authenticated, service_role;

-- Helper SQL pra calcular kcal queimadas
CREATE OR REPLACE FUNCTION calc_workout_kcal(
  p_slug text,
  p_duration_min int,
  p_intensity text DEFAULT 'moderada',
  p_weight_kg numeric DEFAULT 70
) RETURNS int
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_base numeric;
  v_factor numeric;
BEGIN
  SELECT kcal_per_min INTO v_base FROM workout_types
   WHERE slug = lower(p_slug) AND is_active = true;
  IF v_base IS NULL THEN
    -- Fallback genérico
    SELECT kcal_per_min INTO v_base FROM workout_types WHERE slug = 'outro';
    IF v_base IS NULL THEN v_base := 6.0; END IF;
  END IF;
  v_factor := CASE lower(coalesce(p_intensity, 'moderada'))
    WHEN 'leve'     THEN 0.75
    WHEN 'moderada' THEN 1.0
    WHEN 'alta'     THEN 1.25
    ELSE 1.0
  END;
  -- Ajuste por peso (ref: 70kg) — kcal escala linearmente
  RETURN ROUND(v_base * p_duration_min * v_factor * (p_weight_kg / 70.0));
END;
$$;

GRANT EXECUTE ON FUNCTION calc_workout_kcal TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2) RPC snapshot_add_meal — UPDATE atomico (resolve race condition)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION snapshot_add_meal(
  p_user_id  uuid,
  p_date     date,
  p_kcal     numeric,
  p_protein  numeric,
  p_carbs    numeric,
  p_fat      numeric,
  p_calories_target int DEFAULT NULL,
  p_protein_target numeric DEFAULT NULL
) RETURNS daily_snapshots
LANGUAGE plpgsql
AS $$
DECLARE
  v_snap daily_snapshots;
BEGIN
  -- INSERT com ON CONFLICT — atomico
  INSERT INTO daily_snapshots (
    user_id, date,
    calories_consumed, protein_g, carbs_g, fat_g,
    calories_target, protein_target
  ) VALUES (
    p_user_id, p_date,
    ROUND(p_kcal)::int, p_protein, p_carbs, p_fat,
    p_calories_target, p_protein_target
  )
  ON CONFLICT (user_id, date) DO UPDATE SET
    calories_consumed = daily_snapshots.calories_consumed + ROUND(p_kcal)::int,
    protein_g         = ROUND((daily_snapshots.protein_g + p_protein) * 100) / 100,
    carbs_g           = ROUND((daily_snapshots.carbs_g + p_carbs) * 100) / 100,
    fat_g             = ROUND((daily_snapshots.fat_g + p_fat) * 100) / 100,
    -- Só preenche target se tava null
    calories_target = COALESCE(daily_snapshots.calories_target, EXCLUDED.calories_target),
    protein_target  = COALESCE(daily_snapshots.protein_target,  EXCLUDED.protein_target),
    updated_at = now()
  RETURNING * INTO v_snap;
  RETURN v_snap;
END;
$$;

GRANT EXECUTE ON FUNCTION snapshot_add_meal TO authenticated, service_role;

-- RPC equivalente pra workouts
CREATE OR REPLACE FUNCTION snapshot_add_workout(
  p_user_id           uuid,
  p_date              date,
  p_exercise_kcal     int,
  p_calories_target   int DEFAULT NULL,
  p_protein_target    numeric DEFAULT NULL
) RETURNS daily_snapshots
LANGUAGE plpgsql
AS $$
DECLARE
  v_snap daily_snapshots;
BEGIN
  INSERT INTO daily_snapshots (
    user_id, date,
    exercise_calories, training_done,
    calories_target, protein_target
  ) VALUES (
    p_user_id, p_date,
    p_exercise_kcal, true,
    p_calories_target, p_protein_target
  )
  ON CONFLICT (user_id, date) DO UPDATE SET
    exercise_calories = daily_snapshots.exercise_calories + p_exercise_kcal,
    training_done     = true,
    calories_target = COALESCE(daily_snapshots.calories_target, EXCLUDED.calories_target),
    protein_target  = COALESCE(daily_snapshots.protein_target,  EXCLUDED.protein_target),
    updated_at = now()
  RETURNING * INTO v_snap;
  RETURN v_snap;
END;
$$;

GRANT EXECUTE ON FUNCTION snapshot_add_workout TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) DROP dead code: daily_close_user / daily_close_all (sql)
-- ----------------------------------------------------------------------------
-- Lógica de fechamento diário 100% migrada pro Inngest worker daily-closer.
-- Funções SQL nunca chamadas pelos crons atuais (substituídos por
-- dispatch_inngest_event), mas existir pode confundir manutenção.
DROP FUNCTION IF EXISTS daily_close_all(date);
DROP FUNCTION IF EXISTS daily_close_user(uuid, date);
DROP FUNCTION IF EXISTS mpp_level_for_xp(int);  -- helper só usado pela função SQL morta

-- ----------------------------------------------------------------------------
-- 4) Housekeeping: attention_dismissals expirados há > 7d
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION attention_cleanup_expired()
RETURNS int
LANGUAGE sql
AS $$
  WITH deleted AS (
    DELETE FROM attention_dismissals
    WHERE dismissed_until IS NOT NULL
      AND dismissed_until < now() - interval '7 days'
    RETURNING id
  )
  SELECT count(*)::int FROM deleted;
$$;

GRANT EXECUTE ON FUNCTION attention_cleanup_expired TO authenticated, service_role;

-- Cron diário às 03:00 UTC (pouco overhead, baixa prioridade)
SELECT cron.schedule(
  'attention-cleanup',
  '0 3 * * *',
  $$ SELECT attention_cleanup_expired() $$
);

-- ----------------------------------------------------------------------------
-- 5) Multi-tick daily-closer — cobre todos os timezones
-- ----------------------------------------------------------------------------
-- Antes: 4 ticks UTC (00h30, 01h30, 02h30, 03h30).
-- Pacientes em UTC-5 a UTC-8 (US): nunca rodava daily-closer (localHour > 4).
-- Solução: 24 ticks (1×/hora UTC). Cada tick verifica localHour ≤ 4 do user.
-- Custo: ~24 disparos/dia em vez de 4 — mas cada um filtra pacientes
-- (a maioria pula imediatamente). Latência IO total continua baixa.

DO $$
DECLARE
  h int;
BEGIN
  FOR h IN 4..23 LOOP
    -- Já temos 0,1,2,3 schedulados em migration anterior.
    -- Adicionar 4..23 com mesmo padrão.
    PERFORM cron.schedule(
      'daily-closer-' || lpad(h::text, 2, '0') || '30',
      '30 ' || h || ' * * *',
      format($f$ SELECT dispatch_inngest_event(
        'day.close.tick',
        jsonb_build_object('hour', %s, 'fired_at', now()::text)
      ) $f$, h)
    );
  END LOOP;
END $$;

COMMENT ON FUNCTION attention_cleanup_expired IS
  'Apaga dismissals expirados há mais de 7 dias. Roda 1×/dia via cron attention-cleanup.';
