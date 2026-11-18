import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'
import { createPrivateConversationPurgeDependencies } from '../lib/private-conversation-media-account-purge.js'
import { assertPrivateConversationMediaCleanup } from '../lib/private-conversation-media-cleanup-policy.js'
import { createPrivateMediaDisposalV2 } from '../lib/private-conversation-media-disposal.js'
import { purgeDeletedUsers } from './user-deletion-purger.js'

/** Independent bounded cleanup of the private cohort, never a legacy drain. */
export const privateConversationMediaRetentionCleanupFn = inngest.createFunction(
  { id: 'conversation-private-media-retention-cleanup', retries: 1, concurrency: { limit: 1 } },
  { cron: '*/15 * * * *' },
  async ({ step, logger }) =>
    step.run('cleanup-expired-private-conversation-media', async () => {
      try {
        assertPrivateConversationMediaCleanup()
        const disposal = createPrivateMediaDisposalV2(
          createWorkerSupabase(),
          assertPrivateConversationMediaCleanup,
        )
        const sweep = await disposal.sweep(100)
        assertPrivateConversationMediaCleanup()
        const result = { ...sweep, issuanceReconciled: false as const }
        if (result.swept > 0) logger.info('private conversation media sweep completed', result)
        return result
      } catch {
        throw Error('Private conversation media cleanup unavailable')
      }
    }),
)

/** Same scheduler identity replaces the old conversational callback only when
 * cleanup is opted in. Never register two competing account purgers. */
export const privateConversationUserDeletionPurgerFn = inngest.createFunction(
  { id: 'user-deletion-purger', retries: 3, concurrency: { limit: 1 } },
  { cron: '*/15 * * * *' },
  async ({ step, logger }) =>
    step.run('purge-deleted-users', async () => {
      try {
        assertPrivateConversationMediaCleanup()
        const result = await purgeDeletedUsers(
          createPrivateConversationPurgeDependencies(createWorkerSupabase()),
        )
        assertPrivateConversationMediaCleanup()
        if (result.purged > 0) logger.info('deleted users purged', result)
        return result
      } catch {
        throw Error('Private conversation account purge unavailable')
      }
    }),
)
