import { describe, expect, it, vi } from 'vitest'
import type { z } from 'zod'
import type { ConversationMealInterpretationSource } from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import {
  materializeConversationMealLiteralPartition,
  type mealLiteralPartitionSchema,
} from './conversation-meal-literal-partition'

type Wire = z.infer<typeof mealLiteralPartitionSchema>
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
    captured_at: '2026-11-06T00:00:00Z',
    media_binding: null,
    source_units: ['command_text'],
    sources: [{ unit: 'command_text', text, visual_items: [] }],
  }
}
function rice(): Wire {
  return {
    schema: 'conversation.meal-literal-partition.v1',
    decision: 'reported_meal',
    reason: 'nominal_food_list',
    sources: [
      {
        unit: 'command_text',
        classification: 'nominal_list',
        visual_indexes: [],
        parts: [
          { text: 'arroz', kind: 'food', food_index: 0 },
          { text: '200', kind: 'quantity', food_index: 0 },
          { text: 'g', kind: 'unit', food_index: 0 },
        ],
      },
    ],
    foods: [
      {
        index: 0,
        name: { unit: 'command_text', part_index: 0 },
        quantity: { unit: 'command_text', part_index: 1 },
        unit: { unit: 'command_text', part_index: 2 },
        visual_index: null,
      },
    ],
  }
}
function first<T>(values: T[]): T {
  const item = values[0]
  if (item === undefined) throw new Error('Missing fixture')
  return item
}
function validated(raw: unknown, input: ConversationMealInterpretationSource, onFailure = vi.fn()) {
  const canonical = materializeConversationMealLiteralPartition(raw, input, onFailure)
  return validateConversationMealInterpretationModel(canonical, input, onFailure)
}
function media() {
  const input = source('unused')
  input.media_binding = {
    asset_id: id,
    kind: 'meal_photo',
    processed_at: '2026-11-06T00:00:00Z',
    updated_at: '2026-11-06T00:00:00Z',
    processing_hash: 'c'.repeat(64),
  }
  input.source_units = ['media_caption', 'vision_items']
  input.sources = [
    { unit: 'media_caption', text: 'Meu almoço', visual_items: [] },
    { unit: 'vision_items', text: null, visual_items: [{ name: 'arroz' }] },
  ]
  const wire: Wire = {
    schema: 'conversation.meal-literal-partition.v1',
    decision: 'reported_meal',
    reason: 'explicit_media_action',
    sources: [
      {
        unit: 'media_caption',
        classification: 'media_pointer',
        visual_indexes: [],
        parts: [{ text: 'Meu almoço', kind: 'other', food_index: null }],
      },
      { unit: 'vision_items', classification: 'visual', visual_indexes: [0], parts: [] },
    ],
    foods: [{ index: 0, name: null, quantity: null, unit: null, visual_index: 0 }],
  }
  return { input, wire }
}
describe('literal partitions preserve the canonical proof boundary', () => {
  it('materializes the supported milk/whey report with hand-checked UTF16 positions', () => {
    const input = source('Consumi 200 mL de leite com 1 medida de whey.'),
      wire = rice()
    wire.decision = 'reported_meal'
    wire.reason = 'explicit_report'
    first(wire.sources).classification = 'reported'
    first(wire.sources).parts = [
      { text: 'Consumi ', kind: 'report', food_index: null },
      { text: '200', kind: 'quantity', food_index: 0 },
      { text: ' ', kind: 'separator', food_index: null },
      { text: 'mL', kind: 'unit', food_index: 0 },
      { text: ' de ', kind: 'separator', food_index: null },
      { text: 'leite com 1 medida de whey', kind: 'food', food_index: 0 },
      { text: '.', kind: 'separator', food_index: null },
    ]
    first(wire.foods).name = { unit: 'command_text', part_index: 5 }
    first(wire.foods).quantity = { unit: 'command_text', part_index: 1 }
    first(wire.foods).unit = { unit: 'command_text', part_index: 3 }
    const result = validated(wire, input)
    expect(result.decision).toBe('reported_meal')
    expect(result.sources).toEqual([
      {
        unit: 'command_text',
        classification: 'reported',
        visual_indexes: [],
        spans: [
          { start: 0, end: 8, kind: 'report', food_index: null },
          { start: 8, end: 11, kind: 'quantity', food_index: 0 },
          { start: 11, end: 12, kind: 'separator', food_index: null },
          { start: 12, end: 14, kind: 'unit', food_index: 0 },
          { start: 14, end: 18, kind: 'separator', food_index: null },
          { start: 18, end: 44, kind: 'food', food_index: 0 },
          { start: 44, end: 45, kind: 'separator', food_index: null },
        ],
      },
    ])
    expect(result.foods).toEqual([
      {
        index: 0,
        name: { unit: 'command_text', start: 18, end: 44 },
        quantity: { unit: 'command_text', start: 8, end: 11 },
        unit: { unit: 'command_text', start: 12, end: 14 },
        visual_index: null,
      },
    ])
    expect(Object.isFrozen(result)).toBe(true)
    expect(input.sources[0]?.text).toBe('Consumi 200 mL de leite com 1 medida de whey.')
    expect(wire.schema).toBe('conversation.meal-literal-partition.v1')
    // A separate report-context correction now accepts this exact prefix.
    // The literal adapter still only preserves text/positions; canonical
    // validation independently establishes the supported consumption grammar.
    first(wire.sources).parts[0] = {
      text: 'No café da manhã, consumi ',
      kind: 'report',
      food_index: null,
    }
    expect(
      validated(wire, source('No café da manhã, consumi 200 mL de leite com 1 medida de whey.'))
        .decision,
    ).toBe('reported_meal')
  })
  it('counts original UTF16, retaining astral and combining characters exactly', () => {
    const wire = rice()
    wire.decision = 'clarification_required'
    wire.reason = 'ambiguous'
    wire.foods = []
    first(wire.sources).classification = 'ambiguous'
    first(wire.sources).parts = [
      { text: '😀', kind: 'other', food_index: null },
      { text: 'feija\u0303o', kind: 'other', food_index: null },
    ]
    expect(validated(wire, source('😀feija\u0303o')).sources[0]?.spans).toEqual([
      { start: 0, end: 2, kind: 'other', food_index: null },
      { start: 2, end: 9, kind: 'other', food_index: null },
    ])
    first(wire.sources).parts = [
      { text: '\ud83d', kind: 'other', food_index: null },
      { text: '\ude00feija\u0303o', kind: 'other', food_index: null },
    ]
    const failure = vi.fn()
    expect(() => validated(wire, source('😀feija\u0303o'), failure)).toThrow(
      'Meal interpretation is unavailable',
    )
    expect(failure.mock.calls).toEqual([['span_range']])
  })
  it('binds repeated occurrences by local index, never by searching identical text', () => {
    const wire = rice()
    first(wire.sources).parts.push(
      { text: '; ', kind: 'separator', food_index: null },
      { text: 'arroz', kind: 'food', food_index: 1 },
      { text: '100', kind: 'quantity', food_index: 1 },
      { text: 'g', kind: 'unit', food_index: 1 },
    )
    wire.foods.push({
      index: 1,
      name: { unit: 'command_text', part_index: 4 },
      quantity: { unit: 'command_text', part_index: 5 },
      unit: { unit: 'command_text', part_index: 6 },
      visual_index: null,
    })
    const input = source('arroz200g; arroz100g'),
      result = validated(wire, input)
    expect(result.foods[1]).toEqual({
      index: 1,
      name: { unit: 'command_text', start: 11, end: 16 },
      quantity: { unit: 'command_text', start: 16, end: 19 },
      unit: { unit: 'command_text', start: 19, end: 20 },
      visual_index: null,
    })
    first(wire.foods).quantity = { unit: 'command_text', part_index: 5 }
    expect(() => validated(wire, input)).toThrow('Meal interpretation is unavailable')
  })
  it.each([
    [
      'omitted literal',
      'span_partition',
      (w: Wire) => {
        first(w.sources).parts.pop()
      },
    ],
    [
      'changed case',
      'span_partition',
      (w: Wire) => {
        first(first(w.sources).parts).text = 'Arroz'
      },
    ],
    [
      'added whitespace',
      'span_partition',
      (w: Wire) => {
        first(first(w.sources).parts).text = ' arroz'
      },
    ],
    [
      'empty literal',
      'span_range',
      (w: Wire) => {
        first(w.sources).parts.unshift({ text: '', kind: 'other', food_index: null })
      },
    ],
    [
      'wrong source',
      'source_units',
      (w: Wire) => {
        first(w.sources).unit = 'media_caption'
      },
    ],
    [
      'duplicate source',
      'source_units',
      (w: Wire) => {
        w.sources.push(first(w.sources))
      },
    ],
    [
      'visual classification',
      'source_shape',
      (w: Wire) => {
        first(w.sources).classification = 'visual'
      },
    ],
    [
      'visual indices on text',
      'source_shape',
      (w: Wire) => {
        first(w.sources).visual_indexes = [0]
      },
    ],
    [
      'ref index outside unit',
      'reference_binding',
      (w: Wire) => {
        first(w.foods).name = { unit: 'command_text', part_index: 3 }
      },
    ],
    [
      'ref missing unit',
      'reference_binding',
      (w: Wire) => {
        first(w.foods).name = { unit: 'media_caption', part_index: 0 }
      },
    ],
    [
      'ref wrong role',
      'reference_binding',
      (w: Wire) => {
        first(w.foods).name = { unit: 'command_text', part_index: 1 }
      },
    ],
    [
      'non dense occurrence',
      'occurrence_binding',
      (w: Wire) => {
        first(w.foods).index = 1
      },
    ],
    [
      'extra wire property',
      'model_schema',
      (w: Wire) => {
        Object.assign(w, { secret: 'sentinel' })
      },
    ],
    [
      'negative part index',
      'model_schema',
      (w: Wire) => {
        first(w.foods).name = { unit: 'command_text', part_index: -1 }
      },
    ],
    [
      'fractional part index',
      'model_schema',
      (w: Wire) => {
        first(w.foods).name = { unit: 'command_text', part_index: 0.5 }
      },
    ],
    [
      'unsafe part index',
      'model_schema',
      (w: Wire) => {
        first(w.foods).name = { unit: 'command_text', part_index: Number.MAX_SAFE_INTEGER + 1 }
      },
    ],
    [
      'wrong literal type',
      'model_schema',
      (w: Wire) => {
        Object.assign(first(first(w.sources).parts), { text: 42 })
      },
    ],
    [
      'extra literal property',
      'model_schema',
      (w: Wire) => {
        Object.assign(first(first(w.sources).parts), { start: 0 })
      },
    ],
    [
      'too many parts',
      'model_schema',
      (w: Wire) => {
        first(w.sources).parts = Array.from({ length: 4097 }, () => first(first(w.sources).parts))
      },
    ],
    [
      'too many foods',
      'model_schema',
      (w: Wire) => {
        w.foods = Array.from({ length: 31 }, () => first(w.foods))
      },
    ],
  ] as const)('rejects %s without repair or diagnostics from raw values', (_name, reason, mutate) => {
    const wire = rice(),
      failure = vi.fn(() => {
        throw new Error('private sink')
      })
    mutate(wire)
    expect(() => validated(wire, source('arroz200g'), failure)).toThrow(
      'Meal interpretation is unavailable',
    )
    expect(failure.mock.calls).toEqual([[reason]])
  })
  it('rejects Unicode normalization even if rendered words look identical', () => {
    const wire = rice()
    first(first(wire.sources).parts).text = 'feijão'
    expect(() => validated(wire, source('feija\u0303o200g'))).toThrow(
      'Meal interpretation is unavailable',
    )
  })
  it('preserves owned visual items and refuses text substituted for vision', () => {
    const { input, wire } = media()
    const result = validated(wire, input)
    expect(result.decision).toBe('reported_meal')
    expect(result.sources[1]).toEqual({
      unit: 'vision_items',
      classification: 'visual',
      spans: [],
      visual_indexes: [0],
    })
    expect(result.foods[0]?.visual_index).toBe(0)
    const visual = wire.sources[1]
    if (!visual) throw new Error('Missing visual fixture')
    visual.parts = [{ text: 'arroz', kind: 'food', food_index: 0 }]
    expect(() => validated(wire, input)).toThrow('Meal interpretation is unavailable')
  })
  it.each([
    'order',
    'omission',
    'visual_index',
    'duplicate_visual_index',
    'negative_caption',
    'cross_unit',
  ] as const)('preserves source/vision guards: %s', (change) => {
    const { input, wire } = media(),
      failure = vi.fn()
    if (change === 'order') wire.sources.reverse()
    if (change === 'omission') wire.sources.pop()
    if (change === 'visual_index') first(wire.foods).visual_index = 1
    if (change === 'duplicate_visual_index') {
      const visual = wire.sources[1]
      if (visual) visual.visual_indexes = [0, 0]
    }
    if (change === 'cross_unit')
      first(wire.foods).name = { unit: 'media_transcript', part_index: 0 }
    if (change === 'negative_caption') {
      first(input.sources).text = 'Não comi'
      first(first(wire.sources).parts).text = 'Não comi'
      expect(validated(wire, input).decision).toBe('clarification_required')
      return
    }
    expect(() => validated(wire, input, failure)).toThrow('Meal interpretation is unavailable')
    expect(failure.mock.calls).toEqual([
      [
        change === 'visual_index'
          ? 'visual_binding'
          : change === 'duplicate_visual_index'
            ? 'source_shape'
            : change === 'cross_unit'
              ? 'reference_binding'
              : 'source_units',
      ],
    ])
  })
  it.each([
    'Sonhei que comi ',
    'Vou comer ',
    'Costumo comer ',
    'Não comi ',
    'Ela comeu ',
  ])('does not upgrade %s through literal equality', (prefix) => {
    const wire = rice()
    wire.reason = 'explicit_report'
    first(wire.sources).classification = 'reported'
    first(wire.sources).parts.unshift({ text: prefix, kind: 'report', food_index: null })
    first(wire.foods).name = { unit: 'command_text', part_index: 1 }
    first(wire.foods).quantity = { unit: 'command_text', part_index: 2 }
    first(wire.foods).unit = { unit: 'command_text', part_index: 3 }
    expect(validated(wire, source(`${prefix}arroz200g`)).decision).toBe('clarification_required')
  })
  it.each([
    'not_reported',
    'clarification_required',
  ] as const)('preserves valid %s and no foods', (decision) => {
    const wire = rice()
    wire.decision = decision
    wire.reason = 'negated'
    wire.foods = []
    first(wire.sources).classification = 'negated'
    first(wire.sources).parts = [{ text: 'Não comi', kind: 'other', food_index: null }]
    expect(validated(wire, source('Não comi'))).toMatchObject({
      decision,
      reason: 'negated',
      foods: [],
    })
  })
  it('keeps caption and transcript occurrences distinct and downgrades their duplicate association', () => {
    const { input } = media()
    if (!input.media_binding) throw new Error('Missing media fixture')
    input.media_binding.kind = 'audio_note'
    input.source_units = ['media_caption', 'media_transcript']
    input.sources = [
      { unit: 'media_caption', text: 'arroz100g', visual_items: [] },
      { unit: 'media_transcript', text: 'arroz200g', visual_items: [] },
    ]
    const wire: Wire = {
      schema: 'conversation.meal-literal-partition.v1',
      decision: 'reported_meal',
      reason: 'nominal_food_list',
      sources: [
        {
          unit: 'media_caption',
          classification: 'nominal_list',
          visual_indexes: [],
          parts: [
            { text: 'arroz', kind: 'food', food_index: 0 },
            { text: '100', kind: 'quantity', food_index: 0 },
            { text: 'g', kind: 'unit', food_index: 0 },
          ],
        },
        {
          unit: 'media_transcript',
          classification: 'nominal_list',
          visual_indexes: [],
          parts: [
            { text: 'arroz', kind: 'food', food_index: 1 },
            { text: '200', kind: 'quantity', food_index: 1 },
            { text: 'g', kind: 'unit', food_index: 1 },
          ],
        },
      ],
      foods: [
        {
          index: 0,
          name: { unit: 'media_caption', part_index: 0 },
          quantity: { unit: 'media_caption', part_index: 1 },
          unit: { unit: 'media_caption', part_index: 2 },
          visual_index: null,
        },
        {
          index: 1,
          name: { unit: 'media_transcript', part_index: 0 },
          quantity: { unit: 'media_transcript', part_index: 1 },
          unit: { unit: 'media_transcript', part_index: 2 },
          visual_index: null,
        },
      ],
    }
    const canonical = materializeConversationMealLiteralPartition(wire, input)
    expect(canonical.foods).toEqual([
      {
        index: 0,
        name: { unit: 'media_caption', start: 0, end: 5 },
        quantity: { unit: 'media_caption', start: 5, end: 8 },
        unit: { unit: 'media_caption', start: 8, end: 9 },
        visual_index: null,
      },
      {
        index: 1,
        name: { unit: 'media_transcript', start: 0, end: 5 },
        quantity: { unit: 'media_transcript', start: 5, end: 8 },
        unit: { unit: 'media_transcript', start: 8, end: 9 },
        visual_index: null,
      },
    ])
    expect(validated(wire, input).decision).toBe('clarification_required')
    first(wire.foods).quantity = { unit: 'media_transcript', part_index: 1 }
    const failure = vi.fn()
    expect(() => validated(wire, input, failure)).toThrow('Meal interpretation is unavailable')
    expect(failure.mock.calls).toEqual([['reference_binding']])
  })
  it('rejects invalid source and oversized wire with isolated static reasons', () => {
    const wire = rice(),
      input = source(''),
      failure = vi.fn()
    expect(() => materializeConversationMealLiteralPartition(wire, input, failure)).toThrow(
      'Meal interpretation is unavailable',
    )
    expect(failure.mock.calls).toEqual([['source_contract']])
    failure.mockClear()
    first(first(wire.sources).parts).text = 'x'.repeat(131072)
    expect(() =>
      materializeConversationMealLiteralPartition(wire, source('arroz200g'), failure),
    ).toThrow('Meal interpretation is unavailable')
    expect(failure.mock.calls).toEqual([['model_envelope']])
  })
})
