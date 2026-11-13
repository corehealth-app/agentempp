import type { LLMCallParams, LLMResult } from '@mpp/providers'
import {
  APIConnectionError,
  APIConnectionTimeoutError,
  APIUserAbortError,
  AuthenticationError,
} from 'openai'
import { describe, expect, it, vi } from 'vitest'
import {
  bindConversationIntake,
  parseConversationIntakeSource,
} from './conversation-intake-contracts'
import { createOpenRouterConversationIntakeRouter } from './conversation-intake-router'

const owner = 'c3cc0000-0000-4000-8000-000000000001',
  id = 'c3cc0000-0000-4000-8000-000000000051',
  epoch = 'c3cc0000-0000-4000-8000-000000000052'
function source(text = 'Comi arroz 200 g; feijão 100 g') {
  const input = bindConversationIntake(owner, `cintake1:${id}`, {
      intake_protocol: 'conversation.intake.v1',
      intake_id: id,
      source: { channel: 'text', text },
      meal_type_hint: 'cafe',
    }),
    binding = {
      owner_id: owner,
      intake_id: id,
      input_hash: input.inputHash,
      epoch,
      admitted_at: '2026-11-05T13:00:00.000001Z',
    }
  return parseConversationIntakeSource(input, binding, {
    source_hash: 'a'.repeat(64),
    context: {
      schema: 'conversation.intake-source.v1',
      ...binding,
      source_input: input.input,
      captured_at: '2026-11-05T13:00:00.000002Z',
      time_zone: 'UTC',
      local_date: '2026-11-05',
      media: null,
    },
  })
}
const decision = {
  schema: 'conversation.intake-routing.v1',
  kind: 'meal.report',
  reason: 'reported_consumption',
}
function reply(content = JSON.stringify(decision)): LLMResult {
  return {
    content,
    finishReason: 'stop',
    toolCalls: [],
    model: 'configured-model',
    promptTokens: 20,
    completionTokens: 30,
    totalTokens: 50,
    costUsd: null,
    latencyMs: 5,
  }
}
function setup(content = JSON.stringify(decision)) {
  const complete = vi.fn<(_input: LLMCallParams) => Promise<LLMResult>>(async () => reply(content)),
    provider = { complete },
    diagnostic = vi.fn(),
    router = createOpenRouterConversationIntakeRouter('synthetic-private-key', provider, diagnostic)
  return { complete, provider, router, diagnostic }
}
function mediaSource(
  kind: 'audio_note' | 'meal_photo' | 'gym_photo' | 'conversation_photo',
  result: Record<string, unknown>,
  caption: string | null = 'O que acha desta refeição?',
  context: string | null = 'Ainda não consumi.',
) {
  const input = bindConversationIntake(owner, `cintake1:${id}`, {
      intake_protocol: 'conversation.intake.v1',
      intake_id: id,
      source: {
        channel: 'media',
        media_asset_id: 'c3cc0000-0000-4000-8000-000000000053',
        user_action: 'report_actual_record',
        ...(caption === null ? {} : { caption }),
      },
    }),
    binding = {
      owner_id: owner,
      intake_id: id,
      input_hash: input.inputHash,
      epoch,
      admitted_at: '2026-11-05T13:00:00.000001Z',
    }
  return parseConversationIntakeSource(input, binding, {
    source_hash: 'b'.repeat(64),
    context: {
      schema: 'conversation.intake-source.v1',
      ...binding,
      source_input: input.input,
      captured_at: '2026-11-05T13:00:00.000002Z',
      time_zone: 'UTC',
      local_date: '2026-11-05',
      media: {
        asset_id: input.input.source.channel === 'media' ? input.input.source.media_asset_id : '',
        owner_id: owner,
        kind,
        status: 'processed',
        processed_at: '2026-11-05T12:59:59Z',
        updated_at: '2026-11-05T12:59:59Z',
        context_text: context,
        processing_result: result,
      },
    },
  })
}
describe('neutral provider routing without performed or nutrition authority', () => {
  it('constructs a pure factory and invokes a provider only on route', async () => {
    const f = setup()
    expect(f.complete).not.toHaveBeenCalled()
    const value = await f.router.route(source())
    expect(value).toEqual(decision)
    expect(Object.isFrozen(value)).toBe(true)
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it('constrains provider routing to a closed strict schema rather than unrestricted JSON', async () => {
    const f = setup()
    await f.router.route(source())
    const format = f.complete.mock.calls[0]?.[0].responseFormat
    expect(format).toMatchObject({
      type: 'json_schema',
      json_schema: {
        name: 'conversation_intake_routing_v1',
        strict: true,
        schema: { type: 'object', additionalProperties: false },
      },
    })
    if (!format || format.type !== 'json_schema') throw new Error('Expected strict provider wire')
    expect(format.json_schema.schema?.required).toEqual(['schema', 'kind', 'reason', 'question'])
    expect(f.complete.mock.calls[0]?.[0].provider).toEqual({ require_parameters: true })
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it.each([
    'meal.report',
    'workout.report',
    'not_reported',
  ] as const)('maps the required nullable provider question for %s to the unchanged canonical result', async (kind) => {
    const f = setup(JSON.stringify({ ...decision, kind, question: null }))
    expect(await f.router.route(source())).toEqual({ ...decision, kind })
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it.each([
    { ...decision, question: null, owner_id: owner },
    { ...decision, question: null, meal_type: 'almoco' },
    { ...decision, kind: 'clarification_required', question: null },
    { ...decision, question: { field: 'description', text: 'What?' } },
  ])('never strips unknown keys or upgrades malformed nullable-question output', async (wire) => {
    const f = setup(JSON.stringify(wire))
    expect(await f.router.route(source())).toMatchObject({
      kind: 'clarification_required',
      reason: 'routing_unavailable',
    })
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it('preserves literal full discourse and omits private authority and credentials', async () => {
    const f = setup(),
      text = '  Comi arroz200g; não comi feijão.\nPosso caminhar? 🥛'
    await f.router.route(source(text))
    const call = f.complete.mock.calls[0]?.[0]
    expect(call).toMatchObject({
      temperature: 0,
      maxRetries: 0,
      toolChoice: 'none',
      responseFormat: { type: 'json_schema', json_schema: { strict: true } },
      provider: { require_parameters: true },
    })
    for (const key of ['tools', 'userId', 'metadata']) expect(call).not.toHaveProperty(key)
    const json = JSON.stringify(call)
    for (const value of [
      owner,
      id,
      epoch,
      'synthetic-private-key',
      'admitted_at',
      'source_hash',
      'input_hash',
    ])
      expect(json).not.toContain(value)
    expect(JSON.parse(String(call?.messages[0]?.content))).toEqual({
      sources: [{ unit: 'command_text', text }],
      meal_type_hint: 'cafe',
      media_kind: null,
    })
  })
  it.each([
    'meal.report',
    'workout.report',
    'not_reported',
  ] as const)('retains the closed %s routing hint', async (kind) => {
    const f = setup(JSON.stringify({ ...decision, kind }))
    expect(await f.router.route(source())).toEqual({ ...decision, kind })
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it('retains a specific clarification and a whole fenced JSON result', async () => {
    const value = {
        schema: 'conversation.intake-routing.v1',
        kind: 'clarification_required',
        reason: 'multiple_records',
        question: {
          field: 'record_kind',
          text: 'Você quer registrar a refeição ou a atividade primeiro?',
        },
      },
      f = setup(`\`\`\`json\n${JSON.stringify(value)}\n\`\`\``)
    expect(await f.router.route(source())).toEqual(value)
  })
  it.each([
    '',
    'not JSON',
    '{"schema":"conversation.intake-routing.v1","kind":"meal.report","kind":"workout.report","reason":"reported"}',
    JSON.stringify({ ...decision, owner_id: owner }),
    JSON.stringify({ ...decision, kcal: 300 }),
    JSON.stringify({ ...decision, question: { field: 'description', text: 'Ignored?' } }),
    JSON.stringify({ ...decision, kind: 'clarification_required' }),
    'x'.repeat(8193),
  ])('does not turn malformed output into a domain command', async (content) => {
    const f = setup(content)
    expect(await f.router.route(source())).toMatchObject({
      kind: 'clarification_required',
      reason: 'routing_unavailable',
      question: { field: 'description' },
    })
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it.each(['length', 'tool_calls'])('refuses the %s completion as a hint', async (finishReason) => {
    const f = setup()
    f.complete.mockResolvedValueOnce({ ...reply(), finishReason })
    expect(await f.router.route(source())).toMatchObject({ reason: 'routing_unavailable' })
  })
  it('does not accept tool calls even with a stop reason', async () => {
    const f = setup()
    f.complete.mockResolvedValueOnce({
      ...reply(),
      toolCalls: [{ id: 'fake', name: 'write', arguments: '{}' }],
    })
    expect(await f.router.route(source())).toMatchObject({ reason: 'routing_unavailable' })
  })
  it('does not retry or disclose a thrown provider result', async () => {
    const f = setup()
    f.complete.mockRejectedValueOnce(new Error('private-secret-token and provider content'))
    const result = await f.router.route(source())
    expect(result).toMatchObject({ reason: 'routing_unavailable' })
    expect(JSON.stringify(result)).not.toContain('private-secret')
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it('rejects changed captured source before any provider call', async () => {
    const f = setup()
    await expect(f.router.route({ ...source(), sourceHash: 'changed' })).rejects.toMatchObject({
      code: 'conversation_intake_changed',
    })
    expect(f.complete).not.toHaveBeenCalled()
  })
  it('pins the method and receiver instead of observing a replaced callback', async () => {
    const original = reply(),
      provider = {
        expected: original,
        async complete() {
          return this.expected
        },
      },
      router = createOpenRouterConversationIntakeRouter('synthetic-key', provider)
    provider.complete = vi.fn(async () => {
      throw new Error('Replaced')
    })
    expect(await router.route(source())).toEqual(decision)
    expect(provider.complete).not.toHaveBeenCalled()
  })
  it('rejects missing configuration before consuming a permanent claim', () => {
    const f = setup()
    expect(() => createOpenRouterConversationIntakeRouter(' ', f.provider)).toThrow()
    expect(f.complete).not.toHaveBeenCalled()
  })
  it('preserves caption, media context and transcript separately without provider raw response', async () => {
    const f = setup()
    await f.router.route(
      mediaSource('audio_note', {
        text: 'Amanhã vou comer arroz.',
        latencyMs: 5,
        raw_response: 'private-provider-output',
      }),
    )
    const content = f.complete.mock.calls[0]?.[0].messages[0]?.content,
      request = JSON.parse(String(content))
    expect(request.sources).toEqual([
      { unit: 'media_caption', text: 'O que acha desta refeição?' },
      { unit: 'media_context', text: 'Ainda não consumi.' },
      { unit: 'media_transcript', text: 'Amanhã vou comer arroz.' },
    ])
    expect(String(content)).not.toContain('private-provider-output')
    expect(String(content)).not.toContain('latencyMs')
  })
  it('projects observed visual candidates without treating them as a saved meal', async () => {
    const f = setup()
    await f.router.route(
      mediaSource('meal_photo', {
        type: 'meal',
        items: [
          { name: 'arroz', quantity_g_estimate: 200, confidence: 0.7, notes: 'porção aproximada' },
        ],
        meal_context: 'prato',
        raw_response: 'private-raw',
        promptTokens: 100,
      }),
    )
    const content = f.complete.mock.calls[0]?.[0].messages[0]?.content,
      request = JSON.parse(String(content))
    expect(request.sources[2]).toEqual({
      unit: 'vision_meal',
      visual: {
        type: 'meal',
        items: [
          { name: 'arroz', quantity_g_estimate: 200, confidence: 0.7, notes: 'porção aproximada' },
        ],
        meal_context: 'prato',
      },
    })
    expect(String(content)).not.toMatch(/private-raw|promptTokens|owner_id|asset_id/u)
  })
  it('keeps equipment descriptive and excludes transport/usage data', async () => {
    const f = setup()
    await f.router.route(
      mediaSource('gym_photo', {
        type: 'equipment',
        equipment: ['halteres'],
        location: 'casa',
        confidence: 0.9,
        notes: 'Foto de aparelhos',
        raw_response: 'private-raw',
      }),
    )
    const request = JSON.parse(String(f.complete.mock.calls[0]?.[0].messages[0]?.content))
    expect(request.sources[2]).toEqual({
      unit: 'vision_equipment',
      visual: {
        type: 'equipment',
        equipment: ['halteres'],
        location: 'casa',
        confidence: 0.9,
        notes: 'Foto de aparelhos',
      },
    })
    expect(request).not.toHaveProperty('performed')
  })
  it('does not truncate an oversized transcript into apparently complete discourse', async () => {
    const f = setup()
    expect(
      await f.router.route(mediaSource('audio_note', { text: 'a'.repeat(2001) })),
    ).toMatchObject({ kind: 'clarification_required', reason: 'routing_unavailable' })
    expect(f.complete).not.toHaveBeenCalled()
  })
})

describe('safe routing failure diagnostics without changing the durable outcome', () => {
  it('reports a genuine provider HTTP status and elapsed duration without provider contents', async () => {
    const f = setup(),
      clock = vi.spyOn(performance, 'now').mockReturnValueOnce(100).mockReturnValueOnce(350)
    f.complete.mockRejectedValueOnce(
      new AuthenticationError(
        401,
        { message: 'private-provider-body' },
        'private-provider-message',
        { authorization: 'private-provider-token' },
      ),
    )
    try {
      expect(await f.router.route(source('private-user-discourse'))).toMatchObject({
        kind: 'clarification_required',
        reason: 'routing_unavailable',
      })
      expect(f.diagnostic.mock.calls).toEqual([
        [{ phase: 'provider', category: 'http_error', duration_ms: 250, http_status: 401 }],
      ])
      expect(f.complete).toHaveBeenCalledOnce()
    } finally {
      clock.mockRestore()
    }
  })
  it.each([
    [new APIConnectionTimeoutError({ message: 'private-timeout-details' }), 'timeout'],
    [new APIConnectionError({ message: 'private-connection-details' }), 'connection_error'],
    [new APIUserAbortError({ message: 'private-abort-details' }), 'aborted'],
    [new Error('private-provider-details'), 'provider_error'],
    [
      { status: 401, name: 'APIConnectionTimeoutError', message: 'private-forged' },
      'provider_error',
    ],
  ])('uses a closed provider error category without inventing an HTTP status', async (error, category) => {
    const f = setup()
    f.complete.mockRejectedValueOnce(error)
    expect(await f.router.route(source())).toMatchObject({ reason: 'routing_unavailable' })
    expect(f.diagnostic.mock.calls).toEqual([
      [{ phase: 'provider', category, duration_ms: expect.any(Number) }],
    ])
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it.each([
    [{ ...reply(), finishReason: 'length' }, 'invalid_result', 'length'],
    [{ ...reply(), finishReason: 'private-unexpected-finish' }, 'invalid_result', 'unknown'],
    [reply('private-invalid-json'), 'invalid_json', 'stop'],
    [reply(JSON.stringify({ ...decision, kind: 'private-invalid-kind' })), 'invalid_shape', 'stop'],
  ])('separates completion, JSON and schema rejection without logging raw output', async (result, category, finishReason) => {
    const f = setup()
    f.complete.mockResolvedValueOnce(result)
    expect(await f.router.route(source())).toMatchObject({ reason: 'routing_unavailable' })
    expect(f.diagnostic).toHaveBeenCalledOnce()
    const event = f.diagnostic.mock.calls[0]?.[0]
    expect(event).toMatchObject({
      phase: 'decode',
      category,
      duration_ms: expect.any(Number),
      finish_reason: finishReason,
    })
    expect(Object.keys(event).sort()).toEqual(
      [
        'phase',
        'category',
        'duration_ms',
        'finish_reason',
        ...(category === 'invalid_shape' ? ['validation_issue_codes'] : []),
      ].sort(),
    )
    if (category === 'invalid_shape')
      expect(event.validation_issue_codes).toEqual(['invalid_enum_value'])
    expect(JSON.stringify(event)).not.toMatch(/private|c3cc|reported_consumption|meal\.report/u)
    expect(event).not.toHaveProperty('http_status')
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it('reports discourse validation codes without transcripts, paths, IDs or provider invocation', async () => {
    const f = setup()
    expect(
      await f.router.route(mediaSource('audio_note', { text: 'private-'.repeat(300) })),
    ).toMatchObject({ reason: 'routing_unavailable' })
    expect(f.diagnostic.mock.calls).toEqual([
      [
        {
          phase: 'discourse',
          category: 'invalid_discourse',
          duration_ms: expect.any(Number),
          validation_issue_codes: ['too_big'],
        },
      ],
    ])
    expect(f.complete).not.toHaveBeenCalled()
  })
  it('keeps invalid immutable input outside the diagnostic catch', async () => {
    const f = setup()
    await expect(
      f.router.route({ ...source(), sourceHash: 'private-changed' }),
    ).rejects.toMatchObject({
      code: 'conversation_intake_changed',
    })
    expect(f.diagnostic).not.toHaveBeenCalled()
    expect(f.complete).not.toHaveBeenCalled()
  })
  it('does not inspect getters or stringify a thrown provider object', async () => {
    const f = setup(),
      access = vi.fn(() => {
        throw new Error('private-poison')
      }),
      error = new AuthenticationError(401, undefined, 'private-error', {})
    for (const key of ['name', 'message', 'status', 'headers', 'error', 'issues', 'toJSON'])
      Object.defineProperty(error, key, { configurable: true, get: access })
    f.complete.mockRejectedValueOnce(error)
    expect(await f.router.route(source())).toMatchObject({ reason: 'routing_unavailable' })
    expect(access).not.toHaveBeenCalled()
    expect(f.diagnostic.mock.calls).toEqual([
      [{ phase: 'provider', category: 'provider_error', duration_ms: expect.any(Number) }],
    ])
  })
  it('does not turn a failed diagnostic sink into another provider call or failure', async () => {
    const f = setup()
    f.complete.mockRejectedValueOnce(new APIConnectionTimeoutError())
    f.diagnostic.mockImplementationOnce(() => {
      throw new Error('private-logger-failure')
    })
    expect(await f.router.route(source())).toMatchObject({ reason: 'routing_unavailable' })
    expect(f.diagnostic).toHaveBeenCalledOnce()
    expect(f.complete).toHaveBeenCalledOnce()
  })
  it('uses the same safe event for the default server logger and emits nothing on success', async () => {
    const log = vi.spyOn(console, 'warn').mockImplementation(() => undefined),
      complete = vi.fn(async () => reply()),
      router = createOpenRouterConversationIntakeRouter('synthetic-private-key', { complete })
    try {
      expect(await router.route(source())).toEqual(decision)
      expect(log).not.toHaveBeenCalled()
      complete.mockRejectedValueOnce(new APIConnectionTimeoutError())
      expect(await router.route(source())).toMatchObject({ reason: 'routing_unavailable' })
      expect(log.mock.calls).toEqual([
        [
          '[mobile-api] conversation_intake_routing_failed',
          { phase: 'provider', category: 'timeout', duration_ms: expect.any(Number) },
        ],
      ])
    } finally {
      log.mockRestore()
    }
  })
})

describe('ordinary photos retain their validated classification and literal discourse', () => {
  it.each([
    'meal',
    'equipment',
  ] as const)('routes %s observations without retagging the asset', async (classification) => {
    const analysis =
      classification === 'meal'
        ? { type: 'meal', items: [{ name: 'arroz', quantity_g_estimate: 100, confidence: 0.9 }] }
        : {
            type: 'equipment',
            equipment: ['esteira'],
            location: 'academia_completa',
            confidence: 0.9,
          }
    const f = setup(),
      source = mediaSource('conversation_photo', {
        schema: 'conversation.image-result.v1',
        status: 'ready',
        classification,
        analysis,
      })
    await f.router.route(source)
    const sent = JSON.parse(String(f.complete.mock.calls[0]?.[0].messages[0]?.content))
    expect(sent.media_kind).toBe('conversation_photo')
    expect(sent.sources).toContainEqual({
      unit: classification === 'meal' ? 'vision_meal' : 'vision_equipment',
      visual: analysis,
    })
    expect(sent.sources).toContainEqual({
      unit: 'media_caption',
      text: 'O que acha desta refeição?',
    })
    expect(sent.sources).toContainEqual({ unit: 'media_context', text: 'Ainda não consumi.' })
  })
  it.each([
    'body',
    'scale',
    'other',
    'unknown',
  ])('does not request model interpretation of unsupported %s pixels', async (classification) => {
    const f = setup(),
      result = await f.router.route(
        mediaSource('conversation_photo', {
          schema: 'conversation.image-result.v1',
          status: 'unsupported',
          classification,
          reason: 'image_not_supported_for_conversation',
        }),
      )
    expect(result).toMatchObject({
      kind: 'clarification_required',
      reason: 'image_not_supported_for_conversation',
      question: { field: 'description' },
    })
    expect(f.complete).not.toHaveBeenCalled()
  })
})

describe('reviewed missing ordinary observations preserve sufficient literal reports', () => {
  const macros = { kcal: null, protein_g: null, carbs_g: null, fat_g: null }
  it.each([
    null,
    '',
    ' ',
    'x'.repeat(241),
  ])('asks for label identity before creating an unusable child (%#)', async (product_name) => {
    const f = setup(),
      raw = {
        schema: 'conversation.image-result.v1',
        status: 'ready',
        classification: 'nutrition_label',
        analysis: {
          type: 'nutrition_label',
          product_name,
          serving_size_g: 30,
          per_serving: macros,
          per_100g: macros,
          confidence: 0.9,
        },
      }
    expect(await f.router.route(mediaSource('conversation_photo', raw, null, null))).toMatchObject({
      kind: 'clarification_required',
      reason: 'label_product_required',
      question: { field: 'description' },
    })
    expect(f.complete).not.toHaveBeenCalled()
  })
  it('routes a complete caption when the ordinary meal image has no identifiable items', async () => {
    const f = setup(),
      raw = {
        schema: 'conversation.image-result.v1',
        status: 'ready',
        classification: 'meal',
        analysis: { type: 'meal', items: [] },
      }
    expect(
      await f.router.route(mediaSource('conversation_photo', raw, 'Comi arroz 100 g', null)),
    ).toEqual(decision)
    expect(f.complete).toHaveBeenCalledOnce()
    const sent = JSON.parse(String(f.complete.mock.calls[0]?.[0].messages[0]?.content))
    expect(sent.sources).toContainEqual({ unit: 'media_caption', text: 'Comi arroz 100 g' })
  })
  it('asks a specific food question when neither image nor literal text supplies observations', async () => {
    const f = setup(),
      raw = {
        schema: 'conversation.image-result.v1',
        status: 'ready',
        classification: 'meal',
        analysis: { type: 'meal', items: [] },
      }
    expect(await f.router.route(mediaSource('conversation_photo', raw, null, null))).toMatchObject({
      kind: 'clarification_required',
      reason: 'image_description_required',
      question: { field: 'description' },
    })
    expect(f.complete).not.toHaveBeenCalled()
  })
})
