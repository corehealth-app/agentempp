import { describe, expect, it } from 'vitest'
import { buildConfirmedMealArgs, shouldBlockEffectiveReplace } from './pending-meal-confirmation.js'

describe('buildConfirmedMealArgs', () => {
  it('propaga correções e macros aprovados no pending para registra_refeicao', () => {
    const args = buildConfirmedMealArgs(
      {
        mealType: 'almoco',
        items: [
          {
            name: 'frango grelhado',
            quantity_g: 120,
            kcal: 191,
            protein_g: 38.4,
            carbs_g: 0,
            fat_g: 3,
          },
        ],
        corrections: [
          {
            de: 'frango frito',
            para: 'frango grelhado',
            kcal_per_100g: 159,
            protein_g: 32,
            carbs_g: 0,
            fat_g: 2.5,
          },
        ],
      },
      true,
      '2026-07-10',
    )

    expect(args.corrections).toEqual([
      {
        de: 'frango frito',
        para: 'frango grelhado',
        kcal_per_100g: 159,
        protein_g: 32,
        carbs_g: 0,
        fat_g: 2.5,
      },
    ])
    expect(args.items[0]?.approved_nutrition).toEqual({
      kcal: 191,
      protein_g: 38.4,
      carbs_g: 0,
      fat_g: 3,
    })
  })
})

describe('shouldBlockEffectiveReplace', () => {
  it('bloqueia replace fraco vindo de uma edição comum', () => {
    expect(
      shouldBlockEffectiveReplace({
        effectiveReplace: true,
        hasPriorMealOfSameType: true,
        hasPriorEditedPending: true,
        inferredReplace: false,
        replaceEvidence: null,
      }),
    ).toBe(true)
  })

  it('preserva replace necessário para concluir recuperação atômica', () => {
    expect(
      shouldBlockEffectiveReplace({
        effectiveReplace: true,
        hasPriorMealOfSameType: true,
        hasPriorEditedPending: true,
        inferredReplace: false,
        replaceEvidence: 'lossy_cancellation_recovery',
      }),
    ).toBe(false)
  })
})
