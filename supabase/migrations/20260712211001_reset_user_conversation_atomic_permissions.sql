REVOKE ALL ON FUNCTION public.reset_user_conversation_atomic(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reset_user_conversation_atomic(uuid)
  TO service_role;
