-- ============================================================================
-- Migration 0011: Admin extras
-- ============================================================================
-- Tabelas usadas pelo admin UI para configurar API keys, cron, persona, etc.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- service_credentials — API keys editáveis via admin
-- ----------------------------------------------------------------------------
-- Modelo: 1 row por (service, key_name).
-- Edge Functions e workers leem via cache em memória + invalidação on update.
-- Valores em texto puro com RLS estrita (apenas service_role e role admin).
-- TODO: migrar para pgsodium/Vault em fase posterior (requer plano Pro).
CREATE TABLE service_credentials (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service     text NOT NULL,                 -- 'openrouter' | 'groq' | 'elevenlabs' | 'cartesia' | 'meta_whatsapp' | 'stripe' | 'helicone' | 'sentry' | 'inngest'
  key_name    text NOT NULL,                 -- 'api_key' | 'voice_id' | 'webhook_secret' | etc
  value       text NOT NULL,
  notes       text,
  is_active   boolean NOT NULL DEFAULT true,
  last_tested_at timestamptz,
  last_test_result text,                     -- 'ok' | 'invalid' | 'error: ...'
  updated_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE(service, key_name)
);

CREATE INDEX idx_credentials_service ON service_credentials(service, is_active);

COMMENT ON TABLE service_credentials IS
  'Credenciais editáveis via admin UI. Substitui env vars em runtime quando disponível.';

-- ----------------------------------------------------------------------------
-- audit_log — todas as mudanças sensíveis no admin
-- ----------------------------------------------------------------------------
CREATE TABLE audit_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    uuid,
  actor_email text,
  action      text NOT NULL,                 -- 'credential.update' | 'rule.publish' | 'config.update' | etc
  entity      text NOT NULL,                 -- 'service_credentials' | 'agent_rules' | 'agent_configs' | 'feature_flags'
  entity_id   text,
  before      jsonb,
  after       jsonb,
  ip_address  text,
  user_agent  text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_actor ON audit_log(actor_id, created_at DESC);
CREATE INDEX idx_audit_entity ON audit_log(entity, entity_id, created_at DESC);
CREATE INDEX idx_audit_action ON audit_log(action, created_at DESC);

-- ----------------------------------------------------------------------------
-- View: cron_jobs_view (lista pg_cron jobs com último status)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_cron_jobs AS
SELECT
  j.jobid,
  j.jobname,
  j.schedule,
  j.command,
  j.active,
  j.database,
  j.username,
  (
    SELECT row_to_json(r)
    FROM (
      SELECT
        runid,
        status,
        return_message,
        start_time,
        end_time
      FROM cron.job_run_details
      WHERE jobid = j.jobid
      ORDER BY start_time DESC
      LIMIT 1
    ) r
  ) AS last_run
FROM cron.job j;

COMMENT ON VIEW v_cron_jobs IS 'Lista de jobs pg_cron com status da última execução.';

-- ----------------------------------------------------------------------------
-- Function: agent_kpis (dados pro dashboard)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION agent_kpis(days integer DEFAULT 7)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  WITH range_msgs AS (
    SELECT * FROM messages
    WHERE created_at >= now() - (days || ' days')::interval
  )
  SELECT jsonb_build_object(
    'period_days', days,
    'users_total', (SELECT count(*) FROM users WHERE status = 'active'),
    'users_active_period', (
      SELECT count(DISTINCT user_id) FROM range_msgs WHERE direction = 'in'
    ),
    'messages_in', (SELECT count(*) FROM range_msgs WHERE direction = 'in'),
    'messages_out', (SELECT count(*) FROM range_msgs WHERE direction = 'out'),
    'cost_usd_total', (
      SELECT COALESCE(SUM(cost_usd), 0)::numeric(12,4) FROM range_msgs WHERE cost_usd IS NOT NULL
    ),
    'avg_latency_ms', (
      SELECT COALESCE(AVG(latency_ms), 0)::int FROM range_msgs WHERE latency_ms IS NOT NULL
    ),
    'tools_called', (
      SELECT count(*) FROM tools_audit
      WHERE created_at >= now() - (days || ' days')::interval
    ),
    'tools_failed', (
      SELECT count(*) FROM tools_audit
      WHERE created_at >= now() - (days || ' days')::interval AND success = false
    ),
    'meals_logged', (
      SELECT count(*) FROM meal_logs
      WHERE created_at >= now() - (days || ' days')::interval
    ),
    'workouts_logged', (
      SELECT count(*) FROM workout_logs
      WHERE created_at >= now() - (days || ' days')::interval
    ),
    'subscriptions_active', (
      SELECT count(*) FROM subscriptions WHERE status IN ('active', 'trial')
    ),
    'top_models', (
      SELECT jsonb_agg(jsonb_build_object('model', model_used, 'calls', n))
      FROM (
        SELECT model_used, count(*) AS n FROM range_msgs
        WHERE model_used IS NOT NULL
        GROUP BY model_used
        ORDER BY n DESC LIMIT 5
      ) t
    )
  );
$$;

COMMENT ON FUNCTION agent_kpis IS 'KPIs agregados para o dashboard do admin.';

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
ALTER TABLE service_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Apenas admin role no JWT pode ler/editar credentials
CREATE POLICY credentials_admin ON service_credentials FOR ALL
  USING (auth.jwt() ->> 'role' = 'admin')
  WITH CHECK (auth.jwt() ->> 'role' = 'admin');

CREATE POLICY audit_admin_read ON audit_log FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('admin','editor','viewer'));

GRANT EXECUTE ON FUNCTION agent_kpis TO authenticated, service_role;
