import { z } from 'zod'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const extensions = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a',
  'audio/x-m4a': 'm4a',
  'audio/aac': 'aac',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav',
  'audio/ogg': 'ogg',
} as const
const mime = z.enum([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'audio/mpeg',
  'audio/mp4',
  'audio/x-m4a',
  'audio/aac',
  'audio/wav',
  'audio/x-wav',
  'audio/ogg',
])

/** Shape and lineage validation only. Authentication, catalog authority and
 * committed disposal are separate capabilities; a valid path grants none. */
export const conversationMediaIdentityV2Schema = z
  .object({
    catalog_version: z.literal(2),
    user_id: uuid,
    asset_id: uuid,
    kind: z.enum(['conversation_photo', 'audio_note']),
    bucket_id: z.enum(['meal-photos', 'audio-notes']),
    object_path: z.string().min(1).max(512),
    mime_type: mime,
    declared_size_bytes: z.number().int().positive().max(26214400),
  })
  .strict()
  .refine((value) => {
    const photo = value.kind === 'conversation_photo'
    return (
      value.bucket_id === (photo ? 'meal-photos' : 'audio-notes') &&
      value.mime_type.startsWith(photo ? 'image/' : 'audio/') &&
      (!photo || value.declared_size_bytes <= 15728640) &&
      value.object_path ===
        `conversation-v2/${value.user_id}/${value.asset_id}.${extensions[value.mime_type]}`
    )
  })

export type ConversationMediaIdentityV2 = z.infer<typeof conversationMediaIdentityV2Schema>

/** Pure key generation for the private catalog; never a legacy public mirror. */
export function createConversationMediaIdentityV2(input: {
  userId: string
  assetId: string
  kind: 'conversation_photo' | 'audio_note'
  mimeType: string
  declaredSizeBytes: number
}): ConversationMediaIdentityV2 {
  const mimeType = mime.parse(input.mimeType)
  return conversationMediaIdentityV2Schema.parse({
    catalog_version: 2,
    user_id: input.userId,
    asset_id: input.assetId,
    kind: input.kind,
    bucket_id: input.kind === 'conversation_photo' ? 'meal-photos' : 'audio-notes',
    object_path: `conversation-v2/${input.userId}/${input.assetId}.${extensions[mimeType]}`,
    mime_type: mimeType,
    declared_size_bytes: input.declaredSizeBytes,
  })
}
