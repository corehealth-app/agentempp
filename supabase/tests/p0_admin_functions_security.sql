BEGIN;

DO $test$
DECLARE
  v_exposed text;
  v_missing_search_path text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text)
  INTO v_exposed
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef
    AND p.proname = ANY (ARRAY[
      'attention_dismiss',
      'attention_restore',
      'attention_snooze',
      'cron_run_now',
      'cron_toggle_job',
      'cron_update_schedule',
      'dispatch_inngest_event',
      'pause_user',
      'refresh_mv_kpis_daily',
      'resume_user',
      'set_global_config',
      'tag_user',
      'untag_user'
    ])
    AND (
      has_function_privilege('anon', p.oid, 'EXECUTE')
      OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
    );

  IF v_exposed IS NOT NULL THEN
    RAISE EXCEPTION 'administrative functions exposed to anon/authenticated: %', v_exposed;
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text)
  INTO v_missing_search_path
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef
    AND NOT EXISTS (
      SELECT 1
      FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config(value)
      WHERE config.value LIKE 'search_path=%'
    );

  IF v_missing_search_path IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY DEFINER functions without fixed search_path: %', v_missing_search_path;
  END IF;

  IF has_function_privilege('anon', 'public.is_admin()', 'EXECUTE')
    OR has_function_privilege('anon', 'public.admin_role()', 'EXECUTE') THEN
    RAISE EXCEPTION 'admin helper functions must not be executable by anon';
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE')
    OR NOT has_function_privilege('authenticated', 'public.admin_role()', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated admin sessions require the read-only admin helpers';
  END IF;
END;
$test$;

ROLLBACK;
