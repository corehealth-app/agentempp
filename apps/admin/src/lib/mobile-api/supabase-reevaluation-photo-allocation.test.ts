import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createSupabaseReevaluationPhotoAllocationRepository } from './supabase-reevaluation-photo-allocation'
import fixture from './testing/reevaluation-photo-allocation-fixture.json'

describe('injected allocation adapter, sanitized quota and no retry', () => {
  it.each([
    ['P0001', 'mobile_reevaluation_photo_limit_reached', 429, 'quota_reached'],
    ['P0001', 'unrelated_sql_exception private', 503, 'unavailable'],
    ['40001', 'private detail', 409, 'state_changed'],
    ['22023', 'bad remote argument', 503, 'unavailable'],
  ])('maps only exact quota failure, SQLSTATE %s / %s', async (code, message, status, kind) => {
    const rpc = vi
      .fn()
      .mockResolvedValue({ data: null, error: { code, message, details: 'private-secret' } })
    const repository = createSupabaseReevaluationPhotoAllocationRepository({
      rpc,
    } as unknown as ServiceClient)
    const error = await repository
      .allocate(fixture.owner, fixture.request)
      .catch((value: unknown) => value)
    expect(error).toMatchObject({ status, code: `mobile_reevaluation_photo_allocation_${kind}` })
    expect(error).toHaveProperty(
      'details',
      status === 429 ? { max_new_photos: 6, window_seconds: 86400 } : undefined,
    )
    expect(String(error)).not.toMatch(/private|secret/)
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    null,
    [],
    {},
    { data: fixture.response },
    { error: null },
    { data: fixture.response, error: undefined },
    { data: fixture.response, error: 'private' },
  ])('rejects malformed envelopes without guessing quota or success %#', async (response) => {
    const rpc = vi.fn().mockResolvedValue(response)
    const repository = createSupabaseReevaluationPhotoAllocationRepository({
      rpc,
    } as unknown as ServiceClient)
    await expect(repository.allocate(fixture.owner, fixture.request)).rejects.toMatchObject({
      status: 500,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('transport uncertainty never retries a possible successful allocation', async () => {
    const rpc = vi.fn().mockRejectedValue(new Error('private-session-token'))
    const repository = createSupabaseReevaluationPhotoAllocationRepository({
      rpc,
    } as unknown as ServiceClient)
    await expect(repository.allocate(fixture.owner, fixture.request)).rejects.toMatchObject({
      status: 503,
      details: undefined,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('binds SDK receiver and validates direct adapter input before RPC', async () => {
    const client = {
      owned: true,
      rpc: vi.fn(function (this: { owned: boolean }) {
        if (!this.owned) throw new Error('receiver lost')
        return Promise.resolve({ data: fixture.response, error: null })
      }),
    }
    const repository = createSupabaseReevaluationPhotoAllocationRepository(
      client as unknown as ServiceClient,
    )
    await expect(repository.allocate(fixture.owner, fixture.request)).resolves.toEqual(
      fixture.response,
    )
    await expect(repository.allocate('invalid', fixture.request)).rejects.toMatchObject({
      status: 422,
    })
    expect(client.rpc).toHaveBeenCalledTimes(1)
  })
})
