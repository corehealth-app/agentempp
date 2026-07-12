DO $permissions$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.ensure_user_initialized(text) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.ensure_user_initialized(text) TO service_role';
  EXECUTE 'COMMENT ON FUNCTION public.ensure_user_initialized(text) IS ''Idempotently creates or repairs the user, profile, and progress rows in one transaction.''';
END;
$permissions$;
