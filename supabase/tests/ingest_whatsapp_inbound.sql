BEGIN;

DO $test$
DECLARE
  v_wpp text := '15550000447';
  v_result jsonb;
  v_retry jsonb;
  v_user_id uuid;
  v_message_count integer;
  v_buffer_count integer;
  v_profile_count integer;
  v_progress_count integer;
  v_interactive_user_id uuid;
BEGIN
  v_result := public.ingest_whatsapp_inbound(
    p_provider_message_id => 'wamid-ingest-1',
    p_wpp => v_wpp,
    p_content_type => 'text',
    p_content => 'primeira mensagem',
    p_media_url => NULL,
    p_raw_payload => '{"id":"wamid-ingest-1"}'::jsonb,
    p_received_at => timestamptz '2026-07-12 12:00:00+00',
    p_server_received_at => timestamptz '2026-07-12 12:00:01+00',
    p_debounce_ms => 8000,
    p_buffer => true
  );
  v_user_id := (v_result->>'user_id')::uuid;

  SELECT count(*) INTO v_message_count
  FROM public.messages
  WHERE provider = 'whatsapp_cloud'
    AND provider_message_id = 'wamid-ingest-1'
    AND direction = 'in';
  SELECT jsonb_array_length(messages) INTO v_buffer_count
  FROM public.message_buffer
  WHERE user_id = v_user_id;
  SELECT count(*) INTO v_profile_count FROM public.user_profiles WHERE user_id = v_user_id;
  SELECT count(*) INTO v_progress_count FROM public.user_progress WHERE user_id = v_user_id;

  IF (v_result->>'duplicate')::boolean
    OR v_message_count <> 1
    OR v_buffer_count <> 1
    OR v_profile_count <> 1
    OR v_progress_count <> 1 THEN
    RAISE EXCEPTION 'atomic inbound ingest failed: %, messages %, buffer %, profile %, progress %',
      v_result, v_message_count, v_buffer_count, v_profile_count, v_progress_count;
  END IF;

  v_retry := public.ingest_whatsapp_inbound(
    p_provider_message_id => 'wamid-ingest-1',
    p_wpp => v_wpp,
    p_content_type => 'text',
    p_content => 'não pode sobrescrever',
    p_media_url => NULL,
    p_raw_payload => '{}'::jsonb,
    p_received_at => timestamptz '2026-07-12 12:00:00+00',
    p_server_received_at => NULL,
    p_debounce_ms => 8000,
    p_buffer => true
  );

  SELECT count(*) INTO v_message_count
  FROM public.messages
  WHERE provider = 'whatsapp_cloud'
    AND provider_message_id = 'wamid-ingest-1'
    AND direction = 'in';
  SELECT jsonb_array_length(messages) INTO v_buffer_count
  FROM public.message_buffer
  WHERE user_id = v_user_id;

  IF NOT (v_retry->>'duplicate')::boolean
    OR (v_retry->>'user_id')::uuid <> v_user_id
    OR v_message_count <> 1
    OR v_buffer_count <> 1 THEN
    RAISE EXCEPTION 'inbound retry was not idempotent: %, messages %, buffer %',
      v_retry, v_message_count, v_buffer_count;
  END IF;

  -- Legacy reservation without a message must be recoverable, not skipped forever.
  INSERT INTO public.processed_messages (provider_message_id)
  VALUES ('wamid-ingest-orphan');

  v_result := public.ingest_whatsapp_inbound(
    p_provider_message_id => 'wamid-ingest-orphan',
    p_wpp => v_wpp,
    p_content_type => 'text',
    p_content => 'recuperada',
    p_media_url => NULL,
    p_raw_payload => '{}'::jsonb,
    p_received_at => timestamptz '2026-07-12 12:01:00+00',
    p_server_received_at => NULL,
    p_debounce_ms => 8000,
    p_buffer => true
  );

  IF (v_result->>'duplicate')::boolean THEN
    RAISE EXCEPTION 'orphan processed marker was not repaired: %', v_result;
  END IF;

  v_result := public.ingest_whatsapp_inbound(
    p_provider_message_id => 'wamid-ingest-tap',
    p_wpp => '15550000448',
    p_content_type => 'interactive',
    p_content => 'confirm_00000000-0000-0000-0000-000000000001',
    p_media_url => NULL,
    p_raw_payload => '{}'::jsonb,
    p_received_at => timestamptz '2026-07-12 12:02:00+00',
    p_server_received_at => NULL,
    p_debounce_ms => 8000,
    p_buffer => false
  );
  v_interactive_user_id := (v_result->>'user_id')::uuid;

  IF EXISTS (
    SELECT 1 FROM public.message_buffer WHERE user_id = v_interactive_user_id
  ) THEN
    RAISE EXCEPTION 'interactive inbound must not enter message_buffer';
  END IF;

  IF has_function_privilege(
    'anon',
    'public.ingest_whatsapp_inbound(text,text,text,text,text,jsonb,timestamptz,timestamptz,integer,boolean)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute ingest_whatsapp_inbound';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.ingest_whatsapp_inbound(text,text,text,text,text,jsonb,timestamptz,timestamptz,integer,boolean)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role must execute ingest_whatsapp_inbound';
  END IF;
END;
$test$;

ROLLBACK;
