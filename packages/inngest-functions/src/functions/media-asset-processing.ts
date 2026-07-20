import type { Json, ServiceClient } from '@mpp/db'
import { GeminiVision, GroqSTT } from '@mpp/providers'
import { z } from 'zod'
import { inngest } from '../client.js'
import { createWorkerSupabase } from '../lib/env.js'
import { loadVisionConfig } from '../lib/runtime-config.js'

export type ProcessableMediaKind = 'meal_photo' | 'body_checkin_photo' | 'gym_photo' | 'audio_note'

export interface ProcessableMediaAsset {
  id: string
  user_id: string
  kind: ProcessableMediaKind
  bucket_id: string
  object_path: string
  mime_type: string
  context_text: string | null
  status: 'processing'
  processing_request_id: string
}

export interface MediaProcessingInput {
  assetId: string
  userId: string
  requestId: string
}

export interface MediaProcessingDependencies {
  repository: {
    claim(input: MediaProcessingInput): Promise<ProcessableMediaAsset | null>
    markProcessed(
      assetId: string,
      userId: string,
      requestId: string,
      result: unknown,
    ): Promise<void>
    markFailed(assetId: string, userId: string, requestId: string, reason: string): Promise<void>
  }
  storage: {
    download(bucketId: string, objectPath: string): Promise<Uint8Array>
  }
  providers: {
    analyzeImage(input: {
      bytes: Uint8Array
      mimeType: string
      contextText: string | null
      kind: Exclude<ProcessableMediaKind, 'audio_note'>
    }): Promise<unknown>
    transcribeAudio(input: { bytes: Uint8Array; mimeType: string }): Promise<unknown>
  }
}

const claimedMediaSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  kind: z.enum(['meal_photo', 'body_checkin_photo', 'gym_photo', 'audio_note']),
  bucket_id: z.string().min(1),
  object_path: z.string().min(1),
  mime_type: z.string().min(1),
  context_text: z.string().nullable(),
  status: z.literal('processing'),
  processing_request_id: z.string().regex(/^[0-9a-f]{64}$/),
})

function ascii(bytes: Uint8Array, start: number, length: number): string {
  return String.fromCharCode(...bytes.slice(start, start + length))
}

function hasPrefix(bytes: Uint8Array, prefix: number[]): boolean {
  return prefix.every((value, index) => bytes[index] === value)
}

function isIsoBaseMedia(bytes: Uint8Array): boolean {
  return bytes.length >= 12 && ascii(bytes, 4, 4) === 'ftyp'
}

export function mediaSignatureMatches(bytes: Uint8Array, mimeType: string): boolean {
  if (mimeType === 'image/jpeg') return hasPrefix(bytes, [0xff, 0xd8, 0xff])
  if (mimeType === 'image/png') {
    return hasPrefix(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
  }
  if (mimeType === 'image/webp') {
    return bytes.length >= 12 && ascii(bytes, 0, 4) === 'RIFF' && ascii(bytes, 8, 4) === 'WEBP'
  }
  if (mimeType === 'image/heic' || mimeType === 'image/heif') {
    if (!isIsoBaseMedia(bytes)) return false
    return ['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(ascii(bytes, 8, 4))
  }
  if (mimeType === 'audio/mpeg') {
    return (
      ascii(bytes, 0, 3) === 'ID3' ||
      (bytes.length >= 2 && bytes[0] === 0xff && ((bytes[1] ?? 0) & 0xe0) === 0xe0)
    )
  }
  if (mimeType === 'audio/mp4' || mimeType === 'audio/x-m4a') return isIsoBaseMedia(bytes)
  if (mimeType === 'audio/aac') {
    return bytes.length >= 2 && bytes[0] === 0xff && ((bytes[1] ?? 0) & 0xf6) === 0xf0
  }
  if (mimeType === 'audio/wav' || mimeType === 'audio/x-wav') {
    return bytes.length >= 12 && ascii(bytes, 0, 4) === 'RIFF' && ascii(bytes, 8, 4) === 'WAVE'
  }
  if (mimeType === 'audio/ogg') return ascii(bytes, 0, 4) === 'OggS'
  return false
}

export async function processMediaAsset(
  deps: MediaProcessingDependencies,
  input: MediaProcessingInput,
): Promise<
  | { status: 'processed' }
  | { status: 'failed'; reason: 'invalid_file_signature' }
  | { status: 'skipped' }
> {
  const asset = await deps.repository.claim(input)
  if (!asset) return { status: 'skipped' }

  let bytes: Uint8Array
  try {
    bytes = await deps.storage.download(asset.bucket_id, asset.object_path)
  } catch (error) {
    await deps.repository.markFailed(
      asset.id,
      asset.user_id,
      input.requestId,
      'storage_download_error',
    )
    throw error
  }

  if (!mediaSignatureMatches(bytes, asset.mime_type)) {
    await deps.repository.markFailed(
      asset.id,
      asset.user_id,
      input.requestId,
      'invalid_file_signature',
    )
    return { status: 'failed', reason: 'invalid_file_signature' }
  }

  try {
    const result =
      asset.kind === 'audio_note'
        ? await deps.providers.transcribeAudio({ bytes, mimeType: asset.mime_type })
        : await deps.providers.analyzeImage({
            bytes,
            mimeType: asset.mime_type,
            contextText: asset.context_text,
            kind: asset.kind,
          })
    await deps.repository.markProcessed(asset.id, asset.user_id, input.requestId, result)
    return { status: 'processed' }
  } catch (error) {
    await deps.repository.markFailed(asset.id, asset.user_id, input.requestId, 'provider_error')
    throw error
  }
}

function safeProviderJson(value: unknown): Json {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  if (Array.isArray(value)) return value.slice(0, 100).map(safeProviderJson)
  if (typeof value !== 'object') return null

  const result: { [key: string]: Json | undefined } = {}
  for (const [key, entry] of Object.entries(value)) {
    if (key === 'raw_response' || entry === undefined) continue
    result[key] = safeProviderJson(entry)
  }
  return result
}

function createProcessingRepository(
  supabase: ServiceClient,
): MediaProcessingDependencies['repository'] {
  return {
    async claim(input) {
      const { data, error } = await supabase.rpc('claim_media_asset_processing', {
        p_asset_id: input.assetId,
        p_user_id: input.userId,
        p_request_id: input.requestId,
      })
      if (error) throw new Error(error.message || 'media processing claim failed')
      if (data === null) return null
      const parsed = claimedMediaSchema.safeParse(data)
      if (!parsed.success) throw new Error('invalid media processing claim')
      return parsed.data
    },
    async markProcessed(assetId, userId, requestId, result) {
      const { data, error } = await supabase.rpc('complete_media_asset_processing', {
        p_asset_id: assetId,
        p_user_id: userId,
        p_request_id: requestId,
        p_result: safeProviderJson(result),
      })
      if (error || data !== true) throw new Error(error?.message || 'media completion lost claim')
    },
    async markFailed(assetId, userId, requestId, reason) {
      const { error } = await supabase.rpc('fail_media_asset_processing', {
        p_asset_id: assetId,
        p_user_id: userId,
        p_request_id: requestId,
        p_failure_code: reason,
      })
      if (error) throw new Error(error.message || 'media failure state update failed')
    },
  }
}

function imageHint(
  kind: Exclude<ProcessableMediaKind, 'audio_note'>,
): 'meal' | 'body' | 'equipment' {
  if (kind === 'body_checkin_photo') return 'body'
  if (kind === 'gym_photo') return 'equipment'
  return 'meal'
}

function audioFilename(mimeType: string): string {
  const extension: Record<string, string> = {
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'audio/x-m4a': 'm4a',
    'audio/aac': 'aac',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/ogg': 'ogg',
  }
  return `bodyflow-audio.${extension[mimeType] ?? 'bin'}`
}

async function createDefaultMediaProcessingDependencies(): Promise<MediaProcessingDependencies> {
  const supabase = createWorkerSupabase()
  return {
    repository: createProcessingRepository(supabase),
    storage: {
      async download(bucketId, objectPath) {
        const { data, error } = await supabase.storage.from(bucketId).download(objectPath)
        if (error || !data) throw new Error(error?.message || 'private media download failed')
        return new Uint8Array(await data.arrayBuffer())
      },
    },
    providers: {
      async analyzeImage(input) {
        const apiKey = process.env.OPENROUTER_API_KEY
        if (!apiKey) throw new Error('OPENROUTER_API_KEY ausente')
        const config = await loadVisionConfig(supabase)
        const vision = new GeminiVision({
          apiKey,
          heliconeApiKey: process.env.HELICONE_API_KEY,
          model: config.model,
          nutritionLabelModel: config.nutrition_label_model,
          prompts: config.prompts,
        })
        const dataUri = `data:${input.mimeType};base64,${Buffer.from(input.bytes).toString('base64')}`
        return safeProviderJson(
          await vision.analyzeImage(dataUri, {
            hint: imageHint(input.kind),
            userMessage: input.contextText ?? undefined,
          }),
        )
      },
      async transcribeAudio(input) {
        const apiKey = process.env.GROQ_API_KEY
        if (!apiKey) throw new Error('GROQ_API_KEY ausente')
        const stt = new GroqSTT({ apiKey })
        return safeProviderJson(
          await stt.transcribe({
            audio: input.bytes,
            filename: audioFilename(input.mimeType),
            mimeType: input.mimeType,
            language: 'pt',
          }),
        )
      },
    },
  }
}

export const mediaAssetProcessingFn = inngest.createFunction(
  {
    id: 'media-asset-processing',
    retries: 3,
    concurrency: { key: 'event.data.assetId', limit: 1 },
  },
  { event: 'media.asset.process.requested' },
  async ({ event, step }) => {
    return await step.run('process-private-media', async () => {
      const deps = await createDefaultMediaProcessingDependencies()
      return processMediaAsset(deps, event.data)
    })
  },
)
