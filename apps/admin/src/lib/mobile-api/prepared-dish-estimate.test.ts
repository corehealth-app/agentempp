import type { MealCalcResult, MealItemInput } from '@mpp/agent'
import { describe, expect, it } from 'vitest'
import { applyMobilePreparedDishEstimate } from './prepared-dish-estimate'

const name = 'carne desfiada com molho e milho'
const rejection = (food: string) => `Não consegui identificar "${food}" porque veio com vários alimentos juntos. Peça pro paciente descrever cada item separado com a quantidade (ex: "leite 250ml" e "whey 30g"). Não foi possível calcular as calorias desse item ainda.`
const input = (food = name, quantity = 180): MealItemInput => ({ food_name: food, quantity_g: quantity })
function rejected(food = name, quantity = 180): MealCalcResult {
  const warning = rejection(food)
  return {
    items: [{ ...input(food, quantity), matched_taco_name: '', matched_taco_id: null,
      kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0,
      similarity: 0, source: 'composite_rejected' }],
    totals: { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 },
    user_warnings: [warning], audit_warnings: ['retained audit'], warnings: [warning, 'retained audit'],
  }
}

describe('mobile prepared dish estimate approved23Oct', () => {
  it.each([name, 'CARNE DESFIADA COM MOLHO E MILHO', ' carne  cozida com molho de tomate + milho cozido '])('estimates the whole recognized dish without inventing ingredients: %s', food => {
    const original = rejected(food)
    const before = structuredClone(original)
    const result = applyMobilePreparedDishEstimate(original, [input(food)], 'mobile_app', 'pt-BR')
    expect(result.items).toHaveLength(1)
    expect(result.items[0]).toEqual({ ...original.items[0], matched_taco_name: '[estimativa prato_genérico]',
      kcal: 270, protein_g: 12.6, carbs_g: 32.4, fat_g: 9, fiber_g: 1.8, source: 'llm_estimate' })
    expect(result.totals).toEqual({ kcal: 270, protein_g: 12.6, carbs_g: 32.4, fat_g: 9, fiber_g: 1.8 })
    expect(result.user_warnings).toEqual([expect.stringMatching(/referência genérica.*aproximados.*corrigidos/),])
    expect(result.audit_warnings).toEqual(['retained audit'])
    expect(result.warnings).toEqual([...result.user_warnings, ...result.audit_warnings])
    expect(original).toEqual(before)
  })

  it.each(['carne crua com molho e milho', 'carne frita com molho', 'carne desfiada com molho e milho SKU123',
    'carne desfiada sem molho e milho', 'carne desfiada com molho e xyz', 'carne desfiada com',
    'carne desfiada com molho e molho', 'carne desfiada com milho e milho cozido',
    'carne desfiada com molho de tomate e molho', 'xyz com abc', 'carne desfiada com molho;'])('keeps unknown or unsupported text blocked: %s', food => {
    const original = rejected(food)
    expect(applyMobilePreparedDishEstimate(original, [input(food)], 'mobile_app', 'pt-BR')).toBe(original)
  })

  it.each([null, 'legacy', 'mobile_flow'])('does not change origin %s', origin => {
    const original = rejected()
    expect(applyMobilePreparedDishEstimate(original, [input()], origin, 'pt-BR')).toBe(original)
  })

  it.each([0, -1, 10000, Number.NaN, Number.POSITIVE_INFINITY])('does not estimate invalid weight %s', quantity => {
    const original = rejected(name, quantity)
    expect(applyMobilePreparedDishEstimate(original, [input(name, quantity)], 'mobile_app', 'pt-BR')).toBe(original)
  })

  it('does not guess a missing line association or discard a changed engine warning', () => {
    const original = rejected()
    expect(applyMobilePreparedDishEstimate(original, [input(), input()], 'mobile_app', 'pt-BR')).toBe(original)
    original.user_warnings = ['different engine refusal']
    expect(applyMobilePreparedDishEstimate(original, [input()], 'mobile_app', 'pt-BR')).toBe(original)
  })

  it('keeps overrides, labels, approved nutrition, preparation and invalid mapping intact', () => {
    const cases = [
      { inputs: [{ ...input(), user_kcal: 0 }] },
      { inputs: [{ ...input(), use_nutrition_label: true }] },
      { inputs: [{ ...input(), approved_nutrition: { kcal: 100, protein_g: 1, carbs_g: 1, fat_g: 1 } }] },
      { inputs: [input()], preparation: ['cru', 'cozido'] },
      { inputs: [input()], indexes: [[0, 0]] },
      { inputs: [input()], indexes: [[2]] },
      { inputs: [input()], indexes: [[]] },
      { inputs: [input()], indexes: [[0.5]] },
      { inputs: [input()], indexes: [] },
      { inputs: [input('outro nome')] },
      { inputs: [input(name, 100)] },
    ]
    for (const test of cases) {
      const original = rejected()
      if (test.preparation) original.items[0]!.preparation_options = test.preparation
      if (test.indexes) original.input_indexes = test.indexes
      expect(applyMobilePreparedDishEstimate(original, test.inputs, 'mobile_app', 'pt-BR')).toBe(original)
    }
  })

  it.each(['canonical_exact', 'canonical_composite', 'canonical_composite_partial', 'product_label', 'user_kcal', 'no_match'] as const)('preserves existing source %s', source => {
    const original = rejected(); original.items[0]!.source = source
    expect(applyMobilePreparedDishEstimate(original, [input()], 'mobile_app', 'pt-BR')).toBe(original)
  })

  it('maps past a merged row, removes only one duplicate warning and adds only the new contribution', () => {
    const original = rejected()
    const partial = { ...rejected('abacate com tomate', 123).items[0]!, source: 'canonical_composite_partial' as const,
      kcal: 10.1, protein_g: 1.15, carbs_g: 2.26, fat_g: 3.36, fiber_g: 4.46 }
    original.items = [partial, original.items[0]!, structuredClone(original.items[0]!)]
    original.input_indexes = [[0, 1], [2], [3]]
    original.totals = { kcal: 10.1, protein_g: 1.1, carbs_g: 2.2, fat_g: 3.3, fiber_g: 4.4 }
    original.user_warnings = ['portion notice', rejection(name), rejection(name), 'safety notice']
    const inputs = [input('leite', 100), input('leite integral', 100), input(), { ...input(), user_kcal: 0 }]
    const result = applyMobilePreparedDishEstimate(original, inputs, 'mobile_app', 'en-US')
    expect(result.items[0]).toBe(partial)
    expect(result.items[1]!.source).toBe('llm_estimate')
    expect(result.items[2]).toBe(original.items[2])
    expect(result.input_indexes).toEqual(original.input_indexes)
    expect(result.totals).toEqual({ kcal: 280.1, protein_g: 13.7, carbs_g: 34.6, fat_g: 12.3, fiber_g: 6.2 })
    expect(result.user_warnings.filter(value => value === rejection(name))).toHaveLength(1)
    expect(result.user_warnings).toContain('portion notice')
    expect(result.user_warnings).toContain('safety notice')
    expect(result.user_warnings).toContainEqual(expect.stringMatching(/generic reference.*approximate.*edited/))
  })
})
