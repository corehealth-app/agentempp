-- ============================================================================
-- Migration 0005: Agent rules and configs (substitui Notion)
-- ============================================================================
-- Configuração dos sub-agentes + regras de comportamento, com versionamento
-- imutável via trigger.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- agent_configs (6 sub-agentes)
-- ----------------------------------------------------------------------------
CREATE TABLE agent_configs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stage             agent_stage NOT NULL,
  name              text NOT NULL,
  version           text NOT NULL,
  model             text NOT NULL,
  temperature       numeric(3,2) NOT NULL CHECK (temperature BETWEEN 0 AND 2),
  max_tokens        integer NOT NULL CHECK (max_tokens > 0),
  wait_seconds      integer NOT NULL DEFAULT 10 CHECK (wait_seconds >= 0),
  prompt_image      text,
  status            config_status NOT NULL DEFAULT 'draft',
  rollout_percent   smallint NOT NULL DEFAULT 0 CHECK (rollout_percent BETWEEN 0 AND 100),
  notes             text,
  created_by        uuid,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  -- Garante apenas 1 config 'active' por stage
  EXCLUDE USING btree (stage WITH =) WHERE (status = 'active')
);

CREATE INDEX idx_configs_active ON agent_configs(stage) WHERE status = 'active';

COMMENT ON TABLE agent_configs IS 'Configuração de cada sub-agente (modelo, temperature, max_tokens, etc).';

-- ----------------------------------------------------------------------------
-- agent_rules (88+ regras de comportamento)
-- ----------------------------------------------------------------------------
CREATE TABLE agent_rules (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic           text NOT NULL,
  slug            text NOT NULL UNIQUE,
  tipo            rule_tipo NOT NULL,
  content         text NOT NULL,
  content_tsv     tsvector GENERATED ALWAYS AS (to_tsvector('portuguese', content)) STORED,
  display_order   integer NOT NULL DEFAULT 0,
  status          config_status NOT NULL DEFAULT 'draft',
  token_estimate  integer,
  created_by      uuid,
  updated_by      uuid,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_rules_search ON agent_rules USING gin(content_tsv);
CREATE INDEX idx_rules_active ON agent_rules(tipo, display_order) WHERE status = 'active';
CREATE INDEX idx_rules_slug ON agent_rules(slug);

COMMENT ON TABLE agent_rules IS 'Regras de comportamento que compõem o system prompt.';

-- ----------------------------------------------------------------------------
-- Versionamento imutável (ADR-008)
-- ----------------------------------------------------------------------------
CREATE TABLE agent_rules_versions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id       uuid NOT NULL REFERENCES agent_rules(id) ON DELETE CASCADE,
  version_num   integer NOT NULL,
  topic         text NOT NULL,
  tipo          rule_tipo NOT NULL,
  content       text NOT NULL,
  status        config_status NOT NULL,
  change_reason text,
  changed_by    uuid,
  changed_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE(rule_id, version_num)
);

CREATE INDEX idx_rule_versions_rule ON agent_rules_versions(rule_id, version_num DESC);

CREATE OR REPLACE FUNCTION snapshot_rule_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_v integer;
BEGIN
  SELECT COALESCE(MAX(version_num), 0) + 1
    INTO next_v
    FROM agent_rules_versions
   WHERE rule_id = NEW.id;

  INSERT INTO agent_rules_versions(
    rule_id, version_num, topic, tipo, content, status, changed_by
  ) VALUES (
    NEW.id, next_v, NEW.topic, NEW.tipo, NEW.content, NEW.status, NEW.updated_by
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_rules_version
  AFTER INSERT OR UPDATE OF content, status ON agent_rules
  FOR EACH ROW EXECUTE FUNCTION snapshot_rule_version();

CREATE TABLE agent_configs_versions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  config_id     uuid NOT NULL REFERENCES agent_configs(id) ON DELETE CASCADE,
  version_num   integer NOT NULL,
  snapshot      jsonb NOT NULL,
  change_reason text,
  changed_by    uuid,
  changed_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE(config_id, version_num)
);

CREATE INDEX idx_config_versions_config ON agent_configs_versions(config_id, version_num DESC);

CREATE OR REPLACE FUNCTION snapshot_config_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_v integer;
BEGIN
  SELECT COALESCE(MAX(version_num), 0) + 1
    INTO next_v
    FROM agent_configs_versions
   WHERE config_id = NEW.id;

  INSERT INTO agent_configs_versions(
    config_id, version_num, snapshot, changed_by
  ) VALUES (
    NEW.id, next_v, to_jsonb(NEW.*), NEW.created_by
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_configs_version
  AFTER INSERT OR UPDATE ON agent_configs
  FOR EACH ROW EXECUTE FUNCTION snapshot_config_version();

-- ----------------------------------------------------------------------------
-- View consumida em runtime: prompt já montado por stage
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_active_prompts AS
SELECT
  c.stage,
  c.model,
  c.temperature,
  c.max_tokens,
  c.wait_seconds,
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

COMMENT ON VIEW v_active_prompts IS 'System prompt montado dinamicamente: regras gerais + regras do stage.';

-- ----------------------------------------------------------------------------
-- Feature flags
-- ----------------------------------------------------------------------------
CREATE TABLE feature_flags (
  key             text PRIMARY KEY,
  value           jsonb NOT NULL,
  rollout_percent smallint NOT NULL DEFAULT 100 CHECK (rollout_percent BETWEEN 0 AND 100),
  user_allowlist  uuid[] NOT NULL DEFAULT '{}',
  user_blocklist  uuid[] NOT NULL DEFAULT '{}',
  description     text,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE feature_flags IS 'Feature flags para rollout gradual. Lidas em runtime, cacheadas 60s.';
