import { describe, expect, it } from 'vitest'
import { reconcilePendingMealEdit } from './pending-meal-edit.js'

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
