import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createSupabaseReevaluationCycleRepository } from './supabase-reevaluation-cycles'

const OWNER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const KEY = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const unavailable = {
  version: 1,
  availability: 'unavailable',
  unavailable_reason: 'anchor_unproven',
  clock: null,
  cycle: null,
}
const envelope = (data: unknown) => ({
  data,
  error: null,
  count: null,
  status: 200,
  statusText: 'OK',
})

describe('concrete reevaluation Supabase repository', () => {
  it('calls only the two exact public RPCs with their bound client receiver', async () => {
    const client = {
      original: true,
      rpc: vi.fn(function (this: { original: boolean }) {
        if (!this.original) throw new Error('Lost receiver')
        return Promise.resolve(envelope(unavailable))
      }),
    }
    const repository = createSupabaseReevaluationCycleRepository(client as unknown as ServiceClient)
    await expect(repository.get(OWNER)).resolves.toEqual(unavailable)
    await expect(repository.start(OWNER, KEY)).resolves.toEqual(unavailable)
    expect(client.rpc.mock.calls).toEqual([
      ['get_mobile_reevaluation_cycle', { p_user_id: OWNER }],
      ['start_mobile_reevaluation_cycle', { p_user_id: OWNER, p_idempotency_key: KEY }],
    ])
  })

  it.each([
    null,
    [],
    {},
    { data: unavailable },
    { error: null },
    { data: unavailable, error: undefined },
    { data: { ...unavailable, cycle: {} }, error: null },
    { data: { ...unavailable, unavailable_reason: 'disabled' }, error: null },
  ])('rejects malformed or disabled RPC results %# without retry', async (response) => {
    const rpc = vi.fn().mockResolvedValue(response)
    const repository = createSupabaseReevaluationCycleRepository({
      rpc,
    } as unknown as ServiceClient)
    await expect(repository.get(OWNER)).rejects.toMatchObject({
      status: 500,
      code: 'mobile_reevaluation_invalid_response',
      details: undefined,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it.each([
    ['40001', 409, 'mobile_reevaluation_state_changed'],
    ['XX001', 500, 'mobile_reevaluation_invalid_response'],
    ['P0002', 503, 'mobile_reevaluation_unavailable'],
  ])('maps SQLSTATE %s without disclosing database messages', async (code, status, expectedCode) => {
    const rpc = vi.fn().mockResolvedValue({
      ...envelope(null),
      error: { code, message: 'private-db-fixture', details: 'private-fixture' },
    })
    const repository = createSupabaseReevaluationCycleRepository({
      rpc,
    } as unknown as ServiceClient)
    const caught = await repository.start(OWNER, KEY).catch((error: unknown) => error)
    expect(caught).toMatchObject({ status, code: expectedCode, details: undefined })
    expect(String(caught)).not.toContain('private')
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('maps transport failure without leaking it or repeating a possible write', async () => {
    const rpc = vi.fn().mockRejectedValue(new Error('private transport fixture'))
    const repository = createSupabaseReevaluationCycleRepository({
      rpc,
    } as unknown as ServiceClient)
    await expect(repository.start(OWNER, KEY)).rejects.toMatchObject({
      status: 503,
      code: 'mobile_reevaluation_unavailable',
      details: undefined,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('rejects invalid owner and key before invoking the external RPC', async () => {
    const rpc = vi.fn()
    const repository = createSupabaseReevaluationCycleRepository({
      rpc,
    } as unknown as ServiceClient)
    await expect(repository.get('invalid')).rejects.toMatchObject({
      status: 500,
      code: 'mobile_reevaluation_invalid_input',
    })
    await expect(repository.start(OWNER, 'invalid')).rejects.toMatchObject({
      status: 500,
      code: 'mobile_reevaluation_invalid_input',
    })
    expect(rpc).not.toHaveBeenCalled()
  })
})
