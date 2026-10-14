-- Read-only observation for the dormant workout-strength classifier.
-- Not a capture receipt or a guarantee that this set is unchanged at commit.
CREATE FUNCTION public.get_workout_strength_catalogue_context()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM private.assert_trusted_backend();

  -- One data statement: count and rows share the same full active-set snapshot.
  WITH active AS MATERIALIZED (
    SELECT id, slug, display_name, category, is_active, updated_at,
      id IS NOT NULL AND slug IS NOT NULL AND display_name IS NOT NULL
        AND category IN ('musculacao', 'cardio', 'esporte', 'mobilidade')
        AND category IS NOT NULL AND is_active IS TRUE
        AND CASE WHEN updated_at IS NOT NULL AND isfinite(updated_at)
          THEN extract(year FROM updated_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999
          ELSE false END AS valid
    FROM public.workout_types
    WHERE is_active = true
  ), metadata AS MATERIALIZED (
    SELECT gen_random_uuid() AS observation_key, clock_timestamp() AS observed_at
  ), aggregate_set AS (
    SELECT count(*)::text AS row_count,
      coalesce(bool_and(valid), true) AS valid,
      coalesce(jsonb_agg(CASE WHEN valid THEN jsonb_build_object(
        'id', id::text,
        'slug', slug,
        'displayName', display_name,
        'category', category,
        'isActive', true,
        'updatedAtLiteral', to_char(updated_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      ) ELSE NULL END ORDER BY id), '[]'::jsonb) AS active_rows
    FROM active
  )
  SELECT CASE WHEN a.valid AND isfinite(m.observed_at)
      AND extract(year FROM m.observed_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999
    THEN jsonb_build_object(
      'status', 'available',
      'observationKey', m.observation_key::text,
      'observedAt', to_char(m.observed_at AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'matcherVersion', 'active_slug_then_unique_canonical_display_v1',
      'complete', true,
      'rowCount', a.row_count,
      'activeRows', a.active_rows
    )
    ELSE jsonb_build_object('status', 'unavailable', 'reason', 'catalogue_invalid')
    END INTO v_result
  FROM aggregate_set a CROSS JOIN metadata m;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_workout_strength_catalogue_context()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_workout_strength_catalogue_context()
  TO service_role;

COMMENT ON FUNCTION public.get_workout_strength_catalogue_context() IS
  'Backend-only complete active workout catalogue observation; no workout write or historical classification.';
