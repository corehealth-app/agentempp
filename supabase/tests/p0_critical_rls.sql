BEGIN;

DO $test$
DECLARE
  v_without_rls text;
BEGIN
  SELECT string_agg(expected.table_name, ', ' ORDER BY expected.table_name)
  INTO v_without_rls
  FROM unnest(ARRAY[
    'attention_dismissals',
    'engagement_phrases',
    'food_education_phrases',
    'global_config',
    'pending_registrations',
    'prescriptions',
    'training_plans',
    'user_phrase_cooldown',
    'workout_types'
  ]) AS expected(table_name)
  LEFT JOIN pg_class table_row
    ON table_row.relname = expected.table_name
    AND table_row.relnamespace = 'public'::regnamespace
    AND table_row.relkind = 'r'
  WHERE table_row.oid IS NULL OR NOT table_row.relrowsecurity;

  IF v_without_rls IS NOT NULL THEN
    RAISE EXCEPTION 'critical tables without RLS: %', v_without_rls;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(ARRAY[
      'attention_dismissals',
      'engagement_phrases',
      'food_education_phrases',
      'global_config',
      'pending_registrations',
      'prescriptions',
      'training_plans',
      'user_phrase_cooldown',
      'workout_types'
    ]) AS expected(table_name)
    WHERE has_table_privilege('anon', format('public.%I', expected.table_name),
      'SELECT,INSERT,UPDATE,DELETE')
  ) THEN
    RAISE EXCEPTION 'anon retains privileges on a critical table';
  END IF;
END;
$test$;

ROLLBACK;
