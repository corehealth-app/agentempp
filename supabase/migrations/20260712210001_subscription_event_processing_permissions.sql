REVOKE ALL ON FUNCTION public.claim_subscription_event(text, text, jsonb, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_subscription_event(text, boolean, jsonb, text, timestamptz)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_subscription_event(text, text, jsonb, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_subscription_event(text, boolean, jsonb, text, timestamptz)
  TO service_role;
