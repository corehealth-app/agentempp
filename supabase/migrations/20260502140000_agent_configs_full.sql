-- ============================================================================
-- Migration 0018: Expor todas variáveis de configuração do agente
-- ============================================================================
-- Antes: pipeline tinha buffer_debounce, max_tool_iterations, timeouts e
-- allowlist de tools hardcoded em código. Gestor não conseguia ajustar
-- sem deploy.
-- Depois: tudo configurável por stage em agent_configs.
-- ============================================================================

ALTER TABLE agent_configs
  ADD COLUMN IF NOT EXISTS max_tool_iterations  smallint NOT NULL DEFAULT 5
    CHECK (max_tool_iterations BETWEEN 1 AND 20),
  ADD COLUMN IF NOT EXISTS buffer_debounce_ms   integer NOT NULL DEFAULT 8000
    CHECK (buffer_debounce_ms BETWEEN 500 AND 60000),
  ADD COLUMN IF NOT EXISTS llm_timeout_ms       integer NOT NULL DEFAULT 90000
    CHECK (llm_timeout_ms BETWEEN 5000 AND 300000),
  ADD COLUMN IF NOT EXISTS vision_timeout_ms    integer NOT NULL DEFAULT 60000
    CHECK (vision_timeout_ms BETWEEN 5000 AND 180000),
  ADD COLUMN IF NOT EXISTS stt_timeout_ms       integer NOT NULL DEFAULT 30000
    CHECK (stt_timeout_ms BETWEEN 3000 AND 120000),
  ADD COLUMN IF NOT EXISTS allowed_tools        text[] DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS helicone_cache       boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS streaming            boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS top_p                numeric(3,2) DEFAULT NULL
    CHECK (top_p IS NULL OR top_p BETWEEN 0 AND 1),
  ADD COLUMN IF NOT EXISTS frequency_penalty    numeric(3,2) DEFAULT 0
    CHECK (frequency_penalty BETWEEN -2 AND 2),
  ADD COLUMN IF NOT EXISTS presence_penalty     numeric(3,2) DEFAULT 0
    CHECK (presence_penalty BETWEEN -2 AND 2);

COMMENT ON COLUMN agent_configs.max_tool_iterations IS
  'Quantas iterações de tool calling o LLM pode fazer num turno (segurança contra loops).';
COMMENT ON COLUMN agent_configs.buffer_debounce_ms IS
  'Janela de empilhamento de mensagens (debounce). Webhook agenda flush nesse delay.';
COMMENT ON COLUMN agent_configs.llm_timeout_ms IS
  'Timeout por chamada LLM individual. Pipeline pode fazer N iterações × este valor.';
COMMENT ON COLUMN agent_configs.allowed_tools IS
  'Lista de tools permitidas neste stage. NULL = todas. Use slugs (cadastra_dados_iniciais, etc).';
COMMENT ON COLUMN agent_configs.helicone_cache IS
  'Habilita cache do Helicone (respostas idênticas reutilizadas, economiza custo).';
COMMENT ON COLUMN agent_configs.streaming IS
  'Streaming token-a-token (futuro). Hoje é off — sendHumanized faz quebra natural.';

-- Atualiza v_active_prompts pra trazer essas colunas novas
DROP VIEW IF EXISTS v_active_prompts CASCADE;

CREATE OR REPLACE VIEW v_active_prompts AS
SELECT
  c.id                AS config_id,
  c.stage,
  c.model,
  c.temperature,
  c.top_p,
  c.frequency_penalty,
  c.presence_penalty,
  c.max_tokens,
  c.wait_seconds,
  c.max_tool_iterations,
  c.buffer_debounce_ms,
  c.llm_timeout_ms,
  c.vision_timeout_ms,
  c.stt_timeout_ms,
  c.allowed_tools,
  c.helicone_cache,
  c.streaming,
  c.prompt_image,
  (
    SELECT string_agg(
      '## ' || topic || E'\n\n' || content,
      E'\n\n---\n\n' ORDER BY display_order
    )
    FROM agent_rules r
    WHERE r.status = 'active'
      AND (
        r.tipo = 'regras_gerais'
        OR r.tipo::text = c.stage::text
      )
  ) AS system_prompt
FROM agent_configs c
WHERE c.status = 'active';

COMMENT ON VIEW v_active_prompts IS
  'System prompt + todas configurações do stage ativo. Pipeline lê daqui.';

-- ----------------------------------------------------------------------------
-- Tabela de configuração GLOBAL (não por stage)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS global_config (
  key             text PRIMARY KEY,
  value           jsonb NOT NULL,
  description     text,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      uuid
);

COMMENT ON TABLE global_config IS
  'Configurações globais que se aplicam ao sistema todo (rate limits, alertas, etc).';

-- Seeds iniciais
INSERT INTO global_config (key, value, description) VALUES
  ('rate_limit.msgs_per_user_per_minute',  '20'::jsonb,
   'Máximo de msgs IN por user por minuto. Acima disso, dropa silenciosamente.'),
  ('rate_limit.cost_per_user_per_day_usd', '0.50'::jsonb,
   'Custo IA máximo por user/dia. Acima disso, agente responde com fallback.'),
  ('alerts.cost_24h_usd_threshold',        '5.00'::jsonb,
   'Dispara alerta se custo total 24h > este valor.'),
  ('alerts.latency_p95_ms_threshold',      '60000'::jsonb,
   'Dispara alerta se latency P95 nas últimas 100 msgs > este valor.'),
  ('alerts.tool_failure_rate_threshold',   '0.10'::jsonb,
   'Dispara alerta se taxa de erro de tools > 10% nas últimas 50 chamadas.'),
  ('tts.elevenlabs_stability',             '0.5'::jsonb,
   'ElevenLabs voice stability (0-1). Maior = voz consistente, menor = expressiva.'),
  ('tts.elevenlabs_similarity',            '1.0'::jsonb,
   'ElevenLabs similarity_boost (0-1).'),
  ('tts.elevenlabs_style',                 '1.0'::jsonb,
   'ElevenLabs style (0-1).'),
  ('tts.elevenlabs_speed',                 '1.0'::jsonb,
   'Velocidade da fala (0.7-1.2).'),
  ('tts.rewriter_enabled',                 'true'::jsonb,
   'Reescrever texto pra fala natural antes de TTS.')
ON CONFLICT (key) DO NOTHING;

-- Helper RPC pra ler/atualizar config global
CREATE OR REPLACE FUNCTION get_global_config(p_key text)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT value FROM global_config WHERE key = p_key;
$$;

CREATE OR REPLACE FUNCTION set_global_config(p_key text, p_value jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO global_config (key, value, updated_at)
  VALUES (p_key, p_value, now())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION get_global_config TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION set_global_config TO authenticated, service_role;
