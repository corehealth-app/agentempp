import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { prepareReevaluationPhotoAccountPurge } from './reevaluation-photo-account-purge.js'
import { createReevaluationPhotoAccountPurgeDependencies } from './supabase-reevaluation-photo-account-purge.js'
import fixture from './testing/reevaluation-photo-disposition-fixture.json'

const cutoff = '2026-10-25T11:00:00.000Z'
describe('injected recurring account purge adapter', () => {
  it('binds owner, cutoff, keyset and deadline, then delegates the existing private drain', async () => {
    let purges = 0
    const values: Record<string, unknown> = {
      begin_mobile_deleted_user_photo_purge: true,
      claim_mobile_reevaluation_photo_purge_scopes: {
        version: 1,
        user_id: fixture.scope.userId,
        eligible: true,
        items: [{ cycle_id: fixture.scope.cycleId, acceptance_id: fixture.scope.acceptanceId }],
        has_more: false,
      },
      prepare_mobile_reevaluation_photo_disposition: fixture.prepare,
      get_mobile_reevaluation_photo_disposition_page: fixture.page,
      commit_mobile_reevaluation_photo_disposition_page: fixture.ack,
    }
    const signals: AbortSignal[] = []
    const rpc = vi.fn((name: string, _args: Record<string, unknown>) => ({
      abortSignal: async (signal: AbortSignal) => {
        signals.push(signal)
        return {
          data:
            name === 'purge_mobile_reevaluation_photo_catalog_for_deleted_user'
              ? ++purges > 1
              : values[name],
          error: null,
        }
      },
    }))
    const remove = vi.fn().mockResolvedValue({ data: [], error: null })
    const from = vi.fn(() => ({ remove }))
    const client = { rpc, storage: { from } } as unknown as ServiceClient
    expect(
      await prepareReevaluationPhotoAccountPurge(
        createReevaluationPhotoAccountPurgeDependencies(client),
        fixture.scope.userId,
        cutoff,
      ),
    ).toBe(true)
    expect(rpc.mock.calls.map(([name]) => name)).toEqual([
      'begin_mobile_deleted_user_photo_purge',
      'purge_mobile_reevaluation_photo_catalog_for_deleted_user',
      'claim_mobile_reevaluation_photo_purge_scopes',
      'prepare_mobile_reevaluation_photo_disposition',
      'get_mobile_reevaluation_photo_disposition_page',
      'commit_mobile_reevaluation_photo_disposition_page',
      'purge_mobile_reevaluation_photo_catalog_for_deleted_user',
    ])
    expect(rpc.mock.calls[0]?.[1]).toEqual({ p_user_id: fixture.scope.userId, p_cutoff: cutoff })
    expect(rpc.mock.calls[2]?.[1]).toEqual({
      p_user_id: fixture.scope.userId,
      p_cutoff: cutoff,
      p_limit: 1,
    })
    expect(from).toHaveBeenCalledWith('body-checkin-photos')
    expect(remove).toHaveBeenCalledWith(fixture.page.items.map((x) => x.object_path))
    expect(signals.every((x) => x instanceof AbortSignal)).toBe(true)
  })
  it('sanitizes backend errors without invoking Storage', async () => {
    const from = vi.fn()
    const client = {
      rpc: () => ({ abortSignal: async () => ({ data: null, error: { message: 'private' } }) }),
      storage: { from },
    } as unknown as ServiceClient
    await expect(
      createReevaluationPhotoAccountPurgeDependencies(client).purge(
        fixture.scope.userId,
        cutoff,
        new AbortController().signal,
      ),
    ).rejects.toThrow('reevaluation_photo_account_purge_unavailable')
    expect(
      await prepareReevaluationPhotoAccountPurge(
        createReevaluationPhotoAccountPurgeDependencies(client),
        fixture.scope.userId,
        cutoff,
      ),
    ).toBe(false)
    expect(from).not.toHaveBeenCalled()
  })
})
