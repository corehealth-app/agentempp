import { describe, expect, it, vi } from 'vitest'
import {
  createPurgeDependencies,
  purgeDeletedUsers,
  type UserDeletionPurgeDependencies,
} from './user-deletion-purger.js'

function makeDeps(): UserDeletionPurgeDependencies {
  return {
    repository: {
      listUsersReadyForPurge: vi.fn().mockResolvedValue([{ id: 'user-1' }]),
      prepareRecurringMediaPurge: vi.fn().mockResolvedValue(true),
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
  it('uses durable owner selection instead of the old fixed first100 query', async () => {
    const id = 'b3b01000-0000-4000-8000-000000000101'
    const rpc = vi.fn(() => ({
      abortSignal: async () => ({ data: { version: 1, users: [{ id }] }, error: null }),
    }))
    const from = vi.fn(() => {
      throw new Error('legacy fixed first100 selector must not run')
    })
    const client = { rpc, from } as unknown as ServiceClient
    expect(
      await createPurgeDependencies(client).repository.listUsersReadyForPurge(
        '2026-10-25T11:00:00.000Z',
        100,
      ),
    ).toEqual([{ id }])
    expect(rpc).toHaveBeenCalledWith('list_mobile_deleted_users_for_photo_purge', {
      p_cutoff: '2026-10-25T11:00:00.000Z',
      p_limit: 100,
    })
    expect(from).not.toHaveBeenCalled()
  })
  it('defers only the pending recurring owner and continues the batch', async () => {
    const deps = makeDeps()
    const prepare = vi.fn().mockResolvedValueOnce(false).mockResolvedValueOnce(true)
    Object.assign(deps.repository, { prepareRecurringMediaPurge: prepare })
    vi.mocked(deps.repository.listUsersReadyForPurge).mockResolvedValue([
      { id: 'waiting-owner' },
      { id: 'ready-owner' },
    ])
    await expect(purgeDeletedUsers(deps, new Date('2026-07-12T12:00:00.000Z'))).resolves.toEqual({
      purged: 1,
      mediaRemoved: 2,
    })
    expect(prepare).toHaveBeenNthCalledWith(1, 'waiting-owner', '2026-07-12T11:00:00.000Z')
    expect(deps.repository.listUserMedia).toHaveBeenCalledTimes(1)
    expect(deps.repository.listUserMedia).toHaveBeenCalledWith('ready-owner')
    expect(deps.repository.deleteUser).toHaveBeenCalledWith(
      'ready-owner',
      '2026-07-12T11:00:00.000Z',
    )
  })

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
    expect(deps.repository.prepareRecurringMediaPurge).toHaveBeenCalledWith(
      'user-1',
      '2026-07-12T11:00:00.000Z',
    )
    expect(
      vi.mocked(deps.repository.prepareRecurringMediaPurge).mock.invocationCallOrder[0],
    ).toBeLessThan(vi.mocked(deps.repository.listUserMedia).mock.invocationCallOrder[0] ?? 0)
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

  it('does not read or delete generic media while recurring cleanup is pending', async () => {
    const deps = makeDeps()
    vi.mocked(deps.repository.prepareRecurringMediaPurge).mockResolvedValue(false)
    expect(await purgeDeletedUsers(deps)).toEqual({ purged: 0, mediaRemoved: 0 })
    expect(deps.repository.listUserMedia).not.toHaveBeenCalled()
    expect(deps.storage.remove).not.toHaveBeenCalled()
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

import type { ServiceClient } from '@mpp/db'

describe('conversational account purge retains upload barriers', () => {
  const owner = 'b3b01000-0000-4000-8000-000000000101'
  const cutoff = '2026-11-13T05:00:00.000Z'
  function fixture(ready: unknown = false, error: unknown = null) {
    const rows = [
      {
        id: 'ordinary',
        kind: 'conversation_photo',
        reevaluation_origin_version: null,
        bucket_id: 'meal-photos',
        object_path: `${owner}/ordinary.jpg`,
      },
      {
        id: 'audio',
        kind: 'audio_note',
        reevaluation_origin_version: null,
        bucket_id: 'audio-notes',
        object_path: `${owner}/audio.m4a`,
      },
      {
        id: 'legacy',
        kind: 'meal_photo',
        reevaluation_origin_version: null,
        bucket_id: 'meal-photos',
        object_path: `${owner}/legacy.jpg`,
      },
      {
        id: 'clinical',
        kind: 'body_checkin_photo',
        reevaluation_origin_version: 1,
        bucket_id: 'body-checkin-photos',
        object_path: `${owner}/clinical.jpg`,
      },
    ]
    const query = { select: vi.fn(), eq: vi.fn().mockResolvedValue({ data: rows, error: null }) }
    query.select.mockReturnValue(query)
    const remove = vi.fn().mockResolvedValue({ error: null })
    const rpc = vi.fn(() => ({ abortSignal: vi.fn().mockResolvedValue({ data: ready, error }) }))
    const client = {
      from: vi.fn(() => query),
      rpc,
      storage: { from: vi.fn(() => ({ remove })) },
    } as unknown as ServiceClient
    const deps = createPurgeDependencies(client, { conversationMedia: true })
    Object.assign(deps.repository, {
      listUsersReadyForPurge: vi.fn().mockResolvedValue([{ id: owner }]),
      prepareRecurringMediaPurge: vi.fn().mockResolvedValue(true),
      deleteUserMediaCatalog: vi.fn().mockResolvedValue(undefined),
      deleteUser: vi.fn().mockResolvedValue(true),
    })
    return { deps, remove, rpc, client }
  }
  it('waits before any physical or catalogue deletion while an ordinary payload is not sealed', async () => {
    const f = fixture(false)
    expect(await purgeDeletedUsers(f.deps, new Date('2026-11-13T06:00:00.000Z'))).toEqual({
      purged: 0,
      mediaRemoved: 0,
    })
    expect(f.remove).not.toHaveBeenCalled()
    expect(f.deps.repository.prepareRecurringMediaPurge).not.toHaveBeenCalled()
    expect(f.deps.repository.deleteUserMediaCatalog).not.toHaveBeenCalled()
    expect(f.deps.repository.deleteUser).not.toHaveBeenCalled()
    expect(f.rpc).toHaveBeenCalledWith('prepare_conversation_media_account_purge', {
      p_user_id: owner,
      p_cutoff: cutoff,
    })
  })
  it('purges a ready account without deleting ordinary barriers, preserving generic and clinical cleanup', async () => {
    const f = fixture(true)
    expect(await purgeDeletedUsers(f.deps, new Date('2026-11-13T06:00:00.000Z'))).toEqual({
      purged: 1,
      mediaRemoved: 2,
    })
    expect(f.remove.mock.calls).toEqual([[[`${owner}/legacy.jpg`]], [[`${owner}/clinical.jpg`]]])
    expect(f.deps.repository.deleteUser).toHaveBeenCalledWith(owner, cutoff)
  })
  it.each([
    null,
    1,
    'true',
    { ready: true },
  ])('refuses malformed readiness %j before deleting anything', async (ready) => {
    const f = fixture(ready)
    await expect(purgeDeletedUsers(f.deps)).rejects.toThrow(
      'Conversation media account purge unavailable',
    )
    expect(f.remove).not.toHaveBeenCalled()
    expect(f.deps.repository.deleteUser).not.toHaveBeenCalled()
  })
  it('does not fall back to untracked deletion if the new RPC is missing', async () => {
    const f = fixture(null, { message: 'private/provider/raw', code: 'PGRST202' })
    await expect(purgeDeletedUsers(f.deps)).rejects.toThrow(
      /^Conversation media account purge unavailable$/,
    )
    expect(f.remove).not.toHaveBeenCalled()
    expect(f.deps.repository.deleteUser).not.toHaveBeenCalled()
  })
})
