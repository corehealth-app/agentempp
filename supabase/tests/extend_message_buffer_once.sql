BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000445';
  v_extended boolean;
  v_extension_count integer;
  v_flush_after timestamptz;
BEGIN
  INSERT INTO public.users (id, wpp, status)
  VALUES (v_user_id, '15550000445', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.message_buffer (user_id, messages, flush_after)
  VALUES (
    v_user_id,
    '[{"provider_message_id":"wamid-buffer-1","content_type":"text","received_at":"2026-07-12T12:00:00Z"}]'::jsonb,
    timestamptz '2026-07-12 12:00:08+00'
  );

  v_extended := public.extend_message_buffer_once(
    v_user_id,
    timestamptz '2026-07-12 12:00:28+00'
  );

  SELECT media_extension_count, flush_after
  INTO v_extension_count, v_flush_after
  FROM public.message_buffer
  WHERE user_id = v_user_id;

  IF NOT v_extended
    OR v_extension_count <> 1
    OR v_flush_after <> timestamptz '2026-07-12 12:00:28+00' THEN
    RAISE EXCEPTION 'first extension failed: extended %, count %, flush %',
      v_extended, v_extension_count, v_flush_after;
  END IF;

  v_extended := public.extend_message_buffer_once(
    v_user_id,
    timestamptz '2026-07-12 12:01:00+00'
  );

  IF v_extended THEN
    RAISE EXCEPTION 'second extension must be blocked';
  END IF;

  PERFORM public.buffer_append_msg(
    v_user_id,
    '{"provider_message_id":"wamid-buffer-2","content_type":"text","received_at":"2026-07-12T12:00:10Z"}'::jsonb,
    8000
  );

  SELECT media_extension_count
  INTO v_extension_count
  FROM public.message_buffer
  WHERE user_id = v_user_id;

  IF v_extension_count <> 1 THEN
    RAISE EXCEPTION 'append reset extension count: %', v_extension_count;
  END IF;

  IF has_function_privilege(
    'anon',
    'public.extend_message_buffer_once(uuid,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute extend_message_buffer_once';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.extend_message_buffer_once(uuid,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute extend_message_buffer_once';
  END IF;
END;
$test$;

ROLLBACK;
