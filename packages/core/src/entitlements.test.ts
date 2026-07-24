import { describe, expect, it } from 'vitest'
import {
  compareEntitlementEventOrder,
  entitlementDecisionSchema,
  entitlementEnvironmentSchema,
  entitlementSourceSchema,
  entitlementStatusSchema,
  normalizedEntitlementEventSchema,
} from './entitlements.js'

const USER_ID = '00000000-0000-4000-8000-000000000001'

describe('entitlement contracts', () => {
  it('accepts only the approved statuses, sources and environments', () => {
    expect(entitlementStatusSchema.options).toEqual([
      'active',
      'trialing',
      'grace_period',
      'expired',
      'canceled',
      'grandfathered',
      'manual_comp',
      'blocked',
    ])
    expect(entitlementSourceSchema.options).toEqual([
      'stripe',
      'apple_storekit',
      'revenuecat',
      'manual',
      'legacy',
    ])
    expect(entitlementEnvironmentSchema.options).toEqual(['sandbox', 'production', 'internal'])
  })

  it('parses a bounded patient-safe decision without provider references', () => {
    expect(
      entitlementDecisionSchema.parse({
        entitlement: 'bodyflow_full',
        has_active_access: true,
        status: 'active',
        source: 'revenuecat',
        plan: 'mensal',
        access_expires_at: '2026-08-24T00:00:00.000Z',
        grace_expires_at: null,
        cancel_at_period_end: false,
        reason: 'valid_entitlement',
        decision_at: '2026-07-24T00:00:00.000Z',
      }),
    ).toEqual({
      entitlement: 'bodyflow_full',
      has_active_access: true,
      status: 'active',
      source: 'revenuecat',
      plan: 'mensal',
      access_expires_at: '2026-08-24T00:00:00.000Z',
      grace_expires_at: null,
      cancel_at_period_end: false,
      reason: 'valid_entitlement',
      decision_at: '2026-07-24T00:00:00.000Z',
    })

    expect(() =>
      entitlementDecisionSchema.parse({
        entitlement: 'bodyflow_full',
        has_active_access: false,
        status: 'expired',
        source: null,
        plan: null,
        access_expires_at: null,
        grace_expires_at: null,
        cancel_at_period_end: false,
        reason: 'no_entitlement',
        decision_at: '2026-07-24T00:00:00.000Z',
        provider_subscription_id: 'must-not-leak',
      }),
    ).toThrow()
  })

  it('normalizes a strict entitlement event and trims controlled identifiers', () => {
    expect(
      normalizedEntitlementEventSchema.parse({
        event_id: ' event-001 ',
        event_type: ' INITIAL_PURCHASE ',
        user_id: USER_ID,
        entitlement_key: ' bodyflow_full ',
        source: 'revenuecat',
        source_reference: ' original-transaction-001 ',
        status: 'trialing',
        plan: 'mensal',
        environment: 'sandbox',
        occurred_at: '2026-07-24T10:00:00.000Z',
        starts_at: '2026-07-24T10:00:00.000Z',
        access_expires_at: '2026-08-24T10:00:00.000Z',
        grace_expires_at: null,
        cancel_at_period_end: false,
      }),
    ).toMatchObject({
      event_id: 'event-001',
      event_type: 'INITIAL_PURCHASE',
      entitlement_key: 'bodyflow_full',
      source_reference: 'original-transaction-001',
    })
  })

  it('rejects contradictory time bounds and unknown fields', () => {
    const base = {
      event_id: 'event-002',
      event_type: 'EXPIRATION',
      user_id: USER_ID,
      entitlement_key: 'bodyflow_full',
      source: 'revenuecat' as const,
      source_reference: 'transaction-002',
      status: 'expired' as const,
      plan: null,
      environment: 'sandbox' as const,
      occurred_at: '2026-07-24T10:00:00.000Z',
      starts_at: '2026-07-24T10:00:00.000Z',
      access_expires_at: '2026-07-23T10:00:00.000Z',
      grace_expires_at: '2026-07-22T10:00:00.000Z',
      cancel_at_period_end: false,
    }

    expect(() => normalizedEntitlementEventSchema.parse(base)).toThrow()
    expect(() => normalizedEntitlementEventSchema.parse({ ...base, unexpected: true })).toThrow()
  })
})

describe('entitlement event ordering', () => {
  it('orders first by provider time and then stable event id', () => {
    expect(
      compareEntitlementEventOrder(
        { occurredAt: '2026-07-24T10:01:00.000Z', eventId: 'a' },
        { occurredAt: '2026-07-24T10:00:00.000Z', eventId: 'z' },
      ),
    ).toBe(1)
    expect(
      compareEntitlementEventOrder(
        { occurredAt: '2026-07-24T10:00:00.000Z', eventId: 'b' },
        { occurredAt: '2026-07-24T10:00:00.000Z', eventId: 'a' },
      ),
    ).toBe(1)
    expect(
      compareEntitlementEventOrder(
        { occurredAt: '2026-07-24T10:00:00.000Z', eventId: 'a' },
        { occurredAt: '2026-07-24T10:00:00.000Z', eventId: 'a' },
      ),
    ).toBe(0)
  })
})
