CREATE TABLE public.engagement_delivery_attempts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  local_date date NOT NULL,
  attempt_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  slot text NOT NULL CHECK (btrim(slot) <> ''),
  claim_key text NOT NULL CHECK (btrim(claim_key) <> ''),
  status text NOT NULL CHECK (status IN ('claimed', 'sent', 'failed')),
  claimed_at timestamptz NOT NULL,
  sent_at timestamptz,
  provider_message_ids jsonb,
  last_error text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, local_date),
  CHECK (provider_message_ids IS NULL OR jsonb_typeof(provider_message_ids) = 'array')
);

ALTER TABLE public.engagement_delivery_attempts ENABLE ROW LEVEL SECURITY;

CREATE INDEX engagement_delivery_attempts_status_idx
  ON public.engagement_delivery_attempts (status, claimed_at);

CREATE OR REPLACE FUNCTION public.claim_engagement_delivery(
  p_user_id uuid,
  p_local_date date,
  p_slot text,
  p_claim_key text,
  p_now timestamptz DEFAULT now()
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.engagement_delivery_attempts%ROWTYPE;
  v_slot text := NULLIF(btrim(p_slot), '');
  v_claim_key text := NULLIF(btrim(p_claim_key), '');
  v_now timestamptz := COALESCE(p_now, now());
  v_attempt_id uuid;
BEGIN
  IF p_user_id IS NULL OR p_local_date IS NULL OR v_slot IS NULL OR v_claim_key IS NULL THEN
    RAISE EXCEPTION 'user, local date, slot, and claim key are required';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':engagement:' || p_local_date::text, 0)
  );

  SELECT *
  INTO v_row
  FROM public.engagement_delivery_attempts
  WHERE user_id = p_user_id AND local_date = p_local_date
  FOR UPDATE;

  IF v_row.attempt_id IS NULL THEN
    INSERT INTO public.engagement_delivery_attempts (
      user_id,
      local_date,
      slot,
      claim_key,
      status,
      claimed_at
    ) VALUES (
      p_user_id,
      p_local_date,
      v_slot,
      v_claim_key,
      'claimed',
      v_now
    )
    RETURNING attempt_id INTO v_attempt_id;

    RETURN jsonb_build_object(
      'status', 'claimed',
      'attempt_id', v_attempt_id,
      'existing', false
    );
  END IF;

  IF v_row.status = 'sent' THEN
    RETURN jsonb_build_object(
      'status', 'already_sent',
      'attempt_id', v_row.attempt_id
    );
  END IF;

  IF v_row.status = 'claimed' AND v_row.claim_key = v_claim_key THEN
    RETURN jsonb_build_object(
      'status', 'claimed',
      'attempt_id', v_row.attempt_id,
      'existing', true
    );
  END IF;

  IF v_row.status = 'claimed' AND v_row.claimed_at > v_now - interval '15 minutes' THEN
    RETURN jsonb_build_object(
      'status', 'busy',
      'attempt_id', v_row.attempt_id
    );
  END IF;

  v_attempt_id := gen_random_uuid();
  UPDATE public.engagement_delivery_attempts
  SET
    attempt_id = v_attempt_id,
    slot = v_slot,
    claim_key = v_claim_key,
    status = 'claimed',
    claimed_at = v_now,
    sent_at = NULL,
    provider_message_ids = NULL,
    last_error = NULL,
    updated_at = v_now
  WHERE user_id = p_user_id AND local_date = p_local_date;

  RETURN jsonb_build_object(
    'status', 'claimed',
    'attempt_id', v_attempt_id,
    'existing', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_engagement_delivery(
  p_attempt_id uuid,
  p_claim_key text,
  p_provider text,
  p_deliveries jsonb,
  p_sent_at timestamptz,
  p_model text DEFAULT NULL,
  p_prompt_tokens integer DEFAULT NULL,
  p_completion_tokens integer DEFAULT NULL,
  p_cost_usd numeric DEFAULT NULL,
  p_latency_ms integer DEFAULT NULL,
  p_reevaluation_due boolean DEFAULT false,
  p_reevaluation_context jsonb DEFAULT '{}'::jsonb,
  p_phrase_id uuid DEFAULT NULL,
  p_phrase_used boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.engagement_delivery_attempts%ROWTYPE;
  v_claim_key text := NULLIF(btrim(p_claim_key), '');
  v_provider text := COALESCE(NULLIF(btrim(p_provider), ''), 'whatsapp_cloud');
  v_sent_at timestamptz := COALESCE(p_sent_at, now());
  v_delivery_count integer;
  v_persisted_count integer;
  v_provider_message_ids jsonb;
  v_reevaluation_context jsonb := CASE
    WHEN jsonb_typeof(p_reevaluation_context) = 'object' THEN p_reevaluation_context
    ELSE '{}'::jsonb
  END;
BEGIN
  IF p_attempt_id IS NULL OR v_claim_key IS NULL THEN
    RAISE EXCEPTION 'attempt and claim key are required';
  END IF;
  IF jsonb_typeof(p_deliveries) <> 'array'
    OR jsonb_array_length(p_deliveries) = 0
    OR jsonb_array_length(p_deliveries) > 10 THEN
    RAISE EXCEPTION 'deliveries must be a non-empty array with at most 10 entries';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_deliveries) AS delivery
    WHERE NULLIF(btrim(delivery->>'provider_message_id'), '') IS NULL
      OR NULLIF(btrim(delivery->>'content'), '') IS NULL
      OR COALESCE(delivery->>'content_type', 'text') NOT IN ('text', 'audio')
  ) THEN
    RAISE EXCEPTION 'invalid engagement delivery payload';
  END IF;

  SELECT count(*), count(DISTINCT delivery->>'provider_message_id')
  INTO v_delivery_count, v_persisted_count
  FROM jsonb_array_elements(p_deliveries) AS delivery;
  IF v_delivery_count <> v_persisted_count THEN
    RAISE EXCEPTION 'engagement provider message ids must be unique';
  END IF;

  SELECT *
  INTO v_row
  FROM public.engagement_delivery_attempts
  WHERE attempt_id = p_attempt_id
  FOR UPDATE;

  IF v_row.attempt_id IS NULL THEN
    RAISE EXCEPTION 'engagement delivery attempt not found';
  END IF;
  IF v_row.status = 'sent' THEN
    RETURN jsonb_build_object('applied', false, 'status', 'already_sent');
  END IF;
  IF v_row.status <> 'claimed' OR v_row.claim_key <> v_claim_key THEN
    RAISE EXCEPTION 'engagement delivery claim mismatch';
  END IF;

  INSERT INTO public.messages (
    user_id,
    direction,
    role,
    content_type,
    content,
    media_url,
    provider,
    provider_message_id,
    agent_stage,
    model_used,
    prompt_tokens,
    completion_tokens,
    cost_usd,
    latency_ms,
    delivery_status,
    raw_payload,
    created_at
  )
  SELECT
    v_row.user_id,
    'out',
    'assistant',
    COALESCE(delivery->>'content_type', 'text')::public.content_type_enum,
    delivery->>'content',
    NULLIF(delivery->>'media_url', ''),
    v_provider,
    delivery->>'provider_message_id',
    'engajamento',
    p_model,
    p_prompt_tokens,
    p_completion_tokens,
    p_cost_usd,
    p_latency_ms,
    'sent',
    jsonb_build_object(
      'source', 'engagement_sender',
      'slot', v_row.slot,
      'engagement_slot', v_row.slot,
      'local_date', v_row.local_date,
      'attempt_id', v_row.attempt_id
    ),
    v_sent_at
  FROM jsonb_array_elements(p_deliveries) AS delivery
  ON CONFLICT (provider, provider_message_id)
    WHERE provider_message_id IS NOT NULL
  DO NOTHING;

  SELECT count(*)
  INTO v_persisted_count
  FROM public.messages AS message
  JOIN jsonb_array_elements(p_deliveries) AS delivery
    ON message.provider_message_id = delivery->>'provider_message_id'
  WHERE message.user_id = v_row.user_id
    AND message.provider = v_provider
    AND message.direction = 'out';

  IF v_persisted_count <> v_delivery_count THEN
    RAISE EXCEPTION 'engagement deliveries could not be persisted consistently';
  END IF;

  SELECT jsonb_agg(delivery->>'provider_message_id' ORDER BY delivery->>'provider_message_id')
  INTO v_provider_message_ids
  FROM jsonb_array_elements(p_deliveries) AS delivery;

  INSERT INTO public.product_events (user_id, event, properties, occurred_at)
  VALUES (
    v_row.user_id,
    'engagement.sent',
    jsonb_build_object(
      'slot', v_row.slot,
      'local_date', v_row.local_date,
      'attempt_id', v_row.attempt_id,
      'provider_message_ids', v_provider_message_ids,
      'delivery_count', v_delivery_count,
      'model', p_model,
      'cost_usd', p_cost_usd
    ),
    v_sent_at
  );

  IF COALESCE(p_reevaluation_due, false) THEN
    INSERT INTO public.product_events (user_id, event, properties, occurred_at)
    VALUES (
      v_row.user_id,
      'reevaluation.prompt_sent',
      v_reevaluation_context || jsonb_build_object(
        'slot', v_row.slot,
        'local_date', v_row.local_date,
        'attempt_id', v_row.attempt_id,
        'provider_message_ids', v_provider_message_ids
      ),
      v_sent_at
    );
  END IF;

  IF p_phrase_id IS NOT NULL THEN
    UPDATE public.engagement_phrases
    SET
      picked_count = picked_count + 1,
      used_count = used_count + CASE WHEN COALESCE(p_phrase_used, false) THEN 1 ELSE 0 END,
      last_used_at = v_sent_at
    WHERE id = p_phrase_id;

    IF FOUND THEN
      INSERT INTO public.user_phrase_cooldown (
        user_id,
        phrase_table,
        phrase_id,
        last_seen_at
      ) VALUES (
        v_row.user_id,
        'engagement',
        p_phrase_id,
        v_sent_at
      )
      ON CONFLICT (user_id, phrase_table, phrase_id) DO UPDATE SET
        last_seen_at = EXCLUDED.last_seen_at;
    END IF;
  END IF;

  UPDATE public.engagement_delivery_attempts
  SET
    status = 'sent',
    sent_at = v_sent_at,
    provider_message_ids = v_provider_message_ids,
    last_error = NULL,
    updated_at = v_sent_at
  WHERE attempt_id = v_row.attempt_id;

  RETURN jsonb_build_object(
    'applied', true,
    'status', 'sent',
    'delivery_count', v_delivery_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_engagement_delivery(
  p_attempt_id uuid,
  p_claim_key text,
  p_error text,
  p_now timestamptz DEFAULT now()
) RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_updated boolean := false;
BEGIN
  UPDATE public.engagement_delivery_attempts
  SET
    status = 'failed',
    last_error = left(COALESCE(p_error, 'delivery failed'), 500),
    updated_at = COALESCE(p_now, now())
  WHERE attempt_id = p_attempt_id
    AND claim_key = NULLIF(btrim(p_claim_key), '')
    AND status = 'claimed'
  RETURNING true INTO v_updated;

  RETURN COALESCE(v_updated, false);
END;
$$;
