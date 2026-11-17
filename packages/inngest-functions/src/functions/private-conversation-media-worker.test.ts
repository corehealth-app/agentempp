/** Actual registered callback/default factory/private processor/installed SDK.
 * Only network/model/config/client-construction boundaries are synthetic. */

import type { ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'

const boundary = vi.hoisted(() => ({
  client: vi.fn(),
  config: vi.fn(),
  vision: vi.fn(),
  stt: vi.fn(),
  analyze: vi.fn(),
  transcribe: vi.fn(),
}))
vi.mock('../lib/env.js', () => ({ createWorkerSupabase: boundary.client }))
vi.mock('../lib/runtime-config.js', () => ({ loadVisionConfig: boundary.config }))
vi.mock('@mpp/providers', async (original) => ({
  ...(await original<typeof import('@mpp/providers')>()),
  GeminiVision: boundary.vision,
  GroqSTT: boundary.stt,
}))
const { privateConversationMediaProcessingFn } = await import(
  './private-conversation-media-worker.js'
)
const owner = 'c1731000-0000-4000-8000-000000000001',
  asset = 'c1731000-0000-4000-8000-000000000002',
  token = 'c1731000-0000-4000-8000-000000000003'
const at = '2026-11-17T21:00:00.000Z',
  until = '2026-12-17T21:00:00.000Z',
  lease = '2026-11-17T21:05:00.000Z',
  origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
const input = {
  schema: 'conversation.media-process.v2',
  catalogVersion: 2,
  userId: owner,
  assetId: asset,
  requestId: 'a'.repeat(64),
}
const imageResult = {
  schema: 'conversation.image-result.v1',
  status: 'ready',
  classification: 'meal',
  analysis: {
    type: 'meal',
    items: [{ name: 'arroz cozido', quantity_g_estimate: 100, confidence: 0.8 }],
  },
}
function wav(seconds: number) {
  const size = 8000 * seconds,
    bytes = new Uint8Array(44 + size).fill(128),
    v = new DataView(bytes.buffer)
  const ascii = (at: number, text: string) => {
    for (let i = 0; i < text.length; i++) v.setUint8(at + i, text.charCodeAt(i))
  }
  ascii(0, 'RIFF')
  v.setUint32(4, 36 + size, true)
  ascii(8, 'WAVE')
  ascii(12, 'fmt ')
  v.setUint32(16, 16, true)
  v.setUint16(20, 1, true)
  v.setUint16(22, 1, true)
  v.setUint32(24, 8000, true)
  v.setUint32(28, 8000, true)
  v.setUint16(32, 1, true)
  v.setUint16(34, 8, true)
  ascii(36, 'data')
  v.setUint32(40, size, true)
  return bytes
}
function setup(
  kind: 'conversation_photo' | 'audio_note' = 'conversation_photo',
  mode: 'normal' | 'busy' | 'bad_signature' | 'long_audio' | 'withdraw' | 'uncertain' = 'normal',
) {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date(at))
  vi.clearAllMocks()
  for (const [key, value] of Object.entries({
    MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED: 'true',
    MOBILE_CONVERSATION_PHOTOS_ENABLED: 'true',
    INNGEST_FUNCTION_SET: 'media-conversation-staging',
    SUPABASE_URL: origin,
    OPENROUTER_API_KEY: 'synthetic-key',
    GROQ_API_KEY: 'synthetic-key',
  }))
    vi.stubEnv(key, value)
  const photo = kind === 'conversation_photo',
    bytes = photo
      ? new Uint8Array(mode === 'bad_signature' ? [0, 0, 0, 0] : [255, 216, 255, 224])
      : wav(mode === 'long_audio' ? 181 : 1)
  const bucket = photo ? 'meal-photos' : 'audio-notes',
    mime = photo ? 'image/jpeg' : 'audio/wav',
    path = `conversation-v2/${owner}/${asset}.${photo ? 'jpg' : 'wav'}`
  const identity = {
    catalog_version: 2,
    user_id: owner,
    asset_id: asset,
    kind,
    bucket_id: bucket,
    object_path: path,
    mime_type: mime,
    declared_size_bytes: bytes.byteLength,
  }
  const row = {
    id: asset,
    user_id: owner,
    kind,
    bucket_id: bucket,
    object_path: path,
    mime_type: mime,
    declared_size_bytes: bytes.byteLength,
    actual_size_bytes: bytes.byteLength,
    etag: 'etag',
    status: 'uploaded',
    failure_stage: null as 'processing' | null,
    failure_code: null as string | null,
    context_text: 'Meu almoço',
    processing_request_id: null as string | null,
    processing_result: null as unknown,
    source_request_hash: 'b'.repeat(64),
    retention_until: until,
    uploaded_at: at,
    processed_at: null as string | null,
    deleted_at: null,
    created_at: at,
    updated_at: at,
  }
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  let downloads = 0
  const client = createClient(origin, 'synthetic-worker-only', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: async (raw, init) => {
        const req = new Request(raw, init),
          url = new URL(req.url)
        expect(url.origin).toBe(origin)
        if (url.pathname.startsWith('/rest/v1/rpc/')) {
          const name = url.pathname.split('/').at(-1) ?? '',
            args = await req.json()
          calls.push({ name, args })
          expect(args.p_user_id).toBe(owner)
          expect(args.p_asset_id).toBe(asset)
          if (name === 'claim_conversation_media_processing_v2') {
            if (row.status === 'processed')
              return Response.json({
                schema: 'conversation.media-processing-claim.v2',
                action: 'unavailable',
              })
            if (mode === 'busy')
              return Response.json({
                schema: 'conversation.media-processing-claim.v2',
                action: 'busy',
                retry_at: lease,
              })
            Object.assign(row, { status: 'processing', processing_request_id: input.requestId })
            return Response.json({
              schema: 'conversation.media-processing-claim.v2',
              action: 'claimed',
              asset: {
                identity,
                state: { status: 'processing', created_at: at, retention_until: until },
                context_text: row.context_text,
                processing_request_id: input.requestId,
              },
              claim: { token, lease_until: lease },
            })
          }
          if (name === 'get_conversation_media_asset_v2')
            return Response.json({
              schema: 'conversation.media-asset.v2',
              catalog_version: 2,
              asset: row,
            })
          if (name === 'complete_conversation_media_processing_v2') {
            expect(args.p_request_id).toBe(input.requestId)
            expect(args.p_claim_token).toBe(token)
            Object.assign(row, {
              status: 'processed',
              processing_result: args.p_result,
              processed_at: at,
            })
            if (mode === 'uncertain') throw Error('uncertain committed response')
            return Response.json(true)
          }
          if (name === 'fail_conversation_media_processing_v2') {
            Object.assign(row, {
              status: 'failed',
              failure_stage: 'processing',
              failure_code: args.p_failure_code,
            })
            return Response.json(true)
          }
        }
        if (req.method === 'GET' && url.pathname === `/storage/v1/object/${bucket}/${path}`) {
          downloads++
          if (mode === 'withdraw')
            vi.stubEnv('MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED', 'false')
          return new Response(bytes, { headers: { 'content-type': mime } })
        }
        return Response.json(
          { code: '42501', message: 'Unexpected private worker IO' },
          { status: 400 },
        )
      },
    },
  }) as unknown as ServiceClient
  boundary.client.mockReturnValue(client)
  boundary.config.mockResolvedValue({
    model: 'synthetic',
    nutrition_label_model: 'synthetic',
    prompts: {},
  })
  boundary.vision.mockImplementation(() => ({
    analyzeConversationImage: boundary.analyze,
    analyzeImage: () => {
      throw Error('Legacy clinical analyzer forbidden')
    },
  }))
  boundary.analyze.mockResolvedValue(imageResult)
  boundary.stt.mockImplementation(() => ({ transcribe: boundary.transcribe }))
  boundary.transcribe.mockResolvedValue({
    text: 'Tomei leite com whey',
    language: 'pt',
    duration: 1,
    latencyMs: 2,
    providerDiagnostic: 'must not persist',
  })
  const run = (data: unknown = input) =>
    (
      privateConversationMediaProcessingFn as unknown as { fn: (ctx: unknown) => Promise<unknown> }
    ).fn({
      event: { data },
      step: {
        run: () => {
          throw Error('Do not memoize a busy claim as completed')
        },
      },
      logger: {
        info: () => {
          throw Error('No raw event/model logging')
        },
      },
    })
  return { row, calls, run, downloads: () => downloads }
}
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllEnvs()
})
describe('registered private media worker', () => {
  it('processes the proved private photo through the neutral analyzer and stores only its observations', async () => {
    const x = setup()
    expect(await x.run()).toEqual({ status: 'processed' })
    expect(x.row.processing_result).toEqual(imageResult)
    expect(boundary.analyze).toHaveBeenCalledWith('data:image/jpeg;base64,/9j/4A==', {
      userMessage: 'Meu almoço',
      purposeEnabled: expect.any(Function),
    })
    expect(x.calls.map((c) => c.name)).toEqual([
      'claim_conversation_media_processing_v2',
      'get_conversation_media_asset_v2',
      'complete_conversation_media_processing_v2',
    ])
  })
  it('uses measured audio duration and strips provider diagnostics before storage', async () => {
    const x = setup('audio_note')
    expect(await x.run()).toEqual({ status: 'processed' })
    expect(x.row.processing_result).toEqual({
      text: 'Tomei leite com whey',
      language: 'pt',
      duration: 1,
      latencyMs: 2,
    })
    expect(boundary.vision).not.toHaveBeenCalled()
  })
  it('returns the completed source on technical replay without another provider call', async () => {
    const x = setup()
    await x.run()
    expect(await x.run()).toEqual({ status: 'skipped' })
    expect(boundary.analyze).toHaveBeenCalledTimes(1)
    expect(x.downloads()).toBe(1)
  })
  it('defers a busy SQL lease without download/provider or a completed memoized step', async () => {
    const x = setup('conversation_photo', 'busy')
    await expect(x.run()).rejects.toMatchObject({
      name: 'RetryAfterError',
      retryAfter: '2026-11-17T21:05:01.000Z',
    })
    expect(x.downloads()).toBe(0)
    expect(boundary.vision).not.toHaveBeenCalled()
  })
  it('rejects unknown event versions before constructing privileged clients', async () => {
    const x = setup()
    await expect(x.run({ ...input, catalogVersion: 1 })).rejects.toMatchObject({
      name: 'NonRetriableError',
    })
    expect(boundary.client).not.toHaveBeenCalled()
    expect(x.calls).toEqual([])
  })
  it('does not acknowledge a temporarily disabled private policy as completed work', async () => {
    const x = setup()
    vi.stubEnv('MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED', 'false')
    await expect(x.run()).rejects.toMatchObject({ name: 'RetryAfterError' })
    expect(boundary.client).not.toHaveBeenCalled()
  })
  it('refuses an inconsistent staging target without client or provider work', async () => {
    const x = setup()
    vi.stubEnv('SUPABASE_URL', 'https://other-project.supabase.co')
    await expect(x.run()).rejects.toThrow('Private media processing unavailable')
    expect(boundary.client).not.toHaveBeenCalled()
  })
  it('fails bad image bytes before any paid model request', async () => {
    const x = setup('conversation_photo', 'bad_signature')
    expect(await x.run()).toEqual({ status: 'failed', reason: 'invalid_file_signature' })
    expect(boundary.vision).not.toHaveBeenCalled()
  })
  it('fails overlong audio before constructing transcription provider', async () => {
    const x = setup('audio_note', 'long_audio')
    expect(await x.run()).toEqual({ status: 'failed', reason: 'audio_too_long' })
    expect(boundary.stt).not.toHaveBeenCalled()
  })
  it('rechecks the live private gate after the Storage wait and before any provider', async () => {
    const x = setup('conversation_photo', 'withdraw')
    await expect(x.run()).rejects.toThrow('Private media processing unavailable')
    expect(boundary.vision).not.toHaveBeenCalled()
  })
  it('recovers an uncertain completed SQL response without another model call or failure overwrite', async () => {
    const x = setup('conversation_photo', 'uncertain')
    await expect(x.run()).rejects.toThrow('Private media processing unavailable')
    expect(x.row.status).toBe('processed')
    expect(await x.run()).toEqual({ status: 'skipped' })
    expect(boundary.analyze).toHaveBeenCalledTimes(1)
    expect(x.calls.some((c) => c.name === 'fail_conversation_media_processing_v2')).toBe(false)
  })
})
