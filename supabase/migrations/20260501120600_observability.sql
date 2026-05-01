-- ============================================================================
-- Migration 0007: Observability tables
-- ============================================================================

-- ----------------------------------------------------------------------------
-- tools_audit (auditoria de cada tool call)
-- ----------------------------------------------------------------------------
CREATE TABLE tools_audit (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id  uuid REFERENCES messages(id) ON DELETE SET NULL,
  user_id     uuid REFERENCES users(id) ON DELETE CASCADE,
  tool_name   text NOT NULL,
  arguments   jsonb,
  result      jsonb,
  duration_ms integer,
  success     boolean NOT NULL,
  error       text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_tools_user_created ON tools_audit(user_id, created_at DESC);
CREATE INDEX idx_tools_name ON tools_audit(tool_name, created_at DESC);
CREATE INDEX idx_tools_failed ON tools_audit(created_at DESC) WHERE success = false;

-- ----------------------------------------------------------------------------
-- llm_evaluations (LLM-as-a-Judge sample 10%)
-- ----------------------------------------------------------------------------
CREATE TABLE llm_evaluations (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id        uuid REFERENCES messages(id) ON DELETE SET NULL,
  user_id           uuid REFERENCES users(id) ON DELETE CASCADE,
  agent_name        text,
  user_input        text,
  response_obtained text,
  expected_response text,
  score             numeric(3,1) CHECK (score IS NULL OR (score BETWEEN 0 AND 10)),
  reasoning         text,
  model_used        text,
  evaluated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_evals_score ON llm_evaluations(score, evaluated_at DESC);
CREATE INDEX idx_evals_user ON llm_evaluations(user_id, evaluated_at DESC);

-- ----------------------------------------------------------------------------
-- product_events (espelho local do PostHog para queries SQL)
-- ----------------------------------------------------------------------------
CREATE TABLE product_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES users(id) ON DELETE CASCADE,
  event       text NOT NULL,
  properties  jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_events_user_occurred ON product_events(user_id, occurred_at DESC);
CREATE INDEX idx_events_name_occurred ON product_events(event, occurred_at DESC);

-- ----------------------------------------------------------------------------
-- whatsapp_phone_status (monitoramento de quality + tier)
-- ----------------------------------------------------------------------------
CREATE TABLE whatsapp_phone_status (
  phone_number_id      text PRIMARY KEY,
  display_phone_number text,
  quality_rating       text,
  messaging_limit_tier text,
  last_checked_at      timestamptz NOT NULL DEFAULT now(),
  history              jsonb NOT NULL DEFAULT '[]'::jsonb
);

COMMENT ON COLUMN whatsapp_phone_status.quality_rating IS 'GREEN | YELLOW | RED — alerta em mudança.';
COMMENT ON COLUMN whatsapp_phone_status.messaging_limit_tier IS '250 | 1000 | 10000 | 100000 | unlimited';

-- ----------------------------------------------------------------------------
-- View: custo diário por stage
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_daily_cost AS
SELECT
  date_trunc('day', created_at) AS day,
  agent_stage,
  model_used,
  COUNT(*) AS calls,
  SUM(prompt_tokens) AS total_in_tokens,
  SUM(completion_tokens) AS total_out_tokens,
  SUM(cost_usd) AS total_cost_usd,
  AVG(latency_ms) AS avg_latency_ms
FROM messages
WHERE direction = 'out' AND model_used IS NOT NULL
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 6 DESC;

COMMENT ON VIEW v_daily_cost IS 'Agregado de custo LLM por dia/stage/modelo.';
