import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

const PURGE_GRACE_MS = 60 * 60 * 1000

interface DeletionPurgeClient {
  from(table: 'users'): {
    delete(): {
      eq(
        column: 'status',
        value: 'deleted',
      ): {
        lte(
          column: 'updated_at',
          cutoff: string,
        ): {
          select(selection: 'id'): Promise<{
            data: Array<{ id: string }> | null
            error: { message?: string } | null
          }>
        }
      }
    }
  }
}

export async function purgeDeletedUsers(
  supabase: DeletionPurgeClient,
  now = new Date(),
): Promise<{ purged: number }> {
  const cutoff = new Date(now.getTime() - PURGE_GRACE_MS).toISOString()
  const { data, error } = await supabase
    .from('users')
    .delete()
    .eq('status', 'deleted')
    .lte('updated_at', cutoff)
    .select('id')

  if (error) throw new Error(error.message || 'deleted user purge failed')
  return { purged: data?.length ?? 0 }
}

export const userDeletionPurgerFn = inngest.createFunction(
  { id: 'user-deletion-purger', retries: 3, concurrency: { limit: 1 } },
  { cron: '*/15 * * * *' },
  async ({ step, logger }) => {
    return await step.run('purge-deleted-users', async () => {
      const { supabase } = createWorkerDeps()
      const result = await purgeDeletedUsers(supabase as unknown as DeletionPurgeClient)
      if (result.purged > 0) logger.info('deleted users purged', result)
      return result
    })
  },
)
