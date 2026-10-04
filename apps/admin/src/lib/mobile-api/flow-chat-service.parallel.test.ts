import { afterEach, beforeEach, describe, expect, it, type MockInstance, vi } from 'vitest'
import {
  createSupabaseFlowChatStore,
  createSupabaseFlowDraftLookup,
  type FlowAgent,
  type FlowChatStore,
  type FlowDraftLookup,
  type FlowInboundAttempt,
  type FlowInboundTransition,
  FlowMessageAlreadyStoredError,
  type StoredFlowMessage,
  scopedFlowProviderMessageId,
  sendFlowMessage,
} from './flow-chat-service'

// The reads and writes around the Flow agent used to run one after the other.
// Independent ones now share a wave (performance audit 2026-10-04). These
// tests hold three things:
//  (a) every idempotency / rate-limit decision is the one the sequential code
//      made, including when any of the parallel reads fails;
//  (b) how many sequential waves a turn costs (a wave = store calls that
//      start while no other is in flight = one database round trip of wall
//      time);
//  (c) the per-phase timing line: whole milliseconds, identifiers, no text.
// The table is a unit-level model of `messages`, not a database.

const userA = '00000000-0000-4000-8000-00000000000a'
const now = new Date('2026-10-04T18:00:00.000Z')
const at = (offsetMs: number) => new Date(now.getTime() + offsetMs).toISOString()
const LEASE_MS = 10 * 60_000
const TRIP_MS = 2
const patientText = 'Almocei arroz, feijão e frango grelhado'
const replyText = 'Registrado: 620 kcal no almoço.'

interface Row {
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

/** `messages` for the mobile Flow: global unique provider id, compare-and-set on the turn. */
class Table implements FlowChatStore {
  readonly rows: Row[] = []

  seed(row: Partial<Row> & Pick<Row, 'direction' | 'providerMessageId' | 'content'>) {
    this.rows.push({
      userId: userA,
      state: 'completed',
      requestId: 'req-seeded-0001',
      createdAt: at(-30 * 60_000),
      attempt: null,
      errorCode: null,
      ...row,
    })
  }

  inbound(providerMessageId: string) {
    return this.rows.find(
      (row) => row.direction === 'in' && row.providerMessageId === providerMessageId,
    )
  }

  private stored(row: Row): StoredFlowMessage {
    return {
      id: `${row.direction}:${row.providerMessageId}`,
      role: row.direction === 'in' ? 'user' : 'assistant',
      content: row.content,
      state: row.state,
      requestId: row.requestId,
      createdAt: row.createdAt,
      ...(row.direction === 'in' ? { attempt: row.attempt } : {}),
    }
  }

  private find(userId: string, providerMessageId: string, direction: Row['direction']) {
    const row = this.rows.find(
      (candidate) =>
        candidate.userId === userId &&
        candidate.providerMessageId === providerMessageId &&
        candidate.direction === direction,
    )
    return row ? this.stored(row) : null
  }

  private insert(
    input: Parameters<FlowChatStore['insertInbound']>[0],
    direction: Row['direction'],
  ) {
    if (this.rows.some((row) => row.providerMessageId === input.providerMessageId)) {
      throw new FlowMessageAlreadyStoredError()
    }
    const row: Row = {
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

  private set(providerMessageId: string, state: Row['state'], errorCode: string | null) {
    const row = this.inbound(providerMessageId)
    if (row) Object.assign(row, { state, errorCode })
  }

  loadHistory = async () => this.rows.map((row) => this.stored(row))
  findInbound = async (user: string, id: string) => this.find(user, id, 'in')
  findAssistant = async (user: string, id: string) => this.find(user, id, 'out')
  insertInbound = async (input: Parameters<FlowChatStore['insertInbound']>[0]) =>
    this.insert(input, 'in')
  insertAssistant = async (input: Parameters<FlowChatStore['insertAssistant']>[0]) =>
    this.insert(input, 'out')
  completeInbound = async (_user: string, id: string) => this.set(id, 'completed', null)
  failInbound = async (_user: string, id: string, code?: string) =>
    this.set(id, 'failed', code ?? 'flow_provider_failed')
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
  transitionInbound = async (_user: string, id: string, change: FlowInboundTransition) => {
    const row = this.inbound(id)
    if (!row || row.state !== change.from) return false
    if ((row.attempt?.startedAt ?? null) !== change.expectedAttemptStartedAt) return false
    if (change.expectedRequestId !== undefined && row.requestId !== change.expectedRequestId)
      return false
    Object.assign(row, {
      state: change.to,
      requestId: change.requestId,
      attempt: change.attempt,
      errorCode: change.errorCode ?? null,
    })
    return true
  }
}

/** Groups calls into waves: a call that starts while none is in flight opens a new one. */
class Waves {
  count = 0
  private inFlight = 0
  readonly calls: Array<{ wave: number; op: string }> = []

  async track<T>(op: string, work: () => Promise<T>): Promise<T> {
    if (this.inFlight === 0) this.count += 1
    this.inFlight += 1
    this.calls.push({ wave: this.count, op })
    try {
      await new Promise((resolve) => setTimeout(resolve, TRIP_MS))
      return await work()
    } finally {
      this.inFlight -= 1
    }
  }

  /** The operations of each wave, in order, e.g. [['a', 'b'], ['c']]. */
  list(): string[][] {
    const grouped: string[][] = []
    for (const call of this.calls) {
      grouped[call.wave - 1] = [...(grouped[call.wave - 1] ?? []), call.op]
    }
    return grouped
  }

  ops(): string[] {
    return this.calls.map((call) => call.op)
  }
}

type Fault =
  | 'findInbound:scoped'
  | 'findInbound:legacy'
  | 'findAssistant:scoped'
  | 'findAssistant:legacy'
  | 'countRecentExecutions#1'
  | 'countRecentExecutions#2'
  | 'completeInbound'

const faultError = (fault: string) => new Error(`fault ${fault}`)

/** The table behind a wave recorder; a faulted operation takes its trip and then throws. */
function traced(table: Table, waves: Waves, faults: readonly Fault[]): FlowChatStore {
  let counts = 0
  const run = <T>(op: string, work: () => Promise<T>) =>
    waves.track(op, async () => {
      if ((faults as readonly string[]).includes(op)) throw faultError(op)
      return work()
    })
  const idKind = (id: string) => (id.startsWith('mobile_flow/') ? 'scoped' : 'legacy')
  return {
    loadHistory: () => run('loadHistory', () => table.loadHistory()),
    findInbound: (user, id) => run(`findInbound:${idKind(id)}`, () => table.findInbound(user, id)),
    findAssistant: (user, id) =>
      run(`findAssistant:${idKind(id)}`, () => table.findAssistant(user, id)),
    countRecentExecutions: (user, since) =>
      run(`countRecentExecutions#${++counts}`, () => table.countRecentExecutions(user, since)),
    insertInbound: (input) => run('insertInbound', () => table.insertInbound(input)),
    insertAssistant: (input) => run('insertAssistant', () => table.insertAssistant(input)),
    transitionInbound: (user, id, change) =>
      run(`transitionInbound:${change.from}>${change.to}`, () =>
        table.transitionInbound(user, id, change),
      ),
    completeInbound: (user, id) => run('completeInbound', () => table.completeInbound(user, id)),
    failInbound: (user, id, code) => run('failInbound', () => table.failInbound(user, id, code)),
  }
}

interface Scenario {
  seed?(table: Table): void
  faults?: readonly Fault[]
  key?: string
  text?: string
  requestId?: string
  agent?: FlowAgent['reply']
  drafts?: FlowDraftLookup['findForTurn']
}

async function run(scenario: Scenario) {
  const table = new Table()
  scenario.seed?.(table)
  const waves = new Waves()
  const agentCalled: { atWave: number | null } = { atWave: null }
  const reply = vi.fn<FlowAgent['reply']>(async (input) => {
    agentCalled.atWave = waves.count
    return scenario.agent ? scenario.agent(input) : { text: replyText, metadata: {} }
  })
  const findForTurn = vi.fn<FlowDraftLookup['findForTurn']>((user, turn) =>
    waves.track('drafts.findForTurn', async () =>
      scenario.drafts ? scenario.drafts(user, turn) : null,
    ),
  )
  const outcome = await sendFlowMessage(
    {
      store: traced(table, waves, scenario.faults ?? []),
      agent: { reply },
      drafts: { findForTurn },
    },
    {
      userId: userA,
      text: scenario.text ?? patientText,
      idempotencyKey: scenario.key ?? 'parallel-key-0001',
      requestId: scenario.requestId ?? 'req-parallel-0001',
      now,
    },
  ).then(
    (value) => ({ value, error: null }),
    (error: unknown) => ({
      value: null,
      error: error as { status?: number; code?: string; message?: string },
    }),
  )
  return {
    ...outcome,
    table,
    waves,
    reply,
    findForTurn,
    wavesBeforeAgent: agentCalled.atWave,
    wavesAfterAgent: agentCalled.atWave === null ? null : waves.count - agentCalled.atWave,
  }
}

const key = 'parallel-key-0001'
const scopedId = scopedFlowProviderMessageId(userA, key)
const scopedReplyId = `${scopedId}/assistant`

const seedTurn =
  (state: StoredFlowMessage['state'], overrides: Partial<Row> = {}) =>
  (table: Table) =>
    table.seed({
      direction: 'in',
      providerMessageId: scopedId,
      content: patientText,
      state,
      ...overrides,
    })
const seedReply =
  (content = 'Resposta gravada') =>
  (table: Table) =>
    table.seed({ direction: 'out', providerMessageId: scopedReplyId, content })
const seedExecutions = (count: number) => (table: Table) => {
  for (let index = 0; index < count; index += 1) {
    table.seed({
      direction: 'in',
      providerMessageId: scopedFlowProviderMessageId(userA, `recent-key-${index}`),
      content: `mensagem ${index}`,
      createdAt: at(-20_000 - index),
    })
  }
}
const all =
  (...seeds: Array<(table: Table) => void>) =>
  (table: Table) => {
    for (const seed of seeds) seed(table)
  }
const failedAttempt: Partial<Row> = {
  createdAt: at(-5 * 60_000),
  attempt: { startedAt: at(-5 * 60_000), providerStartedAt: at(-5 * 60_000), retryStartedAt: [] },
  errorCode: 'flow_provider_failed',
}
const staleBeforeProvider: Partial<Row> = {
  createdAt: at(-LEASE_MS - 60_000),
  attempt: { startedAt: at(-LEASE_MS - 60_000), providerStartedAt: null, retryStartedAt: [] },
}

let info: MockInstance<typeof console.info>
let failureLog: MockInstance<typeof console.error>
beforeEach(() => {
  info = vi.spyOn(console, 'info').mockImplementation(() => {})
  failureLog = vi.spyOn(console, 'error').mockImplementation(() => {})
})
afterEach(() => {
  info.mockRestore()
  failureLog.mockRestore()
  vi.useRealTimers()
})

describe('(b) sequential waves of a Flow turn around the agent', () => {
  // Measured on the code before this change with the same recorder: 7 store
  // waves before the agent and 3 after (9 and 3 database round trips, since
  // each count was two queries in a row).
  it('a new turn costs 4 waves before the agent and 2 after', async () => {
    const turn = await run({})

    expect(turn.error).toBeNull()
    expect(turn.wavesBeforeAgent).toBe(4)
    expect(turn.wavesAfterAgent).toBe(2)
    expect(turn.waves.list()).toEqual([
      [
        'findInbound:scoped',
        'findInbound:legacy',
        'findAssistant:scoped',
        'countRecentExecutions#1',
      ],
      ['insertInbound'],
      ['countRecentExecutions#2'],
      ['transitionInbound:processing>processing'],
      ['insertAssistant'],
      ['completeInbound', 'drafts.findForTurn'],
    ])
  })

  it('a replay costs 2 waves (was 4) and never reaches the agent', async () => {
    const turn = await run({ seed: all(seedTurn('completed'), seedReply()) })

    expect(turn.value?.message.content).toBe('Resposta gravada')
    expect(turn.reply).not.toHaveBeenCalled()
    expect(turn.waves.list()).toEqual([
      [
        'findInbound:scoped',
        'findInbound:legacy',
        'findAssistant:scoped',
        'countRecentExecutions#1',
      ],
      ['completeInbound', 'drafts.findForTurn'],
    ])
  })

  it('a retry of a failed turn costs 4 waves before the agent (was 6) and 2 after', async () => {
    const turn = await run({ seed: seedTurn('failed', failedAttempt) })

    expect(turn.error).toBeNull()
    expect(turn.waves.list()).toEqual([
      [
        'findInbound:scoped',
        'findInbound:legacy',
        'findAssistant:scoped',
        'countRecentExecutions#1',
      ],
      ['transitionInbound:failed>processing'],
      ['countRecentExecutions#2'],
      ['transitionInbound:processing>processing'],
      ['insertAssistant'],
      ['completeInbound', 'drafts.findForTurn'],
    ])
  })

  it('the writes that guard the paid call keep their order: record, recount, mark, call, store, complete', async () => {
    const turn = await run({})
    const order = turn.waves.ops()
    const position = (op: string) => order.indexOf(op)

    expect(position('insertInbound')).toBeGreaterThan(position('countRecentExecutions#1'))
    expect(position('countRecentExecutions#2')).toBeGreaterThan(position('insertInbound'))
    expect(position('transitionInbound:processing>processing')).toBeGreaterThan(
      position('countRecentExecutions#2'),
    )
    expect(position('completeInbound')).toBeGreaterThan(position('insertAssistant'))
    // Each of them is alone in its wave, and the marker is the last before the agent.
    for (const wave of turn.waves.list().slice(1, 5)) expect(wave).toHaveLength(1)
    expect(turn.waves.list()[3]).toEqual(['transitionInbound:processing>processing'])
    expect(turn.wavesBeforeAgent).toBe(4)
  })

  it('through the Supabase adapter a new turn is 12 queries in 6 round trips (was 12 in 12)', async () => {
    const waves = new Waves()
    const queries: string[] = []
    const from = (table: string) => {
      const state = { op: 'select', single: false, direction: '' }
      const query: Record<string, unknown> = {}
      for (const name of ['select', 'gte', 'in', 'is', 'order', 'limit']) query[name] = () => query
      query.eq = (column: string, value: string) => {
        if (column === 'direction') state.direction = value
        return query
      }
      query.insert = () => {
        state.op = 'insert'
        return query
      }
      query.update = () => {
        state.op = 'update'
        return query
      }
      query.single = () => {
        state.single = true
        return query
      }
      query.maybeSingle = query.single
      // Like supabase-js, the request is only sent when the builder is awaited.
      // biome-ignore lint/suspicious/noThenProperty: models the PostgREST builder, which is a thenable
      query.then = (resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) => {
        const written = {
          id: 'row-1',
          direction: state.op === 'insert' ? 'out' : 'in',
          content: replyText,
          delivery_status: 'completed',
          raw_payload: { request_id: 'req-parallel-0001' },
          created_at: now.toISOString(),
        }
        const data =
          state.op === 'select' ? (state.single ? null : []) : state.single ? written : [written]
        const label = `${state.op}:${table}${state.direction ? `:${state.direction}` : ''}`
        queries.push(label)
        return waves
          .track(label, async () => ({ data, error: null, count: 0 }))
          .then(resolve, reject)
      }
      return query
    }
    const supabase = { from } as unknown as import('@mpp/db').ServiceClient
    let roundTripsAtAgent = -1

    const result = await sendFlowMessage(
      {
        store: createSupabaseFlowChatStore(supabase),
        drafts: createSupabaseFlowDraftLookup(supabase),
        agent: {
          async reply() {
            roundTripsAtAgent = waves.count
            return { text: replyText, metadata: {} }
          },
        },
      },
      {
        userId: userA,
        text: patientText,
        idempotencyKey: key,
        requestId: 'req-parallel-0001',
        now,
      },
    )

    expect(result.message.content).toBe(replyText)
    expect(queries).toHaveLength(12)
    expect(roundTripsAtAgent).toBe(4)
    expect(waves.count - roundTripsAtAgent).toBe(2)
    expect(waves.list().map((wave) => wave.length)).toEqual([5, 1, 2, 1, 1, 2])
    expect(waves.list()[0]?.slice().sort()).toEqual([
      'select:messages:in',
      'select:messages:in',
      'select:messages:in',
      'select:messages:in',
      'select:messages:out',
    ])
    expect(waves.list()[5]?.slice().sort()).toEqual(['select:plan_drafts', 'update:messages:in'])
  })
})

describe('(a) the parallel reads decide exactly what the sequential ones did', () => {
  const reads: readonly Fault[] = [
    'findInbound:scoped',
    'findInbound:legacy',
    'findAssistant:scoped',
    'countRecentExecutions#1',
  ]

  describe('a new turn', () => {
    it('runs once and stores the same two rows', async () => {
      const turn = await run({})

      expect(turn.value).toEqual({
        conversation_id: 'flow',
        message: expect.objectContaining({
          role: 'assistant',
          content: replyText,
          state: 'completed',
        }),
        draft: null,
      })
      expect(turn.reply).toHaveBeenCalledOnce()
      expect(turn.reply).toHaveBeenCalledWith({
        userId: userA,
        providerMessageId: scopedId,
        text: patientText,
        timestamp: now,
      })
      expect(turn.table.rows).toEqual([
        {
          userId: userA,
          direction: 'in',
          providerMessageId: scopedId,
          content: patientText,
          state: 'completed',
          requestId: 'req-parallel-0001',
          createdAt: now.toISOString(),
          attempt: {
            startedAt: now.toISOString(),
            providerStartedAt: now.toISOString(),
            retryStartedAt: [],
          },
          errorCode: null,
        },
        expect.objectContaining({
          direction: 'out',
          providerMessageId: scopedReplyId,
          content: replyText,
          state: 'completed',
          requestId: 'req-parallel-0001',
        }),
      ])
    })

    it.each(
      reads,
    )('an error in %s refuses the turn with that error: nothing stored, agent not called', async (fault) => {
      const turn = await run({ faults: [fault] })

      expect(turn.error?.message).toBe(`fault ${fault}`)
      expect(turn.table.rows).toEqual([])
      expect(turn.reply).not.toHaveBeenCalled()
      // Refused on the first wave: no write was attempted.
      expect(turn.waves.count).toBe(1)
    })

    it('at the per-minute limit it is refused with 429 before anything is stored', async () => {
      const turn = await run({ seed: seedExecutions(10) })

      expect(turn.error).toMatchObject({ status: 429, code: 'flow_rate_limited' })
      expect(turn.table.rows).toHaveLength(10)
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.waves.count).toBe(1)
    })

    it('one execution under the limit still runs', async () => {
      const turn = await run({ seed: seedExecutions(9) })

      expect(turn.error).toBeNull()
      expect(turn.reply).toHaveBeenCalledOnce()
    })

    it('an error in the recount after recording gives the turn back as failed (502)', async () => {
      const turn = await run({ faults: ['countRecentExecutions#2'] })

      expect(turn.error).toMatchObject({ status: 502, code: 'flow_provider_failed' })
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.table.inbound(scopedId)).toMatchObject({
        state: 'failed',
        errorCode: 'flow_provider_failed',
      })
    })
  })

  describe('a replay of a stored reply', () => {
    const seed = all(seedTurn('completed'), seedReply())

    it.each([
      ['the legacy lookup fails', ['findInbound:legacy']],
      ['the execution count fails', ['countRecentExecutions#1']],
      ['both fail', ['findInbound:legacy', 'countRecentExecutions#1']],
    ] as const)('is still served when %s: neither was read by the sequential code', async (_label, faults) => {
      const turn = await run({ seed, faults })

      expect(turn.value?.message.content).toBe('Resposta gravada')
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.table.rows.filter((row) => row.direction === 'out')).toHaveLength(1)
    })

    it('is still served at the per-minute limit, and is not counted', async () => {
      const turn = await run({ seed: all(seed, seedExecutions(12)) })

      expect(turn.value?.message.content).toBe('Resposta gravada')
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.table.rows).toHaveLength(14)
    })

    it.each([
      'findInbound:scoped',
      'findAssistant:scoped',
    ] as const)('fails with the error of %s', async (fault) => {
      const turn = await run({ seed, faults: [fault] })

      expect(turn.error?.message).toBe(`fault ${fault}`)
      expect(turn.reply).not.toHaveBeenCalled()
    })

    it('a completion that fails surfaces its error and no reply is returned', async () => {
      const turn = await run({
        seed: all(seedTurn('processing', staleBeforeProvider), seedReply()),
        faults: ['completeInbound'],
      })

      expect(turn.error?.message).toBe('fault completeInbound')
      expect(turn.value).toBeNull()
      expect(turn.table.inbound(scopedId)?.state).toBe('processing')
    })

    it('an empty stored reply is a 502, never a successful turn, whatever the other reads return', async () => {
      const turn = await run({
        seed: all(seedTurn('completed'), seedReply('   ')),
        faults: ['findInbound:legacy', 'countRecentExecutions#1'],
      })

      expect(turn.error).toMatchObject({ status: 502, code: 'flow_provider_failed' })
      expect(turn.reply).not.toHaveBeenCalled()
    })
  })

  describe('the same key with another text', () => {
    it.each([
      ['no read fails', []],
      [
        'the reply lookup, the legacy lookup and the count fail',
        ['findAssistant:scoped', 'findInbound:legacy', 'countRecentExecutions#1'],
      ],
    ] as const)('is a key conflict (409) when %s', async (_label, faults) => {
      const turn = await run({
        seed: all(seedTurn('completed'), seedReply(), seedExecutions(12)),
        faults,
        text: 'Outra pergunta',
      })

      expect(turn.error).toMatchObject({ status: 409, code: 'idempotency_key_conflict' })
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.waves.count).toBe(1)
    })
  })

  describe('a turn still in progress', () => {
    const seed = seedTurn('processing', {
      createdAt: at(-60_000),
      attempt: { startedAt: at(-60_000), providerStartedAt: at(-60_000), retryStartedAt: [] },
    })

    it.each([
      ['no read fails', [], 0],
      [
        'the legacy lookup and the count fail',
        ['findInbound:legacy', 'countRecentExecutions#1'],
        0,
      ],
      ['the patient is at the per-minute limit', [], 12],
    ] as const)('answers the same 409 when %s', async (_label, faults, executions) => {
      const turn = await run({ seed: all(seed, seedExecutions(executions)), faults })

      expect(turn.error).toMatchObject({
        status: 409,
        code: 'idempotency_request_in_progress',
        message: 'The same request is already being processed',
      })
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.table.inbound(scopedId)).toMatchObject({
        state: 'processing',
        requestId: 'req-seeded-0001',
      })
      expect(turn.waves.count).toBe(1)
    })

    it('an error in the reply lookup wins, as it was read before the lease', async () => {
      const turn = await run({ seed, faults: ['findAssistant:scoped'] })

      expect(turn.error?.message).toBe('fault findAssistant:scoped')
      expect(turn.table.inbound(scopedId)?.state).toBe('processing')
    })
  })

  describe('a retry of a failed turn', () => {
    const seed = seedTurn('failed', failedAttempt)

    it('runs as one counted execution', async () => {
      const turn = await run({ seed })

      expect(turn.value?.message.content).toBe(replyText)
      expect(turn.reply).toHaveBeenCalledOnce()
      expect(turn.table.inbound(scopedId)).toMatchObject({
        state: 'completed',
        requestId: 'req-parallel-0001',
        attempt: {
          startedAt: now.toISOString(),
          providerStartedAt: now.toISOString(),
          retryStartedAt: [now.toISOString()],
        },
      })
    })

    it('at the limit is refused with 429 and the turn is left as it was', async () => {
      const turn = await run({ seed: all(seed, seedExecutions(10)) })

      expect(turn.error).toMatchObject({ status: 429, code: 'flow_rate_limited' })
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.table.inbound(scopedId)).toMatchObject({
        state: 'failed',
        requestId: 'req-seeded-0001',
        ...failedAttempt,
      })
    })

    it('an error in the execution count refuses it and the turn is left as it was', async () => {
      const turn = await run({ seed, faults: ['countRecentExecutions#1'] })

      expect(turn.error?.message).toBe('fault countRecentExecutions#1')
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.table.inbound(scopedId)).toMatchObject({
        state: 'failed',
        requestId: 'req-seeded-0001',
        ...failedAttempt,
      })
      expect(turn.waves.count).toBe(1)
    })
  })

  describe('a turn whose invocation died before the provider', () => {
    const seed = seedTurn('processing', staleBeforeProvider)

    it('continues once', async () => {
      const turn = await run({ seed })

      expect(turn.value?.message.content).toBe(replyText)
      expect(turn.reply).toHaveBeenCalledOnce()
      expect(turn.waves.ops().slice(4, 6)).toEqual([
        'transitionInbound:processing>failed',
        'transitionInbound:failed>processing',
      ])
    })

    it.each([
      [
        'an error in the execution count',
        ['countRecentExecutions#1'],
        0,
        { message: 'fault countRecentExecutions#1' },
      ],
      ['the per-minute limit', [], 10, { status: 429, code: 'flow_rate_limited' }],
    ] as const)('%s refuses it after the dead attempt was closed, as before', async (_label, faults, executions, error) => {
      const turn = await run({ seed: all(seed, seedExecutions(executions)), faults })

      expect(turn.error).toMatchObject(error)
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.table.inbound(scopedId)).toMatchObject({
        state: 'failed',
        errorCode: 'flow_turn_interrupted',
      })
    })
  })

  describe('legacy (pre-scoping) rows', () => {
    const seedLegacyTurn = (state: StoredFlowMessage['state']) => (table: Table) =>
      table.seed({ direction: 'in', providerMessageId: key, content: patientText, state })
    const seedLegacyReply = (table: Table) =>
      table.seed({
        direction: 'out',
        providerMessageId: `${key}:assistant`,
        content: 'Resposta antiga',
      })

    it('a legacy turn replays its legacy reply, read on its own after the first wave', async () => {
      const turn = await run({ seed: all(seedLegacyTurn('completed'), seedLegacyReply) })

      expect(turn.value?.message.content).toBe('Resposta antiga')
      expect(turn.reply).not.toHaveBeenCalled()
      expect(turn.waves.list()).toEqual([
        [
          'findInbound:scoped',
          'findInbound:legacy',
          'findAssistant:scoped',
          'countRecentExecutions#1',
        ],
        ['findAssistant:legacy'],
        ['completeInbound', 'drafts.findForTurn'],
      ])
      expect(turn.findForTurn).toHaveBeenCalledWith(userA, key)
    })

    it('an error in the legacy reply lookup of a legacy turn fails it', async () => {
      const turn = await run({
        seed: all(seedLegacyTurn('completed'), seedLegacyReply),
        faults: ['findAssistant:legacy'],
      })

      expect(turn.error?.message).toBe('fault findAssistant:legacy')
      expect(turn.reply).not.toHaveBeenCalled()
    })

    it('a failed legacy turn runs again and stores its reply under the scoped id', async () => {
      const turn = await run({ seed: seedLegacyTurn('failed') })

      expect(turn.value?.message.content).toBe(replyText)
      expect(turn.reply).toHaveBeenCalledWith(expect.objectContaining({ providerMessageId: key }))
      expect(turn.table.rows.find((row) => row.direction === 'out')?.providerMessageId).toBe(
        scopedReplyId,
      )
      expect(turn.table.inbound(key)?.state).toBe('completed')
    })

    it.each([
      ['a new turn', undefined],
      ['a failed scoped turn', seedTurn('failed', failedAttempt)],
    ] as const)('%s never reads a "<key>:assistant" row: the legacy reply is only for legacy turns', async (_label, seed) => {
      const turn = await run({ seed: all(seedLegacyReply, ...(seed ? [seed] : [])) })

      expect(turn.waves.ops()).not.toContain('findAssistant:legacy')
      expect(turn.value?.message.content).toBe(replyText)
      expect(turn.reply).toHaveBeenCalledOnce()
    })

    it('a scoped turn wins over a legacy row of the same key, whose lookup result is not used', async () => {
      const turn = await run({
        seed: all(seedTurn('completed'), seedReply(), (table) =>
          table.seed({
            direction: 'in',
            providerMessageId: key,
            content: 'Texto antigo diferente',
            state: 'failed',
          }),
        ),
      })

      expect(turn.value?.message.content).toBe('Resposta gravada')
      expect(turn.findForTurn).toHaveBeenCalledWith(userA, scopedId)
      expect(turn.table.inbound(key)?.state).toBe('failed')
    })
  })

  describe('when several reads of the first wave fail at once', () => {
    it.each([
      [reads, 'findInbound:scoped'],
      [
        ['findInbound:legacy', 'findAssistant:scoped', 'countRecentExecutions#1'],
        'findInbound:legacy',
      ],
      [['findAssistant:scoped', 'countRecentExecutions#1'], 'findAssistant:scoped'],
    ] as const)('%j surfaces the one the sequential code would have hit first: %s', async (faults, first) => {
      const turn = await run({ faults })

      expect(turn.error?.message).toBe(`fault ${first}`)
      expect(turn.table.rows).toEqual([])
      expect(turn.reply).not.toHaveBeenCalled()
    })

    it('a failed reply lookup wins over the per-minute limit', async () => {
      const turn = await run({ seed: seedExecutions(10), faults: ['findAssistant:scoped'] })

      expect(turn.error?.message).toBe('fault findAssistant:scoped')
    })
  })

  describe('after the agent', () => {
    it('a completion that fails is a 502 with the turn failed, even though the proposal was found', async () => {
      const turn = await run({
        faults: ['completeInbound'],
        drafts: async () => ({ id: 'draft-1', domain: 'training' }),
      })

      expect(turn.error).toMatchObject({ status: 502, code: 'flow_provider_failed' })
      expect(turn.value).toBeNull()
      expect(turn.table.inbound(scopedId)).toMatchObject({
        state: 'failed',
        errorCode: 'flow_provider_failed',
      })
      expect(turn.table.rows.filter((row) => row.direction === 'out')).toHaveLength(1)
    })

    it('carries the proposal found in the same wave as the completion', async () => {
      const turn = await run({ drafts: async () => ({ id: 'draft-1', domain: 'nutrition' }) })

      expect(turn.value?.draft).toEqual({ id: 'draft-1', domain: 'nutrition' })
      expect(turn.findForTurn).toHaveBeenCalledOnce()
      expect(turn.findForTurn).toHaveBeenCalledWith(userA, scopedId)
      expect(turn.table.inbound(scopedId)?.state).toBe('completed')
    })

    it.each([
      ['rejects', async () => Promise.reject(new Error('database down'))],
      [
        'throws',
        () => {
          throw new Error('database down')
        },
      ],
    ] as const)('a proposal lookup that %s only leaves the reply without the shortcut', async (_label, drafts) => {
      const turn = await run({ drafts })

      expect(turn.value?.draft).toBeNull()
      expect(turn.value?.message.content).toBe(replyText)
      expect(turn.table.inbound(scopedId)?.state).toBe('completed')
    })

    it('a reply already stored for this turn is replayed with its proposal', async () => {
      const turn = await run({
        drafts: async () => ({ id: 'draft-1', domain: 'training' }),
        // A reply row for this very turn lands between the replay check and the insert.
        seed: (table) => {
          const insert = table.insertAssistant
          table.insertAssistant = async (input) => {
            await insert({ ...input, content: 'Resposta gravada antes' })
            return insert(input)
          }
        },
      })

      expect(turn.value?.message.content).toBe('Resposta gravada antes')
      expect(turn.value?.draft).toEqual({ id: 'draft-1', domain: 'training' })
      expect(turn.table.inbound(scopedId)?.state).toBe('completed')
    })
  })

  it('a read that throws instead of rejecting is still an error of that read, not a crash of the wave', async () => {
    const table = new Table()
    const store: FlowChatStore = {
      ...table,
      findInbound: (user, id) => {
        if (!id.startsWith('mobile_flow/')) throw new Error('legacy lookup threw')
        return table.findInbound(user, id)
      },
    }
    const agent = { reply: vi.fn(async () => ({ text: replyText, metadata: {} })) }
    const unhandled = vi.fn()
    process.on('unhandledRejection', unhandled)
    try {
      await expect(
        sendFlowMessage(
          { store, agent },
          {
            userId: userA,
            text: patientText,
            idempotencyKey: key,
            requestId: 'req-parallel-0001',
            now,
          },
        ),
      ).rejects.toThrow('legacy lookup threw')
      await new Promise((resolve) => setTimeout(resolve, 5))
    } finally {
      process.off('unhandledRejection', unhandled)
    }
    expect(agent.reply).not.toHaveBeenCalled()
    expect(unhandled).not.toHaveBeenCalled()
  })

  it('a read whose result is ignored never becomes an unhandled rejection', async () => {
    const unhandled = vi.fn()
    process.on('unhandledRejection', unhandled)
    try {
      const turn = await run({
        seed: all(seedTurn('completed'), seedReply()),
        faults: ['findInbound:legacy', 'countRecentExecutions#1'],
        text: 'Outra pergunta',
      })
      expect(turn.error).toMatchObject({ code: 'idempotency_key_conflict' })
      await new Promise((resolve) => setTimeout(resolve, 5))
    } finally {
      process.off('unhandledRejection', unhandled)
    }
    expect(unhandled).not.toHaveBeenCalled()
  })
})

describe('review of the parallel reads: a reply landing between the two reads', () => {
  // Found by the adversarial review of 2026-10-04. The reply is stored before
  // the turn is completed. With the turn and the reply read in the same wave,
  // a second request with the same key can see "no reply" (read before the
  // other request's insert) and "completed" (read after its completion). The
  // sequential code read the turn first, so a completed turn always had its
  // reply. Without the second look the agent ran — and was charged — twice.
  function crossRead() {
    const table = new Table()
    table.seed({
      direction: 'in',
      providerMessageId: scopedId,
      content: patientText,
      state: 'completed',
    })
    table.seed({ direction: 'out', providerMessageId: scopedReplyId, content: replyText })
    let replyReads = 0
    const store: FlowChatStore = {
      loadHistory: table.loadHistory,
      findInbound: table.findInbound,
      // The first read of the reply happens before the other request stored it.
      findAssistant: async (user, id) => {
        replyReads += 1
        return replyReads === 1 ? null : table.findAssistant(user, id)
      },
      countRecentExecutions: table.countRecentExecutions,
      insertInbound: table.insertInbound,
      insertAssistant: table.insertAssistant,
      transitionInbound: table.transitionInbound,
      completeInbound: table.completeInbound,
      failInbound: table.failInbound,
    }
    return { table, store, reads: () => replyReads }
  }

  it('a completed turn whose reply was not visible in the first wave is replayed, never executed again', async () => {
    const { table, store, reads } = crossRead()
    const reply = vi.fn<FlowAgent['reply']>(async () => ({
      text: 'second execution',
      metadata: {},
    }))
    const result = await sendFlowMessage(
      { store, agent: { reply }, drafts: { findForTurn: async () => null } },
      {
        userId: userA,
        text: patientText,
        idempotencyKey: key,
        requestId: 'req-parallel-0002',
        now,
      },
    )
    expect(reply).not.toHaveBeenCalled()
    expect(JSON.stringify(result)).toContain(replyText)
    expect(JSON.stringify(result)).not.toContain('second execution')
    expect(reads()).toBe(2)
    // The turn was not re-opened and nothing new was written.
    expect(table.inbound(scopedId)?.state).toBe('completed')
    expect(table.rows).toHaveLength(2)
  })

  it('a completed turn that really has no reply still runs again as a counted execution', async () => {
    const table = new Table()
    table.seed({
      direction: 'in',
      providerMessageId: scopedId,
      content: patientText,
      state: 'completed',
    })
    const reply = vi.fn<FlowAgent['reply']>(async () => ({ text: replyText, metadata: {} }))
    const result = await sendFlowMessage(
      { store: table, agent: { reply }, drafts: { findForTurn: async () => null } },
      {
        userId: userA,
        text: patientText,
        idempotencyKey: key,
        requestId: 'req-parallel-0003',
        now,
      },
    )
    expect(reply).toHaveBeenCalledTimes(1)
    expect(JSON.stringify(result)).toContain(replyText)
    expect(table.rows.filter((row) => row.direction === 'out')).toHaveLength(1)
  })

  it('an agent reply without a metadata object still completes the turn', async () => {
    const table = new Table()
    const reply = vi.fn(
      async () => ({ text: replyText }) as unknown as Awaited<ReturnType<FlowAgent['reply']>>,
    )
    const result = await sendFlowMessage(
      { store: table, agent: { reply }, drafts: { findForTurn: async () => null } },
      {
        userId: userA,
        text: patientText,
        idempotencyKey: key,
        requestId: 'req-parallel-0004',
        now,
      },
    )
    expect(JSON.stringify(result)).toContain(replyText)
    expect(table.inbound(scopedId)?.state).toBe('completed')
    expect(table.rows.filter((row) => row.direction === 'out')).toHaveLength(1)
  })
})

describe('the Supabase adapter counts executions with two reads in one round trip', () => {
  function client(results: {
    count: { count: number | null; error: unknown }
    retries: { data: unknown[] | null; error: unknown }
  }) {
    const waves = new Waves()
    const from = () => {
      let head = false
      const query: Record<string, unknown> = {}
      query.select = (_columns: string, options?: { head?: boolean }) => {
        head = options?.head === true
        return query
      }
      for (const name of ['eq', 'gte', 'limit']) query[name] = () => query
      // biome-ignore lint/suspicious/noThenProperty: models the PostgREST builder, which is a thenable
      query.then = (resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) =>
        waves
          .track(head ? 'count' : 'retries', async () => (head ? results.count : results.retries))
          .then(resolve, reject)
      return query
    }
    return { waves, supabase: { from } as unknown as import('@mpp/db').ServiceClient }
  }
  const since = at(-60_000)

  it('adds first attempts and retries, read together', async () => {
    const { waves, supabase } = client({
      count: { count: 3, error: null },
      retries: {
        data: [{ raw_payload: { retry_started_at: [at(-120_000), at(-5_000), at(0)] } }],
        error: null,
      },
    })

    expect(await createSupabaseFlowChatStore(supabase).countRecentExecutions(userA, since)).toBe(5)
    expect(waves.list()).toEqual([['count', 'retries']])
  })

  it.each([
    [
      'the count query fails',
      { count: { count: null, error: { message: 'timeout' } }, retries: { data: [], error: null } },
    ],
    [
      'the retries query fails',
      { count: { count: 3, error: null }, retries: { data: null, error: { message: 'timeout' } } },
    ],
    [
      'both fail',
      {
        count: { count: null, error: { message: 'a' } },
        retries: { data: null, error: { message: 'b' } },
      },
    ],
    [
      'the count does not come back',
      { count: { count: null, error: null }, retries: { data: [], error: null } },
    ],
  ])('fails closed when %s', async (_label, results) => {
    const { supabase } = client(results)

    await expect(
      createSupabaseFlowChatStore(supabase).countRecentExecutions(userA, since),
    ).rejects.toThrow('Unable to enforce Flow rate limit')
  })
})

describe('(c) the turn timing line', () => {
  const timingKeys = [
    'agent_ms',
    'outcome',
    'pipeline_ms',
    'post_agent_ms',
    'pre_agent_ms',
    'request_id',
    'total_ms',
  ]
  const outcomes = [
    'completed',
    'replayed',
    'idempotency_key_conflict',
    'idempotency_request_in_progress',
    'flow_rate_limited',
    'flow_provider_failed',
    'unexpected_error',
  ]

  /** Runs a turn on a fake clock: every store call takes TRIP_MS, the agent `agentMs`. */
  async function timed(
    scenario: Scenario & { agentMs?: number; agentFails?: boolean; latencyMs?: unknown },
  ) {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date', 'performance'] })
    const pending = run({
      ...scenario,
      agent: async () => {
        await new Promise((resolve) => setTimeout(resolve, scenario.agentMs ?? 1_000))
        if (scenario.agentFails) throw new Error(`provider said: ${patientText}`)
        return {
          text: replyText,
          metadata: { latencyMs: scenario.latencyMs, modelUsed: 'anthropic/claude-sonnet-4.6' },
        }
      },
    })
    await vi.runAllTimersAsync()
    const turn = await pending
    const lines = info.mock.calls.filter((call) => call[0] === '[mobile-flow] turn_timing')
    expect(lines).toHaveLength(1)
    const fields = lines[0]?.[1] as Record<string, unknown>
    return { turn, fields, logged: JSON.stringify([...info.mock.calls, ...failureLog.mock.calls]) }
  }

  function expectSafe(fields: Record<string, unknown>, logged: string) {
    expect(Object.keys(fields).sort()).toEqual(timingKeys)
    for (const name of ['pre_agent_ms', 'total_ms'])
      expect(Number.isInteger(fields[name])).toBe(true)
    for (const name of ['agent_ms', 'post_agent_ms', 'pipeline_ms']) {
      expect(fields[name] === null || Number.isInteger(fields[name])).toBe(true)
    }
    // The only non-numeric values: a fixed outcome code and the request id.
    expect(outcomes).toContain(fields.outcome)
    expect(
      fields.request_id === null || /^[A-Za-z0-9._:-]{8,128}$/.test(String(fields.request_id)),
    ).toBe(true)
    for (const text of [patientText, 'arroz', replyText, 'Registrado', userA, key, 'claude']) {
      expect(logged).not.toContain(text)
    }
  }

  it('a completed turn reports each phase in whole milliseconds, adding up to the total', async () => {
    const { turn, fields, logged } = await timed({ latencyMs: 987.4 })

    expect(turn.error).toBeNull()
    expect(fields).toEqual({
      request_id: 'req-parallel-0001',
      outcome: 'completed',
      // Four waves before the agent and two after, at TRIP_MS each.
      pre_agent_ms: 4 * TRIP_MS,
      agent_ms: 1_000,
      post_agent_ms: 2 * TRIP_MS,
      total_ms: 6 * TRIP_MS + 1_000,
      pipeline_ms: 987,
    })
    expectSafe(fields, logged)
  })

  it('a failed provider call still reports the agent time and the time spent failing the turn', async () => {
    const { turn, fields, logged } = await timed({ agentFails: true, agentMs: 500 })

    expect(turn.error).toMatchObject({ code: 'flow_provider_failed' })
    expect(fields).toEqual({
      request_id: 'req-parallel-0001',
      outcome: 'flow_provider_failed',
      pre_agent_ms: 4 * TRIP_MS,
      agent_ms: 500,
      post_agent_ms: TRIP_MS,
      total_ms: 5 * TRIP_MS + 500,
      pipeline_ms: null,
    })
    expectSafe(fields, logged)
  })

  it.each([
    ['a replay', { seed: all(seedTurn('completed'), seedReply()) }, 'replayed', 2 * TRIP_MS],
    ['a turn at the limit', { seed: seedExecutions(10) }, 'flow_rate_limited', TRIP_MS],
    [
      'a key conflict',
      { seed: seedTurn('completed'), text: 'Outra pergunta com frango' },
      'idempotency_key_conflict',
      TRIP_MS,
    ],
    [
      'a turn in progress',
      {
        seed: seedTurn('processing', {
          createdAt: at(-60_000),
          attempt: { startedAt: at(-60_000), providerStartedAt: null, retryStartedAt: [] },
        }),
      },
      'idempotency_request_in_progress',
      TRIP_MS,
    ],
    ['a storage error', { faults: ['findInbound:scoped'] }, 'unexpected_error', TRIP_MS],
  ] as const)('%s reports its outcome and total, with no agent phases', async (_label, scenario, outcome, total) => {
    const { fields, logged } = await timed(scenario)

    expect(fields).toEqual({
      request_id: 'req-parallel-0001',
      outcome,
      pre_agent_ms: total,
      agent_ms: null,
      post_agent_ms: null,
      total_ms: total,
      pipeline_ms: null,
    })
    expectSafe(fields, logged)
  })

  it('an unexpected error is logged by a fixed code, never by its message', async () => {
    const table = new Table()
    const store: FlowChatStore = {
      ...table,
      findInbound: async () => {
        throw new Error(`could not parse "${patientText}"`)
      },
    }

    await expect(
      sendFlowMessage(
        { store, agent: { reply: vi.fn() } },
        {
          userId: userA,
          text: patientText,
          idempotencyKey: key,
          requestId: 'req-parallel-0001',
          now,
        },
      ),
    ).rejects.toThrow('could not parse')

    expect(info).toHaveBeenCalledOnce()
    expect(info).toHaveBeenCalledWith(
      '[mobile-flow] turn_timing',
      expect.objectContaining({ outcome: 'unexpected_error' }),
    )
    expect(JSON.stringify(info.mock.calls)).not.toContain('arroz')
  })

  it('a request id that is not identifier-shaped is not logged', async () => {
    const { fields, logged } = await timed({ requestId: patientText })

    expect(fields.request_id).toBeNull()
    expect(fields.outcome).toBe('completed')
    expectSafe(fields, logged)
  })

  it.each([
    ['a string', '987'],
    ['negative', -5],
    ['not finite', Number.POSITIVE_INFINITY],
    ['absent', undefined],
  ])('a pipeline latency that is %s is reported as null, never copied', async (_label, latencyMs) => {
    const { fields } = await timed({ latencyMs })

    expect(fields.pipeline_ms).toBeNull()
  })

  it('fractional clock readings still give integers that add up', async () => {
    const clock = vi.spyOn(performance, 'now')
    for (const reading of [100.4, 141.1, 1141.3, 1160.6]) clock.mockReturnValueOnce(reading)
    try {
      const turn = await run({})
      expect(turn.error).toBeNull()
    } finally {
      clock.mockRestore()
    }

    const fields = info.mock.calls[0]?.[1] as Record<string, number>
    expect(fields).toMatchObject({
      pre_agent_ms: 41,
      agent_ms: 1_000,
      post_agent_ms: 19,
      total_ms: 1_060,
    })
    expect(fields.pre_agent_ms + fields.agent_ms + fields.post_agent_ms).toBe(fields.total_ms)
  })

  it('a logger that throws never changes the outcome of the turn', async () => {
    info.mockImplementation(() => {
      throw new Error('logger down')
    })

    const turn = await run({})

    expect(turn.error).toBeNull()
    expect(turn.value?.message.content).toBe(replyText)
    expect(turn.table.inbound(scopedId)?.state).toBe('completed')
  })
})
