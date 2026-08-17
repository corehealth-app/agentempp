import { describe, expect, it } from 'vitest'
import {
  hasExplicitWholeMealReplacementIntent,
  selectMealReplacementTarget,
} from './meal-replacement-target.js'

describe('selectMealReplacementTarget', () => {
  it('seleciona somente o item corrigido dentro de um dia com várias refeições', () => {
    const result = selectMealReplacementTarget({
      recentLogs: [
        {
          id: 'kumis',
          food_name: 'iogurte kumis',
          meal_type: 'lanche',
          consumed_at: '2026-07-13T20:08:00Z',
          raw_provider_message_id: 'kumis',
        },
        {
          id: 'milk',
          food_name: 'leite em pó desnatado',
          meal_type: 'almoco',
          consumed_at: '2026-07-13T20:10:00Z',
          raw_provider_message_id: 'milk',
        },
      ],
      newFoodNames: ['leite em pó desnatado'],
    })

    expect(result).toMatchObject({ status: 'selected', logIds: ['milk'], mealType: 'almoco' })
  })

  it('usa o nome anterior de corrections para uma troca de identidade', () => {
    const result = selectMealReplacementTarget({
      recentLogs: [
        {
          id: 'fried',
          food_name: 'frango frito',
          meal_type: 'almoco',
          consumed_at: '2026-07-13T18:00:00Z',
        },
      ],
      newFoodNames: ['frango grelhado'],
      corrections: [{ de: 'frango frito', para: 'frango grelhado' }],
    })

    expect(result).toMatchObject({ status: 'selected', logIds: ['fried'] })
  })

  it('mantém o grupo completo disponível para correção explícita da refeição inteira', () => {
    const result = selectMealReplacementTarget({
      recentLogs: [
        {
          id: 'fried',
          food_name: 'frango frito',
          meal_type: 'almoco',
          consumed_at: '2026-07-13T18:00:00Z',
          raw_provider_message_id: 'lunch',
        },
        {
          id: 'rice',
          food_name: 'arroz branco',
          meal_type: 'almoco',
          consumed_at: '2026-07-13T18:00:00Z',
          raw_provider_message_id: 'lunch',
        },
      ],
      newFoodNames: ['frango grelhado'],
    })

    expect(result).toMatchObject({
      status: 'selected',
      logIds: ['fried'],
      registrationRows: [{ id: 'fried' }, { id: 'rice' }],
    })
  })

  it('não apaga leite com whey ao corrigir somente leite em pó', () => {
    const result = selectMealReplacementTarget({
      recentLogs: [
        {
          id: 'whey',
          food_name: 'leite com whey',
          meal_type: 'cafe',
          consumed_at: '2026-07-13T12:00:00Z',
          raw_provider_message_id: 'breakfast',
        },
        {
          id: 'powder',
          food_name: 'leite em pó desnatado',
          meal_type: 'cafe',
          consumed_at: '2026-07-13T12:00:00Z',
          raw_provider_message_id: 'breakfast',
        },
      ],
      newFoodNames: ['leite em pó desnatado'],
    })

    expect(result).toMatchObject({ status: 'selected', logIds: ['powder'] })
  })

  it('bloqueia quando dois itens do mesmo registro empatam como alvo', () => {
    const result = selectMealReplacementTarget({
      recentLogs: [
        {
          id: 'fried',
          food_name: 'frango frito',
          meal_type: 'almoco',
          consumed_at: '2026-07-13T18:00:00Z',
          raw_provider_message_id: 'lunch',
        },
        {
          id: 'roasted',
          food_name: 'frango assado',
          meal_type: 'almoco',
          consumed_at: '2026-07-13T18:00:00Z',
          raw_provider_message_id: 'lunch',
        },
      ],
      newFoodNames: ['frango grelhado'],
    })

    expect(result.status).toBe('ambiguous')
  })

  it('não confunde correção de um item com autorização para refeição inteira', () => {
    expect(hasExplicitWholeMealReplacementIntent(['corrige o almoço, o frango era grelhado'])).toBe(
      false,
    )
    expect(
      hasExplicitWholeMealReplacementIntent(['corrige o almoço inteiro e substitui tudo']),
    ).toBe(true)
    expect(hasExplicitWholeMealReplacementIntent(['corrige o almoço inteiro'])).toBe(true)
  })
})
