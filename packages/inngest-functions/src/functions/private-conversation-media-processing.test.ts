import { describe, expect, it, vi } from 'vitest'
import { processPrivateConversationMedia } from './private-conversation-media-processing.js'

const userId = 'c3672000-0000-4000-8000-000000000001'
const assetId = 'c3672000-0000-4000-8000-000000000002'
const token = 'c3672000-0000-4000-8000-000000000003'
const requestId = 'a'.repeat(64)
const input = { userId, assetId, requestId }
const at = '2026-11-17T12:00:00.000Z',
  lease = '2026-11-17T12:05:00.000Z',
  until = '2026-12-17T12:00:00.000Z'
const photoResult = {
  schema: 'conversation.image-result.v1',
  status: 'ready',
  classification: 'meal',
  analysis: {
    type: 'meal',
    items: [{ name: 'arroz cozido', quantity_g_estimate: 100, confidence: 0.8 }],
  },
}
function setup(kind: 'conversation_photo' | 'audio_note' = 'conversation_photo') {
  const photo = kind === 'conversation_photo'
  const bytes = photo
    ? new Uint8Array([255, 216, 255, 224])
    : new TextEncoder().encode('OggSsynthetic')
  const identity = {
    catalog_version: 2,
    asset_id: assetId,
    user_id: userId,
    kind,
    bucket_id: photo ? 'meal-photos' : 'audio-notes',
    object_path: `conversation-v2/${userId}/${assetId}.${photo ? 'jpg' : 'ogg'}`,
    mime_type: photo ? 'image/jpeg' : 'audio/ogg',
    declared_size_bytes: bytes.byteLength,
  }
  const claim = {
    schema: 'conversation.media-processing-claim.v2',
    action: 'claimed',
    asset: {
      identity,
      state: { status: 'processing', created_at: at, retention_until: until },
      context_text: 'meu almoço',
      processing_request_id: requestId,
    },
    claim: { token, lease_until: lease },
  }
  const row = {
    id: assetId,
    user_id: userId,
    kind,
    bucket_id: identity.bucket_id,
    object_path: identity.object_path,
    mime_type: identity.mime_type,
    declared_size_bytes: bytes.byteLength,
    actual_size_bytes: bytes.byteLength,
    etag: 'test-etag',
    status: 'processing',
    failure_stage: null,
    failure_code: null,
    context_text: 'meu almoço',
    processing_request_id: requestId,
    processing_result: null,
    source_request_hash: requestId,
    retention_until: until,
    uploaded_at: at,
    processed_at: null,
    deleted_at: null,
    created_at: at,
    updated_at: at,
  }
  let persisted: unknown
  const catalog = {
    claimProcessing: vi.fn().mockResolvedValue(claim),
    findOwned: vi.fn().mockResolvedValue(row),
    completeProcessing: vi.fn().mockImplementation(async (_s, _r, _t, result) => {
      persisted = result
      return true
    }),
    failProcessing: vi.fn().mockResolvedValue(true),
  }
  const deps = {
    catalog,
    now: () => new Date('2026-11-17T12:00:01.000Z'),
    storage: { download: vi.fn().mockResolvedValue(bytes) },
    providers: {
      analyzeImage: vi.fn().mockResolvedValue(photoResult),
      transcribeAudio: vi.fn().mockResolvedValue({
        text: 'tomei leite com whey',
        language: 'pt',
        duration: 3,
        latencyMs: 20,
        raw_response: 'must not persist',
      }),
    },
    measureAudioDuration: vi.fn().mockResolvedValue(3),
  }
  return { deps, catalog, identity, claim, row, bytes, persisted: () => persisted }
}

describe('private conversation processing with owner-bound leases', () => {
  it('downloads only the private key and persists a validated nonclinical observation once', async () => {
    const s = setup()
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual({ status: 'processed' })
    expect(s.deps.storage.download).toHaveBeenCalledWith(
      'meal-photos',
      `conversation-v2/${userId}/${assetId}.jpg`,
    )
    expect(s.deps.providers.analyzeImage).toHaveBeenCalledWith({
      bytes: s.bytes,
      mimeType: 'image/jpeg',
      contextText: 'meu almoço',
    })
    expect(s.catalog.completeProcessing).toHaveBeenCalledWith(
      { userId, assetId },
      requestId,
      token,
      photoResult,
    )
    expect(s.persisted()).toEqual(photoResult)
  })

  it('measures audio before transcription and drops provider-only fields from the retained result', async () => {
    const s = setup('audio_note')
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual({ status: 'processed' })
    expect(s.persisted()).toEqual({
      text: 'tomei leite com whey',
      language: 'pt',
      duration: 3,
      latencyMs: 20,
    })
    expect(s.deps.measureAudioDuration.mock.invocationCallOrder[0]).toBeLessThan(
      s.deps.providers.transcribeAudio.mock.invocationCallOrder[0] ?? 0,
    )
    expect(s.deps.providers.analyzeImage).not.toHaveBeenCalled()
  })

  it.each([
    'busy',
    'unavailable',
  ])('does not download or call a model when the claim is %s', async (action) => {
    const s = setup()
    s.catalog.claimProcessing.mockResolvedValue({
      schema: 'conversation.media-processing-claim.v2',
      action,
      ...(action === 'busy' ? { retry_at: lease } : {}),
    })
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual(
      action === 'busy' ? { status: 'busy', retry_at: lease } : { status: 'skipped' },
    )
    expect(s.deps.storage.download).not.toHaveBeenCalled()
    expect(s.deps.providers.analyzeImage).not.toHaveBeenCalled()
    expect(s.catalog.completeProcessing).not.toHaveBeenCalled()
  })

  it.each([
    'owner',
    'request',
    'legacy-path',
    'clinical-kind',
  ])('refuses a changed claimed scope: %s', async (change) => {
    const s = setup()
    if (change === 'owner') s.claim.asset.identity.user_id = 'c3672000-0000-4000-8000-000000000099'
    if (change === 'request') s.claim.asset.processing_request_id = 'b'.repeat(64)
    if (change === 'legacy-path') s.claim.asset.identity.object_path = `${userId}/${assetId}.jpg`
    if (change === 'clinical-kind')
      Object.assign(s.claim.asset.identity, { kind: 'body_checkin_photo' })
    await expect(processPrivateConversationMedia(s.deps, input)).rejects.toThrow(
      'Private media operation unavailable',
    )
    expect(s.deps.storage.download).not.toHaveBeenCalled()
    expect(s.catalog.failProcessing).not.toHaveBeenCalled()
  })

  it.each([
    'size',
    'signature',
  ])('refuses invalid downloaded %s before paying a provider', async (change) => {
    const s = setup()
    s.deps.storage.download.mockResolvedValue(
      change === 'size' ? new Uint8Array([255, 216, 255]) : new Uint8Array([0, 0, 0, 0]),
    )
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual({
      status: 'failed',
      reason: change === 'size' ? 'media_size_mismatch' : 'invalid_file_signature',
    })
    expect(s.deps.providers.analyzeImage).not.toHaveBeenCalled()
    expect(s.catalog.completeProcessing).not.toHaveBeenCalled()
  })

  it.each([
    null,
    0,
    Number.NaN,
    180.01,
  ])('refuses unreadable or excessive audio duration %s before transcription', async (duration) => {
    const s = setup('audio_note')
    s.deps.measureAudioDuration.mockResolvedValue(duration)
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual({
      status: 'failed',
      reason: duration !== null && duration > 180 ? 'audio_too_long' : 'audio_duration_unreadable',
    })
    expect(s.deps.providers.transcribeAudio).not.toHaveBeenCalled()
  })

  it('rechecks disposal after download before invoking a paid provider', async () => {
    const s = setup()
    s.catalog.findOwned.mockResolvedValue(null)
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual({ status: 'skipped' })
    expect(s.deps.providers.analyzeImage).not.toHaveBeenCalled()
    expect(s.catalog.failProcessing).not.toHaveBeenCalled()
  })

  it('defers an expired lease without making another provider call', async () => {
    const s = setup()
    s.deps.now = () => new Date(lease)
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual({
      status: 'busy',
      retry_at: lease,
    })
    expect(s.deps.storage.download).not.toHaveBeenCalled()
    expect(s.deps.providers.analyzeImage).not.toHaveBeenCalled()
  })

  it('does not resurrect a source disposed while the provider was running', async () => {
    const s = setup()
    s.catalog.completeProcessing.mockResolvedValue(false)
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual({ status: 'skipped' })
    expect(s.catalog.failProcessing).not.toHaveBeenCalled()
  })

  it('retains unsupported body observations without treating them as a clinical assessment', async () => {
    const s = setup()
    const observation = {
      schema: 'conversation.image-result.v1',
      status: 'unsupported',
      classification: 'body',
      reason: 'image_not_supported_for_conversation',
    }
    s.deps.providers.analyzeImage.mockResolvedValue(observation)
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual({ status: 'processed' })
    expect(s.persisted()).toEqual(observation)
  })

  it('sanitizes model errors and marks only the current claim as failed', async () => {
    const s = setup()
    s.deps.providers.analyzeImage.mockRejectedValue(new Error('private provider diagnostic'))
    expect(await processPrivateConversationMedia(s.deps, input)).toEqual({
      status: 'failed',
      reason: 'provider_error',
    })
    expect(s.catalog.failProcessing).toHaveBeenCalledWith(
      { userId, assetId },
      requestId,
      token,
      'provider_error',
    )
    expect(s.catalog.completeProcessing).not.toHaveBeenCalled()
  })

  it('never marks failure or repeats the provider after an uncertain completion', async () => {
    const s = setup()
    s.catalog.completeProcessing.mockRejectedValue(new Error('private database diagnostic'))
    await expect(processPrivateConversationMedia(s.deps, input)).rejects.toThrow(
      'Private media operation unavailable',
    )
    expect(s.deps.providers.analyzeImage).toHaveBeenCalledTimes(1)
    expect(s.catalog.completeProcessing).toHaveBeenCalledTimes(1)
    expect(s.catalog.failProcessing).not.toHaveBeenCalled()
  })
})
