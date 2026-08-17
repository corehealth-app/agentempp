CREATE UNIQUE INDEX IF NOT EXISTS uniq_messages_inbound_provider_id
  ON public.messages (provider, provider_message_id)
  WHERE direction = 'in' AND provider_message_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.ingest_whatsapp_inbound(
  p_provider_message_id text,
  p_wpp text,
  p_content_type text,
  p_content text,
  p_media_url text,
  p_raw_payload jsonb,
  p_received_at timestamptz,
  p_server_received_at timestamptz,
  p_debounce_ms integer,
  p_buffer boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_provider_message_id text := NULLIF(btrim(p_provider_message_id), '');
  v_wpp text := NULLIF(btrim(p_wpp), '');
  v_content_type text := lower(NULLIF(btrim(p_content_type), ''));
  v_user_id uuid;
  v_buffer_result jsonb := '{}'::jsonb;
  v_buffer_count integer := 0;
  v_flush_after timestamptz;
BEGIN
  IF v_provider_message_id IS NULL OR v_wpp IS NULL THEN
    RAISE EXCEPTION 'provider message id and wpp are required';
  END IF;
  IF v_content_type IS NULL
    OR v_content_type NOT IN ('text', 'audio', 'image', 'template', 'interactive') THEN
    RAISE EXCEPTION 'invalid inbound content type';
  END IF;
  IF p_buffer IS NULL THEN
    RAISE EXCEPTION 'buffer flag is required';
  END IF;
  IF p_buffer AND (p_debounce_ms IS NULL OR p_debounce_ms < 1) THEN
    RAISE EXCEPTION 'positive debounce is required for buffered inbound';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('whatsapp:' || v_provider_message_id, 0)
  );

  SELECT user_id
  INTO v_user_id
  FROM public.messages
  WHERE provider = 'whatsapp_cloud'
    AND provider_message_id = v_provider_message_id
    AND direction = 'in'
  LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.processed_messages (provider_message_id)
    VALUES (v_provider_message_id)
    ON CONFLICT (provider_message_id) DO NOTHING;

    INSERT INTO public.user_profiles (user_id)
    VALUES (v_user_id)
    ON CONFLICT (user_id) DO NOTHING;

    INSERT INTO public.user_progress (user_id)
    VALUES (v_user_id)
    ON CONFLICT (user_id) DO NOTHING;

    SELECT
      CASE
        WHEN jsonb_typeof(messages) = 'array' THEN jsonb_array_length(messages)
        ELSE 0
      END,
      flush_after
    INTO v_buffer_count, v_flush_after
    FROM public.message_buffer
    WHERE user_id = v_user_id;

    RETURN jsonb_build_object(
      'duplicate', true,
      'user_id', v_user_id,
      'buffer_count', COALESCE(v_buffer_count, 0),
      'flush_after', v_flush_after
    );
  END IF;

  -- A legacy reservation without an inbound message is incomplete and must
  -- not make every provider retry disappear forever.
  DELETE FROM public.processed_messages
  WHERE provider_message_id = v_provider_message_id;

  v_user_id := public.ensure_user_initialized(v_wpp);

  INSERT INTO public.processed_messages (provider_message_id)
  VALUES (v_provider_message_id);

  INSERT INTO public.messages (
    user_id,
    direction,
    role,
    content_type,
    content,
    media_url,
    provider,
    provider_message_id,
    raw_payload
  ) VALUES (
    v_user_id,
    'in',
    'user',
    v_content_type::public.content_type_enum,
    p_content,
    p_media_url,
    'whatsapp_cloud',
    v_provider_message_id,
    p_raw_payload
  );

  IF p_buffer THEN
    v_buffer_result := public.buffer_append_msg(
      v_user_id,
      jsonb_strip_nulls(
        jsonb_build_object(
          'provider_message_id', v_provider_message_id,
          'content_type', v_content_type,
          'text', p_content,
          'mediaUrl', p_media_url,
          'received_at', COALESCE(p_received_at, now()),
          'server_received_at', p_server_received_at
        )
      ),
      p_debounce_ms
    );
    v_buffer_count := COALESCE((v_buffer_result->>'count')::integer, 0);
    v_flush_after := (v_buffer_result->>'flush_after')::timestamptz;
  END IF;

  RETURN jsonb_build_object(
    'duplicate', false,
    'user_id', v_user_id,
    'buffer_count', v_buffer_count,
    'flush_after', v_flush_after
  );
END;
$$;
