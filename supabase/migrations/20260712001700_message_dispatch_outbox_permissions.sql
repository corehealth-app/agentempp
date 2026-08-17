DO $permissions$
BEGIN
  REVOKE ALL ON TABLE public.message_dispatch_outbox FROM PUBLIC, anon, authenticated;
  GRANT SELECT, INSERT, DELETE ON TABLE public.message_dispatch_outbox TO service_role;

  EXECUTE 'REVOKE ALL ON FUNCTION public.claim_due_message_dispatch(uuid, timestamptz) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.claim_due_message_dispatch(uuid, timestamptz) TO service_role';
  EXECUTE 'REVOKE ALL ON FUNCTION public.complete_message_dispatch(uuid) FROM PUBLIC, anon, authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.complete_message_dispatch(uuid) TO service_role';
END;
$permissions$;
