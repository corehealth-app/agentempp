REVOKE ALL ON TABLE
  public.notification_preferences,
  public.reminder_rules,
  public.routine_items,
  public.routine_adherence_logs,
  public.reminder_events,
  public.notification_deliveries,
  public.legal_documents,
  public.user_legal_acceptances
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE private.routine_mutation_receipts
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.notification_preferences TO authenticated;
GRANT SELECT ON TABLE public.reminder_rules TO authenticated;
GRANT SELECT ON TABLE public.routine_items TO authenticated;
GRANT SELECT ON TABLE public.routine_adherence_logs TO authenticated;
GRANT SELECT ON TABLE public.user_legal_acceptances TO authenticated;

GRANT SELECT, INSERT, UPDATE ON TABLE
  public.notification_preferences,
  public.reminder_rules,
  public.routine_items,
  public.reminder_events,
  public.notification_deliveries
TO service_role;

GRANT SELECT, INSERT ON TABLE
  public.routine_adherence_logs,
  public.legal_documents,
  public.user_legal_acceptances
TO service_role;

GRANT USAGE ON SCHEMA private TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE private.routine_mutation_receipts TO service_role;

REVOKE ALL ON FUNCTION private.reject_bodyflow_routine_immutable_mutation()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enforce_routine_mutation_receipt_result_keys()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enforce_notification_delivery_routine_preview()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enforce_routine_adherence_correction()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enforce_reminder_event_routine_action()
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION private.reject_bodyflow_routine_immutable_mutation() TO service_role;
GRANT EXECUTE ON FUNCTION private.enforce_routine_mutation_receipt_result_keys() TO service_role;
GRANT EXECUTE ON FUNCTION private.enforce_notification_delivery_routine_preview() TO service_role;
GRANT EXECUTE ON FUNCTION private.enforce_routine_adherence_correction() TO service_role;
GRANT EXECUTE ON FUNCTION private.enforce_reminder_event_routine_action() TO service_role;
