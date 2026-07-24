import { createHmac } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  normalizeRevenueCatEvent,
  parseRevenueCatProductPlanMap,
  RevenueCatWebhookError,
  verifyRevenueCatSignature,
} from './revenuecat-webhook'

const USER_ID = '00000000-0000-4000-8000-000000000001'
const NOW = new Date('2026-07-24T10:00:00.000Z')
const SECRET = 'sandbox-signing-secret-with-enough-entropy'

function signature(body: string, timestamp = Math.floor(NOW.getTime() / 1000)): string {
  const digest = createHmac('sha256', SECRET).update(`${timestamp}.${body}`).digest('hex')
  return `t=${timestamp},v1=${digest}`
}

function event(overrides: Record<string, unknown> = {}) {
  return {
    api_version: '1.0',
    event: {
      id: 'rc-event-001',
      type: 'INITIAL_PURCHASE',
      app_user_id: USER_ID,
      entitlement_ids: ['bodyflow_full'],
      environment: 'SANDBOX',
      event_timestamp_ms: NOW.getTime(),
      expiration_at_ms: Date.parse('2026-08-24T10:00:00.000Z'),
      purchased_at_ms: NOW.getTime(),
      product_id: 'bodyflow_monthly',
      original_transaction_id: 'original-transaction-001',
      period_type: 'NORMAL',
      store: 'APP_STORE',
      ...overrides,
    },
  }
}

const configuration = {
  expectedEnvironment: 'sandbox' as const,
  entitlementKey: 'bodyflow_full',
  productPlanMap: { bodyflow_monthly: 'mensal' as const },
}

describe('RevenueCat signature verification', () => {
  it('verifies the exact raw body with a bounded replay window', () => {
    const body = JSON.stringify(event())
    expect(() =>
      verifyRevenueCatSignature({ body, header: signature(body), secret: SECRET, now: NOW }),
    ).not.toThrow()
  })

  it('rejects body tampering, stale timestamps and ambiguous signatures', () => {
    const body = JSON.stringify(event())
    expect(() =>
      verifyRevenueCatSignature({
        body: `${body} `,
        header: signature(body),
        secret: SECRET,
        now: NOW,
      }),
    ).toThrow(RevenueCatWebhookError)
    expect(() =>
      verifyRevenueCatSignature({
        body,
        header: signature(body, Math.floor(NOW.getTime() / 1000) - 301),
        secret: SECRET,
        now: NOW,
      }),
    ).toThrow(/timestamp/i)
    expect(() =>
      verifyRevenueCatSignature({
        body,
        header: `${signature(body)},v1=${'0'.repeat(64)}`,
        secret: SECRET,
        now: NOW,
      }),
    ).toThrow(/signature/i)
  })
})

describe('RevenueCat event normalization', () => {
  it('normalizes an App Store purchase into a central entitlement event', () => {
    expect(normalizeRevenueCatEvent(event(), configuration)).toEqual({
      kind: 'apply',
      event: {
        event_id: 'rc-event-001',
        event_type: 'INITIAL_PURCHASE',
        user_id: USER_ID,
        entitlement_key: 'bodyflow_full',
        source: 'revenuecat',
        source_reference: 'original-transaction-001',
        status: 'active',
        plan: 'mensal',
        environment: 'sandbox',
        occurred_at: '2026-07-24T10:00:00.000Z',
        starts_at: '2026-07-24T10:00:00.000Z',
        access_expires_at: '2026-08-24T10:00:00.000Z',
        grace_expires_at: null,
        cancel_at_period_end: false,
      },
    })
  })

  it('maps trials, paid-through cancellation, expiration and grace period explicitly', () => {
    expect(normalizeRevenueCatEvent(event({ period_type: 'TRIAL' }), configuration)).toMatchObject({
      kind: 'apply',
      event: { status: 'trialing' },
    })
    expect(
      normalizeRevenueCatEvent(
        event({ type: 'CANCELLATION', cancel_reason: 'UNSUBSCRIBE' }),
        configuration,
      ),
    ).toMatchObject({
      kind: 'apply',
      event: { status: 'canceled', cancel_at_period_end: true },
    })
    expect(
      normalizeRevenueCatEvent(
        event({ type: 'CANCELLATION', cancel_reason: 'CUSTOMER_SUPPORT' }),
        configuration,
      ),
    ).toMatchObject({
      kind: 'apply',
      event: { status: 'expired', cancel_at_period_end: false },
    })
    expect(
      normalizeRevenueCatEvent(
        event({ type: 'CANCELLATION', cancel_reason: 'BILLING_ERROR' }),
        configuration,
      ),
    ).toEqual({ kind: 'ignored', reason: 'billing_error_cancellation' })
    expect(normalizeRevenueCatEvent(event({ type: 'EXPIRATION' }), configuration)).toMatchObject({
      kind: 'apply',
      event: { status: 'expired', cancel_at_period_end: false },
    })
    expect(
      normalizeRevenueCatEvent(
        event({
          type: 'BILLING_ISSUE',
          grace_period_expiration_at_ms: Date.parse('2026-08-27T10:00:00.000Z'),
        }),
        configuration,
      ),
    ).toMatchObject({
      kind: 'apply',
      event: {
        status: 'grace_period',
        grace_expires_at: '2026-08-27T10:00:00.000Z',
      },
    })
    expect(
      normalizeRevenueCatEvent(event({ type: 'REFUND_REVERSED' }), configuration),
    ).toMatchObject({
      kind: 'apply',
      event: { status: 'active', cancel_at_period_end: false },
    })
  })

  it('requires reconciliation for ambiguous cancellation reasons', () => {
    expect(() => normalizeRevenueCatEvent(event({ type: 'CANCELLATION' }), configuration)).toThrow(
      /reconciliation/i,
    )
    expect(() =>
      normalizeRevenueCatEvent(
        event({ type: 'CANCELLATION', cancel_reason: 'UNKNOWN' }),
        configuration,
      ),
    ).toThrow(/reconciliation/i)
  })

  it('ignores state-neutral events and requires reconciliation for transfers', () => {
    expect(normalizeRevenueCatEvent(event({ type: 'PRODUCT_CHANGE' }), configuration)).toEqual({
      kind: 'ignored',
      reason: 'state_neutral_event',
    })
    expect(() => normalizeRevenueCatEvent(event({ type: 'TRANSFER' }), configuration)).toThrow(
      /reconciliation/i,
    )
  })

  it('rejects a wrong environment, unknown entitlement, product or patient identity', () => {
    expect(() =>
      normalizeRevenueCatEvent(event({ environment: 'PRODUCTION' }), configuration),
    ).toThrow(/environment/i)
    expect(() =>
      normalizeRevenueCatEvent(event({ entitlement_ids: ['another_product'] }), configuration),
    ).toThrow(/entitlement/i)
    expect(() =>
      normalizeRevenueCatEvent(event({ product_id: 'unknown_product' }), configuration),
    ).toThrow(/product/i)
    expect(() =>
      normalizeRevenueCatEvent(event({ app_user_id: 'anonymous-user' }), configuration),
    ).toThrow(/payload/i)
  })
})

describe('RevenueCat product-plan configuration', () => {
  it('parses a bounded exact product mapping', () => {
    expect(
      parseRevenueCatProductPlanMap(
        JSON.stringify({ bodyflow_monthly: 'mensal', bodyflow_annual: 'anual' }),
      ),
    ).toEqual({ bodyflow_monthly: 'mensal', bodyflow_annual: 'anual' })
  })

  it('rejects empty, malformed and unknown plan mappings', () => {
    expect(() => parseRevenueCatProductPlanMap('{}')).toThrow()
    expect(() => parseRevenueCatProductPlanMap('{')).toThrow()
    expect(() => parseRevenueCatProductPlanMap('{"bodyflow_monthly":"weekly"}')).toThrow()
  })
})
