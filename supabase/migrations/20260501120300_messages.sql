-- ============================================================================
-- Migration 0004: Messages, buffer, idempotency, embeddings
-- ============================================================================
-- Camada de conversação com WhatsApp.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- messages (input e output)
-- ----------------------------------------------------------------------------
CREATE TABLE messages (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  direction             direction_enum NOT NULL,
  role                  msg_role_enum NOT NULL,
  content_type          content_type_enum NOT NULL,
  content               text,
  media_url             text,
  media_storage_path    text,

  -- Provider metadata
  provider              text NOT NULL DEFAULT 'whatsapp_cloud',
  provider_message_id   text,
  raw_payload           jsonb,
  intent                text,

  -- LLM specifics (apenas em outbound do agente)
  agent_stage           text,
  model_used            text,
  prompt_tokens         integer,
  completion_tokens     integer,
  cost_usd              numeric(10,6),
  latency_ms            integer,

  -- Delivery status (Cloud API webhooks de status)
  delivery_status       text,
  delivery_error        jsonb,

  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_user_created ON messages(user_id, created_at DESC);
CREATE INDEX idx_messages_provider_id ON messages(provider_message_id) WHERE provider_message_id IS NOT NULL;
CREATE INDEX idx_messages_direction_created ON messages(direction, created_at DESC);

COMMENT ON COLUMN messages.delivery_status IS 'sent | delivered | read | failed';

-- ----------------------------------------------------------------------------
-- processed_messages (idempotência por provider_message_id)
-- ----------------------------------------------------------------------------
CREATE TABLE processed_messages (
  provider_message_id  text PRIMARY KEY,
  processed_at         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE processed_messages IS 'Garante processamento único de cada mensagem do WhatsApp. TTL via cron.';

-- ----------------------------------------------------------------------------
-- message_embeddings (memória semântica)
-- ----------------------------------------------------------------------------
CREATE TABLE message_embeddings (
  message_id  uuid PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
  embedding   vector(1024),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_msg_emb_hnsw ON message_embeddings
  USING hnsw (embedding vector_cosine_ops);

COMMENT ON TABLE message_embeddings IS 'Embeddings de mensagens para busca semântica. Dimensões: 1024 (voyage-3-lite).';

-- ----------------------------------------------------------------------------
-- message_buffer (debounce 10s para agregar mensagens fragmentadas)
-- ----------------------------------------------------------------------------
CREATE UNLOGGED TABLE message_buffer (
  user_id      uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  messages     jsonb NOT NULL DEFAULT '[]'::jsonb,
  buffered_at  timestamptz NOT NULL DEFAULT now(),
  flush_after  timestamptz NOT NULL
);

CREATE INDEX idx_buffer_flush ON message_buffer(flush_after);

COMMENT ON TABLE message_buffer IS 'Buffer transiente. UNLOGGED para performance. Substitui Upstash no Nível 2.';
