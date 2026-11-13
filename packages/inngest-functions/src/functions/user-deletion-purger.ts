import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'
import { prepareReevaluationPhotoAccountPurge } from '../lib/reevaluation-photo-account-purge.js'
import {
  claimDeletedUsersForPhotoPurge,
  createReevaluationPhotoAccountPurgeDependencies,
} from '../lib/supabase-reevaluation-photo-account-purge.js'

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
    prepareConversationMediaPurge?(userId: string, cutoff: string): Promise<boolean>
    prepareRecurringMediaPurge(userId: string, cutoff: string): Promise<boolean>
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
    if (
      deps.repository.prepareConversationMediaPurge &&
      !(await deps.repository.prepareConversationMediaPurge(user.id, cutoff))
    )
      continue
    if (!(await deps.repository.prepareRecurringMediaPurge(user.id, cutoff))) continue
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

export function createPurgeDependencies(
  supabase: ServiceClient,
  options?: { conversationMedia: true },
): UserDeletionPurgeDependencies {
  if (options !== undefined && options.conversationMedia !== true)
    throw new Error('Conversation media account purge unavailable')
  const conversationMedia = options?.conversationMedia === true
  const ordinaryRow = z.object({
    id: z.string().min(1),
    bucket_id: z.string().min(1),
    object_path: z.string().min(1),
    kind: z.enum([
      'meal_photo',
      'conversation_photo',
      'body_checkin_photo',
      'gym_photo',
      'audio_note',
      'content_cover',
      'plan_document',
    ]),
    reevaluation_origin_version: z.literal(1).nullable(),
  })
  const recurring = createReevaluationPhotoAccountPurgeDependencies(supabase)
  return {
    repository: {
      ...(conversationMedia
        ? {
            async prepareConversationMediaPurge(userId: string, cutoff: string) {
              try {
                const api = supabase as unknown as {
                  rpc(
                    name: string,
                    args: Record<string, unknown>,
                  ): {
                    abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }>
                  }
                }
                const result = await api
                  .rpc('prepare_conversation_media_account_purge', {
                    p_user_id: userId,
                    p_cutoff: cutoff,
                  })
                  .abortSignal(AbortSignal.timeout(5000))
                if (!result || result.error !== null || typeof result.data !== 'boolean')
                  throw new Error('unavailable')
                return result.data
              } catch {
                throw new Error('Conversation media account purge unavailable')
              }
            },
          }
        : {}),
      async listUsersReadyForPurge(cutoff, limit) {
        return claimDeletedUsersForPhotoPurge(supabase, cutoff, limit)
      },
      prepareRecurringMediaPurge(userId, cutoff) {
        return prepareReevaluationPhotoAccountPurge(recurring, userId, cutoff)
      },
      async listUserMedia(userId) {
        const query = supabase.from('media_assets')
        const { data, error } = await (conversationMedia
          ? query.select('id, bucket_id, object_path, kind, reevaluation_origin_version')
          : query.select('id, bucket_id, object_path')
        ).eq('user_id', userId)
        if (error)
          throw new Error(
            conversationMedia
              ? 'Conversation media account purge unavailable'
              : error.message || 'user media lookup failed',
          )
        // The independent expiry manifest owns ordinary payload revocation.
        // Never erase its zero-byte barrier, including after catalogue deletion.
        const parsed = conversationMedia ? z.array(ordinaryRow).safeParse(data ?? []) : undefined
        if (parsed && !parsed.success)
          throw new Error('Conversation media account purge unavailable')
        const rows = parsed?.success
          ? parsed.data.filter(
              (row) =>
                row.reevaluation_origin_version !== null ||
                !['conversation_photo', 'audio_note'].includes(row.kind),
            )
          : z
              .array(ordinaryRow.pick({ id: true, bucket_id: true, object_path: true }))
              .parse(data ?? [])
        return rows.map((row) => ({
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
