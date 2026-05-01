-- ============================================================================
-- Migration 0009: Row Level Security
-- ============================================================================
-- Princípio: Edge Functions usam service_role (bypass RLS). Admin UI usa JWT
-- com claim 'role' customizado: 'admin' | 'editor' | 'viewer'.
-- Quando expusermos API direta para usuários finais, RLS por user_id entra.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Tabelas de domínio (somente admin/editor/viewer leem; mutação por service_role)
-- ----------------------------------------------------------------------------
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE reevaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_embeddings ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE tools_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE llm_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_events ENABLE ROW LEVEL SECURITY;

-- Admin: leitura total
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'users','user_profiles','user_progress','daily_snapshots','meal_logs',
    'workout_logs','reevaluations','messages','message_embeddings',
    'subscriptions','subscription_events','tools_audit','llm_evaluations',
    'product_events'
  ])
  LOOP
    EXECUTE format($f$
      CREATE POLICY "%I_admin_read" ON %I FOR SELECT
        USING (auth.jwt() ->> 'role' IN ('admin','editor','viewer'))
    $f$, t, t);
  END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- Agent rules / configs
-- ----------------------------------------------------------------------------
ALTER TABLE agent_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_rules_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_configs_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY rules_read ON agent_rules FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('admin','editor','viewer'));

CREATE POLICY rules_insert ON agent_rules FOR INSERT
  WITH CHECK (auth.jwt() ->> 'role' IN ('admin','editor'));

CREATE POLICY rules_update ON agent_rules FOR UPDATE
  USING (auth.jwt() ->> 'role' IN ('admin','editor'));

-- Apenas admin pode publicar/arquivar (mudar status)
CREATE POLICY rules_publish ON agent_rules FOR UPDATE
  USING (
    auth.jwt() ->> 'role' = 'admin'
    OR (auth.jwt() ->> 'role' = 'editor' AND status = 'draft')
  )
  WITH CHECK (
    auth.jwt() ->> 'role' = 'admin'
    OR (auth.jwt() ->> 'role' = 'editor' AND status IN ('draft', 'testing'))
  );

CREATE POLICY configs_read ON agent_configs FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('admin','editor','viewer'));

CREATE POLICY configs_write ON agent_configs FOR ALL
  USING (auth.jwt() ->> 'role' = 'admin')
  WITH CHECK (auth.jwt() ->> 'role' = 'admin');

CREATE POLICY rule_versions_read ON agent_rules_versions FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('admin','editor','viewer'));

CREATE POLICY config_versions_read ON agent_configs_versions FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('admin','editor','viewer'));

CREATE POLICY flags_admin ON feature_flags FOR ALL
  USING (auth.jwt() ->> 'role' = 'admin')
  WITH CHECK (auth.jwt() ->> 'role' = 'admin');

CREATE POLICY flags_read ON feature_flags FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('admin','editor','viewer'));

-- ----------------------------------------------------------------------------
-- Cache & reference (food_db público para read; tts_cache só service)
-- ----------------------------------------------------------------------------
ALTER TABLE food_db ENABLE ROW LEVEL SECURITY;
ALTER TABLE tts_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_phone_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE processed_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_buffer ENABLE ROW LEVEL SECURITY;

CREATE POLICY food_read ON food_db FOR SELECT USING (true);

CREATE POLICY tts_admin_read ON tts_cache FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('admin','editor','viewer'));

CREATE POLICY wa_status_admin ON whatsapp_phone_status FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('admin','editor','viewer'));

-- processed_messages e message_buffer: nunca expostos via API. Service only.
