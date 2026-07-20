-- P0-A advisor cleanup: every API-visible view runs as invoker, while direct
-- access remains backend-only until the versioned mobile API defines its DTOs.
ALTER VIEW public.v_active_prompts SET (security_invoker = true);
ALTER VIEW public.v_cron_jobs SET (security_invoker = true);
ALTER VIEW public.v_daily_cost SET (security_invoker = true);
ALTER VIEW public.v_funnel_activation SET (security_invoker = true);
ALTER VIEW public.v_mrr_summary SET (security_invoker = true);

REVOKE ALL PRIVILEGES ON TABLE
  public.v_active_prompts,
  public.v_attention_items,
  public.v_cron_jobs,
  public.v_daily_cost,
  public.v_funnel_activation,
  public.v_mrr_summary,
  public.v_user_metrics,
  public.vw_meal_state,
  public.mv_kpis_daily
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE
  public.v_active_prompts,
  public.v_attention_items,
  public.v_cron_jobs,
  public.v_daily_cost,
  public.v_funnel_activation,
  public.v_mrr_summary,
  public.v_user_metrics,
  public.vw_meal_state,
  public.mv_kpis_daily
TO service_role;

-- Existing application functions are now client-inaccessible, but a fixed
-- search_path still protects trusted backend and trigger execution.
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
      AND NOT EXISTS (
        SELECT 1
        FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) setting
        WHERE setting LIKE 'search_path=%'
      )
  LOOP
    EXECUTE format(
      'ALTER FUNCTION %s SET search_path = pg_catalog, public, auth, extensions, pg_temp',
      v_function.function_signature
    );
  END LOOP;
END;
$migration$;
