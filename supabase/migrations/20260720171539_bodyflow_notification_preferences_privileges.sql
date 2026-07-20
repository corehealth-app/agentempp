DO $$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.update_notification_preferences_atomic(uuid, jsonb) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.update_notification_preferences_atomic(uuid, jsonb) TO service_role';
END;
$$;
