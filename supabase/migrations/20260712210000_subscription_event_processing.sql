ALTER TABLE public.subscription_events
  ADD COLUMN IF NOT EXISTS processing_status text NOT NULL DEFAULT 'processed',
  ADD COLUMN IF NOT EXISTS processing_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS processed_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_error text,
  ADD COLUMN IF NOT EXISTS attempt_count integer NOT NULL DEFAULT 0;

UPDATE public.subscription_events
SET processed_at = COALESCE(processed_at, created_at)
WHERE processing_status = 'processed'
  AND processed_at IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.subscription_events'::regclass
      AND conname = 'subscription_events_processing_status_check'
  ) THEN
    ALTER TABLE public.subscription_events
      ADD CONSTRAINT subscription_events_processing_status_check
      CHECK (processing_status IN ('processing', 'failed', 'processed'));
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_subscription_events_processing
  ON public.subscription_events (processing_status, processing_started_at);

CREATE OR REPLACE FUNCTION public.claim_subscription_event(
  p_provider_event_id text,
  p_event_type text,
  p_payload jsonb,
  p_now timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inserted_id uuid;
  v_event public.subscription_events%ROWTYPE;
BEGIN
  IF NULLIF(btrim(p_provider_event_id), '') IS NULL THEN
    RAISE EXCEPTION 'provider event id is required';
  END IF;
  IF NULLIF(btrim(p_event_type), '') IS NULL THEN
    RAISE EXCEPTION 'event type is required';
  END IF;

  INSERT INTO public.subscription_events (
    provider_event_id,
    event_type,
    payload,
    processing_status,
    processing_started_at,
    processed_at,
    last_error,
    attempt_count
  ) VALUES (
    p_provider_event_id,
    p_event_type,
    COALESCE(p_payload, '{}'::jsonb),
    'processing',
    p_now,
    null,
    null,
    1
  )
  ON CONFLICT (provider_event_id) DO NOTHING
  RETURNING id INTO v_inserted_id;

  IF v_inserted_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status', 'claimed',
      'event_id', v_inserted_id,
      'attempt_count', 1
    );
  END IF;

  SELECT *
  INTO v_event
  FROM public.subscription_events
  WHERE provider_event_id = p_provider_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'subscription event disappeared during claim';
  END IF;

  IF v_event.processing_status = 'processed' THEN
    RETURN jsonb_build_object(
      'status', 'duplicate',
      'event_id', v_event.id,
      'attempt_count', v_event.attempt_count
    );
  END IF;

  IF v_event.processing_status = 'processing'
    AND v_event.processing_started_at IS NOT NULL
    AND v_event.processing_started_at > p_now - interval '5 minutes' THEN
    RETURN jsonb_build_object(
      'status', 'in_progress',
      'event_id', v_event.id,
      'attempt_count', v_event.attempt_count
    );
  END IF;

  UPDATE public.subscription_events
  SET event_type = p_event_type,
      payload = COALESCE(p_payload, payload),
      processing_status = 'processing',
      processing_started_at = p_now,
      processed_at = null,
      last_error = null,
      attempt_count = attempt_count + 1
  WHERE id = v_event.id
  RETURNING * INTO v_event;

  RETURN jsonb_build_object(
    'status', 'claimed',
    'event_id', v_event.id,
    'attempt_count', v_event.attempt_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_subscription_event(
  p_provider_event_id text,
  p_success boolean,
  p_context jsonb DEFAULT '{}'::jsonb,
  p_error text DEFAULT null,
  p_now timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_event public.subscription_events%ROWTYPE;
  v_context jsonb := COALESCE(p_context, '{}'::jsonb);
BEGIN
  SELECT *
  INTO v_event
  FROM public.subscription_events
  WHERE provider_event_id = p_provider_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'subscription event % not found', p_provider_event_id;
  END IF;

  IF v_event.processing_status = 'processed' THEN
    RETURN jsonb_build_object('status', 'processed', 'event_id', v_event.id);
  END IF;

  IF v_event.processing_status <> 'processing' THEN
    RAISE EXCEPTION 'subscription event % is not claimed', p_provider_event_id;
  END IF;

  IF p_success THEN
    UPDATE public.subscription_events
    SET processing_status = 'processed',
        processed_at = p_now,
        last_error = null,
        user_id = COALESCE(NULLIF(v_context->>'user_id', '')::uuid, user_id),
        subscription_id = COALESCE(
          NULLIF(v_context->>'subscription_id', '')::uuid,
          subscription_id
        ),
        amount_cents = COALESCE(NULLIF(v_context->>'amount_cents', '')::integer, amount_cents),
        currency = COALESCE(NULLIF(v_context->>'currency', ''), currency)
    WHERE id = v_event.id
    RETURNING * INTO v_event;
  ELSE
    UPDATE public.subscription_events
    SET processing_status = 'failed',
        processed_at = null,
        last_error = left(COALESCE(NULLIF(p_error, ''), 'unknown processing failure'), 1000)
    WHERE id = v_event.id
    RETURNING * INTO v_event;
  END IF;

  RETURN jsonb_build_object(
    'status', v_event.processing_status,
    'event_id', v_event.id,
    'attempt_count', v_event.attempt_count
  );
END;
$$;
