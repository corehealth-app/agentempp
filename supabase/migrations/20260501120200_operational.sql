-- ============================================================================
-- Migration 0003: Operational tables
-- ============================================================================
-- Tabelas do dia-a-dia: snapshots diários, refeições, treinos, reavaliações.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- daily_snapshots
-- ----------------------------------------------------------------------------
CREATE TABLE daily_snapshots (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date                  date NOT NULL,
  calories_consumed     integer NOT NULL DEFAULT 0,
  calories_target       integer,
  protein_g             numeric(6,2) NOT NULL DEFAULT 0,
  protein_target        numeric(6,2),
  carbs_g               numeric(6,2) NOT NULL DEFAULT 0,
  fat_g                 numeric(6,2) NOT NULL DEFAULT 0,
  exercise_calories     integer NOT NULL DEFAULT 0,
  steps                 integer,
  training_done         boolean NOT NULL DEFAULT false,
  sleep_hours           numeric(3,1),
  water_consumed_ml     integer NOT NULL DEFAULT 0,
  xp_earned             integer NOT NULL DEFAULT 0,
  deficit_accumulated   integer NOT NULL DEFAULT 0,
  daily_balance         integer GENERATED ALWAYS AS (
    calories_consumed - COALESCE(calories_target, 0) - COALESCE(exercise_calories, 0)
  ) STORED,
  current_protocol      protocol_enum,
  day_closed            boolean NOT NULL DEFAULT false,
  closed_at             timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, date)
);

CREATE INDEX idx_daily_user_date ON daily_snapshots(user_id, date DESC);
CREATE INDEX idx_daily_unclosed ON daily_snapshots(date, day_closed) WHERE day_closed = false;

COMMENT ON TABLE daily_snapshots IS 'Resumo agregado por usuário/dia. Atualizado por cada refeição/treino.';
COMMENT ON COLUMN daily_snapshots.daily_balance IS 'Positivo = surplus, negativo = déficit.';

-- ----------------------------------------------------------------------------
-- meal_logs (cada item da foto vira 1 linha)
-- ----------------------------------------------------------------------------
CREATE TABLE meal_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_id     uuid REFERENCES daily_snapshots(id) ON DELETE CASCADE,
  meal_type       meal_type_enum,
  food_name       text NOT NULL,
  quantity_g      numeric(6,2),
  kcal            numeric(7,2),
  protein_g       numeric(6,2),
  carbs_g         numeric(6,2),
  fat_g           numeric(6,2),
  source          text,
  confidence      numeric(3,2) CHECK (confidence IS NULL OR (confidence BETWEEN 0 AND 1)),
  image_url       text,
  raw_message_id  uuid,
  consumed_at     timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_meals_user_consumed ON meal_logs(user_id, consumed_at DESC);
CREATE INDEX idx_meals_snapshot ON meal_logs(snapshot_id);

COMMENT ON COLUMN meal_logs.source IS 'taco | gemini_estimate | user_correction | manual';

-- ----------------------------------------------------------------------------
-- workout_logs
-- ----------------------------------------------------------------------------
CREATE TABLE workout_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_id     uuid REFERENCES daily_snapshots(id) ON DELETE CASCADE,
  workout_type    text,
  duration_min    integer CHECK (duration_min IS NULL OR duration_min > 0),
  estimated_kcal  integer CHECK (estimated_kcal IS NULL OR estimated_kcal >= 0),
  intensity       text,
  notes           text,
  performed_at    timestamptz NOT NULL DEFAULT now(),
  raw_message_id  uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_workouts_user_performed ON workout_logs(user_id, performed_at DESC);

-- ----------------------------------------------------------------------------
-- reevaluations (a cada 14 dias)
-- ----------------------------------------------------------------------------
CREATE TABLE reevaluations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  evaluation_date date NOT NULL,
  weight_kg       numeric(5,2),
  bf_percent      numeric(4,2),
  photos          text[],
  user_feedback   text,
  agent_decision  jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_reeval_user_date ON reevaluations(user_id, evaluation_date DESC);

COMMENT ON COLUMN reevaluations.agent_decision IS 'JSON com {protocol_change, deficit_adjustment, new_goal, ...}';
