DO $permissions$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.extend_message_buffer_once(uuid, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.extend_message_buffer_once(uuid, timestamptz) TO service_role';
  EXECUTE 'COMMENT ON FUNCTION public.extend_message_buffer_once(uuid, timestamptz) IS ''Extends a message buffer at most once per burst to wait for media processing.''';
END;
$permissions$;
