-- Provider message IDs identify both inbound and outbound WhatsApp messages.
-- Build the broader index before removing the inbound-only predecessor so
-- retries remain protected throughout the migration.

CREATE UNIQUE INDEX IF NOT EXISTS uniq_messages_provider_message_id_all
  ON public.messages(provider, provider_message_id)
  WHERE provider_message_id IS NOT NULL;

DROP INDEX IF EXISTS public.uniq_messages_provider_message_id;

COMMENT ON INDEX public.uniq_messages_provider_message_id_all IS
  'Idempotency for inbound and outbound provider messages. Each WhatsApp message id is globally stable per provider.';
