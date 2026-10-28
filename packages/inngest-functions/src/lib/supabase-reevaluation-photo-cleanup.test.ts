import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { cleanupReevaluationPhotos } from './reevaluation-photo-cleanup.js'
import { createReevaluationPhotoCleanupDependencies } from './supabase-reevaluation-photo-cleanup.js'
import fixture from './testing/reevaluation-photo-disposition-fixture.json'

describe('normal recurring cleanup backend adapter', () => {
  it('claims via server authority and removes exact paths before the original page ACK', async () => {
    const sequence: string[] = [],
      signals: AbortSignal[] = []
    const responses: Record<string, unknown> = {
      claim_mobile_reevaluation_photo_cleanup_scopes: {
        version: 1,
        items: [
          {
            user_id: fixture.scope.userId,
            cycle_id: fixture.scope.cycleId,
            acceptance_id: fixture.scope.acceptanceId,
          },
        ],
        has_more: false,
      },
      prepare_mobile_reevaluation_photo_disposition: fixture.prepare,
      get_mobile_reevaluation_photo_disposition_page: fixture.page,
      commit_mobile_reevaluation_photo_disposition_page: fixture.ack,
    }
    const rpc = vi.fn((name: string, _args: Record<string, unknown>) => ({
      abortSignal: async (signal: AbortSignal) => {
        sequence.push(name)
        signals.push(signal)
        return { data: responses[name], error: null }
      },
    }))
    const remove = vi.fn(async (_paths: string[]) => {
      sequence.push('Storage.remove')
      return { data: [], error: null }
    })
    const from = vi.fn(() => ({ remove }))
    const result = await cleanupReevaluationPhotos(
      createReevaluationPhotoCleanupDependencies({
        rpc,
        storage: { from },
      } as unknown as ServiceClient),
    )
    expect(result).toMatchObject({
      attempted: 1,
      settled: 1,
      newlyDeleted: fixture.ack.assets.filter((x) => x.newly_deleted).length,
      stopped: 'batch_end',
    })
    expect(sequence).toEqual([
      'claim_mobile_reevaluation_photo_cleanup_scopes',
      'prepare_mobile_reevaluation_photo_disposition',
      'get_mobile_reevaluation_photo_disposition_page',
      'Storage.remove',
      'commit_mobile_reevaluation_photo_disposition_page',
    ])
    expect(rpc.mock.calls[0]?.[1]).toEqual({ p_limit: 1 })
    expect(from).toHaveBeenCalledWith('body-checkin-photos')
    expect(remove).toHaveBeenCalledWith(fixture.page.items.map((item) => item.object_path))
    expect(signals.every((signal) => signal instanceof AbortSignal)).toBe(true)
    expect(JSON.stringify(result)).not.toContain(fixture.scope.userId)
  })
  it('sanitizes RPC failures and refuses invalid limits without touching Storage', async () => {
    const rpc = vi.fn(() => ({
        abortSignal: async () => ({ data: null, error: { message: 'secret signed URL' } }),
      })),
      from = vi.fn()
    const deps = createReevaluationPhotoCleanupDependencies({
      rpc,
      storage: { from },
    } as unknown as ServiceClient)
    await expect(deps.claim(0, new AbortController().signal)).rejects.toThrow(
      'reevaluation_photo_cleanup_unavailable',
    )
    expect(rpc).not.toHaveBeenCalled()
    await expect(deps.claim(1, new AbortController().signal)).rejects.toThrow(
      'reevaluation_photo_cleanup_unavailable',
    )
    expect(await cleanupReevaluationPhotos(deps)).toMatchObject({
      attempted: 0,
      stopped: 'unavailable',
    })
    expect(from).not.toHaveBeenCalled()
  })
})
