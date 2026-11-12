import { zodResponseFormat } from 'openai/helpers/zod'
import { describe, expect, it, vi } from 'vitest'
import type { ConversationMealInterpretationSource } from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import * as api from './conversation-meal-source-labels'

const id = '10000000-0000-4000-8000-000000000001'
function source(text: string): ConversationMealInterpretationSource {
  return {
    schema: 'conversation.meal-interpretation-source.v1',
    interpreter_version: 'conversation.meal-interpreter.v1',
    owner_id: id,
    command_id: id,
    input_hash: 'a'.repeat(64),
    source_hash: 'b'.repeat(64),
    epoch: id,
    captured_at: '2026-11-11T00:00:00Z',
    media_binding: null,
    source_units: ['command_text'],
    sources: [{ unit: 'command_text', text, visual_items: [] }],
  }
}
type Role = 'food' | 'quantity' | 'unit' | 'report' | 'separator' | 'other'
const label = (kind: Role, food_index: number | null = null) => ({ kind, food_index })
function rice() {
  return {
    schema: 'conversation.meal-source-labels.v1',
    decision: 'reported_meal',
    reason: 'nominal_food_list',
    sources: {
      command_text: {
        classification: 'nominal_list',
        labels: { t0: label('food', 0), t1: label('quantity', 0), t2: label('unit', 0) },
      },
    },
    foods: [{ index: 0, visual_index: null }],
  }
}

function implementation() {
  return api
}
describe('source-preserving semantic labels', () => {
  it('requires every owned source and token key in a closed schema without private identity or original words', () => {
    const packet = api.prepareConversationMealSourceLabels(source('arroz200g')),
      format = zodResponseFormat(packet.schema, 'conversation_meal_source_labels_v1'),
      schema = format.json_schema.schema as Record<string, unknown>,
      walk = (v: unknown) => {
        if (Array.isArray(v)) {
          v.forEach(walk)
          return
        }
        if (!v || typeof v !== 'object') return
        const obj = v as Record<string, unknown>
        if (obj.type === 'object') {
          expect(obj.additionalProperties).toBe(false)
          expect([...(obj.required as string[])].sort()).toEqual(
            Object.keys(obj.properties as object).sort(),
          )
        }
        Object.values(obj).forEach(walk)
      }
    walk(schema)
    const serialized = JSON.stringify(schema)
    for (const forbidden of [
      id,
      'a'.repeat(64),
      'arroz',
      '200g',
      '"start"',
      '"end"',
      '"text"',
      'part_index',
    ])
      expect(serialized).not.toContain(forbidden)
    expect(serialized).toContain('"t0"')
    expect(serialized).toContain('"t2"')
    expect(JSON.stringify(packet.input)).not.toContain(id)
  })
  it('binds a source copy before a mutable caller changes its text', () => {
    const original = source('arroz200g'),
      packet = api.prepareConversationMealSourceLabels(original)
    const input = original.sources[0]
    if (!input) throw new Error('Missing source')
    input.text = 'Não comi arroz200g'
    expect(packet.input.sources[0]?.text).toBe('arroz200g')
    expect(packet.materialize(rice()).foods[0]?.name?.end).toBe(5)
    expect(Object.isFrozen(packet.input.sources[0]?.tokens)).toBe(true)
  })
  it('retains maximum-length text and every punctuation token without truncating the approved source contract', () => {
    const text = '!'.repeat(2000),
      packet = api.prepareConversationMealSourceLabels(source(text))
    expect(packet.input.sources[0]?.text).toBe(text)
    expect(packet.input.sources[0]?.tokens).toHaveLength(2000)
    const wire = {
      ...rice(),
      decision: 'not_reported',
      reason: 'ambiguous',
      foods: [],
      sources: {
        command_text: {
          classification: 'ambiguous',
          labels: Object.fromEntries(
            (packet.input.sources[0]?.tokens ?? []).map(([key]) => [key, label('other')]),
          ),
        },
      },
    }
    expect(packet.materialize(wire).sources[0]?.spans).toEqual([
      { start: 0, end: 2000, kind: 'other', food_index: null },
    ])
    expect(() => api.prepareConversationMealSourceLabels(source(`${text}!`))).toThrow()
  })
  it('binds caption/transcript separately and never interprets label keys from another unit', () => {
    const input = source('unused')
    input.media_binding = {
      asset_id: id,
      kind: 'audio_note',
      processed_at: '2026-11-11T00:00:00Z',
      updated_at: '2026-11-11T00:00:00Z',
      processing_hash: 'c'.repeat(64),
    }
    input.source_units = ['media_caption', 'media_transcript']
    input.sources = [
      { unit: 'media_caption', text: 'Não comi', visual_items: [] },
      { unit: 'media_transcript', text: 'arroz200g', visual_items: [] },
    ]
    const packet = api.prepareConversationMealSourceLabels(input),
      wire = {
        ...rice(),
        reason: 'explicit_media_action',
        sources: {
          media_caption: {
            classification: 'negated',
            labels: { t0: label('other'), t1: label('other') },
          },
          media_transcript: rice().sources.command_text,
        },
      }
    expect(
      validateConversationMealInterpretationModel(packet.materialize(wire), input).decision,
    ).toBe('clarification_required')
    Reflect.deleteProperty(wire.sources, 'media_caption')
    expect(() => packet.materialize(wire)).toThrow()
  })
  it('derives exact visual indexes from owned evidence and still refuses a fabricated food index', () => {
    const input = source('unused')
    input.media_binding = {
      asset_id: id,
      kind: 'meal_photo',
      processed_at: '2026-11-11T00:00:00Z',
      updated_at: '2026-11-11T00:00:00Z',
      processing_hash: 'c'.repeat(64),
    }
    input.source_units = ['media_caption', 'vision_items']
    input.sources = [
      { unit: 'media_caption', text: 'Meu almoço', visual_items: [] },
      { unit: 'vision_items', text: null, visual_items: [{ name: 'arroz' }] },
    ]
    const packet = api.prepareConversationMealSourceLabels(input),
      wire = {
        ...rice(),
        reason: 'explicit_media_action',
        sources: {
          media_caption: {
            classification: 'media_pointer',
            labels: { t0: label('other'), t1: label('other') },
          },
          vision_items: { classification: 'visual', labels: {} },
        },
        foods: [{ index: 0, visual_index: 0 }],
      }
    const result = validateConversationMealInterpretationModel(packet.materialize(wire), input)
    expect(result.decision).toBe('reported_meal')
    expect(result.sources[1]).toEqual({
      unit: 'vision_items',
      classification: 'visual',
      spans: [],
      visual_indexes: [0],
    })
    Object.assign(wire.foods[0] ?? {}, { visual_index: 1 })
    expect(() =>
      validateConversationMealInterpretationModel(packet.materialize(wire), input),
    ).toThrow()
    Object.assign(wire.sources.vision_items.labels, { t0: label('food', 0) })
    expect(() => packet.materialize(wire)).toThrow()
  })
  it('reports only closed failure categories and isolates a throwing observer', () => {
    const packet = api.prepareConversationMealSourceLabels(source('arroz200g')),
      failure = vi.fn(() => {
        throw new Error('private-observer')
      })
    expect(() => packet.materialize({ private_output: 'secret' }, failure)).toThrow(
      'Meal interpretation is unavailable',
    )
    expect(failure.mock.calls).toEqual([['model_schema']])
  })
  it.each([
    ['negative index', { index: -1, visual_index: null }],
    ['fractional index', { index: 0.5, visual_index: null }],
    ['unsafe index', { index: Number.MAX_SAFE_INTEGER + 1, visual_index: null }],
    ['string index', { index: '0', visual_index: null }],
    ['nonfinite index', { index: Number.POSITIVE_INFINITY, visual_index: null }],
    [
      'invented reference',
      { index: 0, visual_index: null, name: { unit: 'command_text', start: 0, end: 5 } },
    ],
  ])('rejects provider food metadata: %s', (_name, food) => {
    const packet = api.prepareConversationMealSourceLabels(source('arroz200g'))
    expect(() => packet.materialize({ ...rice(), foods: [food] })).toThrow()
  })
  it('retains backend bounds even when strict wire projection omits numeric limits', () => {
    const packet = api.prepareConversationMealSourceLabels(source('arroz200g')),
      wire = rice()
    expect(() =>
      packet.materialize({ ...wire, foods: Array.from({ length: 31 }, () => wire.foods[0]) }),
    ).toThrow()
    Object.assign(wire.sources.command_text.labels.t0, { food_index: 30 })
    expect(() => packet.materialize(wire)).toThrow()
  })
  it('refuses non-dense and out-of-order occurrence assignments at the canonical boundary', () => {
    const input = source('arroz200g'),
      packet = api.prepareConversationMealSourceLabels(input),
      wire = rice()
    Object.assign(wire.foods[0] ?? {}, { index: 1 })
    expect(() =>
      validateConversationMealInterpretationModel(packet.materialize(wire), input),
    ).toThrow()
    Object.assign(wire.foods[0] ?? {}, { index: 0 })
    wire.sources.command_text.labels.t0.food_index = 1
    expect(() => packet.materialize(wire)).toThrow()
  })
  it.each([
    ['Sonhei que comi ', 3],
    ['Vou comer ', 2],
    ['Costumo comer ', 2],
    ['Não comi ', 2],
    ['Ela comeu ', 2],
  ] as const)('does not authorize a false reporting prefix even with valid food references: %s', (prefix, count) => {
    const input = source(`${prefix}arroz200g`),
      packet = api.prepareConversationMealSourceLabels(input),
      labels = Object.fromEntries(
        Array.from({ length: count }, (_, i) => [`t${i}`, label('report')]),
      )
    Object.assign(labels, {
      [`t${count}`]: label('food', 0),
      [`t${count + 1}`]: label('quantity', 0),
      [`t${count + 2}`]: label('unit', 0),
    })
    const wire = {
      ...rice(),
      reason: 'explicit_report',
      sources: { command_text: { classification: 'reported', labels } },
    }
    expect(
      validateConversationMealInterpretationModel(packet.materialize(wire), input).decision,
    ).toBe('clarification_required')
  })
  it.each([
    'not_reported',
    'clarification_required',
  ] as const)('preserves a valid %s refusal', (decision) => {
    const input = source('Não comi'),
      packet = api.prepareConversationMealSourceLabels(input)
    const wire = {
      ...rice(),
      decision,
      reason: 'negated',
      foods: [],
      sources: {
        command_text: {
          classification: 'negated',
          labels: { t0: label('other'), t1: label('other') },
        },
      },
    }
    expect(
      validateConversationMealInterpretationModel(packet.materialize(wire), input),
    ).toMatchObject({ decision, reason: 'negated', foods: [] })
  })
  it('keeps literal and numeric former provider formats out of the new transport', () => {
    const packet = api.prepareConversationMealSourceLabels(source('arroz200g'))
    for (const schema of [
      'conversation.meal-literal-partition.v1',
      'conversation.meal-interpretation.v1',
    ])
      expect(() => packet.materialize({ ...rice(), schema })).toThrow()
  })
  it('lexes without changing characters, offsets, combining marks or astral codepoints', () => {
    const { tokenizeConversationMealSource } = implementation()
    const text = 'arroz200g; cafe\u0301 1,5mL 🥛 d’água pão-de-queijo\r\n',
      tokens = tokenizeConversationMealSource(text)
    expect(tokens.map((t) => t.text).join('')).toBe(text)
    expect(tokens.filter((t) => t.key !== null).map((t) => t.text)).toEqual([
      'arroz',
      '200',
      'g',
      ';',
      'cafe\u0301',
      '1,5',
      'mL',
      '🥛',
      'd’água',
      'pão-de-queijo',
    ])
    let cursor = 0
    for (const token of tokens) {
      expect(token.start).toBe(cursor)
      expect(text.slice(token.start, token.end)).toBe(token.text)
      cursor = token.end
    }
    expect(cursor).toBe(text.length)
    expect(tokens.filter((t) => t.key !== null).map((t) => t.key)).toEqual(
      Array.from({ length: 10 }, (_, i) => `t${i}`),
    )
  })
  it('materializes exact canonical references without model text or offsets', () => {
    const { prepareConversationMealSourceLabels } = implementation(),
      packet = prepareConversationMealSourceLabels(source('arroz200g')),
      result = packet.materialize(rice())
    expect(result).toEqual({
      schema: 'conversation.meal-interpretation.v1',
      decision: 'reported_meal',
      reason: 'nominal_food_list',
      sources: [
        {
          unit: 'command_text',
          classification: 'nominal_list',
          visual_indexes: [],
          spans: [
            { start: 0, end: 5, kind: 'food', food_index: 0 },
            { start: 5, end: 8, kind: 'quantity', food_index: 0 },
            { start: 8, end: 9, kind: 'unit', food_index: 0 },
          ],
        },
      ],
      foods: [
        {
          index: 0,
          name: { unit: 'command_text', start: 0, end: 5 },
          quantity: { unit: 'command_text', start: 5, end: 8 },
          unit: { unit: 'command_text', start: 8, end: 9 },
          visual_index: null,
        },
      ],
    })
    expect(validateConversationMealInterpretationModel(result, source('arroz200g')).decision).toBe(
      'reported_meal',
    )
    expect(Object.isFrozen(result.foods)).toBe(true)
  })
  it('keeps the complete original breakfast report and milk/whey literal inside canonical spans', () => {
    const { prepareConversationMealSourceLabels } = implementation(),
      text = 'No café da manhã, consumi 200 mL de leite com 1 medida de whey.',
      input = source(text),
      packet = prepareConversationMealSourceLabels(input)
    expect(packet.input.sources[0]?.tokens).toEqual([
      ['t0', 'No'],
      ['t1', 'café'],
      ['t2', 'da'],
      ['t3', 'manhã'],
      ['t4', ','],
      ['t5', 'consumi'],
      ['t6', '200'],
      ['t7', 'mL'],
      ['t8', 'de'],
      ['t9', 'leite'],
      ['t10', 'com'],
      ['t11', '1'],
      ['t12', 'medida'],
      ['t13', 'de'],
      ['t14', 'whey'],
      ['t15', '.'],
    ])
    const wire = {
      ...rice(),
      reason: 'explicit_report',
      sources: {
        command_text: {
          classification: 'reported',
          labels: {
            t0: label('report'),
            t1: label('report'),
            t2: label('report'),
            t3: label('report'),
            t4: label('report'),
            t5: label('report'),
            t6: label('quantity', 0),
            t7: label('unit', 0),
            t8: label('separator'),
            t9: label('food', 0),
            t10: label('food', 0),
            t11: label('food', 0),
            t12: label('food', 0),
            t13: label('food', 0),
            t14: label('food', 0),
            t15: label('separator'),
          },
        },
      },
    }
    const result = validateConversationMealInterpretationModel(packet.materialize(wire), input),
      food = result.foods[0]
    expect(result.decision).toBe('reported_meal')
    expect(food?.name).toEqual({ unit: 'command_text', start: 36, end: 62 })
    expect(result.sources[0]?.spans.map((s) => text.slice(s.start, s.end)).join('')).toBe(text)
    expect(food?.quantity && text.slice(food.quantity.start, food.quantity.end)).toBe('200')
    expect(food?.unit && text.slice(food.unit.start, food.unit.end)).toBe('mL')
  })
  it.each([
    'missing token',
    'extra token',
    'source text',
    'model offset',
    'extra source',
    'wrong role',
    'wrong owner',
  ])('rejects a forged or incomplete model envelope: %s', (caseName) => {
    const { prepareConversationMealSourceLabels } = implementation(),
      packet = prepareConversationMealSourceLabels(source('arroz200g')),
      wire = rice()
    if (caseName === 'missing token') Reflect.deleteProperty(wire.sources.command_text.labels, 't1')
    if (caseName === 'extra token')
      Object.assign(wire.sources.command_text.labels, { t3: label('other') })
    if (caseName === 'source text') Object.assign(wire.sources.command_text, { text: 'arroz200g' })
    if (caseName === 'model offset') Object.assign(wire.foods[0] ?? {}, { start: 1 })
    if (caseName === 'extra source')
      Object.assign(wire.sources, { media_transcript: wire.sources.command_text })
    if (caseName === 'wrong role')
      Object.assign(wire.sources.command_text.labels.t0, { kind: 'consumed' })
    if (caseName === 'wrong owner') Object.assign(wire, { owner_id: id })
    expect(() => packet.materialize(wire)).toThrow()
  })
  it('does not choose one of two disjoint name runs for an occurrence', () => {
    const { prepareConversationMealSourceLabels } = implementation(),
      packet = prepareConversationMealSourceLabels(source('arroz e feijão')),
      wire = {
        ...rice(),
        sources: {
          command_text: {
            classification: 'nominal_list',
            labels: {
              t0: label('food', 0),
              t1: label('separator'),
              t2: label('food', 0),
            },
          },
        },
      }
    expect(() => packet.materialize(wire)).toThrow()
  })
  it('derives references from occurrences, preserving repeated identical foods', () => {
    const { prepareConversationMealSourceLabels } = implementation(),
      input = source('arroz200g; arroz100g'),
      packet = prepareConversationMealSourceLabels(input),
      wire = {
        ...rice(),
        sources: {
          command_text: {
            classification: 'nominal_list',
            labels: {
              t0: label('food', 0),
              t1: label('quantity', 0),
              t2: label('unit', 0),
              t3: label('separator'),
              t4: label('food', 1),
              t5: label('quantity', 1),
              t6: label('unit', 1),
            },
          },
        },
        foods: [
          { index: 0, visual_index: null },
          { index: 1, visual_index: null },
        ],
      }
    const result = validateConversationMealInterpretationModel(packet.materialize(wire), input)
    expect(result.foods.map((f) => f.name?.start)).toEqual([0, 11])
    expect(result.foods.map((f) => f.quantity?.start)).toEqual([5, 16])
  })
  it.each([
    'Não comi arroz200g',
    'Vou comer arroz200g',
    'Sonhei que comi arroz200g',
    'Minha filha comeu arroz200g',
    'Posso comer arroz200g?',
    'Comi arroz200g mas não feijão100g',
  ])('does not upgrade a positive assertion over complete discourse: %s', (text) => {
    const { prepareConversationMealSourceLabels } = implementation(),
      input = source(text),
      packet = prepareConversationMealSourceLabels(input)
    const labels = Object.fromEntries(
      (packet.input.sources[0]?.tokens ?? []).map(([key]) => [key, label('other')]),
    )
    const wire = {
      ...rice(),
      decision: 'reported_meal',
      reason: 'explicit_report',
      sources: { command_text: { classification: 'reported', labels } },
      foods: [],
    }
    const result = validateConversationMealInterpretationModel(packet.materialize(wire), input)
    expect(result.decision).toBe('clarification_required')
    expect(result.sources[0]?.spans.map((s) => text.slice(s.start, s.end)).join('')).toBe(text)
  })
})
