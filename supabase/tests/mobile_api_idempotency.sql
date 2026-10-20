BEGIN;

SET LOCAL ROLE postgres;
-- Seed the synthetic account as the local owner. All idempotency operations and
-- permission assertions below still run as service_role. Do not grant fixture
-- setup helpers to that backend role merely to run this test.
DO $fixture$
BEGIN
  IF EXISTS(SELECT 1 FROM public.users WHERE id='00000000-0000-0000-0000-000000000601') THEN
    RAISE EXCEPTION 'idempotency fixture user already exists';
  END IF;
  INSERT INTO public.users (id, email, wpp, country)
  VALUES ('00000000-0000-0000-0000-000000000601', 'p0-mobile-idempotency@example.com', NULL, 'BR');
END $fixture$;

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000601';
  v_claim jsonb;
  v_replay jsonb;
  v_conflict jsonb;
  v_reclaimed jsonb;
  v_before_expiry public.mobile_api_idempotency%ROWTYPE;
  v_after_expiry public.mobile_api_idempotency%ROWTYPE;
  v_hash text;
  v_lower timestamptz;
  v_upper timestamptz;
BEGIN
  IF has_table_privilege('anon', 'public.mobile_api_idempotency', 'SELECT')
    OR has_table_privilege('authenticated', 'public.mobile_api_idempotency', 'SELECT')
    OR has_table_privilege('authenticated', 'public.mobile_api_idempotency', 'INSERT') THEN
    RAISE EXCEPTION 'mobile idempotency table is exposed to a client role';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.claim_mobile_api_request(uuid,text,text,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'authenticated can execute backend idempotency claim';
  END IF;

  v_claim := public.claim_mobile_api_request(
    v_user_id,
    'mobile-request-0001',
    'PATCH',
    '/api/mobile/v1/me',
    repeat('a', 64)
  );
  IF v_claim ->> 'action' <> 'claimed' OR v_claim ->> 'claim_id' IS NULL THEN
    RAISE EXCEPTION 'first idempotency request was not claimed: %', v_claim;
  END IF;
  SELECT * INTO STRICT v_before_expiry FROM public.mobile_api_idempotency
  WHERE id = (v_claim ->> 'claim_id')::uuid AND user_id = v_user_id;
  IF v_before_expiry.expires_at IS DISTINCT FROM v_before_expiry.created_at + interval '24 hours'
    OR v_before_expiry.updated_at IS DISTINCT FROM v_before_expiry.created_at THEN
    RAISE EXCEPTION 'initial idempotency claim does not retain its key for exactly 24 hours';
  END IF;

  IF NOT public.complete_mobile_api_request(
    (v_claim ->> 'claim_id')::uuid,
    v_user_id,
    200,
    '{"data":{"ok":true}}'::jsonb
  ) THEN
    RAISE EXCEPTION 'idempotency request did not complete';
  END IF;

  v_replay := public.claim_mobile_api_request(
    v_user_id,
    'mobile-request-0001',
    'PATCH',
    '/api/mobile/v1/me',
    repeat('a', 64)
  );
  IF v_replay ->> 'action' <> 'replay'
    OR (v_replay ->> 'response_status')::integer <> 200
    OR v_replay #>> '{response_body,data,ok}' <> 'true' THEN
    RAISE EXCEPTION 'completed idempotency request did not replay: %', v_replay;
  END IF;

  v_conflict := public.claim_mobile_api_request(
    v_user_id,
    'mobile-request-0001',
    'PATCH',
    '/api/mobile/v1/me',
    repeat('b', 64)
  );
  IF v_conflict ->> 'action' <> 'conflict' THEN
    RAISE EXCEPTION 'idempotency key accepted a different payload: %', v_conflict;
  END IF;

  -- Exercise the real expiry branch without waiting 24 hours or replacing its
  -- clock. Only the row created above is changed, inside this outer ROLLBACK.
  -- The HTTP ledger may reuse a key even with a different payload after expiry;
  -- signup's independent durable admission must still refuse rebinding it.
  FOREACH v_hash IN ARRAY ARRAY[repeat('a', 64), repeat('b', 64)] LOOP
    UPDATE public.mobile_api_idempotency
    SET expires_at = clock_timestamp() - interval '1 second'
    WHERE id = (v_claim ->> 'claim_id')::uuid AND user_id = v_user_id
    RETURNING * INTO STRICT v_before_expiry;
    v_lower := clock_timestamp();
    v_reclaimed := public.claim_mobile_api_request(
      v_user_id, 'mobile-request-0001', 'PATCH', '/api/mobile/v1/me', v_hash
    );
    v_upper := clock_timestamp();
    SELECT * INTO STRICT v_after_expiry FROM public.mobile_api_idempotency
    WHERE id = (v_claim ->> 'claim_id')::uuid AND user_id = v_user_id;
    IF v_reclaimed ->> 'action' IS DISTINCT FROM 'claimed'
      OR v_reclaimed ->> 'claim_id' IS DISTINCT FROM v_claim ->> 'claim_id'
      OR v_after_expiry.state IS DISTINCT FROM 'processing'
      OR v_after_expiry.request_hash IS DISTINCT FROM v_hash
      OR v_after_expiry.request_method IS DISTINCT FROM 'PATCH'
      OR v_after_expiry.request_route IS DISTINCT FROM '/api/mobile/v1/me'
      OR v_after_expiry.attempt_count IS DISTINCT FROM 1
      OR v_after_expiry.response_status IS NOT NULL
      OR v_after_expiry.response_body IS NOT NULL
      OR (v_after_expiry.created_at BETWEEN v_lower AND v_upper) IS DISTINCT FROM true
      OR (v_after_expiry.created_at > v_before_expiry.created_at) IS DISTINCT FROM true
      OR v_after_expiry.updated_at IS DISTINCT FROM v_after_expiry.created_at
      OR v_after_expiry.expires_at IS DISTINCT FROM v_after_expiry.created_at + interval '24 hours'
      OR (SELECT count(*) FROM public.mobile_api_idempotency
        WHERE user_id = v_user_id AND idempotency_key = 'mobile-request-0001') <> 1 THEN
      RAISE EXCEPTION 'expired HTTP key did not renew only its owned claim: %', v_reclaimed;
    END IF;
    IF NOT public.complete_mobile_api_request(
      (v_claim ->> 'claim_id')::uuid, v_user_id, 200, '{"data":{"ttl_test":true}}'::jsonb
    ) THEN
      RAISE EXCEPTION 'reclaimed idempotency request did not complete';
    END IF;
  END LOOP;
END;
$$;

ROLLBACK;
