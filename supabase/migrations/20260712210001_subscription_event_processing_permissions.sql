DO $permissions$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.claim_subscription_event(text, text, jsonb, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'REVOKE ALL ON FUNCTION public.finish_subscription_event(text, boolean, jsonb, text, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.claim_subscription_event(text, text, jsonb, timestamptz) TO service_role';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.finish_subscription_event(text, boolean, jsonb, text, timestamptz) TO service_role';
END;
$permissions$;
