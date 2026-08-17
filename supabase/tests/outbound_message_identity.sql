BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000222';
  v_message_id uuid;
  v_pending_id uuid;
BEGIN
  INSERT INTO public.users (id, wpp, name)
  VALUES (v_user_id, '18888888888', 'message-identity-test')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.pending_registrations (user_id, proposal, expires_at)
  VALUES (v_user_id, '{"kind":"meal"}'::jsonb, now() + interval '1 day')
  RETURNING id INTO v_pending_id;

  INSERT INTO public.messages (
    user_id,
    direction,
    role,
    content_type,
    content,
    provider,
    provider_message_id,
    delivery_status
  ) VALUES (
    v_user_id,
    'out',
    'assistant',
    'interactive',
    'proposal',
    'whatsapp_cloud',
    'wamid-local-outbound-1',
    'sent'
  ) RETURNING id INTO v_message_id;

  UPDATE public.pending_registrations
  SET proposal_msg_id = v_message_id
  WHERE id = v_pending_id;

  IF NOT EXISTS (
    SELECT 1
    FROM public.pending_registrations
    WHERE id = v_pending_id AND proposal_msg_id = v_message_id
  ) THEN
    RAISE EXCEPTION 'pending did not reference messages.id';
  END IF;

  BEGIN
    INSERT INTO public.messages (
      user_id,
      direction,
      role,
      content_type,
      content,
      provider,
      provider_message_id
    ) VALUES (
      v_user_id,
      'out',
      'assistant',
      'text',
      'duplicate',
      'whatsapp_cloud',
      'wamid-local-outbound-1'
    );
    RAISE EXCEPTION 'duplicate outbound provider id was accepted';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;
END;
$test$;

ROLLBACK;
