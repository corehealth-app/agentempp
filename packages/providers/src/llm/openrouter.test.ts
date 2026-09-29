import { describe, expect, it, vi } from 'vitest'
import { OpenRouterLLM } from './openrouter'

// A long generation (a whole training plan) needs its own time limit and no
// silent retry: the client default (90 s, 1 retry) aborts it and pays twice.
describe('OpenRouterLLM per-call limits', () => {
  function stubbed() {
    const llm = new OpenRouterLLM({ apiKey: 'test-key' })
    const create = vi.fn(async (_body: unknown, _options?: unknown) => ({
      model: 'm',
      choices: [{ message: { content: '{}' }, finish_reason: 'stop' }],
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
    }))
    ;(llm as unknown as { client: { chat: { completions: { create: unknown } } } }).client.chat.completions.create =
      create
    return { llm, create }
  }

  it('passes a per-call timeout and retry count to the request', async () => {
    const { llm, create } = stubbed()
    await llm.complete({ model: 'm', systemPrompt: 's', messages: [], requestTimeoutMs: 120_000, maxRetries: 0 })
    expect(create.mock.calls[0]?.[1]).toEqual({ timeout: 120_000, maxRetries: 0 })
  })

  it('a call without limits keeps the client defaults (no request options)', async () => {
    const { llm, create } = stubbed()
    await llm.complete({ model: 'm', systemPrompt: 's', messages: [] })
    expect(create.mock.calls[0]?.[1]).toBeUndefined()
  })
})
