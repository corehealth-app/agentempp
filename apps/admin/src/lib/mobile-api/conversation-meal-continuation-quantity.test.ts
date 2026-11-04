import { describe, expect, it } from 'vitest'
import { parseConversationMealReplyBody } from './conversation-meal-continuation-input'
import * as quantityConversion from './conversation-meal-continuation-quantity'
import {
  ConversationMealContinuationQuantityError,
  resolveConversationMealQuantityAnswer,
} from './conversation-meal-continuation-quantity'
import { mobileQuantityDisplay } from './mobile-quantity-display'

const key = 'e'.repeat(64)
function input(amount = 200, unit = 'g') {
  return {
    schema: 'conversation.meal-clarification.v1',
    expected_revision: 4,
    question_key: key,
    answer: { kind: 'quantity', food_index: 2, amount, unit },
  }
}
function question(name = 'leite') {
  const reference = mobileQuantityDisplay(name)
  const units = ['g', 'kg']
  if (reference?.unit === 'mL') {
    units.push('mL', 'L')
    if (reference.reference_id === 'fao-infoods-v2-whole-milk-tb') units.push('caneca')
  } else if (reference) units.push(reference.unit)
  return {
    schema: 'conversation.meal-question.v1',
    question_key: key,
    revision: 4,
    kind: 'quantity',
    food_index: 2,
    food_name: name,
    allowed_units: units,
    quantity_reference: reference,
  }
}

describe('linked explicit quantity conversion only', () => {
  it.each([
    ['leite', 200, 'mL', 206],
    ['leite integral', 1, 'caneca', 206],
    ['leite', 1.5, 'caneca', 309],
    ['leite', 0.2, 'L', 206],
    ['leite', 1, 'L', 1030],
    ['whey', 1, 'scoop', 30],
    ['whey protein em pó', 1.5, 'scoop', 45],
    ['pão de queijo', 8, 'unit', 240],
    ['ovo', 3, 'unit', 150],
    ['pão francês', 2, 'unit', 100],
    ['banana', 2, 'unit', 200],
    ['maçã', 1, 'unit', 150],
    ['café coado', 250, 'mL', 250],
    ['chá preparado', 250, 'mL', 250],
    ['água', 2, 'L', 2000],
    ['suco de laranja', 0.125, 'L', 129.75],
    ['suco de laranja', 200, 'mL', 207.6],
  ] as const)('resolves approved %s %s %s to %sg', (name, amount, unit, grams) => {
    expect(resolveConversationMealQuantityAnswer(input(amount, unit), question(name))).toEqual({
      food_index: 2,
      food_name: name,
      amount,
      unit,
      quantity_g: grams,
      quantity_basis: 'portion_reference',
      quantity_display: mobileQuantityDisplay(name),
    })
  })

  it.each([
    [200, 'g', 200],
    [1.23456789, 'g', 1.23456789],
    [1e-7, 'g', 1e-7],
    [0.0000005, 'g', 0.0000005],
    [Number.MIN_VALUE, 'g', Number.MIN_VALUE],
    [1e-7, 'kg', 0.00009999999999999999],
    [Number.MIN_VALUE, 'kg', 4.94e-321],
    [0.00123456789, 'kg', 1.23456789],
    [0.2, 'kg', 200],
    [9.999, 'kg', 9999],
    [9999, 'g', 9999],
  ] as const)('preserves explicit mass %s %s without six-decimal rounding', (amount, unit, grams) => {
    const result = resolveConversationMealQuantityAnswer(input(amount, unit), question())
    expect(result.quantity_g).toBe(grams)
    expect(result.amount).toBe(amount)
    expect(result.unit).toBe(unit)
    expect(result.quantity_basis).toBe('stated')
    expect(result.quantity_display).toBeNull()
  })

  it.each([
    ['água', 0.0000005, 'mL', 0.000001],
    ['água', 0.00000149, 'mL', 0.000001],
    ['água', 0.0000015, 'mL', 0.000002],
    ['água', 9999, 'mL', 9999],
    ['whey', 333.3, 'scoop', 9999],
    ['whey', 333.30000001, 'scoop', 9999],
  ] as const)('rounds only approved final reference grams: %s %s %s', (name, amount, unit, grams) => {
    expect(
      resolveConversationMealQuantityAnswer(input(amount, unit), question(name)).quantity_g,
    ).toBe(grams)
  })

  it.each([
    ['água', Number.MIN_VALUE, 'mL'],
    ['água', 0.0000004, 'mL'],
    ['whey', Number.MIN_VALUE, 'scoop'],
    ['whey', 333.30000002, 'scoop'],
    ['leite', 9999, 'mL'],
    ['leite', 9999, 'L'],
    ['leite', 49, 'caneca'],
    ['maçã', 100, 'unit'],
    ['leite', 9.9990000001, 'kg'],
    ['leite', 9999, 'kg'],
  ] as const)('refuses rounded-zero or over-bound %s %s %s', (name, amount, unit) => {
    // The body is valid. Refusal belongs to conversion, never a zero fallback.
    expect(() => parseConversationMealReplyBody(input(amount, unit))).not.toThrow()
    expect(() =>
      resolveConversationMealQuantityAnswer(input(amount, unit), question(name)),
    ).toThrow(ConversationMealContinuationQuantityError)
  })

  it.each([0, -0, -1, Infinity, NaN, 10000])('refuses invalid original amount %s', (amount) => {
    expect(() => resolveConversationMealQuantityAnswer(input(amount), question())).toThrow()
  })

  it('pins whole-milk and whey reference metadata and returns no calculation or registration authority', () => {
    const milk = resolveConversationMealQuantityAnswer(input(1, 'caneca'), question())
    const whey = resolveConversationMealQuantityAnswer(input(1.5, 'scoop'), question('whey'))
    expect(milk.quantity_display).toEqual({
      unit: 'mL',
      grams_per_unit: 1.03,
      reference_id: 'fao-infoods-v2-whole-milk-tb',
      estimated: true,
    })
    expect(whey.quantity_display).toEqual({
      unit: 'scoop',
      grams_per_unit: 30,
      reference_id: 'app-household-whey-scoop-v1',
      estimated: true,
    })
    expect(Object.keys(milk).sort()).toEqual([
      'amount',
      'food_index',
      'food_name',
      'quantity_basis',
      'quantity_display',
      'quantity_g',
      'unit',
    ])
    expect(Object.keys(whey).sort()).toEqual(Object.keys(milk).sort())
  })

  it('preserves the literal original name, answer and tokens without mutating input', () => {
    const rawName = '  LÉITE\t integral  '
    const originalInput = input(200, 'mL'),
      originalQuestion = question(rawName)
    const before = structuredClone({ originalInput, originalQuestion })
    const result = resolveConversationMealQuantityAnswer(originalInput, originalQuestion)
    expect({ originalInput, originalQuestion }).toEqual(before)
    expect(result.food_name).toBe(rawName)
    expect(result.amount).toBe(200)
    expect(result.unit).toBe('mL')
    originalInput.answer.amount = 300
    originalQuestion.food_name = 'água'
    if (originalQuestion.quantity_reference) originalQuestion.quantity_reference.grams_per_unit = 1
    expect(result.quantity_g).toBe(206)
    expect(result.quantity_display?.grams_per_unit).toBe(1.03)
    expect(Object.isFrozen(result)).toBe(true)
    expect(Object.isFrozen(result.quantity_display)).toBe(true)
  })

  it.each([
    'leite em pó',
    'leite desnatado',
    'leite com whey',
    'whey Growth',
    'whey com leite',
    'café em pó',
    'iogurte natural',
  ])('does not infer a reference for %s but preserves explicit grams', (name) => {
    expect(resolveConversationMealQuantityAnswer(input(200), question(name))).toEqual({
      food_index: 2,
      food_name: name,
      amount: 200,
      unit: 'g',
      quantity_g: 200,
      quantity_basis: 'stated',
      quantity_display: null,
    })
    for (const unit of ['mL', 'L', 'caneca', 'unit', 'scoop'])
      expect(() => resolveConversationMealQuantityAnswer(input(1, unit), question(name))).toThrow()
  })

  it.each([
    'água',
    'whey',
    'café coado',
    'suco de laranja',
  ])('does not give %s a milk cup or mismatched portion unit', (name) => {
    expect(() =>
      resolveConversationMealQuantityAnswer(input(1, 'caneca'), question(name)),
    ).toThrow()
    const mismatched = name === 'whey' ? 'unit' : 'scoop'
    expect(() =>
      resolveConversationMealQuantityAnswer(input(1, mismatched), question(name)),
    ).toThrow()
  })

  it('requires the exact current question revision/key/kind/target before calculating', () => {
    const validInput = input(200, 'mL'),
      validQuestion = question()
    for (const changed of [
      { ...validInput, expected_revision: 3 },
      { ...validInput, question_key: 'f'.repeat(64) },
      { ...validInput, answer: { ...validInput.answer, food_index: 1 } },
      { ...validInput, answer: { kind: 'meal_type', meal_type: 'cafe' } },
      { ...validInput, answer: { ...validInput.answer, user_kcal: 20 } },
      { ...validInput, answer: { ...validInput.answer, amount: '200' } },
    ])
      expect(() => resolveConversationMealQuantityAnswer(changed, validQuestion)).toThrow()
    const mealQuestion = {
      ...validQuestion,
      kind: 'meal_type',
      food_index: null,
      food_name: null,
      allowed_units: [],
      quantity_reference: null,
    }
    const mealInput = { ...validInput, answer: { kind: 'meal_type', meal_type: 'cafe' } }
    expect(() => resolveConversationMealQuantityAnswer(mealInput, mealQuestion)).toThrow(
      ConversationMealContinuationQuantityError,
    )
  })

  it('rejects forged factors/references/units even for explicit grams', () => {
    const valid = question()
    for (const changed of [
      { ...valid, quantity_reference: { ...valid.quantity_reference, grams_per_unit: 1 } },
      { ...valid, quantity_reference: { ...valid.quantity_reference, reference_id: 'invented' } },
      { ...valid, quantity_reference: { ...valid.quantity_reference, unit: 'scoop' } },
      { ...valid, allowed_units: ['g', 'kg'] },
      { ...valid, food_name: 'leite com whey' },
      { ...valid, owner_id: '10000000-0000-4000-8000-000000000001' },
    ])
      expect(() => resolveConversationMealQuantityAnswer(input(), changed)).toThrow()
  })

  it('does not execute getters or retain caller-owned objects', () => {
    let reads = 0
    const malicious = Object.defineProperty(input(), 'answer', {
      enumerable: true,
      get() {
        reads++
        return input().answer
      },
    })
    expect(() => resolveConversationMealQuantityAnswer(malicious, question())).toThrow()
    expect(reads).toBe(0)
  })
})

describe('historical quantity conversion without fabricated question', () => {
  it.each([
    ['leite', 200, 'mL', 206],
    ['leite', 1, 'caneca', 206],
    ['whey', 1, 'scoop', 30],
    ['whey', 1.5, 'scoop', 45],
    ['ovo', 2, 'unit', 100],
    ['água', 0.0000005, 'mL', 0.000001],
    ['arroz', 1e-7, 'g', 1e-7],
    ['arroz', 1e-7, 'kg', 0.00009999999999999999],
  ] as const)('converts exact original name %s %s %s with no question identity', (name, amount, unit, grams) => {
    const result = quantityConversion.convertConversationMealQuantity(name, amount, unit)
    expect(result).toEqual({
      amount,
      unit,
      quantity_g: grams,
      quantity_basis: unit === 'g' || unit === 'kg' ? 'stated' : 'portion_reference',
      quantity_display: unit === 'g' || unit === 'kg' ? null : mobileQuantityDisplay(name),
    })
    expect(Object.isFrozen(result)).toBe(true)
    if (result.quantity_display) expect(Object.isFrozen(result.quantity_display)).toBe(true)
  })

  it.each([
    ['leite', 0, 'g'],
    ['leite', -1, 'g'],
    ['leite', NaN, 'g'],
    ['leite', Infinity, 'g'],
    ['leite', 10000, 'g'],
    ['leite', 10, 'kg'],
    ['leite', Number.MIN_VALUE, 'mL'],
    ['whey', Number.MIN_VALUE, 'scoop'],
    ['leite em pó', 200, 'mL'],
    ['whey Growth', 1, 'scoop'],
    ['leite com whey', 1, 'caneca'],
    ['água', 1, 'caneca'],
    ['whey', 1, 'unit'],
    ['leite', 1, 'scoop'],
    ['ovo', 200, 'mL'],
    ['', 1, 'g'],
    [' '.repeat(10), 1, 'g'],
    ['x'.repeat(161), 1, 'g'],
    ['leite\u0000', 1, 'g'],
    ['leite\u007f', 1, 'g'],
    ['\ud800', 1, 'g'],
    [new String('leite'), 200, 'mL'],
    ['leite', '200', 'mL'],
    ['leite', 200, 'ml'],
    [{ food_name: 'leite', grams_per_unit: 1 }, 200, 'mL'],
  ])('refuses invalid original primitives without caller factors: %s/%s/%s', (name, amount, unit) => {
    expect(() => quantityConversion.convertConversationMealQuantity(name, amount, unit)).toThrow(
      ConversationMealContinuationQuantityError,
    )
  })
})
