import { describe, expect, it, vi } from 'vitest'
import { GeminiVision } from './gemini.js'

function setup() {
  const vision = new GeminiVision({ apiKey: 'synthetic-local-not-a-key' })
  const create = vi.fn().mockResolvedValue({
    choices: [
      { message: { content: '{"view":"front","bf_percent_estimate":22,"bf_confidence":0.7}' } },
    ],
  })
  ;(vision as unknown as { client: { chat: { completions: { create: typeof create } } } }).client =
    { chat: { completions: { create } } }
  return { vision, create }
}
describe('bounded recurring body request transport', () => {
  it('forwards cancellation/timeout and disables SDK retry for the dedicated body call', async () => {
    const f = setup()
    const signal = new AbortController().signal
    await f.vision.analyzeImage(
      'data:image/jpeg;base64,synthetic',
      { hint: 'body' },
      { signal, timeout: 1200, maxRetries: 0 },
    )
    expect(f.create.mock.calls[0]?.[1]).toEqual({ signal, timeout: 1200, maxRetries: 0 })
    expect(f.create).toHaveBeenCalledTimes(1)
  })
  it('rejects bounded options for another hint before a provider request', async () => {
    const f = setup()
    await expect(
      f.vision.analyzeImage(
        'data:image/jpeg;base64,synthetic',
        { hint: 'meal' },
        { maxRetries: 0 },
      ),
    ).rejects.toThrow('Body request options require an explicit body hint')
    expect(f.create).not.toHaveBeenCalled()
  })
  it('keeps legacy body request defaults when no transport override is supplied', async () => {
    const f = setup()
    expect(
      (await f.vision.analyzeImage('data:image/jpeg;base64,synthetic', { hint: 'body' })).type,
    ).toBe('body')
    expect(f.create).toHaveBeenCalledTimes(1)
    expect(f.create.mock.calls[0]?.[1]).toBeUndefined()
  })
})
