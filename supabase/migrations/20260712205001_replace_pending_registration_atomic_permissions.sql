REVOKE ALL ON FUNCTION public.replace_pending_registration_atomic(uuid, jsonb, timestamptz, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.replace_pending_registration_atomic(uuid, jsonb, timestamptz, text)
  TO service_role;

COMMENT ON FUNCTION public.replace_pending_registration_atomic(uuid, jsonb, timestamptz, text) IS
  'Atomically cancels open proposals and creates one idempotent pending registration.';

