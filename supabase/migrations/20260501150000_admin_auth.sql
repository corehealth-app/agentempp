-- ============================================================================
-- Migration 0012: Admin auth (admin_users + helper functions)
-- ============================================================================
-- Modelo simples: tabela `admin_users` com FK para auth.users(id).
-- Function `is_admin()` (SECURITY DEFINER) verifica se o user atual é admin.
-- Policies usam `is_admin()` em vez de checar JWT claim.
-- ============================================================================

CREATE TABLE admin_users (
  id          uuid PRIMARY KEY,
  email       text UNIQUE NOT NULL,
  name        text,
  role        text NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'editor', 'viewer')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_admin_users_email ON admin_users(email);

COMMENT ON TABLE admin_users IS
  'Usuários autorizados a acessar o painel admin. id = auth.users.id após login.';

-- ----------------------------------------------------------------------------
-- Helper: is_admin() — usada nas RLS policies
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS(
    SELECT 1 FROM admin_users
    WHERE id = auth.uid()
    AND role IN ('admin', 'editor', 'viewer')
  );
$$;

CREATE OR REPLACE FUNCTION admin_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM admin_users WHERE id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION is_admin TO authenticated;
GRANT EXECUTE ON FUNCTION admin_role TO authenticated;

-- ----------------------------------------------------------------------------
-- Substituir policies que usavam auth.jwt() ->> 'role' por is_admin()
-- ----------------------------------------------------------------------------

-- agent_rules
DROP POLICY IF EXISTS rules_read ON agent_rules;
DROP POLICY IF EXISTS rules_insert ON agent_rules;
DROP POLICY IF EXISTS rules_update ON agent_rules;
DROP POLICY IF EXISTS rules_publish ON agent_rules;

CREATE POLICY rules_admin_read ON agent_rules FOR SELECT USING (is_admin());
CREATE POLICY rules_admin_write ON agent_rules FOR INSERT WITH CHECK (
  admin_role() IN ('admin', 'editor')
);
CREATE POLICY rules_admin_update ON agent_rules FOR UPDATE USING (
  admin_role() IN ('admin', 'editor')
);

-- agent_configs
DROP POLICY IF EXISTS configs_read ON agent_configs;
DROP POLICY IF EXISTS configs_write ON agent_configs;

CREATE POLICY configs_admin_read ON agent_configs FOR SELECT USING (is_admin());
CREATE POLICY configs_admin_write ON agent_configs FOR ALL USING (admin_role() = 'admin');

-- versions (readonly except trigger)
DROP POLICY IF EXISTS rule_versions_read ON agent_rules_versions;
DROP POLICY IF EXISTS config_versions_read ON agent_configs_versions;

CREATE POLICY rule_versions_admin ON agent_rules_versions FOR SELECT USING (is_admin());
CREATE POLICY config_versions_admin ON agent_configs_versions FOR SELECT USING (is_admin());

-- feature_flags
DROP POLICY IF EXISTS flags_admin ON feature_flags;
DROP POLICY IF EXISTS flags_read ON feature_flags;

CREATE POLICY flags_admin_all ON feature_flags FOR ALL USING (admin_role() = 'admin');
CREATE POLICY flags_admin_read ON feature_flags FOR SELECT USING (is_admin());

-- service_credentials
DROP POLICY IF EXISTS credentials_admin ON service_credentials;
CREATE POLICY credentials_admin_all ON service_credentials FOR ALL USING (admin_role() = 'admin');

-- audit_log
DROP POLICY IF EXISTS audit_admin_read ON audit_log;
CREATE POLICY audit_admin_read ON audit_log FOR SELECT USING (is_admin());

-- Tabelas de domínio: admin pode ler tudo
DROP POLICY IF EXISTS users_admin_read ON users;
CREATE POLICY users_admin_read ON users FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS user_profiles_admin_read ON user_profiles;
CREATE POLICY user_profiles_admin_read ON user_profiles FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS user_progress_admin_read ON user_progress;
CREATE POLICY user_progress_admin_read ON user_progress FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS daily_snapshots_admin_read ON daily_snapshots;
CREATE POLICY daily_snapshots_admin_read ON daily_snapshots FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS meal_logs_admin_read ON meal_logs;
CREATE POLICY meal_logs_admin_read ON meal_logs FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS workout_logs_admin_read ON workout_logs;
CREATE POLICY workout_logs_admin_read ON workout_logs FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS messages_admin_read ON messages;
CREATE POLICY messages_admin_read ON messages FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS llm_evaluations_admin_read ON llm_evaluations;
CREATE POLICY llm_evaluations_admin_read ON llm_evaluations FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS tools_audit_admin_read ON tools_audit;
CREATE POLICY tools_audit_admin_read ON tools_audit FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS subscriptions_admin_read ON subscriptions;
CREATE POLICY subscriptions_admin_read ON subscriptions FOR SELECT USING (is_admin());

-- admin_users self
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY admin_users_self_read ON admin_users FOR SELECT USING (id = auth.uid() OR is_admin());
CREATE POLICY admin_users_admin_write ON admin_users FOR ALL USING (admin_role() = 'admin');

-- ----------------------------------------------------------------------------
-- Seed inicial: o primeiro admin é gestao@excluvia.com.br
-- (ele será associado ao auth.users após primeiro login via magic link)
-- ----------------------------------------------------------------------------
-- Não inserimos id ainda; um trigger ou Edge Function preenche no signup.
-- Por ora, o admin entra direto via Supabase dashboard ou inserimos manualmente.

-- ----------------------------------------------------------------------------
-- Trigger: ao criar/editar admin_users, registra audit_log
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_admin_users()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO audit_log(actor_id, action, entity, entity_id, before, after)
  VALUES (
    auth.uid(),
    TG_OP,
    'admin_users',
    COALESCE(NEW.id::text, OLD.id::text),
    CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE NULL END,
    CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_audit_admin_users
  AFTER INSERT OR UPDATE OR DELETE ON admin_users
  FOR EACH ROW EXECUTE FUNCTION audit_admin_users();
