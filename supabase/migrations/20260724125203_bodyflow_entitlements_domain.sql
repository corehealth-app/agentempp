CREATE TABLE public.user_entitlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  entitlement_key text NOT NULL DEFAULT 'bodyflow_full',
  source text NOT NULL,
  source_reference text NOT NULL,
  status text NOT NULL,
  plan public.plan_enum,
  environment text NOT NULL,
  starts_at timestamptz,
  access_expires_at timestamptz,
  grace_expires_at timestamptz,
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  last_provider_event_id text NOT NULL,
  last_provider_event_at timestamptz NOT NULL,
  reason_code text,
  actor_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT user_entitlements_key_check CHECK (
    char_length(entitlement_key) BETWEEN 1 AND 200
    AND entitlement_key ~ '^[A-Za-z0-9._:/-]+$'
  ),
  CONSTRAINT user_entitlements_source_check CHECK (
    source IN ('stripe', 'apple_storekit', 'revenuecat', 'manual', 'legacy')
  ),
  CONSTRAINT user_entitlements_source_reference_check CHECK (
    char_length(source_reference) BETWEEN 1 AND 200
    AND source_reference ~ '^[A-Za-z0-9._:/-]+$'
  ),
  CONSTRAINT user_entitlements_status_check CHECK (
    status IN (
      'active',
      'trialing',
      'grace_period',
      'expired',
      'canceled',
      'grandfathered',
      'manual_comp',
      'blocked'
    )
  ),
  CONSTRAINT user_entitlements_environment_check CHECK (
    environment IN ('sandbox', 'production', 'internal')
  ),
  CONSTRAINT user_entitlements_event_id_check CHECK (
    char_length(last_provider_event_id) BETWEEN 1 AND 200
    AND last_provider_event_id ~ '^[A-Za-z0-9._:/-]+$'
  ),
  CONSTRAINT user_entitlements_reason_check CHECK (
    reason_code IS NULL
    OR (
      char_length(reason_code) BETWEEN 1 AND 64
      AND reason_code ~ '^[a-z][a-z0-9_]*$'
    )
  ),
  CONSTRAINT user_entitlements_time_order_check CHECK (
    (starts_at IS NULL OR access_expires_at IS NULL OR starts_at <= access_expires_at)
    AND (
      access_expires_at IS NULL
      OR grace_expires_at IS NULL
      OR access_expires_at <= grace_expires_at
    )
  ),
  CONSTRAINT user_entitlements_provider_expiry_check CHECK (
    source NOT IN ('stripe', 'apple_storekit', 'revenuecat')
    OR status NOT IN ('active', 'trialing')
    OR access_expires_at IS NOT NULL
  ),
  CONSTRAINT user_entitlements_grace_expiry_check CHECK (
    status <> 'grace_period' OR grace_expires_at IS NOT NULL
  ),
  CONSTRAINT user_entitlements_manual_audit_check CHECK (
    source <> 'manual' OR (reason_code IS NOT NULL AND actor_id IS NOT NULL)
  )
);

CREATE UNIQUE INDEX user_entitlements_source_reference_key
  ON public.user_entitlements (source, source_reference, entitlement_key);

CREATE INDEX user_entitlements_resolver_idx
  ON public.user_entitlements (
    user_id,
    entitlement_key,
    status,
    access_expires_at DESC,
    grace_expires_at DESC
  );

CREATE INDEX user_entitlements_provider_order_idx
  ON public.user_entitlements (
    source,
    source_reference,
    entitlement_key,
    last_provider_event_at DESC,
    last_provider_event_id DESC
  );

CREATE TABLE public.entitlement_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entitlement_id uuid REFERENCES public.user_entitlements(id) ON DELETE SET NULL,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  entitlement_key text NOT NULL,
  source text NOT NULL,
  source_reference text NOT NULL,
  provider_event_id text NOT NULL,
  event_type text NOT NULL,
  environment text NOT NULL,
  occurred_at timestamptz NOT NULL,
  processing_result text NOT NULL DEFAULT 'received',
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  processed_at timestamptz,
  CONSTRAINT entitlement_events_key_check CHECK (
    char_length(entitlement_key) BETWEEN 1 AND 200
    AND entitlement_key ~ '^[A-Za-z0-9._:/-]+$'
  ),
  CONSTRAINT entitlement_events_source_check CHECK (
    source IN ('stripe', 'apple_storekit', 'revenuecat', 'manual', 'legacy')
  ),
  CONSTRAINT entitlement_events_source_reference_check CHECK (
    char_length(source_reference) BETWEEN 1 AND 200
    AND source_reference ~ '^[A-Za-z0-9._:/-]+$'
  ),
  CONSTRAINT entitlement_events_provider_event_id_check CHECK (
    char_length(provider_event_id) BETWEEN 1 AND 200
    AND provider_event_id ~ '^[A-Za-z0-9._:/-]+$'
  ),
  CONSTRAINT entitlement_events_event_type_check CHECK (
    char_length(event_type) BETWEEN 1 AND 200
    AND event_type ~ '^[A-Za-z0-9._:/-]+$'
  ),
  CONSTRAINT entitlement_events_environment_check CHECK (
    environment IN ('sandbox', 'production', 'internal')
  ),
  CONSTRAINT entitlement_events_processing_result_check CHECK (
    processing_result IN ('received', 'applied', 'stale')
  )
);

CREATE UNIQUE INDEX entitlement_events_source_provider_event_key
  ON public.entitlement_events (source, provider_event_id);

CREATE INDEX entitlement_events_user_audit_idx
  ON public.entitlement_events (user_id, occurred_at DESC, id DESC);

CREATE OR REPLACE FUNCTION public.apply_entitlement_event(
  p_provider_event_id text,
  p_event_type text,
  p_user_id uuid,
  p_entitlement_key text,
  p_source text,
  p_source_reference text,
  p_status text,
  p_plan public.plan_enum,
  p_environment text,
  p_occurred_at timestamptz,
  p_starts_at timestamptz,
  p_access_expires_at timestamptz,
  p_grace_expires_at timestamptz,
  p_cancel_at_period_end boolean,
  p_reason_code text DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_event public.entitlement_events%ROWTYPE;
  v_entitlement public.user_entitlements%ROWTYPE;
  v_event_id text := btrim(COALESCE(p_provider_event_id, ''));
  v_event_type text := btrim(COALESCE(p_event_type, ''));
  v_entitlement_key text := btrim(COALESCE(p_entitlement_key, ''));
  v_source text := btrim(COALESCE(p_source, ''));
  v_source_reference text := btrim(COALESCE(p_source_reference, ''));
  v_status text := btrim(COALESCE(p_status, ''));
  v_environment text := btrim(COALESCE(p_environment, ''));
  v_reason_code text := NULLIF(btrim(COALESCE(p_reason_code, '')), '');
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.users domain_user WHERE domain_user.id = p_user_id
  ) THEN
    RAISE EXCEPTION 'invalid entitlement user' USING ERRCODE = '22023';
  END IF;
  IF char_length(v_event_id) NOT BETWEEN 1 AND 200
    OR v_event_id !~ '^[A-Za-z0-9._:/-]+$' THEN
    RAISE EXCEPTION 'invalid provider event id' USING ERRCODE = '22023';
  END IF;
  IF char_length(v_event_type) NOT BETWEEN 1 AND 200
    OR v_event_type !~ '^[A-Za-z0-9._:/-]+$' THEN
    RAISE EXCEPTION 'invalid entitlement event type' USING ERRCODE = '22023';
  END IF;
  IF char_length(v_entitlement_key) NOT BETWEEN 1 AND 200
    OR v_entitlement_key !~ '^[A-Za-z0-9._:/-]+$' THEN
    RAISE EXCEPTION 'invalid entitlement key' USING ERRCODE = '22023';
  END IF;
  IF v_source NOT IN ('stripe', 'apple_storekit', 'revenuecat', 'manual', 'legacy') THEN
    RAISE EXCEPTION 'invalid entitlement source' USING ERRCODE = '22023';
  END IF;
  IF char_length(v_source_reference) NOT BETWEEN 1 AND 200
    OR v_source_reference !~ '^[A-Za-z0-9._:/-]+$' THEN
    RAISE EXCEPTION 'invalid entitlement source reference' USING ERRCODE = '22023';
  END IF;
  IF v_status NOT IN (
    'active',
    'trialing',
    'grace_period',
    'expired',
    'canceled',
    'grandfathered',
    'manual_comp',
    'blocked'
  ) THEN
    RAISE EXCEPTION 'invalid entitlement status' USING ERRCODE = '22023';
  END IF;
  IF v_environment NOT IN ('sandbox', 'production', 'internal') THEN
    RAISE EXCEPTION 'invalid entitlement environment' USING ERRCODE = '22023';
  END IF;
  IF p_occurred_at IS NULL THEN
    RAISE EXCEPTION 'entitlement event time is required' USING ERRCODE = '22023';
  END IF;
  IF p_starts_at IS NOT NULL
    AND p_access_expires_at IS NOT NULL
    AND p_starts_at > p_access_expires_at THEN
    RAISE EXCEPTION 'entitlement expiry precedes start' USING ERRCODE = '22023';
  END IF;
  IF p_access_expires_at IS NOT NULL
    AND p_grace_expires_at IS NOT NULL
    AND p_access_expires_at > p_grace_expires_at THEN
    RAISE EXCEPTION 'entitlement grace precedes expiry' USING ERRCODE = '22023';
  END IF;
  IF v_source IN ('stripe', 'apple_storekit', 'revenuecat')
    AND v_status IN ('active', 'trialing')
    AND p_access_expires_at IS NULL THEN
    RAISE EXCEPTION 'provider access requires expiry' USING ERRCODE = '22023';
  END IF;
  IF v_status = 'grace_period' AND p_grace_expires_at IS NULL THEN
    RAISE EXCEPTION 'grace period requires expiry' USING ERRCODE = '22023';
  END IF;
  IF v_reason_code IS NOT NULL AND (
    char_length(v_reason_code) NOT BETWEEN 1 AND 64
    OR v_reason_code !~ '^[a-z][a-z0-9_]*$'
  ) THEN
    RAISE EXCEPTION 'invalid entitlement reason' USING ERRCODE = '22023';
  END IF;
  IF v_source = 'manual' AND (v_reason_code IS NULL OR p_actor_id IS NULL) THEN
    RAISE EXCEPTION 'manual entitlement requires audit context' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.entitlement_events (
    user_id,
    entitlement_key,
    source,
    source_reference,
    provider_event_id,
    event_type,
    environment,
    occurred_at
  ) VALUES (
    p_user_id,
    v_entitlement_key,
    v_source,
    v_source_reference,
    v_event_id,
    v_event_type,
    v_environment,
    p_occurred_at
  )
  ON CONFLICT (source, provider_event_id) DO NOTHING
  RETURNING * INTO v_event;

  IF v_event.id IS NULL THEN
    SELECT *
    INTO v_event
    FROM public.entitlement_events event
    WHERE event.source = v_source
      AND event.provider_event_id = v_event_id;

    IF v_event.user_id <> p_user_id
      OR v_event.entitlement_key <> v_entitlement_key
      OR v_event.source_reference <> v_source_reference THEN
      RAISE unique_violation USING MESSAGE = 'provider event identity conflict';
    END IF;

    RETURN jsonb_build_object(
      'result', 'duplicate',
      'event_id', v_event.id,
      'entitlement_id', v_event.entitlement_id
    );
  END IF;

  SELECT *
  INTO v_entitlement
  FROM public.user_entitlements entitlement
  WHERE entitlement.source = v_source
    AND entitlement.source_reference = v_source_reference
    AND entitlement.entitlement_key = v_entitlement_key
  FOR UPDATE;

  IF v_entitlement.id IS NOT NULL AND v_entitlement.user_id <> p_user_id THEN
    RAISE unique_violation USING MESSAGE = 'entitlement source reference identity conflict';
  END IF;

  IF v_entitlement.id IS NOT NULL AND (
    p_occurred_at < v_entitlement.last_provider_event_at
    OR (
      p_occurred_at = v_entitlement.last_provider_event_at
      AND v_event_id <= v_entitlement.last_provider_event_id
    )
  ) THEN
    UPDATE public.entitlement_events
    SET entitlement_id = v_entitlement.id,
        processing_result = 'stale',
        processed_at = clock_timestamp()
    WHERE id = v_event.id;

    RETURN jsonb_build_object(
      'result', 'stale',
      'event_id', v_event.id,
      'entitlement_id', v_entitlement.id
    );
  END IF;

  IF v_entitlement.id IS NULL THEN
    INSERT INTO public.user_entitlements (
      user_id,
      entitlement_key,
      source,
      source_reference,
      status,
      plan,
      environment,
      starts_at,
      access_expires_at,
      grace_expires_at,
      cancel_at_period_end,
      last_provider_event_id,
      last_provider_event_at,
      reason_code,
      actor_id
    ) VALUES (
      p_user_id,
      v_entitlement_key,
      v_source,
      v_source_reference,
      v_status,
      p_plan,
      v_environment,
      p_starts_at,
      p_access_expires_at,
      p_grace_expires_at,
      COALESCE(p_cancel_at_period_end, false),
      v_event_id,
      p_occurred_at,
      v_reason_code,
      p_actor_id
    )
    RETURNING * INTO v_entitlement;
  ELSE
    UPDATE public.user_entitlements
    SET status = v_status,
        plan = p_plan,
        environment = v_environment,
        starts_at = p_starts_at,
        access_expires_at = p_access_expires_at,
        grace_expires_at = p_grace_expires_at,
        cancel_at_period_end = COALESCE(p_cancel_at_period_end, false),
        last_provider_event_id = v_event_id,
        last_provider_event_at = p_occurred_at,
        reason_code = v_reason_code,
        actor_id = p_actor_id,
        updated_at = clock_timestamp()
    WHERE id = v_entitlement.id
    RETURNING * INTO v_entitlement;
  END IF;

  UPDATE public.entitlement_events
  SET entitlement_id = v_entitlement.id,
      processing_result = 'applied',
      processed_at = clock_timestamp()
  WHERE id = v_event.id;

  RETURN jsonb_build_object(
    'result', 'applied',
    'event_id', v_event.id,
    'entitlement_id', v_entitlement.id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_user_entitlement(
  p_user_id uuid,
  p_entitlement_key text DEFAULT 'bodyflow_full',
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_key text := btrim(COALESCE(p_entitlement_key, ''));
  v_record record;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.users domain_user WHERE domain_user.id = p_user_id
  ) THEN
    RAISE EXCEPTION 'invalid entitlement user' USING ERRCODE = '22023';
  END IF;
  IF p_now IS NULL THEN
    RAISE EXCEPTION 'entitlement decision time is required' USING ERRCODE = '22023';
  END IF;
  IF char_length(v_key) NOT BETWEEN 1 AND 200 OR v_key !~ '^[A-Za-z0-9._:/-]+$' THEN
    RAISE EXCEPTION 'invalid entitlement key' USING ERRCODE = '22023';
  END IF;

  SELECT
    false AS has_active_access,
    entitlement.status,
    entitlement.source,
    entitlement.plan::text AS plan,
    entitlement.access_expires_at,
    entitlement.grace_expires_at,
    entitlement.cancel_at_period_end,
    'blocked'::text AS reason
  INTO v_record
  FROM public.user_entitlements entitlement
  WHERE entitlement.user_id = p_user_id
    AND entitlement.entitlement_key = v_key
    AND entitlement.status = 'blocked'
    AND (entitlement.starts_at IS NULL OR entitlement.starts_at <= p_now)
    AND (entitlement.access_expires_at IS NULL OR entitlement.access_expires_at > p_now)
  ORDER BY entitlement.updated_at DESC, entitlement.id DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'entitlement', v_key,
      'has_active_access', v_record.has_active_access,
      'status', v_record.status,
      'source', v_record.source,
      'plan', v_record.plan,
      'access_expires_at', v_record.access_expires_at,
      'grace_expires_at', v_record.grace_expires_at,
      'cancel_at_period_end', v_record.cancel_at_period_end,
      'reason', v_record.reason,
      'decision_at', p_now
    );
  END IF;

  WITH canonical AS (
    SELECT
      true AS has_active_access,
      entitlement.status,
      entitlement.source,
      entitlement.plan::text AS plan,
      entitlement.access_expires_at,
      entitlement.grace_expires_at,
      entitlement.cancel_at_period_end,
      CASE entitlement.status
        WHEN 'canceled' THEN 'canceled_until_expiry'
        WHEN 'grace_period' THEN 'grace_period'
        WHEN 'grandfathered' THEN 'grandfathered'
        WHEN 'manual_comp' THEN 'manual_comp'
        ELSE 'valid_entitlement'
      END AS reason,
      CASE entitlement.status
        WHEN 'active' THEN 700
        WHEN 'trialing' THEN 600
        WHEN 'grace_period' THEN 500
        WHEN 'grandfathered' THEN 400
        WHEN 'manual_comp' THEN 300
        WHEN 'canceled' THEN 200
        ELSE 0
      END AS priority,
      entitlement.updated_at,
      entitlement.id
    FROM public.user_entitlements entitlement
    WHERE entitlement.user_id = p_user_id
      AND entitlement.entitlement_key = v_key
      AND entitlement.status <> 'blocked'
      AND (entitlement.starts_at IS NULL OR entitlement.starts_at <= p_now)
      AND CASE entitlement.status
        WHEN 'active' THEN entitlement.access_expires_at > p_now
        WHEN 'trialing' THEN entitlement.access_expires_at > p_now
        WHEN 'grace_period' THEN entitlement.grace_expires_at > p_now
        WHEN 'grandfathered' THEN
          entitlement.access_expires_at IS NULL OR entitlement.access_expires_at > p_now
        WHEN 'manual_comp' THEN
          entitlement.access_expires_at IS NULL OR entitlement.access_expires_at > p_now
        WHEN 'canceled' THEN entitlement.access_expires_at > p_now
        ELSE false
      END
  ),
  legacy_stripe AS (
    SELECT
      true AS has_active_access,
      CASE subscription.status
        WHEN 'trial' THEN 'trialing'
        ELSE 'active'
      END AS status,
      'stripe'::text AS source,
      subscription.plan::text AS plan,
      subscription.current_period_end AS access_expires_at,
      NULL::timestamptz AS grace_expires_at,
      subscription.cancel_at_period_end,
      'legacy_subscription'::text AS reason,
      CASE subscription.status WHEN 'active' THEN 650 ELSE 550 END AS priority,
      subscription.updated_at,
      subscription.id
    FROM public.subscriptions subscription
    WHERE subscription.user_id = p_user_id
      AND subscription.provider = 'stripe'
      AND subscription.provider_subscription_id IS NOT NULL
      AND subscription.status IN ('active', 'trial')
      AND subscription.current_period_end > p_now
      AND (
        subscription.status <> 'trial'
        OR (subscription.trial_ends_at IS NOT NULL AND subscription.trial_ends_at > p_now)
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_entitlements entitlement
        WHERE entitlement.source = 'stripe'
          AND entitlement.source_reference = subscription.provider_subscription_id
          AND entitlement.entitlement_key = v_key
      )
  ),
  valid AS (
    SELECT * FROM canonical
    UNION ALL
    SELECT * FROM legacy_stripe
  )
  SELECT
    valid.has_active_access,
    valid.status,
    valid.source,
    valid.plan,
    valid.access_expires_at,
    valid.grace_expires_at,
    valid.cancel_at_period_end,
    valid.reason
  INTO v_record
  FROM valid
  ORDER BY
    valid.priority DESC,
    valid.access_expires_at DESC NULLS FIRST,
    valid.updated_at DESC,
    valid.id DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'entitlement', v_key,
      'has_active_access', v_record.has_active_access,
      'status', v_record.status,
      'source', v_record.source,
      'plan', v_record.plan,
      'access_expires_at', v_record.access_expires_at,
      'grace_expires_at', v_record.grace_expires_at,
      'cancel_at_period_end', v_record.cancel_at_period_end,
      'reason', v_record.reason,
      'decision_at', p_now
    );
  END IF;

  WITH denied AS (
    SELECT
      CASE
        WHEN entitlement.status IN ('expired', 'canceled') THEN entitlement.status
        ELSE 'expired'
      END AS status,
      entitlement.source,
      entitlement.plan::text AS plan,
      entitlement.access_expires_at,
      entitlement.grace_expires_at,
      entitlement.cancel_at_period_end,
      CASE
        WHEN entitlement.status = 'canceled' THEN 'canceled'
        ELSE 'expired_entitlement'
      END AS reason,
      entitlement.last_provider_event_at AS ordered_at,
      entitlement.id
    FROM public.user_entitlements entitlement
    WHERE entitlement.user_id = p_user_id
      AND entitlement.entitlement_key = v_key
      AND NOT (
        entitlement.status = 'blocked'
        AND (entitlement.starts_at IS NULL OR entitlement.starts_at <= p_now)
        AND (entitlement.access_expires_at IS NULL OR entitlement.access_expires_at > p_now)
      )
    UNION ALL
    SELECT
      'expired'::text AS status,
      'stripe'::text AS source,
      subscription.plan::text AS plan,
      subscription.current_period_end AS access_expires_at,
      NULL::timestamptz AS grace_expires_at,
      subscription.cancel_at_period_end,
      'expired_entitlement'::text AS reason,
      subscription.updated_at AS ordered_at,
      subscription.id
    FROM public.subscriptions subscription
    WHERE subscription.user_id = p_user_id
      AND subscription.provider = 'stripe'
      AND subscription.provider_subscription_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_entitlements entitlement
        WHERE entitlement.source = 'stripe'
          AND entitlement.source_reference = subscription.provider_subscription_id
          AND entitlement.entitlement_key = v_key
      )
  )
  SELECT
    false AS has_active_access,
    denied.status,
    denied.source,
    denied.plan,
    denied.access_expires_at,
    denied.grace_expires_at,
    denied.cancel_at_period_end,
    denied.reason
  INTO v_record
  FROM denied
  ORDER BY denied.ordered_at DESC, denied.id DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'entitlement', v_key,
      'has_active_access', v_record.has_active_access,
      'status', v_record.status,
      'source', v_record.source,
      'plan', v_record.plan,
      'access_expires_at', v_record.access_expires_at,
      'grace_expires_at', v_record.grace_expires_at,
      'cancel_at_period_end', v_record.cancel_at_period_end,
      'reason', v_record.reason,
      'decision_at', p_now
    );
  END IF;

  RETURN jsonb_build_object(
    'entitlement', v_key,
    'has_active_access', false,
    'status', 'expired',
    'source', NULL,
    'plan', NULL,
    'access_expires_at', NULL,
    'grace_expires_at', NULL,
    'cancel_at_period_end', false,
    'reason', 'no_entitlement',
    'decision_at', p_now
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_stripe_subscription_entitlement(
  p_subscription_id uuid,
  p_provider_event_id text,
  p_occurred_at timestamptz,
  p_environment text DEFAULT 'internal'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, pg_temp
AS $$
DECLARE
  v_subscription public.subscriptions%ROWTYPE;
  v_status text;
  v_grace_expires_at timestamptz;
BEGIN
  PERFORM private.assert_trusted_backend();

  IF p_subscription_id IS NULL OR p_occurred_at IS NULL THEN
    RAISE EXCEPTION 'Stripe entitlement sync requires subscription and event time'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_subscription
  FROM public.subscriptions subscription
  WHERE subscription.id = p_subscription_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stripe subscription not found' USING ERRCODE = '22023';
  END IF;
  IF v_subscription.provider <> 'stripe'
    OR NULLIF(btrim(v_subscription.provider_subscription_id), '') IS NULL THEN
    RAISE EXCEPTION 'invalid Stripe subscription projection' USING ERRCODE = '22023';
  END IF;

  v_status := CASE v_subscription.status
    WHEN 'active' THEN 'active'
    WHEN 'trial' THEN 'trialing'
    WHEN 'past_due' THEN
      CASE
        WHEN v_subscription.current_period_end > p_occurred_at THEN 'grace_period'
        ELSE 'expired'
      END
    WHEN 'canceled' THEN 'canceled'
    ELSE 'expired'
  END;

  v_grace_expires_at := CASE
    WHEN v_status = 'grace_period' THEN v_subscription.current_period_end
    ELSE NULL
  END;

  RETURN public.apply_entitlement_event(
    p_provider_event_id,
    'STRIPE_SUBSCRIPTION_SYNC',
    v_subscription.user_id,
    'bodyflow_full',
    'stripe',
    v_subscription.provider_subscription_id,
    v_status,
    v_subscription.plan,
    p_environment,
    p_occurred_at,
    v_subscription.current_period_start,
    v_subscription.current_period_end,
    v_grace_expires_at,
    v_subscription.cancel_at_period_end,
    NULL,
    NULL
  );
END;
$$;

COMMENT ON TABLE public.user_entitlements IS
  'Provider-neutral BodyFlow access projections. Provider identifiers are backend-only.';
COMMENT ON TABLE public.entitlement_events IS
  'Sanitized idempotency and audit ledger for entitlement state transitions.';
COMMENT ON FUNCTION public.apply_entitlement_event(
  text, text, uuid, text, text, text, text, public.plan_enum, text,
  timestamptz, timestamptz, timestamptz, timestamptz, boolean, text, uuid
) IS 'Applies one ordered, idempotent normalized entitlement event.';
COMMENT ON FUNCTION public.resolve_user_entitlement(uuid, text, timestamptz) IS
  'Returns the bounded patient-safe BodyFlow access decision.';
COMMENT ON FUNCTION public.sync_stripe_subscription_entitlement(uuid, text, timestamptz, text) IS
  'Projects one persisted legacy Stripe subscription into central entitlements.';
