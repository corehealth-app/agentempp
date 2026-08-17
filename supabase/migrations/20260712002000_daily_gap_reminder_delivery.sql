CREATE UNIQUE INDEX IF NOT EXISTS uniq_messages_outbound_provider_id
  ON public.messages (provider, provider_message_id)
  WHERE direction = 'out' AND provider_message_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.daily_gap_reminder_attempts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  date date NOT NULL,
  attempt_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  claim_key text NOT NULL,
  gap jsonb NOT NULL CHECK (jsonb_typeof(gap) = 'array' AND jsonb_array_length(gap) > 0),
  status text NOT NULL CHECK (status IN ('claimed', 'sent', 'failed')),
  claimed_at timestamptz NOT NULL,
  sent_at timestamptz,
  provider_message_id text,
  last_error text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date)
);

ALTER TABLE public.daily_gap_reminder_attempts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.claim_daily_gap_reminder(
  p_user_id uuid,
  p_date date,
  p_claim_key text,
  p_gap jsonb,
  p_now timestamptz DEFAULT now()
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.daily_gap_reminder_attempts%ROWTYPE;
  v_claim_key text := NULLIF(btrim(p_claim_key), '');
  v_now timestamptz := COALESCE(p_now, now());
  v_attempt_id uuid;
BEGIN
  IF p_user_id IS NULL OR p_date IS NULL OR v_claim_key IS NULL THEN
    RAISE EXCEPTION 'user, date, and claim key are required';
  END IF;
  IF jsonb_typeof(p_gap) <> 'array' OR jsonb_array_length(p_gap) = 0 THEN
    RAISE EXCEPTION 'daily gap reminder requires a non-empty gap array';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':daily-gap:' || p_date::text, 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.daily_snapshots
    WHERE user_id = p_user_id
      AND date = p_date
      AND gap_reminder_sent_at IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('status', 'already_sent');
  END IF;

  SELECT *
  INTO v_row
  FROM public.daily_gap_reminder_attempts
  WHERE user_id = p_user_id AND date = p_date
  FOR UPDATE;

  IF v_row.attempt_id IS NULL THEN
    INSERT INTO public.daily_gap_reminder_attempts (
      user_id,
      date,
      claim_key,
      gap,
      status,
      claimed_at
    ) VALUES (
      p_user_id,
      p_date,
      v_claim_key,
      p_gap,
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
  UPDATE public.daily_gap_reminder_attempts
  SET
    attempt_id = v_attempt_id,
    claim_key = v_claim_key,
    gap = p_gap,
    status = 'claimed',
    claimed_at = v_now,
    sent_at = NULL,
    provider_message_id = NULL,
    last_error = NULL,
    updated_at = v_now
  WHERE user_id = p_user_id AND date = p_date;

  RETURN jsonb_build_object(
    'status', 'claimed',
    'attempt_id', v_attempt_id,
    'existing', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_daily_gap_reminder(
  p_attempt_id uuid,
  p_claim_key text,
  p_provider text,
  p_provider_message_id text,
  p_content text,
  p_sent_at timestamptz,
  p_pattern_days integer,
  p_local_hour integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.daily_gap_reminder_attempts%ROWTYPE;
  v_claim_key text := NULLIF(btrim(p_claim_key), '');
  v_provider text := COALESCE(NULLIF(btrim(p_provider), ''), 'whatsapp_cloud');
  v_provider_message_id text := NULLIF(btrim(p_provider_message_id), '');
  v_sent_at timestamptz := COALESCE(p_sent_at, now());
BEGIN
  IF p_attempt_id IS NULL OR v_claim_key IS NULL
    OR v_provider_message_id IS NULL OR NULLIF(btrim(p_content), '') IS NULL THEN
    RAISE EXCEPTION 'attempt, claim, provider message id, and content are required';
  END IF;

  SELECT *
  INTO v_row
  FROM public.daily_gap_reminder_attempts
  WHERE attempt_id = p_attempt_id
  FOR UPDATE;

  IF v_row.attempt_id IS NULL THEN
    RAISE EXCEPTION 'daily gap reminder attempt not found';
  END IF;
  IF v_row.status = 'sent' THEN
    RETURN jsonb_build_object('applied', false, 'status', 'already_sent');
  END IF;
  IF v_row.status <> 'claimed' OR v_row.claim_key <> v_claim_key THEN
    RAISE EXCEPTION 'daily gap reminder claim mismatch';
  END IF;

  INSERT INTO public.daily_snapshots (
    user_id,
    date,
    day_status,
    gap_reminder_sent_at,
    updated_at
  ) VALUES (
    v_row.user_id,
    v_row.date,
    'pending_close',
    v_sent_at,
    v_sent_at
  )
  ON CONFLICT (user_id, date) DO UPDATE SET
    day_status = CASE
      WHEN public.daily_snapshots.day_closed THEN public.daily_snapshots.day_status
      ELSE 'pending_close'
    END,
    gap_reminder_sent_at = COALESCE(
      public.daily_snapshots.gap_reminder_sent_at,
      EXCLUDED.gap_reminder_sent_at
    ),
    updated_at = EXCLUDED.updated_at;

  INSERT INTO public.messages (
    user_id,
    direction,
    role,
    content_type,
    content,
    provider,
    provider_message_id,
    agent_stage,
    delivery_status,
    raw_payload
  ) VALUES (
    v_row.user_id,
    'out',
    'assistant',
    'text',
    p_content,
    v_provider,
    v_provider_message_id,
    'engajamento',
    'sent',
    jsonb_build_object(
      'source', 'daily_gap_checker',
      'date', v_row.date,
      'gap', v_row.gap,
      'attempt_id', v_row.attempt_id
    )
  )
  ON CONFLICT (provider, provider_message_id)
    WHERE direction = 'out' AND provider_message_id IS NOT NULL
  DO NOTHING;

  INSERT INTO public.product_events (user_id, event, properties, occurred_at)
  VALUES (
    v_row.user_id,
    'daily.gap_reminder_sent',
    jsonb_build_object(
      'gap', v_row.gap,
      'date', v_row.date,
      'pattern_active_days', p_pattern_days,
      'local_hour', p_local_hour,
      'delivery_status', 'sent',
      'attempt_id', v_row.attempt_id
    ),
    v_sent_at
  );

  UPDATE public.daily_gap_reminder_attempts
  SET
    status = 'sent',
    sent_at = v_sent_at,
    provider_message_id = v_provider_message_id,
    last_error = NULL,
    updated_at = v_sent_at
  WHERE attempt_id = v_row.attempt_id;

  RETURN jsonb_build_object('applied', true, 'status', 'sent');
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_daily_gap_reminder(
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
  UPDATE public.daily_gap_reminder_attempts
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
