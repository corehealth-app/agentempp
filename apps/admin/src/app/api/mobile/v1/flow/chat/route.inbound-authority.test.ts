import { readFileSync } from 'node:fs'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { type FlowChatDependencies, sendFlowMessage } from '@/lib/mobile-api/flow-chat-service'
import {
  type CapturedFlowInboundAuthority,
  FlowInboundAuthorityRefusal,
  type FlowInboundAuthoritySource,
} from '@/lib/mobile-api/flow-inbound-authority'
import { MobileApiError, mobileErrorResponse } from '@/lib/mobile-api/http'
import {
  executeIdempotent,
  type executeSupabaseIdempotent,
  type MobileIdempotencyStore,
} from '@/lib/mobile-api/idempotency'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import { type FlowChatRouteDependencies, handleFlowChatGet, handleFlowChatPost } from './handler'

const OWNER = '00000000-0000-0000-0000-00000000f171'
const OTHER = '00000000-0000-0000-0000-00000000f172'
const INBOUND = '00000000-0000-0000-0000-00000000b171'
const KEY = 's17j-turn-0001'
const TEXT = 'Cafe\u0301  \nleg press'
const STARTED = '2026-10-15T12:00:00.123Z'
const REQUEST = 'request-s17j-0001'

function context(
  owner = OWNER,
  key: string | null = KEY,
  text: unknown = TEXT,
): MobileRouteContext {
  return {
    request: new Request('https://performe.test/api/mobile/v1/flow/chat', {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(key ? { 'Idempotency-Key': key } : {}) },
      body: JSON.stringify(typeof text === 'object' ? text : { text }),
    }),
    requestId: REQUEST,
    supabase: {} as ServiceClient,
    auth: {
      accessToken: 'synthetic',
      authUserId: owner,
      userId: owner,
      identity: { id: owner, email: 'synthetic@example.invalid', emailConfirmedAt: STARTED },
      patient: {
        id: owner,
        authUserId: owner,
        email: 'synthetic@example.invalid',
        name: 'Synthetic',
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function handle(owner = OWNER): CapturedFlowInboundAuthority {
  return Object.freeze({
    userId: owner,
    requestKey: KEY,
    text: TEXT,
    admissionId: '00000000-0000-0000-0000-00000000a171',
    probe: vi.fn(async () => ({
      status: 'bound' as const,
      inbound: {
        id: INBOUND,
        direction: 'in' as const,
        content: TEXT,
        delivery_status: 'completed',
        raw_payload: {},
        created_at: STARTED,
      },
    })),
    persist: vi.fn(async () => {
      throw new Error('unexpected persist')
    }),
  })
}

function setup(claim: 'replay' | 'claimed' = 'replay', captured = handle()) {
  const cachedBody: {
    data: Awaited<ReturnType<typeof sendFlowMessage>>
    meta: { api_version: 'v1'; request_id: string }
  } = {
    data: {
      conversation_id: 'flow',
      message: {
        id: 'assistant-original',
        conversation_id: 'flow',
        role: 'assistant',
        content: 'Resposta sintética',
        state: 'completed',
        request_id: 'request-original',
        created_at: STARTED,
      },
      draft: null,
    },
    meta: { api_version: 'v1', request_id: 'request-original' },
  }
  const source: FlowInboundAuthoritySource = { capture: vi.fn(async () => captured) }
  // Extra structural dependency intentionally makes the RED exercise the old real handler.
  const chat: FlowChatDependencies & { inboundAuthority: FlowInboundAuthoritySource } = {
    store: {} as FlowChatDependencies['store'],
    agent: {} as FlowChatDependencies['agent'],
    inboundAuthority: source,
  }
  const ledger: MobileIdempotencyStore = {
    claim: vi.fn(async () =>
      claim === 'replay'
        ? { action: 'replay' as const, status: 201, body: cachedBody }
        : { action: 'claimed' as const, claimId: 'claim-current' },
    ),
    complete: vi.fn(async () => {}),
    fail: vi.fn(async () => {}),
  }
  const deps: FlowChatRouteDependencies = {
    createChatDependencies: vi.fn(() => chat),
    loadHistory: vi.fn(async () => ({ conversation_id: 'flow' as const, messages: [] })),
    sendMessage: vi.fn(async () => cachedBody.data),
    executeIdempotent: (
      ctx,
      payload,
      operation,
      options?: Parameters<typeof executeSupabaseIdempotent>[3],
    ) => executeIdempotent(ctx, payload, ledger, operation, options),
    loadPresentationContext: vi.fn(async () => ({ currentProtocol: null })),
    now: vi.fn(() => new Date(STARTED)),
  }
  return { deps, chat, source, captured, ledger, cachedBody }
}

describe('S17J Flow HTTP captured admission (dormant injection)', () => {
  it('H1 refuses a real ledger replay when reset makes the original admission stale', async () => {
    const q = setup()
    vi.mocked(q.ledger.claim).mockImplementation(async () => {
      vi.mocked(q.captured.probe).mockRejectedValue(
        new FlowInboundAuthorityRefusal('forbidden', 'stale_epoch'),
      )
      return { action: 'replay', body: q.cachedBody, status: 201 }
    })
    const before = JSON.stringify(q.cachedBody)
    await expect(handleFlowChatPost(context(), q.deps)).rejects.toMatchObject({
      status: 409,
      code: 'flow_request_authority_conflict',
      details: undefined,
    })
    expect(q.source.capture).toHaveBeenCalledOnce()
    expect(q.source.capture).toHaveBeenCalledWith({ userId: OWNER, requestKey: KEY, text: TEXT })
    expect(q.captured.probe).toHaveBeenCalledOnce()
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.deps.sendMessage).not.toHaveBeenCalled()
    expect(q.deps.now).not.toHaveBeenCalled()
    expect(q.deps.loadPresentationContext).not.toHaveBeenCalled()
    expect(q.ledger.complete).not.toHaveBeenCalled()
    expect(q.ledger.fail).not.toHaveBeenCalled()
    expect(JSON.stringify(q.cachedBody)).toBe(before)
  })

  it('H2 keeps the stored cache intact and projects only after the bound replay gate', async () => {
    const q = setup()
    const order: string[] = []
    vi.mocked(q.source.capture).mockImplementation(async () => {
      order.push('capture')
      return q.captured
    })
    vi.mocked(q.ledger.claim).mockImplementation(async () => {
      order.push('claim')
      return { action: 'replay', status: 201, body: q.cachedBody }
    })
    const probe = q.captured.probe
    vi.mocked(probe).mockImplementation(async () => {
      order.push('probe')
      return {
        status: 'bound',
        inbound: {
          id: INBOUND,
          direction: 'in',
          content: TEXT,
          delivery_status: 'completed',
          raw_payload: {},
          created_at: STARTED,
        },
      }
    })
    vi.mocked(q.deps.loadPresentationContext).mockImplementation(async () => {
      order.push('presentation')
      return { currentProtocol: null }
    })
    const before = JSON.stringify(q.cachedBody)
    const response = await handleFlowChatPost(context(), q.deps)
    const body = await response.json()
    expect(order).toEqual(['capture', 'claim', 'probe', 'presentation'])
    expect(response.status).toBe(201)
    expect(body.data).toEqual(q.cachedBody.data)
    expect(body.meta.request_id).toBe(REQUEST)
    expect(response.headers.get('Idempotency-Replayed')).toBe('true')
    expect(response.headers.get('X-Request-Id')).toBe(REQUEST)
    expect(response.headers.get('Vary')).toBe('Authorization')
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(JSON.stringify(q.cachedBody)).toBe(before)
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.deps.sendMessage).not.toHaveBeenCalled()
    expect(q.deps.now).not.toHaveBeenCalled()
    expect(q.ledger.complete).not.toHaveBeenCalled()
    expect(q.ledger.fail).not.toHaveBeenCalled()
  })

  it.each([
    'unbound',
    'unproved_inbound',
    'inbound_mismatch',
    'stale_epoch',
  ] as const)('H3 refuses %s before exposing an old positive body, without repairing it', async (reason) => {
    const q = setup()
    if (reason === 'unbound') vi.mocked(q.captured.probe).mockResolvedValue({ status: 'unbound' })
    else
      vi.mocked(q.captured.probe).mockRejectedValue(
        new FlowInboundAuthorityRefusal('forbidden', reason),
      )
    let caught: unknown
    try {
      await handleFlowChatPost(context(), q.deps)
    } catch (error) {
      caught = error
    }
    expect(caught).toBeInstanceOf(MobileApiError)
    const response = mobileErrorResponse(caught as MobileApiError, REQUEST)
    expect(response.status).toBe(409)
    const body = await response.json()
    expect(body.error).toEqual({
      code: 'flow_request_authority_conflict',
      message: 'Flow request authority could not be verified',
      request_id: REQUEST,
    })
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.deps.sendMessage).not.toHaveBeenCalled()
    expect(q.deps.now).not.toHaveBeenCalled()
    expect(q.deps.loadPresentationContext).not.toHaveBeenCalled()
    expect(q.ledger.fail).not.toHaveBeenCalled()
  })

  it('H4 passes the exact original handle only to the claimed mutation', async () => {
    const q = setup('claimed')
    await handleFlowChatPost(context(), q.deps)
    expect(q.deps.sendMessage).toHaveBeenCalledOnce()
    expect(vi.mocked(q.deps.sendMessage).mock.calls[0]?.[1].inboundAuthority).toBe(q.captured)
    expect(q.source.capture).toHaveBeenCalledOnce()
    expect(q.captured.probe).not.toHaveBeenCalled()
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.deps.now).toHaveBeenCalledOnce()
    expect(q.ledger.complete).toHaveBeenCalledOnce()
  })

  it('H5 a renewed HTTP ledger never recaptures an old admission after reset', async () => {
    const q = setup('replay')
    // First the old completed ledger really replays. The controlled DB port then expires
    // that lease/cache and grants a new claim; it never grants a new admission epoch.
    await handleFlowChatPost(context(), q.deps)
    vi.mocked(q.ledger.claim).mockResolvedValue({
      action: 'claimed',
      claimId: 'claim-after-expiry',
    })
    q.chat.store.countRecentExecutions = vi.fn(async () => 0)
    q.chat.store.findAssistant = vi.fn(async () => null)
    q.chat.store.findInbound = vi.fn(async () => null)
    q.chat.store.insertInbound = vi.fn(async () => {
      throw new Error('legacy insert forbidden')
    })
    vi.mocked(q.captured.probe).mockRejectedValue(
      new FlowInboundAuthorityRefusal('forbidden', 'stale_epoch'),
    )
    q.deps.sendMessage = sendFlowMessage
    await expect(handleFlowChatPost(context(), q.deps)).rejects.toMatchObject({
      status: 409,
      code: 'flow_request_authority_conflict',
    })
    expect(q.source.capture).toHaveBeenCalledTimes(2)
    expect(q.captured.probe).toHaveBeenCalledTimes(2)
    expect(vi.mocked(q.ledger.claim).mock.calls.map(([value]) => value.requestHash)).toEqual([
      '5ca3e0b81191fa485c27b05e7f2c68d4354824f6482fb229751a8dd84f893600',
      '5ca3e0b81191fa485c27b05e7f2c68d4354824f6482fb229751a8dd84f893600',
    ])
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.chat.store.findInbound).not.toHaveBeenCalled()
    expect(q.chat.store.insertInbound).not.toHaveBeenCalled()
    expect(q.ledger.fail).toHaveBeenCalledOnce()
    expect(q.ledger.complete).not.toHaveBeenCalled()
  })

  it.each([
    [null, TEXT],
    ['invalid/key', TEXT],
    [KEY, ''],
    [KEY, { text: TEXT, user_id: OTHER }],
    [KEY, { text: TEXT, inboundAuthority: {} }],
  ] as const)('validates key and strict payload before capture: %j', async (key, text) => {
    const q = setup()
    await expect(handleFlowChatPost(context(OWNER, key, text), q.deps)).rejects.toThrow()
    expect(q.source.capture).not.toHaveBeenCalled()
    expect(q.ledger.claim).not.toHaveBeenCalled()
    expect(q.deps.now).not.toHaveBeenCalled()
  })

  it('H6 keeps A → B → A requests isolated while the first A capture is pending', async () => {
    const a1 = setup('replay', handle(OWNER))
    const b = setup('replay', handle(OTHER))
    const a2 = setup('replay', handle(OWNER))
    const ca1 = context()
    ca1.requestId = 'request-A-original'
    const cb = context(OTHER)
    cb.requestId = 'request-B-current'
    const ca2 = context()
    ca2.requestId = 'request-A-return'
    a1.cachedBody.data.message.content = 'A original'
    b.cachedBody.data.message.content = 'B'
    a2.cachedBody.data.message.content = 'A retorno'
    let release: (value: CapturedFlowInboundAuthority) => void = () => {
      throw new Error('not started')
    }
    let entered: () => void = () => {}
    const started = new Promise<void>((resolve) => {
      entered = resolve
    })
    vi.mocked(a1.source.capture).mockImplementation(() => {
      entered()
      return new Promise((resolve) => {
        release = resolve
      })
    })
    const requests = new Map([
      [ca1.requestId, a1],
      [cb.requestId, b],
      [ca2.requestId, a2],
    ])
    const deps: FlowChatRouteDependencies = {
      ...a1.deps,
      createChatDependencies: (ctx) => {
        const q = requests.get(ctx.requestId)
        if (!q) throw new Error('unknown context')
        return q.chat
      },
      executeIdempotent: (ctx, payload, operation, options) => {
        const q = requests.get(ctx.requestId)
        if (!q) throw new Error('unknown context')
        return executeIdempotent(ctx, payload, q.ledger, operation, options)
      },
    }
    const pending = handleFlowChatPost(ca1, deps)
    await started
    expect(a1.ledger.claim).not.toHaveBeenCalled()
    expect((await (await handleFlowChatPost(cb, deps)).json()).data.message.content).toBe('B')
    expect((await (await handleFlowChatPost(ca2, deps)).json()).data.message.content).toBe(
      'A retorno',
    )
    release(a1.captured)
    const body = await (await pending).json()
    expect(body.data.message.content).toBe('A original')
    expect(body.meta.request_id).toBe(ca1.requestId)
    for (const [q, owner] of [
      [a1, OWNER],
      [b, OTHER],
      [a2, OWNER],
    ] as const) {
      expect(q.source.capture).toHaveBeenCalledWith({ userId: owner, requestKey: KEY, text: TEXT })
      expect(q.source.capture).toHaveBeenCalledOnce()
      expect(q.captured.probe).toHaveBeenCalledOnce()
      expect(q.captured.persist).not.toHaveBeenCalled()
    }
    expect(deps.sendMessage).not.toHaveBeenCalled()
    expect(deps.now).not.toHaveBeenCalled()
  })

  it('O GET history never captures or probes an admission', async () => {
    const q = setup()
    const ctx = context()
    ctx.request = new Request(ctx.request.url)
    await handleFlowChatGet(ctx, q.deps)
    expect(q.source.capture).not.toHaveBeenCalled()
    expect(q.captured.probe).not.toHaveBeenCalled()
    expect(q.deps.loadHistory).toHaveBeenCalledWith(q.chat, OWNER, 50)
  })

  it.each([
    'owner',
    'key',
    'text',
    'missing',
  ] as const)('refuses a mixed %s capture before the HTTP ledger', async (kind) => {
    const q = setup()
    const mixed =
      kind === 'missing'
        ? undefined
        : {
            ...q.captured,
            ...(kind === 'owner'
              ? { userId: OTHER }
              : kind === 'key'
                ? { requestKey: 'other-key-0002' }
                : { text: 'other text' }),
          }
    vi.mocked(q.source.capture).mockResolvedValue(mixed as CapturedFlowInboundAuthority)
    await expect(handleFlowChatPost(context(), q.deps)).rejects.toMatchObject({
      status: 500,
      code: 'flow_request_authority_invalid_input',
    })
    expect(q.ledger.claim).not.toHaveBeenCalled()
    expect(q.captured.probe).not.toHaveBeenCalled()
    expect(q.deps.now).not.toHaveBeenCalled()
  })

  it('O production composition does not instantiate this source or use the UI flag to enable it', () => {
    const production = readFileSync(new URL('./route.ts', import.meta.url), 'utf8')
    expect(production).not.toContain('flow-inbound-authority')
    expect(production).not.toContain('inboundAuthority')
    expect(production).not.toContain('MOBILE_WORKOUT_REGISTRATION_PROJECT_REF')
  })
})
