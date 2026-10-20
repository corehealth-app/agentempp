import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createSupabaseSignupStrengthAuthoritySource } from './supabase-signup-strength-authority'

const OWNER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const EPOCH = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const ADMISSION = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const WHEN = '2026-10-20T10:00:00.123456Z'
const KEY = 'signup-original-key'
const HASH = 'd'.repeat(64)
const identity = () => ({ userId: OWNER, requestKey: KEY, requestHash: HASH, expectedEpoch: EPOCH })
const admission = () => ({
  ownerID: OWNER,
  epoch: EPOCH,
  admissionID: ADMISSION,
  requestKey: KEY,
  requestHash: HASH,
  admittedAt: WHEN,
})
const observed = () => ({
  status: 'observed',
  observation: { ownerID: OWNER, epoch: EPOCH, changedAt: WHEN },
})
const reply = (data: unknown) => ({ data, error: null, count: null, status: 200, statusText: 'OK' })

describe('concrete Supabase signup strength authority', () => {
  it('observes without admitting and preserves the caller owner spelling', async () => {
    const rpc = vi.fn().mockResolvedValue(reply(observed()))
    const source = createSupabaseSignupStrengthAuthoritySource({ rpc } as unknown as ServiceClient)
    await expect(source.observe({ userId: OWNER.toUpperCase() })).resolves.toEqual({
      userId: OWNER.toUpperCase(),
      epoch: EPOCH,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('observe_mobile_signup_strength_epoch', {
      p_user_id: OWNER.toUpperCase(),
    })
  })

  it.each([
    'admitted',
    'reused',
  ])('binds %s and verifies the same complete admission without re-observing', async (status) => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce(reply({ status, admission: admission() }))
      .mockResolvedValueOnce(reply({ status: 'verified', admission: admission() }))
    const source = createSupabaseSignupStrengthAuthoritySource({ rpc } as unknown as ServiceClient)
    const input = { ...identity(), expectedEpoch: EPOCH.toUpperCase() }
    const handle = await source.bind(input)
    expect(handle).toMatchObject({
      userId: OWNER,
      epoch: EPOCH.toUpperCase(),
      requestKey: KEY,
      requestHash: HASH,
      admissionId: ADMISSION,
    })
    await expect(handle.verifyReplay()).resolves.toBeUndefined()
    expect(rpc.mock.calls).toEqual([
      [
        'admit_mobile_signup_strength_request',
        {
          p_user_id: OWNER,
          p_request_key: KEY,
          p_request_hash: HASH,
          p_expected_epoch: EPOCH.toUpperCase(),
        },
      ],
      [
        'verify_mobile_signup_strength_request',
        {
          p_user_id: OWNER,
          p_admission_id: ADMISSION,
          p_request_key: KEY,
          p_request_hash: HASH,
          p_expected_epoch: EPOCH.toUpperCase(),
        },
      ],
    ])
  })

  it('captures RPC receiver, input and admission primitives before retained aliases can change', async () => {
    let release!: (value: ReturnType<typeof reply>) => void
    const gate = new Promise<ReturnType<typeof reply>>((resolve) => {
      release = resolve
    })
    const input = identity()
    const admitted = { status: 'admitted', admission: admission() }
    const client = {
      original: true,
      rpc: vi.fn(function (this: { original: boolean }, name: string) {
        expect(this.original).toBe(true)
        if (name === 'admit_mobile_signup_strength_request') return gate
        return Promise.resolve(reply({ status: 'verified', admission: admission() }))
      }),
    }
    const source = createSupabaseSignupStrengthAuthoritySource(client as unknown as ServiceClient)
    const pending = source.bind(input)
    input.requestKey = 'mutated-request-key'
    input.requestHash = 'e'.repeat(64)
    input.expectedEpoch = ADMISSION
    client.rpc = vi.fn()
    release(reply(admitted))
    const handle = await pending
    admitted.admission.epoch = ADMISSION
    admitted.admission.admittedAt = '2026-10-20T11:00:00.123456Z'
    await expect(
      handle.verifyReplay.call({ ...handle, requestKey: 'foreign-receiver-key' }),
    ).resolves.toBeUndefined()
    expect(handle.requestKey).toBe(KEY)
    expect(handle.requestHash).toBe(HASH)
    expect(handle.epoch).toBe(EPOCH)
    expect(client.rpc).not.toHaveBeenCalled()
  })

  it.each([
    ['forbidden', 'invalid_observation', 'mobile_signup_strength_invalid_observation'],
    ['forbidden', 'stale_epoch', 'mobile_signup_strength_stale_epoch'],
    ['conflict', 'request_content_conflict', 'mobile_signup_strength_request_content_conflict'],
  ])('maps bind refusal %s/%s without retrying', async (status, reason, code) => {
    const rpc = vi.fn().mockResolvedValue(reply({ status, reason }))
    const source = createSupabaseSignupStrengthAuthoritySource({ rpc } as unknown as ServiceClient)
    await expect(source.bind(identity())).rejects.toMatchObject({ status: 409, code })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it.each([
    ['invalid_admission', 'mobile_signup_strength_invalid_admission'],
    ['stale_epoch', 'mobile_signup_strength_stale_epoch'],
  ])('maps verify refusal %s without renewing the admission', async (reason, code) => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce(reply({ status: 'admitted', admission: admission() }))
      .mockResolvedValueOnce(reply({ status: 'forbidden', reason }))
    const handle = await createSupabaseSignupStrengthAuthoritySource({
      rpc,
    } as unknown as ServiceClient).bind(identity())
    await expect(handle.verifyReplay()).rejects.toMatchObject({ status: 409, code })
    expect(rpc).toHaveBeenCalledTimes(2)
  })

  it.each([
    { data: null },
    { data: [] },
    { data: { ...observed(), extra: true } },
    { data: { status: 'observed', observation: { ...observed().observation, extra: true } } },
    {
      data: { status: 'observed', observation: { ...observed().observation, ownerID: ADMISSION } },
    },
    { data: { status: 'verified', admission: admission() } },
  ])('rejects an invalid observe wire ($data)', async ({ data }) => {
    const rpc = vi.fn().mockResolvedValue(reply(data))
    const source = createSupabaseSignupStrengthAuthoritySource({ rpc } as unknown as ServiceClient)
    await expect(source.observe({ userId: OWNER })).rejects.toMatchObject({ status: 500 })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it.each([
    '0000-01-01T00:00:00.000000Z',
    '2026-02-30T10:00:00.123456Z',
    '2025-02-29T10:00:00.123456Z',
    '2026-10-20T24:00:00.123456Z',
    '2026-10-20T10:00:60.123456Z',
    '2026-10-20T10:00:00.123Z',
    '2026-10-20T10:00:00.1234567Z',
    '2026-10-20T10:00:00.123456+00:00',
  ])('rejects invalid UTC6 civil time %s', async (changedAt) => {
    const data = observed()
    data.observation.changedAt = changedAt
    const source = createSupabaseSignupStrengthAuthoritySource({
      rpc: vi.fn().mockResolvedValue(reply(data)),
    } as unknown as ServiceClient)
    await expect(source.observe({ userId: OWNER })).rejects.toMatchObject({ status: 500 })
  })

  it.each([
    '0001-01-01T00:00:00.000001Z',
    '2024-02-29T23:59:59.999999Z',
    '9999-12-31T23:59:59.999999Z',
  ])('accepts valid UTC6 without changing the wire precision (%s)', async (changedAt) => {
    const data = observed()
    data.observation.changedAt = changedAt
    const source = createSupabaseSignupStrengthAuthoritySource({
      rpc: vi.fn().mockResolvedValue(reply(data)),
    } as unknown as ServiceClient)
    await expect(source.observe({ userId: OWNER })).resolves.toEqual({
      userId: OWNER,
      epoch: EPOCH,
    })
  })

  it.each([
    { ownerID: ADMISSION },
    { epoch: ADMISSION },
    { requestKey: 'different-key' },
    { requestHash: 'e'.repeat(64) },
    { admissionID: 'invalid' },
    { admittedAt: '2026-02-30T10:00:00.123456Z' },
    { extra: true },
  ])('rejects a mixed or malformed admitted tuple (%j)', async (delta) => {
    const source = createSupabaseSignupStrengthAuthoritySource({
      rpc: vi
        .fn()
        .mockResolvedValue(reply({ status: 'admitted', admission: { ...admission(), ...delta } })),
    } as unknown as ServiceClient)
    await expect(source.bind(identity())).rejects.toMatchObject({ status: 500 })
  })

  it.each([
    { admissionID: OWNER },
    { admittedAt: '2026-10-20T10:00:00.123457Z' },
    { epoch: OWNER },
    { requestKey: 'different-key' },
    { ownerID: EPOCH },
    { requestHash: 'e'.repeat(64) },
  ])('rejects any changed identity in verify (%j)', async (delta) => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce(reply({ status: 'admitted', admission: admission() }))
      .mockResolvedValueOnce(reply({ status: 'verified', admission: { ...admission(), ...delta } }))
    const handle = await createSupabaseSignupStrengthAuthoritySource({
      rpc,
    } as unknown as ServiceClient).bind(identity())
    await expect(handle.verifyReplay()).rejects.toMatchObject({ status: 500 })
    expect(rpc).toHaveBeenCalledTimes(2)
  })

  it.each([
    { status: 'forbidden', reason: 'invalid_admission' },
    { status: 'forbidden', reason: 'invalid_observation', extra: true },
    { status: 'verified', admission: admission() },
    { status: 'conflict', reason: 'stale_epoch' },
  ])('rejects statuses and refusal reasons outside bind mode (%j)', async (data) => {
    const source = createSupabaseSignupStrengthAuthoritySource({
      rpc: vi.fn().mockResolvedValue(reply(data)),
    } as unknown as ServiceClient)
    await expect(source.bind(identity())).rejects.toMatchObject({ status: 500 })
  })

  it.each([
    { userId: 'invalid' },
    { requestKey: 'bad key' },
    { requestHash: 'E'.repeat(64) },
    { expectedEpoch: 'invalid' },
  ])('rejects invalid caller parameters before RPC (%j)', async (delta) => {
    const rpc = vi.fn()
    const source = createSupabaseSignupStrengthAuthoritySource({ rpc } as unknown as ServiceClient)
    await expect(source.bind({ ...identity(), ...delta })).rejects.toMatchObject({ status: 500 })
    expect(rpc).not.toHaveBeenCalled()
  })

  it.each([
    { value: null },
    { value: [] },
    { value: { data: observed() } },
    { value: { error: null } },
    { value: { data: observed(), error: { message: 'private SQL detail' } } },
  ])('rejects malformed or error envelopes without exposing private details (%j)', async ({
    value,
  }) => {
    const rpc = vi.fn().mockResolvedValue(value)
    const source = createSupabaseSignupStrengthAuthoritySource({ rpc } as unknown as ServiceClient)
    await expect(source.observe({ userId: OWNER })).rejects.toMatchObject({
      status: 500,
      details: undefined,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('turns a transport rejection into an opaque error without retry', async () => {
    const rpc = vi.fn().mockRejectedValue(new Error('private transport detail'))
    const source = createSupabaseSignupStrengthAuthoritySource({ rpc } as unknown as ServiceClient)
    await expect(source.bind(identity())).rejects.toMatchObject({ status: 500, details: undefined })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
