import { describe, expect, it } from 'vitest'
import type { ConversationMealInterpretationSource } from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import { prepareConversationMealSourceLabels } from './conversation-meal-source-labels'

type Unit = 'command_text' | 'media_transcript'
type Role = 'other' | 'report' | 'quantity' | 'unit' | 'separator' | 'food'

function spokenMilk(unit: Unit, prefix = ' No almoço eu ') {
  const text = `${prefix}tomei 200 mililitros de leite com uma medida de whey.`,
    id = '10000000-0000-4000-8000-000000000001',
    source: ConversationMealInterpretationSource = {
      schema: 'conversation.meal-interpretation-source.v1',
      interpreter_version: 'conversation.meal-interpreter.v1',
      owner_id: id,
      command_id: id,
      input_hash: 'a'.repeat(64),
      source_hash: 'b'.repeat(64),
      epoch: id,
      captured_at: '2026-11-13T08:32:00Z',
      media_binding:
        unit === 'media_transcript'
          ? {
              asset_id: id,
              kind: 'audio_note',
              processed_at: '2026-11-13T08:31:00Z',
              updated_at: '2026-11-13T08:31:00Z',
              processing_hash: 'c'.repeat(64),
            }
          : null,
      source_units: [unit],
      sources: [{ unit, text, visual_items: [] }],
    },
    packet = prepareConversationMealSourceLabels(source),
    tokens = packet.input.sources[0]?.tokens ?? [],
    reportAt = tokens.findIndex(([, word]) => word === 'tomei'),
    roles: Array<[Role, number | null]> = [
      ['report', null],
      ['quantity', 0],
      ['unit', 0],
      ['separator', null],
      ['food', 0],
      ['separator', null],
      ['quantity', 1],
      ['unit', 1],
      ['separator', null],
      ['food', 1],
      ['separator', null],
    ],
    wire = {
      schema: 'conversation.meal-source-labels.v1',
      decision: 'reported_meal',
      reason: 'explicit_report',
      sources: {
        [unit]: {
          classification: 'reported',
          labels: Object.fromEntries(
            tokens.map(([key], i) => {
              const role = i < reportAt ? (['other', null] as const) : roles[i - reportAt]
              if (!role) throw new Error('Unaccounted synthetic token')
              const [kind, food_index] = role
              return [key, { kind, food_index }]
            }),
          ),
        },
      },
      foods: [
        { index: 0, visual_index: null },
        { index: 1, visual_index: null },
      ],
    }
  return { source, text, model: packet.materialize(wire) }
}

describe('separately labeled first-person subject in a spoken meal context', () => {
  for (const unit of ['command_text', 'media_transcript'] as const) {
    it(`preserves the complete ${unit} report without requiring another manual confirmation`, () => {
      const { source, text, model } = spokenMilk(unit),
        result = validateConversationMealInterpretationModel(model, source)
      const runs: Record<string, number> = {}
      for (const span of model.sources[0]?.spans ?? []) runs[span.kind] = (runs[span.kind] ?? 0) + 1
      // Same closed role counts observed in the synthetic hosted audio case;
      // raw provider labels were not retained by that privacy-safe diagnostic.
      expect(runs).toEqual({ separator: 9, other: 1, report: 1, quantity: 2, unit: 2, food: 2 })
      expect(result.decision).toBe('reported_meal')
      expect(result).toEqual(model)
      expect(
        result.sources[0]?.spans.map((span) => text.slice(span.start, span.end)).join(''),
      ).toBe(text)
      expect(
        result.foods.map((food) =>
          [food.name, food.quantity, food.unit].map((ref) => ref && text.slice(ref.start, ref.end)),
        ),
      ).toEqual([
        ['leite', '200', 'mililitros'],
        ['whey', 'uma', 'medida'],
      ])
    })
    it.each([
      'No almoço eu não ',
      'No almoço eu nunca ',
      'No almoço eu vou dizer que ',
      'No almoço eu costumo dizer que ',
      'No almoço eu sonhei que ',
      'No almoço eu talvez ',
      'No almoço ela ',
      'No almoço minha filha ',
      'No almoço de amanhã eu ',
      'No almoço de ontem eu ',
      'No almoço eu perguntei se ',
      'No almoço eu disse "',
    ])(`preserves unsafe or unaccounted discourse in ${unit}: %s`, (prefix) => {
      const { source, model } = spokenMilk(unit, prefix),
        result = validateConversationMealInterpretationModel(model, source)
      expect(result.decision).toBe('clarification_required')
      expect(result.foods).toEqual([])
    })
    it(`never upgrades a model refusal in ${unit}`, () => {
      const { source, model } = spokenMilk(unit)
      expect(
        validateConversationMealInterpretationModel(
          { ...model, decision: 'clarification_required', reason: 'ambiguous' },
          source,
        ).decision,
      ).toBe('clarification_required')
    })
  }
})
