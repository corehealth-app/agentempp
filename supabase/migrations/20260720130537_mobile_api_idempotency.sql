CREATE TABLE public.mobile_api_idempotency (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  idempotency_key text NOT NULL,
  request_method text NOT NULL,
  request_route text NOT NULL,
  request_hash text NOT NULL,
  state text NOT NULL DEFAULT 'processing',
  response_status integer,
  response_body jsonb,
  attempt_count integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '24 hours',
  CONSTRAINT mobile_api_idempotency_user_key_unique
    UNIQUE (user_id, idempotency_key),
  CONSTRAINT mobile_api_idempotency_key_check
    CHECK (
      char_length(idempotency_key) BETWEEN 8 AND 128
      AND idempotency_key ~ '^[A-Za-z0-9._:-]+$'
    ),
  CONSTRAINT mobile_api_idempotency_method_check
    CHECK (request_method IN ('POST', 'PUT', 'PATCH', 'DELETE')),
  CONSTRAINT mobile_api_idempotency_route_check
    CHECK (
      char_length(request_route) BETWEEN 1 AND 255
      AND request_route LIKE '/api/mobile/v1/%'
    ),
  CONSTRAINT mobile_api_idempotency_hash_check
    CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT mobile_api_idempotency_state_check
    CHECK (state IN ('processing', 'completed', 'failed')),
  CONSTRAINT mobile_api_idempotency_response_status_check
    CHECK (response_status IS NULL OR response_status BETWEEN 100 AND 599),
  CONSTRAINT mobile_api_idempotency_attempt_count_check
    CHECK (attempt_count > 0),
  CONSTRAINT mobile_api_idempotency_completed_response_check
    CHECK (
      state <> 'completed'
      OR (response_status IS NOT NULL AND response_body IS NOT NULL)
    )
);

CREATE INDEX mobile_api_idempotency_expires_at_idx
  ON public.mobile_api_idempotency (expires_at);

ALTER TABLE public.mobile_api_idempotency ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.mobile_api_idempotency
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.mobile_api_idempotency
  TO service_role;

COMMENT ON TABLE public.mobile_api_idempotency IS
  'Backend-only replay ledger for authenticated mobile API mutations.';
COMMENT ON COLUMN public.mobile_api_idempotency.request_hash IS
  'SHA-256 of canonical validated input. Raw request payloads are not retained.';
COMMENT ON COLUMN public.mobile_api_idempotency.expires_at IS
  'Keys may be claimed as new requests after this retention window.';

CREATE OR REPLACE FUNCTION public.claim_mobile_api_request(
  p_user_id uuid,
  p_idempotency_key text,
  p_request_method text,
  p_request_route text,
  p_request_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_inserted_id uuid;
  v_request public.mobile_api_idempotency%ROWTYPE;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user id is required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.mobile_api_idempotency (
    user_id,
    idempotency_key,
    request_method,
    request_route,
    request_hash,
    created_at,
    updated_at,
    expires_at
  ) VALUES (
    p_user_id,
    p_idempotency_key,
    upper(p_request_method),
    p_request_route,
    lower(p_request_hash),
    v_now,
    v_now,
    v_now + interval '24 hours'
  )
  ON CONFLICT (user_id, idempotency_key) DO NOTHING
  RETURNING id INTO v_inserted_id;

  IF v_inserted_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'action', 'claimed',
      'claim_id', v_inserted_id
    );
  END IF;

  SELECT *
  INTO v_request
  FROM public.mobile_api_idempotency
  WHERE user_id = p_user_id
    AND idempotency_key = p_idempotency_key
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'idempotency claim disappeared' USING ERRCODE = '40001';
  END IF;

  IF v_request.expires_at <= v_now THEN
    UPDATE public.mobile_api_idempotency
    SET request_method = upper(p_request_method),
        request_route = p_request_route,
        request_hash = lower(p_request_hash),
        state = 'processing',
        response_status = NULL,
        response_body = NULL,
        attempt_count = 1,
        created_at = v_now,
        updated_at = v_now,
        expires_at = v_now + interval '24 hours'
    WHERE id = v_request.id;

    RETURN jsonb_build_object(
      'action', 'claimed',
      'claim_id', v_request.id
    );
  END IF;

  IF v_request.request_method <> upper(p_request_method)
    OR v_request.request_route <> p_request_route
    OR v_request.request_hash <> lower(p_request_hash) THEN
    RETURN jsonb_build_object('action', 'conflict');
  END IF;

  IF v_request.state = 'completed' THEN
    RETURN jsonb_build_object(
      'action', 'replay',
      'response_status', v_request.response_status,
      'response_body', v_request.response_body
    );
  END IF;

  IF v_request.state = 'processing'
    AND v_request.updated_at > v_now - interval '10 minutes' THEN
    RETURN jsonb_build_object('action', 'in_progress');
  END IF;

  UPDATE public.mobile_api_idempotency
  SET state = 'processing',
      response_status = NULL,
      response_body = NULL,
      attempt_count = attempt_count + 1,
      updated_at = v_now,
      expires_at = v_now + interval '24 hours'
  WHERE id = v_request.id;

  RETURN jsonb_build_object(
    'action', 'claimed',
    'claim_id', v_request.id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_mobile_api_request(
  p_claim_id uuid,
  p_user_id uuid,
  p_response_status integer,
  p_response_body jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.mobile_api_idempotency
  SET state = 'completed',
      response_status = p_response_status,
      response_body = p_response_body,
      updated_at = clock_timestamp()
  WHERE id = p_claim_id
    AND user_id = p_user_id
    AND state = 'processing';

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_mobile_api_request(
  p_claim_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.mobile_api_idempotency
  SET state = 'failed',
      response_status = NULL,
      response_body = NULL,
      updated_at = clock_timestamp()
  WHERE id = p_claim_id
    AND user_id = p_user_id
    AND state = 'processing';

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_mobile_api_request(uuid, text, text, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_mobile_api_request(uuid, uuid, integer, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fail_mobile_api_request(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_mobile_api_request(uuid, text, text, text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_mobile_api_request(uuid, uuid, integer, jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_mobile_api_request(uuid, uuid)
  TO service_role;
