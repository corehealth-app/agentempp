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
const revocationState = z
  .object({
    schema: z.literal('conversation.media-revocation-state.v1'),
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
  .refine((v) =>
    v.state === 'absent'
      ? v.size_bytes === null && v.object_version === null
      : v.state === 'empty'
        ? v.size_bytes === 0 && v.object_version !== null
        : v.size_bytes !== null && v.size_bytes > 0 && v.object_version !== null,
  )
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
  async function inspect(x: z.infer<typeof item>) {
    const result = revocationState.safeParse(
      await invoke('inspect_conversation_media_payload_revocation', {
        p_asset_id: x.asset_id,
        p_user_id: x.user_id,
        p_claim_token: x.claim_token,
      }),
    )
    if (
      !result.success ||
      result.data.asset_id !== x.asset_id ||
      result.data.user_id !== x.user_id ||
      result.data.claim_token !== x.claim_token ||
      result.data.bucket_id !== x.bucket_id ||
      result.data.object_path !== x.object_path ||
      result.data.mime_type !== (x.kind === 'conversation_photo' ? 'image/jpeg' : 'audio/mp4')
    )
      throw Error('Conversation media revocation unavailable')
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
          const before = await inspect(x)
          // Removing a pre-existing barrier would reopen the capability's path.
          if (before.state !== 'empty') {
            const storage = client.storage.from(bucketId)
            if (before.state === 'payload') {
              // The pinned SDK serializes prefixes unchanged. Its string-only
              // types predate Storage's {path,versionId} DELETE HTTP contract.
              // Delete only the inspected version: a stale job must never erase
              // a newer empty barrier installed while this request was paused.
              const versioned = storage as unknown as {
                remove(
                  paths: Array<{ path: string; versionId: string }>,
                ): PromiseLike<{ error: unknown }>
              }
              if (!before.object_version) throw Error('Object version unavailable')
              const { error } = await versioned.remove([
                { path: objectPath, versionId: before.object_version },
              ])
              if (error) throw Error('Removal failed')
            }
            const { error } = await storage.upload(objectPath, new Uint8Array(0), {
              upsert: false,
              contentType: before.mime_type,
              cacheControl: '0',
            })
            if (error) throw Error('Barrier write uncertain')
            if ((await inspect(x)).state !== 'empty') throw Error('Barrier not observed')
          }
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
