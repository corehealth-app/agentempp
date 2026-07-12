BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000446';
  v_first jsonb;
  v_retry jsonb;
  v_complete jsonb;
  v_second jsonb;
  v_first_id uuid;
  v_outbox_count integer;
  v_buffer_count integer;
BEGIN
  INSERT INTO public.users (id, wpp, status)
  VALUES (v_user_id, '15550000446', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.message_buffer (user_id, messages, flush_after)
  VALUES (
    v_user_id,
    '[
      {"provider_message_id":"wamid-outbox-1","content_type":"text","text":"primeira","received_at":"2026-07-12T12:00:00Z"},
      {"provider_message_id":"wamid-outbox-2","content_type":"text","text":"segunda","received_at":"2026-07-12T12:00:02Z"}
    ]'::jsonb,
    timestamptz '2026-07-12 12:00:10+00'
  );

  v_first := public.claim_due_message_dispatch(
    v_user_id,
    timestamptz '2026-07-12 12:00:11+00'
  );
  v_first_id := (v_first->>'dispatch_id')::uuid;

  SELECT count(*) INTO v_outbox_count
  FROM public.message_dispatch_outbox
  WHERE user_id = v_user_id;
  SELECT count(*) INTO v_buffer_count
  FROM public.message_buffer
  WHERE user_id = v_user_id;

  IF v_first->>'status' <> 'claimed'
    OR jsonb_array_length(v_first->'messages') <> 2
    OR v_outbox_count <> 1
    OR v_buffer_count <> 0 THEN
    RAISE EXCEPTION 'first claim failed: %, outbox %, buffer %',
      v_first, v_outbox_count, v_buffer_count;
  END IF;

  -- A message arriving while the first dispatch is in flight stays buffered.
  PERFORM public.buffer_append_msg(
    v_user_id,
    '{"provider_message_id":"wamid-outbox-3","content_type":"text","text":"nova","received_at":"2026-07-12T12:00:12Z"}'::jsonb,
    8000
  );

  v_retry := public.claim_due_message_dispatch(
    v_user_id,
    timestamptz '2026-07-12 12:00:30+00'
  );

  IF (v_retry->>'dispatch_id')::uuid <> v_first_id
    OR jsonb_array_length(v_retry->'messages') <> 2 THEN
    RAISE EXCEPTION 'retry did not return the same in-flight dispatch: %', v_retry;
  END IF;

  v_complete := public.complete_message_dispatch(v_first_id);

  IF v_complete->>'status' <> 'completed'
    OR (v_complete->>'next_buffer_count')::integer <> 1 THEN
    RAISE EXCEPTION 'completion lost the next buffer: %', v_complete;
  END IF;

  SELECT count(*) INTO v_outbox_count
  FROM public.message_dispatch_outbox
  WHERE user_id = v_user_id;
  IF v_outbox_count <> 0 THEN
    RAISE EXCEPTION 'completed outbox row was not removed';
  END IF;

  v_second := public.claim_due_message_dispatch(
    v_user_id,
    timestamptz '2026-07-13 00:00:00+00'
  );

  IF v_second->>'status' <> 'claimed'
    OR (v_second->>'dispatch_id')::uuid = v_first_id
    OR jsonb_array_length(v_second->'messages') <> 1
    OR v_second->'messages'->0->>'provider_message_id' <> 'wamid-outbox-3' THEN
    RAISE EXCEPTION 'second buffer was not isolated: %', v_second;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.claim_due_message_dispatch(uuid,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.complete_message_dispatch(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute message dispatch functions';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.claim_due_message_dispatch(uuid,timestamptz)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.complete_message_dispatch(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute message dispatch functions';
  END IF;
END;
$test$;

ROLLBACK;
