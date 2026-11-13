import {
  conversationMediaRevocationAckSchema as ack,
  conversationMediaRevocationClaimSchema as item,
  revokeConversationMediaPayload,
} from '@mpp/core/conversation-media-revocation'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MediaRetentionDependencies } from '../functions/media-retention-cleanup.js'

const page = z
  .object({
    schema: z.literal('conversation.media-expiry-page.v1'),
    items: z.array(item).max(100),
    has_more: z.boolean(),
  })
  .strict()
/** SQL first commits a private cleanup obligation and closes the catalogue.
 * A non-upsert empty object prevents later writes without retaining the payload.
 * Neither that object nor an acknowledgment proves final ticket-drain/disposal.
 * No environment, provider text, captions or identities appear in job results. */
export function createConversationMediaExpiryDependencies(
  client: ServiceClient,
): MediaRetentionDependencies {
  const claims = new Map<string, z.infer<typeof item>>()
  const sealed = new Set<string>()
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
        sealed.clear()
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
        if (!x || x.user_id !== userId || !sealed.has(assetId))
          throw Error('Conversation media expiry claim unavailable')
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
        const x = [...claims.values()].find(
          (x) => x.bucket_id === bucketId && x.object_path === objectPath,
        )
        if (!x) throw Error('Conversation media expiry claim unavailable')
        sealed.delete(x.asset_id)
        try {
          await revokeConversationMediaPayload(x, {
            inspect: () =>
              invoke('inspect_conversation_media_payload_revocation', {
                p_asset_id: x.asset_id,
                p_user_id: x.user_id,
                p_claim_token: x.claim_token,
              }),
            async removeVersion(version) {
              // SDK forwards the versioned HTTP prefix unchanged; never fall
              // back to an unversioned path that could erase a newer barrier.
              const storage = client.storage.from(bucketId) as unknown as {
                remove(
                  paths: Array<{ path: string; versionId: string }>,
                ): PromiseLike<{ error: unknown }>
              }
              const { error } = await storage.remove([{ path: objectPath, versionId: version }])
              if (error) throw Error('Removal failed')
            },
            async installEmpty(mimeType) {
              const { error } = await client.storage
                .from(bucketId)
                .upload(objectPath, new Uint8Array(0), {
                  upsert: false,
                  contentType: mimeType,
                  cacheControl: '0',
                })
              if (error) throw Error('Barrier write uncertain')
            },
          })
          sealed.add(x.asset_id)
        } catch {
          // Preserve the debt. The next claim inspects first, including after a
          // successful write whose response was lost; it never deletes a barrier.
          throw Error('Conversation media revocation unavailable')
        }
      },
    },
  }
}
