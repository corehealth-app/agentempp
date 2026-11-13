import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MediaRetentionDependencies } from '../functions/media-retention-cleanup.js'

const uuid = z
  .string()
  .uuid()
  .refine((v) => v === v.toLowerCase())
const item = z
  .object({
    asset_id: uuid,
    user_id: uuid,
    kind: z.enum(['conversation_photo', 'audio_note']),
    bucket_id: z.enum(['meal-photos', 'audio-notes']),
    object_path: z.string().min(1).max(512),
    claim_token: uuid,
  })
  .strict()
  .refine(
    (v) =>
      v.bucket_id === (v.kind === 'conversation_photo' ? 'meal-photos' : 'audio-notes') &&
      new RegExp(`^${v.user_id}/${v.asset_id}\\.[a-z0-9]+$`).test(v.object_path),
  )
const page = z
  .object({
    schema: z.literal('conversation.media-expiry-page.v1'),
    items: z.array(item).max(100),
    has_more: z.boolean(),
  })
  .strict()
const ack = z
  .object({
    schema: z.literal('conversation.media-expiry-ack.v1'),
    asset_id: uuid,
    user_id: uuid,
    claim_token: uuid,
    state: z.literal('waiting_for_issuance_drain'),
  })
  .strict()
/** SQL first commits a private cleanup obligation and closes the catalogue.
 * Storage removal only acknowledges a sweep, never final ticket-drain proof.
 * No environment, provider text, captions or identities appear in job results. */
export function createConversationMediaExpiryDependencies(
  client: ServiceClient,
): MediaRetentionDependencies {
  const claims = new Map<string, z.infer<typeof item>>()
  const api = client as unknown as {
    rpc(name: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>
  }
  async function invoke(name: string, args: Record<string, unknown>) {
    const result = await api.rpc(name, args)
    if (!result || result.error !== null) throw Error('Conversation media expiry unavailable')
    return result.data
  }
  return {
    repository: {
      async listExpired(_now, limit) {
        if (!Number.isInteger(limit) || limit < 1 || limit > 100)
          throw Error('Conversation media expiry unavailable')
        const result = page.parse(
          await invoke('claim_conversation_media_expiry_batch', { p_limit: limit }),
        )
        if (
          result.items.length > limit ||
          new Set(result.items.map((x) => x.asset_id)).size !== result.items.length
        )
          throw Error('Conversation media expiry unavailable')
        claims.clear()
        for (const x of result.items) claims.set(x.asset_id, x)
        return result.items.map((x) => ({
          id: x.asset_id,
          userId: x.user_id,
          bucketId: x.bucket_id,
          objectPath: x.object_path,
        }))
      },
      async markDeleted(assetId, userId) {
        const x = claims.get(assetId)
        if (!x || x.user_id !== userId) throw Error('Conversation media expiry claim unavailable')
        const result = ack.parse(
          await invoke('acknowledge_conversation_media_expiry_sweep', {
            p_asset_id: assetId,
            p_user_id: userId,
            p_claim_token: x.claim_token,
          }),
        )
        if (
          result.asset_id !== assetId ||
          result.user_id !== userId ||
          result.claim_token !== x.claim_token
        )
          throw Error('Conversation media expiry claim unavailable')
      },
    },
    storage: {
      async remove(bucketId, objectPath) {
        if (
          ![...claims.values()].some(
            (x) => x.bucket_id === bucketId && x.object_path === objectPath,
          )
        )
          throw Error('Conversation media expiry claim unavailable')
        const { error } = await client.storage.from(bucketId).remove([objectPath])
        if (error) throw Error('Conversation media expiry unavailable')
      },
    },
  }
}
