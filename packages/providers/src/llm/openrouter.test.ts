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
    ;(
      llm as unknown as { client: { chat: { completions: { create: unknown } } } }
    ).client.chat.completions.create = create
    return { llm, create }
  }

  it('passes a per-call timeout and retry count to the request', async () => {
    const { llm, create } = stubbed()
    await llm.complete({
      model: 'm',
      systemPrompt: 's',
      messages: [],
      requestTimeoutMs: 120_000,
      maxRetries: 0,
    })
    expect(create.mock.calls[0]?.[1]).toEqual({ timeout: 120_000, maxRetries: 0 })
  })

  it('forwards strict JSON schema and required parameter support only when requested', async () => {
    const { llm, create } = stubbed()
    const responseFormat = {
      type: 'json_schema' as const,
      json_schema: {
        name: 'closed_result',
        strict: true,
        schema: {
          type: 'object',
          properties: { value: { type: 'string' } },
          required: ['value'],
          additionalProperties: false,
        },
      },
    }
    await llm.complete({
      model: 'm',
      systemPrompt: 's',
      messages: [],
      responseFormat,
      provider: { require_parameters: true },
      requestTimeoutMs: 45_000,
      maxRetries: 0,
    })
    expect(create.mock.calls).toEqual([
      [
        {
          model: 'm',
          messages: [{ role: 'system', content: 's' }],
          temperature: 0.4,
          max_tokens: 8192,
          response_format: responseFormat,
          provider: { require_parameters: true },
        },
        { timeout: 45_000, maxRetries: 0 },
      ],
    ])
  })
  it('keeps the legacy JSON-object request body unchanged', async () => {
    const { llm, create } = stubbed()
    await llm.complete({
      model: 'm',
      systemPrompt: 's',
      messages: [],
      responseFormat: { type: 'json_object' },
    })
    expect(create.mock.calls).toEqual([
      [
        {
          model: 'm',
          messages: [{ role: 'system', content: 's' }],
          temperature: 0.4,
          max_tokens: 8192,
          response_format: { type: 'json_object' },
        },
        undefined,
      ],
    ])
  })
  it('does not retry or fall back when the strict-schema request is refused', async () => {
    const { llm, create } = stubbed(),
      error = Object.assign(new Error('invalid schema'), { status: 400 })
    create.mockRejectedValueOnce(error)
    await expect(
      llm.complete({
        model: 'm',
        systemPrompt: 's',
        messages: [],
        responseFormat: {
          type: 'json_schema',
          json_schema: {
            name: 'closed',
            strict: true,
            schema: { type: 'object', properties: {}, additionalProperties: false },
          },
        },
        provider: { require_parameters: true },
        maxRetries: 0,
      }),
    ).rejects.toBe(error)
    expect(create).toHaveBeenCalledTimes(1)
    expect(create.mock.calls[0]?.[0]).toHaveProperty('provider', { require_parameters: true })
    expect(create.mock.calls[0]?.[1]).toEqual({ maxRetries: 0 })
  })
  it('a call without limits keeps the client defaults (no request options)', async () => {
    const { llm, create } = stubbed()
    await llm.complete({ model: 'm', systemPrompt: 's', messages: [] })
    expect(create.mock.calls).toEqual([
      [
        {
          model: 'm',
          messages: [{ role: 'system', content: 's' }],
          temperature: 0.4,
          max_tokens: 8192,
        },
        undefined,
      ],
    ])
  })
})
