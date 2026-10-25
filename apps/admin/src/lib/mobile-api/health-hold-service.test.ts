import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { declareHealthRisk, getHealthHold } from './health-hold-service'
import { createSupabaseHealthHoldRepository } from './supabase-health-hold'
import fixture from './testing/health-hold-fixture.json'

const A = fixture.absent.user_id
const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const AUTH_A = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const KEY = fixture.initial.receipt.operation_key
const ITEMS = fixture.initial.receipt.items
function auth(): MobileAuthContext {
  return {
    userId: A,
    authUserId: AUTH_A,
    accessToken: 'synthetic-verified-session',
    identity: { id: AUTH_A, email: 'qa@example.invalid', emailConfirmedAt: '2026-10-01T00:00:00Z' },
    patient: {
      id: A,
      authUserId: AUTH_A,
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
const envelope = (data: unknown) => ({ data, error: null })
function setup(value: unknown = fixture.absent) {
  const rpc = vi.fn().mockResolvedValue(envelope(value))
  return {
    rpc,
    dependencies: {
      enabled: true,
      repository: createSupabaseHealthHoldRepository({ rpc } as unknown as ServiceClient),
    },
  }
}

describe('dormant health service, bound to verified person identity', () => {
  it('disabled never reads a dependency and is explicitly unavailable without a false HOLD value', async () => {
    const dependencies = {
      enabled: false,
      get repository(): never {
        throw new Error('Should stay unused')
      },
    }
    for (const result of [
      await getHealthHold(auth(), dependencies),
      await declareHealthRisk(auth(), KEY, ITEMS, dependencies),
    ]) {
      expect(result).toEqual({ availability: 'unavailable', reason: 'disabled' })
      expect(result).not.toHaveProperty('hold_active')
      expect(result).not.toHaveProperty('state')
    }
  })

  it('uses public person ID distinct from auth ID, ignoring unrelated payload owner properties', async () => {
    const { rpc, dependencies } = setup()
    expect(
      await getHealthHold({ ...auth(), user_id: B } as MobileAuthContext, dependencies),
    ).toEqual({ availability: 'available', state: fixture.absent })
    expect(rpc.mock.calls).toEqual([['get_mobile_health_hold_state', { p_user_id: A }]])
  })

  it('preserves the operation key and validates old receipt against current state', async () => {
    const { rpc, dependencies } = setup(fixture.replay)
    expect(await declareHealthRisk(auth(), KEY, ITEMS, dependencies)).toEqual({
      availability: 'available',
      ...fixture.replay,
    })
    expect(rpc.mock.calls).toEqual([
      ['declare_mobile_health_risk', { p_user_id: A, p_operation_key: KEY, p_items: ITEMS }],
    ])
  })

  it.each([
    { userId: B },
    { authUserId: B },
    { identity: { ...auth().identity, id: B } },
    { patient: { ...auth().patient, id: B } },
    { patient: { ...auth().patient, authUserId: B } },
    { patient: { ...auth().patient, status: 'deleted' } },
    { userId: 'invalid' },
  ])('rejects mismatched identity before any read or declaration %#', async (patch) => {
    const { rpc, dependencies } = setup()
    const context = { ...auth(), ...patch } as MobileAuthContext
    await expect(getHealthHold(context, dependencies)).rejects.toMatchObject({ status: 403 })
    await expect(declareHealthRisk(context, KEY, ITEMS, dependencies)).rejects.toMatchObject({
      status: 403,
    })
    expect(rpc).not.toHaveBeenCalled()
  })

  it.each([
    [],
    ['none'],
    ['professional_diet', 'professional_diet'],
    ['secret-unknown-risk'],
    null,
  ])('rejects invalid risk input before RPC %#', async (items) => {
    const { rpc, dependencies } = setup()
    await expect(declareHealthRisk(auth(), KEY, items, dependencies)).rejects.toMatchObject({
      status: 422,
    })
    await expect(declareHealthRisk(auth(), 'bad-key', ITEMS, dependencies)).rejects.toMatchObject({
      status: 422,
    })
    expect(rpc).not.toHaveBeenCalled()
  })

  it('sanitizes arbitrary injected repository failures instead of treating them as no HOLD', async () => {
    const dependencies = {
      enabled: true,
      repository: {
        get: vi.fn().mockRejectedValue(new Error('private-risk professional_diet')),
        declare: vi.fn(),
      },
    }
    const caught = await getHealthHold(auth(), dependencies).catch((error: unknown) => error)
    expect(caught).toMatchObject({
      status: 503,
      code: 'mobile_health_hold_unavailable',
      details: undefined,
    })
    expect(String(caught)).not.toContain('professional_diet')
  })

  it('rejects a valid snapshot from a different owner through the full adapter path', async () => {
    const { dependencies } = setup({ ...fixture.absent, user_id: B })
    await expect(getHealthHold(auth(), dependencies)).rejects.toMatchObject({ status: 500 })
  })
})
