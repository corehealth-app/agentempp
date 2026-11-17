import { conversationMediaIdentityV2Schema } from '@mpp/core/conversation-media'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const claimSchema = z
  .object({
    catalog_version: z.literal(2),
    asset_id: uuid,
    user_id: uuid,
    kind: z.enum(['conversation_photo', 'audio_note']),
    bucket_id: z.enum(['meal-photos', 'audio-notes']),
    object_path: z.string().min(1).max(512),
    mime_type: z.string(),
    declared_size_bytes: z.number().int().positive(),
    claim_token: uuid,
  })
  .strict()
  .refine(
    ({ claim_token: _token, ...identity }) =>
      conversationMediaIdentityV2Schema.safeParse(identity).success,
  )
const pageSchema = z
  .object({
    schema: z.literal('conversation.media-disposal-page.v2'),
    items: z.array(claimSchema).max(100),
    has_more: z.boolean(),
  })
  .strict()
const stateSchema = z
  .object({
    schema: z.literal('conversation.media-disposal-state.v2'),
    catalog_version: z.literal(2),
    asset_id: uuid,
    user_id: uuid,
    claim_token: uuid,
    bucket_id: z.enum(['meal-photos', 'audio-notes']),
    object_path: z.string().min(1).max(512),
    bucket_private: z.literal(true),
    versioning: z.literal('DISABLED'),
    mime_type: z.enum(['image/jpeg', 'audio/mp4']),
    state: z.enum(['absent', 'empty', 'payload']),
    size_bytes: z.number().int().min(0).max(26214400).nullable(),
    object_version: uuid.nullable(),
  })
  .strict()
  .refine((value) =>
    value.state === 'absent'
      ? value.size_bytes === null && value.object_version === null
      : value.object_version !== null &&
        (value.state === 'empty'
          ? value.size_bytes === 0
          : value.size_bytes !== null && value.size_bytes > 0),
  )
const ackSchema = z
  .object({
    schema: z.literal('conversation.media-disposal-ack.v2'),
    catalog_version: z.literal(2),
    asset_id: uuid,
    user_id: uuid,
    claim_token: uuid,
    state: z.literal('barrier_retained'),
    issuance_reconciled: z.literal(false),
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
  async function revoke(claim: z.infer<typeof claimSchema>) {
    const args = {
      p_asset_id: claim.asset_id,
      p_user_id: claim.user_id,
      p_claim_token: claim.claim_token,
    }
    async function inspect() {
      const value = stateSchema.parse(await invoke('inspect_conversation_media_disposal_v2', args))
      if (
        value.asset_id !== claim.asset_id ||
        value.user_id !== claim.user_id ||
        value.claim_token !== claim.claim_token ||
        value.bucket_id !== claim.bucket_id ||
        value.object_path !== claim.object_path ||
        value.mime_type !== (claim.kind === 'conversation_photo' ? 'image/jpeg' : 'audio/mp4')
      )
        throw Error('Private media disposal unavailable')
      return value
    }
    const before = await inspect()
    if (before.state !== 'empty') {
      if (before.state === 'payload') {
        if (!before.object_version) throw Error('Private media disposal unavailable')
        const storage = client.storage.from(claim.bucket_id) as unknown as {
          remove(paths: Array<{ path: string; versionId: string }>): PromiseLike<{ error: unknown }>
        }
        // Never issue an unversioned remove, even on a retry or SDK error.
        const result = await storage.remove([
          { path: claim.object_path, versionId: before.object_version },
        ])
        if (result.error) throw Error('Private media disposal unavailable')
      }
      const result = await client.storage
        .from(claim.bucket_id)
        .upload(claim.object_path, new Uint8Array(0), {
          upsert: false,
          contentType: before.mime_type,
          cacheControl: '0',
        })
      if (result.error) throw Error('Private media disposal unavailable')
      if ((await inspect()).state !== 'empty') throw Error('Private media disposal unavailable')
    }
    const value = ackSchema.parse(await invoke('acknowledge_conversation_media_disposal_v2', args))
    if (
      value.asset_id !== claim.asset_id ||
      value.user_id !== claim.user_id ||
      value.claim_token !== claim.claim_token
    )
      throw Error('Private media disposal unavailable')
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
