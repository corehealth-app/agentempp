-- ============================================================================
-- Idempotência em meal_logs e workout_logs via raw_provider_message_id
-- ============================================================================
-- Bug: registra_refeicao chamada 2x pela mesma mensagem (retry de Inngest,
-- LLM emitindo duas tool calls iguais) duplicava entries em meal_logs E
-- chamava snapshot_add_meal 2x → snapshot duplicado.
--
-- Fix: nova coluna text raw_provider_message_id (do WhatsApp wamid.HBgN…)
-- + UNIQUE composite (user_id, raw_provider_message_id, food_name) onde
-- not null. Tools insertam com ON CONFLICT DO NOTHING; só atualizam
-- snapshot quando insert teve sucesso.
-- ============================================================================

ALTER TABLE meal_logs
  ADD COLUMN IF NOT EXISTS raw_provider_message_id text;

ALTER TABLE workout_logs
  ADD COLUMN IF NOT EXISTS raw_provider_message_id text;

-- Único composite só quando msg_id está presente (preserva backfills/null)
CREATE UNIQUE INDEX IF NOT EXISTS uniq_meal_logs_provider_msg
  ON meal_logs (user_id, raw_provider_message_id, food_name)
  WHERE raw_provider_message_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_workout_logs_provider_msg
  ON workout_logs (user_id, raw_provider_message_id, workout_type)
  WHERE raw_provider_message_id IS NOT NULL;

COMMENT ON COLUMN meal_logs.raw_provider_message_id IS
  'provider_message_id (text) da mensagem que originou o log. Usado pra dedup em retry de Inngest. UNIQUE composite com food_name evita dupla contagem.';

COMMENT ON COLUMN workout_logs.raw_provider_message_id IS
  'provider_message_id (text) da mensagem que originou o log. Usado pra dedup em retry de Inngest.';
