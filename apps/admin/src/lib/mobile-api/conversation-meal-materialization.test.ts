import {
  calcMealMacros,
  consumedFoodDefault,
  everydayFoodDefault,
  type MealCalcResult,
} from '@mpp/agent'
import type { Json, ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  buildConversationMealInterpretationSource,
  type ConversationMealInterpretation,
  type MealInterpretationModelResult,
} from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import {
  mapConversationMealCalculationSources,
  materializeConversationMealContinuation,
  materializeConversationMealInterpretation,
  materializeStoredConversationMealContinuation,
} from './conversation-meal-materialization'
import { createBoundConversationMealCorrectionReader } from './conversation-meal-personal-correction'
import type { CapturedConversationMealSource } from './conversation-meal-source'
import { mobileQuantityDisplay } from './mobile-quantity-display'
import { applyMobilePreparedDishEstimate } from './prepared-dish-estimate'

const OWNER = '10000000-0000-4000-8000-000000000001'
const COMMAND = '10000000-0000-4000-8000-000000000002'
const ATTEMPT = '10000000-0000-4000-8000-000000000003'
const ASSET = '10000000-0000-4000-8000-000000000004'
const EPOCH = '10000000-0000-4000-8000-000000000005'
const options = { confidenceThreshold: 0.6 }
const row = (name: string, id = 91) => ({
  id,
  name_pt: name,
  category: 'alimento',
  similarity: 1,
  kcal_per_100g: 100,
  protein_g: 10,
  carbs_g: 10,
  fat_g: 2,
  fiber_g: 0,
  country_code: 'BR',
})
function db(names: string[] = []) {
  const rpc = vi.fn(async (_name: string, p: Record<string, unknown>) => ({
    data: names.filter((n) => n.toLowerCase() === p.search_term).map((n) => row(n)),
    error: null,
  }))
  const from = vi.fn(() => {
    const result = Promise.resolve({ data: [], error: null })
    return Object.assign(result, {
      select: () => result,
      eq: () => result,
      neq: () => result,
      gte: () => result,
      order: () => result,
      limit: () => result,
    })
  })
  return { client: { rpc, from } as unknown as ServiceClient, rpc, from }
}
function at<T>(list: readonly T[], index = 0): T {
  const item = list[index]
  if (item === undefined) throw new Error('fixture item missing')
  return item
}
type Item = { name: string; quantity?: string; unit?: string }
function fixture(text: string, items: Item[]) {
  const command = bindConversationCommand(OWNER, `cmsg1:${COMMAND}`, {
    command_protocol: 'conversation.command.v1',
    command_id: COMMAND,
    kind: 'meal.report',
    source: { channel: 'text', text },
  })
  const capture: CapturedConversationMealSource = {
    action: 'captured',
    sourceHash: 'a'.repeat(64),
    capturedAt: '2026-11-05T01:00:00.000001Z',
    epoch: EPOCH,
    context: {
      schema: 'conversation.meal-source.v1',
      owner_id: OWNER,
      command_id: COMMAND,
      input_hash: command.inputHash,
      epoch: EPOCH,
      source_input: command.command,
      source_units: ['command_text'],
      source_evidence: {},
      media: null,
      catalog: {},
      clinical: {},
      day: {},
      owner: {
        country: 'BR',
        country_confirmed: true,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
      },
    },
    sourceReader: {
      ownerId: OWNER,
      asOf: '2026-11-05T01:00:00.000001Z',
      read: vi.fn(async () => []),
    },
    sourceReceipts: () => [],
    auditSink: vi.fn(),
    auditEvents: () => [],
  }
  const source = buildConversationMealInterpretationSource(command, capture)
  const spans: MealInterpretationModelResult['sources'][number]['spans'] = []
  const foods: MealInterpretationModelResult['foods'] = []
  let cursor = 0
  for (const [index, item] of items.entries()) {
    const ref = (value: string) => {
      const start = text.indexOf(value, cursor)
      if (start < 0) throw new Error(`missing ${value}`)
      return { unit: 'command_text' as const, start, end: start + value.length }
    }
    const name = ref(item.name),
      quantity = item.quantity ? ref(item.quantity) : null,
      unit =
        item.unit && quantity
          ? {
              unit: 'command_text' as const,
              start: text.indexOf(item.unit, quantity.end),
              end: text.indexOf(item.unit, quantity.end) + item.unit.length,
            }
          : null
    const parts = [
      { ...name, kind: 'food' as const },
      ...(quantity ? [{ ...quantity, kind: 'quantity' as const }] : []),
      ...(unit ? [{ ...unit, kind: 'unit' as const }] : []),
    ].sort((a, b) => a.start - b.start)
    for (const part of parts) {
      if (part.start > cursor)
        spans.push({
          start: cursor,
          end: part.start,
          kind: cursor === 0 && text.slice(0, part.start).trim() ? 'report' : 'separator',
          food_index: null,
        })
      spans.push({ start: part.start, end: part.end, kind: part.kind, food_index: index })
      cursor = part.end
    }
    foods.push({ index, name, quantity, unit, visual_index: null })
  }
  if (cursor < text.length)
    spans.push({ start: cursor, end: text.length, kind: 'separator', food_index: null })
  const reported = spans.some((s) => s.kind === 'report')
  const model: MealInterpretationModelResult = {
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
  const interpretation: ConversationMealInterpretation = {
    ...model,
    interpreter_version: 'conversation.meal-interpreter.v1',
    owner_id: OWNER,
    command_id: COMMAND,
    attempt_id: ATTEMPT,
    input_hash: command.inputHash,
    source_hash: capture.sourceHash,
    source_units: source.source_units,
    provider_metadata: {
      model: 'synthetic',
      prompt_tokens: 1,
      completion_tokens: 1,
      cost_usd: null,
      latency_ms: 1,
    },
  }
  return { command, capture, source, model, interpretation }
}
function visualFixture(items: Json[], caption?: string) {
  const base = fixture('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }])
  const command = bindConversationCommand(OWNER, `cmsg1:${COMMAND}`, {
    command_protocol: 'conversation.command.v1',
    command_id: COMMAND,
    kind: 'meal.report',
    source: {
      channel: 'media',
      media_asset_id: ASSET,
      user_action: 'register_consumed_meal',
      ...(caption ? { caption } : {}),
    },
  })
  const capture: CapturedConversationMealSource = {
    ...base.capture,
    context: {
      ...base.capture.context,
      input_hash: command.inputHash,
      source_input: command.command,
      source_units: [...(caption ? ['media_caption' as const] : []), 'vision_items'],
      source_evidence: { caption: caption ?? null, transcript: null },
      media: {
        asset_id: ASSET,
        kind: 'meal_photo',
        status: 'processed',
        processed_at: '2026-11-05T01:00:00Z',
        updated_at: '2026-11-05T01:00:00Z',
        context_text: null,
        processing_result: {
          items,
          nutrition_label: {
            product_name: 'arroz',
            serving_size_g: 100,
            per_serving: { kcal: 100, protein_g: 2, carbs_g: 20, fat_g: 1 },
            per_100g: null,
            confidence: 0.99,
          },
        },
      },
    },
  }
  const source = buildConversationMealInterpretationSource(command, capture)
  const interpretation: ConversationMealInterpretation = {
    ...base.interpretation,
    input_hash: command.inputHash,
    source_units: source.source_units,
    reason: 'explicit_media_action',
    sources: source.sources.map((s) => ({
      unit: s.unit,
      classification: s.unit === 'vision_items' ? 'visual' : 'media_pointer',
      spans:
        s.text === null ? [] : [{ start: 0, end: s.text.length, kind: 'other', food_index: null }],
      visual_indexes: s.visual_items.map((_, i) => i),
    })),
    foods: items.map((_, index) => ({
      index,
      name: null,
      quantity: null,
      unit: null,
      visual_index: index,
    })),
  }
  return { command, capture, source, interpretation }
}
async function materialize(
  f: ReturnType<typeof fixture> | ReturnType<typeof visualFixture>,
  state: { client: ServiceClient } = db(),
) {
  return materializeConversationMealInterpretation(
    state.client,
    f.command,
    f.capture,
    f.interpretation,
    options,
  )
}
function prepared<T extends { status: string }>(value: T): Extract<T, { status: 'materialized' }> {
  if (value.status !== 'materialized')
    throw new Error(`Expected materialized: ${JSON.stringify(value)}`)
  return value as Extract<T, { status: 'materialized' }>
}

describe('actual command interpretation materialization', () => {
  it('materializes nominal rice/beans and duplicate occurrences preserving original refs', async () => {
    const f = fixture('arroz200g; feija\u0303o100g; arroz50g', [
        { name: 'arroz', quantity: '200', unit: 'g' },
        { name: 'feija\u0303o', quantity: '100', unit: 'g' },
        { name: 'arroz', quantity: '50', unit: 'g' },
      ]),
      state = db()
    const result = prepared(await materialize(f, state))
    expect(result.inputs.map((x) => x.calculation_input)).toEqual([
      { food_name: 'arroz', quantity_g: 200 },
      { food_name: 'feija\u0303o', quantity_g: 100 },
      { food_name: 'arroz', quantity_g: 50 },
    ])
    expect(result.source_groups.map((g) => g.interpretation_food_indexes)).toEqual([[0], [1], [2]])
    expect(result.source_groups[1]?.source_positions[0]?.name).toEqual(
      f.interpretation.foods[1]?.name,
    )
    expect(new Set(result.inputs.map((x) => x.candidate.candidate_id)).size).toBe(3)
    expect(Object.isFrozen(result.source_groups)).toBe(true)
    expect(state.rpc).not.toHaveBeenCalled()
  })
  it('qualifies whole verified catalog names and preserves explicit raw preparation', async () => {
    const f = fixture('Arroz cru100g', [{ name: 'Arroz cru', quantity: '100', unit: 'g' }]),
      state = db(['arroz cru'])
    const result = prepared(await materialize(f, state))
    expect(result.inputs[0]?.calculation_input.food_name).toBe('Arroz cru')
    expect(state.rpc).toHaveBeenCalledWith('search_food_trgm', {
      search_term: 'arroz cru',
      min_similarity: 0.9,
      max_results: 5,
      p_country: 'BR',
    })
  })
  it('never promotes unknown whole prose through a similar nutritional row', async () => {
    const f = fixture('arroz triste100g', [{ name: 'arroz triste', quantity: '100', unit: 'g' }]),
      state = db()
    state.rpc.mockResolvedValue({ data: [row('arroz')], error: null })
    expect(await materialize(f, state)).toMatchObject({
      status: 'clarification_required',
      reason: 'unqualified_whole_name',
      food_indexes: [0],
    })
  })
  it('recognizes the full catalogue wording despite its editorial comma, preserving the stated input', async () => {
    const f = fixture('iogurte natural200g', [
        { name: 'iogurte natural', quantity: '200', unit: 'g' },
      ]),
      state = db()
    // Actual staging catalogue: id597 "Iogurte, natural", similarity1.
    state.rpc.mockResolvedValue({ data: [row('Iogurte, natural', 597)], error: null })
    const result = prepared(await materialize(f, state))
    expect(result.inputs[0]?.calculation_input).toEqual({
      food_name: 'iogurte natural',
      quantity_g: 200,
    })
    expect(result.source_groups[0]?.source_positions[0]?.name).toEqual(
      f.interpretation.foods[0]?.name,
    )
    expect(state.rpc).toHaveBeenCalledWith('search_food_trgm', {
      search_term: 'iogurte natural',
      min_similarity: 0.9,
      max_results: 5,
      p_country: 'BR',
    })
  })
  it('asks only for the missing quantity when the whole catalogue name contains an editorial comma', async () => {
    const f = fixture('iogurte natural', [{ name: 'iogurte natural' }]),
      state = db()
    state.rpc.mockResolvedValue({ data: [row('Iogurte, natural', 597)], error: null })
    expect(await materialize(f, state)).toMatchObject({
      status: 'clarification_required',
      reason: 'missing_quantity',
      food_indexes: [0],
    })
  })
  it.each([
    'Iogurte, natural desnatado',
    'Iogurte, natural com whey',
    'Iogurte, natural Marca X',
    'Iogurte, natural 0,1%',
  ])('does not discard catalogue qualifiers in %s', async (name) => {
    const state = db()
    state.rpc.mockResolvedValue({ data: [row(name)], error: null })
    expect(
      await materialize(
        fixture('iogurte natural200g', [{ name: 'iogurte natural', quantity: '200', unit: 'g' }]),
        state,
      ),
    ).toMatchObject({
      status: 'clarification_required',
      reason: 'unqualified_whole_name',
    })
  })
  it('expands the original breakfast report from explicit milk volume without subtracting whey', async () => {
    const f = fixture('No café da manhã, consumi 200 mL de leite com 1 medida de whey.', [
      { name: 'leite com 1 medida de whey', quantity: '200', unit: 'mL' },
    ])
    expect(validateConversationMealInterpretationModel(f.model, f.source).decision).toBe(
      'reported_meal',
    )
    const result = prepared(await materialize(f))
    expect(result.inputs.map((x) => x.calculation_input)).toEqual([
      { food_name: 'leite integral', quantity_g: 206 },
      { food_name: 'whey', quantity_g: 30 },
    ])
    expect(result.inputs[0]?.candidate).toMatchObject({
      count: 200,
      unit_label: 'ml',
      quantity_basis: 'portion_reference',
      needs_review: true,
      quantity_display: { unit: 'mL', grams_per_unit: 1.03 },
    })
    expect(result.inputs[1]?.candidate).toMatchObject({
      quantity_basis: 'portion_reference',
      needs_review: true,
      quantity_display: { unit: 'scoop', grams_per_unit: 30 },
    })
    expect(result.source_groups).toEqual([
      {
        group_index: 0,
        interpretation_food_indexes: [0],
        input_indexes: [0, 1],
        rule: 'mobile_household',
        source_positions: [
          {
            food_index: 0,
            unit: 'command_text',
            name: f.interpretation.foods[0]?.name,
            quantity: f.interpretation.foods[0]?.quantity,
            unit_ref: f.interpretation.foods[0]?.unit,
            visual_index: null,
          },
        ],
      },
    ])
  })
  it.each([
    ['200', 'mL', 'leite com uma dose de whey', 206],
    ['0,2', 'litros', 'leite integral com 1 medida de whey', 206],
    ['125', 'mL', 'leite com 1 medida de whey', 128.75],
  ] as const)('uses existing milk volume and scoop references for %s%s', async (quantity, unit, name, grams) => {
    const f = fixture(`${quantity}${unit} de ${name}`, [{ name, quantity, unit }]),
      result = prepared(await materialize(f))
    expect(result.inputs.map((x) => x.calculation_input.quantity_g)).toEqual([grams, 30])
    expect(result.inputs.every((x) => x.candidate.quantity_basis === 'portion_reference')).toBe(
      true,
    )
    expect(result.source_groups[0]?.rule).toBe('mobile_household')
  })
  it.each([
    'leite com 1 medida de whey 200mL',
    '200mL leite com 1 medida de whey',
    '200mL com leite com 1 medida de whey',
    '200mL da leite com 1 medida de whey',
  ])('does not infer milk volume from an unproven association: %s', async (text) => {
    const f = fixture(text, [{ name: 'leite com 1 medida de whey', quantity: '200', unit: 'mL' }])
    expect(await materialize(f)).toMatchObject({
      status: 'clarification_required',
      reason: 'unsupported_compound_association',
    })
  })
  it.each([
    'leite de coco com 1 medida de whey',
    'leite com 2 medidas de whey',
    'leite marca especial com 1 medida de whey',
  ])('does not invent a household recipe for %s', async (name) => {
    const f = fixture(`200mL de ${name}`, [{ name, quantity: '200', unit: 'mL' }])
    expect(await materialize(f)).toMatchObject({
      status: 'clarification_required',
      reason: 'interpretation_not_positive',
    })
  })
  it.each([
    '0',
    '10000',
  ])('refuses invalid milk volume %smL without producing ingredients', async (quantity) => {
    const name = 'leite com 1 medida de whey',
      f = fixture(`${quantity}mL de ${name}`, [{ name, quantity, unit: 'mL' }])
    expect(await materialize(f)).toMatchObject({ status: 'clarification_required' })
  })
  it.each([
    [{ status: 'active', confirmed_count: 2 }, 'unsupported_compound_association'],
    [{ status: 'active', confirmed_count: 1 }, 'personal_correction_unproven'],
  ] as const)('keeps whole-recipe correction precedence with volume: %j', async (change, reason) => {
    const name = 'leite com 1 medida de whey',
      f = fixture(`200mL de ${name}`, [{ name, quantity: '200', unit: 'mL' }]),
      state = correctionDb([
        correction({ said_name: name, corrected_to: 'shake pessoal', ...change }),
      ])
    expect(await materialize(f, state)).toMatchObject({ status: 'clarification_required', reason })
  })
  it('keeps ignored learning on the whole recipe and active ingredient correction in the actual calculator', async () => {
    const name = 'leite com 1 medida de whey',
      f = fixture(`200mL de ${name}`, [{ name, quantity: '200', unit: 'mL' }]),
      learning = correction({ said_name: name, status: 'learning', confirmed_count: 1 }),
      milk = correction({
        id: ASSET,
        said_name: 'leite integral',
        corrected_to: 'leite pessoal',
        custom_kcal_per_100g: 100,
        custom_protein_g: 10,
        custom_carbs_g: 5,
        custom_fat_g: 2,
      }),
      state = correctionDb([learning, milk]),
      result = prepared(await materialize(f, state))
    expect(result.inputs.map((x) => x.calculation_input.quantity_g)).toEqual([206, 30])
    const calc = await calcMealMacros(
      state.client,
      result.inputs.map((x) => x.calculation_input),
      'BR',
      OWNER,
      {
        consumptionPolicy: 'consumed-meal-v1',
        sourceReader: f.capture.sourceReader,
        auditSink: f.capture.auditSink,
      },
    )
    expect(calc.items[0]).toMatchObject({
      food_name: 'leite pessoal',
      quantity_g: 206,
      kcal: 206,
      protein_g: 20.6,
      source: 'user_correction',
    })
  })
  it('retains each repeated compound and an additional explicit whey occurrence through real calculator merges', async () => {
    const name = 'leite com 1 medida de whey',
      f = fixture(`200mL de ${name}; 200mL de ${name}; whey30g`, [
        { name, quantity: '200', unit: 'mL' },
        { name, quantity: '200', unit: 'mL' },
        { name: 'whey', quantity: '30', unit: 'g' },
      ]),
      catalogs = ['leite integral', 'whey'].map((name, i) => {
        const entry = everydayFoodDefault(name)
        if (!entry) throw new Error('Missing existing food reference')
        return {
          ...row(entry.catalog_name, 91 + i),
          kcal_per_100g: entry.per_100g.kcal,
          protein_g: entry.per_100g.protein_g,
          carbs_g: entry.per_100g.carbs_g,
          fat_g: entry.per_100g.fat_g,
        }
      }),
      state = calculationDb(catalogs),
      result = prepared(await materialize(f, state))
    expect(result.inputs.map((x) => x.calculation_input.quantity_g)).toEqual([206, 30, 206, 30, 30])
    expect(new Set(result.inputs.map((x) => x.candidate.candidate_id)).size).toBe(5)
    expect(
      result.source_groups.map((g) => [g.interpretation_food_indexes, g.input_indexes]),
    ).toEqual([
      [[0], [0, 1]],
      [[1], [2, 3]],
      [[2], [4]],
    ])
    const calc = await calcMealMacros(
      state.client,
      result.inputs.map((x) => x.calculation_input),
      'BR',
      OWNER,
      {
        consumptionPolicy: 'consumed-meal-v1',
        sourceReader: f.capture.sourceReader,
        auditSink: f.capture.auditSink,
      },
    )
    expect(calc.items.map((x) => [x.food_name, x.quantity_g])).toEqual([
      ['leite integral', 412],
      ['whey protein em pó', 90],
    ])
    expect(mapConversationMealCalculationSources(result, calc)).toMatchObject([
      { input_indexes: [0, 2], source_group_indexes: [0, 1], quantity_basis: 'portion_reference' },
      {
        input_indexes: [1, 3, 4],
        source_group_indexes: [0, 1, 2],
        quantity_basis: 'portion_reference',
      },
    ])
  })
  it('refuses expanded milk-volume overflow without dropping the final occurrence', async () => {
    const names = Array.from({ length: 29 }, () => ({ name: 'arroz', quantity: '1', unit: 'g' })),
      name = 'leite com 1 medida de whey'
    const text = `${names.map((x) => `${x.name}${x.quantity}${x.unit}`).join('; ')}; 200mL de ${name}`
    names.push({ name, quantity: '200', unit: 'mL' })
    expect(await materialize(fixture(text, names))).toMatchObject({
      status: 'clarification_required',
      reason: 'item_limit',
      food_indexes: [29],
    })
  })
  it('keeps200g compact total as170g milk+30g whey with one source group', async () => {
    const f = fixture('leite com 1 medida de whey 200g', [
      { name: 'leite com 1 medida de whey', quantity: '200', unit: 'g' },
    ])
    expect(validateConversationMealInterpretationModel(f.model, f.source).decision).toBe(
      'reported_meal',
    )
    const result = prepared(await materialize(f))
    expect(
      result.inputs.map((x) => [
        x.calculation_input.food_name,
        x.calculation_input.quantity_g,
        x.candidate.quantity_basis,
      ]),
    ).toEqual([
      ['leite integral', 170, 'portion_reference'],
      ['whey protein em pó', 30, 'portion_reference'],
    ])
    expect(result.source_groups).toMatchObject([
      { rule: 'milk_whey_total', input_indexes: [0, 1], interpretation_food_indexes: [0] },
    ])
  })
  it('materializes exact full cup recipe using existing206g milk+30g whey references', async () => {
    const f = fixture('1 caneca de leite com 1 medida de whey', [
      { name: '1 caneca de leite com 1 medida de whey' },
    ])
    expect(validateConversationMealInterpretationModel(f.model, f.source).decision).toBe(
      'reported_meal',
    )
    const result = prepared(await materialize(f))
    expect(result.inputs.map((x) => x.calculation_input.quantity_g)).toEqual([206, 30])
    expect(
      result.inputs.every(
        (x) => x.candidate.needs_review && x.candidate.quantity_basis === 'portion_reference',
      ),
    ).toBe(true)
  })
  it.each([
    'Sonhei que comi ',
    'Vou comer ',
    'Não comi ',
    'Costumo comer ',
    'Minha filha comeu ',
    'Ele disse: ',
  ])('does not upgrade recipe framing: %s', async (prefix) => {
    const f = fixture(`${prefix}leite com 1 medida de whey200g`, [
      { name: 'leite com 1 medida de whey', quantity: '200', unit: 'g' },
    ])
    expect(await materialize(f)).toMatchObject({
      status: 'clarification_required',
      reason: 'interpretation_not_positive',
    })
  })
  it('preserves explicit separate milk volume+whey mass, without adding another scoop', async () => {
    const f = fixture('200mL leite; whey30g', [
      { name: 'leite', quantity: '200', unit: 'mL' },
      { name: 'whey', quantity: '30', unit: 'g' },
    ])
    const result = prepared(await materialize(f))
    expect(result.inputs.map((x) => x.calculation_input.quantity_g)).toEqual([206, 30])
    expect(result.inputs[0]?.candidate).toMatchObject({
      count: 200,
      unit_label: 'ml',
      quantity_basis: 'portion_reference',
      quantity_display: { unit: 'mL', grams_per_unit: 1.03 },
    })
    expect(result.inputs[1]?.candidate.quantity_basis).toBe('stated')
    expect(result.source_groups.map((g) => g.input_indexes)).toEqual([[0], [1]])
  })
  it('keeps explicit grams unchanged and unsupported volume missing', async () => {
    const stated = prepared(
      await materialize(fixture('leite200g', [{ name: 'leite', quantity: '200', unit: 'g' }])),
    )
    expect(stated.inputs[0]?.calculation_input.quantity_g).toBe(200)
    const f = fixture('leite de coco200mL', [
      { name: 'leite de coco', quantity: '200', unit: 'mL' },
    ])
    expect(await materialize(f, db(['leite de coco']))).toMatchObject({
      status: 'clarification_required',
      reason: 'unsupported_quantity',
    })
  })
  it('preserves whole180g prepared dish and does not split weight onto its ingredients', async () => {
    const f = fixture('carne desfiada com molho e milho180g', [
      { name: 'carne desfiada com molho e milho', quantity: '180', unit: 'g' },
    ])
    const result = prepared(await materialize(f))
    expect(result.inputs).toHaveLength(1)
    expect(result.inputs[0]?.calculation_input).toEqual({
      food_name: 'carne desfiada com molho e milho',
      quantity_g: 180,
    })
    expect(result.source_groups[0]?.rule).toBe('prepared_dish')
    const unknown = fixture('carne desfiada com molho e ingrediente secreto180g', [
      { name: 'carne desfiada com molho e ingrediente secreto', quantity: '180', unit: 'g' },
    ])
    expect(await materialize(unknown)).toMatchObject({
      status: 'clarification_required',
      reason: 'unqualified_whole_name',
    })
  })
  it('preserves Vision indexes/count/estimated grams without label autoapproval', async () => {
    const f = visualFixture([
      { name: '2x ovo', quantity_g_estimate: 100, confidence: 0.9 },
      { name: 'arroz', quantity_g_estimate: 150, confidence: 0.8 },
    ])
    const result = prepared(await materialize(f, db(['ovo'])))
    expect(result.inputs.map((x) => x.calculation_input.quantity_g)).toEqual([100, 150])
    expect(result.source_groups.map((g) => g.source_positions[0]?.visual_index)).toEqual([0, 1])
    expect(result.inputs[0]?.candidate).toMatchObject({
      count: 2,
      quantity_basis: 'visual_estimate',
      needs_review: true,
    })
    expect(result.nutrition_label).toMatchObject({ product_name: 'arroz', serving_size_g: 100 })
    expect(result.inputs.every((x) => !('approved_nutrition' in x.calculation_input))).toBe(true)
  })
  it.each([
    0, 0.3,
  ])('refuses missing/low-confidence Vision quantity instead of dropping item (%s)', async (confidence) => {
    const f = visualFixture([
      { name: 'arroz', quantity_g_estimate: confidence === 0 ? 0 : 100, confidence },
    ])
    expect(await materialize(f)).toMatchObject({
      status: 'clarification_required',
      reason: confidence === 0 ? 'missing_quantity' : 'low_confidence',
      food_indexes: [0],
    })
  })
  it('refuses invalid/omitted visual items, conflicting caption and wrong source binding', async () => {
    const f = visualFixture(
      [{ name: 'arroz', quantity_g_estimate: 100, confidence: 0.9 }],
      'Não comi',
    )
    expect(await materialize(f)).toMatchObject({
      status: 'clarification_required',
      reason: 'interpretation_not_positive',
    })
    const omitted = visualFixture([
      { name: 'arroz', quantity_g_estimate: 100, confidence: 0.9 },
      { name: '', quantity_g_estimate: 100, confidence: 0.9 },
    ])
    omitted.interpretation.foods.pop()
    await expect(materialize(omitted)).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
    const changed = fixture('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }])
    changed.interpretation.source_hash = 'b'.repeat(64)
    await expect(materialize(changed)).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
  })
  it('does not infer missing portions or allow expanded item overflow', async () => {
    expect(
      await materialize(fixture('banana', [{ name: 'banana' }]), db(['banana'])),
    ).toMatchObject({ status: 'clarification_required', reason: 'missing_quantity' })
    const names = Array.from({ length: 29 }, () => ({ name: 'arroz', quantity: '1', unit: 'g' }))
    names.push({ name: 'leite com 1 medida de whey', quantity: '200', unit: 'g' })
    const f = fixture(names.map((x) => `${x.name}${x.quantity}${x.unit}`).join('; '), names)
    expect(await materialize(f)).toMatchObject({
      status: 'clarification_required',
      reason: 'item_limit',
    })
  })
  it('fails closed/redacted on catalog failure and malformed rows rather than treating as a miss', async () => {
    const f = fixture('goiaba100g', [{ name: 'goiaba', quantity: '100', unit: 'g' }]),
      state = db()
    state.rpc.mockRejectedValueOnce(new Error('private-token'))
    await expect(materialize(f, state)).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
    state.rpc.mockResolvedValueOnce({
      data: [{ ...row('goiaba'), kcal_per_100g: Infinity }],
      error: null,
    })
    await expect(materialize(f, state)).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
  })
  it.each([
    20, 30,
  ])('refuses compact total%s even if a whole catalog row exists; never adds a dose', async (grams) => {
    const name = 'leite com 1 medida de whey',
      f = fixture(`${name}${grams}g`, [{ name, quantity: String(grams), unit: 'g' }])
    expect(await materialize(f, db([name]))).toMatchObject({
      status: 'clarification_required',
      reason: 'unsupported_compound_association',
    })
  })
  it('does not clamp invalid visual confidence into accepted evidence', async () => {
    const f = visualFixture([{ name: 'arroz', quantity_g_estimate: 100, confidence: 1.5 }])
    expect(await materialize(f)).toMatchObject({
      status: 'clarification_required',
      reason: 'low_confidence',
    })
  })
  it('preserves complete identities rather than a cleaned prefix and converts existing quantity aliases once', async () => {
    const changed = fixture('de banana100g', [{ name: 'de banana', quantity: '100', unit: 'g' }])
    expect(await materialize(changed, db(['de banana']))).toMatchObject({
      status: 'clarification_required',
      reason: 'ambiguous_source_group',
    })
    const f = fixture('leite0,2litros; whey1scoop', [
      { name: 'leite', quantity: '0,2', unit: 'litros' },
      { name: 'whey', quantity: '1', unit: 'scoop' },
    ])
    const result = prepared(await materialize(f))
    expect(result.inputs.map((x) => x.calculation_input.quantity_g)).toEqual([206, 30])
    expect(
      result.inputs.every(
        (x) => x.candidate.quantity_basis === 'portion_reference' && x.candidate.needs_review,
      ),
    ).toBe(true)
  })
  it('binds source, result, policy and RPC callback before any catalog await', async () => {
    const f = fixture('goiaba100g; pera50g', [
      { name: 'goiaba', quantity: '100', unit: 'g' },
      { name: 'pera', quantity: '50', unit: 'g' },
    ])
    let finish!: (value: { data: ReturnType<typeof row>[]; error: null }) => void
    const state = db(),
      first = new Promise<{ data: ReturnType<typeof row>[]; error: null }>((resolve) => {
        finish = resolve
      })
    state.rpc
      .mockImplementationOnce(() => first)
      .mockResolvedValueOnce({ data: [row('pera')], error: null })
    const policy = { confidenceThreshold: 0.6 },
      pending = materializeConversationMealInterpretation(
        state.client,
        f.command,
        f.capture,
        f.interpretation,
        policy,
      )
    Object.assign(f.capture.context.owner, { country: 'XX' })
    Object.assign(at(f.interpretation.foods, 1), { name: at(f.interpretation.foods).name })
    policy.confidenceThreshold = NaN
    const replacement = vi.fn()
    Object.assign(state.client, { rpc: replacement })
    finish({ data: [row('goiaba')], error: null })
    const result = prepared(await pending)
    expect(result.inputs.map((x) => x.calculation_input)).toEqual([
      { food_name: 'goiaba', quantity_g: 100 },
      { food_name: 'pera', quantity_g: 50 },
    ])
    expect(state.rpc).toHaveBeenCalledTimes(2)
    expect(replacement).not.toHaveBeenCalled()
  })
  it('feeds the actual shared calculator and composes its real default merge map without writes', async () => {
    const f = fixture('leite100g; arroz100g; leite200mL', [
      { name: 'leite', quantity: '100', unit: 'g' },
      { name: 'arroz', quantity: '100', unit: 'g' },
      { name: 'leite', quantity: '200', unit: 'mL' },
    ])
    const catalogs = ['leite', 'arroz'].map((name) => {
      const entry = consumedFoodDefault(name, 'BR') ?? everydayFoodDefault(name)
      if (!entry) throw new Error('default')
      return {
        ...row(entry.catalog_name),
        kcal_per_100g: entry.per_100g.kcal,
        protein_g: entry.per_100g.protein_g,
        carbs_g: entry.per_100g.carbs_g,
        fat_g: entry.per_100g.fat_g,
      }
    })
    const state = calculationDb(catalogs),
      result = prepared(await materialize(f, state))
    const calc = await calcMealMacros(
      state.client,
      result.inputs.map((i) => i.calculation_input),
      'BR',
      OWNER,
      {
        consumptionPolicy: 'consumed-meal-v1',
        preparationAnnotations: 'consumed.preparation.v1',
        sourceReader: f.capture.sourceReader,
        auditSink: f.capture.auditSink,
      },
    )
    expect(calc.input_indexes).toEqual([[0, 2], [1]])
    expect(calc.items.map((i) => i.quantity_g)).toEqual([306, 100])
    expect(mapConversationMealCalculationSources(result, calc)).toMatchObject([
      { input_indexes: [0, 2], source_group_indexes: [0, 2], quantity_basis: 'portion_reference' },
      { input_indexes: [1], source_group_indexes: [1], quantity_basis: 'stated' },
    ])
    expect(calc.preparation_annotations).toMatchObject([
      { input_indexes: [1], kind: 'default_cooked' },
    ])
    expect(state.tables.every((table) => table === 'user_food_corrections')).toBe(true)
  })
  it('keeps actual shared prepared-dish calculation as a whole editable estimate', async () => {
    const f = fixture('carne desfiada com molho e milho180g', [
        { name: 'carne desfiada com molho e milho', quantity: '180', unit: 'g' },
      ]),
      state = calculationDb([]),
      result = prepared(await materialize(f, state)),
      inputs = result.inputs.map((i) => i.calculation_input)
    const calc = await calcMealMacros(state.client, inputs, 'BR', OWNER, {
      consumptionPolicy: 'consumed-meal-v1',
      sourceReader: f.capture.sourceReader,
      auditSink: f.capture.auditSink,
    })
    const estimate = applyMobilePreparedDishEstimate(calc, inputs, 'mobile_app', 'pt-BR')
    expect(estimate.items).toMatchObject([{ quantity_g: 180, source: 'llm_estimate', kcal: 270 }])
    expect(estimate.user_warnings.join(' ')).toContain('aproximados')
    expect(mapConversationMealCalculationSources(result, estimate)[0]?.input_indexes).toEqual([0])
    expect(result.source_groups[0]?.source_positions[0]?.name).toEqual(
      f.interpretation.foods[0]?.name,
    )
  })
  it('preserves an owned active custom correction before the actual shared calculation', async () => {
    const f = fixture('geleia da casa50g', [{ name: 'geleia da casa', quantity: '50', unit: 'g' }]),
      state = correctionDb([correction()])
    const result = prepared(await materialize(f, state))
    expect(result.inputs[0]?.calculation_input).toEqual({
      food_name: 'geleia da casa',
      quantity_g: 50,
    })
    const calc = await calcMealMacros(
      state.client,
      result.inputs.map((i) => i.calculation_input),
      'BR',
      OWNER,
      {
        consumptionPolicy: 'consumed-meal-v1',
        sourceReader: f.capture.sourceReader,
        auditSink: f.capture.auditSink,
      },
    )
    expect(calc.items).toMatchObject([
      {
        food_name: 'geleia caseira',
        source: 'user_correction',
        quantity_g: 50,
        kcal: 40,
        protein_g: 0,
        carbs_g: 10,
        fat_g: 0,
      },
    ])
  })
  it('preserves an active exact remap through verified destination and actual calculator', async () => {
    const f = fixture('batata da casa100g', [
        { name: 'batata da casa', quantity: '100', unit: 'g' },
      ]),
      state = correctionDb(
        [
          correction({
            said_name: 'batata da casa',
            corrected_to: 'mandioca',
            custom_kcal_per_100g: null,
            custom_carbs_g: null,
          }),
        ],
        ['mandioca'],
      )
    const result = prepared(await materialize(f, state))
    expect(result.inputs[0]?.calculation_input.food_name).toBe('batata da casa')
    expect(state.calls.every((call) => call.method !== 'or')).toBe(true)
    const calc = await calcMealMacros(
      state.client,
      result.inputs.map((i) => i.calculation_input),
      'BR',
      OWNER,
      {
        sourceReader: f.capture.sourceReader,
        auditSink: f.capture.auditSink,
        consumptionPolicy: 'consumed-meal-v1',
      },
    )
    expect(calc.items[0]).toMatchObject({
      food_name: 'mandioca',
      quantity_g: 100,
      matched_taco_id: 91,
    })
    expect(state.calls.filter((call) => call.method === 'gte')[0]?.args).toEqual([
      'last_seen',
      '2026-10-06T01:00:00.000Z',
    ])
  })
  it('also qualifies exact corrected_to input without pre-rewriting the calculator name', async () => {
    const f = fixture('geleia caseira50g', [{ name: 'geleia caseira', quantity: '50', unit: 'g' }]),
      state = correctionDb([correction()])
    expect(prepared(await materialize(f, state)).inputs[0]?.calculation_input.food_name).toBe(
      'geleia caseira',
    )
    expect(
      state.calls.some(
        (call) =>
          call.method === 'eq' &&
          call.args[0] === 'corrected_to' &&
          call.args[1] === 'geleia caseira',
      ),
    ).toBe(true)
  })
  it.each([
    { status: 'learning', confirmed_count: 1 },
    { status: 'active', confirmed_count: 1 },
  ])('clarifies unproven correction approval %j', async (change) => {
    const f = fixture('geleia da casa50g', [{ name: 'geleia da casa', quantity: '50', unit: 'g' }])
    expect(await materialize(f, correctionDb([correction(change)]))).toMatchObject({
      status: 'clarification_required',
      reason: 'personal_correction_unproven',
    })
  })
  it.each([
    { status: 'retired' },
    { last_seen: '2026-10-01T00:00:00Z' },
  ])('does not revive retired/stale aliases %j', async (change) => {
    const f = fixture('geleia da casa50g', [{ name: 'geleia da casa', quantity: '50', unit: 'g' }])
    expect(await materialize(f, correctionDb([correction(change)]))).toMatchObject({
      status: 'clarification_required',
    })
  })
  it('selects latest learning before checking approval, not an older active mapping', async () => {
    const f = fixture('geleia caseira50g', [{ name: 'geleia caseira', quantity: '50', unit: 'g' }])
    const old = correction(),
      recent = correction({
        id: ASSET,
        said_name: 'outra geleia',
        status: 'learning',
        confirmed_count: 1,
        last_seen: '2026-11-04T13:00:00Z',
      })
    expect(await materialize(f, correctionDb([old, recent]))).toMatchObject({
      status: 'clarification_required',
      reason: 'personal_correction_unproven',
    })
  })
  it.each([
    { user_id: ASSET },
    { last_seen: '2026-11-05T01:00:00.000002Z' },
    { last_seen: '2026-02-30T12:00:00Z' },
    { custom_kcal_per_100g: Infinity },
  ])('refuses corrupt/unbound/future correction rows %j', async (change) => {
    const f = fixture('geleia da casa50g', [{ name: 'geleia da casa', quantity: '50', unit: 'g' }])
    await expect(
      materialize(f, correctionDb([correction(change)], [], true)),
    ).rejects.toMatchObject({ code: 'conversation_meal_materialization_unavailable' })
  })
  it('refuses equal-time competing winners rather than inventing a tie-breaker', async () => {
    const f = fixture('geleia caseira50g', [{ name: 'geleia caseira', quantity: '50', unit: 'g' }])
    await expect(
      materialize(
        f,
        correctionDb([correction(), correction({ id: ASSET, said_name: 'outra geleia' })]),
      ),
    ).rejects.toMatchObject({ code: 'conversation_meal_materialization_unavailable' })
  })
  it('does not turn incomplete remap or invalid custom nutrition into a fuzzy alias', async () => {
    const f = fixture('geleia da casa50g', [{ name: 'geleia da casa', quantity: '50', unit: 'g' }])
    for (const change of [
      { corrected_to: 'arroz estranho', custom_kcal_per_100g: null },
      { custom_kcal_per_100g: -1 },
      { custom_kcal_per_100g: 1000 },
    ])
      expect(await materialize(f, correctionDb([correction(change)]))).toMatchObject({
        status: 'clarification_required',
        reason: 'personal_correction_unproven',
      })
  })
  it('requires the bound frozen clock and rejects correction outages without fallback', async () => {
    const f = fixture('geleia da casa50g', [{ name: 'geleia da casa', quantity: '50', unit: 'g' }])
    Object.assign(f.capture.sourceReader, { ownerId: ASSET })
    await expect(materialize(f, correctionDb([correction()]))).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
    const other = fixture('geleia da casa50g', [
      { name: 'geleia da casa', quantity: '50', unit: 'g' },
    ])
    Object.assign(other.capture.sourceReader, { asOf: '2026-11-06T01:00:00Z' })
    await expect(materialize(other, correctionDb([correction()]))).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
    const state = correctionDb([])
    state.from.mockImplementation(() => {
      throw new Error('private-correction-token')
    })
    const clean = fixture('geleia da casa50g', [
      { name: 'geleia da casa', quantity: '50', unit: 'g' },
    ])
    await expect(materialize(clean, state)).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
  })
  it('captures actual read callback and never interpolates raw filter delimiters', async () => {
    const state = correctionDb([correction()]),
      read = createBoundConversationMealCorrectionReader(state.client, {
        ownerId: OWNER,
        asOf: '2026-11-05T01:00:00.000001Z',
      })
    const replacement = vi.fn()
    Object.assign(state.client, { from: replacement })
    expect(await read('geleia da casa')).toMatchObject({
      status: 'active',
      row: { corrected_to: 'geleia caseira' },
    })
    expect(replacement).not.toHaveBeenCalled()
    expect(state.calls.every((call) => call.method !== 'or')).toBe(true)
    await expect(read('geleia,corrected_to.neq.x')).rejects.toBeInstanceOf(Error)
  })
  it('ignores learning correction for an already qualified original food exactly as shared calculation does', async () => {
    const f = fixture('arroz200g', [{ name: 'arroz', quantity: '200', unit: 'g' }]),
      state = correctionDb([
        correction({
          said_name: 'arroz',
          corrected_to: 'batata',
          status: 'learning',
          confirmed_count: 1,
        }),
      ])
    const result = prepared(await materialize(f, state))
    expect(result.inputs[0]?.calculation_input).toEqual({ food_name: 'arroz', quantity_g: 200 })
  })
  it('gives approved whole recipe correction precedence over component expansion and reaches actual calc', async () => {
    const name = 'leite com 1 medida de whey',
      f = fixture(`${name}200g`, [{ name, quantity: '200', unit: 'g' }]),
      state = correctionDb([
        correction({
          said_name: name,
          corrected_to: 'shake pessoal',
          custom_kcal_per_100g: 100,
          custom_protein_g: 10,
          custom_carbs_g: 5,
          custom_fat_g: 2,
        }),
      ])
    const result = prepared(await materialize(f, state))
    expect(result.inputs.map((i) => i.calculation_input)).toEqual([
      { food_name: name, quantity_g: 200 },
    ])
    const calc = await calcMealMacros(
      state.client,
      result.inputs.map((i) => i.calculation_input),
      'BR',
      OWNER,
      { sourceReader: f.capture.sourceReader, auditSink: f.capture.auditSink },
    )
    expect(calc.items).toMatchObject([
      {
        food_name: 'shake pessoal',
        source: 'user_correction',
        quantity_g: 200,
        kcal: 200,
        protein_g: 20,
      },
    ])
  })
  it('preserves an approved measured whole cup correction but never fabricates its missing whole mass', async () => {
    const name = '1 caneca de leite com 1 medida de whey',
      state = correctionDb([correction({ said_name: name, corrected_to: 'shake pessoal' })])
    const measured = fixture(`${name}200g`, [{ name, quantity: '200', unit: 'g' }])
    expect(
      prepared(await materialize(measured, state)).inputs.map((i) => i.calculation_input),
    ).toEqual([{ food_name: name, quantity_g: 200 }])
    expect(await materialize(fixture(name, [{ name }]), state)).toMatchObject({
      status: 'clarification_required',
      reason: 'unsupported_compound_association',
    })
  })
  it('keeps explicit custom zero and ordinary recipe expansion under ignored learning', async () => {
    const f = fixture('geleia da casa50g', [{ name: 'geleia da casa', quantity: '50', unit: 'g' }]),
      state = correctionDb([correction({ custom_kcal_per_100g: 0, custom_carbs_g: null })])
    expect(prepared(await materialize(f, state)).inputs[0]?.calculation_input).toEqual({
      food_name: 'geleia da casa',
      quantity_g: 50,
    })
    const name = 'leite com 1 medida de whey',
      recipe = fixture(`${name}200g`, [{ name, quantity: '200', unit: 'g' }])
    const result = prepared(
      await materialize(
        recipe,
        correctionDb([correction({ said_name: name, status: 'learning', confirmed_count: 1 })]),
      ),
    )
    expect(result.inputs.map((i) => i.calculation_input.quantity_g)).toEqual([170, 30])
  })
  it('maps shared merges back to all expanded inputs/original groups with least precise basis', async () => {
    const f = fixture('leite100g; arroz100g; leite200mL', [
      { name: 'leite', quantity: '100', unit: 'g' },
      { name: 'arroz', quantity: '100', unit: 'g' },
      { name: 'leite', quantity: '200', unit: 'mL' },
    ])
    const result = prepared(await materialize(f))
    const calc = { items: [{}, {}], input_indexes: [[0, 2], [1]] } as MealCalcResult
    const metadata = mapConversationMealCalculationSources(result, calc)
    expect(metadata).toMatchObject([
      { input_indexes: [0, 2], source_group_indexes: [0, 2], quantity_basis: 'portion_reference' },
      { input_indexes: [1], source_group_indexes: [1], quantity_basis: 'stated' },
    ])
    expect(metadata[0]).not.toHaveProperty('candidate_id')
    expect(metadata[1]?.candidate_id).toBe(result.inputs[1]?.candidate.candidate_id)
    expect(() =>
      mapConversationMealCalculationSources(result, { ...calc, input_indexes: [[0], [1]] }),
    ).toThrow()
    expect(() =>
      mapConversationMealCalculationSources(result, { ...calc, input_indexes: undefined }),
    ).toThrow()
    expect(() =>
      mapConversationMealCalculationSources(result, {
        ...calc,
        input_indexes: [
          [0, 2],
          [0, 1],
        ],
      }),
    ).toThrow()
  })
})

function calculationDb(catalogs: ReturnType<typeof row>[]) {
  const state = db(),
    tables: string[] = []
  state.rpc.mockImplementation(async (_name, params) => ({
    data: catalogs.filter((item) => item.name_pt.toLowerCase() === params.search_term),
    error: null,
  }))
  Object.assign(state.client, {
    from(table: string) {
      tables.push(table)
      if (table !== 'user_food_corrections') throw new Error(`Unexpected table read/write ${table}`)
      const result = Promise.resolve({ data: [], error: null })
      const chain = Object.assign(result, {
        select: () => result,
        eq: () => result,
        or: () => result,
        neq: () => result,
        gte: () => result,
        order: () => result,
        limit: () => result,
      })
      return chain
    },
  })
  return { ...state, tables }
}

function correction(change: Partial<Correction> = {}): Correction {
  return {
    id: '10000000-0000-4000-8000-000000000099',
    user_id: OWNER,
    said_name: 'geleia da casa',
    corrected_to: 'geleia caseira',
    status: 'active',
    confirmed_count: 2,
    last_seen: '2026-11-04T12:00:00Z',
    custom_kcal_per_100g: 80,
    custom_protein_g: null,
    custom_carbs_g: 20,
    custom_fat_g: null,
    ...change,
  }
}
type Correction = {
  id: string
  user_id: string
  said_name: string
  corrected_to: string
  status: string
  confirmed_count: number
  last_seen: string
  custom_kcal_per_100g: number | null
  custom_protein_g: number | null
  custom_carbs_g: number | null
  custom_fat_g: number | null
}
function correctionDb(rows: Correction[], names: string[] = [], raw = false) {
  const state = db(names),
    calls: Array<{ method: string; args: unknown[] }> = []
  const from = vi.fn((table: string) => {
    if (table !== 'user_food_corrections') throw new Error('unexpected table')
    const filters: Array<(row: Correction) => boolean> = []
    let count = 100
    const result = Promise.resolve().then(() => ({
      data: rows
        .filter((row) => raw || filters.every((fn) => fn(row)))
        .sort((a, b) => Date.parse(b.last_seen) - Date.parse(a.last_seen))
        .slice(0, count),
      error: null,
    }))
    const query = Object.assign(result, {} as Record<string, unknown>)
    query.select = (...args: unknown[]) => {
      calls.push({ method: 'select', args })
      return query
    }
    query.eq = (field: keyof Correction, value: unknown) => {
      calls.push({ method: 'eq', args: [field, value] })
      filters.push((row) => row[field] === value)
      return query
    }
    query.neq = (field: keyof Correction, value: unknown) => {
      calls.push({ method: 'neq', args: [field, value] })
      filters.push((row) => row[field] !== value)
      return query
    }
    query.gte = (field: keyof Correction, value: string) => {
      calls.push({ method: 'gte', args: [field, value] })
      filters.push((row) => Date.parse(String(row[field])) >= Date.parse(value))
      return query
    }
    query.order = (...args: unknown[]) => {
      calls.push({ method: 'order', args })
      return query
    }
    query.limit = (value: number) => {
      count = value
      calls.push({ method: 'limit', args: [value] })
      return query
    }
    query.or = (value: string) => {
      calls.push({ method: 'or', args: [value] })
      const match = /^said_name\.eq\.(.*),corrected_to\.eq\.(.*)$/u.exec(value)
      if (!match) throw new Error('unsafe legacy filter')
      filters.push((row) => row.said_name === match[1] || row.corrected_to === match[2])
      return query
    }
    return query
  })
  Object.assign(state.client, { from })
  return { ...state, from, calls }
}

function continuationFixture<
  T extends ReturnType<typeof fixture> | ReturnType<typeof visualFixture>,
>(f: T) {
  Object.assign(f.capture.context.day, { date: '2026-11-04', day_closed: false })
  const resolution: CapturedConversationMealSource = {
    ...f.capture,
    sourceHash: 'b'.repeat(64),
    capturedAt: '2026-11-05T02:00:00.000002Z',
    context: structuredClone(f.capture.context),
    sourceReader: { ...f.capture.sourceReader, asOf: '2026-11-05T02:00:00.000002Z' },
  }
  return { ...f, resolution }
}
function quantityReply(name: string, foodIndex = 0, amount = 200, unit = 'g', id = ASSET) {
  const ref = mobileQuantityDisplay(name),
    units = ['g', 'kg']
  if (ref?.unit === 'mL') {
    units.push('mL', 'L')
    if (ref.reference_id === 'fao-infoods-v2-whole-milk-tb') units.push('caneca')
  } else if (ref) units.push(ref.unit)
  return {
    replyId: id,
    input: {
      schema: 'conversation.meal-clarification.v1',
      expected_revision: foodIndex,
      question_key: 'e'.repeat(64),
      answer: { kind: 'quantity', food_index: foodIndex, amount, unit },
    },
    question: {
      schema: 'conversation.meal-question.v1',
      question_key: 'e'.repeat(64),
      revision: foodIndex,
      kind: 'quantity',
      food_index: foodIndex,
      food_name: name,
      allowed_units: units,
      quantity_reference: ref,
    },
  }
}
function continueMeal(
  f: ReturnType<typeof continuationFixture>,
  answers: unknown[],
  state: { client: ServiceClient } = db(),
  policy = options,
) {
  return materializeConversationMealContinuation(
    state.client,
    f.command,
    f.capture,
    f.interpretation,
    policy,
    { resolutionSource: f.resolution, quantityAnswers: answers },
  )
}

describe('separate linked missing quantity overlay', () => {
  it('continues the catalogue-comma quantity question through the unchanged shared calculator', async () => {
    const f = continuationFixture(fixture('iogurte natural', [{ name: 'iogurte natural' }])),
      state = calculationDb([row('Iogurte, natural', 597)])
    // This scenario reproduces the actual trigram RPC returning the comma
    // spelling for the unpunctuated search; the generic fixture is exact-only.
    state.rpc.mockResolvedValue({ data: [row('Iogurte, natural', 597)], error: null })
    expect(await materialize(f, state)).toMatchObject({ reason: 'missing_quantity' })
    const result = await continueMeal(f, [quantityReply('iogurte natural')], state),
      material = prepared(result.materialization)
    expect(material.inputs.map((i) => i.calculation_input)).toEqual([
      { food_name: 'iogurte natural', quantity_g: 200 },
    ])
    const calc = await calcMealMacros(
      state.client,
      material.inputs.map((i) => i.calculation_input),
      'BR',
      OWNER,
      {
        consumptionPolicy: 'consumed-meal-v1',
        sourceReader: f.capture.sourceReader,
        auditSink: f.capture.auditSink,
      },
    )
    expect(calc.items).toMatchObject([
      { matched_taco_id: 597, quantity_g: 200, kcal: 200, protein_g: 20, carbs_g: 20, fat_g: 4 },
    ])
    expect(calc.totals).toMatchObject({ kcal: 200, protein_g: 20, carbs_g: 20, fat_g: 4 })
    expect(state.tables.every((table) => table === 'user_food_corrections')).toBe(true)
  })
  it('applies rice answer and preserves beans, original source/model bytes and source positions', async () => {
    const f = continuationFixture(
      fixture('arroz; feijão100g', [
        { name: 'arroz' },
        { name: 'feijão', quantity: '100', unit: 'g' },
      ]),
    )
    const before = structuredClone(f.interpretation),
      answer = quantityReply('arroz')
    expect(await materialize(f)).toMatchObject({
      status: 'clarification_required',
      reason: 'missing_quantity',
      food_indexes: [0],
    })
    const result = await continueMeal(f, [answer]),
      material = prepared(result.materialization)
    expect(material.inputs.map((i) => i.calculation_input)).toEqual([
      { food_name: 'arroz', quantity_g: 200 },
      { food_name: 'feijão', quantity_g: 100 },
    ])
    expect(material).toMatchObject({
      input_hash: f.command.inputHash,
      source_hash: f.capture.sourceHash,
      attempt_id: ATTEMPT,
    })
    expect(material.source_groups[0]?.rule).toBe('literal')
    expect(material.source_groups[0]?.source_positions[0]).toMatchObject({
      name: f.interpretation.foods[0]?.name,
      quantity: null,
      unit_ref: null,
    })
    expect(f.interpretation).toEqual(before)
    expect(result.quantity_witnesses).toEqual([
      {
        reply_id: ASSET,
        food_index: 0,
        amount: 200,
        unit: 'g',
        quantity_g: 200,
        quantity_basis: 'stated',
        quantity_display: null,
        input_indexes: [0],
      },
    ])
    expect(Object.isFrozen(result.quantity_witnesses[0]?.input_indexes)).toBe(true)
  })
  it('returns no invented partial input slots, then actual mapping after both answers', async () => {
    const f = continuationFixture(
        fixture('arroz; feijão', [{ name: 'arroz' }, { name: 'feijão' }]),
      ),
      first = quantityReply('arroz'),
      second = quantityReply('feijão', 1, 100, 'g', COMMAND)
    expect((await continueMeal(f, [])).quantity_witnesses).toEqual([])
    const partial = await continueMeal(f, [first])
    expect(partial.materialization).toEqual({
      status: 'clarification_required',
      reason: 'missing_quantity',
      food_indexes: [1],
    })
    expect(partial.quantity_witnesses[0]?.input_indexes).toEqual([])
    const complete = await continueMeal(f, [first, second])
    expect(complete.quantity_witnesses.map((w) => w.input_indexes)).toEqual([[0], [1]])
    expect(
      prepared(complete.materialization).inputs.map((i) => i.calculation_input.quantity_g),
    ).toEqual([200, 100])
  })
  it('retains reference metadata without adding source text refs or replacing the original rule', async () => {
    const f = continuationFixture(fixture('leite; whey', [{ name: 'leite' }, { name: 'whey' }]))
    const result = await continueMeal(f, [
      quantityReply('leite', 0, 200, 'mL'),
      quantityReply('whey', 1, 1.5, 'scoop', COMMAND),
    ])
    expect(
      prepared(result.materialization).inputs.map((i) => [
        i.calculation_input.quantity_g,
        i.candidate.quantity_basis,
        i.candidate.needs_review,
      ]),
    ).toEqual([
      [206, 'portion_reference', true],
      [45, 'portion_reference', true],
    ])
    expect(result.quantity_witnesses[0]?.quantity_display).toEqual(mobileQuantityDisplay('leite'))
    expect(prepared(result.materialization).source_groups.map((g) => g.rule)).toEqual([
      'literal',
      'literal',
    ])
    expect(
      prepared(result.materialization).source_groups.every(
        (g) => g.source_positions[0]?.quantity === null,
      ),
    ).toBe(true)
  })
  it.each([
    'wrong-name',
    'wrong-target',
    'explicit',
    'duplicate-food',
    'duplicate-reply',
    'extra',
    'meal-type',
    'unapplied-later',
  ])('refuses invalid/unapplied answer %s', async (attack) => {
    const explicit = attack === 'explicit',
      f = continuationFixture(
        fixture(
          explicit ? 'arroz100g; feijão' : 'arroz; feijão',
          explicit
            ? [{ name: 'arroz', quantity: '100', unit: 'g' }, { name: 'feijão' }]
            : [{ name: 'arroz' }, { name: 'feijão' }],
        ),
      )
    const a = quantityReply('arroz'),
      b = quantityReply('feijão', 1, 100, 'g', COMMAND),
      state = db()
    let answers: unknown[] = [a]
    if (attack === 'wrong-name') a.question.food_name = 'feijão'
    if (attack === 'wrong-target') {
      a.input.answer.food_index = 2
      a.question.food_index = 2
    }
    if (attack === 'duplicate-food') answers = [a, { ...a, replyId: COMMAND }]
    if (attack === 'duplicate-reply') answers = [a, { ...b, replyId: ASSET }]
    if (attack === 'extra') answers = [{ ...a, owner_id: OWNER }]
    if (attack === 'meal-type')
      answers = [
        {
          ...a,
          input: { ...a.input, answer: { kind: 'meal_type', meal_type: 'cafe' } },
          question: {
            ...a.question,
            kind: 'meal_type',
            food_index: null,
            food_name: null,
            quantity_reference: null,
            allowed_units: [],
          },
        },
      ]
    if (attack === 'unapplied-later') answers = [b]
    await expect(continueMeal(f, answers, state)).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
    if (attack !== 'unapplied-later') {
      expect(state.rpc).not.toHaveBeenCalled()
      expect(state.from).not.toHaveBeenCalled()
    }
  })
  it('refuses exact expanded cup/ambiguous compact recipe answers instead of overwriting portions', async () => {
    for (const name of ['1 caneca de leite com 1 medida de whey', 'leite com 1 medida de whey']) {
      const f = continuationFixture(fixture(name, [{ name }]))
      await expect(continueMeal(f, [quantityReply(name)])).rejects.toMatchObject({
        code: 'conversation_meal_materialization_unavailable',
      })
    }
  })
  it('uses fresh correction cutoff while original interpretation remains bound to old capture', async () => {
    const f = continuationFixture(fixture('geleia da casa', [{ name: 'geleia da casa' }])),
      state = correctionDb([correction({ last_seen: '2026-11-05T01:30:00.000001Z' })])
    const result = await continueMeal(f, [quantityReply('geleia da casa', 0, 50)], state)
    expect(prepared(result.materialization).inputs[0]?.calculation_input).toEqual({
      food_name: 'geleia da casa',
      quantity_g: 50,
    })
    expect(result.materialization).toMatchObject({ source_hash: f.capture.sourceHash })
    expect(
      state.calls
        .filter((c) => c.method === 'gte')
        .every((c) => c.args[1] === '2026-10-06T02:00:00.000Z'),
    ).toBe(true)
    expect(f.capture.sourceReader.asOf).toBe('2026-11-05T01:00:00.000001Z')
    expect(f.resolution.sourceReader.asOf).toBe('2026-11-05T02:00:00.000002Z')
  })
  it.each([
    'owner',
    'epoch',
    'day',
    'empty-day',
    'zone',
    'country',
    'locale',
    'source-input',
    'source-units',
    'source-evidence',
    'original-reader',
    'fresh-reader',
    'fresh-clock',
  ])('refuses crossed %s before querying', async (attack) => {
    const f = continuationFixture(fixture('arroz', [{ name: 'arroz' }])),
      state = db()
    const c = f.resolution.context
    if (attack === 'owner') Object.assign(c, { owner_id: ASSET })
    if (attack === 'epoch') Object.assign(f.resolution, { epoch: ASSET })
    if (attack === 'day') c.day.date = '2026-11-05'
    if (attack === 'empty-day') {
      delete c.day.date
      delete f.capture.context.day.date
    }
    if (attack === 'zone') c.owner.timezone = 'UTC'
    if (attack === 'country') c.owner.country = 'US'
    if (attack === 'locale') c.owner.locale = 'en-US'
    if (attack === 'source-input') Object.assign(c.source_input.source, { text: 'feijão' })
    if (attack === 'source-units') Object.assign(c, { source_units: ['vision_items'] })
    if (attack === 'source-evidence')
      Object.assign(c, { source_evidence: { transcript: 'changed' } })
    if (attack === 'original-reader') Object.assign(f.capture.sourceReader, { ownerId: ASSET })
    if (attack === 'fresh-reader') Object.assign(f.resolution.sourceReader, { ownerId: ASSET })
    if (attack === 'fresh-clock')
      Object.assign(f.resolution.sourceReader, { asOf: f.capture.capturedAt })
    await expect(continueMeal(f, [quantityReply('arroz')], state)).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
    expect(state.rpc).not.toHaveBeenCalled()
    expect(state.from).not.toHaveBeenCalled()
  })
  it('rejects media drift before querying and preserves explicit resolved visual mass', async () => {
    const f = continuationFixture(
        visualFixture([{ name: 'arroz', quantity_g_estimate: null, confidence: 0.9 }]),
      ),
      state = db()
    const media = f.resolution.context.media
    if (!media) throw new Error('missing media')
    media.updated_at = '2026-11-05T01:10:00Z'
    await expect(continueMeal(f, [quantityReply('arroz')], state)).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
    expect(state.from).not.toHaveBeenCalled()
    const resolved = continuationFixture(
      visualFixture([{ name: 'arroz', quantity_g_estimate: 100, confidence: 0.9 }]),
    )
    await expect(continueMeal(resolved, [quantityReply('arroz')])).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
  })
  it('applies only qualified confident missing visual quantity with unchanged visual index', async () => {
    const f = continuationFixture(
      visualFixture([{ name: 'arroz', quantity_g_estimate: null, confidence: 0.9 }]),
    )
    const result = await continueMeal(f, [quantityReply('arroz')])
    expect(prepared(result.materialization).source_groups[0]).toMatchObject({
      rule: 'visual',
      input_indexes: [0],
      source_positions: [{ visual_index: 0, name: null, quantity: null }],
    })
    expect(prepared(result.materialization).inputs[0]?.candidate).toMatchObject({
      quantity_g: 200,
      quantity_basis: 'stated',
      confidence: 0.9,
      needs_review: false,
      review_reason: null,
    })
    const low = continuationFixture(
      visualFixture([{ name: 'arroz', quantity_g_estimate: null, confidence: 0.2 }]),
    )
    await expect(continueMeal(low, [quantityReply('arroz')])).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
  })
  it('pins both captures, all answers and callbacks before the first awaited lookup', async () => {
    const f = continuationFixture(
        fixture('arroz; feijão100g', [
          { name: 'arroz' },
          { name: 'feijão', quantity: '100', unit: 'g' },
        ]),
      ),
      a = quantityReply('arroz'),
      state = db(),
      policy = { confidenceThreshold: 0.6 }
    const pending = continueMeal(f, [a], state, policy)
    a.input.answer.amount = 999
    a.question.food_name = 'feijão'
    f.resolution.context.owner.timezone = 'UTC'
    f.capture.context.owner.country = 'US'
    policy.confidenceThreshold = NaN
    Object.assign(f.resolution.sourceReader, { asOf: 'invalid' })
    const replacement = vi.fn()
    Object.assign(state.client, { rpc: replacement, from: replacement })
    const result = prepared((await pending).materialization)
    expect(result.inputs.map((i) => i.calculation_input.quantity_g)).toEqual([200, 100])
    expect(result.source_hash).toBe('a'.repeat(64))
    expect(replacement).not.toHaveBeenCalled()
  })
})

describe('continuation closed boundary and whole qualification preservation', () => {
  it('rejects foreign outer symbol and getter without invoking it', async () => {
    const f = continuationFixture(fixture('arroz', [{ name: 'arroz' }])),
      state = db(),
      a = quantityReply('arroz')
    const foreign = {
      resolutionSource: f.resolution,
      quantityAnswers: [a],
      [Symbol('foreign')]: true,
    }
    await expect(
      materializeConversationMealContinuation(
        state.client,
        f.command,
        f.capture,
        f.interpretation,
        options,
        foreign,
      ),
    ).rejects.toMatchObject({ code: 'conversation_meal_materialization_unavailable' })
    let reads = 0
    const getter = {
      resolutionSource: f.resolution,
      get quantityAnswers() {
        reads++
        return [a]
      },
    }
    await expect(
      materializeConversationMealContinuation(
        state.client,
        f.command,
        f.capture,
        f.interpretation,
        options,
        getter,
      ),
    ).rejects.toMatchObject({ code: 'conversation_meal_materialization_unavailable' })
    expect(reads).toBe(0)
    expect(state.from).not.toHaveBeenCalled()
  })
  it('rejects over-bound/sparse/non-JSON answer batches before querying', async () => {
    const f = continuationFixture(fixture('arroz', [{ name: 'arroz' }])),
      state = db(),
      a = quantityReply('arroz')
    for (const answers of [
      Array.from({ length: 31 }, () => a),
      new Array(1),
      [{ ...a, extra: undefined }],
      [{ ...a, input: { ...a.input, answer: { ...a.input.answer, amount: NaN } } }],
    ])
      await expect(continueMeal(f, answers, state)).rejects.toMatchObject({
        code: 'conversation_meal_materialization_unavailable',
      })
    expect(state.rpc).not.toHaveBeenCalled()
    expect(state.from).not.toHaveBeenCalled()
  })
  it('preserves prepared whole-dish rule with one actual missing-mass candidate', async () => {
    const name = 'carne desfiada com molho e milho',
      f = continuationFixture(fixture(name, [{ name }]))
    const result = await continueMeal(f, [quantityReply(name, 0, 180)])
    expect(prepared(result.materialization).source_groups[0]).toMatchObject({
      rule: 'prepared_dish',
      input_indexes: [0],
    })
    expect(prepared(result.materialization).inputs[0]?.calculation_input).toEqual({
      food_name: name,
      quantity_g: 180,
    })
  })
  it.each([
    'Vou comer ',
    'Não comi ',
    'Minha filha comeu ',
  ])('cannot upgrade original framing %s with a quantity answer', async (prefix) => {
    const f = continuationFixture(fixture(`${prefix}arroz`, [{ name: 'arroz' }])),
      state = db()
    await expect(continueMeal(f, [quantityReply('arroz')], state)).rejects.toMatchObject({
      code: 'conversation_meal_materialization_unavailable',
    })
    expect(state.rpc).not.toHaveBeenCalled()
    expect(state.from).not.toHaveBeenCalled()
  })
})

function storedLink(index = 0, amount = 200, unit = 'g', id = ASSET) {
  return {
    reply_id: id,
    reply_input_hash: '1'.repeat(64),
    question_key: String(index + 2).repeat(64),
    answer: { kind: 'quantity', food_index: index, amount, unit },
  }
}
function storedRun(
  f: ReturnType<typeof continuationFixture>,
  answerChain: unknown[],
  state = db(),
) {
  return materializeStoredConversationMealContinuation(
    state.client,
    f.command,
    f.capture,
    f.interpretation,
    options,
    { resolutionSource: f.resolution, answerChain },
  )
}
describe('actual stored linked-answer materialization without historical questions', () => {
  it('uses the original missing rice occurrence and preserves explicit beans and original evidence', async () => {
    const f = continuationFixture(
      fixture('Comi arroz e feijão 100 g', [
        { name: 'arroz' },
        { name: 'feijão', quantity: '100', unit: 'g' },
      ]),
    )
    const original = structuredClone(f.interpretation),
      result = await storedRun(f, [storedLink()])
    expect(result.materialization.status).toBe('materialized')
    if (result.materialization.status !== 'materialized') throw new Error('materialized required')
    expect(result.materialization.inputs.map((x) => x.calculation_input.quantity_g)).toEqual([
      200, 100,
    ])
    expect(result.quantity_witnesses[0]?.input_indexes).toEqual([0])
    expect(f.interpretation).toEqual(original)
    expect(result.materialization.source_hash).toBe(f.capture.sourceHash)
  })
  it('keeps an applied answer while another original quantity is still missing, then maps real indexes', async () => {
    const f = continuationFixture(
      fixture('Comi leite e whey', [{ name: 'leite' }, { name: 'whey' }]),
    )
    const milk = storedLink(0, 200, 'mL'),
      whey = storedLink(1, 1, 'scoop', COMMAND)
    const partial = await storedRun(f, [milk])
    expect(partial.materialization).toEqual({
      status: 'clarification_required',
      reason: 'missing_quantity',
      food_indexes: [1],
    })
    expect(partial.quantity_witnesses[0]?.input_indexes).toEqual([])
    const complete = await storedRun(f, [
      milk,
      whey,
      {
        reply_id: OWNER,
        reply_input_hash: 'a'.repeat(64),
        question_key: 'b'.repeat(64),
        answer: { kind: 'meal_type', meal_type: 'almoco' },
      },
    ])
    expect(complete.materialization.status).toBe('materialized')
    expect(complete.quantity_witnesses.map((w) => [w.quantity_g, w.input_indexes])).toEqual([
      [206, [0]],
      [30, [1]],
    ])
  })
  it.each([
    ['unknown link', (a: ReturnType<typeof storedLink>) => ({ ...a, hidden: true })],
    [
      'unknown answer',
      (a: ReturnType<typeof storedLink>) => ({ ...a, answer: { ...a.answer, quantity_g: 200 } }),
    ],
    ['bad hash', (a: ReturnType<typeof storedLink>) => ({ ...a, reply_input_hash: 'BAD' })],
    [
      'wrong target',
      (a: ReturnType<typeof storedLink>) => ({ ...a, answer: { ...a.answer, food_index: 1 } }),
    ],
    [
      'unsupported reference',
      (a: ReturnType<typeof storedLink>) => ({ ...a, answer: { ...a.answer, unit: 'scoop' } }),
    ],
  ])('rejects %s before catalog lookup', async (_label, mutate) => {
    const f = continuationFixture(fixture('Comi arroz', [{ name: 'arroz' }])),
      state = db()
    await expect(storedRun(f, [mutate(storedLink())], state)).rejects.toThrow()
    expect(state.rpc).not.toHaveBeenCalled()
    expect(state.from).not.toHaveBeenCalled()
  })
  it('rejects duplicate reply/question/target and more than one meal target', async () => {
    const f = continuationFixture(
      fixture('Comi arroz e feijão', [{ name: 'arroz' }, { name: 'feijão' }]),
    )
    for (const answers of [
      [storedLink(), storedLink()],
      [storedLink(), { ...storedLink(1), reply_id: COMMAND, question_key: '2'.repeat(64) }],
      [
        {
          reply_id: ASSET,
          reply_input_hash: 'a'.repeat(64),
          question_key: 'b'.repeat(64),
          answer: { kind: 'meal_type', meal_type: 'almoco' },
        },
        {
          reply_id: COMMAND,
          reply_input_hash: 'c'.repeat(64),
          question_key: 'd'.repeat(64),
          answer: { kind: 'meal_type', meal_type: 'jantar' },
        },
      ],
    ])
      await expect(storedRun(f, answers)).rejects.toThrow()
  })
  it('never executes custom array prototypes, getters or unknown hooks', async () => {
    const f = continuationFixture(fixture('Comi arroz', [{ name: 'arroz' }])),
      calls = vi.fn()
    const chain = [storedLink()]
    Object.setPrototypeOf(chain, { toJSON: calls })
    await expect(storedRun(f, chain)).rejects.toThrow()
    const link = storedLink()
    Object.defineProperty(link.answer, 'amount', { enumerable: true, get: calls })
    await expect(storedRun(f, [link])).rejects.toThrow()
    expect(calls).not.toHaveBeenCalled()
  })
  it('does not overwrite an explicit original mass', async () => {
    const f = continuationFixture(
      fixture('Comi arroz 100 g', [{ name: 'arroz', quantity: '100', unit: 'g' }]),
    )
    await expect(storedRun(f, [storedLink()])).rejects.toThrow()
  })
})

describe('stored-answer original evidence and asynchronous snapshot preservation', () => {
  it.each([
    'Vou comer ',
    'Não comi ',
    'Minha filha comeu ',
  ])('does not upgrade %s into a consumption', async (prefix) => {
    const f = continuationFixture(fixture(`${prefix}arroz`, [{ name: 'arroz' }])),
      state = db()
    await expect(storedRun(f, [storedLink()], state)).rejects.toThrow()
    expect(state.rpc).not.toHaveBeenCalled()
    expect(state.from).not.toHaveBeenCalled()
  })
  it('retains the detached stored quantity when a caller mutates its answer during catalog resolution', async () => {
    const name = 'geleia rara',
      f = continuationFixture(fixture(`Comi ${name}`, [{ name }])),
      state = db([name]),
      chain = [storedLink(0, 25)]
    const original = state.rpc.getMockImplementation()
    state.rpc.mockImplementation(async (...args) => {
      const current = chain[0]
      if (!current) throw new Error('actual chain entry')
      current.answer.amount = 999
      return await (
        original as (...v: typeof args) => Promise<Awaited<ReturnType<typeof state.rpc>>>
      )(...args)
    })
    const result = await storedRun(f, chain, state)
    expect(result.materialization.status).toBe('materialized')
    expect(result.quantity_witnesses[0]?.quantity_g).toBe(25)
    expect(result.quantity_witnesses[0]?.amount).toBe(25)
  })
  it('preserves qualified visual source positions and refuses an already resolved visual mass', async () => {
    for (const mass of [null, 100]) {
      const f = continuationFixture(
          visualFixture([{ name: 'arroz', quantity_g_estimate: mass, confidence: 0.9 }]),
        ),
        state = db()
      const promise = materializeStoredConversationMealContinuation(
        state.client,
        f.command,
        f.capture,
        f.interpretation,
        options,
        { resolutionSource: f.resolution, answerChain: [storedLink()] },
      )
      if (mass !== null) await expect(promise).rejects.toThrow()
      else {
        const r = await promise
        expect(r.materialization.status).toBe('materialized')
        if (r.materialization.status !== 'materialized') throw new Error('visual materialized')
        expect(r.materialization.source_groups[0]?.source_positions[0]).toMatchObject({
          visual_index: 0,
          name: null,
          quantity: null,
        })
      }
    }
  })
})


describe('ordinary-photo catalog naming: prepared farofa reference', () => {
  it('materializes the actual visual bare name without dropping the bean occurrence', async () => {
    const f = visualFixture([
      { name: 'feijão preto cozido', quantity_g_estimate: 150, confidence: 0.9 },
      { name: 'farofa', quantity_g_estimate: 80, confidence: 0.85 },
    ])
    const result = prepared(await materialize(f, db()))
    expect(result.inputs.map((x) => x.calculation_input)).toEqual([
      { food_name: 'feijão preto cozido', quantity_g: 150 },
      { food_name: 'farofa', quantity_g: 80 },
    ])
    expect(result.source_groups.map((x) => x.interpretation_food_indexes)).toEqual([[0], [1]])
  })
  it('feeds the public-photo observations through the actual shared calculator and preserves both editable source groups', async () => {
    const f = visualFixture([
      { name: 'feijão preto cozido', quantity_g_estimate: 150, confidence: 0.9 },
      { name: 'farofa', quantity_g_estimate: 80, confidence: 0.85 },
    ])
    const state = calculationDb([
      {
        ...row('Feijão, preto, cozido', 709),
        kcal_per_100g: 77.03,
        protein_g: 4.48,
        carbs_g: 14.01,
        fat_g: 0.54,
        fiber_g: 8.4,
      },
      {
        ...row('Mandioca, farofa, temperada', 288),
        kcal_per_100g: 405.69,
        protein_g: 2.06,
        carbs_g: 80.3,
        fat_g: 9.12,
        fiber_g: 7.82,
      },
    ])
    const result = prepared(await materialize(f, state))
    const calc = await calcMealMacros(
      state.client,
      result.inputs.map((i) => i.calculation_input),
      'BR',
      OWNER,
      {
        consumptionPolicy: 'consumed-meal-v1',
        preparationAnnotations: 'consumed.preparation.v1',
        sourceReader: f.capture.sourceReader,
        auditSink: f.capture.auditSink,
      },
    )
    expect(calc.items.map((i) => [i.food_name, i.quantity_g, i.kcal])).toEqual([
      ['feijão preto cozido', 150, 115.5],
      ['farofa de mandioca temperada', 80, 324.6],
    ])
    expect(calc.totals.kcal).toBe(440.1)
    expect(mapConversationMealCalculationSources(result, calc)).toMatchObject([
      { input_indexes: [0], source_group_indexes: [0], quantity_basis: 'visual_estimate' },
      { input_indexes: [1], source_group_indexes: [1], quantity_basis: 'visual_estimate' },
    ])
    // The bean already explicitly says cooked, and the farofa is only a prepared reference.
    expect(calc.preparation_annotations).toEqual([])
  })
  it('uses the same whole-name qualification for a free-text report', async () => {
    const f = fixture('farofa80g', [{ name: 'farofa', quantity: '80', unit: 'g' }])
    const result = prepared(await materialize(f, db()))
    expect(result.inputs[0]?.calculation_input).toEqual({ food_name: 'farofa', quantity_g: 80 })
  })
})
