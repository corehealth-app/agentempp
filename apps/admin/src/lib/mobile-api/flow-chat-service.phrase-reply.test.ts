import { prepareFlowStatusPhraseReply } from '@mpp/agent/flow-curated-phrases'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ZodError } from 'zod'
import {
  type FlowChatStore,
  type FlowInboundTransition,
  loadFlowHistory,
  type StoredFlowMessage,
  sendFlowMessage,
} from './flow-chat-service'
import type {
  FlowPhraseCursorSnapshot,
  FlowPhraseEventIdentity,
  FlowPhraseEventReply,
  FlowPhraseReplyCommit,
  FlowPhraseReplyStore,
} from './flow-phrase-reply-store'

const owner = '00000000-0000-0000-0000-00000000c501'
const now = new Date('2026-10-09T00:00:00.000Z')
const input = {
  userId: owner,
  text: 'Status do dia',
  idempotencyKey: 'c5-event-0001',
  requestId: 'request-original',
  now,
}
const eventKey = `mobile_flow/${owner}/${input.idempotencyKey}`
const metadata = {
  stage: 'recomposicao',
  modelUsed: 'none' as const,
  promptTokens: 0 as const,
  completionTokens: 0 as const,
  costUsd: 0 as const,
  latencyMs: 17,
}
const tag = {
  kind: 'incentive' as const,
  slot: 'any' as const,
  locale: 'pt-BR',
  accountName: 'Pessoa sintética',
  authority: {
    currentProtocol: 'recomposicao' as const,
    dailyTargets: { calories_target: 2400, protein_target: 150 },
  },
}
type Reply = { text: string; metadata: typeof metadata; flowStatusPhrase?: typeof tag }
type Row = StoredFlowMessage & { userId: string; providerId: string }
type Insert = Parameters<FlowChatStore['insertInbound']>[0]

/** Service boundary fixture only; real PG gates prove locks and durability. */
class Table implements FlowChatStore {
  readonly rows: Row[] = []
  sequence = 0
  row(userId = owner, providerId = eventKey) {
    const row = this.rows.find(
      (candidate) =>
        candidate.userId === userId &&
        candidate.providerId === providerId &&
        candidate.role === 'user',
    )
    if (!row) throw new Error('Synthetic input absent')
    return row
  }
  add(input: Insert, role: 'user' | 'assistant') {
    const row: Row = {
      id: `00000000-0000-0000-0000-${(++this.sequence).toString(16).padStart(12, '0')}`,
      userId: input.userId,
      providerId: input.providerMessageId,
      role,
      content: input.content,
      state: input.state,
      requestId: input.requestId,
      createdAt: input.createdAt,
      ...(role === 'user' ? { attempt: input.attempt ?? null } : {}),
    }
    this.rows.push(row)
    return row
  }
  loadHistory = async (userId: string) => this.rows.filter((row) => row.userId === userId)
  countRecentExecutions = async () => this.rows.filter((row) => row.role === 'user').length
  findInbound = async (userId: string, providerId: string) =>
    this.rows.find(
      (row) => row.userId === userId && row.providerId === providerId && row.role === 'user',
    ) ?? null
  findAssistant = async (userId: string, providerId: string) =>
    this.rows.find(
      (row) => row.userId === userId && row.providerId === providerId && row.role === 'assistant',
    ) ?? null
  insertInbound = async (value: Insert) => this.add(value, 'user')
  insertAssistant = vi.fn(async (value: Insert) => this.add(value, 'assistant'))
  completeInbound = vi.fn(async (userId: string, providerId: string) => {
    this.row(userId, providerId).state = 'completed'
  })
  failInbound = vi.fn(async (userId: string, providerId: string) => {
    this.row(userId, providerId).state = 'failed'
  })
  transitionInbound = async (userId: string, providerId: string, change: FlowInboundTransition) => {
    const row = this.row(userId, providerId)
    if (
      row.state !== change.from ||
      (row.attempt?.startedAt ?? null) !== change.expectedAttemptStartedAt ||
      (change.expectedRequestId !== undefined && row.requestId !== change.expectedRequestId) ||
      ('expectedInboundId' in change && row.id !== change.expectedInboundId)
    )
      return false
    row.state = change.to
    row.requestId = change.requestId
    row.attempt = change.attempt
    return true
  }
}

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: Error) => void
  const promise = new Promise<T>((yes, no) => {
    resolve = yes
    reject = no
  })
  return { promise, resolve, reject }
}

function fixture() {
  const store = new Table()
  const events = new Map<string, FlowPhraseEventReply>()
  const snapshots = new Map<string, FlowPhraseCursorSnapshot>()
  const snapshotFor = (userId: string): FlowPhraseCursorSnapshot =>
    structuredClone(
      snapshots.get(userId) ?? { anchorAssistantId: null, cursorRevision: '0', cursor: null },
    )
  const publish = (value: FlowPhraseReplyCommit) => {
    const row = store.row(value.userId, value.inboundProviderMessageId)
    if (row.id !== value.inboundId || row.content !== value.expectedInboundContent)
      return { action: 'event_conflict' as const }
    const prior = events.get(value.eventKey)
    if (prior) return { action: 'replay' as const, message: prior.message }
    if (
      row.state !== 'processing' ||
      row.requestId !== value.expectedRequestId ||
      row.attempt?.startedAt !== value.expectedAttemptStartedAt
    )
      return { action: 'attempt_conflict' as const }
    const current = snapshotFor(value.userId)
    if (
      current.anchorAssistantId !== value.expectedAnchorAssistantId ||
      current.cursorRevision !== value.expectedCursorRevision ||
      JSON.stringify(current.cursor) !== JSON.stringify(value.expectedCursor)
    )
      return { action: 'cursor_conflict' as const }
    const message = store.add(
      {
        userId: value.userId,
        content: value.content,
        providerMessageId: value.assistantProviderMessageId,
        requestId: value.expectedRequestId,
        state: 'completed',
        createdAt: value.createdAt,
      },
      'assistant',
    )
    row.state = 'completed'
    events.set(value.eventKey, { kind: 'c5', message, receipt: value.receipt })
    snapshots.set(value.userId, {
      anchorAssistantId: message.id,
      cursorRevision: (BigInt(current.cursorRevision) + 1n).toString(),
      cursor: value.nextCursor,
    })
    return { action: 'committed' as const, message }
  }
  const loadEventReply = vi.fn(async (value: FlowPhraseEventIdentity) => {
    const row = store.row(value.userId, value.inboundProviderMessageId)
    if (row.id !== value.inboundId || row.content !== value.expectedInboundContent)
      throw new Error('Synthetic event identity changed')
    return events.get(value.eventKey) ?? null
  })
  const loadCursor = vi.fn(async (userId: string) => snapshotFor(userId))
  const commitReply = vi.fn<FlowPhraseReplyStore['commitReply']>(async (value) => publish(value))
  const failOwnedAttempt = vi.fn<FlowPhraseReplyStore['failOwnedAttempt']>(async (value) => {
    const row = store.row(value.userId, value.inboundProviderMessageId)
    if (
      row.id !== value.inboundId ||
      row.state !== 'processing' ||
      row.requestId !== value.expectedRequestId ||
      row.attempt?.startedAt !== value.expectedAttemptStartedAt
    )
      return false
    row.state = 'failed'
    return true
  })
  const reply = vi.fn(
    async (): Promise<Reply> => ({
      text: 'Status oficial de hoje.',
      metadata,
      flowStatusPhrase: tag,
    }),
  )
  const phraseReplies = { loadEventReply, loadCursor, commitReply, failOwnedAttempt }
  return {
    store,
    events,
    publish,
    snapshotFor,
    reply,
    phraseReplies,
    deps: { store, phraseReplies, agent: { reply } },
  }
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(now)
  vi.spyOn(console, 'info').mockImplementation(() => {})
  vi.spyOn(console, 'error').mockImplementation(() => {})
})
afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

describe('Flow service: durable status publication', () => {
  it('publishes the tagged status through one atomic commit using the inserted real inbound UUID', async () => {
    const f = fixture()
    const result = await sendFlowMessage(f.deps, input)
    expect(result.message.content).toBe(
      'Status oficial de hoje.\n\nConsistência vale mais do que perfeição.',
    )
    expect(result.message.id).toBe('00000000-0000-0000-0000-000000000002')
    expect(f.phraseReplies.commitReply).toHaveBeenCalledTimes(1)
    expect(f.phraseReplies.commitReply.mock.calls[0][0]).toMatchObject({
      userId: owner,
      eventKey,
      inboundId: '00000000-0000-0000-0000-000000000001',
      inboundProviderMessageId: eventKey,
      assistantProviderMessageId: `${eventKey}/assistant`,
      expectedInboundContent: input.text,
      expectedRequestId: input.requestId,
      expectedAttemptStartedAt: now.toISOString(),
      expectedCursorRevision: '0',
      expectedCursor: null,
      nextCursor: { ordinal: 1 },
      metadata,
    })
    expect(f.store.insertAssistant).not.toHaveBeenCalled()
    expect(f.store.completeInbound).not.toHaveBeenCalled()
    expect(f.store.failInbound).not.toHaveBeenCalled()
    expect(f.store.row().state).toBe('completed')
    expect(Object.keys(result.message).sort()).toEqual([
      'content',
      'conversation_id',
      'created_at',
      'id',
      'request_id',
      'role',
      'state',
    ])
  })

  it('replays a completed event before cursor selection and without another completion write', async () => {
    const f = fixture()
    const first = await sendFlowMessage(f.deps, input)
    f.reply.mockClear()
    f.phraseReplies.loadCursor
      .mockClear()
      .mockRejectedValue(new Error('Cursor must not be read on replay'))
    f.phraseReplies.commitReply.mockClear()
    const repeated = await sendFlowMessage(f.deps, { ...input, requestId: 'new-replay-request' })
    expect(repeated).toEqual(first)
    expect(f.reply).not.toHaveBeenCalled()
    expect(f.phraseReplies.loadCursor).not.toHaveBeenCalled()
    expect(f.phraseReplies.commitReply).not.toHaveBeenCalled()
    expect(f.store.completeInbound).not.toHaveBeenCalled()
  })

  it('recovers the official reply after its atomic commit succeeds but transport rejects', async () => {
    const f = fixture()
    f.phraseReplies.commitReply.mockImplementationOnce(async (value) => {
      f.publish(value)
      throw new Error('Synthetic lost commit transport')
    })
    const result = await sendFlowMessage(f.deps, input)
    expect(result.message.content).toBe(
      'Status oficial de hoje.\n\nConsistência vale mais do que perfeição.',
    )
    expect(f.phraseReplies.commitReply).toHaveBeenCalledTimes(1)
    expect(f.phraseReplies.failOwnedAttempt).not.toHaveBeenCalled()
    expect(f.store.row().state).toBe('completed')
    expect(f.store.rows.filter((row) => row.role === 'assistant')).toHaveLength(1)
  })

  it('does not let a late rejection before the tag demote a newer completed attempt', async () => {
    const f = fixture()
    const started = deferred<void>()
    const work = deferred<Reply>()
    f.reply.mockImplementationOnce(() => {
      started.resolve()
      return work.promise
    })
    const pending = sendFlowMessage(f.deps, input).catch((error: unknown) => error)
    await started.promise
    const row = f.store.row()
    row.state = 'completed'
    row.requestId = 'newer-completed-request'
    const saved = structuredClone(f.store.rows)
    work.reject(new Error('Synthetic late Today rejection'))
    await pending
    expect(f.store.rows).toEqual(saved)
    expect(f.store.failInbound).not.toHaveBeenCalled()
    expect(f.phraseReplies.failOwnedAttempt).toHaveBeenCalledWith(
      expect.objectContaining({ inboundId: row.id, expectedRequestId: input.requestId }),
    )
  })

  it('does not fail a recreated UUID even when all string fences match after reset', async () => {
    const f = fixture()
    const started = deferred<void>()
    const work = deferred<Reply>()
    f.reply.mockImplementationOnce(() => {
      started.resolve()
      return work.promise
    })
    const pending = sendFlowMessage(f.deps, input).catch((error: unknown) => error)
    await started.promise
    const oldId = f.store.row().id
    f.store.row().id = '00000000-0000-0000-0000-00000000c512'
    const saved = structuredClone(f.store.rows)
    work.resolve({ text: 'Status oficial de hoje.', metadata, flowStatusPhrase: tag })
    await pending
    expect(f.store.rows).toEqual(saved)
    expect(f.store.failInbound).not.toHaveBeenCalled()
    expect(f.phraseReplies.failOwnedAttempt).toHaveBeenCalledWith(
      expect.objectContaining({ inboundId: oldId }),
    )
  })

  it.each([
    new Error('Synthetic event transport failure'),
    new ZodError([
      { code: 'custom', path: ['flow_phrase_v1'], message: 'Synthetic corrupt private namespace' },
    ]),
  ])('reports private replay lookup failure as recoverable Flow failure: %s', async (failure) => {
    const f = fixture()
    const original = await sendFlowMessage(f.deps, input)
    const saved = structuredClone(f.store.rows)
    vi.clearAllMocks()
    f.phraseReplies.loadEventReply.mockRejectedValueOnce(failure)
    await expect(
      sendFlowMessage(f.deps, { ...input, requestId: 'request-replay-failed' }),
    ).rejects.toMatchObject({ status: 502, code: 'flow_provider_failed' })
    expect(f.store.rows).toEqual(saved)
    expect(f.reply).not.toHaveBeenCalled()
    expect(f.phraseReplies.loadCursor).not.toHaveBeenCalled()
    expect(f.phraseReplies.commitReply).not.toHaveBeenCalled()
    expect(f.phraseReplies.failOwnedAttempt).not.toHaveBeenCalled()
    expect(f.store.completeInbound).not.toHaveBeenCalled()
    expect(f.store.failInbound).not.toHaveBeenCalled()
    const replay = await sendFlowMessage(f.deps, {
      ...input,
      requestId: 'request-replay-recovered',
    })
    expect(replay.message).toEqual(original.message)
    expect(f.store.rows).toEqual(saved)
  })

  it('classifies a C5 reply found only by the second read without completing the IN again', async () => {
    const f = fixture()
    await sendFlowMessage(f.deps, input)
    const original = f.store.findAssistant
    let reads = 0
    f.store.findAssistant = async (...args) => (++reads === 1 ? null : original(...args))
    f.reply.mockClear()
    f.phraseReplies.loadEventReply.mockClear()
    const saved = structuredClone(f.store.rows)
    const result = await sendFlowMessage(f.deps, { ...input, requestId: 'request-replay' })
    expect(result.message.id).toBe(saved[1].id)
    expect(reads).toBe(2)
    expect(f.phraseReplies.loadEventReply).toHaveBeenCalledTimes(1)
    expect(f.store.completeInbound).not.toHaveBeenCalled()
    expect(f.reply).not.toHaveBeenCalled()
    expect(f.store.rows).toEqual(saved)
  })

  it('finds a late scoped C5 OUT for a real bare legacy IN without repeating the agent', async () => {
    const f = fixture()
    f.store.add(
      {
        userId: owner,
        providerMessageId: input.idempotencyKey,
        content: input.text,
        requestId: 'request-old-failed',
        state: 'failed',
        createdAt: now.toISOString(),
        attempt: {
          startedAt: now.toISOString(),
          providerStartedAt: now.toISOString(),
          retryStartedAt: [],
        },
      },
      'user',
    )
    const original = await sendFlowMessage(f.deps, input)
    const find = f.store.findAssistant
    const keys: string[] = []
    f.store.findAssistant = async (userId, key) => {
      keys.push(key)
      return keys.length === 1 ? null : find(userId, key)
    }
    f.reply.mockClear()
    f.phraseReplies.loadCursor.mockClear()
    f.phraseReplies.loadEventReply.mockClear()
    const saved = structuredClone(f.store.rows)
    const result = await sendFlowMessage(f.deps, { ...input, requestId: 'request-replay' })
    expect(result.message).toEqual(original.message)
    expect(keys).toEqual([
      `${eventKey}/assistant`,
      `${input.idempotencyKey}:assistant`,
      `${eventKey}/assistant`,
    ])
    expect(f.phraseReplies.loadEventReply).toHaveBeenCalledWith(
      expect.objectContaining({
        inboundProviderMessageId: input.idempotencyKey,
        assistantProviderMessageId: `${eventKey}/assistant`,
      }),
    )
    expect(f.reply).not.toHaveBeenCalled()
    expect(f.phraseReplies.loadCursor).not.toHaveBeenCalled()
    expect(f.store.completeInbound).not.toHaveBeenCalled()
    expect(f.store.rows).toEqual(saved)
  })

  it('classifies a bare legacy reply before using the original completion path', async () => {
    const f = fixture()
    const oldInput = {
      userId: owner,
      content: input.text,
      providerMessageId: input.idempotencyKey,
      requestId: input.requestId,
      state: 'completed' as const,
      createdAt: now.toISOString(),
    }
    const inside = f.store.add(oldInput, 'user')
    const outside = f.store.add(
      {
        ...oldInput,
        content: 'Resposta antiga.',
        providerMessageId: `${input.idempotencyKey}:assistant`,
      },
      'assistant',
    )
    f.phraseReplies.loadEventReply.mockResolvedValue({ kind: 'legacy', message: outside })
    const result = await sendFlowMessage(f.deps, input)
    expect(result.message.content).toBe('Resposta antiga.')
    expect(f.phraseReplies.loadEventReply).toHaveBeenCalledWith({
      userId: owner,
      eventKey,
      inboundId: inside.id,
      inboundProviderMessageId: input.idempotencyKey,
      assistantProviderMessageId: `${input.idempotencyKey}:assistant`,
      expectedInboundContent: input.text,
    })
    expect(f.store.completeInbound).toHaveBeenCalledTimes(1)
    expect(f.reply).not.toHaveBeenCalled()
    expect(f.phraseReplies.loadCursor).not.toHaveBeenCalled()
  })

  it('stops after three cursor conflicts without a fourth commit or repeating the agent', async () => {
    const f = fixture()
    f.phraseReplies.commitReply.mockResolvedValue({ action: 'cursor_conflict' })
    await expect(sendFlowMessage(f.deps, input)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(f.reply).toHaveBeenCalledTimes(1)
    expect(f.phraseReplies.loadCursor).toHaveBeenCalledTimes(3)
    expect(f.phraseReplies.commitReply).toHaveBeenCalledTimes(3)
    expect(f.store.insertAssistant).not.toHaveBeenCalled()
    expect(f.store.failInbound).not.toHaveBeenCalled()
    expect(f.store.row().state).toBe('failed')
  })

  it('reselects after two real cursor advances, freezing authority, metadata and creation time', async () => {
    const f = fixture()
    const observed: FlowPhraseReplyCommit[] = []
    f.phraseReplies.commitReply.mockImplementation(async (candidate) => {
      observed.push(structuredClone(candidate))
      if (observed.length < 3) {
        const key = `c5-concurrent-${observed.length}`
        const otherEvent = `mobile_flow/${owner}/${key}`
        const row = f.store.add(
          {
            userId: owner,
            providerMessageId: otherEvent,
            content: input.text,
            requestId: `request-other-${observed.length}`,
            createdAt: now.toISOString(),
            state: 'processing',
            attempt: {
              startedAt: now.toISOString(),
              providerStartedAt: now.toISOString(),
              retryStartedAt: [],
            },
          },
          'user',
        )
        const packet = prepareFlowStatusPhraseReply(
          { userId: owner, eventKey: otherEvent, statusText: 'Status concorrente.', ...tag },
          f.snapshotFor(owner).cursor,
        )
        expect(
          f.publish({
            ...candidate,
            eventKey: otherEvent,
            inboundId: row.id,
            inboundProviderMessageId: otherEvent,
            assistantProviderMessageId: `${otherEvent}/assistant`,
            expectedRequestId: row.requestId,
            nextCursor: packet.nextCursor,
            receipt: packet.receipt,
            content: packet.content,
          }).action,
        ).toBe('committed')
        vi.setSystemTime(new Date(now.getTime() + observed.length * 1000))
      }
      return f.publish(candidate)
    })
    const result = await sendFlowMessage(f.deps, input)
    expect(f.reply).toHaveBeenCalledTimes(1)
    expect(observed.map((item) => item.expectedCursorRevision)).toEqual(['0', '1', '2'])
    expect(observed.map((item) => item.nextCursor.ordinal)).toEqual([1, 2, 3])
    expect(new Set(observed.map((item) => item.receipt.selection.phrase)).size).toBe(3)
    for (const item of observed) {
      expect(item.createdAt).toBe(now.toISOString())
      expect(item.metadata).toEqual(metadata)
      expect(item.expectedRequestId).toBe(input.requestId)
      expect(item.expectedAttemptStartedAt).toBe(now.toISOString())
      expect(item.receipt.requestFingerprint).toBe(observed[0].receipt.requestFingerprint)
      expect(item.content.startsWith('Status oficial de hoje.')).toBe(true)
    }
    expect(result.message.content).toBe(observed[2].content)
    expect(f.snapshotFor(owner).cursorRevision).toBe('3')
    expect(f.store.rows.filter((row) => row.providerId === `${eventKey}/assistant`)).toHaveLength(1)
  })

  it.each([
    'attempt_conflict',
    'event_conflict',
  ] as const)('stops immediately on %s without failing a replacement attempt', async (action) => {
    const f = fixture()
    let replacement: Row[] = []
    f.phraseReplies.commitReply.mockImplementationOnce(async () => {
      const row = f.store.row()
      row.requestId = 'request-new-owner'
      if (!row.attempt) throw new Error('Synthetic attempt absent')
      row.attempt = { ...row.attempt, startedAt: '2026-10-09T00:01:00.000Z' }
      replacement = structuredClone(f.store.rows)
      return { action }
    })
    await expect(sendFlowMessage(f.deps, input)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(f.phraseReplies.commitReply).toHaveBeenCalledTimes(1)
    expect(f.phraseReplies.loadCursor).toHaveBeenCalledTimes(1)
    expect(f.store.rows).toEqual(replacement)
    expect(f.store.failInbound).not.toHaveBeenCalled()
  })

  it('preserves a committed OUT and completed IN when recovery lookup also fails, then replays on retry', async () => {
    const f = fixture()
    let confirmed: Row[] = []
    f.phraseReplies.commitReply.mockImplementationOnce(async (candidate) => {
      expect(f.publish(candidate).action).toBe('committed')
      confirmed = structuredClone(f.store.rows)
      f.phraseReplies.loadEventReply.mockRejectedValueOnce(
        new Error('Synthetic lost recovery read'),
      )
      throw new Error('Synthetic lost commit response')
    })
    await expect(sendFlowMessage(f.deps, input)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(f.store.rows).toEqual(confirmed)
    const result = await sendFlowMessage(f.deps, { ...input, requestId: 'request-retry' })
    expect(result.message.id).toBe(confirmed[1].id)
    expect(f.reply).toHaveBeenCalledTimes(1)
    expect(f.phraseReplies.commitReply).toHaveBeenCalledTimes(1)
    expect(f.store.completeInbound).not.toHaveBeenCalled()
    expect(f.store.failInbound).not.toHaveBeenCalled()
  })

  it('publishes EN twice without consuming a phrase, then selects the first PT phrase', async () => {
    const f = fixture()
    const englishTag = { ...tag, locale: 'en-US' }
    f.reply.mockResolvedValueOnce({
      text: 'Official status.',
      metadata,
      flowStatusPhrase: englishTag,
    })
    f.reply.mockResolvedValueOnce({
      text: 'Official status.',
      metadata,
      flowStatusPhrase: englishTag,
    })
    const first = await sendFlowMessage(f.deps, input)
    expect(first.message.content).toBe('Official status.')
    expect(f.snapshotFor(owner)).toMatchObject({
      cursorRevision: '1',
      cursor: { ordinal: 0, lastTextKey: null, usedTextKeys: [] },
    })
    const second = await sendFlowMessage(f.deps, {
      ...input,
      idempotencyKey: 'c5-event-0002',
      requestId: 'request-second',
    })
    expect(second.message.content).toBe('Official status.')
    expect(f.snapshotFor(owner)).toMatchObject({
      cursorRevision: '2',
      cursor: { ordinal: 0, lastTextKey: null, usedTextKeys: [] },
    })
    const third = await sendFlowMessage(f.deps, {
      ...input,
      idempotencyKey: 'c5-event-0003',
      requestId: 'request-third',
    })
    expect(third.message.content).toBe(
      'Status oficial de hoje.\n\nConsistência vale mais do que perfeição.',
    )
    expect(f.snapshotFor(owner)).toMatchObject({ cursorRevision: '3', cursor: { ordinal: 1 } })
    const replay = await sendFlowMessage(f.deps, { ...input, requestId: 'request-replay' })
    expect(replay.message).toEqual(first.message)
    expect(f.snapshotFor(owner).cursorRevision).toBe('3')
  })

  it('isolates A/B/A on the same bare key and advances only each authenticated owner cursor', async () => {
    const f = fixture()
    const other = '00000000-0000-0000-0000-00000000c502'
    const a = await sendFlowMessage(f.deps, input)
    const b = await sendFlowMessage(f.deps, {
      ...input,
      userId: other,
      requestId: 'request-account-b',
    })
    const aAgain = await sendFlowMessage(f.deps, {
      ...input,
      requestId: 'request-account-a-replay',
    })
    expect(aAgain.message).toEqual(a.message)
    expect(b.message.id).not.toBe(a.message.id)
    expect(f.snapshotFor(owner).cursorRevision).toBe('1')
    expect(f.snapshotFor(other).cursorRevision).toBe('1')
    expect(f.reply).toHaveBeenCalledTimes(2)
    expect(f.store.rows.filter((row) => row.userId === owner)).toHaveLength(2)
    expect(f.store.rows.filter((row) => row.userId === other)).toHaveLength(2)
  })

  it('refuses changed text under the same key before any C5 read or provider work', async () => {
    const f = fixture()
    await sendFlowMessage(f.deps, input)
    vi.clearAllMocks()
    await expect(
      sendFlowMessage(f.deps, { ...input, text: 'Outro conteúdo.' }),
    ).rejects.toMatchObject({ status: 409, code: 'idempotency_key_conflict' })
    expect(f.reply).not.toHaveBeenCalled()
    expect(f.phraseReplies.loadEventReply).not.toHaveBeenCalled()
    expect(f.phraseReplies.loadCursor).not.toHaveBeenCalled()
    expect(f.phraseReplies.commitReply).not.toHaveBeenCalled()
  })

  it('does not infer an IN UUID after an ambiguous insert response', async () => {
    const f = fixture()
    f.store.insertInbound = async (value) => {
      f.store.add(value, 'user')
      throw new Error('Synthetic lost insert response')
    }
    await expect(sendFlowMessage(f.deps, input)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(f.store.row().state).toBe('processing')
    expect(f.reply).not.toHaveBeenCalled()
    expect(f.phraseReplies.failOwnedAttempt).not.toHaveBeenCalled()
    expect(f.store.failInbound).not.toHaveBeenCalled()
  })

  it('does not start a commit when a cursor read exhausts the original 165-second turn', async () => {
    const f = fixture()
    let tick = 0
    vi.spyOn(performance, 'now').mockImplementation(() => tick)
    f.phraseReplies.loadCursor.mockImplementationOnce(async () => {
      tick = 165_000
      return f.snapshotFor(owner)
    })
    await expect(sendFlowMessage(f.deps, input)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(f.phraseReplies.commitReply).not.toHaveBeenCalled()
    expect(f.phraseReplies.loadCursor).toHaveBeenCalledTimes(1)
    // Only the initial event lookup ran: a read after the deadline is not launched.
    expect(f.phraseReplies.loadEventReply).toHaveBeenCalledTimes(1)
    expect(f.reply).toHaveBeenCalledTimes(1)
    expect(f.store.rows.filter((row) => row.role === 'assistant')).toHaveLength(0)
  })

  it.each([
    'close',
    'claim',
    'marker',
  ] as const)('refuses a reset generation immediately before the %s CAS', async (phase) => {
    const f = fixture()
    if (phase !== 'marker') {
      const expired = '2026-10-08T23:30:00.000Z'
      f.store.add(
        {
          userId: owner,
          content: input.text,
          providerMessageId: eventKey,
          requestId: 'request-before-reset',
          state: phase === 'close' ? 'processing' : 'failed',
          createdAt: expired,
          attempt: { startedAt: expired, providerStartedAt: null, retryStartedAt: [] },
        },
        'user',
      )
    }
    const transition = f.store.transitionInbound
    let replacement: Row[] = []
    let oldId = ''
    const calls: FlowInboundTransition[] = []
    f.store.transitionInbound = async (userId, key, change) => {
      calls.push(change)
      const row = f.store.row(userId, key)
      oldId = row.id
      const before = structuredClone(row)
      f.store.rows.splice(f.store.rows.indexOf(row), 1)
      f.store.add(
        {
          userId,
          providerMessageId: key,
          content: before.content,
          state: before.state,
          requestId: before.requestId,
          createdAt: before.createdAt,
          attempt: before.attempt ?? undefined,
        },
        'user',
      )
      replacement = structuredClone(f.store.rows)
      return transition(userId, key, change)
    }
    await expect(sendFlowMessage(f.deps, input)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_request_in_progress',
    })
    expect(calls).toHaveLength(1)
    expect(calls[0].expectedInboundId).toBe(oldId)
    expect(f.store.rows).toEqual(replacement)
    expect(f.reply).not.toHaveBeenCalled()
    expect(f.phraseReplies.commitReply).not.toHaveBeenCalled()
    expect(f.phraseReplies.failOwnedAttempt).not.toHaveBeenCalled()
  })

  it('keeps the original UUID between expired close and retry claim', async () => {
    const f = fixture()
    const expired = '2026-10-08T23:30:00.000Z'
    const first = f.store.add(
      {
        userId: owner,
        content: input.text,
        providerMessageId: eventKey,
        requestId: 'request-expired',
        state: 'processing',
        createdAt: expired,
        attempt: { startedAt: expired, providerStartedAt: null, retryStartedAt: [] },
      },
      'user',
    )
    const transition = f.store.transitionInbound
    const changes: FlowInboundTransition[] = []
    let replacement: Row[] = []
    f.store.transitionInbound = async (userId, key, change) => {
      changes.push(change)
      if (changes.length === 1) {
        const result = await transition(userId, key, change)
        expect(result).toBe(true)
        const closed = structuredClone(f.store.row())
        f.store.rows.splice(0, 1)
        f.store.add(
          {
            userId,
            providerMessageId: key,
            content: closed.content,
            state: closed.state,
            requestId: closed.requestId,
            createdAt: closed.createdAt,
            attempt: closed.attempt ?? undefined,
          },
          'user',
        )
        replacement = structuredClone(f.store.rows)
        return result
      }
      return transition(userId, key, change)
    }
    await expect(sendFlowMessage(f.deps, input)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_request_in_progress',
    })
    expect(changes.map((change) => change.expectedInboundId)).toEqual([first.id, first.id])
    expect(f.store.rows).toEqual(replacement)
    expect(f.reply).not.toHaveBeenCalled()
  })

  it.each([
    'error',
    'over-budget',
  ] as const)('preserves a replacement generation on recount %s', async (condition) => {
    const f = fixture()
    let calls = 0
    let oldId = ''
    let replacement: Row[] = []
    const count = f.store.countRecentExecutions
    f.store.countRecentExecutions = async () => {
      if (++calls === 1) return count()
      const original = structuredClone(f.store.row())
      oldId = original.id
      f.store.rows.splice(0, 1)
      f.store.add(
        {
          userId: owner,
          providerMessageId: eventKey,
          content: original.content,
          requestId: original.requestId,
          state: original.state,
          createdAt: original.createdAt,
          attempt: original.attempt ?? undefined,
        },
        'user',
      )
      replacement = structuredClone(f.store.rows)
      if (condition === 'error') throw new Error('Synthetic recount failed')
      return 11
    }
    await expect(sendFlowMessage(f.deps, input)).rejects.toMatchObject({
      status: condition === 'error' ? 502 : 429,
      code: condition === 'error' ? 'flow_provider_failed' : 'flow_rate_limited',
    })
    expect(f.store.rows).toEqual(replacement)
    expect(f.phraseReplies.failOwnedAttempt).toHaveBeenCalledWith(
      expect.objectContaining({ inboundId: oldId }),
    )
    expect(f.store.failInbound).not.toHaveBeenCalled()
    expect(f.reply).not.toHaveBeenCalled()
  })

  it.each([
    'claim',
    'marker',
  ] as const)('does not release a replacement after an applied %s loses its response', async (phase) => {
    const f = fixture()
    if (phase === 'claim')
      f.store.add(
        {
          userId: owner,
          providerMessageId: eventKey,
          content: input.text,
          requestId: 'request-failed',
          state: 'failed',
          createdAt: now.toISOString(),
          attempt: {
            startedAt: now.toISOString(),
            providerStartedAt: now.toISOString(),
            retryStartedAt: [],
          },
        },
        'user',
      )
    const transition = f.store.transitionInbound
    let oldId = ''
    let replacement: Row[] = []
    f.store.transitionInbound = async (userId, key, change) => {
      oldId = f.store.row().id
      expect(await transition(userId, key, change)).toBe(true)
      const applied = structuredClone(f.store.row())
      f.store.rows.splice(0, 1)
      f.store.add(
        {
          userId,
          providerMessageId: key,
          content: applied.content,
          requestId: applied.requestId,
          state: applied.state,
          createdAt: applied.createdAt,
          attempt: applied.attempt ?? undefined,
        },
        'user',
      )
      replacement = structuredClone(f.store.rows)
      throw new Error('Synthetic lost CAS response')
    }
    await expect(sendFlowMessage(f.deps, input)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(f.store.rows).toEqual(replacement)
    expect(f.phraseReplies.failOwnedAttempt).toHaveBeenCalledWith(
      expect.objectContaining({ inboundId: oldId }),
    )
    expect(f.store.failInbound).not.toHaveBeenCalled()
    expect(f.reply).not.toHaveBeenCalled()
  })

  it('ends waiting at 165 seconds and discards a cursor read that completes afterwards', async () => {
    // Replace the Date-only clock installed by the common fixture.
    vi.useRealTimers()
    vi.useFakeTimers({ toFake: ['Date', 'performance', 'setTimeout', 'clearTimeout'] })
    vi.setSystemTime(now)
    const f = fixture()
    const reading = deferred<void>()
    const cursor = deferred<FlowPhraseCursorSnapshot>()
    f.phraseReplies.loadCursor.mockImplementationOnce(() => {
      reading.resolve()
      return cursor.promise
    })
    const pending = sendFlowMessage(f.deps, input).catch((error: unknown) => error)
    await reading.promise
    expect(vi.getTimerCount()).toBe(1)
    await vi.advanceTimersByTimeAsync(165_000)
    expect(await pending).toMatchObject({ status: 502, code: 'flow_provider_failed' })
    const afterTimeout = structuredClone(f.store.rows)
    cursor.resolve(f.snapshotFor(owner))
    await vi.advanceTimersByTimeAsync(0)
    expect(f.store.rows).toEqual(afterTimeout)
    expect(f.phraseReplies.commitReply).not.toHaveBeenCalled()
    expect(f.reply).toHaveBeenCalledTimes(1)
    expect(f.phraseReplies.loadEventReply).toHaveBeenCalledTimes(1)
  })

  it('keeps draft lookup failures outside the confirmed atomic publication result', async () => {
    const f = fixture()
    const drafts = {
      findForTurn: vi.fn(async () => {
        throw new Error('Synthetic draft read failed')
      }),
    }
    const result = await sendFlowMessage({ ...f.deps, drafts }, input)
    expect(result.message.content).toBe(
      'Status oficial de hoje.\n\nConsistência vale mais do que perfeição.',
    )
    expect(result.draft).toBeNull()
    expect(f.store.row().state).toBe('completed')
    expect(f.store.completeInbound).not.toHaveBeenCalled()
    expect(f.store.failInbound).not.toHaveBeenCalled()
  })

  it('never touches C5 while reading history', async () => {
    const f = fixture()
    expect(await loadFlowHistory(f.deps, owner, 50)).toEqual({
      conversation_id: 'flow',
      messages: [],
    })
    expect(f.phraseReplies.loadEventReply).not.toHaveBeenCalled()
    expect(f.phraseReplies.loadCursor).not.toHaveBeenCalled()
    expect(f.phraseReplies.commitReply).not.toHaveBeenCalled()
  })

  it('preserves normal publication when the reply is untagged or the C5 store is absent', async () => {
    const taggedWithoutStore = fixture()
    const plain = fixture()
    plain.reply.mockResolvedValue({ text: 'Resposta normal.', metadata })
    const original = await sendFlowMessage(
      { store: taggedWithoutStore.store, agent: { reply: taggedWithoutStore.reply } },
      input,
    )
    const normal = await sendFlowMessage(plain.deps, input)
    expect(original.message.content).toBe('Status oficial de hoje.')
    expect(normal.message.content).toBe('Resposta normal.')
    for (const f of [taggedWithoutStore, plain]) {
      expect(f.store.insertAssistant).toHaveBeenCalledTimes(1)
      expect(f.store.completeInbound).toHaveBeenCalledTimes(1)
      expect(f.phraseReplies.loadCursor).not.toHaveBeenCalled()
      expect(f.phraseReplies.commitReply).not.toHaveBeenCalled()
    }
  })
})
