-- ============================================================================
-- buffer_append_msg — INSERT atômico no message_buffer (sem race condition)
-- ============================================================================
-- Bug: webhook-whatsapp fazia read-then-write no message_buffer.
-- Quando paciente mandava 3 fotos em sequência, os 3 webhooks paralelos
-- liam buffer.messages ao mesmo tempo, calculavam novo array sobre o
-- mesmo "old" — última escrita sobrescrevia as anteriores.
-- Resultado: agente recebia 1 ou 2 fotos, não as 3.
--
-- Fix: RPC com INSERT...ON CONFLICT DO UPDATE usando jsonb COALESCE
-- + jsonb || (concatenação atomica) — sem read intermediário.
-- ============================================================================

CREATE OR REPLACE FUNCTION buffer_append_msg(
  p_user_id     uuid,
  p_msg_entry   jsonb,
  p_debounce_ms int DEFAULT 8000
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_flush_after timestamptz := now() + make_interval(secs => p_debounce_ms / 1000.0);
  v_buffer message_buffer;
BEGIN
  INSERT INTO message_buffer (user_id, messages, buffered_at, flush_after)
  VALUES (p_user_id, jsonb_build_array(p_msg_entry), now(), v_flush_after)
  ON CONFLICT (user_id) DO UPDATE SET
    messages    = COALESCE(message_buffer.messages, '[]'::jsonb) || EXCLUDED.messages,
    buffered_at = EXCLUDED.buffered_at,
    flush_after = EXCLUDED.flush_after
  RETURNING * INTO v_buffer;

  RETURN jsonb_build_object(
    'flush_after', v_buffer.flush_after,
    'count', jsonb_array_length(v_buffer.messages)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION buffer_append_msg(uuid, jsonb, int) TO authenticated, service_role;

COMMENT ON FUNCTION buffer_append_msg IS
  'Append atômico de msg no buffer. Resolve race condition quando webhook recebe múltiplas msgs paralelas (ex: paciente manda 3 fotos rápidas).';
