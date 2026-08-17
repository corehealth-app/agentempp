DO $permissions$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.register_meal_atomic_scoped(uuid, date, public.meal_type_enum, jsonb, boolean, public.meal_type_enum[], timestamptz, text, integer, numeric, uuid[]) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.register_meal_atomic_scoped(uuid, date, public.meal_type_enum, jsonb, boolean, public.meal_type_enum[], timestamptz, text, integer, numeric, uuid[]) TO service_role';
  EXECUTE 'COMMENT ON FUNCTION public.register_meal_atomic_scoped(uuid, date, public.meal_type_enum, jsonb, boolean, public.meal_type_enum[], timestamptz, text, integer, numeric, uuid[]) IS ''Atomically replaces only validated meal_log ids, inserts corrected items, and recomputes snapshot totals.''';
END;
$permissions$;
