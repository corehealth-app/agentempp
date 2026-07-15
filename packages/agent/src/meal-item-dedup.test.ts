import { describe, expect, it } from 'vitest'
import { dedupeMealItems } from './meal-item-dedup.js'

describe('dedupeMealItems', () => {
  it('colapsa cópias idênticas vindas de foto e legenda sem dobrar a porção', () => {
    const result = dedupeMealItems([
      { food_name: 'tortilha integral Mission Carb Balance', quantity_g: 43 },
      { food_name: 'Tortilha integral Mission Carb Balance', quantity_g: 43 },
      { food_name: 'patê de frango', quantity_g: 40 },
    ])

    expect(result.items).toEqual([
      { food_name: 'tortilha integral Mission Carb Balance', quantity_g: 43 },
      { food_name: 'patê de frango', quantity_g: 40 },
    ])
    expect(result.duplicates).toEqual([
      {
        food_name: 'tortilha integral Mission Carb Balance',
        repeated: 2,
        result_g: 43,
        strategy: 'collapsed_identical',
      },
    ])
  })

  it('não dobra kcal aprovada quando a mesma evidência aparece duas vezes', () => {
    const approved = {
      kcal: 70,
      protein_g: 5,
      carbs_g: 19,
      fat_g: 2,
    }
    const result = dedupeMealItems([
      {
        food_name: 'tortilha Mission Carb Balance',
        quantity_g: 43,
        user_kcal: 70,
        approved_nutrition: approved,
      },
      {
        food_name: 'tortilha Mission Carb Balance',
        quantity_g: 43,
        user_kcal: 70,
        approved_nutrition: approved,
      },
    ])

    expect(result.items).toEqual([
      {
        food_name: 'tortilha Mission Carb Balance',
        quantity_g: 43,
        user_kcal: 70,
        approved_nutrition: approved,
      },
    ])
  })

  it('mantém itens diferentes mesmo quando vieram no mesmo burst multimodal', () => {
    const result = dedupeMealItems([
      { food_name: 'tortilha integral', quantity_g: 43 },
      { food_name: 'patê de frango', quantity_g: 43 },
    ])

    expect(result.items).toHaveLength(2)
    expect(result.duplicates).toEqual([])
  })

  it('falha fechado se o paciente declarou múltiplas porções mas a tool repetiu linhas', () => {
    expect(() =>
      dedupeMealItems(
        [
          { food_name: 'tortilha integral', quantity_g: 43 },
          { food_name: 'tortilha integral', quantity_g: 43 },
        ],
        { patientText: 'Comi 2 tortilhas integrais' },
      ),
    ).toThrow('multiplicidade explícita ambígua')
  })

  it('mantém o contrato canônico de uma linha com a quantidade total', () => {
    const result = dedupeMealItems(
      [{ food_name: 'tortilha integral', quantity_g: 86 }],
      { patientText: 'Comi uma tortilha e depois outra' },
    )

    expect(result.items).toEqual([{ food_name: 'tortilha integral', quantity_g: 86 }])
  })

  it('também bloqueia duas porções descritas como uma e outra', () => {
    expect(() =>
      dedupeMealItems(
        [
          { food_name: 'tortilha integral', quantity_g: 43 },
          { food_name: 'tortilha integral', quantity_g: 43 },
        ],
        { patientText: 'Comi uma tortilha integral e depois outra' },
      ),
    ).toThrow('multiplicidade explícita ambígua')
  })

  it('falha fechado quando cópias idênticas carregam nutrição conflitante', () => {
    expect(() =>
      dedupeMealItems([
        { food_name: 'tortilha integral', quantity_g: 43, user_kcal: 70 },
        { food_name: 'tortilha integral', quantity_g: 43, user_kcal: 65 },
      ]),
    ).toThrow('conflito nutricional')
  })
})
