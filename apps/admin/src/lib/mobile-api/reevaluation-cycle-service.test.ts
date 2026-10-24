import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { getReevaluationCycle, startReevaluationCycle } from './reevaluation-cycle-service'
import { createSupabaseReevaluationCycleRepository } from './supabase-reevaluation-cycles'

const A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const AUTH_A = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const AUTH_B = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
const KEY = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
function auth(userId = A, authUserId = AUTH_A): MobileAuthContext {
  return {
    userId,
    authUserId,
    accessToken: 'test-only-verified-session',
    identity: {
      id: authUserId,
      email: 'qa@example.invalid',
      emailConfirmedAt: '2026-10-01T00:00:00Z',
    },
    patient: {
      id: userId,
      authUserId,
      email: 'qa@example.invalid',
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
}
function state(id = A) {
  return {
    version: 1,
    availability: 'available',
    unavailable_reason: null,
    clock: { base_date: '2026-10-01', due_date: '2026-10-15', timezone: 'America/Sao_Paulo' },
    cycle: {
      id,
      signup_generation: KEY,
      revision: '9007199254740993',
      kind: 'REGULAR',
      status: 'open',
      base_date: '2026-10-01',
      due_date: '2026-10-15',
      timezone_at_open: 'America/Sao_Paulo',
      opened_at: '2026-10-15T03:00:00.123456Z',
    },
  }
}
const envelope = (data: unknown) => ({
  data,
  error: null,
  count: null,
  status: 200,
  statusText: 'OK',
})
function setup(rpc = vi.fn().mockResolvedValue(envelope(state())), enabled = true) {
  return {
    rpc,
    dependencies: {
      enabled,
      repository: createSupabaseReevaluationCycleRepository({ rpc } as unknown as ServiceClient),
    },
  }
}

describe('reevaluation service through the concrete Supabase adapter', () => {
  it('keeps disabled get and start local without even reading the repository', async () => {
    const dependencies = {
      enabled: false,
      get repository(): never {
        throw new Error('RPC dependency must stay unused')
      },
    }
    const expected = {
      version: 1,
      availability: 'unavailable',
      unavailable_reason: 'disabled',
      clock: null,
      cycle: null,
    }
    await expect(getReevaluationCycle(auth(), dependencies)).resolves.toEqual(expected)
    await expect(startReevaluationCycle(auth(), KEY, dependencies)).resolves.toEqual(expected)
  })

  it('gets only the authenticated public owner without starting a cycle', async () => {
    const { rpc, dependencies } = setup()
    const context = { ...auth(), user_id: B }
    await expect(getReevaluationCycle(context, dependencies)).resolves.toEqual(state())
    expect(rpc.mock.calls).toEqual([['get_mobile_reevaluation_cycle', { p_user_id: A }]])
  })

  it('keeps the same idempotency key scoped to two authenticated owners on one repository', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValueOnce(envelope(state(A)))
      .mockResolvedValueOnce(envelope(state(A)))
      .mockResolvedValueOnce(envelope(state(B)))
    const { dependencies } = setup(rpc)
    await expect(startReevaluationCycle(auth(), KEY, dependencies)).resolves.toEqual(state(A))
    await expect(startReevaluationCycle(auth(), KEY, dependencies)).resolves.toEqual(state(A))
    await expect(startReevaluationCycle(auth(B, AUTH_B), KEY, dependencies)).resolves.toEqual(
      state(B),
    )
    expect(rpc.mock.calls).toEqual([
      ['start_mobile_reevaluation_cycle', { p_user_id: A, p_idempotency_key: KEY }],
      ['start_mobile_reevaluation_cycle', { p_user_id: A, p_idempotency_key: KEY }],
      ['start_mobile_reevaluation_cycle', { p_user_id: B, p_idempotency_key: KEY }],
    ])
  })

  it('snapshots the owner before an asynchronous call and never reads a changed context', async () => {
    let release!: (value: ReturnType<typeof envelope>) => void
    const rpc = vi.fn().mockReturnValue(
      new Promise((resolve) => {
        release = resolve
      }),
    )
    const { dependencies } = setup(rpc)
    const context = auth()
    const pending = startReevaluationCycle(context, KEY, dependencies)
    context.userId = B
    context.patient.id = B
    release(envelope(state()))
    await expect(pending).resolves.toEqual(state())
    expect(rpc).toHaveBeenCalledWith('start_mobile_reevaluation_cycle', {
      p_user_id: A,
      p_idempotency_key: KEY,
    })
  })

  it.each([
    'patient_owner',
    'auth_identity',
    'patient_auth',
    'inactive',
    'invalid_uuid',
  ])('rejects the incoherent context %s before any RPC', async (fault) => {
    const context = auth()
    if (fault === 'patient_owner') context.patient.id = B
    if (fault === 'auth_identity') context.identity.id = AUTH_B
    if (fault === 'patient_auth') context.patient.authUserId = AUTH_B
    if (fault === 'inactive') context.patient.status = 'blocked'
    if (fault === 'invalid_uuid') {
      context.userId = 'bad'
      context.patient.id = 'bad'
    }
    const { rpc, dependencies } = setup()
    await expect(getReevaluationCycle(context, dependencies)).rejects.toMatchObject({
      status: 403,
      code: 'mobile_reevaluation_identity_invalid',
    })
    await expect(startReevaluationCycle(context, KEY, dependencies)).rejects.toMatchObject({
      status: 403,
    })
    expect(rpc).not.toHaveBeenCalled()
  })

  it('rejects an invalid idempotency key rather than generating a different one', async () => {
    const { rpc, dependencies } = setup()
    await expect(
      startReevaluationCycle(auth(), 'request-trace-not-a-uuid', dependencies),
    ).rejects.toMatchObject({ status: 422, code: 'mobile_reevaluation_invalid_key' })
    expect(rpc).not.toHaveBeenCalled()
  })

  it('rejects a corrupt read once without attempting start or any recovery write', async () => {
    const { rpc, dependencies } = setup(
      vi
        .fn()
        .mockResolvedValue(
          envelope({ ...state(), cycle: { ...state().cycle, due_date: '2026-10-16' } }),
        ),
    )
    await expect(getReevaluationCycle(auth(), dependencies)).rejects.toMatchObject({
      status: 500,
      code: 'mobile_reevaluation_invalid_response',
    })
    expect(rpc.mock.calls).toEqual([['get_mobile_reevaluation_cycle', { p_user_id: A }]])
  })

  it('also validates an injected repository instead of trusting an incompatible state', async () => {
    const get = vi.fn().mockResolvedValue({ ...state(), targets: { calories: 1500 } })
    const start = vi.fn().mockResolvedValue(envelope(state()))
    await expect(
      getReevaluationCycle(auth(), { enabled: true, repository: { get, start } }),
    ).rejects.toMatchObject({ code: 'mobile_reevaluation_invalid_response' })
    expect(start).not.toHaveBeenCalled()
  })
})
