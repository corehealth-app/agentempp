DO $permissions$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.register_workout_atomic(uuid, date, text, integer, integer, text, text, timestamptz, text, integer, numeric, boolean, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.register_workout_atomic(uuid, date, text, integer, integer, text, text, timestamptz, text, integer, numeric, boolean, timestamptz) TO service_role';
  EXECUTE 'COMMENT ON FUNCTION public.register_workout_atomic(uuid, date, text, integer, integer, text, text, timestamptz, text, integer, numeric, boolean, timestamptz) IS ''Atomically inserts or replaces a workout and recomputes affected snapshot exercise totals from source rows.''';
END;
$permissions$;
