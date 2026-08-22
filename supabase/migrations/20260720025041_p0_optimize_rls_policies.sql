-- P0-A performance cleanup: combine patient/admin SELECT paths into one
-- permissive policy per table. Direct writes remain backend-only.
DROP POLICY IF EXISTS p0_patient_own_read ON public.users;
DROP POLICY IF EXISTS p0_patient_care_admin_read ON public.users;
CREATE POLICY p0_patient_or_care_admin_read
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    auth_user_id = (SELECT auth.uid())
    OR (SELECT public.admin_role()) IN (
      'support',
      'nutrition_admin',
      'operations_admin',
      'master_admin'
    )
  );

DO $migration$
DECLARE
  v_table text;
  v_patient_tables constant text[] := ARRAY[
    'daily_snapshots',
    'meal_logs',
    'messages',
    'pending_registrations',
    'prescriptions',
    'reevaluations',
    'subscriptions',
    'training_plans',
    'user_profiles',
    'user_progress',
    'workout_logs'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_patient_tables
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS p0_patient_own_read ON public.%I',
      v_table
    );
    EXECUTE format(
      'DROP POLICY IF EXISTS p0_patient_care_admin_read ON public.%I',
      v_table
    );
    EXECUTE format(
      $policy$
        CREATE POLICY p0_patient_or_care_admin_read
          ON public.%I
          FOR SELECT
          TO authenticated
          USING (
            EXISTS (
              SELECT 1
              FROM public.users domain_user
              WHERE domain_user.id = %I.user_id
                AND domain_user.auth_user_id = (SELECT auth.uid())
            )
            OR (SELECT public.admin_role()) IN (
              'support',
              'nutrition_admin',
              'operations_admin',
              'master_admin'
            )
          )
      $policy$,
      v_table,
      v_table
    );
  END LOOP;
END;
$migration$;

-- These ALL policies are redundant for SELECT and direct writes have no table
-- grant. The BFF uses service_role after its own role check.
DROP POLICY IF EXISTS admin_users_admin_write ON public.admin_users;
DROP POLICY IF EXISTS admin_users_self_read ON public.admin_users;
CREATE POLICY admin_users_read
  ON public.admin_users
  FOR SELECT
  TO authenticated
  USING (
    id = (SELECT auth.uid())
    OR (SELECT public.is_admin())
  );

DROP POLICY IF EXISTS configs_admin_write ON public.agent_configs;
DROP POLICY IF EXISTS flags_admin_all ON public.feature_flags;

-- Both indexes had the same key and predicate. Keep agent_configs_stage_excl,
-- which backs the exclusion constraint, and remove the ordinary duplicate.
DROP INDEX IF EXISTS public.idx_configs_active;
