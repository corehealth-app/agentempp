DO $permissions$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.save_training_plan_atomic(uuid, text, integer, text, jsonb, text, timestamptz, timestamptz, integer, text, text) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.save_training_plan_atomic(uuid, text, integer, text, jsonb, text, timestamptz, timestamptz, integer, text, text) TO service_role';
  EXECUTE 'COMMENT ON FUNCTION public.save_training_plan_atomic(uuid, text, integer, text, jsonb, text, timestamptz, timestamptz, integer, text, text) IS ''Idempotently replaces the active training plan and enables daily reminders in one transaction.''';
END;
$permissions$;
