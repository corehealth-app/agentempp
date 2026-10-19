import { prepareFlowStatusPhraseReply } from '@mpp/agent/flow-curated-phrases'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  createSupabaseFlowChatStore,
  FLOW_EXECUTION_LEASE_MS,
  type FlowChatDependencies,
  type FlowChatStore,
  FlowMessageAlreadyStoredError,
  type SendFlowMessageInput,
  type StoredFlowMessage,
  sendFlowMessage,
} from './flow-chat-service'
import {
  type CapturedFlowInboundAuthority,
  type FlowInboundAuthorityMessage,
  FlowInboundAuthorityRefusal,
  type FlowInboundAuthoritySource,
} from './flow-inbound-authority'
import type { FlowPhraseReplyStore } from './flow-phrase-reply-store'

const OWNER = '00000000-0000-0000-0000-00000000f171'
const INBOUND = '00000000-0000-0000-0000-00000000b171'
const KEY = 's17j-turn-0001'
const TEXT = 'Cafe\u0301  \nleg press'
const STARTED = '2026-10-15T12:00:00.123Z'
const REQUEST = 'request-s17j-0001'

function wire(overrides: Partial<FlowInboundAuthorityMessage> = {}): FlowInboundAuthorityMessage {
  return {
    id: INBOUND,
    direction: 'in',
    content: TEXT,
    delivery_status: 'processing',
    created_at: STARTED,
    raw_payload: {
      request_id: REQUEST,
      conversation_id: 'flow',
      attempt_started_at: STARTED,
      provider_started_at: null,
      retry_started_at: [],
    },
    ...overrides,
  }
}
function message(overrides: Partial<StoredFlowMessage> = {}): StoredFlowMessage {
  return {
    id: INBOUND,
    role: 'user',
    content: TEXT,
    state: 'processing',
    requestId: REQUEST,
    createdAt: STARTED,
    attempt: { startedAt: STARTED, providerStartedAt: null, retryStartedAt: [] },
    ...overrides,
  }
}
function setup() {
  const store: FlowChatStore = {
    loadHistory: vi.fn(async () => []),
    countRecentExecutions: vi.fn(async () => 0),
    findInbound: vi.fn(async () => null),
    findAssistant: vi.fn(async () => null),
    insertInbound: vi.fn(async () => message()),
    transitionInbound: vi.fn(async () => true),
    insertAssistant: vi.fn(async () =>
      message({ id: 'assistant-1', role: 'assistant', content: 'Resposta', state: 'completed' }),
    ),
    completeInbound: vi.fn(async () => {}),
    failInbound: vi.fn(async () => {}),
  }
  const captured: CapturedFlowInboundAuthority = Object.freeze({
    userId: OWNER,
    requestKey: KEY,
    text: TEXT,
    admissionId: '00000000-0000-0000-0000-00000000a171',
    probe: vi
      .fn<CapturedFlowInboundAuthority['probe']>()
      .mockResolvedValue({ status: 'bound', inbound: wire() })
      .mockResolvedValueOnce({ status: 'unbound' }),
    persist: vi.fn(async () => ({ status: 'inserted' as const, inbound: wire() })),
  })
  const source: FlowInboundAuthoritySource = { capture: vi.fn(async () => captured) }
  const deps: FlowChatDependencies & { inboundAuthority: FlowInboundAuthoritySource } = {
    store,
    agent: { reply: vi.fn(async () => ({ text: 'Resposta', metadata: {} })) },
    inboundAuthority: source,
  }
  const input: SendFlowMessageInput & { inboundAuthority: CapturedFlowInboundAuthority } = {
    userId: OWNER,
    text: TEXT,
    idempotencyKey: KEY,
    requestId: REQUEST,
    now: new Date(STARTED),
    inboundAuthority: captured,
  }
  return { store, captured, source, deps, input }
}

beforeEach(() => {
  vi.spyOn(console, 'info').mockImplementation(() => {})
})
afterEach(() => {
  vi.restoreAllMocks()
  vi.useRealTimers()
})

function withPhrases(q: ReturnType<typeof setup>) {
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
  const packet = prepareFlowStatusPhraseReply(
    {
      userId: OWNER,
      eventKey: `mobile_flow/${OWNER}/${KEY}`,
      statusText: 'Status oficial de hoje.',
      ...tag,
    },
    null,
  )
  const out = message({
    id: 'original-out',
    role: 'assistant',
    content: packet.content,
    state: 'completed',
  })
  const event = { kind: 'c5' as const, message: out, receipt: packet.receipt }
  const phrase: FlowPhraseReplyStore = {
    loadEventReply: vi.fn(async () => null),
    loadCursor: vi.fn(async () => ({ anchorAssistantId: null, cursorRevision: '0', cursor: null })),
    commitReply: vi.fn(async () => ({ action: 'committed' as const, message: out })),
    failOwnedAttempt: vi.fn(async () => true),
  }
  q.deps.phraseReplies = phrase
  const providerReply = {
    text: 'Status oficial de hoje.',
    metadata: {
      stage: 'recomposicao',
      modelUsed: 'none',
      promptTokens: 0,
      completionTokens: 0,
      costUsd: 0,
      latencyMs: 17,
    },
    flowStatusPhrase: tag,
  }
  vi.mocked(q.deps.agent.reply).mockResolvedValue(providerReply)
  return { phrase, event, out, providerReply }
}

describe('S17J Flow service captured IN (dormant injection)', () => {
  it('S4 refuses reset after an unbound probe without falling back to legacy INSERT', async () => {
    const q = setup()
    vi.mocked(q.captured.persist).mockRejectedValue(
      new FlowInboundAuthorityRefusal('forbidden', 'stale_epoch'),
    )
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 409,
      code: 'flow_request_authority_conflict',
    })
    expect(q.captured.probe).toHaveBeenCalledOnce()
    expect(q.captured.persist).toHaveBeenCalledOnce()
    expect(q.captured.persist).toHaveBeenCalledWith({ requestId: REQUEST, startedAt: STARTED })
    expect(q.store.findInbound).not.toHaveBeenCalled()
    expect(q.store.insertInbound).not.toHaveBeenCalled()
    expect(q.store.transitionInbound).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
    expect(q.source.capture).not.toHaveBeenCalled()
  })

  it('S2 reused never grants execution ownership even with the same request ID and clock', async () => {
    const q = setup()
    const row = wire()
    vi.mocked(q.captured.persist).mockResolvedValue({ status: 'reused', inbound: row })
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_request_in_progress',
    })
    expect(q.store.insertInbound).not.toHaveBeenCalled()
    expect(q.store.transitionInbound).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
    expect(row.raw_payload).toEqual(wire().raw_payload)
  })

  it('S1 records the first IN only after budget, then recounts, marks and calls provider once', async () => {
    const q = setup()
    const order: string[] = []
    vi.mocked(q.store.countRecentExecutions)
      .mockImplementationOnce(async () => {
        order.push('first-count')
        return 9
      })
      .mockImplementationOnce(async () => {
        order.push('recount')
        return 10
      })
    vi.mocked(q.captured.persist).mockImplementation(async () => {
      order.push('persist')
      return { status: 'inserted', inbound: wire() }
    })
    vi.mocked(q.store.transitionInbound).mockImplementation(async (_user, _key, change) => {
      order.push('marker')
      expect(change.expectedInboundId).toBe(INBOUND)
      return true
    })
    vi.mocked(q.deps.agent.reply).mockImplementation(async () => {
      order.push('provider')
      return { text: 'Resposta', metadata: {} }
    })
    const response = await sendFlowMessage(q.deps, q.input)
    expect(order).toEqual(['first-count', 'persist', 'recount', 'marker', 'provider'])
    expect(response.message.content).toBe('Resposta')
    expect(q.store.findInbound).not.toHaveBeenCalled()
    expect(q.store.insertInbound).not.toHaveBeenCalled()
    expect(q.store.completeInbound).toHaveBeenCalledWith(
      OWNER,
      `mobile_flow/${OWNER}/${KEY}`,
      INBOUND,
    )
    expect(q.deps.agent.reply).toHaveBeenCalledOnce()
    expect(q.source.capture).not.toHaveBeenCalled()
  })

  it.each([
    'limit',
    'count-error',
  ] as const)('S1 %s refuses before persist or provider', async (kind) => {
    const q = setup()
    if (kind === 'limit') vi.mocked(q.store.countRecentExecutions).mockResolvedValue(10)
    else vi.mocked(q.store.countRecentExecutions).mockRejectedValue(new Error('count failed'))
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toThrow()
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.store.insertInbound).not.toHaveBeenCalled()
    expect(q.store.transitionInbound).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
  })

  it('S2 reused with different operational metadata also never claims or retries it', async () => {
    const q = setup()
    const row = wire({
      delivery_status: 'failed',
      created_at: '2026-10-14T12:00:00.123456Z',
      raw_payload: {
        request_id: 'other-request',
        attempt_started_at: '2026-10-14T12:00:00.123Z',
        retry_started_at: [STARTED],
      },
    })
    const before = JSON.stringify(row)
    vi.mocked(q.captured.persist).mockResolvedValue({ status: 'reused', inbound: row })
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_request_in_progress',
    })
    expect(q.store.transitionInbound).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
    expect(JSON.stringify(row)).toBe(before)
  })

  it('S3 a lost persist reply proves no UUID and performs no cleanup; later retries reuse the bound IN', async () => {
    const q = setup()
    vi.mocked(q.captured.persist).mockRejectedValue(new Error('reply lost after commit'))
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toThrow('reply lost after commit')
    expect(q.store.transitionInbound).not.toHaveBeenCalled()
    expect(q.store.failInbound).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
    // The same original receipt is bound after the server commit, still inside its lease.
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 409,
      code: 'idempotency_request_in_progress',
    })
    expect(q.store.transitionInbound).not.toHaveBeenCalled()
    const later = {
      ...q.input,
      requestId: 'request-after-lease',
      now: new Date(Date.parse(STARTED) + FLOW_EXECUTION_LEASE_MS + 1),
    }
    await sendFlowMessage(q.deps, later)
    expect(q.captured.persist).toHaveBeenCalledOnce()
    expect(q.store.insertInbound).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).toHaveBeenCalledOnce()
    expect(q.source.capture).not.toHaveBeenCalled()
    for (const call of vi.mocked(q.store.transitionInbound).mock.calls)
      expect(call[2].expectedInboundId).toBe(INBOUND)
  })

  it.each([
    'initial-OUT',
    'second-OUT',
  ] as const)('S5 refuses reset before %s replay with the same captured handle', async (where) => {
    const q = setup()
    vi.mocked(q.captured.probe)
      .mockReset()
      .mockResolvedValueOnce({ status: 'bound', inbound: wire({ delivery_status: 'completed' }) })
      .mockRejectedValue(new FlowInboundAuthorityRefusal('forbidden', 'stale_epoch'))
    const out = message({
      id: 'original-out',
      role: 'assistant',
      state: 'completed',
      content: 'Stored',
    })
    vi.mocked(q.store.findAssistant).mockResolvedValue(out)
    if (where === 'second-OUT') vi.mocked(q.store.findAssistant).mockResolvedValueOnce(null)
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 409,
      code: 'flow_request_authority_conflict',
    })
    expect(q.store.completeInbound).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.store.findInbound).not.toHaveBeenCalled()
    expect(q.source.capture).not.toHaveBeenCalled()
  })

  it('S5 preserves a bound original OUT without consuming budget or invoking provider', async () => {
    const q = setup()
    vi.mocked(q.captured.probe)
      .mockReset()
      .mockResolvedValue({
        status: 'bound',
        inbound: wire({ delivery_status: 'completed', created_at: '2026-10-15T12:00:00.123456Z' }),
      })
    const out = message({
      id: 'original-out',
      role: 'assistant',
      state: 'completed',
      content: 'Stored',
      createdAt: '2026-10-15T12:00:00.123456Z',
    })
    vi.mocked(q.store.findAssistant).mockResolvedValue(out)
    vi.mocked(q.store.countRecentExecutions).mockRejectedValue(new Error('ignored on replay'))
    const result = await sendFlowMessage(q.deps, q.input)
    expect(result.message).toMatchObject({
      id: out.id,
      content: out.content,
      created_at: out.createdAt,
    })
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.store.completeInbound).toHaveBeenCalledWith(
      OWNER,
      `mobile_flow/${OWNER}/${KEY}`,
      INBOUND,
    )
  })

  it('S6 never adopts a newly appearing IN to repair an orphan OUT after an unbound probe', async () => {
    const q = setup()
    vi.mocked(q.store.findAssistant).mockResolvedValue(
      message({ role: 'assistant', content: 'Orphan OUT' }),
    )
    // A second bound probe alone must not replace the original unbound observation.
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 409,
      code: 'flow_request_authority_conflict',
    })
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.store.completeInbound).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
  })

  it.each([
    'unproved_inbound',
    'inbound_mismatch',
  ] as const)('S6 %s never falls back to bare/scoped lookup or legacy INSERT', async (reason) => {
    const q = setup()
    vi.mocked(q.captured.probe)
      .mockReset()
      .mockRejectedValue(new FlowInboundAuthorityRefusal('forbidden', reason))
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({ status: 409 })
    expect(q.store.findInbound).not.toHaveBeenCalled()
    expect(q.store.insertInbound).not.toHaveBeenCalled()
    expect(q.captured.persist).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
  })

  it.each([
    'owner',
    'key',
    'text',
    'missing-handle',
    'missing-source',
  ] as const)('mixed %s wiring fails before store, probe, writer or provider work', async (kind) => {
    const q = setup()
    if (kind === 'owner') q.input.userId = '00000000-0000-0000-0000-00000000f172'
    if (kind === 'key') q.input.idempotencyKey = 'other-key-0001'
    if (kind === 'text') q.input.text = 'other text'
    if (kind === 'missing-handle') delete (q.input as SendFlowMessageInput).inboundAuthority
    if (kind === 'missing-source') delete (q.deps as FlowChatDependencies).inboundAuthority
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 500,
      code: 'flow_request_authority_invalid_input',
    })
    expect(q.captured.probe).not.toHaveBeenCalled()
    expect(q.store.countRecentExecutions).not.toHaveBeenCalled()
    expect(q.store.findInbound).not.toHaveBeenCalled()
    expect(q.store.insertInbound).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
  })

  it.each([
    'close',
    'claim',
    'marker',
  ] as const)('S7 a replacement UUID at %s cannot be claimed even with identical other fields', async (phase) => {
    const q = setup()
    const replacement = { ...message(), id: '00000000-0000-0000-0000-00000000b172' }
    if (phase !== 'marker') {
      const expired = '2026-10-14T12:00:00.123Z'
      vi.mocked(q.captured.probe)
        .mockReset()
        .mockResolvedValue({
          status: 'bound',
          inbound: wire({
            delivery_status: phase === 'close' ? 'processing' : 'failed',
            raw_payload: {
              request_id: REQUEST,
              attempt_started_at: expired,
              provider_started_at: null,
              retry_started_at: [],
            },
          }),
        })
    }
    const before = JSON.stringify(replacement)
    vi.mocked(q.store.transitionInbound).mockImplementation(
      async (_owner, _key, change) => change.expectedInboundId === replacement.id,
    )
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({ status: 409 })
    expect(vi.mocked(q.store.transitionInbound).mock.calls[0]?.[2].expectedInboundId).toBe(INBOUND)
    expect(JSON.stringify(replacement)).toBe(before)
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
  })

  it('S7 recount cleanup pins UUID even without C5 and never demotes a replacement', async () => {
    const q = setup()
    const replacement = { ...message(), id: '00000000-0000-0000-0000-00000000b172' }
    vi.mocked(q.store.countRecentExecutions).mockResolvedValueOnce(9).mockResolvedValueOnce(11)
    vi.mocked(q.store.transitionInbound).mockImplementation(async (_owner, _key, change) => {
      if (change.expectedInboundId === replacement.id) {
        replacement.state = change.to
        return true
      }
      return false
    })
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({ status: 429 })
    expect(replacement.state).toBe('processing')
    expect(vi.mocked(q.store.transitionInbound).mock.calls[0]?.[2]).toMatchObject({
      expectedInboundId: INBOUND,
      expectedRequestId: REQUEST,
      expectedAttemptStartedAt: STARTED,
    })
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
  })

  it('S7 a late provider failure cannot demote a later attempt on the same UUID without C5', async () => {
    const q = setup()
    const current = message()
    vi.mocked(q.store.transitionInbound).mockImplementation(async (_owner, _key, change) => {
      if (
        change.expectedInboundId !== current.id ||
        change.expectedRequestId !== current.requestId ||
        change.expectedAttemptStartedAt !== current.attempt?.startedAt
      )
        return false
      current.state = change.to
      current.requestId = change.requestId
      current.attempt = change.attempt
      return true
    })
    vi.mocked(q.deps.agent.reply).mockImplementation(async () => {
      current.requestId = 'later-request-0002'
      current.attempt = {
        startedAt: '2026-10-15T12:20:00.123Z',
        providerStartedAt: STARTED,
        retryStartedAt: [STARTED],
      }
      throw new Error('old provider failure')
    })
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({ status: 502 })
    expect(current.state).toBe('processing')
    expect(current.requestId).toBe('later-request-0002')
    expect(q.store.failInbound).not.toHaveBeenCalled()
    expect(vi.mocked(q.store.transitionInbound).mock.calls.at(-1)?.[2]).toMatchObject({
      expectedInboundId: INBOUND,
      expectedRequestId: REQUEST,
      expectedAttemptStartedAt: STARTED,
    })
  })

  it('S7 completion pins the original UUID and refuses zero updated rows in the real store port', async () => {
    const eq: Array<[string, string]> = []
    const select = vi.fn(async () => ({ data: [], error: null }))
    const query = {
      update: vi.fn(() => query),
      eq: vi.fn((key: string, value: string) => {
        eq.push([key, value])
        return query
      }),
      select,
    }
    const client = { from: vi.fn(() => query) } as unknown as ServiceClient
    await expect(
      createSupabaseFlowChatStore(client).completeInbound(
        OWNER,
        `mobile_flow/${OWNER}/${KEY}`,
        INBOUND,
      ),
    ).rejects.toMatchObject({ status: 409, code: 'flow_request_authority_conflict' })
    expect(eq).toContainEqual(['id', INBOUND])
    expect(select).toHaveBeenCalledWith('id')
  })

  it('S7 completion never updates a replacement with identical key/text/request/clock', async () => {
    const q = setup()
    const replacement = { ...message(), id: '00000000-0000-0000-0000-00000000b172' }
    vi.mocked(q.store.completeInbound).mockImplementation(async (_owner, _key, id) => {
      if (id !== replacement.id)
        throw new FlowInboundAuthorityRefusal('forbidden', 'inbound_mismatch')
      replacement.state = 'completed'
    })
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toThrow()
    expect(replacement.state).toBe('processing')
    expect(q.store.completeInbound).toHaveBeenCalledWith(
      OWNER,
      `mobile_flow/${OWNER}/${KEY}`,
      INBOUND,
    )
  })

  it('S5 rejects reset during OUT collision recovery without reusing a replacement', async () => {
    const q = setup()
    vi.mocked(q.store.insertAssistant).mockRejectedValue(new FlowMessageAlreadyStoredError())
    vi.mocked(q.store.findAssistant)
      .mockResolvedValueOnce(null)
      .mockResolvedValue(message({ role: 'assistant', content: 'Stored' }))
    vi.mocked(q.captured.probe)
      .mockReset()
      .mockResolvedValueOnce({ status: 'unbound' })
      .mockResolvedValueOnce({ status: 'bound', inbound: wire() })
      .mockRejectedValue(new FlowInboundAuthorityRefusal('forbidden', 'stale_epoch'))
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 409,
      code: 'flow_request_authority_conflict',
    })
    expect(q.store.completeInbound).not.toHaveBeenCalled()
    expect(q.source.capture).not.toHaveBeenCalled()
    expect(q.deps.agent.reply).toHaveBeenCalledOnce()
  })

  it.each([
    'initial-c5',
    'prior-c5',
    'commit-replay',
    'recover-c5',
  ] as const)('S8 %s rechecks the original authority and preserves its refusal outside recovery catches', async (where) => {
    const q = setup()
    const { phrase, event, out } = withPhrases(q)
    const stale = () => {
      vi.mocked(q.captured.probe).mockRejectedValue(
        new FlowInboundAuthorityRefusal('forbidden', 'stale_epoch'),
      )
    }
    if (where === 'initial-c5') {
      vi.mocked(q.captured.probe)
        .mockReset()
        .mockResolvedValue({ status: 'bound', inbound: wire({ delivery_status: 'completed' }) })
      vi.mocked(q.store.findAssistant).mockResolvedValue(out)
    }
    if (where === 'initial-c5' || where === 'prior-c5') {
      vi.mocked(phrase.loadEventReply).mockImplementation(async () => {
        stale()
        return event
      })
    } else if (where === 'commit-replay') {
      vi.mocked(phrase.commitReply).mockImplementation(async () => {
        stale()
        return { action: 'replay', message: out }
      })
    } else {
      vi.mocked(phrase.commitReply).mockRejectedValue(new Error('reply lost after C5 commit'))
      vi.mocked(phrase.loadEventReply)
        .mockResolvedValueOnce(null)
        .mockImplementation(async () => {
          stale()
          return event
        })
    }
    const before = JSON.stringify(event)
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 409,
      code: 'flow_request_authority_conflict',
    })
    expect(JSON.stringify(event)).toBe(before)
    expect(q.source.capture).not.toHaveBeenCalled()
    expect(q.store.completeInbound).not.toHaveBeenCalled()
    expect(q.store.failInbound).not.toHaveBeenCalled()
    expect(phrase.failOwnedAttempt).not.toHaveBeenCalled()
    expect(phrase.loadEventReply).toHaveBeenCalledTimes(where === 'recover-c5' ? 2 : 1)
    expect(q.deps.agent.reply).toHaveBeenCalledTimes(where === 'initial-c5' ? 0 : 1)
  })

  it('S8 a valid initial C5 replay preserves its receipt/text/time and never advances the cursor', async () => {
    const q = setup()
    const { phrase, event, out } = withPhrases(q)
    vi.mocked(q.captured.probe)
      .mockReset()
      .mockResolvedValue({ status: 'bound', inbound: wire({ delivery_status: 'completed' }) })
    vi.mocked(q.store.findAssistant).mockResolvedValue(out)
    vi.mocked(phrase.loadEventReply).mockResolvedValue(event)
    const before = JSON.stringify(event)
    const response = await sendFlowMessage(q.deps, q.input)
    expect(response.message).toMatchObject({
      id: out.id,
      content: out.content,
      request_id: out.requestId,
      created_at: out.createdAt,
    })
    expect(JSON.stringify(event)).toBe(before)
    expect(q.deps.agent.reply).not.toHaveBeenCalled()
    expect(phrase.loadCursor).not.toHaveBeenCalled()
    expect(phrase.commitReply).not.toHaveBeenCalled()
    expect(q.store.completeInbound).not.toHaveBeenCalled()
  })

  it('S8 keeps exactly three cursor conflicts, with original UUID/clock and no fourth commit', async () => {
    const q = setup()
    const { phrase } = withPhrases(q)
    vi.mocked(phrase.commitReply).mockResolvedValue({ action: 'cursor_conflict' })
    await expect(sendFlowMessage(q.deps, q.input)).rejects.toMatchObject({
      status: 502,
      code: 'flow_provider_failed',
    })
    expect(phrase.commitReply).toHaveBeenCalledTimes(3)
    expect(phrase.loadCursor).toHaveBeenCalledTimes(3)
    const calls = vi.mocked(phrase.commitReply).mock.calls.map(([value]) => value)
    expect(new Set(calls.map((value) => value.createdAt)).size).toBe(1)
    for (const value of calls)
      expect(value).toMatchObject({
        userId: OWNER,
        inboundId: INBOUND,
        expectedRequestId: REQUEST,
        expectedAttemptStartedAt: STARTED,
      })
    expect(q.deps.agent.reply).toHaveBeenCalledOnce()
    expect(phrase.failOwnedAttempt).toHaveBeenCalledWith(
      expect.objectContaining({
        inboundId: INBOUND,
        expectedRequestId: REQUEST,
        expectedAttemptStartedAt: STARTED,
      }),
    )
  })

  it('S8 a delayed cursor never resets the original 165s deadline or commits a late result', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'performance'] })
    const q = setup()
    const { phrase } = withPhrases(q)
    let release: (value: Awaited<ReturnType<FlowPhraseReplyStore['loadCursor']>>) => void = () => {
      throw new Error('not started')
    }
    let entered: () => void = () => {}
    const started = new Promise<void>((resolve) => {
      entered = resolve
    })
    vi.mocked(phrase.loadCursor).mockImplementation(() => {
      entered()
      return new Promise((resolve) => {
        release = resolve
      })
    })
    const pending = sendFlowMessage(q.deps, q.input).catch((error: unknown) => error)
    await started
    await vi.advanceTimersByTimeAsync(165_000)
    expect(await pending).toMatchObject({ status: 502, code: 'flow_provider_failed' })
    release({ anchorAssistantId: null, cursorRevision: '0', cursor: null })
    await vi.advanceTimersByTimeAsync(0)
    expect(phrase.commitReply).not.toHaveBeenCalled()
    expect(phrase.loadCursor).toHaveBeenCalledOnce()
    expect(phrase.loadEventReply).toHaveBeenCalledOnce()
    expect(q.deps.agent.reply).toHaveBeenCalledOnce()
  })

  it('S8 final authority gate gets only the remaining 45s and never demotes an already committed C5 result', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'performance'] })
    const q = setup()
    const { phrase, out, providerReply } = withPhrases(q)
    vi.mocked(q.deps.agent.reply).mockImplementation(async () => {
      await vi.advanceTimersByTimeAsync(120_000)
      return providerReply
    })
    let release: (value: Awaited<ReturnType<CapturedFlowInboundAuthority['probe']>>) => void =
      () => {
        throw new Error('not started')
      }
    let entered: () => void = () => {}
    let committed = false
    let settled = false
    const started = new Promise<void>((resolve) => {
      entered = resolve
    })
    vi.mocked(phrase.commitReply).mockImplementation(async () => {
      committed = true
      vi.mocked(q.captured.probe).mockImplementation(() => {
        entered()
        return new Promise((resolve) => {
          release = resolve
        })
      })
      return { action: 'committed', message: out }
    })
    const before = JSON.stringify(out)
    const pending = sendFlowMessage(q.deps, q.input).then(
      (value) => {
        settled = true
        return value
      },
      (error: unknown) => {
        settled = true
        return error
      },
    )
    await started
    expect(performance.now()).toBe(120_000)
    await vi.advanceTimersByTimeAsync(44_999)
    expect(settled).toBe(false)
    await vi.advanceTimersByTimeAsync(1)
    const error = await pending
    expect(error).toBeInstanceOf(Error)
    expect(error).toMatchObject({ message: 'flow turn time limit exceeded' })
    expect(committed).toBe(true)
    expect(JSON.stringify(out)).toBe(before)
    expect(phrase.commitReply).toHaveBeenCalledOnce()
    expect(phrase.loadEventReply).toHaveBeenCalledOnce()
    expect(phrase.failOwnedAttempt).not.toHaveBeenCalled()
    expect(q.store.completeInbound).not.toHaveBeenCalled()
    release({ status: 'bound', inbound: wire() })
    await vi.advanceTimersByTimeAsync(0)
    expect(phrase.commitReply).toHaveBeenCalledOnce()
    expect(phrase.failOwnedAttempt).not.toHaveBeenCalled()
  })
})
