-- ============================================================================
-- buffer_append_msg — GREATEST(flush_after) pra preservar extensão do gate
-- vision-inflight (audit 2026-06-24, Bug #2 review H4)
-- ============================================================================
-- Cenário (audit 06-24, review H4 do Bug #2): o vision-inflight gate em
-- buffer-listener.ts (Layer 4) faz `UPDATE message_buffer SET flush_after =
-- now()+20s` pra esperar vision do mesmo user terminar antes de flushar caption
-- tardio. Mas se paciente manda nova msg durante esses 20s, a RPC
-- buffer_append_msg sobrescrevia incondicionalmente `flush_after = now()+8s`
-- (debounce padrão), apagando a extensão e fazendo o flush rodar mais cedo do
-- que o gate pretendia.
--
-- Fix: usar `GREATEST(message_buffer.flush_after, EXCLUDED.flush_after)` —
-- novas msgs JAMAIS encurtam um debounce em andamento. Se o gate estendeu pra
-- now+20s, qualquer append durante os 20s mantém os 20s. Se debounce normal de
-- 8s estiver ativo e msg nova chega aos 2s (faltam 6s), GREATEST mantém os 8s
-- da msg nova (8s > 6s).
--
-- Defesa em profundidade: combina com anti-loop por product_events count em
-- buffer-listener.ts (limite 1 extensão/60s) pra blindar Layer 4 completamente.
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
    flush_after = GREATEST(message_buffer.flush_after, EXCLUDED.flush_after)
  RETURNING * INTO v_buffer;

  RETURN jsonb_build_object(
    'flush_after', v_buffer.flush_after,
    'count', jsonb_array_length(v_buffer.messages)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION buffer_append_msg(uuid, jsonb, int) TO authenticated, service_role;

COMMENT ON FUNCTION buffer_append_msg IS
  'Append atômico de msg no buffer com GREATEST(flush_after) — preserva extensões de debounce do vision-inflight gate (audit 2026-06-24).';
