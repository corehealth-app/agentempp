import { createHmac } from 'node:crypto'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const database = vi.hoisted(() => ({ rpc: vi.fn(), create: vi.fn() }))
vi.mock('@/lib/supabase/server', () => ({ createServiceClient: database.create }))
const secret = 'synthetic-signing-secret-with-enough-length'

function providerConfiguration() {
  vi.stubEnv('REVENUECAT_WEBHOOK_SIGNING_SECRET', secret)
  vi.stubEnv('REVENUECAT_WEBHOOK_ENVIRONMENT', 'sandbox')
  vi.stubEnv('REVENUECAT_PRODUCT_PLAN_MAP', '{"synthetic_monthly":"mensal"}')
}

function signedRequest(rawBody: string): Request {
  const timestamp = Math.floor(Date.now() / 1000)
  const digest = createHmac('sha256', secret).update(`${timestamp}.${rawBody}`).digest('hex')
  return new Request('https://example.test/api/webhooks/revenuecat', {
    method: 'POST',
    body: rawBody,
    headers: {
      'content-type': 'application/json',
      'x-revenuecat-webhook-signature': `t=${timestamp},v1=${digest}`,
    },
  })
}

describe('RevenueCat BFF HTTP entry', () => {
  beforeEach(() => {
    database.rpc.mockReset()
    database.create.mockReset().mockReturnValue({ rpc: database.rpc })
  })
  afterEach(() => vi.unstubAllEnvs())

  it('stays unavailable without provider configuration before database access', async () => {
    vi.stubEnv('REVENUECAT_WEBHOOK_SIGNING_SECRET', undefined)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', undefined)
    vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', undefined)
    const route = await import('./app/api/webhooks/revenuecat/route')
    expect(Object.keys(route).sort()).toEqual(['POST', 'runtime'])
    expect(route.runtime).toBe('nodejs')
    const response = await route.POST(
      new Request('https://example.test/api/webhooks/revenuecat', {
        method: 'POST',
        body: '{}',
        headers: { 'content-type': 'application/json' },
      }),
    )
    expect(response.status).toBe(503)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(await response.json()).toEqual({ ok: false, error: 'provider_not_configured' })
    expect(database.create).not.toHaveBeenCalled()
  })

  it('checks signatures using request-time configuration without a database credential', async () => {
    providerConfiguration()
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', undefined)
    vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', undefined)
    const { POST } = await import('./app/api/webhooks/revenuecat/route')
    const response = await POST(
      new Request('https://example.test/api/webhooks/revenuecat', {
        method: 'POST',
        body: '{}',
        headers: { 'content-type': 'application/json' },
      }),
    )
    expect(response.status).toBe(401)
    expect(await response.json()).toEqual({ ok: false, error: 'invalid_signature' })
    vi.stubEnv('REVENUECAT_WEBHOOK_SIGNING_SECRET', undefined)
    expect((await POST(new Request('https://example.test', { method: 'POST' }))).status).toBe(503)
    expect(database.create).not.toHaveBeenCalled()
  })

  it('rejects an oversized signed body before creating the service client', async () => {
    providerConfiguration()
    const { POST } = await import('./app/api/webhooks/revenuecat/route')
    const response = await POST(signedRequest('x'.repeat(256 * 1024 + 1)))
    expect(response.status).toBe(413)
    expect(await response.json()).toEqual({ ok: false, error: 'request_too_large' })
    expect(database.create).not.toHaveBeenCalled()
  })

  it.each([
    'applied',
    'duplicate',
    'stale',
  ])('acknowledges persisted %s through the real BFF entry', async (result) => {
    providerConfiguration()
    database.rpc.mockResolvedValue({ data: { result }, error: null })
    const now = Date.now()
    const request = signedRequest(
      JSON.stringify({
        api_version: '1.0',
        event: {
          id: 'synthetic-rc-001',
          type: 'INITIAL_PURCHASE',
          app_user_id: '00000000-0000-4000-8000-000000000001',
          entitlement_ids: ['bodyflow_full'],
          environment: 'SANDBOX',
          event_timestamp_ms: now,
          purchased_at_ms: now,
          expiration_at_ms: now + 30 * 24 * 60 * 60 * 1000,
          product_id: 'synthetic_monthly',
          original_transaction_id: 'synthetic-original-001',
          period_type: 'NORMAL',
          store: 'APP_STORE',
        },
      }),
    )
    const { POST } = await import('./app/api/webhooks/revenuecat/route')
    const response = await POST(request)
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ ok: true, result })
    expect(database.create).toHaveBeenCalledOnce()
    expect(database.rpc).toHaveBeenCalledOnce()
    expect(database.rpc).toHaveBeenCalledWith(
      'apply_entitlement_event',
      expect.objectContaining({
        p_provider_event_id: 'synthetic-rc-001',
        p_user_id: '00000000-0000-4000-8000-000000000001',
        p_source: 'revenuecat',
        p_source_reference: 'synthetic-original-001',
        p_plan: 'mensal',
        p_environment: 'sandbox',
        p_status: 'active',
      }),
    )
  })
})
