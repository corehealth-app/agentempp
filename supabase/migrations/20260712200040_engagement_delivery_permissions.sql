REVOKE ALL ON TABLE public.engagement_delivery_attempts
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.engagement_delivery_attempts
  TO service_role;

REVOKE ALL ON FUNCTION public.claim_engagement_delivery(uuid, date, text, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finalize_engagement_delivery(
  uuid, text, text, jsonb, timestamptz, text, integer, integer, numeric, integer,
  boolean, jsonb, uuid, boolean
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fail_engagement_delivery(uuid, text, text, timestamptz)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_engagement_delivery(uuid, date, text, text, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.finalize_engagement_delivery(
  uuid, text, text, jsonb, timestamptz, text, integer, integer, numeric, integer,
  boolean, jsonb, uuid, boolean
) TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_engagement_delivery(uuid, text, text, timestamptz)
  TO service_role;

COMMENT ON TABLE public.engagement_delivery_attempts IS
  'One claimable proactive engagement delivery per user and local date.';
COMMENT ON FUNCTION public.claim_engagement_delivery(uuid, date, text, text, timestamptz) IS
  'Claims one proactive engagement slot for a user and local date.';
COMMENT ON FUNCTION public.finalize_engagement_delivery(
  uuid, text, text, jsonb, timestamptz, text, integer, integer, numeric, integer,
  boolean, jsonb, uuid, boolean
) IS 'Atomically persists confirmed engagement deliveries, events, reevaluation consumption, and phrase cooldown.';
