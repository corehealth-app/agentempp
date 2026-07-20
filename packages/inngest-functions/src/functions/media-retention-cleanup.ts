import type { ServiceClient } from '@mpp/db'
import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'

const RETENTION_BATCH_SIZE = 100

interface ExpiredMediaAsset {
  id: string
  userId: string
  bucketId: string
  objectPath: string
}

export interface MediaRetentionDependencies {
  repository: {
    listExpired(now: string, limit: number): Promise<ExpiredMediaAsset[]>
    markDeleted(assetId: string, userId: string, deletedAt: string): Promise<void>
  }
  storage: {
    remove(bucketId: string, objectPath: string): Promise<void>
  }
}

export async function cleanupExpiredMedia(
  deps: MediaRetentionDependencies,
  now = new Date(),
): Promise<{ deleted: number }> {
  const nowIso = now.toISOString()
  const assets = await deps.repository.listExpired(nowIso, RETENTION_BATCH_SIZE)
  let deleted = 0

  for (const asset of assets) {
    await deps.storage.remove(asset.bucketId, asset.objectPath)
    await deps.repository.markDeleted(asset.id, asset.userId, nowIso)
    deleted += 1
  }

  return { deleted }
}

function createRetentionDependencies(supabase: ServiceClient): MediaRetentionDependencies {
  return {
    repository: {
      async listExpired(now, limit) {
        const { data, error } = await supabase
          .from('media_assets')
          .select('id, user_id, bucket_id, object_path')
          .lte('retention_until', now)
          .neq('status', 'deleted')
          .order('retention_until', { ascending: true })
          .limit(limit)
        if (error) throw new Error(error.message || 'expired media lookup failed')
        return (data ?? []).map((row) => ({
          id: row.id,
          userId: row.user_id,
          bucketId: row.bucket_id,
          objectPath: row.object_path,
        }))
      },
      async markDeleted(assetId, userId, deletedAt) {
        const { error } = await supabase
          .from('media_assets')
          .update({
            status: 'deleted',
            deleted_at: deletedAt,
            failure_stage: null,
            failure_code: null,
            processing_result: null,
          })
          .eq('id', assetId)
          .eq('user_id', userId)
          .neq('status', 'deleted')
        if (error) throw new Error(error.message || 'expired media state update failed')
      },
    },
    storage: {
      async remove(bucketId, objectPath) {
        const { error } = await supabase.storage.from(bucketId).remove([objectPath])
        if (error) throw new Error(error.message || 'expired media removal failed')
      },
    },
  }
}

export const mediaRetentionCleanupFn = inngest.createFunction(
  { id: 'media-retention-cleanup', retries: 3, concurrency: { limit: 1 } },
  { cron: '17 * * * *' },
  async ({ step, logger }) => {
    return await step.run('cleanup-expired-private-media', async () => {
      const supabase = createWorkerSupabase()
      const result = await cleanupExpiredMedia(createRetentionDependencies(supabase))
      if (result.deleted > 0) logger.info('expired media deleted', result)
      return result
    })
  },
)
