REVOKE ALL ON FUNCTION public.list_due_reminder_rules(timestamptz, integer, integer)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.list_due_reminder_rules(timestamptz, integer, integer)
TO service_role;

COMMENT ON FUNCTION public.list_due_reminder_rules(timestamptz, integer, integer) IS
  'Backend-only discovery of due reminder rule IDs and UTC instants. Returns no user, device, token, or message data.';
