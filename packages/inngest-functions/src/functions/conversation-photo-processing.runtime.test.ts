/** Actual registered worker -> default factory -> real processing pipeline.
 * SDK/Storage/model are synthetic boundaries; no network or provider spend. */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const ports = vi.hoisted(() => ({
  client: vi.fn(),
  config: vi.fn(),
  rpc: vi.fn(),
  download: vi.fn(),
  neutral: vi.fn(),
  legacy: vi.fn(),
  makeVision: vi.fn(),
}))
vi.mock('../lib/env.js', () => ({ createWorkerSupabase: ports.client }))
vi.mock('../lib/runtime-config.js', () => ({ loadVisionConfig: ports.config }))
vi.mock('@mpp/providers', async (original) => ({
  ...(await original<typeof import('@mpp/providers')>()),
  GeminiVision: ports.makeVision,
}))
const { mediaAssetProcessingFn } = await import('./media-asset-processing.js')
const who = {
  assetId: '11110000-0000-4000-8000-000000000001',
  userId: '11110000-0000-4000-8000-000000000002',
  requestId: 'a'.repeat(64),
}
const result = {
  schema: 'conversation.image-result.v1',
  status: 'unsupported',
  classification: 'body',
  reason: 'image_not_supported_for_conversation',
}
const run = () =>
  (mediaAssetProcessingFn as unknown as { fn: (ctx: unknown) => Promise<unknown> }).fn({
    event: { data: who },
    step: { run: (_id: string, f: () => unknown) => f() },
  })
describe('default nonclinical photo worker wiring', () => {
  let kind = 'conversation_photo'
  beforeEach(() => {
    vi.clearAllMocks()
    kind = 'conversation_photo'
    vi.stubEnv('OPENROUTER_API_KEY', 'synthetic-test-key')
    vi.stubEnv('MOBILE_CONVERSATION_PHOTOS_ENABLED', 'true')
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-clinical-staging')
    vi.stubEnv('SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    ports.config.mockResolvedValue({
      model: 'synthetic',
      nutrition_label_model: 'synthetic',
      prompts: {},
    })
    ports.neutral.mockResolvedValue(result)
    ports.legacy.mockResolvedValue({ type: 'meal', items: [] })
    ports.makeVision.mockImplementation(() => ({
      analyzeConversationImage: ports.neutral,
      analyzeImage: ports.legacy,
    }))
    ports.rpc.mockImplementation(async (name: string) => ({
      error: null,
      data:
        name === 'claim_media_asset_processing'
          ? {
              id: who.assetId,
              user_id: who.userId,
              kind,
              bucket_id: 'meal-photos',
              object_path: `${who.userId}/${who.assetId}.jpg`,
              mime_type: 'image/jpeg',
              context_text: 'o que aparece?',
              status: 'processing',
              processing_request_id: who.requestId,
            }
          : true,
    }))
    ports.download.mockResolvedValue({
      data: { arrayBuffer: async () => new Uint8Array([255, 216, 255, 224]).buffer },
      error: null,
    })
    ports.client.mockReturnValue({
      rpc: ports.rpc,
      storage: { from: () => ({ download: ports.download }) },
    })
  })
  afterEach(() => vi.unstubAllEnvs())
  it.each([
    'media-clinical-staging',
    'media-conversation-staging',
  ])('uses the explicit neutral analyzer, not the generic/body fallback (%s)', async (set) => {
    vi.stubEnv('INNGEST_FUNCTION_SET', set)
    expect(await run()).toEqual({ status: 'processed' })
    expect(ports.neutral).toHaveBeenCalledWith('data:image/jpeg;base64,/9j/4A==', {
      userMessage: 'o que aparece?',
      purposeEnabled: expect.any(Function),
    })
    expect(ports.legacy).not.toHaveBeenCalled()
    expect(ports.rpc).toHaveBeenCalledWith('complete_media_asset_processing', {
      p_asset_id: who.assetId,
      p_user_id: who.userId,
      p_request_id: who.requestId,
      p_result: result,
    })
  })
  it('has no storage/model capability after opt-in is removed', async () => {
    vi.stubEnv('MOBILE_CONVERSATION_PHOTOS_ENABLED', 'false')
    expect(await run()).toEqual({ status: 'failed', reason: 'conversation_photo_unavailable' })
    expect(ports.download).not.toHaveBeenCalled()
    expect(ports.makeVision).not.toHaveBeenCalled()
    expect(ports.config).not.toHaveBeenCalled()
  })
  it('does not construct or send to a model after revocation while configuration is loading', async () => {
    ports.config.mockImplementation(async () => {
      vi.stubEnv('MOBILE_CONVERSATION_PHOTOS_ENABLED', 'false')
      return { model: 'synthetic', nutrition_label_model: 'synthetic', prompts: {} }
    })
    await expect(run()).rejects.toThrow('Conversation image purpose unavailable')
    expect(ports.makeVision).not.toHaveBeenCalled()
    expect(ports.neutral).not.toHaveBeenCalled()
    expect(ports.legacy).not.toHaveBeenCalled()
    expect(
      ports.rpc.mock.calls.filter((x) => x[0] === 'complete_media_asset_processing'),
    ).toHaveLength(0)
  })
  it('preserves the generic analyzer and explicit hint for existing meal photographs', async () => {
    kind = 'meal_photo'
    expect(await run()).toEqual({ status: 'processed' })
    expect(ports.legacy).toHaveBeenCalledWith(expect.any(String), {
      hint: 'meal',
      userMessage: 'o que aparece?',
    })
    expect(ports.neutral).not.toHaveBeenCalled()
  })
})
