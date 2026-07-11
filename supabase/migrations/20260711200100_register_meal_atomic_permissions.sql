DO $permissions$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.register_meal_atomic(uuid, date, public.meal_type_enum, jsonb, boolean, public.meal_type_enum[], timestamptz, text, integer, numeric) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.register_meal_atomic(uuid, date, public.meal_type_enum, jsonb, boolean, public.meal_type_enum[], timestamptz, text, integer, numeric) TO service_role';
  EXECUTE 'COMMENT ON FUNCTION public.register_meal_atomic(uuid, date, public.meal_type_enum, jsonb, boolean, public.meal_type_enum[], timestamptz, text, integer, numeric) IS ''Atomically inserts/replaces meal logs and recomputes daily snapshot nutrition from source rows.''';
END;
$permissions$;
