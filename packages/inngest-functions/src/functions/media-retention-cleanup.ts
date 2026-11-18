import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'
import { cleanupExpiredMedia, createRetentionDependencies } from '../lib/media-retention.js'

export {
  cleanupExpiredMedia,
  createRetentionDependencies,
  type MediaRetentionDependencies,
} from '../lib/media-retention.js'

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
