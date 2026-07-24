import { assertEquals, assertThrows } from 'jsr:@std/assert@1'
import { buildStripeEntitlementSyncInput } from './stripe-entitlement.ts'

const SUBSCRIPTION_ID = '00000000-0000-4000-8000-000000000001'

Deno.test('builds a sandbox entitlement projection from Stripe event time', () => {
  assertEquals(
    buildStripeEntitlementSyncInput(
      { id: 'evt_test_001', created: 1784887200, livemode: false },
      { subscription_id: SUBSCRIPTION_ID },
    ),
    {
      p_subscription_id: SUBSCRIPTION_ID,
      p_provider_event_id: 'evt_test_001',
      p_occurred_at: '2026-07-24T10:00:00.000Z',
      p_environment: 'sandbox',
    },
  )
})

Deno.test('marks live Stripe events as production', () => {
  const result = buildStripeEntitlementSyncInput(
    { id: 'evt_live_001', created: 1784887200, livemode: true },
    { subscription_id: SUBSCRIPTION_ID },
  )

  assertEquals(result?.p_environment, 'production')
})

Deno.test('does not project events that did not mutate a subscription', () => {
  assertEquals(
    buildStripeEntitlementSyncInput(
      { id: 'evt_no_subscription', created: 1784887200, livemode: false },
      {},
    ),
    null,
  )
})

Deno.test('rejects malformed event identity and timestamp', () => {
  assertThrows(() =>
    buildStripeEntitlementSyncInput(
      { id: '', created: 1784887200, livemode: false },
      { subscription_id: SUBSCRIPTION_ID },
    ),
  )
  assertThrows(() =>
    buildStripeEntitlementSyncInput(
      { id: 'evt_invalid_time', created: Number.NaN, livemode: false },
      { subscription_id: SUBSCRIPTION_ID },
    ),
  )
})
