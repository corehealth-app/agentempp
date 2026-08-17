DO $permissions$
BEGIN
  REVOKE ALL ON TABLE public.daily_gap_reminder_attempts FROM PUBLIC, anon, authenticated;
  GRANT SELECT, INSERT, UPDATE ON TABLE public.daily_gap_reminder_attempts TO service_role;

  EXECUTE 'REVOKE ALL ON FUNCTION public.claim_daily_gap_reminder(uuid, date, text, jsonb, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.claim_daily_gap_reminder(uuid, date, text, jsonb, timestamptz) TO service_role';
  EXECUTE 'REVOKE ALL ON FUNCTION public.finalize_daily_gap_reminder(uuid, text, text, text, text, timestamptz, integer, integer) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.finalize_daily_gap_reminder(uuid, text, text, text, text, timestamptz, integer, integer) TO service_role';
  EXECUTE 'REVOKE ALL ON FUNCTION public.fail_daily_gap_reminder(uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.fail_daily_gap_reminder(uuid, text, text, timestamptz) TO service_role';
END;
$permissions$;
