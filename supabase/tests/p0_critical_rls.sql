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

DO $test$
DECLARE
  v_without_rls text;
BEGIN
  SELECT string_agg(columns_with_user_id.table_name, ', ' ORDER BY columns_with_user_id.table_name)
  INTO v_without_rls
  FROM (
    SELECT DISTINCT column_row.table_name
    FROM information_schema.columns column_row
    JOIN pg_class table_row
      ON table_row.relname = column_row.table_name
      AND table_row.relnamespace = 'public'::regnamespace
      AND table_row.relkind IN ('r', 'p')
    WHERE column_row.table_schema = 'public'
      AND column_row.column_name = 'user_id'
      AND NOT table_row.relrowsecurity
  ) AS columns_with_user_id;

  IF v_without_rls IS NOT NULL THEN
    RAISE EXCEPTION 'user_id tables without RLS: %', v_without_rls;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class table_row
    JOIN pg_namespace schema_row ON schema_row.oid = table_row.relnamespace
    WHERE schema_row.nspname = 'public'
      AND table_row.relkind IN ('r', 'p', 'v', 'm')
      AND has_table_privilege(
        'anon',
        table_row.oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
  ) THEN
    RAISE EXCEPTION 'anon retains a privilege on a public relation';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class table_row
    JOIN pg_namespace schema_row ON schema_row.oid = table_row.relnamespace
    WHERE schema_row.nspname = 'public'
      AND table_row.relkind IN ('r', 'p')
      AND has_table_privilege(
        'authenticated',
        table_row.oid,
        'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
  ) THEN
    RAISE EXCEPTION 'authenticated retains a direct write privilege';
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_unsafe_views text;
BEGIN
  SELECT string_agg(expected.view_name, ', ' ORDER BY expected.view_name)
  INTO v_unsafe_views
  FROM unnest(ARRAY[
    'v_active_prompts',
    'v_attention_items',
    'v_cron_jobs',
    'v_daily_cost',
    'v_funnel_activation',
    'v_mrr_summary',
    'v_user_metrics',
    'vw_meal_state'
  ]) AS expected(view_name)
  LEFT JOIN pg_class view_row
    ON view_row.relname = expected.view_name
    AND view_row.relnamespace = 'public'::regnamespace
    AND view_row.relkind = 'v'
  WHERE view_row.oid IS NULL
    OR NOT ('security_invoker=true' = ANY(COALESCE(view_row.reloptions, ARRAY[]::text[])))
    OR has_table_privilege('anon', view_row.oid, 'SELECT')
    OR has_table_privilege('authenticated', view_row.oid, 'SELECT');

  IF v_unsafe_views IS NOT NULL THEN
    RAISE EXCEPTION 'unsafe public views: %', v_unsafe_views;
  END IF;

  IF has_table_privilege('anon', 'public.mv_kpis_daily', 'SELECT')
    OR has_table_privilege('authenticated', 'public.mv_kpis_daily', 'SELECT')
    OR NOT has_table_privilege('service_role', 'public.mv_kpis_daily', 'SELECT') THEN
    RAISE EXCEPTION 'materialized KPI view grants are unsafe';
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_exposed_functions text;
BEGIN
  SELECT string_agg(
    function_row.oid::regprocedure::text,
    ', '
    ORDER BY function_row.oid::regprocedure::text
  )
  INTO v_exposed_functions
  FROM pg_proc function_row
  JOIN pg_namespace schema_row ON schema_row.oid = function_row.pronamespace
  LEFT JOIN pg_depend extension_member
    ON extension_member.classid = 'pg_proc'::regclass
    AND extension_member.objid = function_row.oid
    AND extension_member.deptype = 'e'
  WHERE schema_row.nspname = 'public'
    AND function_row.prokind = 'f'
    AND extension_member.objid IS NULL
    AND function_row.proname NOT IN (
      'admin_role',
      'bootstrap_patient_profile',
      'is_admin'
    )
    AND (
      has_function_privilege('anon', function_row.oid, 'EXECUTE')
      OR has_function_privilege('authenticated', function_row.oid, 'EXECUTE')
    );

  IF v_exposed_functions IS NOT NULL THEN
    RAISE EXCEPTION 'legacy application functions remain client-executable: %', v_exposed_functions;
  END IF;

  IF has_function_privilege('anon', 'public.bootstrap_patient_profile()', 'EXECUTE')
    OR NOT has_function_privilege(
      'authenticated',
      'public.bootstrap_patient_profile()',
      'EXECUTE'
    ) THEN
    RAISE EXCEPTION 'patient bootstrap grants are incorrect';
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_mutable_search_path text;
BEGIN
  SELECT string_agg(
    function_row.oid::regprocedure::text,
    ', '
    ORDER BY function_row.oid::regprocedure::text
  )
  INTO v_mutable_search_path
  FROM pg_proc function_row
  JOIN pg_namespace schema_row ON schema_row.oid = function_row.pronamespace
  LEFT JOIN pg_depend extension_member
    ON extension_member.classid = 'pg_proc'::regclass
    AND extension_member.objid = function_row.oid
    AND extension_member.deptype = 'e'
  WHERE schema_row.nspname = 'public'
    AND function_row.prokind = 'f'
    AND extension_member.objid IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM unnest(COALESCE(function_row.proconfig, ARRAY[]::text[])) setting
      WHERE setting LIKE 'search_path=%'
    );

  IF v_mutable_search_path IS NOT NULL THEN
    RAISE EXCEPTION 'application functions with mutable search_path: %', v_mutable_search_path;
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_multiple_policies text;
BEGIN
  SELECT string_agg(policy_group.tablename, ', ' ORDER BY policy_group.tablename)
  INTO v_multiple_policies
  FROM (
    SELECT policy_row.tablename
    FROM pg_policies policy_row
    WHERE policy_row.schemaname = 'public'
      AND policy_row.permissive = 'PERMISSIVE'
      AND policy_row.cmd IN ('ALL', 'SELECT')
      AND (
        'public' = ANY(policy_row.roles)
        OR 'authenticated' = ANY(policy_row.roles)
      )
    GROUP BY policy_row.tablename
    HAVING count(*) > 1
  ) AS policy_group;

  IF v_multiple_policies IS NOT NULL THEN
    RAISE EXCEPTION 'multiple authenticated SELECT policies: %', v_multiple_policies;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'admin_users'
      AND policyname = 'admin_users_read'
      AND qual LIKE '%auth.uid()%'
      AND qual NOT LIKE '%SELECT auth.uid()%'
  ) THEN
    RAISE EXCEPTION 'admin_users policy does not cache auth.uid() with an initplan';
  END IF;
END;
$test$;

DO $test$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_index first_index
    JOIN pg_index second_index
      ON second_index.indrelid = first_index.indrelid
      AND second_index.indexrelid > first_index.indexrelid
      AND second_index.indkey = first_index.indkey
      AND second_index.indclass = first_index.indclass
      AND second_index.indcollation = first_index.indcollation
      AND second_index.indoption = first_index.indoption
      AND second_index.indexprs IS NOT DISTINCT FROM first_index.indexprs
      AND second_index.indpred IS NOT DISTINCT FROM first_index.indpred
    JOIN pg_class table_row ON table_row.oid = first_index.indrelid
    JOIN pg_namespace schema_row ON schema_row.oid = table_row.relnamespace
    WHERE schema_row.nspname = 'public'
      AND table_row.relname = 'agent_configs'
  ) THEN
    RAISE EXCEPTION 'agent_configs retains duplicate indexes';
  END IF;
END;
$test$;

ROLLBACK;
