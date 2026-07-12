DO $permissions$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.finalize_daily_close_atomic(uuid, uuid, text, integer, integer, integer, integer, integer, integer, text[], date, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.finalize_daily_close_atomic(uuid, uuid, text, integer, integer, integer, integer, integer, integer, text[], date, timestamptz) TO service_role';
  EXECUTE 'COMMENT ON FUNCTION public.finalize_daily_close_atomic(uuid, uuid, text, integer, integer, integer, integer, integer, integer, text[], date, timestamptz) IS ''Atomically closes a daily snapshot and applies its derived progress exactly once.''';
END;
$permissions$;
