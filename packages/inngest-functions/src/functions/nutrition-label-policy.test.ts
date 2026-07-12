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
          servingSizeG: 30,
          perServing: complete,
          per100g: complete,
        },
        0.6,
      ),
    ).toEqual({
      trusted: { productName: 'Produto', per100g: complete },
      reason: 'per_100g',
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
