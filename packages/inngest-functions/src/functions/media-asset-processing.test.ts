import { describe, expect, it, vi } from 'vitest'
import {
  MAX_AUDIO_DURATION_SECONDS,
  type MediaProcessingDependencies,
  measureAudioDurationFromContainer,
  type ProcessableMediaAsset,
  processMediaAsset,
} from './media-asset-processing.js'

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10])
const mp3 = new Uint8Array([0x49, 0x44, 0x33, 0x04, 0x00, 0x00])

function record(overrides: Partial<ProcessableMediaAsset> = {}): ProcessableMediaAsset {
  return {
    id: 'asset-1',
    user_id: 'user-1',
    kind: 'meal_photo',
    bucket_id: 'meal-photos',
    object_path: 'user-1/asset-1.jpg',
    mime_type: 'image/jpeg',
    context_text: 'Frango grelhado com arroz',
    status: 'processing',
    processing_request_id: 'request-1',
    ...overrides,
  }
}

function makeDeps(asset: ProcessableMediaAsset | null = record()): MediaProcessingDependencies {
  return {
    repository: {
      claim: vi.fn().mockResolvedValue(asset),
      markProcessed: vi.fn().mockResolvedValue(undefined),
      markFailed: vi.fn().mockResolvedValue(undefined),
    },
    storage: { download: vi.fn().mockResolvedValue(jpeg) },
    providers: {
      analyzeImage: vi.fn().mockResolvedValue({ items: [{ name: 'frango' }] }),
      transcribeAudio: vi.fn().mockResolvedValue({ text: 'Treino de quarenta minutos' }),
    },
    // The 6-byte fixtures are not real audio; the duration reader is replaced
    // here and exercised on real bytes in its own tests below.
    measureAudioDuration: vi.fn().mockResolvedValue(40),
  }
}

/** A real PCM WAV file (8 kHz, mono, 8 bit) of the given length. */
function wav(seconds: number): Uint8Array {
  const sampleRate = 8000
  const dataSize = Math.round(seconds * sampleRate)
  const bytes = new Uint8Array(44 + dataSize).fill(0x80)
  const view = new DataView(bytes.buffer)
  const ascii = (offset: number, text: string) =>
    [...text].forEach((char, index) => {
      view.setUint8(offset + index, char.charCodeAt(0))
    })
  ascii(0, 'RIFF')
  view.setUint32(4, 36 + dataSize, true)
  ascii(8, 'WAVE')
  ascii(12, 'fmt ')
  view.setUint32(16, 16, true)
  view.setUint16(20, 1, true)
  view.setUint16(22, 1, true)
  view.setUint32(24, sampleRate, true)
  view.setUint32(28, sampleRate, true)
  view.setUint16(32, 1, true)
  view.setUint16(34, 8, true)
  ascii(36, 'data')
  view.setUint32(40, dataSize, true)
  return bytes
}

describe('media asset processing', () => {
  function neutral() {
    const who = {
      assetId: '11110000-0000-4000-8000-000000000001',
      userId: '11110000-0000-4000-8000-000000000002',
      requestId: 'a'.repeat(64),
    }
    const deps = makeDeps(
      record({
        id: who.assetId,
        user_id: who.userId,
        kind: 'conversation_photo',
        object_path: `${who.userId}/${who.assetId}.jpg`,
        processing_request_id: who.requestId,
      }),
    )
    deps.conversationPhotosEnabled = () => true
    const ready = {
      schema: 'conversation.image-result.v1',
      status: 'ready',
      classification: 'equipment',
      analysis: { type: 'equipment', equipment: ['halteres'], location: 'casa', confidence: 0.9 },
    }
    vi.mocked(deps.providers.analyzeImage).mockResolvedValue(ready)
    return { who, deps, ready }
  }
  it('dispatches only the neutral purpose and preserves its versioned observations', async () => {
    const f = neutral()
    expect(await processMediaAsset(f.deps, f.who)).toEqual({ status: 'processed' })
    expect(f.deps.providers.analyzeImage).toHaveBeenCalledWith(
      expect.objectContaining({ kind: 'conversation_photo' }),
    )
    expect(f.deps.repository.markProcessed).toHaveBeenCalledWith(
      f.who.assetId,
      f.who.userId,
      f.who.requestId,
      f.ready,
    )
  })
  it('holds the new purpose off before downloading or invoking AI', async () => {
    const f = neutral()
    f.deps.conversationPhotosEnabled = () => false
    expect(await processMediaAsset(f.deps, f.who)).toEqual({
      status: 'failed',
      reason: 'conversation_photo_unavailable',
    })
    expect(f.deps.storage.download).not.toHaveBeenCalled()
    expect(f.deps.providers.analyzeImage).not.toHaveBeenCalled()
  })
  it.each([
    'download',
    'provider',
  ] as const)('honors live revocation after %s without publishing a result', async (phase) => {
    const f = neutral()
    let enabled = true
    f.deps.conversationPhotosEnabled = () => enabled
    if (phase === 'download')
      vi.mocked(f.deps.storage.download).mockImplementation(async () => {
        enabled = false
        return jpeg
      })
    else
      vi.mocked(f.deps.providers.analyzeImage).mockImplementation(async () => {
        enabled = false
        return f.ready
      })
    expect(await processMediaAsset(f.deps, f.who)).toEqual({
      status: 'failed',
      reason: 'conversation_photo_unavailable',
    })
    expect(f.deps.repository.markProcessed).not.toHaveBeenCalled()
    if (phase === 'download') expect(f.deps.providers.analyzeImage).not.toHaveBeenCalled()
    expect(f.deps.repository.markFailed).toHaveBeenCalledWith(
      f.who.assetId,
      f.who.userId,
      f.who.requestId,
      'conversation_photo_unavailable',
    )
  })
  it('captures the original request and claimed metadata before asynchronous mutations', async () => {
    const f = neutral(),
      original = { ...f.who }
    const row = record({
      id: original.assetId,
      user_id: original.userId,
      kind: 'conversation_photo',
      object_path: `${original.userId}/${original.assetId}.jpg`,
      processing_request_id: original.requestId,
    })
    vi.mocked(f.deps.repository.claim).mockImplementation(async () => {
      f.who.userId = '11110000-0000-4000-8000-000000000099'
      f.who.requestId = 'b'.repeat(64)
      return row
    })
    vi.mocked(f.deps.storage.download).mockImplementation(async () => {
      row.kind = 'body_checkin_photo'
      row.context_text = 'changed caption'
      return jpeg
    })
    expect(await processMediaAsset(f.deps, f.who)).toEqual({ status: 'processed' })
    expect(f.deps.providers.analyzeImage).toHaveBeenCalledWith(
      expect.objectContaining({
        kind: 'conversation_photo',
        contextText: 'Frango grelhado com arroz',
      }),
    )
    expect(f.deps.repository.markProcessed).toHaveBeenCalledWith(
      original.assetId,
      original.userId,
      original.requestId,
      f.ready,
    )
  })
  it('rejects a mismatched original owner before inspecting private bytes', async () => {
    const f = neutral()
    expect(
      await processMediaAsset(f.deps, { ...f.who, userId: '11110000-0000-4000-8000-000000000003' }),
    ).toEqual({ status: 'failed', reason: 'conversation_photo_scope_changed' })
    expect(f.deps.storage.download).not.toHaveBeenCalled()
    expect(f.deps.providers.analyzeImage).not.toHaveBeenCalled()
  })
  it('cannot persist a clinical analysis under the neutral purpose', async () => {
    const f = neutral()
    vi.mocked(f.deps.providers.analyzeImage).mockResolvedValue({
      type: 'body',
      bf_percent_estimate: 20,
    })
    await expect(processMediaAsset(f.deps, f.who)).rejects.toThrow()
    expect(f.deps.repository.markProcessed).not.toHaveBeenCalled()
    expect(f.deps.repository.markFailed).toHaveBeenCalledWith(
      f.who.assetId,
      f.who.userId,
      f.who.requestId,
      'provider_error',
    )
  })
  it('keeps a safe unsupported result terminal rather than retrying as a body check-in', async () => {
    const f = neutral(),
      result = {
        schema: 'conversation.image-result.v1',
        status: 'unsupported',
        classification: 'body',
        reason: 'image_not_supported_for_conversation',
      }
    vi.mocked(f.deps.providers.analyzeImage).mockResolvedValue(result)
    expect(await processMediaAsset(f.deps, f.who)).toEqual({ status: 'processed' })
    expect(f.deps.repository.markProcessed).toHaveBeenCalledWith(
      f.who.assetId,
      f.who.userId,
      f.who.requestId,
      result,
    )
    expect(f.deps.providers.analyzeImage).toHaveBeenCalledOnce()
  })
  it('validates and analyzes an image together with its user caption', async () => {
    const deps = makeDeps()

    await expect(
      processMediaAsset(deps, { assetId: 'asset-1', userId: 'user-1', requestId: 'request-1' }),
    ).resolves.toEqual({ status: 'processed' })
    expect(deps.providers.analyzeImage).toHaveBeenCalledWith({
      bytes: jpeg,
      mimeType: 'image/jpeg',
      contextText: 'Frango grelhado com arroz',
      kind: 'meal_photo',
    })
    expect(deps.providers.transcribeAudio).not.toHaveBeenCalled()
    expect(deps.repository.markProcessed).toHaveBeenCalledWith('asset-1', 'user-1', 'request-1', {
      items: [{ name: 'frango' }],
    })
  })

  it('transcribes audio without calling the image model', async () => {
    const deps = makeDeps(
      record({
        kind: 'audio_note',
        bucket_id: 'audio-notes',
        object_path: 'user-1/asset-1.mp3',
        mime_type: 'audio/mpeg',
        context_text: null,
      }),
    )
    vi.mocked(deps.storage.download).mockResolvedValue(mp3)

    await processMediaAsset(deps, {
      assetId: 'asset-1',
      userId: 'user-1',
      requestId: 'request-1',
    })

    expect(deps.providers.transcribeAudio).toHaveBeenCalledWith({
      bytes: mp3,
      mimeType: 'audio/mpeg',
    })
    expect(deps.providers.analyzeImage).not.toHaveBeenCalled()
  })

  it('rejects spoofed file content before any AI provider call', async () => {
    const deps = makeDeps()
    vi.mocked(deps.storage.download).mockResolvedValue(new TextEncoder().encode('<svg></svg>'))

    await expect(
      processMediaAsset(deps, { assetId: 'asset-1', userId: 'user-1', requestId: 'request-1' }),
    ).resolves.toEqual({ status: 'failed', reason: 'invalid_file_signature' })
    expect(deps.providers.analyzeImage).not.toHaveBeenCalled()
    expect(deps.providers.transcribeAudio).not.toHaveBeenCalled()
    expect(deps.repository.markFailed).toHaveBeenCalledWith(
      'asset-1',
      'user-1',
      'request-1',
      'invalid_file_signature',
    )
  })

  it('does nothing when another worker owns the claim', async () => {
    const deps = makeDeps(null)

    await expect(
      processMediaAsset(deps, { assetId: 'asset-1', userId: 'user-1', requestId: 'request-1' }),
    ).resolves.toEqual({ status: 'skipped' })
    expect(deps.storage.download).not.toHaveBeenCalled()
  })

  it('records transient provider failure and rethrows for Inngest retry', async () => {
    const deps = makeDeps()
    vi.mocked(deps.providers.analyzeImage).mockRejectedValue(new Error('provider unavailable'))

    await expect(
      processMediaAsset(deps, { assetId: 'asset-1', userId: 'user-1', requestId: 'request-1' }),
    ).rejects.toThrow('provider unavailable')
    expect(deps.repository.markFailed).toHaveBeenCalledWith(
      'asset-1',
      'user-1',
      'request-1',
      'provider_error',
    )
  })

  describe('audio duration, before any paid transcription', () => {
    const audio = record({
      kind: 'audio_note',
      bucket_id: 'audio-notes',
      object_path: 'user-1/asset-1.wav',
      mime_type: 'audio/wav',
      context_text: null,
    })
    const input = { assetId: 'asset-1', userId: 'user-1', requestId: 'request-1' }

    it('reads the length of a real file from its container', async () => {
      await expect(
        measureAudioDurationFromContainer({ bytes: wav(2), mimeType: 'audio/wav' }),
      ).resolves.toBeCloseTo(2, 3)
      await expect(
        measureAudioDurationFromContainer({ bytes: mp3, mimeType: 'audio/mpeg' }),
      ).resolves.toBeNull()
    })

    it('transcribes a recording at the limit', async () => {
      const deps = makeDeps(audio)
      deps.measureAudioDuration = undefined
      vi.mocked(deps.storage.download).mockResolvedValue(wav(MAX_AUDIO_DURATION_SECONDS))

      await expect(processMediaAsset(deps, input)).resolves.toEqual({ status: 'processed' })
      expect(deps.providers.transcribeAudio).toHaveBeenCalledTimes(1)
    })

    it('refuses a longer recording without calling the transcription', async () => {
      const deps = makeDeps(audio)
      deps.measureAudioDuration = undefined
      vi.mocked(deps.storage.download).mockResolvedValue(wav(MAX_AUDIO_DURATION_SECONDS + 1))

      await expect(processMediaAsset(deps, input)).resolves.toEqual({
        status: 'failed',
        reason: 'audio_too_long',
      })
      expect(deps.providers.transcribeAudio).not.toHaveBeenCalled()
      expect(deps.repository.markFailed).toHaveBeenCalledWith(
        'asset-1',
        'user-1',
        'request-1',
        'audio_too_long',
      )
      expect(deps.repository.markProcessed).not.toHaveBeenCalled()
    })

    it('refuses a file whose length cannot be read instead of sending it blind', async () => {
      const deps = makeDeps(audio)
      deps.measureAudioDuration = undefined
      // Valid WAV signature, truncated before the format chunk.
      vi.mocked(deps.storage.download).mockResolvedValue(wav(1).slice(0, 12))

      await expect(processMediaAsset(deps, input)).resolves.toEqual({
        status: 'failed',
        reason: 'audio_duration_unreadable',
      })
      expect(deps.providers.transcribeAudio).not.toHaveBeenCalled()
    })

    it('does not measure images', async () => {
      const deps = makeDeps()
      await processMediaAsset(deps, input)
      expect(deps.measureAudioDuration).not.toHaveBeenCalled()
    })
  })
})
