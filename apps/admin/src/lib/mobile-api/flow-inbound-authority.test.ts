import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createFlowInboundAuthoritySource } from './flow-inbound-authority'
import { MobileApiError, mobileErrorResponse } from './http'

const OWNER = '00000000-0000-0000-0000-00000000f171'
const OTHER = '00000000-0000-0000-0000-00000000f172'
const ADMISSION = '00000000-0000-0000-0000-00000000a171'
const EPOCH = '00000000-0000-0000-0000-00000000e171'
const INBOUND = '00000000-0000-0000-0000-00000000b171'
const KEY = 's17j-turn-0001'
const TEXT = 'Cafe\u0301  \nleg press'
const HASH = 'fa2f13452e98f0c91db4bf3bf412c0c8edb114e3134ff1c3554edccc38d9215c'
const STARTED = '2026-10-15T12:00:00.123Z'
const REQUEST = 'request-s17j-0001'
const ADMIT = 'admit_workout_strength_request'
const ACCESS = 'access_workout_strength_flow_inbound'
type RpcReply = { data: unknown; error: { message: string } | null }

function admission(overrides: Record<string, unknown> = {}) {
  return {
    ownerID: OWNER,
    admissionID: ADMISSION,
    epoch: EPOCH,
    requestNamespace: 'mobile_flow_turn',
    requestKey: KEY,
    requestHash: HASH,
    admittedAt: '2026-10-15T11:59:59.123456Z',
    ...overrides,
  }
}

function inbound(overrides: Record<string, unknown> = {}) {
  return {
    id: INBOUND,
    direction: 'in',
    content: TEXT,
    delivery_status: 'processing',
    raw_payload: {
      request_id: REQUEST,
      conversation_id: 'flow',
      attempt_started_at: STARTED,
      provider_started_at: null,
      retry_started_at: [],
    },
    created_at: STARTED,
    ...overrides,
  }
}

function setup(...replies: unknown[]) {
  const rpc = vi.fn(
    async (_name: string, _parameters: Record<string, unknown>): Promise<RpcReply> => {
      if (replies.length === 0) throw new Error('unexpected RPC')
      return { data: replies.shift(), error: null }
    },
  )
  const client = { rpc }
  const source = createFlowInboundAuthoritySource(client as unknown as ServiceClient)
  return { source, client, rpc }
}

const captureInput = () => ({ userId: OWNER, requestKey: KEY, text: TEXT })
const persistInput = () => ({ requestId: REQUEST, startedAt: STARTED })
const admitted = () => ({ status: 'admitted', admission: admission() })

async function opaqueError(promise: Promise<unknown>, status: number, code: string) {
  let caught: unknown
  try {
    await promise
  } catch (error) {
    caught = error
  }
  expect(caught).toBeInstanceOf(MobileApiError)
  expect(caught).toMatchObject({ status, code, details: undefined })
  const response = mobileErrorResponse(caught as MobileApiError, REQUEST)
  const body = await response.json()
  expect(Object.keys(body.error).sort()).toEqual(['code', 'message', 'request_id'])
  expect(body.error.code).toBe(code)
  expect(JSON.stringify(body)).not.toContain(ADMISSION)
  expect(JSON.stringify(body)).not.toContain('private-debug')
  return caught
}

describe('S17J captured Flow inbound authority adapter (dormant)', () => {
  it.each([
    'admitted',
    'reused',
  ])('hashes exact UTF8 and preserves the original %s admission through probe and persist', async (status) => {
    const row = inbound()
    const { source, rpc } = setup(
      { status, admission: admission() },
      { status: 'unbound' },
      { status: 'inserted', inbound: row },
      { status: 'bound', inbound: row },
    )
    const handle = await source.capture(captureInput())
    expect(handle).toMatchObject({ ...captureInput(), admissionId: ADMISSION })
    expect(await handle.probe()).toEqual({ status: 'unbound' })
    expect(await handle.persist(persistInput())).toEqual({ status: 'inserted', inbound: row })
    expect(await handle.probe()).toEqual({ status: 'bound', inbound: row })
    expect(rpc.mock.calls).toEqual([
      [ADMIT, { p_user_id: OWNER, p_request_key: KEY, p_request_hash: HASH }],
      [
        ACCESS,
        {
          p_user_id: OWNER,
          p_admission_id: ADMISSION,
          p_text: TEXT,
          p_mode: 'probe',
          p_request_id: null,
          p_started_at: null,
        },
      ],
      [
        ACCESS,
        {
          p_user_id: OWNER,
          p_admission_id: ADMISSION,
          p_text: TEXT,
          p_mode: 'persist',
          p_request_id: REQUEST,
          p_started_at: STARTED,
        },
      ],
      [
        ACCESS,
        {
          p_user_id: OWNER,
          p_admission_id: ADMISSION,
          p_text: TEXT,
          p_mode: 'probe',
          p_request_id: null,
          p_started_at: null,
        },
      ],
    ])
  })

  it('compares owner UUIDs by identity while keeping keys and text literal', async () => {
    const { source, rpc } = setup(admitted(), { status: 'unbound' })
    const handle = await source.capture({ ...captureInput(), userId: OWNER.toUpperCase() })
    await handle.probe()
    expect(rpc.mock.calls[1]?.[1].p_user_id).toBe(OWNER.toUpperCase())
    expect(handle.requestKey).toBe(KEY)
    expect(handle.text).toBe(TEXT)
  })

  it('captures the original scalars, RPC function and receiver before awaiting admission', async () => {
    const { source, client, rpc } = setup()
    let deliver = (_value: RpcReply) => {}
    rpc.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          deliver = resolve
        }),
    )
    const input = captureInput()
    const pending = source.capture(input)
    input.userId = OTHER
    input.requestKey = 's17j-other-0002'
    input.text = 'different text'
    client.rpc = vi.fn(async () => {
      throw new Error('changed client RPC')
    })
    deliver({ data: admitted(), error: null })
    const handle = await pending
    rpc.mockResolvedValueOnce({ data: { status: 'unbound' }, error: null })
    expect(Reflect.set(handle, 'admissionId', OTHER)).toBe(false)
    expect(await handle.probe()).toEqual({ status: 'unbound' })
    expect(handle.userId).toBe(OWNER)
    expect(handle.text).toBe(TEXT)
    expect(rpc.mock.contexts).toEqual([client, client])
    expect(rpc.mock.calls[1]?.[1]).toMatchObject({
      p_user_id: OWNER,
      p_admission_id: ADMISSION,
      p_text: TEXT,
    })
    expect(client.rpc).not.toHaveBeenCalled()
  })

  it.each([
    'inserted',
    'reused',
  ] as const)('keeps %s distinct even with identical request/clock', async (status) => {
    // S17I creates a fresh IN with the exact ISO3 attempt clock. Existing rows may use ISO6.
    const row = inbound({
      created_at: status === 'inserted' ? STARTED : '2026-10-15T12:00:00.123456Z',
    })
    const { source } = setup(admitted(), { status, inbound: row })
    const handle = await source.capture(captureInput())
    expect(await handle.persist(persistInput())).toEqual({ status, inbound: row })
  })

  it.each([
    ['different creation clock', { created_at: '2026-10-15T12:00:01.123Z' }],
    ['ISO6 creation clock', { created_at: '2026-10-15T12:00:00.123000Z' }],
    ['failed status', { delivery_status: 'failed' }],
    ['nullable status', { delivery_status: null }],
    [
      'different request ID',
      { raw_payload: { ...inbound().raw_payload, request_id: 'other-request-0002' } },
    ],
    [
      'different conversation',
      { raw_payload: { ...inbound().raw_payload, conversation_id: 'other' } },
    ],
    [
      'different attempt clock',
      { raw_payload: { ...inbound().raw_payload, attempt_started_at: '2026-10-15T12:00:01.123Z' } },
    ],
    [
      'provider already started',
      { raw_payload: { ...inbound().raw_payload, provider_started_at: STARTED } },
    ],
    [
      'retry already started',
      { raw_payload: { ...inbound().raw_payload, retry_started_at: [STARTED] } },
    ],
    ['last retry key present', { raw_payload: { ...inbound().raw_payload, last_retry_at: null } }],
    [
      'missing initial field',
      {
        raw_payload: {
          request_id: REQUEST,
          conversation_id: 'flow',
          attempt_started_at: STARTED,
          retry_started_at: [],
        },
      },
    ],
    [
      'operational JSON instead of initial values',
      { raw_payload: { request_id: { arbitrary: true } } },
    ],
  ])('refuses a fresh inserted IN with contradictory %s', async (_scenario, overrides) => {
    const { source, rpc } = setup(admitted(), { status: 'inserted', inbound: inbound(overrides) })
    const handle = await source.capture(captureInput())
    await opaqueError(
      handle.persist(persistInput()),
      500,
      'flow_request_authority_invalid_response',
    )
    expect(rpc).toHaveBeenCalledTimes(2)
  })

  it('preserves operational JSON values and a nullable delivery status without reinterpretation', async () => {
    const row = inbound({
      delivery_status: null,
      raw_payload: {
        request_id: { unusual: [true, 3, null] },
        conversation_id: false,
        attempt_started_at: 42,
        provider_started_at: ['not-a-time'],
        retry_started_at: { nested: 'value' },
        last_retry_at: null,
      },
    })
    const { source } = setup(admitted(), { status: 'bound', inbound: row })
    const handle = await source.capture(captureInput())
    expect(await handle.probe()).toEqual({ status: 'bound', inbound: row })
  })

  it('preserves all nested JSON keys rather than silently filtering operational values', async () => {
    const raw = JSON.parse('{"request_id":{"__proto__":{"marker":"kept"},"constructor":17}}')
    const row = inbound({ raw_payload: raw })
    const { source } = setup(admitted(), { status: 'bound', inbound: row })
    const handle = await source.capture(captureInput())
    const result = await handle.probe()
    expect(result.status).toBe('bound')
    if (result.status !== 'bound') throw new Error('expected bound')
    expect(JSON.stringify(result.inbound.raw_payload)).toBe(
      '{"request_id":{"__proto__":{"marker":"kept"},"constructor":17}}',
    )
    expect(Object.getPrototypeOf(result.inbound.raw_payload)).toBe(Object.prototype)
  })

  it('captures persist arguments before awaiting its reply and never borrows a mutated attempt', async () => {
    const { source, rpc } = setup(admitted())
    const handle = await source.capture(captureInput())
    let deliver = (_value: RpcReply) => {}
    rpc.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          deliver = resolve
        }),
    )
    const input = persistInput()
    const pending = handle.persist(input)
    input.requestId = 'request-other-0002'
    input.startedAt = '2026-10-16T12:00:00.000Z'
    deliver({ data: { status: 'inserted', inbound: inbound() }, error: null })
    expect(await pending).toMatchObject({ status: 'inserted', inbound: { created_at: STARTED } })
    expect(rpc.mock.calls[1]?.[1]).toMatchObject({ p_request_id: REQUEST, p_started_at: STARTED })
  })

  it('never adopts a replacement UUID or unbound downgrade after observing the original IN', async () => {
    for (const next of [
      { status: 'bound', inbound: inbound({ id: OTHER }) },
      { status: 'unbound' },
    ]) {
      const { source, rpc } = setup(admitted(), { status: 'bound', inbound: inbound() }, next)
      const handle = await source.capture(captureInput())
      await handle.probe()
      await opaqueError(handle.probe(), 500, 'flow_request_authority_invalid_response')
      expect(rpc).toHaveBeenCalledTimes(3)
    }
  })

  it.each([
    { userId: 'wrong' },
    { requestKey: 'short' },
    { requestKey: `${KEY} ` },
    { text: '' },
    { text: 'x'.repeat(4001) },
    { authority: 'client-claim' },
  ])('rejects invalid local capture input before any RPC: %j', async (patch) => {
    const { source, rpc } = setup()
    await opaqueError(
      source.capture({ ...captureInput(), ...patch }),
      500,
      'flow_request_authority_invalid_input',
    )
    expect(rpc).not.toHaveBeenCalled()
  })

  it.each([
    '2026-02-30T12:00:00.123Z',
    '0000-01-01T00:00:00.000Z',
    '2026-10-15T12:00:00.123456Z',
    '2026-10-15T12:00:00Z',
    '2026-10-15T09:00:00.123-03:00',
    '+010000-01-01T00:00:00.000Z',
  ])('rejects persist clock %s without sending it', async (startedAt) => {
    const { source, rpc } = setup(admitted())
    const handle = await source.capture(captureInput())
    await opaqueError(
      handle.persist({ requestId: REQUEST, startedAt }),
      500,
      'flow_request_authority_invalid_input',
    )
    expect(rpc).toHaveBeenCalledOnce()
  })

  it.each([
    '0001-01-01T00:00:00.000Z',
    '9999-12-31T23:59:59.999Z',
  ])('preserves valid persist boundary clock %s', async (startedAt) => {
    const { source, rpc } = setup(admitted(), {
      status: 'inserted',
      inbound: inbound({
        created_at: startedAt,
        raw_payload: { ...inbound().raw_payload, attempt_started_at: startedAt },
      }),
    })
    const handle = await source.capture(captureInput())
    await handle.persist({ requestId: REQUEST, startedAt })
    expect(rpc.mock.calls[1]?.[1].p_started_at).toBe(startedAt)
  })

  it.each([
    'short',
    `${REQUEST} `,
    'request/invalid',
  ])('rejects persist request ID %s before RPC', async (requestId) => {
    const { source, rpc } = setup(admitted())
    const handle = await source.capture(captureInput())
    await opaqueError(
      handle.persist({ requestId, startedAt: STARTED }),
      500,
      'flow_request_authority_invalid_input',
    )
    expect(rpc).toHaveBeenCalledOnce()
  })

  it.each([
    null,
    [],
    { status: 'initialized' },
    { status: 'forbidden', reason: 'invalid_admission' },
    { status: 'admitted', admission: admission(), private: 'private-debug' },
    ...[
      { ownerID: OTHER },
      { requestKey: 'S17J-turn-0001' },
      { requestHash: '0'.repeat(64) },
      { requestNamespace: 'workout_ui' },
      { admissionID: 'wrong' },
      { epoch: 'wrong' },
      { admittedAt: STARTED },
      { admittedAt: '2026-02-30T12:00:00.123456Z' },
      { private: 'private-debug' },
    ].map((patch) => ({ status: 'admitted', admission: admission(patch) })),
  ])('rejects a malformed or mixed admission without exposing private wire: %j', async (reply) => {
    const { source, rpc } = setup(reply)
    await opaqueError(
      source.capture(captureInput()),
      500,
      'flow_request_authority_invalid_response',
    )
    expect(rpc).toHaveBeenCalledOnce()
  })

  it.each([
    { status: 'forbidden', reason: 'stale_epoch' },
    { status: 'conflict', reason: 'request_content_conflict' },
  ])('retains a refused admission reason internally and returns an opaque HTTP error: %j', async (reply) => {
    const { source, rpc } = setup(reply)
    const error = await opaqueError(
      source.capture(captureInput()),
      409,
      'flow_request_authority_conflict',
    )
    expect(error).toMatchObject({ outcome: reply.status, reason: reply.reason })
    expect(rpc).toHaveBeenCalledOnce()
  })

  it.each([
    'probe',
    'persist',
  ] as const)('keeps all five %s refusals distinct, with no fallback or retry', async (mode) => {
    for (const reply of [
      ...['invalid_admission', 'stale_epoch', 'unproved_inbound', 'inbound_mismatch'].map(
        (reason) => ({ status: 'forbidden', reason }),
      ),
      { status: 'conflict', reason: 'request_content_conflict' },
    ]) {
      const { source, rpc } = setup(admitted(), reply)
      const handle = await source.capture(captureInput())
      const error = await opaqueError(
        mode === 'probe' ? handle.probe() : handle.persist(persistInput()),
        409,
        'flow_request_authority_conflict',
      )
      expect(error).toMatchObject({ outcome: reply.status, reason: reply.reason })
      expect(rpc).toHaveBeenCalledTimes(2)
    }
  })

  it.each([
    { status: 'inserted', inbound: inbound() },
    { status: 'reused', inbound: inbound() },
    { status: 'unbound', inbound: inbound() },
    { status: 'forbidden', reason: 'stale_lifecycle' },
    { status: 'bound', inbound: inbound({ content: 'different text' }) },
    { status: 'bound', inbound: inbound({ direction: 'out' }) },
    { status: 'bound', inbound: inbound({ id: 'wrong' }) },
    { status: 'bound', inbound: inbound({ created_at: '2026-02-30T12:00:00.123Z' }) },
    { status: 'bound', inbound: inbound({ delivery_status: 7 }) },
    { status: 'bound', inbound: inbound({ raw_payload: { private: 'private-debug' } }) },
    { status: 'bound', inbound: inbound({ raw_payload: { request_id: Number.NaN } }) },
    { status: 'bound', inbound: inbound({ raw_payload: [] }) },
    { status: 'bound', inbound: inbound({ private: 'private-debug' }) },
  ])('rejects invalid probe wire/status without leaking it: %j', async (reply) => {
    const { source, rpc } = setup(admitted(), reply)
    const handle = await source.capture(captureInput())
    await opaqueError(handle.probe(), 500, 'flow_request_authority_invalid_response')
    expect(rpc).toHaveBeenCalledTimes(2)
  })

  it.each([
    { status: 'unbound' },
    { status: 'bound', inbound: inbound() },
  ])('rejects probe-only status in persist: %j', async (reply) => {
    const { source } = setup(admitted(), reply)
    const handle = await source.capture(captureInput())
    await opaqueError(
      handle.persist(persistInput()),
      500,
      'flow_request_authority_invalid_response',
    )
  })

  it.each([
    'capture',
    'probe',
    'persist',
  ] as const)('wraps transport failure in %s without exposing SQL text or retrying', async (stage) => {
    for (const rejection of [false, true]) {
      const { source, rpc } = setup(admitted())
      const handle = stage === 'capture' ? null : await source.capture(captureInput())
      if (rejection) rpc.mockRejectedValueOnce(new Error('private-debug SQL detail'))
      else rpc.mockResolvedValueOnce({ data: null, error: { message: 'private-debug SQL detail' } })
      let operation: Promise<unknown>
      if (stage === 'capture') operation = source.capture(captureInput())
      else {
        if (!handle) throw new Error('expected captured authority')
        operation = stage === 'probe' ? handle.probe() : handle.persist(persistInput())
      }
      await opaqueError(operation, 500, 'flow_request_authority_unavailable')
      expect(rpc).toHaveBeenCalledTimes(stage === 'capture' ? 1 : 2)
    }
  })
})
