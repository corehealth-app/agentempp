import { describe, expect, it } from 'vitest'
import { resolveLinkedAdditionMealType } from './meal-addition-context.js'

describe('resolveLinkedAdditionMealType', () => {
  it('mantém no lanche um complemento explicitamente adicionado ao iogurte', () => {
    const result = resolveLinkedAdditionMealType({
      currentText: 'Adicionei 30g de leite em pó desnatado ao iogurte',
      recentLogs: [
        {
          id: 'kumis-log',
          food_name: 'iogurte kumis',
          meal_type: 'lanche',
          consumed_at: '2026-07-13T20:08:16Z',
          raw_provider_message_id: 'kumis-confirm',
        },
      ],
    })

    expect(result).toMatchObject({
      mealType: 'lanche',
      matchedFoodName: 'iogurte kumis',
      trigger: 'Adicionei',
    })
  })

  it('não vincula uma correção posterior como se fosse nova adição', () => {
    expect(
      resolveLinkedAdditionMealType({
        currentText: '30 gramas do leite em pó que usei tem apenas 85 kcal',
        recentLogs: [
          {
            id: 'milk-log',
            food_name: 'leite em pó desnatado',
            meal_type: 'almoco',
            consumed_at: '2026-07-13T20:10:24Z',
            raw_provider_message_id: 'milk-add',
          },
        ],
      }),
    ).toBeNull()
  })
})
