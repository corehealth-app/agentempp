import { describe, expect, it, vi } from 'vitest'
import {
  createSupabaseFlowChatStore,
  type FlowAgent,
  type FlowChatStore,
  loadFlowHistory,
  type StoredFlowMessage,
  sendFlowMessage,
} from './flow-chat-service'
import { MobileApiError } from './http'

const userId = '00000000-0000-0000-0000-000000000111'
const now = new Date('2026-09-14T20:00:00.000Z')

function message(overrides: Partial<StoredFlowMessage> = {}): StoredFlowMessage {
  return {
    id: '00000000-0000-0000-0000-000000000201',
    role: 'user',
    content: 'Olá',
    state: 'completed',
    requestId: 'request-flow-0001',
    createdAt: '2026-09-14T19:59:00.000Z',
    ...overrides,
  }
}

function dependencies(overrides: Partial<FlowChatStore> = {}) {
  const store: FlowChatStore = {
    loadHistory: vi.fn(async () => []),
    countRecentInbound: vi.fn(async () => 0),
    findInbound: vi.fn(async () => null),
    findAssistant: vi.fn(async () => null),
    insertInbound: vi.fn(async () => message({ state: 'processing' })),
    retryInbound: vi.fn(async () => undefined),
    insertAssistant: vi.fn(async () =>
      message({ role: 'assistant', content: 'Oi!', id: 'assistant-1' }),
    ),
    completeInbound: vi.fn(async () => undefined),
    failInbound: vi.fn(async () => undefined),
    ...overrides,
  }
  const agent: FlowAgent = { reply: vi.fn(async () => ({ text: 'Oi!', metadata: {} })) }
  return { store, agent }
}

describe('Flow chat service', () => {
  it('pins service-role history reads to the authenticated user and mobile channel', async () => {
    const filters: Array<[string, string]> = []
    const query = {
      select: () => query,
      eq: (column: string, value: string) => {
        filters.push([column, value])
        return query
      },
      order: () => query,
      limit: async () => ({ data: [], error: null }),
    }
    const supabase = {
      from: () => query,
    } as unknown as import('@mpp/db').ServiceClient

    await createSupabaseFlowChatStore(supabase).loadHistory(userId, 20)

    expect(filters).toEqual([
      ['user_id', userId],
      ['provider', 'mobile_flow'],
    ])
  })

  it('loads only authenticated patient history in chronological order', async () => {
    const deps = dependencies({
      loadHistory: vi.fn(async () => [
        message({ id: 'new', createdAt: '2026-09-14T20:00:00.000Z' }),
        message({ id: 'old', createdAt: '2026-09-14T19:00:00.000Z' }),
      ]),
    })

    const result = await loadFlowHistory(deps, userId, 20)

    expect(deps.store.loadHistory).toHaveBeenCalledWith(userId, 20)
    expect(result.messages.map((item) => item.id)).toEqual(['old', 'new'])
    expect(result.conversation_id).toBe('flow')
  })

  it('persists processing inbound, real assistant output, then completion', async () => {
    const deps = dependencies()

    const result = await sendFlowMessage(deps, {
      userId,
      text: 'Olá',
      idempotencyKey: 'mobile-flow-0001',
      requestId: 'request-flow-0001',
      now,
    })

    expect(deps.store.insertInbound).toHaveBeenCalledWith(
      expect.objectContaining({ userId, state: 'processing' }),
    )
    expect(deps.agent.reply).toHaveBeenCalledWith(expect.objectContaining({ userId, text: 'Olá' }))
    expect(deps.store.insertAssistant).toHaveBeenCalledWith(
      expect.objectContaining({ userId, content: 'Oi!' }),
    )
    expect(deps.store.completeInbound).toHaveBeenCalledOnce()
    expect(result.message.role).toBe('assistant')
  })

  it('marks the inbound failed and never fabricates an assistant on provider failure', async () => {
    const deps = dependencies()
    deps.agent.reply = vi.fn(async () => {
      throw new Error('provider detail must not escape')
    })

    await expect(
      sendFlowMessage(deps, {
        userId,
        text: 'Olá',
        idempotencyKey: 'mobile-flow-0002',
        requestId: 'request-flow-0002',
        now,
      }),
    ).rejects.toEqual(
      new MobileApiError(502, 'flow_provider_failed', 'Flow is temporarily unavailable'),
    )
    expect(deps.store.failInbound).toHaveBeenCalledOnce()
    expect(deps.store.insertAssistant).not.toHaveBeenCalled()
  })

  it('reuses a failed inbound when retrying the same idempotency key', async () => {
    const failedInbound = message({ state: 'failed', content: 'Olá' })
    const deps = dependencies({ findInbound: vi.fn(async () => failedInbound) })

    const result = await sendFlowMessage(deps, {
      userId,
      text: 'Olá',
      idempotencyKey: 'mobile-flow-0002',
      requestId: 'request-flow-0002-retry',
      now,
    })

    expect(deps.store.countRecentInbound).not.toHaveBeenCalled()
    expect(deps.store.insertInbound).not.toHaveBeenCalled()
    expect(deps.store.retryInbound).toHaveBeenCalledWith(
      userId,
      'mobile-flow-0002',
      'request-flow-0002-retry',
    )
    expect(deps.agent.reply).toHaveBeenCalledOnce()
    expect(result.message.role).toBe('assistant')
  })

  it('rate limits per authenticated patient before persistence or provider use', async () => {
    const deps = dependencies({ countRecentInbound: vi.fn(async () => 10) })

    await expect(
      sendFlowMessage(deps, {
        userId,
        text: 'Olá',
        idempotencyKey: 'mobile-flow-0003',
        requestId: 'request-flow-0003',
        now,
      }),
    ).rejects.toMatchObject({ status: 429, code: 'flow_rate_limited' })
    expect(deps.store.insertInbound).not.toHaveBeenCalled()
    expect(deps.agent.reply).not.toHaveBeenCalled()
  })

  it('returns an already persisted assistant without calling Flow again', async () => {
    const existing = message({ role: 'assistant', content: 'Resposta estável' })
    const deps = dependencies({ findAssistant: vi.fn(async () => existing) })

    const result = await sendFlowMessage(deps, {
      userId,
      text: 'Olá',
      idempotencyKey: 'mobile-flow-0004',
      requestId: 'request-flow-0004',
      now,
    })

    expect(result.message.content).toBe('Resposta estável')
    expect(deps.store.insertInbound).not.toHaveBeenCalled()
    expect(deps.agent.reply).not.toHaveBeenCalled()
    expect(deps.store.completeInbound).toHaveBeenCalledWith(userId, 'mobile-flow-0004')
  })
})
