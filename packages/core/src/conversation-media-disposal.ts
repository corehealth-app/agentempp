import { z } from 'zod'
import { conversationMediaIdentityV2Schema } from './conversation-media-namespace'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
export const privateMediaDisposalClaimV2Schema = z
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

export interface PrivateMediaRevocationV2Ports {
  inspect(): Promise<unknown>
  removeVersion(version: string): Promise<void>
  installEmpty(mimeType: 'image/jpeg' | 'audio/mp4'): Promise<void>
  acknowledge(): Promise<unknown>
}

/** One committed private claim only. No database, SDK, environment, batch,
 * account or worker capability. An empty barrier is preserved, and successful
 * revocation never claims that outstanding upload authority was reconciled. */
export async function revokePrivateConversationMediaV2(
  raw: z.infer<typeof privateMediaDisposalClaimV2Schema>,
  ports: PrivateMediaRevocationV2Ports,
): Promise<void> {
  try {
    const claim = privateMediaDisposalClaimV2Schema.parse(raw)
    async function inspect() {
      const value = stateSchema.parse(await ports.inspect())
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
        await ports.removeVersion(before.object_version)
      }
      await ports.installEmpty(before.mime_type)
      if ((await inspect()).state !== 'empty') throw Error('Private media disposal unavailable')
    }
    const value = ackSchema.parse(await ports.acknowledge())
    if (
      value.asset_id !== claim.asset_id ||
      value.user_id !== claim.user_id ||
      value.claim_token !== claim.claim_token
    )
      throw Error('Private media disposal unavailable')
  } catch {
    throw Error('Private media disposal unavailable')
  }
}
