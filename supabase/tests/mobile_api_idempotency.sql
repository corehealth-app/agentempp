BEGIN;

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000601';
  v_claim jsonb;
  v_replay jsonb;
  v_conflict jsonb;
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

  INSERT INTO public.users (id, email, wpp)
  VALUES (v_user_id, 'p0-mobile-idempotency@example.com', NULL);

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
END;
$$;

ROLLBACK;
