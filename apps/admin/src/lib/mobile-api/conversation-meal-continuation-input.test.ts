import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  bindConversationMealReply,
  parseConversationMealQuestion,
  parseConversationMealReplyBody,
  validateConversationMealReplyQuestion,
} from './conversation-meal-continuation-input'
import { mobileQuantityDisplay } from './mobile-quantity-display'

const id = '10000000-0000-4000-8000-000000000001'
const replyId = '10000000-0000-4000-8000-000000000080'
const key = 'e'.repeat(64)
const binding = () => ({
  ownerId: id,
  parentCommandId: '10000000-0000-4000-8000-000000000002',
  parentInputHash: 'a'.repeat(64),
  epoch: '10000000-0000-4000-8000-000000000003',
  decisionHash: 'd'.repeat(64),
})
const body = () => ({
  schema: 'conversation.meal-clarification.v1',
  expected_revision: 0,
  question_key: key,
  answer: { kind: 'quantity', food_index: 0, amount: 200, unit: 'g' },
})
function question(name = 'leite') {
  const ref = mobileQuantityDisplay(name),
    units = ['g', 'kg']
  if (ref?.unit === 'mL') {
    units.push('mL', 'L')
    if (ref.reference_id === 'fao-infoods-v2-whole-milk-tb') units.push('caneca')
  } else if (ref) units.push(ref.unit)
  return {
    schema: 'conversation.meal-question.v1',
    question_key: key,
    revision: 0,
    kind: 'quantity',
    food_index: 0,
    food_name: name,
    allowed_units: units,
    quantity_reference: ref,
  }
}
const mealQuestion = () => ({
  schema: 'conversation.meal-question.v1',
  question_key: key,
  revision: 0,
  kind: 'meal_type',
  food_index: null,
  food_name: null,
  allowed_units: [],
  quantity_reference: null,
})
const bind = (input: unknown = body()) =>
  bindConversationMealReply({
    binding: binding(),
    replyId,
    input,
    idempotencyKey: `cmreply1:${replyId}`,
  })

describe('closed linked meal clarification inputs', () => {
  it('freezes detached original intent/binding and keeps exact reply identity and opaque tokens', () => {
    const input = body(),
      original = binding()
    const result = bindConversationMealReply({
      binding: original,
      replyId,
      input,
      idempotencyKey: `cmreply1:${replyId}`,
    })
    input.answer.amount = 30
    original.parentInputHash = 'f'.repeat(64)
    expect(result.input).toEqual(body())
    expect(result.binding).toEqual(binding())
    expect(result.replyId).toBe(replyId)
    expect(result.idempotencyKey).toBe(`cmreply1:${replyId}`)
    expect(Object.isFrozen(result)).toBe(true)
    expect(Object.isFrozen(result.input.answer)).toBe(true)
    expect(Object.isFrozen(result.binding)).toBe(true)
    expect(bind(Object.fromEntries(Object.entries(body()).reverse())).inputHash).toBe(
      result.inputHash,
    )
    expect(
      bindConversationMealReply({
        binding: { ...binding(), ownerId: replyId },
        replyId,
        input: body(),
        idempotencyKey: `cmreply1:${replyId}`,
      }).inputHash,
    ).toBe(result.inputHash)
  })
  it.each([
    [1e-7, '0.0000001'],
    [1.23e-7, '0.000000123'],
    [1e-6, '0.000001'],
    [Number.MIN_VALUE, `0.${'0'.repeat(323)}5`],
    [9999, '9999'],
  ] as const)('uses qualified SQL decimal scalar hash for %s', (amount, decimal) => {
    const input = { ...body(), answer: { ...body().answer, amount } }
    const canonical = `{"answer":{"amount":${decimal},"food_index":0,"kind":"quantity","unit":"g"},"expected_revision":0,"question_key":"${key}","schema":"conversation.meal-clarification.v1"}`
    expect(bind(input).inputHash).toBe(createHash('sha256').update(canonical).digest('hex'))
    expect(bind(input).input).toEqual(input)
  })
  it('preserves numeric negative-zero revision while canonical hashing actual JSON zero', () => {
    const input = { ...body(), expected_revision: -0 }
    expect(bind(input).inputHash).toBe(bind().inputHash)
    expect(Object.is(bind(input).input.expected_revision, -0)).toBe(true)
  })
  it.each([
    'cafe',
    'almoco',
    'lanche',
    'jantar',
    'ceia',
    'outro',
  ])('accepts existing explicit meal type %s without guessing', (meal_type) => {
    const input = { ...body(), answer: { kind: 'meal_type', meal_type } }
    expect(parseConversationMealReplyBody(input)).toEqual(input)
    expect(() => validateConversationMealReplyQuestion(input, mealQuestion())).not.toThrow()
  })
  it.each([
    'g',
    'kg',
    'mL',
    'L',
    'unit',
    'scoop',
    'caneca',
  ])('body accepts literal quantity unit %s without conversion', (unit) => {
    const input = { ...body(), answer: { ...body().answer, amount: 9999, unit } }
    expect(parseConversationMealReplyBody(input)).toEqual(input)
  })
  it.each([
    { extra: true },
    { schema: 'conversation.command.v1' },
    { expected_revision: true },
    { expected_revision: -1 },
    { expected_revision: 0.5 },
    { expected_revision: 2147483648 },
    { question_key: 'E'.repeat(64) },
    { question_key: null },
    ...[-1, 30, 0.5, null, true].map((food_index) => ({
      answer: { ...body().answer, food_index },
    })),
    ...[0, -0, -1, 10000, Infinity, NaN, '20', true, null].map((amount) => ({
      answer: { ...body().answer, amount },
    })),
    { answer: { ...body().answer, unit: 'ml' } },
    { answer: { ...body().answer, quantity_g: 20 } },
    { answer: { ...body().answer, kcal: 20 } },
    { answer: { ...body().answer, meal_type: 'cafe' } },
    { answer: { kind: 'meal_type', meal_type: 'breakfast' } },
    { answer: { kind: 'meal_type', meal_type: 'almoco', food_index: 0 } },
    { answer: { kind: 'meal_type', meal_type: null } },
  ])('refuses malformed/foreign body fields %#', (patch) =>
    expect(() => parseConversationMealReplyBody({ ...body(), ...patch })).toThrow())
  it.each([
    'ownerId',
    'parentCommandId',
    'epoch',
    'parentInputHash',
    'decisionHash',
    'extra',
  ])('refuses invalid binding field %s', (field) => {
    expect(() =>
      bindConversationMealReply({
        binding: { ...binding(), [field]: 'bad' },
        replyId,
        input: body(),
        idempotencyKey: `cmreply1:${replyId}`,
      }),
    ).toThrow()
  })
  it.each([
    null,
    `cmsg1:${replyId}`,
    `cmreply1:${id}`,
    `cmreply1:${replyId},cmreply1:${replyId}`,
  ])('requires exact stable key %s', (idempotencyKey) => {
    expect(() =>
      bindConversationMealReply({ binding: binding(), replyId, input: body(), idempotencyKey }),
    ).toThrow()
  })
  it('never invokes getters or accepts cycles/non-JSON/undefined/sparse arrays', () => {
    let reads = 0
    const getter = Object.defineProperty({}, 'input', {
      enumerable: true,
      get() {
        reads++
        return body()
      },
    })
    Object.assign(getter, { binding: binding(), replyId, idempotencyKey: `cmreply1:${replyId}` })
    expect(() => bindConversationMealReply(getter as never)).toThrow()
    expect(reads).toBe(0)
    const cycle: Record<string, unknown> = {}
    cycle.self = cycle
    for (const value of [
      cycle,
      { ...body(), extra: undefined },
      { ...body(), extra: () => 1 },
      { ...body(), extra: new Date() },
      { ...body(), extra: 2n },
      { ...body(), extra: Symbol('x') },
    ])
      expect(() => parseConversationMealReplyBody(value)).toThrow()
    const q = question()
    q.allowed_units = new Array(2)
    expect(() => parseConversationMealQuestion(q)).toThrow()
  })
  it.each([
    'leite',
    '  LÉITE integral  ',
    'café coado',
    'chá preparado',
    'água',
    'suco de laranja',
    'whey protein em pó',
    'pão de queijo',
    'ovo',
    'pão francês',
    'banana',
    'maçã',
  ])('uses existing exact-name reference and retains raw name %s', (name) => {
    const q = question(name),
      result = parseConversationMealQuestion(q)
    expect(result).toEqual(q)
    expect(result.food_name).toBe(name)
    expect(result.quantity_reference).toEqual(mobileQuantityDisplay(name))
    expect(Object.isFrozen(result.allowed_units)).toBe(true)
    expect(Object.isFrozen(result.quantity_reference)).toBe(true)
  })
  it.each([
    'leite em pó',
    'leite desnatado',
    'leite com whey',
    'whey Growth',
    'whey com leite',
    'café em pó',
    'arroz/feijão 😀 e\u0301',
    'iogurte natural',
  ])('brands/powders/mixtures inherit no guessed reference: %s', (name) => {
    expect(parseConversationMealQuestion(question(name))).toEqual({
      ...question(name),
      quantity_reference: null,
      allowed_units: ['g', 'kg'],
    })
  })
  it('retains literal Unicode/whitespace but refuses UTF16 overflow, controls and blank names', () => {
    const name = `é e\u0301 /\t\r\n${'😀'.repeat(72)}`
    expect(parseConversationMealQuestion(question(name)).food_name).toBe(name)
    expect(parseConversationMealQuestion(question('😀'.repeat(80))).food_name).toBe('😀'.repeat(80))
    for (const name of [
      '😀'.repeat(81),
      '',
      ' \t\n\ufeff',
      'leite\u0001',
      'leite\u007f',
      'leite\ud800',
    ])
      expect(() => parseConversationMealQuestion(question(name))).toThrow()
  })
  it.each([
    'extra',
    'schema',
    'key',
    'revision',
    'kind',
    'index',
    'name',
    'units-duplicate',
    'units-order',
    'units-mass',
    'units-unknown',
    'ref-null',
    'ref-factor',
    'ref-id',
    'ref-unit',
    'ref-estimated',
    'ref-extra',
  ])('fails closed on forged question %s', (attack) => {
    const q: Record<string, unknown> = question()
    const patch: Record<string, unknown> = {
      extra: { parent_command_id: id },
      schema: { schema: 'conversation.meal-question.v2' },
      key: { question_key: 'wrong' },
      revision: { revision: -1 },
      kind: { kind: 'meal' },
      index: { food_index: null },
      name: { food_name: null },
      'units-duplicate': { allowed_units: ['g', 'kg', 'mL', 'L', 'caneca', 'g'] },
      'units-order': { allowed_units: ['kg', 'g', 'mL', 'L', 'caneca'] },
      'units-mass': { allowed_units: ['mL', 'L', 'caneca'] },
      'units-unknown': { allowed_units: ['g', 'kg', 'mL', 'L', 'caneca', 'oz'] },
      'ref-null': { quantity_reference: null, allowed_units: ['g', 'kg'] },
    }
    const refs: Record<string, unknown> = {
      'ref-factor': { grams_per_unit: 1 },
      'ref-id': { reference_id: 'brand' },
      'ref-unit': { unit: 'scoop' },
      'ref-estimated': { estimated: false },
      'ref-extra': { authority: true },
    }
    if (refs[attack])
      q.quantity_reference = { ...mobileQuantityDisplay('leite'), ...(refs[attack] as object) }
    else Object.assign(q, patch[attack])
    expect(() => parseConversationMealQuestion(q)).toThrow()
  })
  it.each([
    'food_index',
    'food_name',
    'quantity_reference',
    'allowed_units',
  ])('meal-type question requires null targets/ref and empty units: %s', (field) => {
    const values: Record<string, unknown> = {
      food_index: 0,
      food_name: 'leite',
      quantity_reference: mobileQuantityDisplay('leite'),
      allowed_units: ['g'],
    }
    expect(() =>
      parseConversationMealQuestion({ ...mealQuestion(), [field]: values[field] }),
    ).toThrow()
  })
  it('pins approved milk and whey reference facts independently of lookup helper', () => {
    const milk = {
      ...question(),
      quantity_reference: {
        unit: 'mL',
        grams_per_unit: 1.03,
        reference_id: 'fao-infoods-v2-whole-milk-tb',
        estimated: true,
      },
      allowed_units: ['g', 'kg', 'mL', 'L', 'caneca'],
    }
    const whey = {
      ...question('whey'),
      quantity_reference: {
        unit: 'scoop',
        grams_per_unit: 30,
        reference_id: 'app-household-whey-scoop-v1',
        estimated: true,
      },
      allowed_units: ['g', 'kg', 'scoop'],
    }
    expect(parseConversationMealQuestion(milk)).toEqual(milk)
    expect(parseConversationMealQuestion(whey)).toEqual(whey)
    expect(() =>
      validateConversationMealReplyQuestion(
        { ...body(), answer: { ...body().answer, unit: 'scoop', amount: 1 } },
        whey,
      ),
    ).not.toThrow()
    expect(() =>
      validateConversationMealReplyQuestion(
        { ...body(), answer: { ...body().answer, unit: 'caneca', amount: 1 } },
        milk,
      ),
    ).not.toThrow()
  })
  it('does not assign a milk cup to water, powder, brand or mixture', () => {
    for (const name of ['água', 'leite em pó', 'whey Growth', 'leite com whey']) {
      const q = question(name)
      q.allowed_units.push('caneca')
      expect(() => parseConversationMealQuestion(q)).toThrow()
    }
  })
  it('requires exact head revision/key/kind/target/allowed unit without calculating grams', () => {
    const q = parseConversationMealQuestion(question()),
      valid = { ...body(), answer: { ...body().answer, amount: 9999, unit: 'kg' } }
    expect(() => validateConversationMealReplyQuestion(valid, q)).not.toThrow()
    for (const input of [
      { ...valid, expected_revision: 1 },
      { ...valid, question_key: 'a'.repeat(64) },
      { ...valid, answer: { kind: 'meal_type', meal_type: 'almoco' } },
      { ...valid, answer: { ...body().answer, food_index: 1 } },
      { ...valid, answer: { ...body().answer, unit: 'scoop' } },
    ])
      expect(() => validateConversationMealReplyQuestion(input, q)).toThrow()
    expect(() => validateConversationMealReplyQuestion(body(), mealQuestion())).toThrow()
  })
})
