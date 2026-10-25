import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createSupabaseHealthHoldRepository } from './supabase-health-hold'
import fixture from './testing/health-hold-fixture.json'

const owner = fixture.absent.user_id
const key = fixture.initial.receipt.operation_key
const items = fixture.initial.receipt.items
describe('injected health Supabase port — no client construction or retry', () => {
  it('binds client receiver and calls only two dedicated RPCs', async () => {
    const client = {
      owned: true,
      rpc: vi.fn(function (this: { owned: boolean }, name: string) {
        if (!this.owned) throw new Error('Lost receiver')
        return Promise.resolve({
          data: name === 'get_mobile_health_hold_state' ? fixture.absent : fixture.initial,
          error: null,
        })
      }),
    }
    const repository = createSupabaseHealthHoldRepository(client as unknown as ServiceClient)
    await expect(repository.get(owner)).resolves.toEqual(fixture.absent)
    await expect(repository.declare(owner, key, items)).resolves.toEqual(fixture.initial)
    expect(client.rpc.mock.calls).toEqual([
      ['get_mobile_health_hold_state', { p_user_id: owner }],
      ['declare_mobile_health_risk', { p_user_id: owner, p_operation_key: key, p_items: items }],
    ])
  })

  it.each([
    null,
    [],
    {},
    { data: fixture.absent },
    { error: null },
    { data: null, error: null },
    { data: fixture.absent, error: undefined },
    { data: fixture.absent, error: 'private-risk' },
  ])('rejects malformed envelopes without fallback or repetition %#', async (value) => {
    const rpc = vi.fn().mockResolvedValue(value)
    const repository = createSupabaseHealthHoldRepository({ rpc } as unknown as ServiceClient)
    await expect(repository.get(owner)).rejects.toMatchObject({
      status: 500,
      code: 'mobile_health_hold_invalid_response',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it.each([
    ['40001', 409, 'mobile_health_hold_state_changed'],
    ['XX001', 500, 'mobile_health_hold_invalid_response'],
    ['P0002', 503, 'mobile_health_hold_unavailable'],
  ])('maps SQLSTATE %s without exposing flags, messages or details', async (code, status, expectedCode) => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code, message: 'professional_diet secret', details: 'private row' },
    })
    const repository = createSupabaseHealthHoldRepository({ rpc } as unknown as ServiceClient)
    const caught = await repository.declare(owner, key, items).catch((error: unknown) => error)
    expect(caught).toMatchObject({ status, code: expectedCode, details: undefined })
    expect(String(caught)).not.toMatch(/professional_diet|private row/)
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('sanitizes transport failure and never retries a possible successful write', async () => {
    const rpc = vi.fn().mockRejectedValue(new Error('secret-risk professional_diet'))
    const repository = createSupabaseHealthHoldRepository({ rpc } as unknown as ServiceClient)
    await expect(repository.declare(owner, key, items)).rejects.toMatchObject({
      status: 503,
      code: 'mobile_health_hold_unavailable',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
