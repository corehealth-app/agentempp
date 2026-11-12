import { type LLMCallParams, type LLMResult, OpenRouterLLM } from '@mpp/providers'
import { AuthenticationError } from 'openai'
import { zodResponseFormat } from 'openai/helpers/zod'
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
import { prepareConversationMealSourceLabels } from './conversation-meal-source-labels'

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
  it('materializes source-bound provider labels to the unchanged canonical result', async () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      complete = vi.fn(async () => providerResult(sourceLabelsRice())),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete })
    const result = await interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 })
    expect(result).toMatchObject(
      modelFor('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }]),
    )
    expect(complete).toHaveBeenCalledTimes(1)
  })
  it('does not accept the former numeric provider format as a fallback', async () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      complete = vi.fn(async () =>
        providerResult(modelFor('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }])),
      ),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete }, vi.fn())
    await expect(
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
    ).rejects.toMatchObject({ status: 503, code: 'conversation_meal_interpretation_unavailable' })
    expect(complete).toHaveBeenCalledTimes(1)
  })
  it('uses the real provider API with explicit single-attempt, token/deadline and no tools authority', async () => {
    const text = 'arroz200g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture)
    const complete = vi.fn<(p: LLMCallParams) => Promise<LLMResult>>(async () =>
      providerResult(sourceLabelsRice()),
    )
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
      responseFormat: { type: 'json_schema', json_schema: { strict: true } },
      provider: { require_parameters: true },
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
  it('sends the dynamic source-label schema with only the three unsupported wire constraints removed', async () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      complete = vi.fn<(p: LLMCallParams) => Promise<LLMResult>>(async () =>
        providerResult(sourceLabelsRice()),
      ),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete }),
      original = zodResponseFormat(
        prepareConversationMealSourceLabels(source).schema,
        'conversation_meal_source_labels_v1',
      )
    await interpreter.interpret(source, { attemptId: epoch, remainingMs: 50000 })
    const request = at(complete.mock.calls)[0],
      format = request.responseFormat
    expect(request.requestTimeoutMs).toBe(45000)
    expect(format?.type).toBe('json_schema')
    if (format?.type !== 'json_schema') throw new Error('Expected strict schema request')
    expect(format.json_schema.name).toBe('conversation_meal_source_labels_v1')
    expect(format.json_schema.strict).toBe(true)
    expect(format.json_schema.schema?.required).toEqual([
      'schema',
      'decision',
      'reason',
      'sources',
      'foods',
    ])
    const removed: Record<string, number> = { minimum: 0, maximum: 0, maxItems: 0 }
    let objects = 0
    function compare(expected: unknown, actual: unknown): void {
      if (Array.isArray(expected)) {
        expect(Array.isArray(actual)).toBe(true)
        expect(actual).toHaveLength(expected.length)
        expected.forEach((value, i) => {
          compare(value, (actual as unknown[])[i])
        })
      } else if (expected !== null && typeof expected === 'object') {
        expect(actual).not.toBeNull()
        expect(typeof actual).toBe('object')
        const before = expected as Record<string, unknown>,
          after = actual as Record<string, unknown>
        if (before.type === 'object') {
          objects++
          expect(after.additionalProperties).toBe(false)
          expect([...(after.required as string[])].sort()).toEqual(
            Object.keys(after.properties as object).sort(),
          )
        }
        expect(Object.keys(after).sort()).toEqual(
          Object.keys(before)
            .filter((key) => !Object.hasOwn(removed, key))
            .sort(),
        )
        for (const [key, value] of Object.entries(before)) {
          if (Object.hasOwn(removed, key)) {
            removed[key] = (removed[key] ?? 0) + 1
            expect(after).not.toHaveProperty(key)
          } else compare(value, after[key])
        }
      } else expect(actual).toEqual(expected)
    }
    compare(JSON.parse(JSON.stringify(original)), format)
    expect(objects).toBeGreaterThan(0)
    for (const count of Object.values(removed)) expect(count).toBeGreaterThan(0)
    const schemaText = JSON.stringify(format)
    expect(schemaText).toContain('conversation.meal-source-labels.v1')
    expect(schemaText).toContain('labels')
    expect(schemaText).toContain('t0')
    expect(schemaText).not.toContain('part_index')
    expect(schemaText).not.toContain('"start"')
    expect(schemaText).not.toContain('"end"')
    for (const privateValue of [
      owner,
      id,
      epoch,
      source.input_hash,
      source.source_hash,
      'arroz200g',
    ])
      expect(JSON.stringify(format)).not.toContain(privateValue)
    expect(complete).toHaveBeenCalledTimes(1)
  })
  it.each([
    [
      'negative index',
      (m: MealInterpretationModelResult) => {
        at(m.foods).index = -1
      },
    ],
    [
      'index above 29',
      (m: MealInterpretationModelResult) => {
        at(m.foods).index = 30
      },
    ],
    [
      'unsafe offset',
      (m: MealInterpretationModelResult) => {
        at(at(m.sources).spans).end = Number.MAX_SAFE_INTEGER + 1
      },
    ],
    [
      'too many foods',
      (m: MealInterpretationModelResult) => {
        m.foods = Array.from({ length: 31 }, () => at(m.foods))
      },
    ],
    [
      'too many spans',
      (m: MealInterpretationModelResult) => {
        at(m.sources).spans = Array.from({ length: 4097 }, () => at(at(m.sources).spans))
      },
    ],
    [
      'extra property',
      (m: MealInterpretationModelResult) => {
        Object.assign(m, { private_output: 'sentinel' })
      },
    ],
    [
      'wrong type',
      (m: MealInterpretationModelResult) => {
        Object.assign(at(m.foods), { index: '0' })
      },
    ],
  ] as const)('retains the original backend rejection for %s despite the wire projection', (_name, mutate) => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      raw = modelFor('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }]),
      onFailure = vi.fn()
    mutate(raw)
    expect(() => validateConversationMealInterpretationModel(raw, source, onFailure)).toThrow(
      'Meal interpretation is unavailable',
    )
    expect(onFailure.mock.calls).toEqual([['model_schema']])
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
    const r = providerResult(sourceLabelsRice())
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
    const onFailure = vi.fn()
    expect(() => validateConversationMealInterpretationModel(forged, source, onFailure)).toThrow(
      'Meal interpretation is unavailable',
    )
    expect(onFailure.mock.calls).toEqual([['visual_binding']])
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
    const complete = vi.fn(async () => providerResult(sourceLabelsRice())),
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
      ...providerResult(sourceLabelsRice()),
      content: JSON.stringify(sourceLabelsRice()).replace(
        '"decision":',
        '"decision":"not_reported","decision":',
      ),
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
    finish(providerResult(sourceLabelsRice()))
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
      .mockResolvedValue(providerResult(sourceLabelsRice()))
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
  it.each([
    {
      name: 'unknown model field',
      reason: 'model_schema',
      mutate: (model: MealInterpretationModelResult) =>
        Object.assign(model, { private_output: 'secret-sentinel' }),
    },
    {
      name: 'source unit mismatch',
      reason: 'source_units',
      mutate: (model: MealInterpretationModelResult) => {
        at(model.sources).unit = 'media_caption'
      },
    },
    {
      name: 'visual classification on text',
      reason: 'source_shape',
      mutate: (model: MealInterpretationModelResult) => {
        at(model.sources).classification = 'visual'
      },
    },
    {
      name: 'partition gap',
      reason: 'span_partition',
      mutate: (model: MealInterpretationModelResult) => {
        at(at(model.sources).spans).start = 1
      },
    },
    {
      name: 'out of range end',
      reason: 'span_range',
      mutate: (model: MealInterpretationModelResult) => {
        at(at(model.sources).spans).end = 10
      },
    },
    {
      name: 'non-dense occurrence',
      reason: 'occurrence_binding',
      mutate: (model: MealInterpretationModelResult) => {
        at(model.foods).index = 1
      },
    },
    {
      name: 'reference without exact span',
      reason: 'reference_binding',
      mutate: (model: MealInterpretationModelResult) => {
        at(model.foods).name = { unit: 'command_text', start: 0, end: 4 }
      },
    },
    {
      name: 'reference splits a word',
      reason: 'token_boundary',
      mutate: (model: MealInterpretationModelResult) => {
        at(at(model.sources).spans).end = 4
        at(at(model.sources).spans, 1).start = 4
        at(model.foods).name = { unit: 'command_text', start: 0, end: 4 }
        at(model.foods).quantity = { unit: 'command_text', start: 4, end: 8 }
      },
    },
  ])('retains the direct canonical rejection reason for $name', ({ reason, mutate }) => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      model = modelFor('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }]),
      onFailure = vi.fn()
    mutate(model)
    expect(() =>
      validateConversationMealInterpretationModel(model, source, onFailure),
    ).toThrowError(
      expect.objectContaining({
        status: 503,
        code: 'conversation_meal_interpretation_unavailable',
        message: 'Meal interpretation is unavailable',
      }),
    )
    expect(onFailure.mock.calls).toEqual([[reason]])
  })
  it('reports visual binding failures without exposing the item or index', async () => {
    const f = mediaSource('meal_photo'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      model = {
        schema: 'conversation.meal-source-labels.v1',
        decision: 'reported_meal',
        reason: 'explicit_media_action',
        sources: { vision_items: { classification: 'visual', labels: {} } },
        foods: [{ index: 0, visual_index: 0 }],
      },
      sink = vi.fn()
    at(model.foods).visual_index = 1
    const interpreter = createOpenRouterConversationMealInterpreter(
      'synthetic',
      {
        complete: async () => providerResult(model),
      },
      sink,
    )
    await expect(
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
    ).rejects.toMatchObject({ status: 503 })
    expect(sink.mock.calls).toEqual([
      [
        {
          event: 'conversation_meal_interpreter_failure',
          stage: 'validation',
          error_name: 'MobileApiError',
          http_status: 503,
          validation_reason: 'visual_binding',
        },
      ],
    ])
  })
  it('classifies direct source and oversized-model failures before later checks', () => {
    const f = textSource('x'.repeat(2000)),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      model: MealInterpretationModelResult = {
        schema: 'conversation.meal-interpretation.v1',
        decision: 'clarification_required',
        reason: 'ambiguous',
        sources: [
          {
            unit: 'command_text',
            classification: 'ambiguous',
            visual_indexes: [],
            spans: Array.from({ length: 3000 }, (_, start) => ({
              start,
              end: start + 1,
              kind: 'other',
              food_index: null,
            })),
          },
        ],
        foods: [],
      },
      invalidSource = structuredClone(source),
      onFailure = vi.fn()
    at(invalidSource.sources).text = ''
    expect(() =>
      validateConversationMealInterpretationModel(model, invalidSource, onFailure),
    ).toThrow('Meal interpretation is unavailable')
    expect(interpretationModelSchema.safeParse(model).success).toBe(true)
    expect(Buffer.byteLength(JSON.stringify(model))).toBeGreaterThan(131072)
    expect(() => validateConversationMealInterpretationModel(model, source, onFailure)).toThrow(
      'Meal interpretation is unavailable',
    )
    expect(onFailure.mock.calls).toEqual([['source_contract'], ['model_envelope']])
  })
  it('isolates a throwing failure callback and classifies unexpected validator exceptions', () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      model = modelFor('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }]),
      onFailure = vi.fn(() => {
        throw new Error('private-callback-sentinel')
      }),
      normalize = vi.spyOn(String.prototype, 'normalize').mockImplementation(() => {
        throw new Error('private-internal-sentinel')
      })
    try {
      expect(() => validateConversationMealInterpretationModel(model, source, onFailure)).toThrow(
        'Meal interpretation is unavailable',
      )
      expect(onFailure.mock.calls).toEqual([['validation_internal']])
    } finally {
      normalize.mockRestore()
    }
    onFailure.mockClear()
    expect(() =>
      validateConversationMealInterpretationModel({ private_output: 'secret' }, source, onFailure),
    ).toThrow('Meal interpretation is unavailable')
    expect(onFailure.mock.calls).toEqual([['model_schema']])
  })
  it('keeps valid results and semantic downgrades unchanged without a failure callback', () => {
    for (const text of ['arroz200g', 'Sonhei que comi arroz200g']) {
      const f = textSource(text),
        source = buildConversationMealInterpretationSource(f.command, f.capture),
        model = modelFor(text, [{ name: 'arroz', quantity: '200', unit: 'g' }]),
        onFailure = vi.fn(),
        result = validateConversationMealInterpretationModel(model, source, onFailure)
      expect(result).toEqual(
        text === 'arroz200g'
          ? model
          : {
              schema: 'conversation.meal-interpretation.v1',
              decision: 'clarification_required',
              reason: 'ambiguous',
              sources: [
                {
                  unit: 'command_text',
                  classification: 'ambiguous',
                  spans: [{ start: 0, end: 25, kind: 'other', food_index: null }],
                  visual_indexes: [],
                },
              ],
              foods: [],
            },
      )
      expect(Object.isFrozen(result)).toBe(true)
      expect(onFailure).not.toHaveBeenCalled()
    }
  })
  it('keeps concurrent failure reasons local and tolerates a throwing diagnostic sink', async () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      model = sourceLabelsRice(),
      resolve: ((result: LLMResult) => void)[] = [],
      complete = vi.fn(
        () =>
          new Promise<LLMResult>((done) => {
            resolve.push(done)
          }),
      ),
      sink = vi.fn(() => {
        throw new Error('private-sink-sentinel')
      }),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete }, sink),
      calls = Promise.allSettled([
        interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
        interpreter.interpret(source, { attemptId: id, remainingMs: 1000 }),
      ])
    Object.assign(model.sources.command_text.labels.t0, { food_index: 1 })
    at(resolve, 1)(providerResult(model))
    at(resolve)(providerResult({ private_output: 'secret', validation_reason: 'untrusted-secret' }))
    const outcomes = await calls
    expect(outcomes).toEqual([
      expect.objectContaining({
        status: 'rejected',
        reason: expect.objectContaining({
          status: 503,
          code: 'conversation_meal_interpretation_unavailable',
        }),
      }),
      expect.objectContaining({
        status: 'rejected',
        reason: expect.objectContaining({
          status: 503,
          code: 'conversation_meal_interpretation_unavailable',
        }),
      }),
    ])
    expect(sink.mock.calls).toEqual(
      ['occurrence_binding', 'model_schema'].map((validation_reason) => [
        {
          event: 'conversation_meal_interpreter_failure',
          stage: 'validation',
          error_name: 'MobileApiError',
          http_status: 503,
          validation_reason,
        },
      ]),
    )
    expect(complete).toHaveBeenCalledTimes(2)
  })
  it('records only the provider stage, whitelisted SDK name and HTTP status for a secret-bearing 401', async () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      secret = 'password=diagnostic-secret-sentinel',
      failure = new AuthenticationError(401, { message: secret, code: secret }, secret, {
        authorization: secret,
        'x-request-id': secret,
      }),
      sink = vi.fn(),
      complete = vi.fn<(p: LLMCallParams) => Promise<LLMResult>>(async () => {
        throw failure
      }),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete }, sink)
    await expect(
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
    ).rejects.toMatchObject({
      status: 503,
      code: 'conversation_meal_interpretation_unavailable',
      message: 'Meal interpretation is unavailable',
    })
    expect(sink.mock.calls).toEqual([
      [
        {
          event: 'conversation_meal_interpreter_failure',
          stage: 'provider',
          error_name: 'AuthenticationError',
          http_status: 401,
        },
      ],
    ])
    expect(JSON.stringify(sink.mock.calls)).not.toContain(secret)
    expect(complete).toHaveBeenCalledTimes(1)
    expect(complete.mock.calls[0]?.[0]).toMatchObject({ maxRetries: 0 })
  })
  it.each([
    'source',
    'decode',
    'validation',
    'result',
  ] as const)('attributes failure to %s without including source or model output', async (stage) => {
    const text = 'arroz200g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      reply = providerResult(sourceLabelsRice()),
      sink = vi.fn()
    if (stage === 'decode') reply.content = '{private-model-output'
    if (stage === 'validation') reply.content = JSON.stringify({ private_model_output: text })
    if (stage === 'result') reply.costUsd = Number.POSITIVE_INFINITY
    const complete = vi.fn(async () => reply),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete }, sink)
    await expect(
      interpreter.interpret(source, {
        attemptId: epoch,
        remainingMs: stage === 'source' ? 0 : 1000,
      }),
    ).rejects.toMatchObject({ code: 'conversation_meal_interpretation_unavailable', status: 503 })
    expect(sink).toHaveBeenCalledTimes(1)
    expect(sink.mock.calls[0]?.[0]).toMatchObject({
      event: 'conversation_meal_interpreter_failure',
      stage,
    })
    for (const key of Object.keys(sink.mock.calls[0]?.[0]))
      expect([
        'error_name',
        'event',
        'http_status',
        'stage',
        ...(stage === 'validation' ? ['validation_reason'] : []),
      ]).toContain(key)
    if (stage === 'validation')
      expect(sink.mock.calls[0]?.[0].validation_reason).toBe('model_schema')
    for (const value of [
      owner,
      id,
      epoch,
      source.source_hash,
      source.input_hash,
      text,
      'private-model-output',
      'private_model_output',
    ])
      expect(JSON.stringify(sink.mock.calls)).not.toContain(value)
    expect(complete).toHaveBeenCalledTimes(stage === 'source' ? 0 : 1)
  })
  it.each([
    99,
    600,
    401.5,
    '401',
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ])('omits non-HTTP status %s and untrusted error names', async (status) => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      sink = vi.fn(),
      complete = vi.fn(async () => {
        throw {
          status,
          name: 'password=secret',
          message: 'password=secret',
          code: 'password=secret',
        }
      }),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete }, sink)
    await expect(
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
    ).rejects.toMatchObject({ status: 503 })
    expect(sink.mock.calls).toEqual([
      [
        {
          event: 'conversation_meal_interpreter_failure',
          stage: 'provider',
          error_name: 'UnknownError',
        },
      ],
    ])
  })
  it('does not evaluate error accessors or let a failing sink replace the API error', async () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      accessor = vi.fn(() => {
        throw new Error('password=accessor')
      }),
      failure = Object.defineProperties({}, { name: { get: accessor }, status: { get: accessor } }),
      sink = vi.fn(() => {
        throw new Error('password=sink')
      }),
      complete = vi.fn(async () => {
        throw failure
      }),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete }, sink)
    await expect(
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
    ).rejects.toMatchObject({
      status: 503,
      code: 'conversation_meal_interpretation_unavailable',
      message: 'Meal interpretation is unavailable',
    })
    expect(accessor).not.toHaveBeenCalled()
    expect(sink.mock.calls).toEqual([
      [
        {
          event: 'conversation_meal_interpreter_failure',
          stage: 'provider',
          error_name: 'UnknownError',
        },
      ],
    ])
    expect(complete).toHaveBeenCalledTimes(1)
  })
  it('emits a structured default diagnostic for provider setup failure', () => {
    const logged = vi.spyOn(console, 'error').mockImplementation(() => {})
    try {
      expect(() => createOpenRouterConversationMealInterpreter('')).toThrow(
        'Meal interpretation is unavailable',
      )
      expect(logged.mock.calls).toEqual([
        [
          {
            event: 'conversation_meal_interpreter_failure',
            stage: 'provider',
            error_name: 'MobileApiError',
            http_status: 503,
          },
        ],
      ])
    } finally {
      logged.mockRestore()
    }
  })
  it('leaves a normal result unchanged and emits no diagnostic', async () => {
    const text = 'arroz200g',
      f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      complete = vi.fn(async () => providerResult(sourceLabelsRice())),
      sink = vi.fn(),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete }, sink),
      result = await interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 })
    expect(result).toEqual(
      await createOpenRouterConversationMealInterpreter('synthetic', { complete }).interpret(
        source,
        { attemptId: epoch, remainingMs: 1000 },
      ),
    )
    expect(sink).not.toHaveBeenCalled()
    expect(result.decision).toBe('reported_meal')
    expect(Object.isFrozen(result)).toBe(true)
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

// Explicit provider labels; never converted from canonical numeric fixtures.
function sourceLabelsRice() {
  return {
    schema: 'conversation.meal-source-labels.v1',
    decision: 'reported_meal',
    reason: 'nominal_food_list',
    sources: {
      command_text: {
        classification: 'nominal_list',
        labels: {
          t0: { kind: 'food', food_index: 0 },
          t1: { kind: 'quantity', food_index: 0 },
          t2: { kind: 'unit', food_index: 0 },
        },
      },
    },
    foods: [{ index: 0, visual_index: null }],
  }
}

describe('source label diagnostics', () => {
  it('refuses source rewriting and missing labels without leaking submitted values', async () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      a = sourceLabelsRice(),
      b = sourceLabelsRice(),
      sink = vi.fn()
    Object.assign(a.sources.command_text, { text: 'Arroz200g' })
    Reflect.deleteProperty(b.sources.command_text.labels, 't1')
    const complete = vi
        .fn()
        .mockResolvedValueOnce(providerResult(a))
        .mockResolvedValueOnce(providerResult(b)),
      interpreter = createOpenRouterConversationMealInterpreter('synthetic', { complete }, sink)
    const results = await Promise.allSettled([
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
      interpreter.interpret(source, { attemptId: id, remainingMs: 1000 }),
    ])
    expect(results.every((r) => r.status === 'rejected')).toBe(true)
    expect(complete).toHaveBeenCalledTimes(2)
    expect(sink.mock.calls).toEqual(
      Array.from({ length: 2 }, () => [
        {
          event: 'conversation_meal_interpreter_failure',
          stage: 'validation',
          error_name: 'MobileApiError',
          http_status: 503,
          validation_reason: 'model_schema',
        },
      ]),
    )
    expect(JSON.stringify(sink.mock.calls)).not.toContain('arroz')
    expect(JSON.stringify(sink.mock.calls)).not.toContain(owner)
  })
})

describe('content-free ambiguous screening observation', () => {
  function fixture(reported: boolean) {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      wire = sourceLabelsRice()
    return {
      source,
      wire: {
        ...wire,
        decision: reported ? 'reported_meal' : 'clarification_required',
        reason: reported ? 'explicit_report' : 'ambiguous',
        sources: {
          command_text: {
            classification: reported ? 'reported' : 'ambiguous',
            labels: reported
              ? wire.sources.command_text.labels
              : {
                  t0: { kind: 'other', food_index: null },
                  t1: { kind: 'other', food_index: null },
                  t2: { kind: 'other', food_index: null },
                },
          },
        },
        foods: reported ? wire.foods : [],
      },
    }
  }
  it.each([
    false,
    true,
  ])('distinguishes provider ambiguity from conservative positive screening: %s', async (reported) => {
    const { source, wire } = fixture(reported),
      observe = vi.fn(),
      failure = vi.fn(),
      complete = vi.fn(async () => providerResult(wire)),
      interpreter = createOpenRouterConversationMealInterpreter(
        'synthetic-key',
        { complete },
        failure,
        observe,
      )
    const result = await interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 })
    expect(result.decision).toBe('clarification_required')
    expect(result.reason).toBe('ambiguous')
    expect(observe.mock.calls).toEqual([
      [
        {
          event: 'conversation_meal_interpreter_screening',
          model_decision: reported ? 'reported_meal' : 'clarification_required',
          model_reason: reported ? 'explicit_report' : 'ambiguous',
          model_food_count: reported ? 1 : 0,
          screening_reasons: reported ? ['report_count'] : [],
          result_decision: 'clarification_required',
          result_reason: 'ambiguous',
          sources: [
            {
              unit: 'command_text',
              classification: reported ? 'reported' : 'ambiguous',
              runs: {
                food: reported ? 1 : 0,
                quantity: reported ? 1 : 0,
                unit: reported ? 1 : 0,
                report: 0,
                separator: 0,
                other: reported ? 0 : 1,
              },
            },
          ],
        },
      ],
    ])
    const observation = observe.mock.calls[0]?.[0]
    expect(Object.isFrozen(observation)).toBe(true)
    expect(Object.isFrozen(observation.sources)).toBe(true)
    expect(Object.isFrozen(observation.sources[0].runs)).toBe(true)
    for (const secret of [
      'arroz',
      owner,
      id,
      epoch,
      source.input_hash,
      source.source_hash,
      'synthetic-key',
    ])
      expect(JSON.stringify(observation)).not.toContain(secret)
    expect(failure).not.toHaveBeenCalled()
    expect(complete).toHaveBeenCalledTimes(1)
  })
  it('does not observe an accepted positive or expose malformed provider content', async () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      observe = vi.fn(),
      failure = vi.fn(),
      complete = vi
        .fn()
        .mockResolvedValueOnce(providerResult(sourceLabelsRice()))
        .mockResolvedValueOnce(providerResult({ private_output: 'secret' })),
      interpreter = createOpenRouterConversationMealInterpreter(
        'synthetic-key',
        { complete },
        failure,
        observe,
      )
    expect(
      (await interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 })).decision,
    ).toBe('reported_meal')
    await expect(
      interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
    ).rejects.toMatchObject({ code: 'conversation_meal_interpretation_unavailable' })
    expect(observe).not.toHaveBeenCalled()
    expect(JSON.stringify(failure.mock.calls)).not.toContain('secret')
    expect(complete).toHaveBeenCalledTimes(2)
  })
  it('preserves the canonical refusal and single attempt when observation throws', async () => {
    const { source, wire } = fixture(true),
      packet = prepareConversationMealSourceLabels(source),
      expected = validateConversationMealInterpretationModel(packet.materialize(wire), source),
      observe = vi.fn(() => {
        throw new Error('observer-secret')
      }),
      failure = vi.fn(),
      complete = vi.fn(async () => providerResult(wire)),
      interpreter = createOpenRouterConversationMealInterpreter(
        'synthetic-key',
        { complete },
        failure,
        observe,
      )
    expect(
      await interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 }),
    ).toMatchObject(expected)
    expect(observe).toHaveBeenCalledTimes(1)
    expect(failure).not.toHaveBeenCalled()
    expect(complete).toHaveBeenCalledTimes(1)
  })
})

describe('whole-source current meal context after reported foods', () => {
  function suffix(text: string, tailKind: 'other' | 'report' | 'separator' = 'other') {
    const raw = modelFor(text, [{ name: 'iogurte natural', quantity: '200', unit: 'g' }])
    const spans = at(raw.sources).spans
    at(spans, spans.length - 1).kind = tailKind
    const f = textSource(text)
    return { raw, source: buildConversationMealInterpretationSource(f.command, f.capture) }
  }
  it.each([
    'no café da manhã.',
    'no almoço',
    'no jantar de hoje.',
    'no lanche!',
    'na ceia',
    ', no café da manhã de hoje.',
  ])('preserves the explicit current meal suffix %s without changing food evidence', (context) => {
    const f = suffix('Comi iogurte natural200g ' + context)
    const result = validateConversationMealInterpretationModel(f.raw, f.source)
    expect(result).toEqual(f.raw)
    expect(result.foods[0]?.name).toEqual(f.raw.foods[0]?.name)
  })
  it.each([
    'other',
    'report',
    'separator',
  ] as const)('accounts for a trailing meal context labeled %s with one genuine leading report', (kind) => {
    const f = suffix('Comi iogurte natural200g no café da manhã.', kind)
    expect(validateConversationMealInterpretationModel(f.raw, f.source).decision).toBe(
      'reported_meal',
    )
  })
  it('keeps the missing quantity missing in the observed unquantified report', () => {
    const text = 'Comi iogurte natural no café da manhã.',
      f = textSource(text),
      start = text.indexOf('iogurte natural'),
      end = start + 'iogurte natural'.length,
      raw: MealInterpretationModelResult = {
        schema: 'conversation.meal-interpretation.v1',
        decision: 'reported_meal',
        reason: 'explicit_report',
        sources: [
          {
            unit: 'command_text',
            classification: 'reported',
            visual_indexes: [],
            spans: [
              { start: 0, end: start, kind: 'report', food_index: null },
              { start, end, kind: 'food', food_index: 0 },
              { start: end, end: text.length, kind: 'other', food_index: null },
            ],
          },
        ],
        foods: [
          {
            index: 0,
            name: { unit: 'command_text', start, end },
            quantity: null,
            unit: null,
            visual_index: null,
          },
        ],
      }
    expect(
      validateConversationMealInterpretationModel(
        raw,
        buildConversationMealInterpretationSource(f.command, f.capture),
      ),
    ).toEqual(raw)
  })
  it.each([
    'no sonho',
    'no café da manhã de amanhã',
    'no café da manhã de ontem',
    'mas não no café da manhã',
    'se fosse no café da manhã',
    'no café da manhã?',
    'no café da manhã mas não comi',
    'no café da manhã da minha filha',
    '"no café da manhã"',
  ])('refuses unaccounted or non-current context %s', (context) => {
    const f = suffix('Comi iogurte natural200g ' + context)
    expect(validateConversationMealInterpretationModel(f.raw, f.source).decision).toBe(
      'clarification_required',
    )
  })
  it.each([
    'Sonhei que comi',
    'Não comi',
    'Vou comer',
    'Costumo comer',
    'Minha filha comeu',
  ])('a current meal suffix never establishes consumption for %s', (prefix) => {
    const f = suffix(prefix + ' iogurte natural200g no café da manhã.')
    expect(validateConversationMealInterpretationModel(f.raw, f.source).decision).toBe(
      'clarification_required',
    )
  })
  it('does not upgrade a model refusal or silently accept hidden unknown words', () => {
    const f = suffix('Comi iogurte natural200g no café da manhã.')
    f.raw.decision = 'clarification_required'
    f.raw.reason = 'ambiguous'
    expect(validateConversationMealInterpretationModel(f.raw, f.source).decision).toBe(
      'clarification_required',
    )
    const unknown = suffix('Comi iogurte natural200g talvez no café da manhã.')
    expect(validateConversationMealInterpretationModel(unknown.raw, unknown.source).decision).toBe(
      'clarification_required',
    )
  })
  it('cannot substitute a trailing meal context for an actual reporting predicate', () => {
    const f = suffix('iogurte natural200g no café da manhã.')
    at(f.raw.sources).classification = 'reported'
    f.raw.reason = 'explicit_report'
    expect(validateConversationMealInterpretationModel(f.raw, f.source).decision).toBe(
      'clarification_required',
    )
  })
})

describe('closed conservative screening reasons', () => {
  it.each([
    ['quero200g', 'quero', '200', 'g', 'food_name'],
    ['arroz0g', 'arroz', '0', 'g', 'quantity'],
    ['arroz200zz', 'arroz', '200', 'zz', 'unit'],
    ['Sonhei que consumi arroz200g', 'arroz', '200', 'g', 'report_prefix'],
  ])('reports the existing rejection of %s without changing the refusal', (text, name, amount, unit, reason) => {
    const f = textSource(text),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      raw = modelFor(text, [{ name, quantity: amount, unit }]),
      observe = vi.fn(),
      failure = vi.fn(),
      old = validateConversationMealInterpretationModel(raw, source),
      result = validateConversationMealInterpretationModel(raw, source, failure, observe)
    expect(result).toEqual(old)
    expect(result.decision).toBe('clarification_required')
    expect(observe.mock.calls).toEqual([[[reason]]])
    expect(Object.isFrozen(observe.mock.calls[0]?.[0])).toBe(true)
    expect(failure).not.toHaveBeenCalled()
  })
  it('does not expose screening observations on accepted or malformed evidence', () => {
    const f = textSource('arroz200g'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      raw = modelFor('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }]),
      observe = vi.fn(),
      failure = vi.fn()
    expect(
      validateConversationMealInterpretationModel(raw, source, failure, observe).decision,
    ).toBe('reported_meal')
    expect(() =>
      validateConversationMealInterpretationModel(
        { secret: 'never-log' },
        source,
        failure,
        observe,
      ),
    ).toThrow()
    expect(observe).not.toHaveBeenCalled()
  })
  it('cannot change a refusal when the reason observer throws', () => {
    const f = textSource('arroz200zz'),
      source = buildConversationMealInterpretationSource(f.command, f.capture),
      raw = modelFor('arroz200zz', [{ name: 'arroz', quantity: '200', unit: 'zz' }]),
      observe = vi.fn(() => {
        throw new Error('observer-secret')
      })
    expect(validateConversationMealInterpretationModel(raw, source, undefined, observe)).toEqual(
      validateConversationMealInterpretationModel(raw, source),
    )
    expect(observe).toHaveBeenCalledTimes(1)
  })
  it('serializes only the generated safe projection so nested counts survive runtime logs', async () => {
    const emit = vi.spyOn(console, 'info').mockImplementation(() => undefined)
    try {
      const f = textSource('arroz200g'),
        source = buildConversationMealInterpretationSource(f.command, f.capture),
        wire = sourceLabelsRice()
      wire.reason = 'explicit_report'
      wire.sources.command_text.classification = 'reported'
      const interpreter = createOpenRouterConversationMealInterpreter('synthetic-key', {
        complete: async () => providerResult(wire),
      })
      expect(
        (await interpreter.interpret(source, { attemptId: epoch, remainingMs: 1000 })).decision,
      ).toBe('clarification_required')
      expect(emit).toHaveBeenCalledTimes(1)
      const text = emit.mock.calls[0]?.[0]
      expect(typeof text).toBe('string')
      const value = JSON.parse(text)
      expect(value.screening_reasons).toEqual(['report_count'])
      expect(value.sources[0].runs).toEqual({
        food: 1,
        quantity: 1,
        unit: 1,
        report: 0,
        separator: 0,
        other: 0,
      })
      for (const secret of [
        'arroz',
        owner,
        id,
        epoch,
        source.input_hash,
        source.source_hash,
        'synthetic-key',
      ])
        expect(text).not.toContain(secret)
    } finally {
      emit.mockRestore()
    }
  })
})
