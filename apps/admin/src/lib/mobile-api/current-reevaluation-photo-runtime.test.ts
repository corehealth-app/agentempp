import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createCurrentReevaluationPhotoRuntimeRoutes } from './current-reevaluation-photo-runtime'
import type { createSupabaseReevaluationPhotoLifecycleOperations } from './reevaluation-photo-lifecycle'
import type { createReevaluationPhotoLifecycleRoutes } from './reevaluation-photo-lifecycle-http'

const spies = vi.hoisted(() => ({
  http: vi.fn(),
  operations: vi.fn(),
  load: vi.fn(),
  vision: vi.fn(),
  analyze: vi.fn(),
}))
vi.mock('./reevaluation-photo-lifecycle-http', () => ({
  createReevaluationPhotoLifecycleRoutes: spies.http,
}))
vi.mock('./reevaluation-photo-lifecycle', () => ({
  createSupabaseReevaluationPhotoLifecycleOperations: spies.operations,
}))
vi.mock('./current-vision-runtime-config', () => ({
  createCurrentVisionConfigLoader: () => spies.load,
}))
vi.mock('@mpp/providers/vision', () => ({ GeminiVision: spies.vision }))
beforeEach(() => {
  vi.clearAllMocks()
  spies.vision.mockImplementation(() => ({ analyzeImage: spies.analyze }))
  spies.analyze.mockResolvedValue({ type: 'body', view: 'front', bf_percent_estimate: 20 })
  spies.load.mockResolvedValue({
    model: 'configured/model',
    nutrition_label_model: 'configured/label',
    meal_confidence_threshold: 0.6,
    prompts: { body: 'configured prompt' },
  })
  vi.stubEnv('OPENROUTER_API_KEY', 'synthetic')
  vi.stubEnv('HELICONE_API_KEY', '')
})
afterEach(() => vi.unstubAllEnvs())
function operations() {
  createCurrentReevaluationPhotoRuntimeRoutes({
    mode: 'current',
    storageOrigin: 'https://xitugspwfxkcluxvrdeg.supabase.co',
  })
  const dependencies = spies.http.mock.calls[0][0] as Parameters<
    typeof createReevaluationPhotoLifecycleRoutes
  >[0]
  const client = {} as ServiceClient
  dependencies.createOperations(client)
  const options = spies.operations.mock.calls[0][1] as Parameters<
    typeof createSupabaseReevaluationPhotoLifecycleOperations
  >[1]
  return { client, options }
}
describe('recurring photo runtime provider composition (HTTP/SQL ports controlled)', () => {
  it('constructs operations without loading configuration or initializing a provider', () => {
    const { options } = operations()
    expect(options.storageOrigin).toBe('https://xitugspwfxkcluxvrdeg.supabase.co')
    expect(spies.load).not.toHaveBeenCalled()
    expect(spies.vision).not.toHaveBeenCalled()
    expect(spies.analyze).not.toHaveBeenCalled()
  })
  it('uses configured model/prompts and preserves body-only bounded provider call when authorized analyzer is reached', async () => {
    const { client, options } = operations(),
      signal = new AbortController().signal
    const bytes = new Uint8Array([1, 2, 3])
    expect(await options.analyze(bytes, 'image/jpeg', { signal, timeoutMs: 1200 })).toMatchObject({
      type: 'body',
      view: 'front',
    })
    expect(spies.load).toHaveBeenCalledWith(client, 'https://xitugspwfxkcluxvrdeg.supabase.co')
    expect(spies.vision).toHaveBeenCalledWith({
      apiKey: 'synthetic',
      heliconeApiKey: '',
      model: 'configured/model',
      nutritionLabelModel: 'configured/label',
      prompts: { body: 'configured prompt' },
    })
    expect(spies.analyze).toHaveBeenCalledWith(
      'data:image/jpeg;base64,AQID',
      { hint: 'body' },
      { signal, timeout: 1200, maxRetries: 0 },
    )
    expect(spies.analyze).toHaveBeenCalledTimes(1)
  })
  it('refuses a missing provider key without querying config or substituting defaults', async () => {
    vi.stubEnv('OPENROUTER_API_KEY', '')
    const { options } = operations()
    await expect(
      options.analyze(new Uint8Array([1]), 'image/jpeg', {
        signal: new AbortController().signal,
        timeoutMs: 1200,
      }),
    ).rejects.toThrow('Photo provider unavailable')
    expect(spies.load).not.toHaveBeenCalled()
    expect(spies.vision).not.toHaveBeenCalled()
  })
})
