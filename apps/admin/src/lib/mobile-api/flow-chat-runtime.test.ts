import { describe, expect, it, vi } from 'vitest'
import {
  createSupabaseFlowChatStore,
  FLOW_EXECUTION_LEASE_MS,
  FLOW_EXECUTIONS_PER_MINUTE,
  type FlowAgent,
  type FlowChatStore,
  type FlowInboundAttempt,
  FlowMessageAlreadyStoredError,
  loadFlowHistory,
  type StoredFlowMessage,
  scopedFlowProviderMessageId,
  sendFlowMessage,
} from './flow-chat-service'

// Runtime gaps of the mobile Flow turn, closed without a paid provider call:
// retries under the per-minute limit, empty replies, and turns interrupted
// by an abrupt process death at controlled points. The table below is a
// unit-level model of `messages` (global unique provider id, compare-and-set
// on delivery_status, attempt markers in raw_payload) — not a database.

const userA = '00000000-0000-4000-8000-00000000000a'
const userB = '00000000-0000-4000-8000-00000000000b'
const now = new Date('2026-09-27T12:00:00.000Z')
const minutes = (count: number) => count * 60_000
const at = (offsetMs: number) => new Date(now.getTime() + offsetMs)
const lease = 10 * 60_000

interface Row {
  id: string
  userId: string
  direction: 'in' | 'out'
  providerMessageId: string
  content: string
  state: StoredFlowMessage['state']
  requestId: string
  createdAt: string
  attempt: FlowInboundAttempt | null
  errorCode: string | null
}

type Change = {
  from: StoredFlowMessage['state']
  to: StoredFlowMessage['state']
  requestId: string
  attempt: FlowInboundAttempt
  expectedAttemptStartedAt: string | null
  expectedRequestId?: string
  errorCode?: string
}

class RuntimeTable implements FlowChatStore {
  readonly rows: Row[] = []
  private sequence = 0

  seedInbound(row: Partial<Row> & Pick<Row, 'userId' | 'providerMessageId' | 'content' | 'state' | 'createdAt'>) {
    this.rows.push({
      id: `seed-${++this.sequence}`,
      direction: 'in',
      requestId: 'req-seed',
      attempt: null,
      errorCode: null,
      ...row,
    })
  }

  seedReply(userId: string, providerMessageId: string, content: string, createdAt: string) {
    this.rows.push({
      id: `seed-${++this.sequence}`,
      userId,
      direction: 'out',
      providerMessageId,
      content,
      state: 'completed',
      requestId: 'req-seed',
      createdAt,
      attempt: null,
      errorCode: null,
    })
  }

  inbound(userId: string, providerMessageId: string) {
    return this.rows.find(
      (row) => row.userId === userId && row.providerMessageId === providerMessageId && row.direction === 'in',
    )
  }

  private stored(row: Row): StoredFlowMessage {
    return {
      id: row.id,
      role: row.direction === 'in' ? 'user' : 'assistant',
      content: row.content,
      state: row.state,
      requestId: row.requestId,
      createdAt: row.createdAt,
      attempt: row.attempt,
    }
  }

  private async find(userId: string, providerMessageId: string, direction: 'in' | 'out') {
    await Promise.resolve()
    const row = this.rows.find(
      (candidate) =>
        candidate.userId === userId &&
        candidate.providerMessageId === providerMessageId &&
        candidate.direction === direction,
    )
    return row ? this.stored(row) : null
  }

  private async insert(input: Parameters<FlowChatStore['insertInbound']>[0], direction: 'in' | 'out') {
    await Promise.resolve()
    if (this.rows.some((row) => row.providerMessageId === input.providerMessageId)) {
      throw new FlowMessageAlreadyStoredError()
    }
    const row: Row = {
      id: `row-${++this.sequence}`,
      userId: input.userId,
      direction,
      providerMessageId: input.providerMessageId,
      content: input.content,
      state: input.state,
      requestId: input.requestId,
      createdAt: input.createdAt,
      attempt: direction === 'in' ? (input.attempt ?? null) : null,
      errorCode: null,
    }
    this.rows.push(row)
    return this.stored(row)
  }

  private set(userId: string, providerMessageId: string, state: Row['state'], errorCode: string | null) {
    const row = this.inbound(userId, providerMessageId)
    if (row) {
      row.state = state
      row.errorCode = errorCode
    }
  }

  loadHistory = async (user: string) => this.rows.filter((row) => row.userId === user).map((row) => this.stored(row))
  findInbound = (user: string, id: string) => this.find(user, id, 'in')
  findAssistant = (user: string, id: string) => this.find(user, id, 'out')
  insertInbound = (input: Parameters<FlowChatStore['insertInbound']>[0]) => this.insert(input, 'in')
  insertAssistant = (input: Parameters<FlowChatStore['insertAssistant']>[0]) => this.insert(input, 'out')
  completeInbound = async (user: string, id: string) => this.set(user, id, 'completed', null)
  failInbound = async (user: string, id: string, code?: string) => this.set(user, id, 'failed', code ?? 'flow_provider_failed')

  /** Executions started in the window: first attempts plus every retry. */
  countRecentExecutions = async (user: string, since: string) => {
    await Promise.resolve()
    let count = 0
    for (const row of this.rows) {
      if (row.userId !== user || row.direction !== 'in') continue
      if (row.createdAt >= since) count += 1
      count += (row.attempt?.retryStartedAt ?? []).filter((time) => time >= since).length
    }
    return count
  }

  /** Compare-and-set on delivery_status and on the attempt, as the adapter's conditional update. */
  transitionInbound = async (user: string, id: string, change: Change) => {
    await Promise.resolve()
    const row = this.inbound(user, id)
    if (!row || row.state !== change.from) return false
    if ((row.attempt?.startedAt ?? null) !== change.expectedAttemptStartedAt) return false
    if (change.expectedRequestId !== undefined && row.requestId !== change.expectedRequestId) return false
    row.state = change.to
    row.requestId = change.requestId
    row.attempt = change.attempt
    row.errorCode = change.errorCode ?? null
    return true
  }
}

function agentReplying(text = 'Resposta do Flow') {
  return { reply: vi.fn(async () => ({ text, metadata: {} })) } satisfies FlowAgent
}

function agentFailing() {
  return {
    reply: vi.fn(async () => {
      throw new Error('provider timeout')
    }),
  } satisfies FlowAgent
}

function send(
  deps: { store: FlowChatStore; agent: FlowAgent },
  userId: string,
  key: string,
  when: Date,
  text = 'Como está meu dia?',
) {
  return sendFlowMessage(deps, { userId, text, idempotencyKey: key, requestId: `req-${key}-${when.getTime()}`, now: when })
}

function seedRecentExecutions(table: RuntimeTable, userId: string, count: number) {
  for (let index = 0; index < count; index += 1) {
    table.seedInbound({
      userId,
      providerMessageId: scopedFlowProviderMessageId(userId, `recent-${index}-key`),
      content: `mensagem ${index}`,
      state: 'completed',
      createdAt: at(-20_000 - index).toISOString(),
    })
  }
}

function seedFailedTurn(table: RuntimeTable, userId: string, key: string, createdMsAgo = minutes(5)) {
  const createdAt = at(-createdMsAgo).toISOString()
  table.seedInbound({
    userId,
    providerMessageId: scopedFlowProviderMessageId(userId, key),
    content: 'Como está meu dia?',
    state: 'failed',
    createdAt,
    attempt: { startedAt: createdAt, providerStartedAt: createdAt, retryStartedAt: [] },
    errorCode: 'flow_provider_failed',
  })
}

describe('3.1 retries run through the per-minute limit', () => {
  it('the limit constants are the documented ones', () => {
    expect(FLOW_EXECUTIONS_PER_MINUTE).toBe(10)
    expect(FLOW_EXECUTION_LEASE_MS).toBe(lease)
    // The lease must outlive the route's maxDuration (300 s) so a stale turn
    // provably belongs to an invocation that has already ended.
    expect(FLOW_EXECUTION_LEASE_MS).toBeGreaterThan(300_000)
  })

  it('refuses a retry of a failed turn when the limit is reached, without calling the provider', async () => {
    const store = new RuntimeTable()
    seedRecentExecutions(store, userA, 10)
    seedFailedTurn(store, userA, 'failed-key-0001')
    const agent = agentReplying()

    await expect(send({ store, agent }, userA, 'failed-key-0001', now)).rejects.toMatchObject({
      status: 429,
      code: 'flow_rate_limited',
    })
    expect(agent.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, scopedFlowProviderMessageId(userA, 'failed-key-0001'))?.state).toBe('failed')
  })

  it('counts every retry execution, so repeated retries of one key cannot exceed the limit', async () => {
    const store = new RuntimeTable()
    seedFailedTurn(store, userA, 'retry-loop-key1')
    const agent = agentFailing()
    const outcomes: number[] = []
    for (let attempt = 0; attempt < 12; attempt += 1) {
      const result = await send({ store, agent }, userA, 'retry-loop-key1', at(attempt * 1_000)).catch(
        (error: { status: number }) => error.status,
      )
      outcomes.push(typeof result === 'number' ? result : 201)
    }

    expect(agent.reply).toHaveBeenCalledTimes(10)
    expect(outcomes.slice(0, 10)).toEqual(Array(10).fill(502))
    expect(outcomes.slice(10)).toEqual([429, 429])
    // The same budget covers new messages too.
    await expect(send({ store, agent: agentReplying() }, userA, 'brand-new-key-1', at(12_000))).rejects.toMatchObject({
      status: 429,
    })
  })

  it('a retry outside the window is allowed again and is counted once', async () => {
    const store = new RuntimeTable()
    seedFailedTurn(store, userA, 'later-retry-key')
    const agent = agentReplying()

    const result = await send({ store, agent }, userA, 'later-retry-key', now)

    expect(result.message.content).toBe('Resposta do Flow')
    expect(agent.reply).toHaveBeenCalledOnce()
    expect(await store.countRecentExecutions(userA, at(-60_000).toISOString())).toBe(1)
  })

  it('a replay of a completed turn neither counts nor calls the provider, even at the limit', async () => {
    const store = new RuntimeTable()
    const agent = agentReplying()
    await send({ store, agent }, userA, 'replayed-key-01', now)
    seedRecentExecutions(store, userA, 12)

    for (let index = 0; index < 5; index += 1) {
      const replay = await send({ store, agent }, userA, 'replayed-key-01', at(index * 100))
      expect(replay.message.content).toBe('Resposta do Flow')
    }
    expect(agent.reply).toHaveBeenCalledOnce()
  })

  it('two concurrent retries of the same failed turn call the provider once', async () => {
    const store = new RuntimeTable()
    seedFailedTurn(store, userA, 'race-retry-key1')
    const agent = agentReplying()

    const results = await Promise.allSettled([
      send({ store, agent }, userA, 'race-retry-key1', now),
      send({ store, agent }, userA, 'race-retry-key1', now),
    ])

    expect(agent.reply).toHaveBeenCalledOnce()
    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1)
    const rejected = results.find((result) => result.status === 'rejected') as PromiseRejectedResult
    expect(rejected.reason).toMatchObject({ status: 409, code: 'idempotency_request_in_progress' })
  })

  it('one patient at the limit does not limit another (A/B), and neither reads the other turn', async () => {
    const store = new RuntimeTable()
    seedRecentExecutions(store, userA, 10)
    seedFailedTurn(store, userA, 'shared-key-0001')
    seedFailedTurn(store, userB, 'shared-key-0001')
    const agent = agentReplying()

    await expect(send({ store, agent }, userA, 'shared-key-0001', now)).rejects.toMatchObject({ status: 429 })
    const fromB = await send({ store, agent }, userB, 'shared-key-0001', now)

    expect(fromB.message.content).toBe('Resposta do Flow')
    expect(agent.reply).toHaveBeenCalledOnce()
    expect(agent.reply).toHaveBeenCalledWith(expect.objectContaining({ userId: userB }))
    expect(store.inbound(userA, scopedFlowProviderMessageId(userA, 'shared-key-0001'))?.state).toBe('failed')
  })
})

describe('3.2 an empty visible reply is never a successful turn', () => {
  it.each(['', '   ', '\n\n'])('reply %j fails the turn with the typed 502 and stores no assistant', async (text) => {
    const store = new RuntimeTable()
    const agent = agentReplying(text)

    await expect(send({ store, agent }, userA, 'empty-reply-key', now)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(store.rows.filter((row) => row.direction === 'out')).toEqual([])
    expect(store.inbound(userA, scopedFlowProviderMessageId(userA, 'empty-reply-key'))?.state).toBe('failed')
  })
})

describe('3.3 a turn interrupted by an abrupt process death', () => {
  const key = 'interrupted-key'
  const inboundId = scopedFlowProviderMessageId(userA, key)
  const replyId = `${inboundId}/assistant`

  function seedProcessing(table: RuntimeTable, startedMsAgo: number, providerStarted: boolean | 'legacy') {
    const startedAt = at(-startedMsAgo).toISOString()
    table.seedInbound({
      userId: userA,
      providerMessageId: inboundId,
      content: 'Como está meu dia?',
      state: 'processing',
      createdAt: startedAt,
      attempt:
        providerStarted === 'legacy'
          ? null
          : { startedAt, providerStartedAt: providerStarted ? startedAt : null, retryStartedAt: [] },
    })
  }

  it('an attempt still inside its lease is reported in progress and never re-executed', async () => {
    const store = new RuntimeTable()
    seedProcessing(store, minutes(1), false)
    const agent = agentReplying()

    await expect(send({ store, agent }, userA, key, now)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_request_in_progress',
    })
    expect(agent.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, inboundId)?.state).toBe('processing')
  })

  it('died before the provider: continues once, counted, with no duplicate message', async () => {
    const store = new RuntimeTable()
    seedProcessing(store, lease + minutes(1), false)
    const agent = agentReplying()

    const result = await send({ store, agent }, userA, key, now)

    expect(result.message.content).toBe('Resposta do Flow')
    expect(agent.reply).toHaveBeenCalledOnce()
    expect(store.rows.filter((row) => row.direction === 'in')).toHaveLength(1)
    expect(store.rows.filter((row) => row.direction === 'out')).toHaveLength(1)
    expect(store.inbound(userA, inboundId)?.state).toBe('completed')
    expect(await store.countRecentExecutions(userA, at(-60_000).toISOString())).toBe(1)
  })

  it.each([
    ['after the provider started, before the reply was stored', true],
    ['in a legacy row without attempt markers', 'legacy'],
  ] as const)('died %s: not re-executed; the turn fails and only an explicit retry runs it', async (_label, marker) => {
    const store = new RuntimeTable()
    seedProcessing(store, lease + minutes(1), marker)
    const agent = agentReplying()

    await expect(send({ store, agent }, userA, key, now)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(agent.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, inboundId)?.state).toBe('failed')
    expect(store.inbound(userA, inboundId)?.errorCode).toBe('flow_turn_interrupted')

    const retried = await send({ store, agent }, userA, key, at(1_000))
    expect(retried.message.content).toBe('Resposta do Flow')
    expect(agent.reply).toHaveBeenCalledOnce()
    expect(store.rows.filter((row) => row.direction === 'out')).toHaveLength(1)
  })

  it('died after the reply was stored, before the HTTP response: replays without the provider', async () => {
    const store = new RuntimeTable()
    seedProcessing(store, lease + minutes(1), true)
    store.seedReply(userA, replyId, 'Resposta já gravada', at(-lease).toISOString())
    const agent = agentReplying()

    const result = await send({ store, agent }, userA, key, now)

    expect(result.message.content).toBe('Resposta já gravada')
    expect(agent.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, inboundId)?.state).toBe('completed')
    expect(await store.countRecentExecutions(userA, at(-60_000).toISOString())).toBe(0)
  })
})

describe('3.3 abrupt death at controlled points (the pending promise never settles)', () => {
  const key = 'crash-point-key'
  const inboundId = scopedFlowProviderMessageId(userA, key)
  const never = () => new Promise<never>(() => undefined)
  const settle = () => new Promise((resolve) => setTimeout(resolve, 0))

  it('before the provider: the marker was never written, so the next invocation continues the turn', async () => {
    const store = new RuntimeTable()
    const crashing = Object.create(store) as RuntimeTable
    crashing.transitionInbound = async (user, id, change) =>
      change.from === 'processing' && change.to === 'processing' ? never() : store.transitionInbound(user, id, change)
    const firstAgent = agentReplying()
    void send({ store: crashing, agent: firstAgent }, userA, key, now)
    await settle()

    expect(firstAgent.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, inboundId)?.state).toBe('processing')
    expect(store.inbound(userA, inboundId)?.attempt?.providerStartedAt).toBeNull()

    const agent = agentReplying()
    await expect(send({ store, agent }, userA, key, at(minutes(2)))).rejects.toMatchObject({ status: 409 })
    const result = await send({ store, agent }, userA, key, at(lease + minutes(1)))
    expect(result.message.content).toBe('Resposta do Flow')
    expect(agent.reply).toHaveBeenCalledOnce()
  })

  it('after the provider, before persistence: the next invocation does not call the provider again', async () => {
    const store = new RuntimeTable()
    const crashing = Object.create(store) as RuntimeTable
    crashing.insertAssistant = () => never()
    const firstAgent = agentReplying('Resposta perdida')
    void send({ store: crashing, agent: firstAgent }, userA, key, now)
    await settle()

    expect(firstAgent.reply).toHaveBeenCalledOnce()
    expect(store.inbound(userA, inboundId)?.attempt?.providerStartedAt).toBe(now.toISOString())

    const agent = agentReplying()
    await expect(send({ store, agent }, userA, key, at(lease + minutes(1)))).rejects.toMatchObject({ status: 502 })
    expect(agent.reply).not.toHaveBeenCalled()
    expect(store.rows.filter((row) => row.direction === 'out')).toEqual([])
  })

  it('after persistence, before the HTTP response: the stored reply is replayed', async () => {
    const store = new RuntimeTable()
    const crashing = Object.create(store) as RuntimeTable
    crashing.completeInbound = () => never()
    void send({ store: crashing, agent: agentReplying('Resposta gravada') }, userA, key, now)
    await settle()

    expect(store.inbound(userA, inboundId)?.state).toBe('processing')
    const agent = agentReplying()
    const result = await send({ store, agent }, userA, key, at(lease + minutes(1)))
    expect(result.message.content).toBe('Resposta gravada')
    expect(agent.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, inboundId)?.state).toBe('completed')
  })
})

describe('Supabase adapter for the runtime controls', () => {
  function recordingClient(results: { count?: number; rows?: unknown[]; updated?: unknown[] }) {
    const calls: Array<[string, ...unknown[]]> = []
    const query: Record<string, unknown> = {}
    const chain = (name: string) => (...args: unknown[]) => {
      calls.push([name, ...args])
      return query
    }
    for (const name of ['select', 'eq', 'is', 'gte', 'update', 'order', 'insert']) query[name] = chain(name)
    query.limit = (...args: unknown[]) => {
      calls.push(['limit', ...args])
      return Promise.resolve({ data: results.rows ?? [], error: null })
    }
    query.then = (resolve: (value: unknown) => unknown) => {
      const selected = calls.find((call) => call[0] === 'select')
      const head = selected && (selected[2] as { head?: boolean } | undefined)?.head
      return Promise.resolve(
        head ? { count: results.count ?? 0, error: null } : { data: results.updated ?? [], error: null },
      ).then(resolve)
    }
    const supabase = { from: (table: string) => (calls.push(['from', table]), query) }
    return { calls, supabase: supabase as unknown as import('@mpp/db').ServiceClient }
  }

  it('counts first attempts by created_at and retries by the last retry marker, per user and channel', async () => {
    const since = at(-60_000).toISOString()
    const { calls, supabase } = recordingClient({
      count: 3,
      rows: [
        { raw_payload: { retry_started_at: [at(-120_000).toISOString(), at(-5_000).toISOString(), now.toISOString()] } },
        { raw_payload: { retry_started_at: 'not-a-list' } },
      ],
    })

    const count = await createSupabaseFlowChatStore(supabase).countRecentExecutions(userA, since)

    expect(count).toBe(5)
    expect(calls).toContainEqual(['gte', 'created_at', since])
    expect(calls).toContainEqual(['gte', 'raw_payload->>last_retry_at', since])
    expect(calls.filter((call) => call[0] === 'eq' && call[1] === 'user_id')).toEqual([
      ['eq', 'user_id', userA],
      ['eq', 'user_id', userA],
    ])
  })

  it('changes an inbound turn only from the expected state and reports whether it did', async () => {
    const attempt: FlowInboundAttempt = {
      startedAt: now.toISOString(),
      providerStartedAt: null,
      retryStartedAt: [now.toISOString()],
    }
    const moved = recordingClient({ updated: [{ id: 'row-1' }] })
    const lost = recordingClient({ updated: [] })
    const observed = at(-minutes(5)).toISOString()
    const change = {
      from: 'failed' as const,
      to: 'processing' as const,
      requestId: 'req-1',
      attempt,
      expectedAttemptStartedAt: observed,
    }

    expect(await createSupabaseFlowChatStore(moved.supabase).transitionInbound(userA, 'id-1', change)).toBe(true)
    expect(await createSupabaseFlowChatStore(lost.supabase).transitionInbound(userA, 'id-1', change)).toBe(false)
    expect(moved.calls).toContainEqual(['eq', 'delivery_status', 'failed'])
    expect(moved.calls).toContainEqual(['eq', 'raw_payload->>attempt_started_at', observed])

    const legacy = recordingClient({ updated: [{ id: 'row-1' }] })
    await createSupabaseFlowChatStore(legacy.supabase).transitionInbound(userA, 'id-1', {
      ...change,
      expectedAttemptStartedAt: null,
      expectedRequestId: 'req-0',
    })
    expect(legacy.calls).toContainEqual(['is', 'raw_payload->>attempt_started_at', null])
    expect(legacy.calls).toContainEqual(['eq', 'raw_payload->>request_id', 'req-0'])
    const update = moved.calls.find((call) => call[0] === 'update')?.[1] as Record<string, unknown>
    expect(update).toMatchObject({
      delivery_status: 'processing',
      delivery_error: null,
      raw_payload: {
        request_id: 'req-1',
        conversation_id: 'flow',
        attempt_started_at: now.toISOString(),
        provider_started_at: null,
        retry_started_at: [now.toISOString()],
        last_retry_at: now.toISOString(),
      },
    })
  })
})

// ── Adversarial review follow-ups ─────────────────────────────────────────

describe('3.1 the per-minute limit holds under concurrent sends of different keys', () => {
  it('nine executions plus three concurrent new keys: at most one reaches the provider', async () => {
    const store = new RuntimeTable()
    seedRecentExecutions(store, userA, 9)
    const agent = agentReplying()

    const results = await Promise.allSettled([
      send({ store, agent }, userA, 'burst-key-0001', now),
      send({ store, agent }, userA, 'burst-key-0002', now),
      send({ store, agent }, userA, 'burst-key-0003', now),
    ])

    expect(agent.reply.mock.calls.length).toBeLessThanOrEqual(1)
    const limited = results.filter(
      (result) => result.status === 'rejected' && (result.reason as { status: number }).status === 429,
    )
    expect(limited.length).toBeGreaterThanOrEqual(2)
    // A refused turn is kept as failed (never a silent success, never deleted).
    for (const key of ['burst-key-0001', 'burst-key-0002', 'burst-key-0003']) {
      expect(store.inbound(userA, scopedFlowProviderMessageId(userA, key))?.state).not.toBe('processing')
    }
  })
})

describe('3.3 compare-and-set is bound to the attempt, not only to the state', () => {
  it('a request holding a stale view cannot close or take over an attempt another request already started', async () => {
    const key = 'aba-key-000001'
    const inboundId = scopedFlowProviderMessageId(userA, key)
    const store = new RuntimeTable()
    const startedAt = at(-(lease + minutes(1))).toISOString()
    store.seedInbound({
      userId: userA,
      providerMessageId: inboundId,
      content: 'Como está meu dia?',
      state: 'processing',
      createdAt: startedAt,
      attempt: { startedAt, providerStartedAt: null, retryStartedAt: [] },
    })
    const staleView = await store.findInbound(userA, inboundId)

    // B recovers the turn and is now waiting on the provider.
    const hanging = { reply: vi.fn(() => new Promise<never>(() => undefined)) } satisfies FlowAgent
    void send({ store, agent: hanging }, userA, key, now)
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(hanging.reply).toHaveBeenCalledOnce()

    // C still holds the stale snapshot from before B acted.
    const staleStore = Object.create(store) as RuntimeTable
    staleStore.findInbound = async (user, id) => (id === inboundId && user === userA ? staleView : null)
    const agentC = agentReplying()
    await expect(send({ store: staleStore, agent: agentC }, userA, key, now)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_request_in_progress',
    })
    expect(agentC.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, inboundId)?.state).toBe('processing')
    expect(store.inbound(userA, inboundId)?.attempt?.providerStartedAt).toBe(now.toISOString())
  })
})

describe('3.3 a storage error before the provider never leaves the turn processing', () => {
  it('the attempt marker cannot be written: the turn fails with 502 and a retry can run', async () => {
    const store = new RuntimeTable()
    const broken = Object.create(store) as RuntimeTable
    broken.transitionInbound = async (user, id, change) => {
      if (change.from === 'processing' && change.to === 'processing') throw new Error('connection reset')
      return store.transitionInbound(user, id, change)
    }
    const agent = agentReplying()

    await expect(send({ store: broken, agent }, userA, 'marker-fail-key', now)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(agent.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, scopedFlowProviderMessageId(userA, 'marker-fail-key'))?.state).toBe('failed')

    const retried = await send({ store, agent }, userA, 'marker-fail-key', at(1_000))
    expect(retried.message.content).toBe('Resposta do Flow')
  })
})

describe('3.2 an empty reply stored before this change is not shown as a message', () => {
  it('history leaves out assistant rows with no visible text', async () => {
    const store = new RuntimeTable()
    store.seedInbound({
      userId: userA,
      providerMessageId: 'mobile_flow/a/old',
      content: 'Oi',
      state: 'completed',
      createdAt: at(-5_000).toISOString(),
    })
    store.seedReply(userA, 'mobile_flow/a/old/assistant', '', at(-4_000).toISOString())
    store.seedReply(userA, 'mobile_flow/a/other/assistant', 'Resposta real', at(-3_000).toISOString())

    const history = await loadFlowHistory({ store, agent: agentReplying() }, userA, 20)

    expect(history.messages.map((message) => message.content)).toEqual(['Oi', 'Resposta real'])
  })
})

describe('the lease is tied to the route and to the idempotency ledger', () => {
  it('outlives the route maxDuration and equals the ledger in-progress window', async () => {
    const { readFileSync } = await import('node:fs')
    const { resolve } = await import('node:path')
    // Read from the route's source, as the ledger window below is read from
    // the SQL: importing the route would load the whole agent and providers
    // only to compare two constants.
    const route = readFileSync(
      resolve(process.cwd(), 'src/app/api/mobile/v1/flow/chat/route.ts'),
      'utf8',
    )
    const maxDuration = Number(route.match(/^export const maxDuration = (\d+)$/m)?.[1])
    expect(maxDuration).toBeGreaterThan(0)
    expect(FLOW_EXECUTION_LEASE_MS).toBeGreaterThan(maxDuration * 1_000)
    const sql = readFileSync(
      resolve(process.cwd(), '../../supabase/migrations/20260720130537_mobile_api_idempotency.sql'),
      'utf8',
    )
    const window = sql.match(/state = 'processing'\s+AND v_request\.updated_at > v_now - interval '(\d+) minutes'/)
    expect(Number(window?.[1]) * 60_000).toBe(FLOW_EXECUTION_LEASE_MS)
  })
})

describe('second review follow-ups', () => {
  it('a storage error in the post-record count fails the turn (502), never leaves it processing', async () => {
    const store = new RuntimeTable()
    let calls = 0
    const broken = Object.create(store) as RuntimeTable
    broken.countRecentExecutions = async (user, since) => {
      calls += 1
      if (calls === 2) throw new Error('connection reset')
      return store.countRecentExecutions(user, since)
    }
    const agent = agentReplying()

    await expect(send({ store: broken, agent }, userA, 'count-fail-key1', now)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(agent.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, scopedFlowProviderMessageId(userA, 'count-fail-key1'))?.state).toBe('failed')
  })

  it('an ambiguous insert error gives back a row that may have been written', async () => {
    const store = new RuntimeTable()
    const broken = Object.create(store) as RuntimeTable
    broken.insertInbound = async (input) => {
      await store.insertInbound(input)
      throw new Error('response lost after commit')
    }
    const agent = agentReplying()

    await expect(send({ store: broken, agent }, userA, 'insert-fail-key', now)).rejects.toMatchObject({ status: 502 })
    expect(agent.reply).not.toHaveBeenCalled()
    expect(store.inbound(userA, scopedFlowProviderMessageId(userA, 'insert-fail-key'))?.state).toBe('failed')
  })

  it('an empty reply stored before this change is never replayed as a successful turn', async () => {
    const store = new RuntimeTable()
    const inboundId = scopedFlowProviderMessageId(userA, 'old-empty-key1')
    store.seedInbound({
      userId: userA,
      providerMessageId: inboundId,
      content: 'Como está meu dia?',
      state: 'completed',
      createdAt: at(-minutes(30)).toISOString(),
    })
    store.seedReply(userA, `${inboundId}/assistant`, '', at(-minutes(30)).toISOString())
    const agent = agentReplying()

    await expect(send({ store, agent }, userA, 'old-empty-key1', now)).rejects.toMatchObject({ status: 502 })
    expect(agent.reply).not.toHaveBeenCalled()
  })

  it('after a refused burst, the next request outside the window runs', async () => {
    const store = new RuntimeTable()
    seedRecentExecutions(store, userA, 9)
    const agent = agentReplying()
    await Promise.allSettled(
      ['burst-2-key-01', 'burst-2-key-02', 'burst-2-key-03'].map((key) => send({ store, agent }, userA, key, now)),
    )

    const later = await send({ store, agent }, userA, 'after-burst-key', at(61_000))

    expect(later.message.content).toBe('Resposta do Flow')
  })

  it('a count the database did not return is treated as an error, not as zero', async () => {
    const query: Record<string, unknown> = {}
    const chain = () => query
    for (const name of ['select', 'eq', 'gte']) query[name] = chain
    query.then = (resolve: (value: unknown) => unknown) => Promise.resolve({ count: null, error: null }).then(resolve)
    query.limit = async () => ({ data: [], error: null })
    const supabase = { from: () => query } as unknown as import('@mpp/db').ServiceClient

    await expect(
      createSupabaseFlowChatStore(supabase).countRecentExecutions(userA, now.toISOString()),
    ).rejects.toThrow('Unable to enforce Flow rate limit')
  })
})

// Staging device gate 2026-09-28 (23:02 local): a Flow diet proposal turn
// failed with 502 flow_provider_failed and nothing was logged, so the cause
// could not be found. The failure is now logged by class, provider status and
// an internal code only; the patient's text and provider messages never are.
describe('a failed Flow turn is logged without patient data', () => {
  it('logs class, provider status and an internal code-like message', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      const store = new RuntimeTable()
      const agent = {
        reply: vi.fn(async () => {
          throw new Error('diet proposal profile lookup failed')
        }),
      } satisfies FlowAgent
      await expect(send({ store, agent }, 'user-log', 'log-key-00001', new Date('2026-09-29T02:02:15Z'), 'quero uma dieta com frango')).rejects.toMatchObject({ code: 'flow_provider_failed' })
      expect(spy).toHaveBeenCalledWith('[mobile-flow] turn_failed', {
        error_name: 'Error',
        provider_status: null,
        internal_code: 'diet proposal profile lookup failed',
      })
      expect(JSON.stringify(spy.mock.calls)).not.toContain('frango')
    } finally {
      spy.mockRestore()
    }
  })

  it('a provider message or anything not code-like is not logged', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      const store = new RuntimeTable()
      const agent = {
        reply: vi.fn(async () => {
          throw Object.assign(new Error('400 Prompt contained: Maria, 54 anos, diabética'), { status: 400 })
        }),
      } satisfies FlowAgent
      await expect(send({ store, agent }, 'user-log', 'log-key-00002', new Date('2026-09-29T02:02:15Z'))).rejects.toMatchObject({ code: 'flow_provider_failed' })
      expect(spy.mock.calls[0]?.[1]).toEqual({ error_name: 'Error', provider_status: 400, internal_code: null })
      expect(JSON.stringify(spy.mock.calls)).not.toContain('Maria')
    } finally {
      spy.mockRestore()
    }
  })

  it('an empty visible reply is logged as such', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      const store = new RuntimeTable()
      await expect(send({ store, agent: agentReplying('   ') }, 'user-log', 'log-key-00003', new Date('2026-09-29T02:02:15Z'))).rejects.toMatchObject({ code: 'flow_provider_failed' })
      expect(spy).toHaveBeenCalledWith('[mobile-flow] turn_failed', { error_name: 'EmptyReply', provider_status: null, internal_code: null })
    } finally {
      spy.mockRestore()
    }
  })
})
