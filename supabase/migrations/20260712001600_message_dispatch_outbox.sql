CREATE TABLE IF NOT EXISTS public.message_dispatch_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  messages jsonb NOT NULL CHECK (
    jsonb_typeof(messages) = 'array' AND jsonb_array_length(messages) > 0
  ),
  source_flush_after timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.message_dispatch_outbox ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.claim_due_message_dispatch(
  p_user_id uuid,
  p_now timestamptz DEFAULT now()
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing public.message_dispatch_outbox%ROWTYPE;
  v_buffer public.message_buffer%ROWTYPE;
  v_dispatch_id uuid;
  v_now timestamptz := COALESCE(p_now, now());
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user id is required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':message-dispatch', 0));

  SELECT *
  INTO v_existing
  FROM public.message_dispatch_outbox
  WHERE user_id = p_user_id;

  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status', 'claimed',
      'dispatch_id', v_existing.id,
      'messages', v_existing.messages,
      'source_flush_after', v_existing.source_flush_after,
      'existing', true
    );
  END IF;

  SELECT *
  INTO v_buffer
  FROM public.message_buffer
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_buffer.user_id IS NULL THEN
    RETURN jsonb_build_object('status', 'empty');
  END IF;

  IF jsonb_typeof(v_buffer.messages) <> 'array' THEN
    RAISE EXCEPTION 'message buffer payload is not an array';
  END IF;

  IF jsonb_array_length(v_buffer.messages) = 0 THEN
    DELETE FROM public.message_buffer WHERE user_id = p_user_id;
    RETURN jsonb_build_object('status', 'empty');
  END IF;

  IF v_buffer.flush_after > v_now THEN
    RETURN jsonb_build_object(
      'status', 'not_due',
      'flush_after', v_buffer.flush_after,
      'buffer_count', jsonb_array_length(v_buffer.messages)
    );
  END IF;

  INSERT INTO public.message_dispatch_outbox (
    user_id,
    messages,
    source_flush_after
  ) VALUES (
    p_user_id,
    v_buffer.messages,
    v_buffer.flush_after
  )
  RETURNING id INTO v_dispatch_id;

  DELETE FROM public.message_buffer WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'status', 'claimed',
    'dispatch_id', v_dispatch_id,
    'messages', v_buffer.messages,
    'source_flush_after', v_buffer.flush_after,
    'existing', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_message_dispatch(
  p_dispatch_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_buffer_count integer := 0;
  v_flush_after timestamptz;
BEGIN
  IF p_dispatch_id IS NULL THEN
    RAISE EXCEPTION 'dispatch id is required';
  END IF;

  SELECT user_id
  INTO v_user_id
  FROM public.message_dispatch_outbox
  WHERE id = p_dispatch_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('status', 'already_completed');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':message-dispatch', 0));

  DELETE FROM public.message_dispatch_outbox
  WHERE id = p_dispatch_id AND user_id = v_user_id;

  SELECT jsonb_array_length(messages), flush_after
  INTO v_buffer_count, v_flush_after
  FROM public.message_buffer
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object(
    'status', 'completed',
    'user_id', v_user_id,
    'next_buffer_count', COALESCE(v_buffer_count, 0),
    'next_flush_after', v_flush_after
  );
END;
$$;
