import { inngest } from '../client.js'
import { assertClinicalStagingWorkerTarget } from '../lib/clinical-staging-worker-target.js'
import { createWorkerSupabase } from '../lib/env.js'
import { cleanupExpiredMedia, createRetentionDependencies } from './media-retention-cleanup.js'

/** An explicit staging-only schedule; never added to production/all or older sets. */
export const conversationMediaRetentionCleanupFn = inngest.createFunction(
  { id: 'conversation-media-retention-cleanup', retries: 1, concurrency: { limit: 1 } },
  { cron: '17 * * * *' },
  async ({ step, logger }) =>
    step.run('cleanup-expired-conversation-media', async () => {
      // Recheck a direct/stale callback before constructing any privileged client.
      assertClinicalStagingWorkerTarget(process.env, 'media-conversation-staging')
      try {
        const sweep = await cleanupExpiredMedia(
          createRetentionDependencies(createWorkerSupabase(), { scope: 'conversation' }),
        )
        const result = { swept: sweep.deleted, issuanceDrain: 'not_qualified' as const }
        if (result.swept > 0) logger.info('conversation media sweep completed', result)
        return result
      } catch {
        // Never persist a Storage path, owner or raw provider response in a job error.
        throw new Error('Conversation media retention unavailable')
      }
    }),
)
