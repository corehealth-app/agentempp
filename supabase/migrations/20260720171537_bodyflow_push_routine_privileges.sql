DO $$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.upsert_mobile_device(uuid, text, text, text) FROM PUBLIC, anon, authenticated';
  EXECUTE 'REVOKE ALL ON FUNCTION public.deactivate_mobile_device(uuid, uuid) FROM PUBLIC, anon, authenticated';
  EXECUTE 'REVOKE ALL ON FUNCTION public.record_hydration_atomic(uuid, date, integer, text, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'REVOKE ALL ON FUNCTION public.record_routine_adherence_atomic(uuid, uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'REVOKE ALL ON FUNCTION public.claim_reminder_event(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated';

  EXECUTE 'GRANT EXECUTE ON FUNCTION public.upsert_mobile_device(uuid, text, text, text) TO service_role';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.deactivate_mobile_device(uuid, uuid) TO service_role';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.record_hydration_atomic(uuid, date, integer, text, timestamptz) TO service_role';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.record_routine_adherence_atomic(uuid, uuid, text, text, timestamptz) TO service_role';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.claim_reminder_event(uuid, timestamptz, timestamptz) TO service_role';

  EXECUTE 'COMMENT ON TABLE public.mobile_devices IS ''Private iOS installation registry. APNs token and generated hash are backend-only columns.''';
  EXECUTE 'COMMENT ON TABLE public.notification_deliveries IS ''Backend-only APNs outbox. This foundation queues per-device deliveries and never marks them sent.''';
END;
$$;
