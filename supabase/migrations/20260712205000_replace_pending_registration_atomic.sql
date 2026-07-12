-- Replaces a user's open proposal without exposing a cancellation/insert gap.
-- The provider request key makes retries return the original proposal.

CREATE OR REPLACE FUNCTION public.replace_pending_registration_atomic(
  p_user_id uuid,
  p_proposal jsonb,
  p_expires_at timestamptz,
  p_request_key text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_proposal jsonb;
  v_existing_id uuid;
  v_existing_status public.pending_registration_status;
  v_pending_id uuid;
  v_cancelled_count integer := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user is required';
  END IF;
  IF p_proposal IS NULL OR jsonb_typeof(p_proposal) <> 'object' THEN
    RAISE EXCEPTION 'proposal must be a JSON object';
  END IF;
  IF p_expires_at IS NULL THEN
    RAISE EXCEPTION 'expiration is required';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':pending-registration', 0)
  );

  v_proposal := p_proposal;
  IF NULLIF(btrim(p_request_key), '') IS NOT NULL THEN
    v_proposal := jsonb_set(
      v_proposal,
      '{source_provider_message_id}',
      to_jsonb(btrim(p_request_key)),
      true
    );

    SELECT pending.id, pending.status
    INTO v_existing_id, v_existing_status
    FROM public.pending_registrations AS pending
    WHERE pending.user_id = p_user_id
      AND pending.proposal->>'source_provider_message_id' = btrim(p_request_key)
    ORDER BY pending.created_at DESC, pending.id DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'pending_id', v_existing_id,
        'created', false,
        'status', v_existing_status,
        'cancelled_count', 0
      );
    END IF;
  END IF;

  UPDATE public.pending_registrations
  SET status = 'cancelled',
      resolved_at = now()
  WHERE user_id = p_user_id
    AND status = 'pending';
  GET DIAGNOSTICS v_cancelled_count = ROW_COUNT;

  INSERT INTO public.pending_registrations (
    user_id,
    proposal,
    expires_at
  ) VALUES (
    p_user_id,
    v_proposal,
    p_expires_at
  )
  RETURNING id INTO v_pending_id;

  RETURN jsonb_build_object(
    'pending_id', v_pending_id,
    'created', true,
    'status', 'pending',
    'cancelled_count', v_cancelled_count
  );
END;
$$;

