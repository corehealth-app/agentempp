import { expect, it, vi } from 'vitest'
import { GroqSTT } from './stt/groq.js'
import { GeminiVision } from './vision/gemini.js'

it.each([
  [
    'vision',
    (fetch: typeof globalThis.fetch) => new GeminiVision({ apiKey: 'synthetic-only', fetch }),
  ],
  ['audio', (fetch: typeof globalThis.fetch) => new GroqSTT({ apiKey: 'synthetic-only', fetch })],
] as const)('binds %s to the caller transport for timeout, origin and lease fencing', (_kind, construct) => {
  const network = vi.fn<typeof globalThis.fetch>()
  const provider = construct(network)
  // The installed OpenAI SDK uses its own Node shim by default. This explicit
  // hook must reach the actual SDK so a worker signal cannot be bypassed.
  expect((provider as unknown as { client: { fetch: typeof globalThis.fetch } }).client.fetch).toBe(
    network,
  )
  expect(network).not.toHaveBeenCalled()
})
