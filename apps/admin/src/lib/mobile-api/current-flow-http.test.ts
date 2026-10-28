import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { readCurrentClinicalState } from './current-clinical-state'
import { createCurrentFlowRoutes } from './current-flow-http'
import type { FlowChatDependencies } from './flow-chat-service'
import type { MobileRouteRuntime } from './route'
import { currentFlowDraftFixture } from './testing/current-flow-draft-fixture'
import { currentOnboardingWire } from './testing/current-onboarding-fixture'
import { consentAuth, uid } from './testing/reevaluation-photo-consent-fixture'

function setup(kind: 'healthy' | 'hold' | 'no_plan' = 'no_plan', enabled = true) {
  const raw = currentOnboardingWire(kind),
    capture = vi.fn(async () => structuredClone(raw)),
    daily = vi.fn(async () => {}),
    close = vi.fn(async () => {})
  const chat = { store: {}, agent: {} } as FlowChatDependencies
  const message = {
    id: 'out-qa',
    conversation_id: 'flow' as const,
    role: 'assistant' as const,
    content: 'Meta calórica: 1800 kcal. Consumido: 1000 kcal. XP: 150.',
    state: 'completed' as const,
    request_id: 'original-request',
    created_at: '2026-10-27T10:00:00Z',
  }
  const stored = {
    conversation_id: 'flow' as const,
    message,
    draft: { id: uid(6902), domain: 'nutrition' as 'training' | 'nutrition' },
  }
  const deps = {
    clinical: {
      state: { capture },
      createReadModel: vi.fn(() => {
        throw new Error('History must not construct a numeric reader')
      }),
      applyDaily: daily,
      closeDays: close,
      periodRows: vi.fn(async () => []),
      drafts: currentFlowDraftFixture(raw).authority,
    },
    createChatDependencies: vi.fn(() => chat),
    loadHistory: vi.fn(async () => ({ conversation_id: 'flow' as const, messages: [message] })),
    sendMessage: vi.fn(async () => stored),
    executeIdempotent: vi.fn(
      async (_ctx: unknown, _input: unknown, operation: (key: string) => Promise<Response>) =>
        operation('flow-qa-123'),
    ),
    now: () => new Date('2026-10-27T12:00:00Z'),
  }
  const runtime: MobileRouteRuntime = {
    authenticate: async () => structuredClone(consentAuth),
    authorizeEntitlement: async () => {},
    createServiceClient: () => ({}) as ServiceClient,
    createRequestId: () => 'current-flow-request',
  }
  const createDependencies = vi.fn(() => deps),
    routes = createCurrentFlowRoutes({ enabled, createDependencies }, runtime)
  return { raw, capture, daily, close, deps, routes, stored, message, createDependencies }
}
function req(method: 'GET' | 'POST' = 'GET', query = '?clinical_policy=current_clinical_v1') {
  return new Request(`https://owned.test/api/mobile/v1/flow/chat${query}`, {
    method,
    ...(method === 'POST'
      ? {
          headers: { 'content-type': 'application/json', 'idempotency-key': 'flow-qa-123' },
          body: JSON.stringify({ text: 'Como foi meu dia?' }),
        }
      : {}),
  })
}
describe('current clinical Flow HTTP boundary', () => {
  it.each([
    'GET',
    'POST',
  ] as const)('establishes a fresh baseline for %s history/cache without a numeric effect or another turn', async (method) => {
    const q = setup('healthy'),
      establish = vi.fn(async () => {
        q.raw.signup_generation = uid(7799)
        Object.assign(q.raw, {
          generation_authority: {
            kind: 'legacy_transition',
            user_id: q.raw.user_id,
            generation: q.raw.signup_generation,
            epoch: q.raw.epoch,
            admitted_at: q.raw.observed_at,
            admitted_date: q.raw.date,
            timezone_at_admission: q.raw.timezone,
            profile_completed_marker: q.raw.generation_token.onboarding_completed_at,
          },
        })
        return readCurrentClinicalState(q.raw, q.raw.user_id)
      })
    Object.assign(q.deps.clinical, { admission: { establish } })
    q.deps.executeIdempotent.mockImplementation(async () =>
      Response.json(
        {
          data: { ...q.stored, draft: null },
          meta: { api_version: 'v1', request_id: 'already-accepted' },
        },
        { status: 201, headers: { 'idempotency-replayed': 'true' } },
      ),
    )
    const response = await q.routes[method](req(method))
    expect(response.status).toBe(method === 'GET' ? 200 : 201)
    expect(establish).toHaveBeenCalledOnce()
    expect(q.daily).not.toHaveBeenCalled()
    expect(q.close).not.toHaveBeenCalled()
    expect(q.deps.clinical.createReadModel).not.toHaveBeenCalled()
    expect(q.deps.sendMessage).not.toHaveBeenCalled()
  })
  it('refuses invalid Flow query/body/key and incompatible representation before admission', async () => {
    const q = setup(),
      establish = vi.fn()
    Object.assign(q.deps.clinical, { admission: { establish } })
    expect(
      (await q.routes.GET(req('GET', '?clinical_policy=current_clinical_v1&limit=bad'))).status,
    ).toBe(422)
    const missing = req('POST')
    missing.headers.delete('idempotency-key')
    expect((await q.routes.POST(missing)).status).toBe(400)
    expect(
      (await q.routes.POST(new Request(req('POST'), { body: JSON.stringify({ text: '' }) })))
        .status,
    ).toBe(422)
    expect(establish).not.toHaveBeenCalled()
    expect(q.capture).not.toHaveBeenCalled()
    expect((await q.routes.GET(req('GET', ''))).status).toBe(409)
    expect(establish).not.toHaveBeenCalled()
    expect(q.deps.executeIdempotent).not.toHaveBeenCalled()
  })
  it('constructs request-owned dependencies with the authenticated owner', async () => {
    const q = setup()
    expect((await q.routes.GET(req())).status).toBe(200)
    expect(q.createDependencies).toHaveBeenCalledTimes(1)
    expect(q.createDependencies).toHaveBeenCalledWith(expect.anything(), consentAuth.userId)
  })
  it('projects bounded GET with a fresh mandatory policy; history creates no numeric reader, daily or closer', async () => {
    const q = setup()
    const response = await q.routes.GET(req('GET', '?clinical_policy=current_clinical_v1&limit=20'))
    expect(response.status).toBe(200)
    const body = await response.json()
    expect(body.data.clinical_policy.version).toBe(1)
    expect(body.data.messages[0].content).not.toContain('1800')
    expect(body.data.messages[0].content).toContain('1000')
    expect(body.data.messages[0].id).toBe(q.message.id)
    expect(q.deps.loadHistory).toHaveBeenCalledWith(expect.anything(), consentAuth.userId, 20)
    expect(q.deps.clinical.createReadModel).not.toHaveBeenCalled()
    expect(q.daily).not.toHaveBeenCalled()
    expect(q.close).not.toHaveBeenCalled()
  })
  it.each([
    'GET',
    'POST',
  ] as const)('rejects a protected legacy client before %s stores, claims or effects', async (method) => {
    const q = setup()
    const response = await q.routes[method](req(method, ''))
    expect(response.status).toBe(409)
    expect(q.deps.createChatDependencies).not.toHaveBeenCalled()
    expect(q.deps.executeIdempotent).not.toHaveBeenCalled()
    expect(q.deps.sendMessage).not.toHaveBeenCalled()
    expect(q.daily).not.toHaveBeenCalled()
  })
  it('leaves a compatible healthy legacy response shape and text unchanged', async () => {
    const q = setup('healthy')
    const response = await q.routes.GET(req('GET', ''))
    const body = await response.json()
    expect(body.data).not.toHaveProperty('clinical_policy')
    expect(body.data.messages[0]).toEqual(q.message)
  })
  it('projects a cached POST after idempotency without touching the old ACK or repeating the writer', async () => {
    const q = setup()
    const cached = JSON.stringify({
      data: q.stored,
      meta: { api_version: 'v1', request_id: 'old' },
    })
    q.deps.executeIdempotent.mockImplementation(
      async () =>
        new Response(cached, {
          status: 201,
          headers: { 'idempotency-replayed': 'true', 'content-length': String(cached.length) },
        }),
    )
    const response = await q.routes.POST(req('POST'))
    const body = await response.json()
    expect(response.status).toBe(201)
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect(response.headers.get('content-length')).toBeNull()
    expect(body.data.message.content).not.toContain('1800')
    expect(body.data.message.content).toContain('150')
    expect(body.data.draft).toBeNull()
    expect(body.data.clinical_policy.pause_weight_loss_guidance).toBe(true)
    expect(JSON.parse(cached).data.draft.id).toBe(uid(6902))
    expect(q.deps.sendMessage).not.toHaveBeenCalled()
  })
  it('allows a training shortcut under a hold when the objective remains visible', async () => {
    const q = setup('hold')
    q.deps.clinical.drafts.lookup.mockResolvedValueOnce({
      id: uid(6902),
      status: 'needs_completion',
      payload: { notes: 'actual persisted draft' },
    })
    q.stored.draft.domain = 'training'
    const response = await q.routes.POST(req('POST'))
    expect((await response.json()).data.draft.domain).toBe('training')
  })
  it('certifies a cached shortcut for this exact POST without numeric effects or another turn', async () => {
    const q = setup('healthy'),
      cached = JSON.stringify({
        data: q.stored,
        meta: { api_version: 'v1', request_id: 'accepted-original' },
      })
    q.deps.executeIdempotent.mockImplementation(
      async () =>
        new Response(cached, { status: 201, headers: { 'idempotency-replayed': 'true' } }),
    )
    q.deps.clinical.drafts.lookup.mockResolvedValueOnce({
      id: uid(6902),
      status: 'ready_for_review',
      payload: { notes: 'persisted' },
    })
    const response = await q.routes.POST(req('POST')),
      body = await response.json()
    expect(response.status).toBe(201)
    expect(body.data.draft).toEqual(q.stored.draft)
    expect(body.meta.request_id).toBe('accepted-original')
    expect(q.deps.clinical.drafts.findTurn).toHaveBeenCalledWith({
      domain: 'nutrition',
      requestKey: `mobile_flow/${consentAuth.userId}/flow-qa-123:propoe_plano_dieta`,
    })
    expect(q.deps.sendMessage).not.toHaveBeenCalled()
    expect(q.daily).not.toHaveBeenCalled()
    expect(q.close).not.toHaveBeenCalled()
    expect(q.deps.clinical.createReadModel).not.toHaveBeenCalled()
    expect(JSON.stringify(body)).not.toMatch(
      /health_state|signup_generation|sourceMessageId|profile_hash/,
    )
    expect(JSON.parse(cached).data.draft).toEqual(q.stored.draft)
  })
  it.each([
    'foreign-turn',
    'lookup-failure',
  ])('hides %s shortcut after cache without repeating accepted work', async (kind) => {
    const q = setup('healthy'),
      cached = JSON.stringify({
        data: q.stored,
        meta: { api_version: 'v1', request_id: 'accepted' },
      })
    q.deps.executeIdempotent.mockImplementation(async () => new Response(cached, { status: 201 }))
    if (kind === 'lookup-failure')
      q.deps.clinical.drafts.lookup.mockRejectedValueOnce(new Error('private SQL failure'))
    else
      q.deps.clinical.drafts.lookup.mockResolvedValueOnce({
        id: uid(6999),
        status: 'ready_for_review',
        payload: { notes: 'other turn' },
      })
    const response = await q.routes.POST(req('POST')),
      body = await response.json()
    expect(response.status).toBe(201)
    expect(body.data.draft).toBeNull()
    expect(q.deps.executeIdempotent).toHaveBeenCalledTimes(1)
    expect(q.deps.sendMessage).not.toHaveBeenCalled()
    expect(q.daily).not.toHaveBeenCalled()
    expect(q.close).not.toHaveBeenCalled()
    expect(JSON.parse(cached).data.draft).toEqual(q.stored.draft)
  })
  it('refuses GET binding drift and snapshots callbacks before its first await', async () => {
    const q = setup('healthy')
    q.deps.loadHistory.mockImplementation(async () => {
      q.raw.profile_hash = 'c'.repeat(64)
      return { conversation_id: 'flow', messages: [q.message] }
    })
    expect((await q.routes.GET(req())).status).toBe(409)
    const t = setup()
    let entered = () => {},
      resume = () => {}
    const started = new Promise<void>((resolve) => {
        entered = resolve
      }),
      gate = new Promise<void>((resolve) => {
        resume = resolve
      })
    t.capture.mockImplementationOnce(async () => {
      entered()
      await gate
      return structuredClone(t.raw)
    })
    const get = t.routes.GET(req())
    await started
    t.deps.loadHistory = vi.fn(async () => {
      throw new Error('replacement')
    })
    resume()
    expect((await get).status).toBe(200)
  })
  it('does not fail or release a completed command when presentation fails; retry reuses it', async () => {
    const q = setup('healthy')
    let accepted = false,
      cached: Response | undefined
    q.deps.executeIdempotent.mockImplementation(async (_c, _i, operation) => {
      if (cached) return cached.clone()
      cached = await operation('flow-qa-123')
      accepted = true
      q.capture.mockRejectedValueOnce(new Error('post-commit read unavailable'))
      return cached.clone()
    })
    expect((await q.routes.POST(req('POST'))).status).toBe(503)
    expect(accepted).toBe(true)
    expect((await q.routes.POST(req('POST'))).status).toBe(201)
    expect(q.deps.sendMessage).toHaveBeenCalledTimes(1)
  })
  it.each([
    '?clinical_policy=unknown',
    '?clinical_policy=current_clinical_v1&clinical_policy=current_clinical_v1',
    '?clinical_policy=current_clinical_v1&user_id=other',
    '?clinical_policy=current_clinical_v1&limit=2&limit=3',
  ])('rejects unexpected/ambiguous negotiation before dependencies run: %s', async (query) => {
    const q = setup()
    expect((await q.routes.GET(req('GET', query))).status).toBeGreaterThanOrEqual(400)
    expect(q.createDependencies).not.toHaveBeenCalled()
  })
  it('keeps the closed constructor disabled by default', async () => {
    const q = setup('healthy', false)
    expect((await q.routes.GET(req())).status).toBe(404)
    expect(q.createDependencies).not.toHaveBeenCalled()
  })
})

it('never publishes a cached clinical policy: replace for current clients and omit for legacy', async () => {
  for (const query of ['?clinical_policy=current_clinical_v1', '']) {
    const q = setup('healthy')
    const packet = {
      data: { ...q.stored, clinical_policy: { version: 999 } },
      meta: { api_version: 'v1', request_id: 'old' },
    }
    q.deps.executeIdempotent.mockImplementation(async () => Response.json(packet, { status: 201 }))
    const body = await (await q.routes.POST(req('POST', query))).json()
    if (query) expect(body.data.clinical_policy.version).toBe(1)
    else expect(body.data).not.toHaveProperty('clinical_policy')
  }
})
