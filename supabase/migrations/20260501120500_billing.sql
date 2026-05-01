-- ============================================================================
-- Migration 0006: Billing (Stripe)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- subscriptions
-- ----------------------------------------------------------------------------
CREATE TABLE subscriptions (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider                 text NOT NULL DEFAULT 'stripe',
  provider_subscription_id text UNIQUE,
  plan                     plan_enum NOT NULL,
  status                   sub_status NOT NULL,
  current_period_start     timestamptz,
  current_period_end       timestamptz,
  trial_ends_at            timestamptz,
  cancel_at_period_end     boolean NOT NULL DEFAULT false,
  metadata                 jsonb,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_sub_user_status ON subscriptions(user_id, status);
CREATE INDEX idx_sub_active ON subscriptions(status) WHERE status IN ('active', 'trial');

-- ----------------------------------------------------------------------------
-- subscription_events (idempotência por provider_event_id)
-- ----------------------------------------------------------------------------
CREATE TABLE subscription_events (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id     uuid REFERENCES subscriptions(id) ON DELETE SET NULL,
  user_id             uuid REFERENCES users(id) ON DELETE SET NULL,
  event_type          text NOT NULL,
  amount_cents        integer,
  currency            text NOT NULL DEFAULT 'BRL',
  provider_event_id   text UNIQUE,
  payload             jsonb,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_sub_events_user ON subscription_events(user_id, created_at DESC);
CREATE INDEX idx_sub_events_type ON subscription_events(event_type, created_at DESC);

COMMENT ON COLUMN subscription_events.provider_event_id IS 'ID do evento no Stripe. UNIQUE garante idempotência do webhook.';
