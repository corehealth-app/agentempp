import { describe, expect, it, vi } from 'vitest'
import {
  createMediaAsset,
  type MediaAssetRecord,
  type MediaServiceDependencies,
} from './media-service'

const user = '11110000-0000-4000-8000-000000000001',
  id = '11110000-0000-4000-8000-000000000002'
const now = new Date('2026-11-13T03:00:00.000Z')
function setup(kind: 'audio_note' | 'conversation_photo' | 'meal_photo' = 'audio_note') {
  const audio = kind === 'audio_note'
  const row = {
    id,
    user_id: user,
    kind,
    bucket_id: audio ? 'audio-notes' : 'meal-photos',
    object_path: `${user}/${id}.${audio ? 'm4a' : 'jpg'}`,
    mime_type: audio ? 'audio/mp4' : 'image/jpeg',
    declared_size_bytes: 100,
    actual_size_bytes: null,
    status: 'pending_upload',
    failure_stage: null,
    failure_code: null,
    context_text: null,
    retention_until: '2026-12-13T03:00:00.000Z',
    uploaded_at: null,
    processed_at: null,
    deleted_at: null,
    created_at: now.toISOString(),
    updated_at: now.toISOString(),
  } as MediaAssetRecord
  const actual = {
    signed_url: 'https://synthetic.invalid/tracked-upload',
    method: 'PUT' as const,
    headers: { 'Content-Type': row.mime_type, 'x-upsert': 'false' },
    expires_at: '2026-11-13T05:00:15.000Z',
  }
  const ordinaryUploads = { issue: vi.fn(async () => actual) }
  const storage = {
    createSignedUpload: vi.fn(async () => ({
      signedUrl: 'https://synthetic.invalid/legacy-upload',
    })),
  }
  const deps = {
    repository: {
      findByRequestHash: async () => structuredClone(row),
      findOwned: async () => structuredClone(row),
    },
    storage,
    ordinaryUploads,
  } as unknown as MediaServiceDependencies
  const run = () =>
    createMediaAsset(
      deps,
      user,
      kind === 'audio_note'
        ? { kind, mime_type: 'audio/mp4', size_bytes: 100 }
        : { kind, mime_type: 'image/jpeg', size_bytes: 100 },
      'same-request',
      now,
      id,
      { conversationPhotoEnabled: () => true },
    )
  return { row, deps, actual, ordinaryUploads, storage, run }
}
describe('ordinary upload ledger handoff in the actual media service', () => {
  it.each([
    'audio_note',
    'conversation_photo',
  ] as const)('returns the registered provider expiry for %s without an untracked signing fallback', async (kind) => {
    const a = setup(kind)
    const response = await a.run()
    expect(response.upload).toEqual(a.actual)
    expect(a.ordinaryUploads.issue).toHaveBeenCalledWith(a.row)
    expect(a.storage.createSignedUpload).not.toHaveBeenCalled()
  })
  it('preserves the generic default when the trusted feature is absent', async () => {
    const a = setup()
    delete (a.deps as unknown as { ordinaryUploads?: unknown }).ordinaryUploads
    const response = await a.run()
    expect(response.upload?.signed_url).toBe('https://synthetic.invalid/legacy-upload')
    expect(response.upload?.expires_at).toBe('2026-11-13T05:00:00.000Z')
  })
  it('does not add the ordinary ticket contract to legacy meal photographs', async () => {
    const a = setup('meal_photo')
    await a.run()
    expect(a.ordinaryUploads.issue).not.toHaveBeenCalled()
    expect(a.storage.createSignedUpload).toHaveBeenCalledOnce()
  })
  it('never retries signing outside the ledger after an uncertain tracked request', async () => {
    const a = setup()
    a.ordinaryUploads.issue.mockRejectedValue(new Error('tracked uncertainty'))
    await expect(a.run()).rejects.toThrow('tracked uncertainty')
    expect(a.storage.createSignedUpload).not.toHaveBeenCalled()
  })
})
