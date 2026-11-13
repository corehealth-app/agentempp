import { inngest } from '../client.js'
import { assertClinicalStagingWorkerTarget } from '../lib/clinical-staging-worker-target.js'
import { createWorkerSupabase } from '../lib/env.js'
import { createPurgeDependencies, purgeDeletedUsers } from './user-deletion-purger.js'

/** Same scheduler identity, separate callback: the production roster keeps its
 * existing purger. A stale conversational callback must never fall back to it. */
export const conversationUserDeletionPurgerFn = inngest.createFunction(
  { id: 'user-deletion-purger', retries: 3, concurrency: { limit: 1 } },
  { cron: '*/15 * * * *' },
  async ({ step, logger }) =>
    step.run('purge-deleted-users', async () => {
      // Check inside the durable step before constructing a privileged client.
      assertClinicalStagingWorkerTarget(process.env, 'media-conversation-staging')
      try {
        const result = await purgeDeletedUsers(
          createPurgeDependencies(createWorkerSupabase(), { conversationMedia: true }),
        )
        if (result.purged > 0) logger.info('deleted users purged', result)
        return result
      } catch {
        throw new Error('Conversation account purge unavailable')
      }
    }),
)
