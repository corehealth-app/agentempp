type StripeEventIdentity = {
  id: string
  created: number
  livemode: boolean
}

type StripeBillingContext = {
  subscription_id?: string
}

export type StripeEntitlementSyncInput = {
  p_subscription_id: string
  p_provider_event_id: string
  p_occurred_at: string
  p_environment: 'sandbox' | 'production'
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const PROVIDER_EVENT_PATTERN = /^[A-Za-z0-9._:/-]{1,200}$/

export function buildStripeEntitlementSyncInput(
  event: StripeEventIdentity,
  context: StripeBillingContext,
): StripeEntitlementSyncInput | null {
  if (!context.subscription_id) return null
  if (!UUID_PATTERN.test(context.subscription_id)) {
    throw new Error('invalid internal subscription id')
  }
  if (!PROVIDER_EVENT_PATTERN.test(event.id)) {
    throw new Error('invalid Stripe event id')
  }
  if (!Number.isFinite(event.created) || event.created <= 0) {
    throw new Error('invalid Stripe event time')
  }

  const occurredAt = new Date(event.created * 1000)
  if (!Number.isFinite(occurredAt.getTime())) {
    throw new Error('invalid Stripe event time')
  }

  return {
    p_subscription_id: context.subscription_id,
    p_provider_event_id: event.id,
    p_occurred_at: occurredAt.toISOString(),
    p_environment: event.livemode ? 'production' : 'sandbox',
  }
}
