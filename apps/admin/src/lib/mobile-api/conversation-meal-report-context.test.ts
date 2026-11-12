import type { MealCalcResult } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import {
  writerBinding,
  writerCommandId,
  writerOwner,
  writerReceipt,
  writerSource,
} from './__fixtures__/conversation-meal-writer'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  buildConversationMealInterpretationSource,
  type ConversationMealInterpretation,
  type MealInterpretationModelResult,
} from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import type { MaterializedConversationMeal } from './conversation-meal-materialization'
import { registerPersistedConversationMeal } from './conversation-meal-registration-service'

const originalMilk = 'No café da manhã, consumi 200 mL de leite com 1 medida de whey.'
const attempt = '10000000-0000-4000-8000-000000000010'
function fixture(text: string, selected?: 'cafe' | 'almoco' | 'jantar') {
  const command = bindConversationCommand(writerOwner, `cmsg1:${writerCommandId}`, {
    command_protocol: 'conversation.command.v1',
    command_id: writerCommandId,
    kind: 'meal.report',
    ...(selected === undefined ? {} : { meal_type: selected }),
    source: { channel: 'text', text },
  })
  const prior = writerSource()
  const capture = {
    ...prior,
    capturedAt: '2026-11-04T18:00:00.000002Z',
    context: { ...prior.context, input_hash: command.inputHash, source_input: command.command },
  }
  return { command, capture, source: buildConversationMealInterpretationSource(command, capture) }
}
function riceModel(prefix: string, suffix = ''): MealInterpretationModelResult {
  const start = prefix.length
  return {
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
          { start, end: start + 5, kind: 'food', food_index: 0 },
          { start: start + 5, end: start + 8, kind: 'quantity', food_index: 0 },
          { start: start + 8, end: start + 9, kind: 'unit', food_index: 0 },
          ...(suffix
            ? [
                {
                  start: start + 9,
                  end: start + 9 + suffix.length,
                  kind: 'separator' as const,
                  food_index: null,
                },
              ]
            : []),
        ],
      },
    ],
    foods: [
      {
        index: 0,
        name: { unit: 'command_text', start, end: start + 5 },
        quantity: { unit: 'command_text', start: start + 5, end: start + 8 },
        unit: { unit: 'command_text', start: start + 8, end: start + 9 },
        visual_index: null,
      },
    ],
  }
}
function milkModel(): MealInterpretationModelResult {
  return {
    schema: 'conversation.meal-interpretation.v1',
    decision: 'reported_meal',
    reason: 'explicit_report',
    sources: [
      {
        unit: 'command_text',
        classification: 'reported',
        visual_indexes: [],
        spans: [
          { start: 0, end: 26, kind: 'report', food_index: null },
          { start: 26, end: 29, kind: 'quantity', food_index: 0 },
          { start: 29, end: 30, kind: 'separator', food_index: null },
          { start: 30, end: 32, kind: 'unit', food_index: 0 },
          { start: 32, end: 36, kind: 'separator', food_index: null },
          { start: 36, end: 62, kind: 'food', food_index: 0 },
          { start: 62, end: 63, kind: 'separator', food_index: null },
        ],
      },
    ],
    foods: [
      {
        index: 0,
        name: { unit: 'command_text', start: 36, end: 62 },
        quantity: { unit: 'command_text', start: 26, end: 29 },
        unit: { unit: 'command_text', start: 30, end: 32 },
        visual_index: null,
      },
    ],
  }
}
function validate(prefix: string, suffix = '') {
  return validateConversationMealInterpretationModel(
    riceModel(prefix, suffix),
    fixture(`${prefix}arroz200g${suffix}`).source,
  )
}

describe('closed leading meal context preserves consumption authority', () => {
  it('accepts the exact original63 UTF16 milk/whey source without modifying text or authority', () => {
    const f = fixture(originalMilk),
      before = structuredClone(f),
      model = milkModel()
    expect(originalMilk).toHaveLength(63)
    expect(originalMilk.slice(36, 62)).toBe('leite com 1 medida de whey')
    expect(originalMilk.slice(26, 29)).toBe('200')
    expect(originalMilk.slice(30, 32)).toBe('mL')
    const result = validateConversationMealInterpretationModel(model, f.source)
    expect(result).toEqual(model)
    expect(result.decision).toBe('reported_meal')
    expect(f).toEqual(before)
    expect(f.command.command).not.toHaveProperty('meal_type')
    expect(f.command.command).not.toHaveProperty('meal_type_hint')
    expect(f.source.sources[0]?.text).toBe(originalMilk)
    expect(f.source.input_hash).toBe(f.command.inputHash)
  })
  it.each([
    'No almoço, comi ',
    'No jantar, eu bebi ',
    'No café da manhã consumi ',
    'No almoço, agora eu ingeri ',
    'No jantar, acabei de comer ',
  ])('accepts one closed context followed by an existing predicate: %s', (prefix) => {
    expect(validate(prefix).decision).toBe('reported_meal')
  })
  it.each([
    'No café da manhã, não consumi ',
    'No almoço, nunca comi ',
    'No jantar, vou consumir ',
    'No café da manhã, costumo consumir ',
    'No almoço, geralmente comi ',
    'No jantar, ela consumiu ',
    'No café da manhã, minha filha consumiu ',
    'No almoço, sonhei que comi ',
    'No sonho, consumi ',
    'No almoço, talvez consumi ',
    'No jantar, consumi ou comi ',
    'No almoço e no jantar, consumi ',
    'No almoço de amanhã, consumi ',
    'No almoço, depois consumi ',
    'No lanche, consumi ',
    'Na refeição, consumi ',
    'No jantar, você consumiu ',
    'No café da manhã, "consumi" ',
  ])('rejects a forged positive assertion around unsupported context: %s', (prefix) => {
    expect(validate(prefix).decision).toBe('clarification_required')
  })
  it.each([
    ' mas não feijão100g',
    ' e amanhã vou comer feijão100g',
    ' no sonho',
    ' e ela comeu feijão100g',
    '?',
    ' geralmente',
  ])('keeps the complete trailing discourse refused: %s', (suffix) => {
    expect(validate('No almoço, consumi ', suffix).decision).toBe('clarification_required')
  })
  it('does not accept a meal context alone as consumption proof', () => {
    expect(validate('No café da manhã, ').decision).toBe('clarification_required')
    expect(validate('Hoje, ', ' no almoço').decision).toBe('clarification_required')
  })
  it('preserves a genuine consumption predicate and all food references with a trailing current meal context', () => {
    const model = riceModel('Consumi ', ' no almoço')
    expect(validate('Consumi ', ' no almoço')).toEqual(model)
    expect(model.foods[0]?.quantity).toEqual({ unit: 'command_text', start: 13, end: 16 })
  })
})

// Real registration composition with synthetic ports; this is unit evidence,
// not an SQL/provider/nutrition qualification. Only the semantic model is real.
async function registerRice(selected?: 'jantar', prefix = 'No café da manhã, consumi ') {
  const text = `${prefix}arroz200g`,
    f = fixture(text, selected),
    model = riceModel(prefix)
  const value = validateConversationMealInterpretationModel(model, f.source)
  const persisted: ConversationMealInterpretation = {
    ...value,
    interpreter_version: f.source.interpreter_version,
    owner_id: writerOwner,
    command_id: writerCommandId,
    attempt_id: attempt,
    input_hash: f.command.inputHash,
    source_hash: f.capture.sourceHash,
    source_units: ['command_text'],
    provider_metadata: {
      model: 'synthetic',
      prompt_tokens: 1,
      completion_tokens: 1,
      cost_usd: null,
      latency_ms: 1,
    },
  }
  const food = value.foods[0]
  const writer = {
    readPrepared: vi.fn().mockResolvedValue({ action: 'absent' }),
    readEffect: vi.fn().mockResolvedValue({ action: 'absent' }),
    prepare: vi.fn().mockResolvedValue({ action: 'prepared', resolvedHash: 'c'.repeat(64) }),
    commit: vi.fn().mockResolvedValue({
      action: 'committed',
      receipt: {
        ...writerReceipt(),
        input_hash: f.command.inputHash,
        meal_type: selected ?? 'cafe',
      },
    }),
  }
  const dependencies = {
    journal: {
      read: vi.fn().mockResolvedValue({ action: 'absent' }),
      admit: vi.fn().mockResolvedValue({
        action: 'admitted',
        binding: { ...writerBinding(), input_hash: f.command.inputHash },
      }),
      attach: vi.fn(),
    },
    sources: {
      capture: vi.fn().mockResolvedValue({
        ...f.capture,
        sourceReader: {
          ownerId: writerOwner,
          asOf: f.capture.capturedAt,
          read: vi.fn(async () => []),
        },
        auditSink: vi.fn(async () => {}),
        sourceReceipts: () => [],
        auditEvents: () => [],
      }),
    },
    initializeDay: vi.fn(async () => {}),
    interpreter: { interpret: vi.fn() },
    interpret: vi.fn(async () => persisted),
    materialize: vi.fn(
      async (): Promise<MaterializedConversationMeal> => ({
        status: 'materialized',
        schema: 'conversation.meal-materialization.v1',
        input_hash: f.command.inputHash,
        source_hash: f.capture.sourceHash,
        attempt_id: attempt,
        inputs: [
          {
            input_index: 0,
            calculation_input: { food_name: 'arroz', quantity_g: 200 },
            source_group_index: 0,
            candidate: {
              candidate_id: 'context-rice',
              name: 'arroz',
              quantity_g: 200,
              quantity_basis: 'stated',
              count: null,
              unit_label: null,
              confidence: null,
              needs_review: false,
              review_reason: null,
            },
          },
        ],
        source_groups: [
          {
            group_index: 0,
            interpretation_food_indexes: [0],
            input_indexes: [0],
            rule: 'literal',
            source_positions: [
              {
                food_index: 0,
                unit: 'command_text',
                name: food?.name ?? null,
                quantity: food?.quantity ?? null,
                unit_ref: food?.unit ?? null,
                visual_index: null,
              },
            ],
          },
        ],
        nutrition_label: null,
      }),
    ),
    calculate: vi.fn(
      async (): Promise<MealCalcResult> => ({
        items: [
          {
            food_name: 'Arroz branco cozido',
            matched_taco_name: 'Arroz branco cozido',
            matched_taco_id: 1,
            quantity_g: 200,
            kcal: 256,
            protein_g: 5,
            carbs_g: 56.2,
            fat_g: 0.4,
            fiber_g: 2,
            similarity: 1,
            source: 'canonical_exact',
          },
        ],
        totals: { kcal: 256, protein_g: 5, carbs_g: 56.2, fat_g: 0.4, fiber_g: 2 },
        warnings: [],
        user_warnings: [],
        audit_warnings: [],
        preparation_annotations: [],
      }),
    ),
    confidenceThreshold: async () => 0.6,
    writer,
    feedback: {
      ensureOriginal: vi.fn().mockResolvedValue(null),
      readOriginal: vi.fn().mockResolvedValue(null),
    },
  }
  const result = await registerPersistedConversationMeal(
    {} as ServiceClient,
    candidateAuth,
    `cmsg1:${writerCommandId}`,
    f.command.command,
    dependencies,
  )
  return { result, dependencies, f }
}
describe('actual registration service keeps selected and textual meal authority', () => {
  it('does not prepare or commit a negated report even with a selected meal', async () => {
    const { result, dependencies } = await registerRice('jantar', 'No café da manhã, não consumi ')
    expect(result).toMatchObject({ status: 'not_recorded', reason: 'ambiguous' })
    expect(dependencies.materialize).not.toHaveBeenCalled()
    expect(dependencies.calculate).not.toHaveBeenCalled()
    expect(dependencies.writer.prepare).not.toHaveBeenCalled()
    expect(dependencies.writer.commit).not.toHaveBeenCalled()
  })
  it('infers breakfast from the accepted original context, with no selected hint or clock inference', async () => {
    const { result, dependencies, f } = await registerRice()
    expect(result).toMatchObject({ status: 'saved', receipt: { meal_type: 'cafe' } })
    expect(dependencies.writer.prepare).toHaveBeenCalledWith(
      expect.objectContaining({ resolved: expect.objectContaining({ meal_type: 'cafe' }) }),
    )
    expect(f.command.command).not.toHaveProperty('meal_type')
    expect(f.capture.capturedAt).toBe('2026-11-04T18:00:00.000002Z')
  })
  it('keeps an explicit selected meal ahead of the leading context', async () => {
    const { result, dependencies } = await registerRice('jantar')
    expect(result).toMatchObject({ status: 'saved', receipt: { meal_type: 'jantar' } })
    expect(dependencies.writer.prepare).toHaveBeenCalledWith(
      expect.objectContaining({ resolved: expect.objectContaining({ meal_type: 'jantar' }) }),
    )
  })
})
