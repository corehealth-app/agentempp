import type { LLMCallParams, LLMResult } from '@mpp/providers'
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
    router = createOpenRouterConversationIntakeRouter('synthetic-private-key', provider)
  return { complete, provider, router }
}
function mediaSource(
  kind: 'audio_note' | 'meal_photo' | 'gym_photo',
  result: Record<string, unknown>,
) {
  const input = bindConversationIntake(owner, `cintake1:${id}`, {
      intake_protocol: 'conversation.intake.v1',
      intake_id: id,
      source: {
        channel: 'media',
        media_asset_id: 'c3cc0000-0000-4000-8000-000000000053',
        user_action: 'report_actual_record',
        caption: 'O que acha desta refeição?',
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
        context_text: 'Ainda não consumi.',
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
  it('preserves literal full discourse and omits private authority and credentials', async () => {
    const f = setup(),
      text = '  Comi arroz200g; não comi feijão.\nPosso caminhar? 🥛'
    await f.router.route(source(text))
    const call = f.complete.mock.calls[0]?.[0]
    expect(call).toMatchObject({
      temperature: 0,
      maxRetries: 0,
      toolChoice: 'none',
      responseFormat: { type: 'json_object' },
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
