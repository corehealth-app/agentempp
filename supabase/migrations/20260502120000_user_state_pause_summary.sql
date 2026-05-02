-- ============================================================================
-- Migration 0016: estado de pausa + resumo + last_active + idx idempotência
-- ============================================================================
-- - users.metadata é jsonb genérico; pausa fica em metadata.paused_until
-- - users.summary: resumo periódico do paciente (gerado por cron LLM)
-- - users.last_active_at: timestamp da última msg IN
-- - messages: índice único em (provider, provider_message_id) — antes só
--   tinha não-único, permitia duplicatas em retry de webhook
-- ============================================================================

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS summary             text,
  ADD COLUMN IF NOT EXISTS summary_updated_at  timestamptz,
  ADD COLUMN IF NOT EXISTS last_active_at      timestamptz;

COMMENT ON COLUMN users.summary IS
  'Resumo da relação com o paciente, regenerado periodicamente. Vai no system prompt do LLM em vez de carregar 30 msgs.';
COMMENT ON COLUMN users.last_active_at IS
  'Última msg IN recebida. Atualizado no insert via trigger.';

-- Trigger pra manter last_active_at fresh
CREATE OR REPLACE FUNCTION update_user_last_active()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.direction = 'in' THEN
    UPDATE users
    SET last_active_at = NEW.created_at
    WHERE id = NEW.user_id
      AND (last_active_at IS NULL OR NEW.created_at > last_active_at);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_update_last_active ON messages;
CREATE TRIGGER trg_messages_update_last_active
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_user_last_active();

-- Backfill: popular last_active_at com a última msg in de cada user
UPDATE users u
SET last_active_at = sub.last_in
FROM (
  SELECT user_id, MAX(created_at) AS last_in
  FROM messages
  WHERE direction = 'in'
  GROUP BY user_id
) sub
WHERE u.id = sub.user_id;

-- Índice único pra idempotência (antes era só índice comum)
DROP INDEX IF EXISTS idx_messages_provider_id;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_messages_provider_message_id
  ON messages(provider, provider_message_id)
  WHERE provider_message_id IS NOT NULL AND direction = 'in';

COMMENT ON INDEX uniq_messages_provider_message_id IS
  'Garante que cada msg IN do provider seja persistida 1 vez só. OUT podem repetir id (sendHumanized).';

-- Helper SQL: pausar agente por N dias
CREATE OR REPLACE FUNCTION pause_user(p_user_id uuid, p_days integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE users
  SET metadata = COALESCE(metadata, '{}'::jsonb) ||
                 jsonb_build_object(
                   'paused_until', (now() + (p_days || ' days')::interval)::text,
                   'paused_at', now()::text
                 ),
      updated_at = now()
  WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION resume_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE users
  SET metadata = (COALESCE(metadata, '{}'::jsonb) - 'paused_until' - 'paused_at'),
      updated_at = now()
  WHERE id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION pause_user TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION resume_user TO authenticated, service_role;

-- Atualiza engagement_eligible_users pra respeitar paused_until
CREATE OR REPLACE FUNCTION engagement_eligible_users(
  p_quiet_hours_min integer DEFAULT 4,
  p_window_label text DEFAULT 'manha'
)
RETURNS TABLE (
  user_id uuid,
  wpp text,
  name text,
  timezone text,
  current_protocol protocol_enum,
  hours_since_last_in numeric
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    u.id,
    u.wpp,
    u.name,
    u.timezone,
    p.current_protocol,
    EXTRACT(epoch FROM (now() - COALESCE(u.last_active_at, u.created_at)))/3600 AS hours_since_last_in
  FROM users u
  LEFT JOIN user_profiles p ON p.user_id = u.id
  WHERE u.status = 'active'
    AND p.onboarding_completed = true
    AND (
      u.metadata->>'paused_until' IS NULL
      OR (u.metadata->>'paused_until')::timestamptz < now()
    )
    AND COALESCE(u.last_active_at, u.created_at) < now() - (p_quiet_hours_min || ' hours')::interval;
$$;
