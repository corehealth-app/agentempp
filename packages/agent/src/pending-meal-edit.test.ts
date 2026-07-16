import { describe, expect, it } from 'vitest'
import { reconcilePendingMealEdit, reconcileScopedMealCorrection } from './pending-meal-edit.js'

describe('reconcilePendingMealEdit', () => {
  const previous = [
    {
      name: 'chocolate ao leite',
      quantity_g: 12,
      display_qty: 12,
      display_unit: 'g',
      kcal: 70,
      user_kcal: 70,
      protein_g: 0.9,
      carbs_g: 7.2,
      fat_g: 4.2,
    },
  ]

  it('escala kcal e macros quando a edição altera somente a quantidade', () => {
    const result = reconcilePendingMealEdit({
      previousItems: previous,
      resolvedItems: [
        {
          name: 'chocolate ao leite',
          quantity_g: 6,
          display_qty: 6,
          display_unit: 'g',
          kcal: 32.7,
          protein_g: 0.45,
          carbs_g: 3.6,
          fat_g: 2.1,
        },
      ],
      currentExplicitKcalFoods: new Set(),
    })

    expect(result.items[0]).toMatchObject({
      quantity_g: 6,
      kcal: 35,
      user_kcal: 35,
      protein_g: 0.45,
      carbs_g: 3.6,
      fat_g: 2.1,
    })
    expect(result.adjustments).toEqual([
      expect.objectContaining({ food_name: 'chocolate ao leite', reason: 'quantity_scaled' }),
    ])
  })

  it('novo kcal explícito do paciente vence o valor anterior', () => {
    const result = reconcilePendingMealEdit({
      previousItems: previous,
      resolvedItems: [
        {
          name: 'chocolate ao leite',
          quantity_g: 6,
          display_qty: 6,
          display_unit: 'g',
          kcal: 30,
          user_kcal: 30,
          protein_g: 0.4,
          carbs_g: 3.1,
          fat_g: 1.8,
        },
      ],
      currentExplicitKcalFoods: new Set(['chocolate ao leite']),
    })

    expect(result.items[0]?.kcal).toBe(30)
    expect(result.items[0]?.user_kcal).toBe(30)
    expect(result.adjustments).toHaveLength(0)
  })

  it('preserva kcal explícita e proveniência quando outro item da refeição é corrigido', () => {
    const result = reconcilePendingMealEdit({
      previousItems: [
        {
          name: 'rap10',
          food_db_id: null,
          nutrition_source: 'user_kcal',
          quantity_g: 35,
          kcal: 70,
          user_kcal: 70,
          protein_g: 3.27,
          carbs_g: 8.4,
          fat_g: 2.33,
        },
      ],
      resolvedItems: [
        {
          name: 'rap10',
          food_db_id: null,
          nutrition_source: 'llm_estimate',
          quantity_g: 35,
          kcal: 52.5,
          protein_g: 2.45,
          carbs_g: 6.3,
          fat_g: 1.75,
        },
      ],
      currentExplicitKcalFoods: new Set(),
    })

    expect(result.items[0]).toMatchObject({
      kcal: 70,
      user_kcal: 70,
      protein_g: 3.27,
      carbs_g: 8.4,
      fat_g: 2.33,
      food_db_id: null,
      nutrition_source: 'user_kcal',
    })
  })

  it('mudança de identidade ou preparo usa a nova resolução', () => {
    const result = reconcilePendingMealEdit({
      previousItems: [
        {
          name: 'frango frito',
          quantity_g: 120,
          kcal: 336,
          protein_g: 27.6,
          carbs_g: 13.2,
          fat_g: 19.2,
        },
      ],
      resolvedItems: [
        {
          name: 'frango grelhado',
          quantity_g: 120,
          kcal: 198,
          protein_g: 33.6,
          carbs_g: 0,
          fat_g: 6,
        },
      ],
      currentExplicitKcalFoods: new Set(),
    })

    expect(result.items[0]?.kcal).toBe(198)
    expect(result.adjustments).toHaveLength(0)
  })

  it('recalcula os totais a partir dos itens finais', () => {
    const result = reconcilePendingMealEdit({
      previousItems: previous,
      resolvedItems: [
        {
          name: 'chocolate ao leite',
          quantity_g: 6,
          kcal: 32.7,
          protein_g: 0.45,
          carbs_g: 3.6,
          fat_g: 2.1,
        },
        {
          name: 'morango',
          quantity_g: 100,
          kcal: 30,
          protein_g: 0.9,
          carbs_g: 6.8,
          fat_g: 0.3,
        },
      ],
      currentExplicitKcalFoods: new Set(),
    })

    expect(result.totals).toEqual({
      kcal: 65,
      protein_g: 1.35,
      carbs_g: 10.4,
      fat_g: 2.4,
    })
  })
})

describe('reconcileScopedMealCorrection', () => {
  const previousDinner = [
    {
      name: 'rap10',
      quantity_g: 35,
      kcal: 70,
      protein_g: 3.27,
      carbs_g: 8.4,
      fat_g: 2.33,
    },
    {
      name: 'salame fatiado',
      quantity_g: 60,
      kcal: 201.6,
      protein_g: 13.2,
      carbs_g: 1.2,
      fat_g: 16.2,
    },
    {
      name: 'tomate cereja',
      quantity_g: 40,
      kcal: 7.2,
      protein_g: 0.36,
      carbs_g: 1.56,
      fat_g: 0.08,
    },
  ]

  it('reconstrói a refeição completa mesmo quando a LLM retorna só o substituto', () => {
    const result = reconcileScopedMealCorrection({
      previousItems: previousDinner,
      resolvedItems: [
        {
          name: 'calabresa fatiada',
          food_db_id: 317,
          nutrition_source: 'canonical_fuzzy',
          quantity_g: 60,
          kcal: 186,
          protein_g: 10.8,
          carbs_g: 1.2,
          fat_g: 15.6,
        },
      ],
      corrections: [{ de: 'salame fatiado', para: 'calabresa fatiada' }],
    })

    expect(result?.items.map((item) => item.name)).toEqual([
      'rap10',
      'calabresa fatiada',
      'tomate cereja',
    ])
    expect(result?.totals).toEqual({
      kcal: 263.2,
      protein_g: 14.43,
      carbs_g: 11.16,
      fat_g: 18.01,
    })
  })

  it('ignora recálculos da LLM nos itens que não fazem parte da correção', () => {
    const result = reconcileScopedMealCorrection({
      previousItems: previousDinner,
      resolvedItems: [
        {
          name: 'rap10',
          quantity_g: 35,
          kcal: 52.5,
          protein_g: 2.45,
          carbs_g: 6.3,
          fat_g: 1.75,
        },
        {
          name: 'calabresa fatiada',
          quantity_g: 60,
          kcal: 186,
          protein_g: 10.8,
          carbs_g: 1.2,
          fat_g: 15.6,
        },
        {
          name: 'tomate cereja',
          quantity_g: 40,
          kcal: 7.2,
          protein_g: 0.36,
          carbs_g: 1.56,
          fat_g: 0.08,
        },
      ],
      corrections: [{ de: 'salame fatiado', para: 'calabresa fatiada' }],
    })

    expect(result?.items[0]).toMatchObject({ name: 'rap10', kcal: 70 })
  })

  it('falha fechada se a refeição anterior não contém o item de origem', () => {
    expect(
      reconcileScopedMealCorrection({
        previousItems: previousDinner,
        resolvedItems: [
          {
            name: 'calabresa fatiada',
            quantity_g: 60,
            kcal: 186,
            protein_g: 10.8,
            carbs_g: 1.2,
            fat_g: 15.6,
          },
        ],
        corrections: [{ de: 'pepperoni', para: 'calabresa fatiada' }],
      }),
    ).toBeNull()
  })
})
