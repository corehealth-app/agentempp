import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'
import { createPurgeDependencies, purgeDeletedUsers } from '../lib/user-deletion-purge.js'

export {
  createPurgeDependencies,
  purgeDeletedUsers,
  type UserDeletionPurgeDependencies,
} from '../lib/user-deletion-purge.js'

export const userDeletionPurgerFn = inngest.createFunction(
  { id: 'user-deletion-purger', retries: 3, concurrency: { limit: 1 } },
  { cron: '*/15 * * * *' },
  async ({ step, logger }) => {
    return await step.run('purge-deleted-users', async () => {
      const supabase = createWorkerSupabase()
      const result = await purgeDeletedUsers(
        createPurgeDependencies(
          supabase,
          process.env.INNGEST_FUNCTION_SET === 'media-conversation-staging'
            ? { conversationMedia: true }
            : undefined,
        ),
      )
      if (result.purged > 0) logger.info('deleted users purged', result)
      return result
    })
  },
)
