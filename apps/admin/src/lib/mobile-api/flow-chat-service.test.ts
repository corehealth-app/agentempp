import { afterEach, beforeEach, describe, expect, it, type MockInstance, vi } from 'vitest'
import {
  createSupabaseFlowChatStore,
  createSupabaseFlowDraftLookup,
  type FlowAgent,
  FlowMessageAlreadyStoredError,
  type FlowChatStore,
  loadFlowHistory,
  type StoredFlowMessage,
  scopedFlowProviderMessageId,
  sendFlowMessage,
} from './flow-chat-service'
import { MobileApiError } from './http'

// The per-turn timing line is asserted in flow-chat-service.parallel.test.ts;
// here it would only fill the test output.
let timingLine: MockInstance<typeof console.info>
beforeEach(() => {
  timingLine = vi.spyOn(console, 'info').mockImplementation(() => {})
})
afterEach(() => {
  timingLine.mockRestore()
})

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
    countRecentExecutions: vi.fn(async () => 0),
    findInbound: vi.fn(async () => null),
    findAssistant: vi.fn(async () => null),
    insertInbound: vi.fn(async () => message({ state: 'processing' })),
    transitionInbound: vi.fn(async () => true),
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

  it('carries the proposal its turn created, looked up by patient and turn', async () => {
    const deps = dependencies()
    const drafts = {
      findForTurn: vi.fn(async () => ({
        id: '11111111-1111-4111-8111-111111111111',
        domain: 'training' as const,
      })),
    }

    const result = await sendFlowMessage(
      { ...deps, drafts },
      {
        userId,
        text: 'Monte meu treino',
        idempotencyKey: 'mobile-flow-0002',
        requestId: 'request-flow-0002',
        now,
      },
    )

    expect(drafts.findForTurn).toHaveBeenCalledWith(
      userId,
      scopedFlowProviderMessageId(userId, 'mobile-flow-0002'),
    )
    expect(result.draft).toEqual({
      id: '11111111-1111-4111-8111-111111111111',
      domain: 'training',
    })
    expect(result.message.content).toBe('Oi!')
  })

  it('a reply without proposal, without drafts or with a failed lookup carries none', async () => {
    const input = {
      userId,
      text: 'Olá',
      idempotencyKey: 'mobile-flow-0003',
      requestId: 'request-flow-0003',
      now,
    }
    expect((await sendFlowMessage(dependencies(), input)).draft).toBeNull()
    expect(
      (await sendFlowMessage(
        { ...dependencies(), drafts: { findForTurn: vi.fn(async () => null) } },
        input,
      )).draft,
    ).toBeNull()
    const failing = await sendFlowMessage(
      {
        ...dependencies(),
        drafts: {
          findForTurn: vi.fn(async () => {
            throw new Error('database down')
          }),
        },
      },
      input,
    )
    expect(failing.draft).toBeNull()
    expect(failing.message.role).toBe('assistant')
  })

  it('the replay of a turn carries the same proposal', async () => {
    const deps = dependencies({
      findInbound: vi.fn(async () => message({ content: 'Monte meu treino' })),
      findAssistant: vi.fn(async () => message({ role: 'assistant', content: 'Pronto.' })),
    })
    const drafts = {
      findForTurn: vi.fn(async () => ({ id: 'draft-1', domain: 'nutrition' as const })),
    }

    const result = await sendFlowMessage(
      { ...deps, drafts },
      {
        userId,
        text: 'Monte meu treino',
        idempotencyKey: 'mobile-flow-0004',
        requestId: 'request-flow-0004',
        now,
      },
    )

    expect(deps.agent.reply).not.toHaveBeenCalled()
    expect(result.draft).toEqual({ id: 'draft-1', domain: 'nutrition' })
  })

  it('the proposal lookup is pinned to the patient, to the turn and to open drafts', async () => {
    const filters: Array<[string, string, unknown]> = []
    const query = {
      select: () => query,
      eq: (column: string, value: unknown) => {
        filters.push(['eq', column, value])
        return query
      },
      in: (column: string, value: unknown) => {
        filters.push(['in', column, value])
        return query
      },
      order: () => query,
      limit: async () => ({
        data: [{ id: 'draft-1', domain: 'training', payload: { secret: true } }],
        error: null,
      }),
    }
    const tables: string[] = []
    const supabase = {
      from: (table: string) => {
        tables.push(table)
        return query
      },
    } as unknown as import('@mpp/db').ServiceClient

    const turn = scopedFlowProviderMessageId(userId, 'mobile-flow-0005')
    const draft = await createSupabaseFlowDraftLookup(supabase).findForTurn(userId, turn)

    expect(tables).toEqual(['plan_drafts'])
    expect(filters).toEqual([
      ['eq', 'user_id', userId],
      ['in', 'request_key', [`${turn}:propoe_plano_treino`, `${turn}:propoe_plano_dieta`]],
      ['in', 'status', ['needs_completion', 'ready_for_review']],
    ])
    expect(draft).toEqual({ id: 'draft-1', domain: 'training' })
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

  it('reuses a failed inbound when retrying the same idempotency key, as a counted execution', async () => {
    const failedInbound = message({ state: 'failed', content: 'Olá' })
    const deps = dependencies({ findInbound: vi.fn(async () => failedInbound) })

    const result = await sendFlowMessage(deps, {
      userId,
      text: 'Olá',
      idempotencyKey: 'mobile-flow-0002',
      requestId: 'request-flow-0002-retry',
      now,
    })

    // A retry can reach the provider, so it runs through the per-minute limit
    // (before this change it skipped it): checked before, and confirmed after
    // the execution is recorded.
    expect(deps.store.countRecentExecutions).toHaveBeenCalledTimes(2)
    expect(deps.store.insertInbound).not.toHaveBeenCalled()
    expect(deps.store.transitionInbound).toHaveBeenCalledWith(
      userId,
      scopedFlowProviderMessageId(userId, 'mobile-flow-0002'),
      expect.objectContaining({ from: 'failed', to: 'processing', requestId: 'request-flow-0002-retry' }),
    )
    expect(deps.agent.reply).toHaveBeenCalledOnce()
    expect(result.message.role).toBe('assistant')
  })

  it('rate limits per authenticated patient before persistence or provider use', async () => {
    const deps = dependencies({ countRecentExecutions: vi.fn(async () => 10) })

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
    expect(deps.store.completeInbound).toHaveBeenCalledWith(
      userId,
      scopedFlowProviderMessageId(userId, 'mobile-flow-0004'),
    )
  })
})

// ── Per-user message identity (S2) ────────────────────────────────────────
// A fake `messages` table that enforces the real global unique index
// `uniq_messages_provider_message_id_all (provider, provider_message_id)`
// across ALL users, with the adapter's user/provider/direction filters.
// This is a unit-level model of the table, not an authenticated A/B test
// against a database.

interface FakeRow {
  id: string
  userId: string
  provider: 'mobile_flow'
  direction: 'in' | 'out'
  providerMessageId: string
  content: string
  state: StoredFlowMessage['state']
  requestId: string
  createdAt: string
  attempt?: StoredFlowMessage['attempt']
}

class FakeMessagesTable implements FlowChatStore {
  readonly rows: FakeRow[] = []
  private sequence = 0

  seed(row: Omit<FakeRow, 'id' | 'provider'>) {
    this.rows.push({ ...row, id: `seed-${++this.sequence}`, provider: 'mobile_flow' })
  }

  private toStored(row: FakeRow): StoredFlowMessage {
    return {
      id: row.id,
      role: row.direction === 'in' ? 'user' : 'assistant',
      content: row.content,
      state: row.state,
      requestId: row.requestId,
      createdAt: row.createdAt,
      attempt: row.attempt ?? null,
    }
  }

  private async find(userId: string, providerMessageId: string, direction: 'in' | 'out') {
    await Promise.resolve()
    const row = this.rows.find(
      (candidate) =>
        candidate.userId === userId &&
        candidate.provider === 'mobile_flow' &&
        candidate.providerMessageId === providerMessageId &&
        candidate.direction === direction,
    )
    return row ? this.toStored(row) : null
  }

  private async insert(
    input: Parameters<FlowChatStore['insertInbound']>[0],
    direction: 'in' | 'out',
  ) {
    await Promise.resolve()
    if (this.rows.some((row) => row.provider === 'mobile_flow' && row.providerMessageId === input.providerMessageId)) {
      // What the Supabase adapter surfaces for 23505 on this index.
      throw new FlowMessageAlreadyStoredError()
    }
    const row: FakeRow = {
      id: `row-${++this.sequence}`,
      userId: input.userId,
      provider: 'mobile_flow',
      direction,
      providerMessageId: input.providerMessageId,
      content: input.content,
      state: input.state,
      requestId: input.requestId,
      createdAt: input.createdAt,
      attempt: input.attempt ?? null,
    }
    this.rows.push(row)
    return this.toStored(row)
  }

  private update(userId: string, providerMessageId: string, state: StoredFlowMessage['state']) {
    for (const row of this.rows) {
      if (row.userId === userId && row.providerMessageId === providerMessageId && row.direction === 'in') {
        row.state = state
      }
    }
  }

  loadHistory = async (user: string) =>
    this.rows.filter((row) => row.userId === user).map((row) => this.toStored(row))
  countRecentExecutions = async (user: string, since: string) =>
    this.rows
      .filter((row) => row.userId === user && row.direction === 'in')
      .reduce(
        (total, row) =>
          total +
          (row.createdAt >= since ? 1 : 0) +
          (row.attempt?.retryStartedAt ?? []).filter((time) => time >= since).length,
        0,
      )
  findInbound = (user: string, id: string) => this.find(user, id, 'in')
  findAssistant = (user: string, id: string) => this.find(user, id, 'out')
  insertInbound = (input: Parameters<FlowChatStore['insertInbound']>[0]) => this.insert(input, 'in')
  insertAssistant = (input: Parameters<FlowChatStore['insertAssistant']>[0]) => this.insert(input, 'out')
  transitionInbound = async (
    user: string,
    id: string,
    change: Parameters<FlowChatStore['transitionInbound']>[2],
  ) => {
    await Promise.resolve()
    const row = this.rows.find(
      (candidate) => candidate.userId === user && candidate.providerMessageId === id && candidate.direction === 'in',
    )
    if (!row || row.state !== change.from) return false
    // The same attempt binding as the adapter's conditional update.
    if ((row.attempt?.startedAt ?? null) !== change.expectedAttemptStartedAt) return false
    if (change.expectedRequestId !== undefined && row.requestId !== change.expectedRequestId) return false
    row.state = change.to
    row.requestId = change.requestId
    row.attempt = change.attempt
    return true
  }
  completeInbound = async (user: string, id: string) => this.update(user, id, 'completed')
  failInbound = async (user: string, id: string) => this.update(user, id, 'failed')
}

const userA = '00000000-0000-4000-8000-00000000000a'
const userB = '00000000-0000-4000-8000-00000000000b'

function flowAgent(prefix: string) {
  const reply = vi.fn(async (input: { userId: string; text: string }) => ({
    text: `${prefix}:${input.userId}:${input.text}`,
    metadata: {},
  }))
  return { reply }
}

describe('Flow chat message identity per user', () => {
  it('two users can use the same Idempotency-Key independently, without a 500', async () => {
    const store = new FakeMessagesTable()
    const agent = flowAgent('reply')
    const deps = { store, agent }

    const fromA = await sendFlowMessage(deps, {
      userId: userA, text: 'Olá A', idempotencyKey: 'shared-key-0001', requestId: 'req-a', now,
    })
    const fromB = await sendFlowMessage(deps, {
      userId: userB, text: 'Olá B', idempotencyKey: 'shared-key-0001', requestId: 'req-b', now,
    })

    expect(fromA.message.content).toBe(`reply:${userA}:Olá A`)
    expect(fromB.message.content).toBe(`reply:${userB}:Olá B`)
    expect(store.rows.filter((row) => row.userId === userA)).toHaveLength(2)
    expect(store.rows.filter((row) => row.userId === userB)).toHaveLength(2)
    expect(new Set(store.rows.map((row) => row.providerMessageId)).size).toBe(4)
  })

  it('replays the same user, key and text without calling Flow or duplicating rows', async () => {
    const store = new FakeMessagesTable()
    const agent = flowAgent('reply')
    const deps = { store, agent }
    const input = { userId: userA, text: 'Olá', idempotencyKey: 'replay-key-0001', requestId: 'req-1', now }

    const first = await sendFlowMessage(deps, input)
    const replay = await sendFlowMessage(deps, { ...input, requestId: 'req-2' })

    expect(replay.message).toEqual(first.message)
    expect(agent.reply).toHaveBeenCalledOnce()
    expect(store.rows).toHaveLength(2)
  })

  it('refuses the same user and key with a different text as a key conflict', async () => {
    const store = new FakeMessagesTable()
    const agent = flowAgent('reply')
    const deps = { store, agent }
    await sendFlowMessage(deps, {
      userId: userA, text: 'Primeira pergunta', idempotencyKey: 'conflict-key-01', requestId: 'req-1', now,
    })

    await expect(
      sendFlowMessage(deps, {
        userId: userA, text: 'Outra pergunta', idempotencyKey: 'conflict-key-01', requestId: 'req-2', now,
      }),
    ).rejects.toMatchObject({ status: 409, code: 'idempotency_key_conflict' })
    expect(agent.reply).toHaveBeenCalledOnce()
    expect(store.rows).toHaveLength(2)
  })

  it('concurrent first sends of the same user and key create one message and call Flow once', async () => {
    const store = new FakeMessagesTable()
    const agent = flowAgent('reply')
    const deps = { store, agent }
    const input = { userId: userA, text: 'Olá', idempotencyKey: 'race-key-00001', now }

    const results = await Promise.allSettled([
      sendFlowMessage(deps, { ...input, requestId: 'req-1' }),
      sendFlowMessage(deps, { ...input, requestId: 'req-2' }),
    ])

    const fulfilled = results.filter((result) => result.status === 'fulfilled')
    const rejected = results.filter((result) => result.status === 'rejected')
    expect(fulfilled).toHaveLength(1)
    expect(rejected).toHaveLength(1)
    expect((rejected[0] as PromiseRejectedResult).reason).toMatchObject({
      status: 409,
      code: 'idempotency_request_in_progress',
    })
    expect(agent.reply).toHaveBeenCalledOnce()
    expect(store.rows.filter((row) => row.direction === 'in')).toHaveLength(1)
  })

  it('replays a legacy (pre-scoping) conversation of the same user and leaves other users unaffected', async () => {
    const store = new FakeMessagesTable()
    store.seed({
      userId: userA, direction: 'in', providerMessageId: 'legacy-key-0001', content: 'Olá antigo',
      state: 'completed', requestId: 'req-old', createdAt: '2026-09-20T10:00:00.000Z',
    })
    store.seed({
      userId: userA, direction: 'out', providerMessageId: 'legacy-key-0001:assistant', content: 'Resposta antiga',
      state: 'completed', requestId: 'req-old', createdAt: '2026-09-20T10:00:01.000Z',
    })
    const agent = flowAgent('reply')
    const deps = { store, agent }

    const replay = await sendFlowMessage(deps, {
      userId: userA, text: 'Olá antigo', idempotencyKey: 'legacy-key-0001', requestId: 'req-new', now,
    })
    const other = await sendFlowMessage(deps, {
      userId: userB, text: 'Olá B', idempotencyKey: 'legacy-key-0001', requestId: 'req-b', now,
    })

    expect(replay.message.content).toBe('Resposta antiga')
    expect(other.message.content).toBe(`reply:${userB}:Olá B`)
    expect(agent.reply).toHaveBeenCalledOnce()
    expect(store.rows.filter((row) => row.userId === userA)).toHaveLength(2)
    const history = await loadFlowHistory({ store, agent }, userA, 20)
    expect(history.messages.map((item) => item.content)).toEqual(['Olá antigo', 'Resposta antiga'])
  })

  it('hands Flow the stored message id, so the current turn is excluded from its own history', async () => {
    const store = new FakeMessagesTable()
    const agent = flowAgent('reply')

    await sendFlowMessage({ store, agent }, {
      userId: userA, text: 'Olá', idempotencyKey: 'context-key-001', requestId: 'req-1', now,
    })

    const inbound = store.rows.find((row) => row.direction === 'in')
    expect(inbound).toBeDefined()
    expect(agent.reply).toHaveBeenCalledWith(
      expect.objectContaining({ providerMessageId: inbound?.providerMessageId }),
    )
    expect(inbound?.providerMessageId).not.toBe('context-key-001')
  })

  it('reports a unique violation on the messages table as an already-stored row, not a 500', async () => {
    const query = {
      insert: () => query,
      select: () => query,
      single: async () => ({ data: null, error: { code: '23505', message: 'duplicate key value' } }),
    }
    const supabase = { from: () => query } as unknown as import('@mpp/db').ServiceClient
    const store = createSupabaseFlowChatStore(supabase)
    const input = {
      userId: userA, content: 'Olá', providerMessageId: 'x', requestId: 'req', state: 'processing' as const,
      createdAt: now.toISOString(),
    }

    await expect(store.insertInbound(input)).rejects.toBeInstanceOf(FlowMessageAlreadyStoredError)
    await expect(store.insertAssistant({ ...input, state: 'completed' })).rejects.toBeInstanceOf(
      FlowMessageAlreadyStoredError,
    )
  })
})

describe('Flow chat reply identity cannot collide with another key of the same user', () => {
  it.each([
    ['abcdefgh:assistant', 'abcdefgh'],
    ['abcdefgh', 'abcdefgh:assistant'],
  ])('keys %s then %s are two independent turns', async (firstKey, secondKey) => {
    const store = new FakeMessagesTable()
    const agent = flowAgent('reply')
    const deps = { store, agent }

    const first = await sendFlowMessage(deps, {
      userId: userA, text: 'Primeira', idempotencyKey: firstKey, requestId: 'req-1', now,
    })
    const second = await sendFlowMessage(deps, {
      userId: userA, text: 'Segunda', idempotencyKey: secondKey, requestId: 'req-2', now,
    })

    expect(first.message.content).toBe(`reply:${userA}:Primeira`)
    expect(second.message.content).toBe(`reply:${userA}:Segunda`)
    expect(agent.reply).toHaveBeenCalledTimes(2)
    expect(store.rows.filter((row) => row.state === 'processing')).toEqual([])
    expect(new Set(store.rows.map((row) => row.providerMessageId)).size).toBe(4)
  })

  it('a reply already stored for this turn is replayed, never reported as in progress', async () => {
    const store = new FakeMessagesTable()
    const agent = flowAgent('reply')
    const deps = { store, agent }
    const turn = { userId: userA, text: 'Olá', idempotencyKey: 'stored-reply-01', now }
    // A reply row for this very turn lands between the replay check and the insert.
    const originalInsert = store.insertAssistant
    store.insertAssistant = async (input) => {
      await originalInsert({ ...input, content: 'Resposta gravada antes' })
      return originalInsert(input)
    }

    const result = await sendFlowMessage(deps, { ...turn, requestId: 'req-1' })

    expect(result.message.content).toBe('Resposta gravada antes')
    expect(store.rows.filter((row) => row.state === 'processing')).toEqual([])
  })
})

describe('Flow chat legacy turns never write a reply id another row can hold', () => {
  it('retrying a legacy turn stores its reply under the scoped id, even when a legacy row owns "<key>:assistant"', async () => {
    const store = new FakeMessagesTable()
    // User B's pre-fix inbound whose bare key happens to be "legacykey:assistant".
    store.seed({
      userId: userB, direction: 'in', providerMessageId: 'legacykey:assistant', content: 'Olá B',
      state: 'completed', requestId: 'req-b-old', createdAt: '2026-09-20T09:00:00.000Z',
    })
    // User A's pre-fix inbound "legacykey" that failed without a reply.
    store.seed({
      userId: userA, direction: 'in', providerMessageId: 'legacykey', content: 'Olá A',
      state: 'failed', requestId: 'req-a-old', createdAt: '2026-09-20T09:00:01.000Z',
    })
    const agent = flowAgent('reply')

    const result = await sendFlowMessage({ store, agent }, {
      userId: userA, text: 'Olá A', idempotencyKey: 'legacykey', requestId: 'req-a-new', now,
    })

    expect(result.message.content).toBe(`reply:${userA}:Olá A`)
    expect(agent.reply).toHaveBeenCalledOnce()
    const reply = store.rows.find((row) => row.userId === userA && row.direction === 'out')
    expect(reply?.providerMessageId).toBe(`${scopedFlowProviderMessageId(userA, 'legacykey')}/assistant`)
    expect(store.rows.find((row) => row.providerMessageId === 'legacykey')?.state).toBe('completed')

    // A replay of the same legacy turn now finds that reply without calling Flow.
    const replay = await sendFlowMessage({ store, agent }, {
      userId: userA, text: 'Olá A', idempotencyKey: 'legacykey', requestId: 'req-a-replay', now,
    })
    expect(replay.message.content).toBe(`reply:${userA}:Olá A`)
    expect(agent.reply).toHaveBeenCalledOnce()
  })
})
