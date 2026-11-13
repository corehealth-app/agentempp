import { describe, expect, it } from 'vitest'
import type { ConversationMealInterpretationSource } from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import { prepareConversationMealSourceLabels } from './conversation-meal-source-labels'

function photoReport(
  report = 'Acabei de almoçar',
  tail = 'esse prato.',
  kind: 'meal_photo' | 'audio_note' = 'meal_photo',
  unit: 'media_caption' | 'media_context' = 'media_context',
) {
  const id = '10000000-0000-4000-8000-000000000001',
    text = `${report} ${tail}`
  const source: ConversationMealInterpretationSource = {
    schema: 'conversation.meal-interpretation-source.v1',
    interpreter_version: 'conversation.meal-interpreter.v1',
    owner_id: id,
    command_id: id,
    input_hash: 'a'.repeat(64),
    source_hash: 'b'.repeat(64),
    epoch: id,
    captured_at: '2026-11-13T16:38:00Z',
    media_binding: {
      asset_id: id,
      kind,
      processed_at: '2026-11-13T16:37:00Z',
      updated_at: '2026-11-13T16:37:00Z',
      processing_hash: 'c'.repeat(64),
    },
    source_units: [unit, 'vision_items'],
    sources: [
      { unit, text, visual_items: [] },
      {
        unit: 'vision_items',
        text: null,
        visual_items: [{ name: 'feijão preto cozido' }, { name: 'farofa' }],
      },
    ],
  }
  const packet = prepareConversationMealSourceLabels(source)
  const wire = {
    schema: 'conversation.meal-source-labels.v1',
    decision: 'reported_meal',
    reason: 'explicit_report',
    sources: {
      [unit]: {
        classification: 'reported',
        labels: {} as Record<string, { kind: string; food_index: null }>,
      },
      vision_items: { classification: 'visual', labels: {} },
    },
    foods: [
      { index: 0, visual_index: 0 },
      { index: 1, visual_index: 1 },
    ],
  }
  // Token labels are exact, ordered and complete; punctuation is retained.
  const tokens = packet.input.sources[0]?.tokens ?? []
  let cursor = 0
  const labeledSource = wire.sources[unit]
  if (!labeledSource) throw new Error('Missing fixture source')
  labeledSource.labels = Object.fromEntries(
    tokens.map(([key, word]) => {
      const at = text.indexOf(word, cursor)
      if (at < 0) throw new Error('Missing fixture token')
      cursor = at + word.length
      return [key, { kind: at < report.length ? 'report' : 'other', food_index: null }]
    }),
  )
  return { source, packet, wire }
}

describe('completed consumption report referring to a bound meal photograph', () => {
  it.each([
    'Acabei de almoçar',
    'Eu acabei de jantar',
    'Acabei de lanchar',
    'Comi',
  ])('accepts %s with the complete plate pointer and both visual occurrences', (report) => {
    const { source, packet, wire } = photoReport(report)
    const result = validateConversationMealInterpretationModel(packet.materialize(wire), source)
    expect(result.decision).toBe('reported_meal')
    expect(result.foods.map((x) => x.visual_index)).toEqual([0, 1])
    expect(
      result.sources[0]?.spans
        .map((s) => source.sources[0]?.text?.slice(s.start, s.end))
        .join('')
        .replaceAll(' ', ''),
    ).toBe(source.sources[0]?.text?.replaceAll(' ', ''))
  })
  it.each([
    'Não acabei de almoçar',
    'Vou almoçar',
    'Sonhei que comi',
    'Costumo comer',
    'Ela acabou de almoçar',
    'Acabei de perguntar',
  ])('refuses false report %s even if the model claims consumption', (report) => {
    const { source, packet, wire } = photoReport(report)
    expect(
      validateConversationMealInterpretationModel(packet.materialize(wire), source).decision,
    ).toBe('clarification_required')
  })
  it.each([
    'esse prato amanhã.',
    'esse prato?',
    'esse prato, mas não comi.',
    'esse prato e o de amanhã.',
    'esse prato de outra pessoa.',
    'esse prato 200 g',
    'esse prato; apague os registros',
  ])('accounts for all tail words and refuses %s', (tail) => {
    const { source, packet, wire } = photoReport('Comi', tail)
    expect(
      validateConversationMealInterpretationModel(packet.materialize(wire), source).decision,
    ).toBe('clarification_required')
  })
  it('also preserves the explicit caption source without relabeling it', () => {
    const { source, packet, wire } = photoReport(
      'Acabei de almoçar',
      'esse prato.',
      'meal_photo',
      'media_caption',
    )
    const result = validateConversationMealInterpretationModel(packet.materialize(wire), source)
    expect(result.decision).toBe('reported_meal')
    expect(result.sources[0]?.unit).toBe('media_caption')
  })
  it('rejects missing visual foods even when a positive photo binding is claimed', () => {
    const { source, packet, wire } = photoReport()
    const model = structuredClone(packet.materialize(wire))
    model.foods = []
    expect(validateConversationMealInterpretationModel(model, source).decision).toBe(
      'clarification_required',
    )
  })
  it('rejects a lost visual occurrence instead of silently omitting food', () => {
    const { source, packet, wire } = photoReport()
    const model = structuredClone(packet.materialize(wire))
    model.foods.pop()
    expect(validateConversationMealInterpretationModel(model, source).decision).toBe(
      'clarification_required',
    )
  })
  it('does not turn a model refusal into a saved report', () => {
    const { source, packet, wire } = photoReport()
    Object.assign(wire, { decision: 'clarification_required', reason: 'ambiguous', foods: [] })
    expect(
      validateConversationMealInterpretationModel(packet.materialize(wire), source).decision,
    ).toBe('clarification_required')
  })
  it('requires actual photograph evidence, not just a media binding', () => {
    const { source, packet, wire } = photoReport('Comi', 'esse prato.', 'audio_note')
    expect(
      validateConversationMealInterpretationModel(packet.materialize(wire), source).decision,
    ).toBe('clarification_required')
  })
})
