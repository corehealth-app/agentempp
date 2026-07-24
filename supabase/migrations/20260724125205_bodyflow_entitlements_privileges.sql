ALTER TABLE public.user_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entitlement_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.user_entitlements,
  public.entitlement_events
FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE
  public.user_entitlements,
  public.entitlement_events
TO service_role;

REVOKE ALL ON FUNCTION public.apply_entitlement_event(
  text, text, uuid, text, text, text, text, public.plan_enum, text,
  timestamptz, timestamptz, timestamptz, timestamptz, boolean, text, uuid
) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.resolve_user_entitlement(uuid, text, timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.sync_stripe_subscription_entitlement(
  uuid, text, timestamptz, text
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.apply_entitlement_event(
  text, text, uuid, text, text, text, text, public.plan_enum, text,
  timestamptz, timestamptz, timestamptz, timestamptz, boolean, text, uuid
) TO service_role;

GRANT EXECUTE ON FUNCTION public.resolve_user_entitlement(uuid, text, timestamptz)
  TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_stripe_subscription_entitlement(
  uuid, text, timestamptz, text
) TO service_role;
