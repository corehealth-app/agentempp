REVOKE ALL ON FUNCTION public.advance_reevaluation_schedule(uuid, date)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.advance_reevaluation_schedule(uuid, date)
  TO service_role;

COMMENT ON FUNCTION public.advance_reevaluation_schedule(uuid, date) IS
  'Atomically bootstraps or advances the 14-day reevaluation schedule and emits one due event.';
