-- ============================================================================
-- WhatsApp delivery status lookup
-- ============================================================================
-- webhook-whatsapp atualiza mensagens OUT pelo provider_message_id recebido da
-- Meta. O índice antigo de provider_message_id foi removido quando criamos a
-- unique parcial de mensagens IN, deixando esse caminho sem índice compatível.

CREATE INDEX IF NOT EXISTS idx_messages_whatsapp_status_lookup
  ON public.messages(provider, provider_message_id)
  WHERE provider_message_id IS NOT NULL
    AND provider = 'whatsapp_cloud'
    AND direction = 'out';
