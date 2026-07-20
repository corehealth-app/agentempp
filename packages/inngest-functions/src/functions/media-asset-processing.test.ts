import { describe, expect, it, vi } from 'vitest'
import {
  type MediaProcessingDependencies,
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
  }
}

describe('media asset processing', () => {
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
})
