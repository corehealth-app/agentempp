import { describe, expect, it, vi } from 'vitest'
import { cleanupExpiredMedia, type MediaRetentionDependencies } from './media-retention-cleanup.js'

function makeDeps(): MediaRetentionDependencies {
  return {
    repository: {
      listExpired: vi.fn().mockResolvedValue([
        {
          id: 'asset-1',
          userId: 'user-1',
          bucketId: 'meal-photos',
          objectPath: 'user-1/asset-1.jpg',
        },
      ]),
      markDeleted: vi.fn().mockResolvedValue(undefined),
    },
    storage: { remove: vi.fn().mockResolvedValue(undefined) },
  }
}

describe('media retention cleanup', () => {
  it('deletes an expired object before soft-deleting its catalog row', async () => {
    const deps = makeDeps()

    await expect(cleanupExpiredMedia(deps, new Date('2026-07-20T12:00:00.000Z'))).resolves.toEqual({
      deleted: 1,
    })
    expect(deps.repository.listExpired).toHaveBeenCalledWith('2026-07-20T12:00:00.000Z', 100)
    const storageOrder = vi.mocked(deps.storage.remove).mock.invocationCallOrder[0] ?? 0
    const catalogOrder = vi.mocked(deps.repository.markDeleted).mock.invocationCallOrder[0] ?? 0
    expect(storageOrder).toBeLessThan(catalogOrder)
  })

  it('keeps the catalog active when physical deletion fails so a retry can recover', async () => {
    const deps = makeDeps()
    vi.mocked(deps.storage.remove).mockRejectedValue(new Error('storage unavailable'))

    await expect(cleanupExpiredMedia(deps)).rejects.toThrow('storage unavailable')
    expect(deps.repository.markDeleted).not.toHaveBeenCalled()
  })
})
