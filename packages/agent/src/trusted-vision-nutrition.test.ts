import { describe, expect, it } from 'vitest'
import { attachTrustedVisionNutrition } from './trusted-vision-nutrition.js'

const label = {
  productName: 'Iogurte Whey Morango',
  per100g: { kcal: 95, protein_g: 10, carbs_g: 8, fat_g: 2 },
}

describe('attachTrustedVisionNutrition', () => {
  it('converte valores por 100g para a quantidade proposta', () => {
    expect(
      attachTrustedVisionNutrition(
        [{ food_name: 'iogurte whey morango', quantity_g: 170 }],
        [label],
      ),
    ).toEqual([
      {
        food_name: 'iogurte whey morango',
        quantity_g: 170,
        approved_nutrition: {
          kcal: 161.5,
          protein_g: 17,
          carbs_g: 13.6,
          fat_g: 3.4,
        },
      },
    ])
  })

  it('preserva kcal explícita do paciente acima do OCR', () => {
    const item = { food_name: 'iogurte whey morango', quantity_g: 170, user_kcal: 120 }
    expect(attachTrustedVisionNutrition([item], [label])).toEqual([item])
  })

  it('em refeição com vários itens aplica apenas ao nome compatível', () => {
    const result = attachTrustedVisionNutrition(
      [
        { food_name: 'banana', quantity_g: 100 },
        { food_name: 'iogurte whey morango', quantity_g: 170 },
      ],
      [label],
    )

    expect(result[0]).not.toHaveProperty('approved_nutrition')
    expect(result[1]).toHaveProperty('approved_nutrition.kcal', 161.5)
  })

  it('não associa rótulo a item sem correspondência', () => {
    const item = { food_name: 'peito de frango', quantity_g: 170 }
    expect(attachTrustedVisionNutrition([item], [label])).toEqual([item])
  })

  it('associa nome comercial Yokey Kumis ao item iogurte kumis', () => {
    const result = attachTrustedVisionNutrition(
      [{ food_name: 'iogurte kumis', quantity_g: 150 }],
      [
        {
          productName: 'Yokey Kumis',
          per100g: { kcal: 83.33, protein_g: 3.33, carbs_g: 9.58, fat_g: 3.33 },
        },
      ],
    )

    expect(result[0]?.approved_nutrition).toEqual({
      kcal: 125,
      protein_g: 5,
      carbs_g: 14.37,
      fat_g: 5,
    })
  })
})
