import { z } from 'zod'

const uuid = z
  .string()
  .uuid()
  .refine((v) => v === v.toLowerCase())
export const conversationMediaRevocationClaimSchema = z
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

export const conversationMediaRevocationAckSchema = z
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

export type ConversationMediaRevocationClaim = z.infer<
  typeof conversationMediaRevocationClaimSchema
>
export interface ConversationMediaRevocationPorts {
  inspect(): Promise<unknown>
  removeVersion(version: string): Promise<void>
  installEmpty(mimeType: 'image/jpeg' | 'audio/mp4'): Promise<void>
}

/** Shared byte-revocation algorithm only. No SDK, environment, job or account
 * access. Callers bind the committed lease and use version-targeted Storage.
 * An empty barrier is preserved; success does not mean final ticket drain. */
export async function revokeConversationMediaPayload(
  claim: ConversationMediaRevocationClaim,
  ports: ConversationMediaRevocationPorts,
): Promise<void> {
  try {
    const x = conversationMediaRevocationClaimSchema.parse(claim)
    async function inspect() {
      const result = revocationState.safeParse(await ports.inspect())
      if (
        !result.success ||
        result.data.asset_id !== x.asset_id ||
        result.data.user_id !== x.user_id ||
        result.data.claim_token !== x.claim_token ||
        result.data.bucket_id !== x.bucket_id ||
        result.data.object_path !== x.object_path ||
        result.data.mime_type !== (x.kind === 'conversation_photo' ? 'image/jpeg' : 'audio/mp4')
      )
        throw Error('Invalid revocation state')
      return result.data
    }
    const before = await inspect()
    if (before.state === 'empty') return
    if (before.state === 'payload') {
      if (!before.object_version) throw Error('Object version unavailable')
      await ports.removeVersion(before.object_version)
    }
    await ports.installEmpty(before.mime_type)
    if ((await inspect()).state !== 'empty') throw Error('Barrier not observed')
  } catch {
    throw Error('Conversation media revocation unavailable')
  }
}
