-- Fundação Sprint 4 + 3.1 (Roberto 2026-06-11):
-- - prescriptions: armazena dieta + lista de compras gerada pelo agente
-- - training_plans: treino esporádico (geração 1x, entrega diária determinística)
-- - food_education_phrases: receptor das 50 frases curadas pelo Roberto
--
-- Implementação concreta dos endpoints/tools fica pra próximo sprint.
-- Estas tabelas são a FUNDAÇÃO mínima viável.

CREATE TABLE IF NOT EXISTS prescriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('diet', 'shopping_list', 'combined')),
  payload jsonb NOT NULL,
  generated_by text DEFAULT 'agent',
  generated_at timestamptz NOT NULL DEFAULT now(),
  last_sent_at timestamptz,
  valid_until timestamptz,
  version int DEFAULT 1,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_prescriptions_user ON prescriptions(user_id, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_prescriptions_valid ON prescriptions(user_id, type, valid_until);

CREATE TABLE IF NOT EXISTS training_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_type text NOT NULL DEFAULT 'split' CHECK (plan_type IN ('split', 'full_body', 'custom')),
  days_per_week int NOT NULL CHECK (days_per_week BETWEEN 1 AND 7),
  equipment_summary text,
  weekly_schedule jsonb NOT NULL,
  generated_by text DEFAULT 'agent',
  generated_at timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  active boolean NOT NULL DEFAULT true,
  version int DEFAULT 1,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_training_plans_user_active
  ON training_plans(user_id, active, generated_at DESC)
  WHERE active = true;

CREATE TABLE IF NOT EXISTS food_education_phrases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  food_canonical_name text NOT NULL,
  phrase text NOT NULL,
  tags jsonb DEFAULT '{}'::jsonb,
  language text DEFAULT 'pt-BR',
  curated_by text DEFAULT 'roberto',
  active boolean NOT NULL DEFAULT true,
  usage_count int NOT NULL DEFAULT 0,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_food_phrases_food
  ON food_education_phrases(food_canonical_name, active, language);
CREATE INDEX IF NOT EXISTS idx_food_phrases_usage
  ON food_education_phrases(food_canonical_name, last_used_at NULLS FIRST);

COMMENT ON TABLE prescriptions IS 'Dieta + lista de compras geradas para cada paciente';
COMMENT ON TABLE training_plans IS 'Plano de treino semanal gerado 1x via foto de equipamentos, entregue diariamente via cron determinístico';
COMMENT ON TABLE food_education_phrases IS 'Frases prontas curadas pelo Roberto pra substituir Haiku edu-comment (até 50 variantes por alimento)';
