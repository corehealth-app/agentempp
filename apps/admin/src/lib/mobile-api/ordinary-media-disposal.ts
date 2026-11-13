import {
  conversationMediaRevocationAckSchema,
  conversationMediaRevocationClaimSchema,
  revokeConversationMediaPayload,
} from '@mpp/core/conversation-media-revocation'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'
import type { MediaAssetRecord } from './media-service'

const prepared = z
  .object({
    schema: z.literal('conversation.media-disposal.v1'),
    asset_id: z.string().uuid(),
    user_id: z.string().uuid(),
    claim: conversationMediaRevocationClaimSchema.nullable(),
  })
  .strict()

/** Only the trusted staging factory installs this port. Ownership comes from
 * the existing owned-asset lookup; SQL commits closure before returning a lease.
 * Provider text, URLs and customer paths never escape an error. */
export function createOrdinaryMediaDisposal(client: ServiceClient) {
  async function rpc(name: string, args: Record<string, unknown>) {
    const api = client as unknown as {
      rpc(
        name: string,
        args: Record<string, unknown>,
      ): {
        abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }>
      }
    }
    const result = await api.rpc(name, args).abortSignal(AbortSignal.timeout(10000))
    if (!result || result.error !== null) throw Error('Disposal unavailable')
    return result.data
  }
  return {
    async dispose(asset: MediaAssetRecord): Promise<void> {
      try {
        if (!['conversation_photo', 'audio_note'].includes(asset.kind)) throw Error('Wrong scope')
        const result = prepared.parse(
          await rpc('claim_conversation_media_disposal', {
            p_asset_id: asset.id,
            p_user_id: asset.user_id,
          }),
        )
        if (result.asset_id !== asset.id || result.user_id !== asset.user_id)
          throw Error('Wrong scope')
        const x = result.claim
        if (!x) throw Error('Disposal busy')
        if (
          x.asset_id !== asset.id ||
          x.user_id !== asset.user_id ||
          x.kind !== asset.kind ||
          x.bucket_id !== asset.bucket_id ||
          x.object_path !== asset.object_path
        )
          throw Error('Wrong claim')
        await revokeConversationMediaPayload(x, {
          inspect: () =>
            rpc('inspect_conversation_media_payload_revocation', {
              p_asset_id: x.asset_id,
              p_user_id: x.user_id,
              p_claim_token: x.claim_token,
            }),
          async removeVersion(version) {
            const storage = client.storage.from(x.bucket_id) as unknown as {
              remove(
                paths: Array<{ path: string; versionId: string }>,
              ): PromiseLike<{ error: unknown }>
            }
            const { error } = await storage.remove([{ path: x.object_path, versionId: version }])
            if (error) throw Error('Removal failed')
          },
          async installEmpty(mimeType) {
            const { error } = await client.storage
              .from(x.bucket_id)
              .upload(x.object_path, new Uint8Array(0), {
                upsert: false,
                contentType: mimeType,
                cacheControl: '0',
              })
            if (error) throw Error('Barrier write uncertain')
          },
        })
        const ack = conversationMediaRevocationAckSchema.parse(
          await rpc('acknowledge_conversation_media_expiry_sweep', {
            p_asset_id: x.asset_id,
            p_user_id: x.user_id,
            p_claim_token: x.claim_token,
          }),
        )
        if (
          ack.asset_id !== x.asset_id ||
          ack.user_id !== x.user_id ||
          ack.claim_token !== x.claim_token
        )
          throw Error('Claim changed')
      } catch {
        throw new MobileApiError(503, 'media_disposal_unavailable', 'Media deletion unavailable')
      }
    },
  }
}
