-- ============================================================================
-- Migration 0019: Inbox observability — tags, notes, message review flags
-- ============================================================================
-- Habilita ferramentas de observabilidade/curadoria pra um SaaS de agente
-- automatizado. Admin não responde — apenas observa, marca casos, anota.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- users: tags + admin notes (curadoria)
-- ----------------------------------------------------------------------------
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS tags         text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS admin_notes  text;

CREATE INDEX IF NOT EXISTS idx_users_tags ON users USING GIN (tags);

COMMENT ON COLUMN users.tags IS
  'Labels do admin pra curadoria: alucinou, caso-bom, precisa-rule, vip, etc.';
COMMENT ON COLUMN users.admin_notes IS
  'Anotações livres do admin sobre o paciente.';

-- ----------------------------------------------------------------------------
-- messages.review_flag — marca turnos de OUT pra training/eval
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'review_flag_enum') THEN
    CREATE TYPE review_flag_enum AS ENUM (
      'hallucination',  -- agente inventou (foto, dado, fato)
      'great_response', -- exemplo bom pra eval/training
      'needs_review',   -- olhar com calma depois
      'wrong_tool',     -- chamou tool errada ou não chamou quando devia
      'tone_off',       -- tom errado (robotizado, frio, etc)
      'too_long'        -- resposta longa demais
    );
  END IF;
END $$;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS review_flag         review_flag_enum,
  ADD COLUMN IF NOT EXISTS review_flagged_by   uuid REFERENCES admin_users(id),
  ADD COLUMN IF NOT EXISTS review_flagged_at   timestamptz,
  ADD COLUMN IF NOT EXISTS review_note         text;

CREATE INDEX IF NOT EXISTS idx_messages_review_flag
  ON messages(review_flag, created_at DESC) WHERE review_flag IS NOT NULL;

COMMENT ON COLUMN messages.review_flag IS
  'Flag do admin sobre qualidade da OUT do agente. Vai pra eval set.';

-- ----------------------------------------------------------------------------
-- RPC: tag_user / untag_user
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tag_user(p_user_id uuid, p_tag text)
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tags text[];
BEGIN
  UPDATE users
  SET tags = ARRAY(
    SELECT DISTINCT unnest(COALESCE(tags, '{}') || ARRAY[p_tag])
  ),
  updated_at = now()
  WHERE id = p_user_id
  RETURNING tags INTO v_tags;
  RETURN v_tags;
END;
$$;

CREATE OR REPLACE FUNCTION untag_user(p_user_id uuid, p_tag text)
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tags text[];
BEGIN
  UPDATE users
  SET tags = array_remove(COALESCE(tags, '{}'), p_tag),
      updated_at = now()
  WHERE id = p_user_id
  RETURNING tags INTO v_tags;
  RETURN v_tags;
END;
$$;

GRANT EXECUTE ON FUNCTION tag_user TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION untag_user TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- RPC: search_messages — busca textual em messages.content
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION search_messages(p_query text, p_limit integer DEFAULT 30)
RETURNS TABLE (
  id            uuid,
  user_id       uuid,
  user_name     text,
  user_wpp      text,
  direction     text,
  content       text,
  agent_stage   text,
  created_at    timestamptz,
  rank          real
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    m.id,
    m.user_id,
    u.name AS user_name,
    u.wpp AS user_wpp,
    m.direction::text,
    m.content,
    m.agent_stage,
    m.created_at,
    similarity(m.content, p_query) AS rank
  FROM messages m
  JOIN users u ON u.id = m.user_id
  WHERE m.content IS NOT NULL
    AND (
      m.content ILIKE '%' || p_query || '%'
      OR similarity(m.content, p_query) > 0.2
    )
  ORDER BY rank DESC, m.created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION search_messages TO authenticated, service_role;

COMMENT ON FUNCTION search_messages IS
  'Busca em messages.content por substring + similarity (pg_trgm). Retorna user info junto.';
