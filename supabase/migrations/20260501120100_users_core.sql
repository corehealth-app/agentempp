-- ============================================================================
-- Migration 0002: Users, Profiles, Progress
-- ============================================================================
-- Núcleo do domínio: identidade, perfil clínico, gamificação.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- users
-- ----------------------------------------------------------------------------
CREATE TABLE users (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wpp         text UNIQUE NOT NULL,
  email       text UNIQUE,
  name        text,
  locale      text DEFAULT 'pt-BR',
  timezone    text DEFAULT 'America/Sao_Paulo',
  status      user_status NOT NULL DEFAULT 'active',
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_wpp ON users(wpp);
CREATE INDEX idx_users_status ON users(status) WHERE status <> 'deleted';

COMMENT ON TABLE users IS 'Usuários finais do produto (acessam via WhatsApp).';
COMMENT ON COLUMN users.wpp IS 'Número WhatsApp normalizado (E.164 sem +).';

-- ----------------------------------------------------------------------------
-- user_profiles
-- ----------------------------------------------------------------------------
CREATE TABLE user_profiles (
  user_id              uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  sex                  sex_enum,
  birth_date           date,
  height_cm            numeric(5,2) CHECK (height_cm > 0 AND height_cm < 300),
  weight_kg            numeric(5,2) CHECK (weight_kg > 0 AND weight_kg < 500),
  body_fat_percent     numeric(4,2) CHECK (body_fat_percent IS NULL OR (body_fat_percent > 0 AND body_fat_percent < 70)),
  activity_level       activity_enum,
  training_frequency   smallint CHECK (training_frequency IS NULL OR (training_frequency BETWEEN 0 AND 7)),
  water_intake         water_enum,
  hunger_level         hunger_enum,
  wake_time            time,
  bedtime              time,
  current_protocol     protocol_enum,
  goal_type            goal_type_enum,
  goal_value           numeric(5,2),
  deficit_level        smallint CHECK (deficit_level IS NULL OR deficit_level IN (400, 500, 600)),
  onboarding_completed boolean NOT NULL DEFAULT false,
  onboarding_step      smallint NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE user_profiles IS 'Dados clínicos e preferências coletados no onboarding.';
COMMENT ON COLUMN user_profiles.deficit_level IS 'Apenas para protocolo de recomposição: 400/500/600 kcal.';

-- ----------------------------------------------------------------------------
-- user_progress (gamificação)
-- ----------------------------------------------------------------------------
CREATE TABLE user_progress (
  user_id              uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  xp_total             integer NOT NULL DEFAULT 0 CHECK (xp_total >= 0),
  level                smallint NOT NULL DEFAULT 1 CHECK (level >= 1),
  current_streak       smallint NOT NULL DEFAULT 0 CHECK (current_streak >= 0),
  longest_streak       smallint NOT NULL DEFAULT 0 CHECK (longest_streak >= 0),
  blocks_completed     smallint NOT NULL DEFAULT 0 CHECK (blocks_completed >= 0),
  deficit_block        integer NOT NULL DEFAULT 0 CHECK (deficit_block >= 0),
  current_weight       numeric(5,2),
  current_bf_percent   numeric(4,2),
  badges_earned        text[] NOT NULL DEFAULT '{}',
  last_active_date     date,
  next_reevaluation    date,
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_progress_next_reeval ON user_progress(next_reevaluation)
  WHERE next_reevaluation IS NOT NULL;

COMMENT ON TABLE user_progress IS 'Estado de gamificação por usuário.';
COMMENT ON COLUMN user_progress.deficit_block IS 'Acúmulo de déficit dentro do bloco atual de 7700 kcal.';

-- ----------------------------------------------------------------------------
-- View de métricas calculadas (substitui fórmulas do Notion)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_user_metrics AS
SELECT
  p.user_id,
  EXTRACT(YEAR FROM age(p.birth_date))::int AS age,
  -- BMR: Katch-McArdle se BF disponível, senão Mifflin-St Jeor
  CASE
    WHEN p.body_fat_percent IS NOT NULL AND p.weight_kg IS NOT NULL THEN
      370 + (21.6 * p.weight_kg * (1 - p.body_fat_percent / 100))
    WHEN p.sex = 'masculino' AND p.weight_kg IS NOT NULL AND p.height_cm IS NOT NULL AND p.birth_date IS NOT NULL THEN
      (10 * p.weight_kg) + (6.25 * p.height_cm) - (5 * EXTRACT(YEAR FROM age(p.birth_date))) + 5
    WHEN p.sex = 'feminino' AND p.weight_kg IS NOT NULL AND p.height_cm IS NOT NULL AND p.birth_date IS NOT NULL THEN
      (10 * p.weight_kg) + (6.25 * p.height_cm) - (5 * EXTRACT(YEAR FROM age(p.birth_date))) - 161
    ELSE NULL
  END AS bmr,
  -- Activity factor
  CASE p.activity_level
    WHEN 'sedentario' THEN 1.2
    WHEN 'leve'       THEN 1.375
    WHEN 'moderado'   THEN 1.55
    WHEN 'alto'       THEN 1.725
    WHEN 'atleta'     THEN 1.9
  END AS activity_factor,
  -- LBM (massa magra)
  CASE
    WHEN p.weight_kg IS NOT NULL AND p.body_fat_percent IS NOT NULL THEN
      p.weight_kg * (1 - p.body_fat_percent / 100)
    ELSE p.weight_kg
  END AS lbm,
  -- IMC
  CASE
    WHEN p.weight_kg IS NOT NULL AND p.height_cm IS NOT NULL AND p.height_cm > 0 THEN
      p.weight_kg / ((p.height_cm / 100) * (p.height_cm / 100))
    ELSE NULL
  END AS imc,
  -- Protein factor
  CASE p.hunger_level
    WHEN 'pouca'    THEN 1.6
    WHEN 'moderada' THEN 1.8
    WHEN 'muita'    THEN 2.0
  END AS protein_factor
FROM user_profiles p;

COMMENT ON VIEW v_user_metrics IS 'Métricas derivadas do perfil. Reflete em tempo real qualquer mudança em user_profiles.';
