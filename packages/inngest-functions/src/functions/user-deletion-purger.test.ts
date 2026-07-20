import { describe, expect, it, vi } from 'vitest'
import { purgeDeletedUsers, type UserDeletionPurgeDependencies } from './user-deletion-purger.js'

function makeDeps(): UserDeletionPurgeDependencies {
  return {
    repository: {
      listUsersReadyForPurge: vi.fn().mockResolvedValue([{ id: 'user-1' }]),
      listUserMedia: vi.fn().mockResolvedValue([
        { id: 'media-1', bucketId: 'meal-photos', objectPath: 'user-1/media-1.jpg' },
        { id: 'media-2', bucketId: 'audio-notes', objectPath: 'user-1/media-2.m4a' },
      ]),
      deleteUserMediaCatalog: vi.fn().mockResolvedValue(undefined),
      deleteUser: vi.fn().mockResolvedValue(true),
    },
    storage: { remove: vi.fn().mockResolvedValue(undefined) },
  }
}

describe('purgeDeletedUsers', () => {
  it('removes private objects and catalog rows before purging an eligible account', async () => {
    const deps = makeDeps()

    await expect(purgeDeletedUsers(deps, new Date('2026-07-12T12:00:00.000Z'))).resolves.toEqual({
      purged: 1,
      mediaRemoved: 2,
    })
    expect(deps.repository.listUsersReadyForPurge).toHaveBeenCalledWith(
      '2026-07-12T11:00:00.000Z',
      100,
    )
    expect(deps.storage.remove).toHaveBeenNthCalledWith(1, 'meal-photos', 'user-1/media-1.jpg')
    expect(deps.storage.remove).toHaveBeenNthCalledWith(2, 'audio-notes', 'user-1/media-2.m4a')
    const storageOrder = vi.mocked(deps.storage.remove).mock.invocationCallOrder[1] ?? 0
    const catalogOrder =
      vi.mocked(deps.repository.deleteUserMediaCatalog).mock.invocationCallOrder[0] ?? 0
    const userOrder = vi.mocked(deps.repository.deleteUser).mock.invocationCallOrder[0] ?? 0
    expect(storageOrder).toBeLessThan(catalogOrder)
    expect(catalogOrder).toBeLessThan(userOrder)
  })

  it('does not delete catalog or user when physical media removal fails', async () => {
    const deps = makeDeps()
    vi.mocked(deps.storage.remove).mockRejectedValue(new Error('storage unavailable'))

    await expect(purgeDeletedUsers(deps)).rejects.toThrow('storage unavailable')
    expect(deps.repository.deleteUserMediaCatalog).not.toHaveBeenCalled()
    expect(deps.repository.deleteUser).not.toHaveBeenCalled()
  })

  it('does not count a user that no longer satisfies the purge precondition', async () => {
    const deps = makeDeps()
    vi.mocked(deps.repository.listUserMedia).mockResolvedValue([])
    vi.mocked(deps.repository.deleteUser).mockResolvedValue(false)

    await expect(purgeDeletedUsers(deps)).resolves.toEqual({ purged: 0, mediaRemoved: 0 })
  })
})
