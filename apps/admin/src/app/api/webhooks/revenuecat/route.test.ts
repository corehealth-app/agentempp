import { createHmac } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createRevenueCatWebhookHandler } from './handler'

const NOW = new Date('2026-07-24T10:00:00.000Z')
const SECRET = 'sandbox-signing-secret-with-enough-entropy'
const USER_ID = '00000000-0000-4000-8000-000000000001'

function body(): string {
  return JSON.stringify({
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
    },
  })
}

function signedRequest(rawBody = body()): Request {
  const timestamp = Math.floor(NOW.getTime() / 1000)
  const digest = createHmac('sha256', SECRET).update(`${timestamp}.${rawBody}`).digest('hex')
  return new Request('https://example.test/api/webhooks/revenuecat', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-revenuecat-webhook-signature': `t=${timestamp},v1=${digest}`,
    },
    body: rawBody,
  })
}

function runtime(overrides: Record<string, unknown> = {}) {
  const rpc = vi.fn().mockResolvedValue({
    data: { result: 'applied', event_id: 'internal-event-id' },
    error: null,
  })
  return {
    rpc,
    value: {
      now: () => NOW,
      createServiceClient: () => ({ rpc }) as unknown as ServiceClient,
      configuration: {
        signingSecret: SECRET,
        expectedEnvironment: 'sandbox' as const,
        entitlementKey: 'bodyflow_full',
        productPlanMap: { bodyflow_monthly: 'mensal' as const },
      },
      ...overrides,
    },
  }
}

describe('RevenueCat webhook route', () => {
  it('verifies, normalizes and applies one central entitlement event', async () => {
    const testRuntime = runtime()
    const handler = createRevenueCatWebhookHandler(testRuntime.value)

    const response = await handler(signedRequest())

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ ok: true, result: 'applied' })
    expect(testRuntime.rpc).toHaveBeenCalledWith('apply_entitlement_event', {
      p_provider_event_id: 'rc-event-001',
      p_event_type: 'INITIAL_PURCHASE',
      p_user_id: USER_ID,
      p_entitlement_key: 'bodyflow_full',
      p_source: 'revenuecat',
      p_source_reference: 'original-transaction-001',
      p_status: 'active',
      p_plan: 'mensal',
      p_environment: 'sandbox',
      p_occurred_at: '2026-07-24T10:00:00.000Z',
      p_starts_at: '2026-07-24T10:00:00.000Z',
      p_access_expires_at: '2026-08-24T10:00:00.000Z',
      p_grace_expires_at: null,
      p_cancel_at_period_end: false,
      p_reason_code: null,
      p_actor_id: null,
    })
  })

  it('stays unavailable before sandbox provider configuration exists', async () => {
    const testRuntime = runtime({ configuration: null })
    const response = await createRevenueCatWebhookHandler(testRuntime.value)(signedRequest())

    expect(response.status).toBe(503)
    expect(testRuntime.rpc).not.toHaveBeenCalled()
  })

  it('rejects an invalid signature before creating a service client', async () => {
    const createServiceClient = vi.fn()
    const testRuntime = runtime({ createServiceClient })
    const request = signedRequest()
    request.headers.set('x-revenuecat-webhook-signature', `t=1,v1=${'0'.repeat(64)}`)

    const response = await createRevenueCatWebhookHandler(testRuntime.value)(request)

    expect(response.status).toBe(401)
    expect(createServiceClient).not.toHaveBeenCalled()
  })

  it('rejects an oversized body before creating a service client', async () => {
    const createServiceClient = vi.fn()
    const testRuntime = runtime({ createServiceClient })
    const request = signedRequest('x'.repeat(256 * 1024 + 1))

    const response = await createRevenueCatWebhookHandler(testRuntime.value)(request)

    expect(response.status).toBe(413)
    expect(createServiceClient).not.toHaveBeenCalled()
  })

  it('returns a generic retryable error when persistence fails', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { message: 'provider receipt and database detail' },
    })
    const testRuntime = runtime({
      createServiceClient: () => ({ rpc }) as unknown as ServiceClient,
    })

    const response = await createRevenueCatWebhookHandler(testRuntime.value)(signedRequest())

    expect(response.status).toBe(500)
    const responseBody = await response.json()
    expect(responseBody).toEqual({ ok: false, error: 'persistence_failed' })
    expect(JSON.stringify(responseBody)).not.toContain('receipt')
  })
})
