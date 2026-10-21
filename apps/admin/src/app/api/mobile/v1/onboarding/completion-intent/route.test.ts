import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from '@/lib/mobile-api/auth'
import { authorizeMobileEntitlement } from '@/lib/mobile-api/entitlement-service'
import { MobileApiError } from '@/lib/mobile-api/http'
import { createMobileRoute, type MobileRouteRuntime } from '@/lib/mobile-api/route'
import { handleSignupCompletionIntentGet, handleSignupCompletionIntentPost } from './handler'

const OWNER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const Q = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const ID = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const ENDPOINT = 'https://app.example.invalid/api/mobile/v1/onboarding/completion-intent'
const REQUEST_ID = 'intent-route-test-1'
const receipt = () => ({
  userId: OWNER,
  preparationId: Q,
  intentId: ID,
  requestKey: `osc1:${ID}`,
  epoch: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  issuedAt: '2026-10-21T14:00:00.123456Z',
})
const publicReceipt = () => ({
  protocol: 'osc1',
  preparation_id: Q,
  intent_id: ID,
  request_key: `osc1:${ID}`,
})
function harness() {
  const rpc = vi.fn(async () => {
    throw new Error('unexpected direct RPC or HTTP claim')
  })
  const client = { rpc } as unknown as ServiceClient
  const auth: MobileAuthContext = {
    accessToken: 'synthetic-token',
    authUserId: ID,
    userId: OWNER,
    identity: {
      id: ID,
      email: 'synthetic@example.invalid',
      emailConfirmedAt: '2026-10-21T14:00:00Z',
    },
    patient: {
      id: OWNER,
      authUserId: ID,
      email: 'synthetic@example.invalid',
      name: 'Synthetic',
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
  const control = { enabled: true }
  const intents = {
    begin: vi.fn(async () => receipt()),
    resolve: vi.fn(async (): Promise<ReturnType<typeof receipt> | null> => receipt()),
    verify: vi.fn(async () => {
      throw new Error('intent endpoint must not verify a completion')
    }),
  }
  const composition = {
    enabled: vi.fn(() => control.enabled),
    createSources: vi.fn((_client: ServiceClient) => ({
      intents,
      admission: {
        bind: vi.fn(async () => {
          throw new Error('must not admit content')
        }),
      },
    })),
  }
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => auth),
    authorizeEntitlement: (authenticated, request, supabase) =>
      authorizeMobileEntitlement(supabase, authenticated.userId, new URL(request.url).pathname),
    createServiceClient: () => client,
    createRequestId: () => REQUEST_ID,
  }
  const get = createMobileRoute((ctx) => handleSignupCompletionIntentGet(ctx, composition), runtime)
  const post = createMobileRoute(
    (ctx) => handleSignupCompletionIntentPost(ctx, composition),
    runtime,
  )
  return { get, post, runtime, composition, intents, control, rpc, client }
}
function postRequest(body: unknown = { preparation_id: Q }, key: string | null = Q) {
  return new Request(ENDPOINT, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(key === null ? {} : { 'idempotency-key': key }),
    },
    body: JSON.stringify(body),
  })
}

describe('signup completion intent endpoint', () => {
  it('issues only for the authenticated owner and returns no epoch, profile or clock', async () => {
    const h = harness()
    const response = await h.post(postRequest())
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({ completion_intent: publicReceipt() })
    expect(h.intents.begin).toHaveBeenCalledWith({ userId: OWNER, preparationId: Q })
    expect(h.composition.createSources).toHaveBeenCalledWith(h.client)
    expect(h.intents.resolve).not.toHaveBeenCalled()
    expect(h.intents.verify).not.toHaveBeenCalled()
    // The real entitlement guard exempts this child route; no fake grant or ledger.
    expect(h.rpc).not.toHaveBeenCalled()
    expect(response.headers.get('Cache-Control')).toBe('no-store')
  })

  it('resolves with a read and never creates a replacement', async () => {
    const h = harness()
    const response = await h.get(new Request(`${ENDPOINT}?preparation_id=${Q}`))
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({ completion_intent: publicReceipt() })
    expect(h.intents.resolve).toHaveBeenCalledWith({ userId: OWNER, preparationId: Q })
    expect(h.intents.begin).not.toHaveBeenCalled()
    expect(h.rpc).not.toHaveBeenCalled()
  })

  it('keeps absent explicit without issuing another identity', async () => {
    const h = harness()
    h.intents.resolve.mockResolvedValue(null)
    const response = await h.get(new Request(`${ENDPOINT}?preparation_id=${Q}`))
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({ completion_intent: null })
    expect(h.intents.begin).not.toHaveBeenCalled()
    expect(h.intents.resolve).toHaveBeenCalledOnce()
  })

  it.each(['get', 'post'] as const)('OFF %s stops before constructing sources', async (method) => {
    const h = harness()
    h.control.enabled = false
    const response = await h[method](
      method === 'get' ? new Request(`${ENDPOINT}?preparation_id=${Q}`) : postRequest(),
    )
    expect(response.status).toBe(503)
    expect((await response.json()).error.code).toBe('signup_completion_unavailable')
    expect(h.composition.createSources).not.toHaveBeenCalled()
    expect(h.rpc).not.toHaveBeenCalled()
  })

  it.each([
    ['', Q],
    [Q, null],
    [Q, ID],
    [Q, `osc1:${Q}`],
  ])('refuses malformed or inconsistent preparation/header before sources (%s/%s)', async (q, key) => {
    const h = harness()
    const response = await h.post(postRequest({ preparation_id: q }, key))
    expect(response.status).toBe(400)
    expect(h.composition.createSources).not.toHaveBeenCalled()
  })

  it('never accepts caller-owned user IDs in the preparation body', async () => {
    const h = harness()
    const response = await h.post(postRequest({ preparation_id: Q, user_id: ID }))
    expect(response.status).toBe(400)
    expect(h.composition.createSources).not.toHaveBeenCalled()
  })

  it.each([
    '',
    '?preparation_id=invalid',
    `?preparation_id=${Q}&preparation_id=${Q}`,
    `?preparation_id=${Q}&user_id=${ID}`,
  ])('rejects ambiguous resolution input %s before sources', async (query) => {
    const h = harness()
    expect((await h.get(new Request(ENDPOINT + query))).status).toBe(400)
    expect(h.composition.createSources).not.toHaveBeenCalled()
  })

  it('does not turn an uncertain begin into a server retry or automatic resolution', async () => {
    const h = harness()
    h.intents.begin.mockRejectedValue(
      new MobileApiError(500, 'mobile_signup_completion_intent_unavailable', 'Unavailable'),
    )
    const response = await h.post(postRequest())
    expect(response.status).toBe(500)
    expect(h.intents.begin).toHaveBeenCalledOnce()
    expect(h.intents.resolve).not.toHaveBeenCalled()
  })

  it('returns a receipt already issued ON even if the switch goes OFF before the response', async () => {
    const h = harness()
    h.intents.begin.mockImplementation(async () => {
      h.control.enabled = false
      return receipt()
    })
    expect((await h.post(postRequest())).status).toBe(200)
    expect(h.intents.begin).toHaveBeenCalledOnce()
  })

  it.each([
    'get',
    'post',
  ] as const)('propagates stale on %s without another operation', async (method) => {
    const h = harness()
    h.intents[method === 'get' ? 'resolve' : 'begin'].mockRejectedValue(
      new MobileApiError(409, 'mobile_signup_strength_stale_epoch', 'Review signup'),
    )
    const response = await h[method](
      method === 'get' ? new Request(`${ENDPOINT}?preparation_id=${Q}`) : postRequest(),
    )
    expect(response.status).toBe(409)
    expect((await response.json()).error.code).toBe('mobile_signup_strength_stale_epoch')
    expect(h.intents.verify).not.toHaveBeenCalled()
  })

  it('refuses a mixed internal owner before exposing a public receipt', async () => {
    const h = harness()
    h.intents.begin.mockResolvedValue({ ...receipt(), userId: ID })
    const response = await h.post(postRequest())
    expect(response.status).toBe(500)
    expect((await response.json()).error.code).toBe(
      'mobile_signup_completion_intent_invalid_response',
    )
  })

  it('keeps authentication before any preparation side effect', async () => {
    const h = harness()
    vi.mocked(h.runtime.authenticate).mockRejectedValue(
      new MobileApiError(401, 'unauthorized', 'Sign in'),
    )
    expect((await h.post(postRequest())).status).toBe(401)
    expect(h.composition.enabled).not.toHaveBeenCalled()
    expect(h.composition.createSources).not.toHaveBeenCalled()
  })
})
