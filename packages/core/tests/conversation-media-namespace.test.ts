import { describe, expect, it } from 'vitest'
import {
  conversationMediaIdentityV2Schema,
  createConversationMediaIdentityV2,
} from '../src/conversation-media-namespace'

const userId = 'c3660000-0000-4000-8000-000000000001'
const assetId = 'c3660000-0000-4000-8000-000000000002'
const source = {
  userId,
  assetId,
  kind: 'audio_note' as const,
  mimeType: 'audio/mp4',
  declaredSizeBytes: 8,
}

describe('private conversational media namespace', () => {
  it.each([
    ['audio_note', 'audio/mp4', 'audio-notes', 'm4a'],
    ['audio_note', 'audio/x-m4a', 'audio-notes', 'm4a'],
    ['audio_note', 'audio/mpeg', 'audio-notes', 'mp3'],
    ['audio_note', 'audio/aac', 'audio-notes', 'aac'],
    ['audio_note', 'audio/wav', 'audio-notes', 'wav'],
    ['audio_note', 'audio/x-wav', 'audio-notes', 'wav'],
    ['audio_note', 'audio/ogg', 'audio-notes', 'ogg'],
    ['conversation_photo', 'image/jpeg', 'meal-photos', 'jpg'],
    ['conversation_photo', 'image/png', 'meal-photos', 'png'],
    ['conversation_photo', 'image/webp', 'meal-photos', 'webp'],
    ['conversation_photo', 'image/heic', 'meal-photos', 'heic'],
    ['conversation_photo', 'image/heif', 'meal-photos', 'heif'],
  ] as const)('binds %s / %s to a disjoint path', (kind, mimeType, bucket, extension) => {
    const actual = createConversationMediaIdentityV2({ ...source, kind, mimeType })
    expect(actual).toEqual({
      catalog_version: 2,
      user_id: userId,
      asset_id: assetId,
      kind,
      bucket_id: bucket,
      object_path: `conversation-v2/${userId}/${assetId}.${extension}`,
      mime_type: mimeType,
      declared_size_bytes: 8,
    })
    expect(actual.object_path).not.toMatch(new RegExp(`^${userId}/${assetId}\\.[a-z0-9]+$`))
    expect(conversationMediaIdentityV2Schema.parse(actual)).toEqual(actual)
  })

  it.each([
    { user_id: 'c3660000-0000-4000-8000-000000000003' },
    { asset_id: 'c3660000-0000-4000-8000-000000000004' },
    { catalog_version: 1 },
    { bucket_id: 'meal-photos' },
    { kind: 'body_checkin_photo' },
    { kind: 'meal_photo' },
    { kind: 'gym_photo' },
    { object_path: `${userId}/${assetId}.m4a` },
    { object_path: `conversation-v2/${userId}/${assetId}.jpg` },
    { object_path: `conversation-v2/${userId}/../${assetId}.m4a` },
    { object_path: `conversation-v2/${userId}/${assetId}.m4a/extra` },
    { object_path: `conversation-v2%2F${userId}/${assetId}.m4a` },
    { object_path: `conversation-v2/${userId}/${assetId}.m4a?token=x` },
    { mime_type: 'image/jpeg' },
    { mime_type: 'audio/MP4' },
    { declared_size_bytes: 0 },
    { declared_size_bytes: -1 },
    { declared_size_bytes: 0.5 },
    { declared_size_bytes: 26214401 },
    { privileged: true },
  ])('refuses a changed identity or unsupported scope: %j', (change) => {
    const actual = createConversationMediaIdentityV2(source)
    expect(conversationMediaIdentityV2Schema.safeParse({ ...actual, ...change }).success).toBe(
      false,
    )
  })

  it('preserves the existing ordinary photo and audio size limits', () => {
    expect(() =>
      createConversationMediaIdentityV2({ ...source, declaredSizeBytes: 26214400 }),
    ).not.toThrow()
    expect(() =>
      createConversationMediaIdentityV2({
        ...source,
        kind: 'conversation_photo',
        mimeType: 'image/jpeg',
        declaredSizeBytes: 15728640,
      }),
    ).not.toThrow()
    expect(() =>
      createConversationMediaIdentityV2({
        ...source,
        kind: 'conversation_photo',
        mimeType: 'image/jpeg',
        declaredSizeBytes: 15728641,
      }),
    ).toThrow()
  })

  it('does not accept noncanonical owner/asset strings when generating a key', () => {
    expect(() =>
      createConversationMediaIdentityV2({ ...source, userId: userId.toUpperCase() }),
    ).toThrow()
    expect(() => createConversationMediaIdentityV2({ ...source, assetId: '../file' })).toThrow()
  })
})
