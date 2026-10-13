import type { ServiceClient } from '@mpp/db'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { FlowChatDependencies, SendFlowMessageInput } from '@/lib/mobile-api/flow-chat-service'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

// Composition/SDK boundary only: no Next server, JWT, database, or provider proof.
const mocks = vi.hoisted(() => ({
  callbacks: [] as Array<(context: MobileRouteContext) => Promise<Response>>,
  history: vi.fn(),
  send: vi.fn(),
  agentReply: vi.fn(),
  cache: vi.fn(),
}))
vi.mock('@/lib/mobile-api/route', () => ({
  createMobileRoute: (handler: (context: MobileRouteContext) => Promise<Response>) => {
    mocks.callbacks.push(handler)
    return handler
  },
}))
vi.mock('@/lib/mobile-api/flow-agent-factory', () => ({
  createFlowAgent: () => ({ reply: mocks.agentReply }),
}))
vi.mock('@/lib/mobile-api/flow-chat-service', () => ({
  createSupabaseFlowChatStore: () => ({}),
  createSupabaseFlowDraftLookup: () => ({}),
  loadFlowHistory: mocks.history,
  sendFlowMessage: mocks.send,
}))
vi.mock('@/lib/mobile-api/flow-presentation-context', () => ({
  loadFlowPresentationContext: async () => ({ currentProtocol: null }),
}))
vi.mock('@/lib/mobile-api/idempotency', () => ({ executeSupabaseIdempotent: mocks.cache }))
// Import the actual route/handler composition and actual phrase-store constructor.
import './route'

function context(method: 'GET' | 'POST', userId: string, locale = 'pt-BR') {
  const rpc = vi.fn(async () => ({
    data: { anchor_assistant_id: null, cursor_revision: '0', cursor: null },
    error: null,
  }))
  const value: MobileRouteContext = {
    request: new Request('https://performe.test/api/mobile/v1/flow/chat', {
      method,
      ...(method === 'POST'
        ? {
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({ text: 'Status do dia' }),
          }
        : {}),
    }),
    requestId: 'c5a-wiring-request',
    supabase: { rpc } as unknown as ServiceClient,
    auth: {
      accessToken: 'synthetic-not-a-token',
      authUserId: userId,
      userId,
      identity: {
        id: userId,
        email: 'c5a@example.invalid',
        emailConfirmedAt: '2026-10-13T00:00:00Z',
      },
      patient: {
        id: userId,
        authUserId: userId,
        email: 'c5a@example.invalid',
        name: 'Synthetic C5a',
        locale,
        timezone: 'UTC',
        country: 'US',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
  return { value, rpc }
}
function output(requestId = 'c5a-wiring-request') {
  return {
    conversation_id: 'flow' as const,
    message: {
      id: 'c5a-assistant',
      conversation_id: 'flow' as const,
      role: 'assistant' as const,
      content: 'Status oficial de hoje.',
      state: 'completed' as const,
      request_id: requestId,
      created_at: '2026-10-13T00:00:00Z',
    },
    draft: null,
  }
}

beforeEach(() => {
  vi.clearAllMocks()
  mocks.history.mockResolvedValue({ conversation_id: 'flow', messages: [] })
  mocks.cache.mockImplementation(
    async (
      _context: MobileRouteContext,
      _payload: unknown,
      operation: (key: string) => Promise<Response>,
    ) => operation('c5a-route-event-0001'),
  )
  mocks.send.mockImplementation(async (chat: FlowChatDependencies, input: SendFlowMessageInput) => {
    // Optional access keeps the missing production binding an assertion RED, not a setup throw.
    await chat.phraseReplies?.loadCursor(input.userId)
    return output(input.requestId)
  })
})

describe('C5a actual route composition', () => {
  it.each([
    ['00000000-0000-0000-0000-00000000c5a1', 'pt-BR'],
    ['00000000-0000-0000-0000-00000000c5a2', 'en-US'],
  ])('binds the real phrase adapter to the current POST owner %s (%s)', async (owner, locale) => {
    const { value, rpc } = context('POST', owner, locale)
    const response = await mocks.callbacks[1](value)
    expect(response.status).toBe(201)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('read_flow_phrase_cursor', { p_user_id: owner })
    expect(mocks.send).toHaveBeenCalledWith(
      expect.objectContaining({
        phraseReplies: expect.objectContaining({
          loadCursor: expect.any(Function),
          commitReply: expect.any(Function),
        }),
      }),
      expect.objectContaining({ userId: owner }),
    )
    expect(mocks.agentReply).not.toHaveBeenCalled()
  })
  it('does not read or advance a phrase while loading GET history', async () => {
    const owner = '00000000-0000-0000-0000-00000000c5a1'
    const { value, rpc } = context('GET', owner)
    const response = await mocks.callbacks[0](value)
    expect(response.status).toBe(200)
    expect(mocks.history).toHaveBeenCalledWith(expect.anything(), owner, 50)
    expect(rpc).not.toHaveBeenCalled()
    expect(mocks.send).not.toHaveBeenCalled()
    expect(mocks.agentReply).not.toHaveBeenCalled()
  })
  it('keeps cached HTTP replay ahead of send and phrase cursor work', async () => {
    const { value, rpc } = context('POST', '00000000-0000-0000-0000-00000000c5a1')
    mocks.cache.mockResolvedValue(
      Response.json(
        {
          data: output('c5a-original-request'),
          meta: { api_version: 'v1', request_id: 'c5a-original-request' },
        },
        { status: 201, headers: { 'Idempotency-Replayed': 'true' } },
      ),
    )
    const response = await mocks.callbacks[1](value)
    expect(response.status).toBe(201)
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect((await response.json()).data.message.id).toBe('c5a-assistant')
    expect(mocks.send).not.toHaveBeenCalled()
    expect(rpc).not.toHaveBeenCalled()
    expect(mocks.agentReply).not.toHaveBeenCalled()
  })
})
