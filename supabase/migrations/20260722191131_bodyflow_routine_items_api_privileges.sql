REVOKE ALL ON FUNCTION private.routine_user_timezone(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.canonicalize_routine_schedules(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.routine_same_local_date(uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.derive_routine_occurrence_key(uuid, timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.lock_routine_occurrence(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.lock_routine_item(uuid, uuid, text, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.read_routine_mutation_receipt(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.write_routine_mutation_receipt(uuid, text, text, text, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.assert_current_medication_legal_acceptance(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION private.routine_user_timezone(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION private.canonicalize_routine_schedules(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION private.routine_same_local_date(uuid, timestamptz, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION private.derive_routine_occurrence_key(uuid, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION private.lock_routine_occurrence(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION private.lock_routine_item(uuid, uuid, text, boolean)
  TO service_role;
GRANT EXECUTE ON FUNCTION private.read_routine_mutation_receipt(uuid, text, text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION private.write_routine_mutation_receipt(
  uuid, text, text, text, jsonb
) TO service_role;
GRANT EXECUTE ON FUNCTION private.assert_current_medication_legal_acceptance(uuid)
  TO service_role;

REVOKE ALL ON FUNCTION public.create_mobile_routine_item(uuid, text, jsonb, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.update_mobile_routine_item(
  uuid, uuid, integer, jsonb, text, text
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.archive_mobile_routine_item(uuid, uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.list_mobile_routine_items(uuid, text, boolean, timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.list_mobile_routine_history(
  uuid, uuid, text, integer, timestamptz, uuid
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_routine_occurrence_action_atomic(
  uuid, uuid, text, uuid, timestamptz, text, timestamptz, timestamptz, text
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_mobile_legal_document(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.accept_mobile_legal_document(uuid, text, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.create_mobile_routine_item(
  uuid, text, jsonb, text, text
) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_mobile_routine_item(
  uuid, uuid, integer, jsonb, text, text
) TO service_role;
GRANT EXECUTE ON FUNCTION public.archive_mobile_routine_item(uuid, uuid, text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.list_mobile_routine_items(
  uuid, text, boolean, timestamptz
) TO service_role;
GRANT EXECUTE ON FUNCTION public.list_mobile_routine_history(
  uuid, uuid, text, integer, timestamptz, uuid
) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_routine_occurrence_action_atomic(
  uuid, uuid, text, uuid, timestamptz, text, timestamptz, timestamptz, text
) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_legal_document(uuid, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.accept_mobile_legal_document(
  uuid, text, text, text, text
) TO service_role;
