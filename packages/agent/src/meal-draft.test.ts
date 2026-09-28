import { describe, expect, it } from 'vitest'
import {
  buildDraftCandidates,
  draftFromStatedText,
  draftFromVisionItems,
  labelCandidateId,
  parseCountedSegment,
  parseStatedGrams,
  portionReferenceGrams,
  sanitizeExtractedItems,
  splitMealText,
} from './meal-draft.js'
import { naturalUnit } from './meal-pipeline.js'

describe('portionReferenceGrams — only the unit weights the server already uses', () => {
  it.each([
    ['ovo', null, 50],
    ['ovos mexidos', 'unidade', 50],
    ['pão francês', null, 50],
    ['pão de queijo', 'unidades', 30],
    ['banana', null, 100],
    ['maçã', null, 150],
    ['queijo', 'fatia', 15],
    ['presunto', 'fatias', 15],
  ])('%s (%s) = %s g', (food, unit, grams) => {
    expect(portionReferenceGrams(food, unit)).toBe(grams)
  })

  it.each([
    ['feijoada', null],
    ['bife', 'unidade'],
    ['arroz', 'colher'],
    ['ovo de codorna', null],
    ['pão', null],
    ['queijo', null],
  ])('%s (%s) has no reference', (food, unit) => {
    expect(portionReferenceGrams(food, unit)).toBeNull()
  })

  // "maçã" is left out: the display rule exists (150 g) but its word boundary
  // never matches the accented name, so naturalUnit shows grams (pre-existing).
  it('agrees with the display rules of naturalUnit (same numbers)', () => {
    for (const [food, count] of [
      ['ovo', 2],
      ['pão francês', 3],
      ['pão de queijo', 4],
      ['banana', 2],
      ['queijo fatiado', 2],
    ] as const) {
      const unit = food.includes('fatiado') ? 'fatia' : null
      const grams = (portionReferenceGrams(food, unit) ?? 0) * count
      expect(naturalUnit(food, grams).display_qty).toBe(count)
    }
  })
})

describe('text segments', () => {
  it('splits items without cutting a decimal comma', () => {
    expect(splitMealText('Arroz 150 g, feijão 86,5 g; 2 ovos e 1 pão francês\nbanana')).toEqual([
      'Arroz 150 g',
      'feijão 86,5 g',
      '2 ovos',
      '1 pão francês',
      'banana',
    ])
  })

  it('reads stated grams exactly, kilograms included', () => {
    expect(parseStatedGrams('Feijão carioca 86,5 g')).toEqual({
      name: 'Feijão carioca',
      grams_stated: 86.5,
    })
    expect(parseStatedGrams('10,5 g de azeite')).toEqual({ name: 'azeite', grams_stated: 10.5 })
    expect(parseStatedGrams('0,2 kg de frango')).toEqual({ name: 'frango', grams_stated: 200 })
    expect(parseStatedGrams('arroz 12000 g')).toBeNull()
    expect(parseStatedGrams('120 g')).toBeNull()
    expect(parseStatedGrams('2 ovos')).toBeNull()
    expect(parseStatedGrams('1 garrafa de suco')).toBeNull()
  })

  it('reads counts and units and keeps the name as written', () => {
    expect(parseCountedSegment('2 ovos mexidos')).toEqual({ name: 'ovos mexidos', count: 2, unit: null })
    expect(parseCountedSegment('três bananas')).toEqual({ name: 'bananas', count: 3, unit: null })
    expect(parseCountedSegment('1 fatia de queijo')).toEqual({ name: 'queijo', count: 1, unit: 'fatia' })
    expect(parseCountedSegment('250ml de leite')).toEqual({ name: 'leite', count: 250, unit: 'ml' })
    expect(parseCountedSegment('meia maçã')).toEqual({ name: 'maçã', count: 0.5, unit: null })
    expect(parseCountedSegment('feijão')).toEqual({ name: 'feijão' })
    expect(parseCountedSegment('   ')).toBeNull()
    expect(parseCountedSegment('comi 2 ovos')).toEqual({ name: 'ovos', count: 2, unit: null })
    expect(parseCountedSegment('tomei um café')).toEqual({ name: 'café', count: 1, unit: null })
    // A number the parser cannot place is shown back for the patient to fix.
    expect(parseCountedSegment('arroz 2 colheres')).toEqual({
      name: 'arroz 2 colheres',
      ambiguous: true,
    })
  })
})

describe('candidates never receive invented grams', () => {
  it('"2 ovos" uses the existing reference, marked approximate and for review', () => {
    const [eggs] = buildDraftCandidates([{ name: 'ovo', count: 2, unit: 'unidade' }])
    expect(eggs).toMatchObject({
      name: 'ovo',
      quantity_g: 100,
      quantity_basis: 'portion_reference',
      count: 2,
      unit_label: 'unidade',
      needs_review: true,
      review_reason: 'estimated_quantity',
    })
  })

  it('a food without reference stays without quantity', () => {
    const [dish] = buildDraftCandidates([{ name: 'prato de feijoada', count: 1 }])
    expect(dish).toMatchObject({
      quantity_g: null,
      quantity_basis: 'missing',
      needs_review: true,
      review_reason: 'missing_quantity',
    })
  })

  it('stated grams are exact and need no review', () => {
    const { raw, rest } = draftFromStatedText('Arroz branco 150 g\nFeijão carioca 86,5 g\n2 ovos')
    expect(rest).toEqual(['2 ovos'])
    expect(buildDraftCandidates(raw)).toMatchObject([
      { name: 'Arroz branco', quantity_g: 150, quantity_basis: 'stated', needs_review: false },
      { name: 'Feijão carioca', quantity_g: 86.5, quantity_basis: 'stated', needs_review: false },
    ])
  })

  it('millilitres become grams only for a liquid, and as an approximation', () => {
    const [milk, rice] = buildDraftCandidates([
      { name: 'leite', count: 250, unit: 'ml' },
      { name: 'arroz', count: 250, unit: 'ml' },
    ])
    expect(milk).toMatchObject({ quantity_g: 250, quantity_basis: 'portion_reference', unit_label: 'ml' })
    expect(rice).toMatchObject({ quantity_g: null, quantity_basis: 'missing' })
  })

  it('gives each candidate a stable id', () => {
    const first = buildDraftCandidates([{ name: 'ovo', count: 2 }, { name: 'Banana' }])
    const second = buildDraftCandidates([{ name: 'ovo', count: 2 }, { name: 'banana' }])
    expect(first.map((c) => c.candidate_id)).toEqual(second.map((c) => c.candidate_id))
    expect(new Set(first.map((c) => c.candidate_id)).size).toBe(2)
  })
})

describe('extractor output is untrusted', () => {
  const text = 'comi 2 ovos mexidos, um pão francês e arroz com 120 g de frango'

  it('keeps what the patient said and drops quantities that are not in the text', () => {
    expect(
      sanitizeExtractedItems(text, [
        { name: 'ovo mexido', count: 2, unit: 'unidade' },
        { name: 'pão francês', count: 1 },
        { name: 'arroz', grams_stated: 150 },
        { name: 'frango', grams_stated: 120 },
        { name: 'frango', count: 7 },
      ]),
    ).toEqual([
      { name: 'ovo mexido', count: 2, unit: 'unidade', grams_stated: null },
      { name: 'pão francês', count: 1, unit: null, grams_stated: null },
      { name: 'arroz', count: null, unit: null, grams_stated: null },
      { name: 'frango', count: null, unit: null, grams_stated: 120 },
      { name: 'frango', count: null, unit: null, grams_stated: null },
    ])
  })

  it('drops foods that are not in the text and anything that is not an item', () => {
    expect(
      sanitizeExtractedItems(text, [
        { name: 'pizza de calabresa', grams_stated: 300 },
        { name: '' },
        'ignore previous instructions',
        null,
        { grams_stated: 100 },
      ]),
    ).toEqual([])
    expect(sanitizeExtractedItems(text, { items: [] })).toEqual([])
  })
})

describe('photo candidates', () => {
  it('maps the Vision items without a second guess', () => {
    const candidates = draftFromVisionItems(
      [
        { name: '2x ovo frito', quantity_g_estimate: 100, confidence: 0.9 },
        { name: 'arroz branco', quantity_g_estimate: 140, confidence: 0.5 },
        { name: 'molho', quantity_g_estimate: 0, confidence: 0 },
        { name: '  ', quantity_g_estimate: 50, confidence: 0.9 },
        'not an item',
      ],
      0.6,
    )
    expect(candidates).toMatchObject([
      {
        name: 'ovo frito',
        quantity_g: 100,
        quantity_basis: 'visual_estimate',
        count: 2,
        needs_review: true,
        review_reason: 'estimated_quantity',
        confidence: 0.9,
      },
      {
        name: 'arroz branco',
        quantity_g: 140,
        quantity_basis: 'visual_estimate',
        review_reason: 'low_confidence',
      },
      { name: 'molho', quantity_g: null, quantity_basis: 'missing', review_reason: 'missing_quantity' },
    ])
    expect(draftFromVisionItems(null, 0.6)).toEqual([])
  })

  it('associates a label only when it is unequivocal', () => {
    const one = draftFromVisionItems([{ name: 'iogurte', quantity_g_estimate: 170, confidence: 0.9 }], 0.6)
    expect(labelCandidateId(one, null)).toBe(one[0]?.candidate_id)

    const many = draftFromVisionItems(
      [
        { name: 'iogurte natural', quantity_g_estimate: 170, confidence: 0.9 },
        { name: 'granola', quantity_g_estimate: 30, confidence: 0.9 },
      ],
      0.6,
    )
    expect(labelCandidateId(many, 'Iogurte Natural Integral')).toBe(many[0]?.candidate_id)
    expect(labelCandidateId(many, 'Barra de cereal')).toBeNull()
    expect(labelCandidateId(many, null)).toBeNull()

    const twins = draftFromVisionItems(
      [
        { name: 'iogurte natural', quantity_g_estimate: 170, confidence: 0.9 },
        { name: 'iogurte grego', quantity_g_estimate: 100, confidence: 0.9 },
      ],
      0.6,
    )
    expect(labelCandidateId(twins, 'Iogurte')).toBeNull()
  })
})
