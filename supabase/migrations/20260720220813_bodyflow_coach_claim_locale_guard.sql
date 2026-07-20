-- Keep event idempotency fail-closed when a caller accidentally reuses the
-- same event key after changing locale. The original implementation remains
-- private so the public service-only contract stays unchanged.

ALTER FUNCTION public.claim_coach_message(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  timestamptz
) SET SCHEMA private;

ALTER FUNCTION private.claim_coach_message(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  timestamptz
) RENAME TO claim_coach_message_unchecked;

GRANT USAGE ON SCHEMA private TO service_role;
REVOKE ALL ON FUNCTION private.claim_coach_message_unchecked(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  timestamptz
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.claim_coach_message_unchecked(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  timestamptz
) TO service_role;

CREATE OR REPLACE FUNCTION public.claim_coach_message(
  p_user_id uuid,
  p_context text,
  p_channel text,
  p_locale text,
  p_event_key text,
  p_available_variables text[],
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, extensions, pg_temp
AS $$
DECLARE
  v_event_key_hash text;
BEGIN
  IF p_user_id IS NULL
    OR p_context IS NULL
    OR p_channel IS NULL
    OR p_locale IS NULL
    OR p_event_key IS NULL
    OR p_now IS NULL
    OR char_length(btrim(p_event_key)) NOT BETWEEN 1 AND 512 THEN
    RAISE EXCEPTION 'valid user, context, channel, locale, event key, and time are required'
      USING ERRCODE = '22023';
  END IF;

  v_event_key_hash := encode(extensions.digest(btrim(p_event_key), 'sha256'), 'hex');

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      concat_ws(':', 'coach-claim', p_user_id::text, p_context, p_channel),
      0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM public.coach_message_usage usage
    WHERE usage.user_id = p_user_id
      AND usage.context = p_context
      AND usage.channel = p_channel
      AND usage.event_key_hash = v_event_key_hash
      AND usage.locale <> p_locale
  ) THEN
    RAISE EXCEPTION 'event key was already claimed with another locale'
      USING ERRCODE = '23514';
  END IF;

  RETURN private.claim_coach_message_unchecked(
    p_user_id,
    p_context,
    p_channel,
    p_locale,
    p_event_key,
    p_available_variables,
    p_now
  );
END;
$$;

REVOKE ALL ON FUNCTION public.claim_coach_message(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_coach_message(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  timestamptz
) TO service_role;

COMMENT ON FUNCTION public.claim_coach_message(
  uuid,
  text,
  text,
  text,
  text,
  text[],
  timestamptz
) IS 'Service-only locale-safe wrapper around the deterministic coach catalog claim.';
