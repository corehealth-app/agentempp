import type { Database } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { describe, expect, it } from 'vitest'
import { createSupabaseFlowChatStore } from './flow-chat-service'

const nowAttempt = '2026-10-09T00:00:00.000Z'
const owner = '00000000-0000-0000-0000-00000000c501'
const inboundId = '00000000-0000-0000-0000-00000000c511'
const assistantId = '00000000-0000-0000-0000-00000000c521'
const eventKey = `mobile_flow/${owner}/c5-event-0001`
const catalogVersion =
  'flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb'
const textKey = '972da9d0303d445a31ba14f93f6e7fcd29f5e625b274244313c6bbe65fc45a24'
const cursor = {
  schema: 'flow.phrase-state.v1' as const,
  userId: owner,
  catalogVersion,
  ordinal: 1,
  lastTextKey: textKey,
  usedTextKeys: [textKey],
}
const receipt = {
  eventKey,
  requestFingerprint: 'ad21dd91df986aaf7ffbce6760ecfcfc0df4bb223481946e208b4d17e292e580',
  selection: {
    phrase: 'Consistência vale mais do que perfeição.',
    phraseId: 'engagement:002',
    sourceText: 'Consistência vale mais do que perfeição.',
    foodCanonicalName: null,
    reason: 'selected_incentive',
  },
}
const namespace = {
  schema: 'flow.phrase-store.v1',
  cursor_revision: '1',
  previous_anchor_assistant_id: null,
  cursor,
  receipt,
}
const identity = {
  userId: owner,
  eventKey,
  inboundId,
  inboundProviderMessageId: 'c5-event-0001', // A real legacy IN can use the bare key.
  assistantProviderMessageId: `${eventKey}/assistant`,
  expectedInboundContent: 'Status do dia',
}
const inbound = {
  id: inboundId,
  user_id: owner,
  provider: 'mobile_flow',
  provider_message_id: identity.inboundProviderMessageId,
  direction: 'in',
  role: 'user',
  content_type: 'text',
  content: identity.expectedInboundContent,
  delivery_status: 'completed',
  raw_payload: {
    conversation_id: 'flow',
    request_id: 'request-original',
    attempt_started_at: '2026-10-09T00:00:00.000Z',
    sentinel: { preserve: true },
  },
  created_at: '2026-10-09T00:00:00+00:00',
}
const outbound = {
  ...inbound,
  id: assistantId,
  provider_message_id: identity.assistantProviderMessageId,
  direction: 'out',
  role: 'assistant',
  content: 'Status oficial de hoje.\n\nConsistência vale mais do que perfeição.',
  raw_payload: {
    conversation_id: 'flow',
    request_id: 'request-original',
    flow_phrase_v1: namespace,
    sentinel: { private: true },
  },
}
const message = {
  id: assistantId,
  role: 'assistant',
  content: outbound.content,
  state: 'completed',
  requestId: 'request-original',
  createdAt: outbound.created_at,
}
const rpcMessage = {
  id: assistantId,
  direction: 'out',
  content: outbound.content,
  delivery_status: 'completed',
  raw_payload: outbound.raw_payload,
  created_at: outbound.created_at,
}
const commit = {
  ...identity,
  expectedRequestId: 'request-new',
  expectedAttemptStartedAt: '2026-10-09T00:00:00.000Z',
  expectedAnchorAssistantId: null,
  expectedCursorRevision: '0',
  expectedCursor: null,
  nextCursor: cursor,
  receipt,
  content: outbound.content,
  createdAt: '2026-10-09T00:00:00.000Z',
  metadata: {
    stage: 'recomposicao',
    modelUsed: 'none' as const,
    promptTokens: 0 as const,
    completionTokens: 0 as const,
    costUsd: 0 as const,
    latencyMs: 17,
  },
}
const committedMessage = { ...message, requestId: 'request-new' }
const committedRpcMessage = {
  ...rpcMessage,
  raw_payload: { ...rpcMessage.raw_payload, request_id: 'request-new' },
}

type Request = { url: URL; method: string; body: unknown }
// Use the real Supabase/PostgREST client. Only the HTTP boundary is synthetic;
// SQL transaction/lock guarantees belong to the separate real PG gates.
function client(respond: (request: Request) => { data: unknown; status?: number }) {
  const requests: Request[] = []
  const supabase = createClient<Database>('http://127.0.0.1:55489', 'synthetic-test-key', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (input, init) => {
        const request = {
          url: new URL(typeof input === 'string' || input instanceof URL ? input : input.url),
          method: init?.method ?? 'GET',
          body: typeof init?.body === 'string' ? JSON.parse(init.body) : null,
        }
        requests.push(request)
        const { data, status = 200 } = respond(request)
        return new Response(JSON.stringify(data), {
          status,
          headers: { 'Content-Type': 'application/json' },
        })
      },
    },
  })
  return { supabase, requests }
}
function rows(out: unknown = outbound, inside: unknown = inbound) {
  return client(({ url }) => {
    const direction = url.searchParams.get('direction')
    expect(['eq.in', 'eq.out']).toContain(direction)
    const value = direction === 'eq.in' ? inside : out
    return { data: value === null ? [] : [value] }
  })
}
async function subject() {
  const path = './flow-phrase-reply-store'
  return import(path)
}

describe('Flow phrase reply store: private event identity and parsing', () => {
  it('reads a bare legacy OUT only as legacy and retains its exact text', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const legacyIdentity = { ...identity, assistantProviderMessageId: 'c5-event-0001:assistant' }
    const { supabase, requests } = rows({
      ...outbound,
      provider_message_id: legacyIdentity.assistantProviderMessageId,
      content: 'Resposta antiga.',
      raw_payload: { request_id: 'request-original', conversation_id: 'flow' },
    })
    expect(
      await createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(legacyIdentity),
    ).toEqual({ kind: 'legacy', message: { ...message, content: 'Resposta antiga.' } })
    expect(requests).toHaveLength(2)
    expect(
      requests
        .find(({ url }) => url.searchParams.get('direction') === 'eq.out')
        ?.url.searchParams.get('provider_message_id'),
    ).toBe('eq.c5-event-0001:assistant')
  })

  it.each([
    null,
    [],
    ['historic'],
    false,
    0,
    'historic',
  ])('preserves legacy raw compatibility without using it as cursor proof: %j', async (raw) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase, requests } = rows({ ...outbound, raw_payload: raw })
    expect(await createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity)).toEqual({
      kind: 'legacy',
      message: { ...message, requestId: 'request-unavailable' },
    })
    expect(requests.map(({ url }) => url.pathname)).toEqual([
      '/rest/v1/messages',
      '/rest/v1/messages',
    ])
  })

  it('never accepts a C5 namespace on a bare legacy OUT', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const legacyIdentity = { ...identity, assistantProviderMessageId: 'c5-event-0001:assistant' }
    const { supabase } = rows({
      ...outbound,
      provider_message_id: legacyIdentity.assistantProviderMessageId,
    })
    await expect(
      createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(legacyIdentity),
    ).rejects.toThrow()
  })

  it('refuses publishing new C5 under a bare legacy OUT before any RPC', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase, requests } = client(() => ({
      data: { action: 'committed', message: committedRpcMessage },
    }))
    await expect(
      createSupabaseFlowPhraseReplyStore(supabase).commitReply({
        ...commit,
        assistantProviderMessageId: 'c5-event-0001:assistant',
      }),
    ).rejects.toThrow()
    expect(requests).toHaveLength(0)
  })

  it('loads the requested legacy-IN event without reading the current cursor or exposing raw fields', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase, requests } = rows()
    const store = createSupabaseFlowPhraseReplyStore(supabase)
    expect(requests).toHaveLength(0)
    expect(await store.loadEventReply(identity)).toEqual({ kind: 'c5', message, receipt })
    expect(requests).toHaveLength(2)
    expect(requests.map(({ url }) => url.searchParams.get('direction')).sort()).toEqual([
      'eq.in',
      'eq.out',
    ])
    for (const { url, method } of requests) {
      expect(method).toBe('GET')
      expect(url.pathname).toBe('/rest/v1/messages')
      expect(url.searchParams.get('user_id')).toBe(`eq.${owner}`)
      expect(url.searchParams.get('provider')).toBe('eq.mobile_flow')
      expect(url.searchParams.has('limit')).toBe(false)
      expect(url.searchParams.has('order')).toBe(false)
      expect(url.searchParams.get('provider_message_id')).toBe(
        url.searchParams.get('direction') === 'eq.in'
          ? `eq.${identity.inboundProviderMessageId}`
          : `eq.${identity.assistantProviderMessageId}`,
      )
    }
  })

  it('classifies a completed legacy reply with no namespace separately', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = rows({ ...outbound, raw_payload: { request_id: 'request-original' } })
    expect(await createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity)).toEqual({
      kind: 'legacy',
      message,
    })
  })

  it('returns null only for real event absence, including a removed IN and OUT', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    for (const inside of [inbound, null]) {
      const { supabase } = rows(null, inside)
      expect(await createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity)).toBeNull()
    }
  })

  for (const direction of ['in', 'out'] as const) {
    it.each([
      false,
      0,
      '',
    ])(`rejects a malformed ${direction} row %s rather than treating it as absent`, async (bad) => {
      const { createSupabaseFlowPhraseReplyStore } = await subject()
      const { supabase } = direction === 'in' ? rows(null, bad) : rows(bad, inbound)
      await expect(
        createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity),
      ).rejects.toThrow()
    })
  }

  it('rejects an orphan OUT instead of replaying after its real inbound disappeared', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = rows(outbound, null)
    await expect(
      createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity),
    ).rejects.toThrow()
  })

  it.each([
    { id: '00000000-0000-0000-0000-00000000c512' },
    { user_id: '00000000-0000-0000-0000-00000000c502' },
    { content: 'Outro corpo sob a mesma chave' },
    { provider: 'whatsapp' },
    { role: 'assistant' },
  ])('rejects an inbound identity mismatch %j', async (change) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = rows(outbound, { ...inbound, ...change })
    await expect(
      createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity),
    ).rejects.toThrow()
  })

  it.each([
    null,
    { ...namespace, schema: 'unknown' },
    { ...namespace, extra: true },
    { ...namespace, cursor_revision: 1 },
    { ...namespace, previous_anchor_assistant_id: assistantId },
    { ...namespace, cursor: { ...cursor, userId: 'other-owner' } },
    { ...namespace, cursor: { ...cursor, catalogVersion: 'unknown' } },
    { ...namespace, cursor: { ...cursor, usedTextKeys: [textKey, textKey] } },
    {
      ...namespace,
      cursor: { ...cursor, lastTextKey: 'a'.repeat(64), usedTextKeys: ['a'.repeat(64)] },
    },
    { ...namespace, receipt: { ...receipt, eventKey: `${eventKey}-other` } },
    {
      ...namespace,
      receipt: { ...receipt, selection: { ...receipt.selection, foodCanonicalName: 'arroz' } },
    },
  ])('rejects a present corrupt namespace instead of treating it as legacy: %j', async (bad) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = rows({
      ...outbound,
      raw_payload: { ...outbound.raw_payload, flow_phrase_v1: bad },
    })
    await expect(
      createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity),
    ).rejects.toThrow()
  })

  it('rejects a changed rendered suffix despite an otherwise valid stored receipt', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = rows({ ...outbound, content: 'Status sem a frase armazenada.' })
    await expect(
      createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity),
    ).rejects.toThrow()
  })

  it('preserves lookup errors instead of returning event absence', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({
      status: 500,
      data: { code: 'P0001', message: 'synthetic failure' },
    }))
    await expect(
      createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity),
    ).rejects.toThrow()
  })

  it('accepts a selected phrase whose last successful ordinal reached MAX_SAFE_INTEGER', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const maxNamespace = { ...namespace, cursor: { ...cursor, ordinal: Number.MAX_SAFE_INTEGER } }
    const { supabase } = rows({
      ...outbound,
      raw_payload: { ...outbound.raw_payload, flow_phrase_v1: maxNamespace },
    })
    expect(await createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity)).toEqual({
      kind: 'c5',
      message,
      receipt,
    })
  })

  it.each([
    { ordinal: 0, reason: 'unsupported_language', lastTextKey: null, usedTextKeys: [] },
    {
      ordinal: Number.MAX_SAFE_INTEGER,
      reason: 'rotation_exhausted',
      lastTextKey: textKey,
      usedTextKeys: [textKey],
    },
  ])('preserves a valid empty receipt for %s', async (state) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const emptyReceipt = {
      ...receipt,
      selection: {
        phrase: null,
        phraseId: null,
        sourceText: null,
        foodCanonicalName: null,
        reason: state.reason,
      },
    }
    const emptyNamespace = {
      ...namespace,
      cursor: {
        ...cursor,
        ordinal: state.ordinal,
        lastTextKey: state.lastTextKey,
        usedTextKeys: state.usedTextKeys,
      },
      receipt: emptyReceipt,
    }
    const { supabase } = rows({
      ...outbound,
      content: 'Official status without an incentive.',
      raw_payload: { ...outbound.raw_payload, flow_phrase_v1: emptyNamespace },
    })
    expect(await createSupabaseFlowPhraseReplyStore(supabase).loadEventReply(identity)).toEqual({
      kind: 'c5',
      message: { ...message, content: 'Official status without an incentive.' },
      receipt: emptyReceipt,
    })
  })
})

describe('Flow phrase reply store: RPC cursor and commit', () => {
  it.each([
    '9',
    '10',
    '9223372036854775807',
  ])('preserves canonical revision %s without Number conversion', async (revision) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const data = { anchor_assistant_id: assistantId, cursor_revision: revision, cursor }
    const { supabase, requests } = client(() => ({ data }))
    expect(await createSupabaseFlowPhraseReplyStore(supabase).loadCursor(owner)).toEqual({
      anchorAssistantId: assistantId,
      cursorRevision: revision,
      cursor,
    })
    expect(requests[0].url.pathname).toBe('/rest/v1/rpc/read_flow_phrase_cursor')
    expect(requests[0].body).toEqual({ p_user_id: owner })
  })

  it('accepts initial absence only as revision zero with no anchor and no cursor', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({
      data: { anchor_assistant_id: null, cursor_revision: '0', cursor: null },
    }))
    expect(await createSupabaseFlowPhraseReplyStore(supabase).loadCursor(owner)).toEqual({
      anchorAssistantId: null,
      cursorRevision: '0',
      cursor: null,
    })
  })

  it.each([
    0,
    1,
    '01',
    '+1',
    ' 1',
    '1e1',
    '-1',
    '1.5',
    '9223372036854775808',
  ])('rejects malformed revision %s', async (revision) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({
      data: { anchor_assistant_id: assistantId, cursor_revision: revision, cursor },
    }))
    await expect(createSupabaseFlowPhraseReplyStore(supabase).loadCursor(owner)).rejects.toThrow()
  })

  it.each([
    { anchor_assistant_id: assistantId, cursor_revision: '0', cursor },
    { anchor_assistant_id: null, cursor_revision: '1', cursor: null },
    { anchor_assistant_id: assistantId, cursor_revision: '1', cursor: { ...cursor, ordinal: -1 } },
    {
      anchor_assistant_id: assistantId,
      cursor_revision: '1',
      cursor: { ...cursor, ordinal: 9007199254740992 },
    },
    {
      anchor_assistant_id: assistantId,
      cursor_revision: '1',
      cursor: { ...cursor, replayByEventKey: {} },
    },
  ])('rejects cursor/anchor incoherence %j without initializing', async (data) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({ data }))
    await expect(createSupabaseFlowPhraseReplyStore(supabase).loadCursor(owner)).rejects.toThrow()
  })

  it('passes all sixteen literal commit parameters including the real legacy IN UUID', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase, requests } = client(() => ({
      data: { action: 'committed', message: committedRpcMessage },
    }))
    expect(await createSupabaseFlowPhraseReplyStore(supabase).commitReply(commit)).toEqual({
      action: 'committed',
      message: committedMessage,
    })
    expect(requests).toHaveLength(1)
    expect(requests[0].method).toBe('POST')
    expect(requests[0].url.pathname).toBe('/rest/v1/rpc/commit_flow_phrase_reply')
    expect(requests[0].body).toEqual({
      p_user_id: owner,
      p_event_key: eventKey,
      p_expected_inbound_id: inboundId,
      p_inbound_provider_message_id: 'c5-event-0001',
      p_assistant_provider_message_id: `${eventKey}/assistant`,
      p_expected_inbound_content: 'Status do dia',
      p_expected_request_id: 'request-new',
      p_expected_attempt_started_at: '2026-10-09T00:00:00.000Z',
      p_expected_anchor_assistant_id: null,
      p_expected_cursor_revision: '0',
      p_expected_cursor: null,
      p_next_cursor: cursor,
      p_receipt: receipt,
      p_content: outbound.content,
      p_created_at: '2026-10-09T00:00:00.000Z',
      p_metadata: commit.metadata,
    })
  })

  it('returns the official replay rather than comparing it to a newly prepared candidate', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({ data: { action: 'replay', message: rpcMessage } }))
    expect(
      await createSupabaseFlowPhraseReplyStore(supabase).commitReply({
        ...commit,
        content: 'Candidate after a changed locale/name',
      }),
    ).toEqual({ action: 'replay', message })
  })

  it.each([
    {
      ...committedRpcMessage,
      raw_payload: { ...committedRpcMessage.raw_payload, request_id: 'another-request' },
    },
    { ...committedRpcMessage, content: `A different status.\n\n${receipt.selection.phrase}` },
  ])('rejects a committed result that does not describe this publication %j', async (bad) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({ data: { action: 'committed', message: bad } }))
    await expect(createSupabaseFlowPhraseReplyStore(supabase).commitReply(commit)).rejects.toThrow()
  })

  it.each([
    'cursor_conflict',
    'attempt_conflict',
    'event_conflict',
  ])('preserves the explicit action %s', async (action) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({ data: { action } }))
    expect(await createSupabaseFlowPhraseReplyStore(supabase).commitReply(commit)).toEqual({
      action,
    })
  })

  it.each([
    null,
    { action: 'unknown' },
    { action: 'cursor_conflict', message: rpcMessage },
    { action: 'committed', message: { ...rpcMessage, delivery_status: 'unknown' } },
    { action: 'committed', message: { ...rpcMessage, raw_payload: {} } },
    { action: 'replay', message: { ...rpcMessage, direction: 'in' } },
  ])('rejects malformed commit output %j without treating it as a CAS conflict', async (data) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({ data }))
    await expect(createSupabaseFlowPhraseReplyStore(supabase).commitReply(commit)).rejects.toThrow()
  })

  it('preserves read RPC errors instead of returning an initial cursor', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({
      status: 500,
      data: { code: 'P0001', message: 'synthetic cursor corruption' },
    }))
    await expect(createSupabaseFlowPhraseReplyStore(supabase).loadCursor(owner)).rejects.toThrow()
  })

  it('preserves commit RPC errors instead of returning a cursor conflict', async () => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const { supabase } = client(() => ({
      status: 500,
      data: { code: '22003', message: 'synthetic overflow' },
    }))
    await expect(createSupabaseFlowPhraseReplyStore(supabase).commitReply(commit)).rejects.toThrow()
  })
})

describe('Flow phrase reply store: late failure fence', () => {
  it.each([
    'owned',
    'completed',
    'new-request',
    'new-attempt',
    'new-uuid',
  ])('fails only the owned UUID attempt: %s', async (scenario) => {
    const { createSupabaseFlowPhraseReplyStore } = await subject()
    const row = structuredClone({
      ...inbound,
      delivery_status: 'processing',
      delivery_error: null as unknown,
    })
    if (scenario === 'completed') row.delivery_status = 'completed'
    if (scenario === 'new-request') row.raw_payload.request_id = 'new-request'
    if (scenario === 'new-attempt') row.raw_payload.attempt_started_at = '2026-10-09T00:01:00.000Z'
    if (scenario === 'new-uuid') row.id = '00000000-0000-0000-0000-00000000c512'
    const before = structuredClone(row)
    const expectedFilters = {
      id: `eq.${inboundId}`,
      user_id: `eq.${owner}`,
      provider: 'eq.mobile_flow',
      direction: 'eq.in',
      provider_message_id: 'eq.c5-event-0001',
      delivery_status: 'eq.processing',
      'raw_payload->>request_id': 'eq.request-original',
      'raw_payload->>attempt_started_at': 'eq.2026-10-09T00:00:00.000Z',
    }
    const actualValues: Record<string, string> = {
      id: row.id,
      user_id: row.user_id,
      provider: row.provider,
      direction: row.direction,
      provider_message_id: row.provider_message_id,
      delivery_status: row.delivery_status,
      'raw_payload->>request_id': row.raw_payload.request_id,
      'raw_payload->>attempt_started_at': row.raw_payload.attempt_started_at,
    }
    const { supabase, requests } = client(({ url, body, method }) => {
      expect(method).toBe('PATCH')
      for (const [column, filter] of Object.entries(expectedFilters)) {
        expect(url.searchParams.get(column)).toBe(filter)
      }
      expect(body).toEqual({
        delivery_status: 'failed',
        delivery_error: { code: 'flow_provider_failed' },
      })
      const matches = Object.entries(expectedFilters).every(
        ([column]) => url.searchParams.get(column) === `eq.${actualValues[column]}`,
      )
      if (matches) Object.assign(row, body)
      return { data: matches ? [{ id: row.id }] : [] }
    })
    const changed = await createSupabaseFlowPhraseReplyStore(supabase).failOwnedAttempt({
      userId: owner,
      inboundId,
      inboundProviderMessageId: 'c5-event-0001',
      expectedRequestId: 'request-original',
      expectedAttemptStartedAt: '2026-10-09T00:00:00.000Z',
      errorCode: 'flow_provider_failed',
    })
    expect(changed).toBe(scenario === 'owned')
    expect(requests).toHaveLength(1)
    expect(row).toEqual(
      scenario === 'owned'
        ? { ...before, delivery_status: 'failed', delivery_error: { code: 'flow_provider_failed' } }
        : before,
    )
    expect(row.raw_payload).toEqual(before.raw_payload)
  })
})

describe('Flow transition adapter: optional generation fence', () => {
  it.each([
    'legacy-default',
    'owned-uuid',
    'recreated-uuid',
  ] as const)('retains existing predicates and conditionally fences id: %s', async (scenario) => {
    const change = {
      from: 'processing' as const,
      to: 'processing' as const,
      requestId: 'request-original',
      expectedRequestId: 'request-original',
      expectedAttemptStartedAt: nowAttempt,
      attempt: { startedAt: nowAttempt, providerStartedAt: nowAttempt, retryStartedAt: [] },
      ...(scenario === 'legacy-default' ? {} : { expectedInboundId: inboundId }),
    }
    const currentId =
      scenario === 'recreated-uuid' ? '00000000-0000-0000-0000-00000000c512' : inboundId
    const { supabase, requests } = client(({ url, method, body }) => {
      expect(method).toBe('PATCH')
      expect(url.pathname).toBe('/rest/v1/messages')
      const filters = {
        user_id: owner,
        provider: 'mobile_flow',
        provider_message_id: identity.inboundProviderMessageId,
        direction: 'in',
        delivery_status: 'processing',
        'raw_payload->>request_id': 'request-original',
        'raw_payload->>attempt_started_at': nowAttempt,
      }
      for (const [column, value] of Object.entries(filters))
        expect(url.searchParams.get(column)).toBe(`eq.${value}`)
      expect(url.searchParams.get('select')).toBe('id')
      if (scenario === 'legacy-default') expect(url.searchParams.has('id')).toBe(false)
      else expect(url.searchParams.get('id')).toBe(`eq.${inboundId}`)
      expect(body).toEqual({
        delivery_status: 'processing',
        delivery_error: null,
        raw_payload: {
          request_id: 'request-original',
          conversation_id: 'flow',
          attempt_started_at: nowAttempt,
          provider_started_at: nowAttempt,
          retry_started_at: [],
        },
      })
      const matches =
        !url.searchParams.has('id') || url.searchParams.get('id') === `eq.${currentId}`
      return { data: matches ? [{ id: currentId }] : [] }
    })
    expect(
      await createSupabaseFlowChatStore(supabase).transitionInbound(
        owner,
        identity.inboundProviderMessageId,
        change,
      ),
    ).toBe(scenario !== 'recreated-uuid')
    expect(requests).toHaveLength(1)
  })
})
