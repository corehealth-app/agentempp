import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { snapshotSignupCompletionEpoch } from './signup-completion-intent'
import { createSupabaseSignupCompletionIntentSource } from './supabase-signup-completion-intent'

const OWNER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const Q = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const ID = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const E0 = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
const OTHER = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
const K = `osc1:${ID}`
const WHEN = '2026-10-21T14:00:00.123456Z'
const wire = () => ({
  ownerID: OWNER,
  preparationID: Q,
  intentID: ID,
  requestKey: K,
  epoch: E0,
  issuedAt: WHEN,
})
const receipt = () => ({
  userId: OWNER,
  preparationId: Q,
  intentId: ID,
  requestKey: K,
  epoch: E0,
  issuedAt: WHEN,
})
const reply = (data: unknown) => ({ data, error: null })
const preparation = () => ({ userId: OWNER, preparationId: Q })
const verification = () => ({ userId: OWNER, intentId: ID, requestKey: K })
type Method = 'begin' | 'resolve' | 'verify'
const methods: Method[] = ['begin', 'resolve', 'verify']
const status = { begin: 'issued', resolve: 'resolved', verify: 'verified' }
function harness(data: unknown) {
  const rpc = vi.fn().mockResolvedValue(reply(data))
  return {
    rpc,
    source: createSupabaseSignupCompletionIntentSource({ rpc } as unknown as ServiceClient),
  }
}
function call(
  source: ReturnType<typeof createSupabaseSignupCompletionIntentSource>,
  method: Method,
) {
  return method === 'verify' ? source.verify(verification()) : source[method](preparation())
}

describe('positive signup intent RPC adapter', () => {
  it.each([
    'issued',
    'reused',
  ])('accepts begin %s without another observation or HTTP ledger', async (state) => {
    const { source, rpc } = harness({ status: state, intent: wire() })
    const result = await source.begin(preparation())
    expect(result).toEqual(receipt())
    expect(Object.isFrozen(result)).toBe(true)
    expect(rpc.mock.calls).toEqual([
      [
        'begin_mobile_signup_completion_intent',
        {
          p_user_id: OWNER,
          p_preparation_id: Q,
        },
      ],
    ])
  })

  it('resolves an existing receipt with one read and no issuance', async () => {
    const { source, rpc } = harness({ status: 'resolved', intent: wire() })
    await expect(source.resolve(preparation())).resolves.toEqual(receipt())
    expect(rpc.mock.calls).toEqual([
      [
        'resolve_mobile_signup_completion_intent',
        {
          p_user_id: OWNER,
          p_preparation_id: Q,
        },
      ],
    ])
  })

  it('keeps an absent resolution distinct and never issues or observes', async () => {
    const { source, rpc } = harness({ status: 'absent' })
    await expect(source.resolve(preparation())).resolves.toBeNull()
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc.mock.calls[0]?.[0]).toBe('resolve_mobile_signup_completion_intent')
  })

  it('verifies only the original owner/receipt/key and returns E0', async () => {
    const { source, rpc } = harness({ status: 'verified', intent: wire() })
    await expect(source.verify(verification())).resolves.toEqual(receipt())
    expect(rpc.mock.calls).toEqual([
      [
        'verify_mobile_signup_completion_intent',
        {
          p_user_id: OWNER,
          p_intent_id: ID,
          p_request_key: K,
        },
      ],
    ])
  })

  it.each(methods)('%s refuses stale rather than renewing the identity', async (method) => {
    const { source, rpc } = harness({ status: 'forbidden', reason: 'stale_epoch' })
    await expect(call(source, method)).rejects.toMatchObject({
      status: 409,
      code: 'mobile_signup_strength_stale_epoch',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('maps a foreign or mixed intent to a generic conflict', async () => {
    const { source, rpc } = harness({ status: 'forbidden', reason: 'invalid_intent' })
    await expect(source.verify(verification())).rejects.toMatchObject({
      status: 409,
      code: 'mobile_signup_completion_invalid_intent',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it.each(
    methods,
  )('%s rejects extra fields, wrong statuses and unknown refusals', async (method) => {
    for (const data of [
      null,
      [],
      { status: status[method], intent: wire(), extra: true },
      { status: status[method], intent: { ...wire(), extra: true } },
      { status: 'forbidden', reason: 'unknown' },
      { status: 'invented', intent: wire() },
    ]) {
      const { source, rpc } = harness(data)
      await expect(call(source, method)).rejects.toMatchObject({ status: 500 })
      expect(rpc).toHaveBeenCalledTimes(1)
    }
  })

  it.each([
    ['begin', { ...wire(), ownerID: OTHER }],
    ['begin', { ...wire(), preparationID: OTHER }],
    ['resolve', { ...wire(), ownerID: OTHER }],
    ['resolve', { ...wire(), preparationID: OTHER }],
    ['verify', { ...wire(), ownerID: OTHER }],
    ['verify', { ...wire(), intentID: OTHER }],
    ['verify', { ...wire(), requestKey: `osc1:${OTHER}` }],
  ] as const)('%s rejects a mixed wire identity', async (method, intent) => {
    const { source, rpc } = harness({ status: status[method], intent })
    await expect(call(source, method)).rejects.toMatchObject({ status: 500 })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it.each([
    '2026-02-30T14:00:00.123456Z',
    '2025-02-29T14:00:00.123456Z',
    '2026-10-21T24:00:00.123456Z',
    '2026-10-21T14:00:60.123456Z',
    '0000-01-01T00:00:00.123456Z',
    '2026-10-21T14:00:00.123Z',
    '2026-10-21T14:00:00.123456+00:00',
  ])('rejects invalid original UTC6 %s', async (issuedAt) => {
    const { source } = harness({ status: 'verified', intent: { ...wire(), issuedAt } })
    await expect(source.verify(verification())).rejects.toMatchObject({ status: 500 })
  })

  it('keeps a leap date and microseconds exact', async () => {
    const issuedAt = '2024-02-29T23:59:59.999999Z'
    const { source } = harness({ status: 'verified', intent: { ...wire(), issuedAt } })
    await expect(source.verify(verification())).resolves.toMatchObject({ issuedAt })
  })

  it('captures caller primitives and RPC receiver before the first await', async () => {
    let release!: (value: ReturnType<typeof reply>) => void
    const pendingWire = new Promise<ReturnType<typeof reply>>((resolve) => {
      release = resolve
    })
    const client = {
      original: true,
      rpc: vi.fn(function (this: { original: boolean }) {
        expect(this.original).toBe(true)
        return pendingWire
      }),
    }
    const source = createSupabaseSignupCompletionIntentSource(client as unknown as ServiceClient)
    const input = preparation()
    const pending = source.begin(input)
    input.userId = OTHER
    input.preparationId = OTHER
    client.rpc = vi.fn()
    const response = { status: 'issued', intent: wire() }
    release(reply(response))
    const result = await pending
    response.intent.epoch = OTHER
    response.intent.requestKey = `osc1:${OTHER}`
    expect(result).toEqual(receipt())
    expect(Object.isFrozen(result)).toBe(true)
    expect(client.rpc).not.toHaveBeenCalled()
  })

  it('compares UUID spelling semantically and retains the requested tuple spelling', async () => {
    const { source } = harness({ status: 'verified', intent: wire() })
    await expect(
      source.verify({ ...verification(), userId: OWNER.toUpperCase(), intentId: ID.toUpperCase() }),
    ).resolves.toEqual({ ...receipt(), userId: OWNER.toUpperCase(), intentId: ID.toUpperCase() })
  })

  it('rejects invalid inputs before RPC', async () => {
    const { source, rpc } = harness({ status: 'issued', intent: wire() })
    await expect(source.begin({ userId: 'invalid', preparationId: Q })).rejects.toMatchObject({
      status: 500,
    })
    await expect(source.resolve({ userId: OWNER, preparationId: 'invalid' })).rejects.toMatchObject(
      { status: 500 },
    )
    await expect(
      source.verify({ ...verification(), requestKey: 'legacy-key' }),
    ).rejects.toMatchObject({ status: 500 })
    expect(rpc).not.toHaveBeenCalled()
  })

  it('does not expose a thrown backend message or retry it', async () => {
    const rpc = vi.fn().mockRejectedValue(new Error('private-secret-backend-message'))
    const source = createSupabaseSignupCompletionIntentSource({ rpc } as unknown as ServiceClient)
    const error = await source.begin(preparation()).catch((failure: unknown) => failure)
    expect(error).toMatchObject({
      status: 500,
      code: 'mobile_signup_completion_intent_unavailable',
    })
    expect(String(error)).not.toContain('private-secret')
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it.each([
    null,
    [],
    { data: { status: 'issued', intent: wire() } },
    { data: { status: 'issued', intent: wire() }, error: { message: 'private-secret' } },
  ])('rejects an invalid backend envelope without a fallback (%j)', async (envelope) => {
    const rpc = vi.fn().mockResolvedValue(envelope)
    const source = createSupabaseSignupCompletionIntentSource({ rpc } as unknown as ServiceClient)
    await expect(source.begin(preparation())).rejects.toMatchObject({ status: 500 })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})

describe('request-local positive intent snapshot', () => {
  it('captures E0 before a producer can alter the receipt during preparation', () => {
    const value = receipt()
    const epoch = snapshotSignupCompletionEpoch(value, verification())
    value.epoch = OTHER
    expect(epoch).toBe(E0)
  })
  it.each([
    { userId: OTHER },
    { intentId: OTHER },
    { requestKey: `osc1:${OTHER}` },
    { epoch: '' },
  ])('rejects a mixed or empty receipt (%j)', (change) => {
    expect(() =>
      snapshotSignupCompletionEpoch({ ...receipt(), ...change }, verification()),
    ).toThrow()
  })
})
