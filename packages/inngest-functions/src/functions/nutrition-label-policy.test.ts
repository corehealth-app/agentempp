import { describe, expect, it } from 'vitest'
import { resolveTrustedNutritionLabel } from './nutrition-label-policy.js'

const complete = {
  kcal: 95,
  protein_g: 10,
  carbs_g: 8,
  fat_g: 2,
}

describe('resolveTrustedNutritionLabel', () => {
  it('rejeita OCR abaixo do limiar mesmo com números completos', () => {
    expect(
      resolveTrustedNutritionLabel(
        {
          productName: 'Produto',
          confidence: 0.4,
          servingSizeG: 100,
          perServing: complete,
          per100g: complete,
        },
        0.6,
      ),
    ).toEqual({ trusted: null, reason: 'low_confidence' })
  })

  it('aceita os quatro macros por 100g quando o OCR é confiável', () => {
    expect(
      resolveTrustedNutritionLabel(
        {
          productName: 'Produto',
          confidence: 0.9,
          servingSizeG: null,
          perServing: { kcal: null, protein_g: null, carbs_g: null, fat_g: null },
          per100g: complete,
        },
        0.6,
      ),
    ).toEqual({
      trusted: { productName: 'Produto', per100g: complete },
      reason: 'per_100g',
    })
  })

  it('prioriza a proporção da porção impressa quando o per100g calculado diverge', () => {
    expect(
      resolveTrustedNutritionLabel(
        {
          productName: 'Yokey Kumis',
          confidence: 0.98,
          servingSizeG: 240,
          perServing: { kcal: 200, protein_g: 8, carbs_g: 23, fat_g: 8 },
          per100g: { kcal: 97, protein_g: 9, carbs_g: 4, fat_g: 5 },
        },
        0.6,
      ),
    ).toEqual({
      trusted: {
        productName: 'Yokey Kumis',
        per100g: { kcal: 83.33, protein_g: 3.33, carbs_g: 9.58, fat_g: 3.33 },
      },
      reason: 'derived_from_serving',
    })
  })

  it('deriva por 100g somente quando porção e quatro macros estão completos', () => {
    expect(
      resolveTrustedNutritionLabel(
        {
          productName: 'Produto',
          confidence: 0.9,
          servingSizeG: 50,
          perServing: { kcal: 100, protein_g: 5, carbs_g: 10, fat_g: 4 },
          per100g: { kcal: null, protein_g: null, carbs_g: null, fat_g: null },
        },
        0.6,
      ),
    ).toEqual({
      trusted: {
        productName: 'Produto',
        per100g: { kcal: 200, protein_g: 10, carbs_g: 20, fat_g: 8 },
      },
      reason: 'derived_from_serving',
    })
  })

  it('rejeita tabela parcial para não transformar campo ausente em zero', () => {
    expect(
      resolveTrustedNutritionLabel(
        {
          productName: 'Produto',
          confidence: 0.9,
          servingSizeG: 50,
          perServing: { kcal: 100, protein_g: null, carbs_g: 10, fat_g: 4 },
          per100g: { kcal: 200, protein_g: null, carbs_g: 20, fat_g: 8 },
        },
        0.6,
      ),
    ).toEqual({ trusted: null, reason: 'incomplete_macros' })
  })
})
