DO $permissions$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.ingest_whatsapp_inbound(text, text, text, text, text, jsonb, timestamptz, timestamptz, integer, boolean) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.ingest_whatsapp_inbound(text, text, text, text, text, jsonb, timestamptz, timestamptz, integer, boolean) TO service_role';
  EXECUTE 'COMMENT ON FUNCTION public.ingest_whatsapp_inbound(text, text, text, text, text, jsonb, timestamptz, timestamptz, integer, boolean) IS ''Atomically persists and buffers an inbound WhatsApp message with retry-safe idempotency.''';
END;
$permissions$;
