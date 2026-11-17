import {
  type ConversationMediaIdentityV2,
  conversationMediaIdentityV2Schema,
} from '@mpp/core/conversation-media'
import {
  privateMediaDisposalClaimV2Schema,
  revokePrivateConversationMediaV2,
} from '@mpp/core/conversation-media-disposal'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'

const preparedSchema = z
  .object({
    schema: z.literal('conversation.media-owned-disposal.v2'),
    catalog_version: z.literal(2),
    asset_id: z.string().uuid(),
    user_id: z.string().uuid(),
    claim: privateMediaDisposalClaimV2Schema.nullable(),
  })
  .strict()

/** Existing request client, one exact owner/source only. The global batch and
 * account purge capabilities are intentionally absent from this app adapter. */
export function createPrivateMediaSingleDisposal(client: ServiceClient) {
  const api = client as unknown as {
    rpc(
      name: string,
      args: Record<string, unknown>,
    ): {
      abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }>
    }
  }
  async function invoke(name: string, args: Record<string, unknown>) {
    const result = await api.rpc(name, args).abortSignal(AbortSignal.timeout(10000))
    if (!result || result.error !== null) throw Error('Private disposal unavailable')
    return result.data
  }
  return {
    async dispose(raw: ConversationMediaIdentityV2): Promise<void> {
      try {
        const identity = conversationMediaIdentityV2Schema.parse(raw)
        const prepared = preparedSchema.parse(
          await invoke('claim_conversation_media_owned_disposal_v2', {
            p_user_id: identity.user_id,
            p_asset_id: identity.asset_id,
          }),
        )
        if (
          prepared.user_id !== identity.user_id ||
          prepared.asset_id !== identity.asset_id ||
          !prepared.claim
        )
          throw Error('Private disposal unavailable')
        const { claim_token, ...observed } = prepared.claim
        if (
          JSON.stringify(conversationMediaIdentityV2Schema.parse(observed)) !==
          JSON.stringify(identity)
        )
          throw Error('Private disposal unavailable')
        const args = {
          p_user_id: identity.user_id,
          p_asset_id: identity.asset_id,
          p_claim_token: claim_token,
        }
        await revokePrivateConversationMediaV2(prepared.claim, {
          inspect: () => invoke('inspect_conversation_media_disposal_v2', args),
          acknowledge: () => invoke('acknowledge_conversation_media_disposal_v2', args),
          async removeVersion(version) {
            const storage = client.storage.from(identity.bucket_id) as unknown as {
              remove(
                paths: Array<{ path: string; versionId: string }>,
              ): PromiseLike<{ error: unknown }>
            }
            const result = await storage.remove([
              { path: identity.object_path, versionId: version },
            ])
            if (result.error) throw Error('Private disposal unavailable')
          },
          async installEmpty(mimeType) {
            const result = await client.storage
              .from(identity.bucket_id)
              .upload(identity.object_path, new Uint8Array(0), {
                upsert: false,
                contentType: mimeType,
                cacheControl: '0',
              })
            if (result.error) throw Error('Private disposal unavailable')
          },
        })
      } catch {
        throw new MobileApiError(503, 'media_disposal_unavailable', 'Media deletion unavailable')
      }
    },
  }
}
