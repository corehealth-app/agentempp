-- BodyFlow P0-A: app-first table grants, RLS ownership and legacy surface lockdown.
-- Direct clients are read-only. All state changes remain behind the trusted BFF/service role.

DO $migration$
DECLARE
  v_table record;
BEGIN
  -- Staging starts deny-by-default for unauthenticated clients and direct writes.
  FOR v_table IN
    SELECT c.oid::regclass AS relation
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p', 'v', 'm')
  LOOP
    EXECUTE format(
      'REVOKE ALL PRIVILEGES ON TABLE %s FROM PUBLIC, anon',
      v_table.relation
    );
    EXECUTE format(
      'REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE %s FROM authenticated',
      v_table.relation
    );
  END LOOP;
END;
$migration$;

REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public
  FROM PUBLIC, anon, authenticated;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Existing application functions predate the deny-by-default function grants.
-- Keep only the three client-facing identity/RBAC helpers callable by authenticated.
DO $migration$
DECLARE
  v_function record;
BEGIN
  FOR v_function IN
    SELECT p.oid::regprocedure AS function_signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    LEFT JOIN pg_depend extension_member
      ON extension_member.classid = 'pg_proc'::regclass
      AND extension_member.objid = p.oid
      AND extension_member.deptype = 'e'
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND extension_member.objid IS NULL
      AND p.proname NOT IN (
        'admin_role',
        'bootstrap_patient_profile',
        'is_admin'
      )
  LOOP
    EXECUTE format(
      'REVOKE ALL PRIVILEGES ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      v_function.function_signature
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION %s TO service_role',
      v_function.function_signature
    );
  END LOOP;
END;
$migration$;

REVOKE ALL PRIVILEGES ON FUNCTION public.admin_role()
  FROM PUBLIC, anon;
REVOKE ALL PRIVILEGES ON FUNCTION public.is_admin()
  FROM PUBLIC, anon;
REVOKE ALL PRIVILEGES ON FUNCTION public.bootstrap_patient_profile()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_role()
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_admin()
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bootstrap_patient_profile()
  TO authenticated, service_role;

-- These views previously ran with owner privileges and were selectable by anon.
ALTER VIEW public.v_attention_items SET (security_invoker = true);
ALTER VIEW public.v_user_metrics SET (security_invoker = true);
ALTER VIEW public.vw_meal_state SET (security_invoker = true);

REVOKE ALL PRIVILEGES ON TABLE
  public.v_attention_items,
  public.v_user_metrics,
  public.vw_meal_state
FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE
  public.v_attention_items,
  public.v_user_metrics,
  public.vw_meal_state
TO service_role;

-- Reset the app-first policy surface so no legacy JWT-role policy survives.
DO $migration$
DECLARE
  v_policy record;
  v_table text;
  v_tables constant text[] := ARRAY[
    'attention_dismissals',
    'daily_gap_reminder_attempts',
    'daily_snapshots',
    'engagement_delivery_attempts',
    'engagement_phrases',
    'food_education_phrases',
    'global_config',
    'llm_evaluations',
    'meal_logs',
    'message_buffer',
    'message_dispatch_outbox',
    'message_embeddings',
    'messages',
    'pending_registrations',
    'prescriptions',
    'product_events',
    'reevaluations',
    'subscription_events',
    'subscriptions',
    'tools_audit',
    'training_plans',
    'user_food_corrections',
    'user_phrase_cooldown',
    'user_profiles',
    'user_progress',
    'users',
    'workout_logs',
    'workout_types'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_table);
  END LOOP;

  FOR v_policy IN
    SELECT tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY(v_tables)
  LOOP
    EXECUTE format(
      'DROP POLICY %I ON public.%I',
      v_policy.policyname,
      v_policy.tablename
    );
  END LOOP;
END;
$migration$;

-- Remove inherited broad SELECT grants from the tables governed below.
REVOKE SELECT ON TABLE
  public.attention_dismissals,
  public.daily_gap_reminder_attempts,
  public.daily_snapshots,
  public.engagement_delivery_attempts,
  public.engagement_phrases,
  public.food_education_phrases,
  public.global_config,
  public.llm_evaluations,
  public.meal_logs,
  public.message_buffer,
  public.message_dispatch_outbox,
  public.message_embeddings,
  public.messages,
  public.pending_registrations,
  public.prescriptions,
  public.product_events,
  public.reevaluations,
  public.subscription_events,
  public.subscriptions,
  public.tools_audit,
  public.training_plans,
  public.user_food_corrections,
  public.user_phrase_cooldown,
  public.user_profiles,
  public.user_progress,
  public.users,
  public.workout_logs,
  public.workout_types
FROM authenticated;

-- Safe direct read contract for the future patient client.
GRANT SELECT (
  id,
  auth_user_id,
  wpp,
  email,
  name,
  locale,
  timezone,
  status,
  country,
  country_confirmed,
  created_at,
  updated_at
) ON public.users TO authenticated;

GRANT SELECT ON TABLE
  public.user_profiles,
  public.user_progress,
  public.daily_snapshots,
  public.meal_logs,
  public.workout_logs,
  public.reevaluations,
  public.pending_registrations,
  public.prescriptions,
  public.training_plans
TO authenticated;

GRANT SELECT (
  id,
  user_id,
  direction,
  role,
  content_type,
  content,
  media_url,
  delivery_status,
  created_at
) ON public.messages TO authenticated;

GRANT SELECT (
  id,
  user_id,
  provider,
  plan,
  status,
  current_period_start,
  current_period_end,
  trial_ends_at,
  cancel_at_period_end,
  created_at,
  updated_at
) ON public.subscriptions TO authenticated;

-- Safe admin-readable surfaces. RLS below still enforces the canonical role.
GRANT SELECT ON TABLE
  public.attention_dismissals,
  public.engagement_phrases,
  public.food_education_phrases,
  public.global_config,
  public.user_food_corrections,
  public.user_phrase_cooldown,
  public.workout_types
TO authenticated;

CREATE POLICY p0_patient_own_read
  ON public.users
  FOR SELECT
  TO authenticated
  USING (auth_user_id = (SELECT auth.uid()));

CREATE POLICY p0_patient_care_admin_read
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN (
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
      $policy$
        CREATE POLICY p0_patient_own_read
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
          )
      $policy$,
      v_table,
      v_table
    );

    EXECUTE format(
      $policy$
        CREATE POLICY p0_patient_care_admin_read
          ON public.%I
          FOR SELECT
          TO authenticated
          USING (
            (SELECT public.admin_role()) IN (
              'support',
              'nutrition_admin',
              'operations_admin',
              'master_admin'
            )
          )
      $policy$,
      v_table
    );
  END LOOP;
END;
$migration$;

CREATE POLICY p0_support_operations_read
  ON public.attention_dismissals
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN (
      'support',
      'operations_admin',
      'master_admin'
    )
  );

CREATE POLICY p0_content_read
  ON public.engagement_phrases
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN ('content_editor', 'master_admin')
  );

CREATE POLICY p0_nutrition_content_read
  ON public.food_education_phrases
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN (
      'content_editor',
      'nutrition_admin',
      'master_admin'
    )
  );

CREATE POLICY p0_operations_read
  ON public.global_config
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN ('operations_admin', 'master_admin')
  );

CREATE POLICY p0_nutrition_read
  ON public.user_food_corrections
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN ('nutrition_admin', 'master_admin')
  );

CREATE POLICY p0_operations_read
  ON public.user_phrase_cooldown
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN ('operations_admin', 'master_admin')
  );

CREATE POLICY p0_nutrition_read
  ON public.workout_types
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN ('nutrition_admin', 'master_admin')
  );

-- Canonicalize remaining legacy admin-only policies outside the patient table set.
DROP POLICY IF EXISTS pending_approvals_admin_all ON public.pending_approvals;
CREATE POLICY pending_approvals_admin_read
  ON public.pending_approvals
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN (
      'support',
      'operations_admin',
      'master_admin'
    )
  );

DROP POLICY IF EXISTS audit_admin_read ON public.audit_log;
CREATE POLICY audit_admin_read
  ON public.audit_log
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN ('operations_admin', 'master_admin')
  );

DROP POLICY IF EXISTS tts_admin_read ON public.tts_cache;
CREATE POLICY tts_admin_read
  ON public.tts_cache
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN ('operations_admin', 'master_admin')
  );

DROP POLICY IF EXISTS wa_status_admin ON public.whatsapp_phone_status;
CREATE POLICY wa_status_admin
  ON public.whatsapp_phone_status
  FOR SELECT
  TO authenticated
  USING (
    (SELECT public.admin_role()) IN ('operations_admin', 'master_admin')
  );

COMMENT ON POLICY p0_patient_own_read ON public.users IS
  'Email-first patients may read only their linked domain row; no direct writes.';
