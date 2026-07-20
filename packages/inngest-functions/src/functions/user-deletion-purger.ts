import type { ServiceClient } from '@mpp/db'
import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'

const PURGE_GRACE_MS = 60 * 60 * 1000
const PURGE_BATCH_SIZE = 100

interface UserMediaForPurge {
  id: string
  bucketId: string
  objectPath: string
}

export interface UserDeletionPurgeDependencies {
  repository: {
    listUsersReadyForPurge(cutoff: string, limit: number): Promise<Array<{ id: string }>>
    listUserMedia(userId: string): Promise<UserMediaForPurge[]>
    deleteUserMediaCatalog(userId: string): Promise<void>
    deleteUser(userId: string, cutoff: string): Promise<boolean>
  }
  storage: {
    remove(bucketId: string, objectPath: string): Promise<void>
  }
}

export async function purgeDeletedUsers(
  deps: UserDeletionPurgeDependencies,
  now = new Date(),
): Promise<{ purged: number; mediaRemoved: number }> {
  const cutoff = new Date(now.getTime() - PURGE_GRACE_MS).toISOString()
  const users = await deps.repository.listUsersReadyForPurge(cutoff, PURGE_BATCH_SIZE)
  let purged = 0
  let mediaRemoved = 0

  for (const user of users) {
    const media = await deps.repository.listUserMedia(user.id)
    for (const asset of media) {
      await deps.storage.remove(asset.bucketId, asset.objectPath)
      mediaRemoved += 1
    }
    await deps.repository.deleteUserMediaCatalog(user.id)
    if (await deps.repository.deleteUser(user.id, cutoff)) purged += 1
  }

  return { purged, mediaRemoved }
}

function createPurgeDependencies(supabase: ServiceClient): UserDeletionPurgeDependencies {
  return {
    repository: {
      async listUsersReadyForPurge(cutoff, limit) {
        const { data, error } = await supabase
          .from('users')
          .select('id')
          .eq('status', 'deleted')
          .lte('updated_at', cutoff)
          .limit(limit)
        if (error) throw new Error(error.message || 'deleted user lookup failed')
        return data ?? []
      },
      async listUserMedia(userId) {
        const { data, error } = await supabase
          .from('media_assets')
          .select('id, bucket_id, object_path')
          .eq('user_id', userId)
        if (error) throw new Error(error.message || 'user media lookup failed')
        return (data ?? []).map((row) => ({
          id: row.id,
          bucketId: row.bucket_id,
          objectPath: row.object_path,
        }))
      },
      async deleteUserMediaCatalog(userId) {
        const { error } = await supabase.from('media_assets').delete().eq('user_id', userId)
        if (error) throw new Error(error.message || 'user media catalog purge failed')
      },
      async deleteUser(userId, cutoff) {
        const { data, error } = await supabase
          .from('users')
          .delete()
          .eq('id', userId)
          .eq('status', 'deleted')
          .lte('updated_at', cutoff)
          .select('id')
          .maybeSingle()
        if (error) throw new Error(error.message || 'deleted user purge failed')
        return data !== null
      },
    },
    storage: {
      async remove(bucketId, objectPath) {
        const { error } = await supabase.storage.from(bucketId).remove([objectPath])
        if (error) throw new Error(error.message || 'user media removal failed')
      },
    },
  }
}

export const userDeletionPurgerFn = inngest.createFunction(
  { id: 'user-deletion-purger', retries: 3, concurrency: { limit: 1 } },
  { cron: '*/15 * * * *' },
  async ({ step, logger }) => {
    return await step.run('purge-deleted-users', async () => {
      const supabase = createWorkerSupabase()
      const result = await purgeDeletedUsers(createPurgeDependencies(supabase))
      if (result.purged > 0) logger.info('deleted users purged', result)
      return result
    })
  },
)
