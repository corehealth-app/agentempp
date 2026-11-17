import {
  privateMediaDisposalClaimV2Schema,
  revokePrivateConversationMediaV2,
} from '@mpp/core/conversation-media-disposal'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const pageSchema = z
  .object({
    schema: z.literal('conversation.media-disposal-page.v2'),
    items: z.array(privateMediaDisposalClaimV2Schema).max(100),
    has_more: z.boolean(),
  })
  .strict()
/** Explicit private-catalog composition only. No client construction, job,
 * environment lookup, legacy fallback, provider retry or global activation.
 * SQL commits closure/lease before external IO and verifies emptiness on ack.
 * Empty barriers are retained; unresolved issuance is never marked reconciled. */
export function createPrivateMediaDisposalV2(client: ServiceClient) {
  const api = client as unknown as {
    rpc(name: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>
  }
  async function invoke(name: string, args: Record<string, unknown>) {
    const result = await api.rpc(name, args)
    if (!result || result.error !== null) throw Error('Private media disposal unavailable')
    return result.data
  }
  async function safe<T>(operation: () => Promise<T>) {
    try {
      return await operation()
    } catch {
      throw Error('Private media disposal unavailable')
    }
  }
  async function revoke(claim: z.infer<typeof privateMediaDisposalClaimV2Schema>) {
    const args = {
      p_asset_id: claim.asset_id,
      p_user_id: claim.user_id,
      p_claim_token: claim.claim_token,
    }
    await revokePrivateConversationMediaV2(claim, {
      inspect: () => invoke('inspect_conversation_media_disposal_v2', args),
      acknowledge: () => invoke('acknowledge_conversation_media_disposal_v2', args),
      async removeVersion(version) {
        const storage = client.storage.from(claim.bucket_id) as unknown as {
          remove(paths: Array<{ path: string; versionId: string }>): PromiseLike<{ error: unknown }>
        }
        const result = await storage.remove([{ path: claim.object_path, versionId: version }])
        if (result.error) throw Error('Private media disposal unavailable')
      },
      async installEmpty(mimeType) {
        const result = await client.storage
          .from(claim.bucket_id)
          .upload(claim.object_path, new Uint8Array(0), {
            upsert: false,
            contentType: mimeType,
            cacheControl: '0',
          })
        if (result.error) throw Error('Private media disposal unavailable')
      },
    })
  }
  return {
    sweep(limit = 100): Promise<{ swept: number; hasMore: boolean }> {
      return safe(async () => {
        z.number().int().min(1).max(100).parse(limit)
        const page = pageSchema.parse(
          await invoke('claim_conversation_media_disposal_batch_v2', { p_limit: limit }),
        )
        if (
          page.items.length > limit ||
          new Set(page.items.map((x) => x.asset_id)).size !== page.items.length
        )
          throw Error('Private media disposal unavailable')
        let swept = 0
        for (const claim of page.items) {
          await revoke(claim)
          swept += 1
        }
        return { swept, hasMore: page.has_more }
      })
    },
    closeOwned(userId: string, assetId: string): Promise<boolean> {
      return safe(async () =>
        z.boolean().parse(
          await invoke('close_conversation_media_v2', {
            p_user_id: uuid.parse(userId),
            p_asset_id: uuid.parse(assetId),
          }),
        ),
      )
    },
    prepareAccountPurge(userId: string, cutoff: string): Promise<boolean> {
      return safe(async () =>
        z.boolean().parse(
          await invoke('prepare_conversation_media_account_purge_v2', {
            p_user_id: uuid.parse(userId),
            p_cutoff: z.string().datetime({ offset: true }).parse(cutoff),
          }),
        ),
      )
    },
  }
}
