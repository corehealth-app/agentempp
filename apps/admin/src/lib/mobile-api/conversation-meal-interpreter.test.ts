import { type LLMCallParams, type LLMResult, OpenRouterLLM } from '@mpp/providers'
import { describe, expect, it, vi } from 'vitest'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  buildConversationMealInterpretationSource,
  interpretationModelSchema,
  type MealInterpretationModelResult,
  parseConversationMealInterpretation,
} from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import { createOpenRouterConversationMealInterpreter } from './conversation-meal-interpreter'

const owner = '10000000-0000-4000-8000-000000000001'
const id = '10000000-0000-4000-8000-000000000002'
const epoch = '10000000-0000-4000-8000-000000000003'
function textSource(text: string) {
  const command = bindConversationCommand(owner, `cmsg1:${id}`, {
    command_protocol: 'conversation.command.v1',
    command_id: id,
    kind: 'meal.report',
    source: { channel: 'text', text },
  })
  return {
    command,
    capture: {
      sourceHash: 'a'.repeat(64),
      capturedAt: '2026-11-04T01:00:00.000001Z',
      epoch,
      context: {
        schema: 'conversation.meal-source.v1',
        owner_id: owner,
        command_id: id,
        input_hash: command.inputHash,
        epoch,
        source_input: command.command,
        source_units: ['command_text'],
        source_evidence: {},
        media: null,
      },
    },
  }
}
describe('closed semantic interpreter input and result', () => {
  it('captures the complete original bare food list without a verbal gate', () => {
    const f = textSource('arroz200g; feijão100g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    expect(source.sources).toEqual([
      { unit: 'command_text', text: 'arroz200g; feijão100g', visual_items: [] },
    ])
    expect(source.source_units).toEqual(['command_text'])
    expect(source.input_hash).toBe(f.command.inputHash)
    expect(Object.isFrozen(source.sources)).toBe(true)
  })
  it('rejects model-chosen authority and unknown model fields', () => {
    expect(
      interpretationModelSchema.safeParse({
        schema: 'conversation.meal-interpretation.v1',
        decision: 'reported_meal',
        reason: 'nominal_food_list',
        sources: [],
        foods: [],
        owner_id: owner,
      }).success,
    ).toBe(false)
  })
  it('accepts nominal lists and explicit reports with exact occurrence spans, without parser agreement', () => {
    for (const text of ['arroz200g; feijão100g', 'Comi arroz200g; feijão100g']) {
      const f = textSource(text),
        source = buildConversationMealInterpretationSource(f.command, f.capture)
      const model = modelFor(text, [
        { name: 'arroz', quantity: '200', unit: 'g' },
        { name: 'feijão', quantity: '100', unit: 'g' },
      ])
      expect(validateConversationMealInterpretationModel(model, source).decision).toBe(
        'reported_meal',
      )
    }
  })
  it.each([
    'Sonhei que comi arroz200g',
    'Comi arroz200g no sonho',
    'Vou comer arroz200g',
    'Geralmente como arroz200g',
    'Não comi arroz200g',
    'Minha filha comeu arroz200g',
    'Posso comer arroz200g?',
    'Comi arroz200g mas não feijão100g',
  ])('does not let model assertion authorize %s', (text) => {
    const f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const model = modelFor(text, [{ name: 'arroz', quantity: '200', unit: 'g' }])
    expect(validateConversationMealInterpretationModel(model, source).decision).not.toBe(
      'reported_meal',
    )
  })
  it('refuses prose inside food names, separate from successful gram parsing', () => {
    const text = 'arroz menos20g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    expect(
      validateConversationMealInterpretationModel(
        modelFor(text, [{ name: 'arroz menos', quantity: '20', unit: 'g' }]),
        source,
      ).decision,
    ).toBe('clarification_required')
    for (const [value, name] of [
      ['Comi arroz no sonho 100g', 'arroz no sonho'],
      ['Sobra de arroz 100g', 'Sobra de arroz'],
    ]) {
      const f = textSource(value),
        packet = buildConversationMealInterpretationSource(f.command, f.capture)
      expect(
        validateConversationMealInterpretationModel(
          modelFor(value, [{ name, quantity: '100', unit: 'g' }]),
          packet,
        ).decision,
      ).toBe('clarification_required')
    }
  })
  it('preserves duplicate occurrences and rejects shared/shortened references', () => {
    const text = 'arroz200g; arroz100g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const raw = modelFor(text, [
      { name: 'arroz', quantity: '200', unit: 'g' },
      { name: 'arroz', quantity: '100', unit: 'g' },
    ])
    expect(validateConversationMealInterpretationModel(raw, source).foods).toHaveLength(2)
    const reused = structuredClone(raw)
    at(reused.foods, 1).name = at(reused.foods).name
    expect(() => validateConversationMealInterpretationModel(reused, source)).toThrow()
    const shortened = structuredClone(raw)
    const shortenedName = at(shortened.foods).name
    if (!shortenedName) throw new Error('fixture name')
    shortenedName.end -= 1
    expect(() => validateConversationMealInterpretationModel(shortened, source)).toThrow()
    const swapped = structuredClone(raw)
    const a = at(swapped.foods),
      b = at(swapped.foods, 1)
    ;[a.quantity, b.quantity] = [b.quantity, a.quantity]
    ;[a.unit, b.unit] = [b.unit, a.unit]
    for (const span of at(swapped.sources).spans)
      if (span.kind === 'quantity' || span.kind === 'unit')
        span.food_index = span.food_index === 0 ? 1 : 0
    expect(() => validateConversationMealInterpretationModel(swapped, source)).toThrow()
  })
  it('validates original UTF16 without normalizing accents or splitting surrogate pairs', () => {
    const text = 'Comi feija\u0303o100g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    expect(
      validateConversationMealInterpretationModel(
        modelFor(text, [{ name: 'feija\u0303o', quantity: '100', unit: 'g' }]),
        source,
      ).decision,
    ).toBe('reported_meal')
    const u = textSource('😀')
    const packet = buildConversationMealInterpretationSource(u.command, u.capture)
    const raw = {
      schema: 'conversation.meal-interpretation.v1',
      decision: 'not_reported',
      reason: 'ambiguous',
      sources: [
        {
          unit: 'command_text',
          classification: 'ambiguous',
          spans: [
            { start: 0, end: 1, kind: 'other', food_index: null },
            { start: 1, end: 2, kind: 'other', food_index: null },
          ],
          visual_indexes: [],
        },
      ],
      foods: [],
    }
    expect(() => validateConversationMealInterpretationModel(raw, packet)).toThrow()
  })
  it('uses the real provider API with explicit single-attempt, token/deadline and no tools authority', async () => {
    const text = 'arroz200g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const raw = modelFor(text, [{ name: 'arroz', quantity: '200', unit: 'g' }]),
      complete = vi.fn<(p: LLMCallParams) => Promise<LLMResult>>(async () => providerResult(raw))
    const interpreter = createOpenRouterConversationMealInterpreter('synthetic-key', { complete })
    expect(complete).not.toHaveBeenCalled()
    const result = await interpreter.interpret(source, { attemptId: epoch, remainingMs: 5000 })
    expect(complete).toHaveBeenCalledTimes(1)
    expect(complete.mock.calls[0]?.[0]).toMatchObject({
      model: 'anthropic/claude-haiku-4.5',
      maxRetries: 0,
      requestTimeoutMs: 5000,
      maxTokens: 8192,
      temperature: 0,
      responseFormat: { type: 'json_object' },
    })
    expect(complete.mock.calls[0]?.[0]).not.toHaveProperty('tools')
    expect(result).toMatchObject({
      schema: 'conversation.meal-interpretation.v1',
      interpreter_version: 'conversation.meal-interpreter.v1',
      owner_id: owner,
      command_id: id,
      attempt_id: epoch,
      input_hash: f.command.inputHash,
      source_hash: 'a'.repeat(64),
      decision: 'reported_meal',
    })
    expect(result).not.toHaveProperty('complete_source')
    expect(result).not.toHaveProperty('semantic_proof')
    expect(JSON.stringify(complete.mock.calls[0]?.[0]?.messages)).not.toContain(owner)
    expect(Object.isFrozen(result.foods)).toBe(true)
  })
  it.each([
    'length',
    'tool_calls',
    'empty',
    'nonfinite',
    'unknown',
  ])('rejects provider outcome %s without retry', async (failure) => {
    const text = 'arroz200g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const r = providerResult(modelFor(text, [{ name: 'arroz', quantity: '200', unit: 'g' }]))
    if (failure === 'length') r.finishReason = 'length'
    if (failure === 'tool_calls')
      r.toolCalls = [{ id: 'bad', name: 'register_meal', arguments: '{}' }]
    if (failure === 'empty') r.content = ''
    if (failure === 'nonfinite') r.costUsd = Number.POSITIVE_INFINITY
    if (failure === 'unknown')
      r.content = JSON.stringify({ ...JSON.parse(r.content ?? '{}'), nutrition: {} })
    const complete = vi.fn(async () => r),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic-key', { complete })
    await expect(
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 50000 }),
    ).rejects.toMatchObject({ code: 'conversation_meal_interpretation_unavailable' })
    expect(complete).toHaveBeenCalledTimes(1)
  })
  it('handles owned photo and audio evidence without rerunning Vision/STT or selecting nutrition', () => {
    for (const kind of ['meal_photo', 'audio_note'] as const) {
      const f = mediaSource(kind),
        source = buildConversationMealInterpretationSource(f.command, f.capture)
      const raw: MealInterpretationModelResult =
        kind === 'meal_photo'
          ? photoResult(source)
          : inUnit(
              modelFor('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }]),
              'media_transcript',
            )
      raw.reason = 'explicit_media_action'
      expect(validateConversationMealInterpretationModel(raw, source).decision).toBe(
        'reported_meal',
      )
      expect(source.media_binding?.processing_hash).toMatch(/^[a-f0-9]{64}$/u)
      expect(source.sources.map((s) => s.unit)).toEqual(
        kind === 'meal_photo' ? ['vision_items'] : ['media_transcript'],
      )
    }
  })
  it('rejects caption omission and never lets photo evidence override a negated caption', () => {
    const f = mediaSource('meal_photo', 'Não comi'),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const lie = photoResult(source)
    at(lie.sources).classification = 'media_pointer'
    expect(validateConversationMealInterpretationModel(lie, source).decision).toBe(
      'clarification_required',
    )
    const omitted = structuredClone(lie)
    omitted.sources.shift()
    expect(() => validateConversationMealInterpretationModel(omitted, source)).toThrow()
    f.capture.context.source_units = ['vision_items']
    expect(() => buildConversationMealInterpretationSource(f.command, f.capture)).toThrow()
  })
  it('keeps caption and audio transcript distinct, rejecting contradictory claims', () => {
    const f = mediaSource('audio_note', 'Não comi'),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const raw = inUnit(
      modelFor('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }]),
      'media_transcript',
    )
    raw.sources.unshift({
      unit: 'media_caption',
      classification: 'negated',
      spans: [{ start: 0, end: 8, kind: 'other', food_index: null }],
      visual_indexes: [],
    })
    expect(validateConversationMealInterpretationModel(raw, source).decision).toBe(
      'clarification_required',
    )
    f.capture.context.media.processing_result.text = 'changed after capture'
    expect(source.sources[1]?.text).toBe('arroz200g')
    expect(() => buildConversationMealInterpretationSource(f.command, f.capture)).toThrow()
  })
  it('requires every captured visual item and rejects a fabricated visual index', () => {
    const f = mediaSource('meal_photo'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      raw = photoResult(source)
    at(raw.sources).visual_indexes = []
    expect(() => validateConversationMealInterpretationModel(raw, source)).toThrow()
    const forged = photoResult(source)
    at(forged.foods).visual_index = 1
    expect(() => validateConversationMealInterpretationModel(forged, source)).toThrow()
  })
  it('refuses tampered owner/hash/media/epoch and oversized sources before provider work', () => {
    for (const field of ['owner_id', 'input_hash', 'epoch'] as const) {
      const f = textSource('arroz200g')
      Object.assign(f.capture.context, { [field]: 'invalid' })
      expect(() => buildConversationMealInterpretationSource(f.command, f.capture)).toThrow()
    }
    const f = mediaSource('audio_note')
    f.capture.context.media.asset_id = owner
    expect(() => buildConversationMealInterpretationSource(f.command, f.capture)).toThrow()
    const tooBig = mediaSource('audio_note')
    tooBig.capture.context.media.processing_result.text = 'x'.repeat(2001)
    tooBig.capture.context.source_evidence.transcript = 'x'.repeat(2001)
    expect(() =>
      buildConversationMealInterpretationSource(tooBig.command, tooBig.capture),
    ).toThrow()
  })
  it('clarifies potentially duplicate audio/caption occurrences rather than adding both amounts', () => {
    const f = mediaSource('audio_note', 'arroz100g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const caption = inUnit(
      modelFor('arroz100g', [{ name: 'arroz', quantity: '100', unit: 'g' }]),
      'media_caption',
    )
    const transcript = inUnit(
      modelFor('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }]),
      'media_transcript',
    )
    at(transcript.foods).index = 1
    for (const span of at(transcript.sources).spans)
      if (span.food_index !== null) span.food_index = 1
    const raw = {
      ...caption,
      reason: 'explicit_media_action' as const,
      sources: [...caption.sources, ...transcript.sources],
      foods: [...caption.foods, ...transcript.foods],
    }
    expect(validateConversationMealInterpretationModel(raw, source).decision).toBe(
      'clarification_required',
    )
  })
  it('rejects omitted text partitions and duplicate JSON keys, and binds all sealed replay headers', async () => {
    const text = 'arroz200g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const raw = modelFor(text, [{ name: 'arroz', quantity: '200', unit: 'g' }]),
      omitted = structuredClone(raw)
    at(omitted.sources).spans.pop()
    expect(() => validateConversationMealInterpretationModel(omitted, source)).toThrow()
    const complete = vi.fn(async () => providerResult(raw)),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete })
    const result = await interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 })
    const binding = {
      ownerId: owner,
      commandId: id,
      attemptId: epoch,
      inputHash: source.input_hash,
      sourceHash: source.source_hash,
    }
    expect(parseConversationMealInterpretation(result, binding)).toEqual(result)
    for (const key of ['ownerId', 'commandId', 'attemptId', 'inputHash', 'sourceHash'] as const) {
      const changed = {
        ...binding,
        [key]: key.endsWith('Hash') ? 'b'.repeat(64) : '10000000-0000-4000-8000-000000000099',
      }
      expect(() => parseConversationMealInterpretation(result, changed)).toThrow()
    }
    const duplicate = {
      ...providerResult(raw),
      content: JSON.stringify(raw).replace('"decision":', '"decision":"not_reported","decision":'),
    }
    complete.mockResolvedValueOnce(duplicate)
    await expect(
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
    ).rejects.toMatchObject({ code: 'conversation_meal_interpretation_unavailable' })
  })
  it('binds mutable caller source/invocation/provider callback before awaiting', async () => {
    const text = 'arroz200g',
      f = textSource(text),
      source = structuredClone(buildConversationMealInterpretationSource(f.command, f.capture))
    let finish!: (value: LLMResult) => void
    const complete = vi.fn<(p: LLMCallParams) => Promise<LLMResult>>(
      () =>
        new Promise((resolve) => {
          finish = resolve
        }),
    )
    const llm = { complete },
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', llm),
      invocation = { attemptId: epoch, remainingMs: 5000 }
    const pending = interpreter.interpret(source, invocation)
    at(source.sources).text = 'Vou comer arroz200g'
    source.source_hash = 'b'.repeat(64)
    invocation.attemptId = owner
    const replacement = vi.fn()
    Object.assign(llm, { complete: replacement })
    finish(providerResult(modelFor(text, [{ name: 'arroz', quantity: '200', unit: 'g' }])))
    expect(await pending).toMatchObject({
      attempt_id: epoch,
      source_hash: 'a'.repeat(64),
      decision: 'reported_meal',
    })
    expect(replacement).not.toHaveBeenCalled()
    expect(complete).toHaveBeenCalledTimes(1)
  })
  it('wires the existing real OpenRouter constructor without issuing any actual request', async () => {
    const text = 'arroz200g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const mocked = vi
      .spyOn(OpenRouterLLM.prototype, 'complete')
      .mockResolvedValue(
        providerResult(modelFor(text, [{ name: 'arroz', quantity: '200', unit: 'g' }])),
      )
    try {
      const interpreter = createOpenRouterConversationMealInterpreter('unique-synthetic-no-network')
      await expect(
        interpreter.interpret(source, { attemptId: epoch, remainingMs: 90000 }),
      ).resolves.toMatchObject({ decision: 'reported_meal' })
      expect(mocked).toHaveBeenCalledTimes(1)
      expect(mocked.mock.calls[0]?.[0]).toMatchObject({ requestTimeoutMs: 45000, maxRetries: 0 })
    } finally {
      mocked.mockRestore()
    }
  })
  it('rejects exhausted budget before provider work and redacts a thrown provider error', async () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const complete = vi.fn(async () => {
        throw new Error('private-token-sentinel')
      }),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete })
    await expect(
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 0 }),
    ).rejects.toMatchObject({ code: 'conversation_meal_interpretation_unavailable' })
    expect(complete).not.toHaveBeenCalled()
    try {
      await interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 })
      throw new Error('expected')
    } catch (error) {
      expect(String(error)).not.toContain('private-token-sentinel')
      expect(error).toMatchObject({ status: 503 })
    }
    expect(complete).toHaveBeenCalledTimes(1)
  })
})

function at<T>(values: readonly T[], index = 0): T {
  const value = values[index]
  if (value === undefined) throw new Error('Missing fixture occurrence')
  return value
}

function mediaSource(kind: 'meal_photo' | 'audio_note', caption: string | null = null) {
  const asset = '10000000-0000-4000-8000-000000000004'
  const command = bindConversationCommand(owner, `cmsg1:${id}`, {
    command_protocol: 'conversation.command.v1',
    command_id: id,
    kind: 'meal.report',
    source: {
      channel: 'media',
      media_asset_id: asset,
      user_action: 'register_consumed_meal',
      ...(caption === null ? {} : { caption }),
    },
  })
  return {
    command,
    capture: {
      sourceHash: 'a'.repeat(64),
      capturedAt: '2026-11-04T01:00:00.000001Z',
      epoch,
      context: {
        schema: 'conversation.meal-source.v1',
        owner_id: owner,
        command_id: id,
        input_hash: command.inputHash,
        epoch,
        source_input: command.command,
        source_units: [
          ...(caption === null ? [] : ['media_caption']),
          kind === 'audio_note' ? 'media_transcript' : 'vision_items',
        ],
        source_evidence: { caption, transcript: kind === 'audio_note' ? 'arroz200g' : null },
        media: {
          asset_id: asset,
          kind,
          status: 'processed',
          processed_at: '2026-11-04T01:00:00Z',
          updated_at: '2026-11-04T01:00:00Z',
          context_text: null,
          processing_result: {
            text: kind === 'audio_note' ? 'arroz200g' : null,
            items: [{ name: 'arroz', quantity_g_estimate: 200, confidence: 0.9 }],
          },
        },
      },
    },
  }
}
function inUnit(
  raw: MealInterpretationModelResult,
  unit: 'media_caption' | 'media_transcript',
): MealInterpretationModelResult {
  const value = structuredClone(raw)
  at(value.sources).unit = unit
  for (const food of value.foods)
    for (const ref of [food.name, food.quantity, food.unit]) if (ref) ref.unit = unit
  return value
}
function photoResult(
  source: ReturnType<typeof buildConversationMealInterpretationSource>,
): MealInterpretationModelResult {
  return {
    schema: 'conversation.meal-interpretation.v1',
    decision: 'reported_meal',
    reason: 'explicit_media_action',
    sources: source.sources.map((s) => ({
      unit: s.unit,
      classification: s.unit === 'vision_items' ? 'visual' : 'media_pointer',
      spans:
        s.text === null ? [] : [{ start: 0, end: s.text.length, kind: 'other', food_index: null }],
      visual_indexes: s.visual_items.map((_, i) => i),
    })),
    foods: [{ index: 0, name: null, quantity: null, unit: null, visual_index: 0 }],
  }
}

function providerResult(value: unknown): LLMResult {
  return {
    content: JSON.stringify(value),
    toolCalls: [],
    promptTokens: 100,
    completionTokens: 100,
    totalTokens: 200,
    costUsd: null,
    model: 'anthropic/claude-haiku-4.5',
    finishReason: 'stop',
    latencyMs: 100,
  }
}

function modelFor(
  text: string,
  items: { name: string; quantity: string; unit: string }[],
): MealInterpretationModelResult {
  const spans: MealInterpretationModelResult['sources'][number]['spans'] = [],
    foods: MealInterpretationModelResult['foods'] = []
  let cursor = 0
  for (const [index, item] of items.entries()) {
    const start = text.indexOf(item.name, cursor),
      name = { unit: 'command_text' as const, start, end: start + item.name.length }
    if (start > cursor)
      spans.push({
        start: cursor,
        end: start,
        kind: cursor === 0 && text.slice(cursor, start).trim() ? 'report' : 'separator',
        food_index: null,
      })
    spans.push({ start: name.start, end: name.end, kind: 'food', food_index: index })
    const q = text.indexOf(item.quantity, name.end),
      quantity = { unit: 'command_text' as const, start: q, end: q + item.quantity.length }
    if (q > name.end) spans.push({ start: name.end, end: q, kind: 'separator', food_index: null })
    spans.push({ start: quantity.start, end: quantity.end, kind: 'quantity', food_index: index })
    const at = text.indexOf(item.unit, quantity.end),
      unit = { unit: 'command_text' as const, start: at, end: at + item.unit.length }
    if (at > quantity.end)
      spans.push({ start: quantity.end, end: at, kind: 'separator', food_index: null })
    spans.push({ start: unit.start, end: unit.end, kind: 'unit', food_index: index })
    foods.push({ index, name, quantity, unit, visual_index: null })
    cursor = unit.end
  }
  if (cursor < text.length)
    spans.push({ start: cursor, end: text.length, kind: 'separator', food_index: null })
  const reported = spans.some((s) => s.kind === 'report')
  return {
    schema: 'conversation.meal-interpretation.v1',
    decision: 'reported_meal',
    reason: reported ? 'explicit_report' : 'nominal_food_list',
    sources: [
      {
        unit: 'command_text',
        classification: reported ? 'reported' : 'nominal_list',
        spans,
        visual_indexes: [],
      },
    ],
    foods,
  }
}
