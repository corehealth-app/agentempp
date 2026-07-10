import { describe, expect, it } from 'vitest'
import { selectMealRegistrationGroup } from './meal-registration-group.js'

describe('selectMealRegistrationGroup', () => {
  const sameRegistration = [
    {
      id: '1',
      food_name: 'rap10',
      kcal: 100,
      consumed_at: '2026-07-10T00:13:00Z',
      raw_provider_message_id: 'wamid-1',
    },
    {
      id: '2',
      food_name: 'frango',
      kcal: 200,
      consumed_at: '2026-07-10T00:13:00Z',
      raw_provider_message_id: 'wamid-1',
    },
    {
      id: '3',
      food_name: 'queijo',
      kcal: 80,
      consumed_at: '2026-07-10T00:13:00Z',
      raw_provider_message_id: 'wamid-1',
    },
    {
      id: '4',
      food_name: 'salada',
      kcal: 20,
      consumed_at: '2026-07-10T00:13:00Z',
      raw_provider_message_id: 'wamid-1',
    },
  ]

  it('food_hint localiza um item mas seleciona o registro inteiro', () => {
    const result = selectMealRegistrationGroup(sameRegistration, 'rap10')
    expect(result.status).toBe('selected')
    if (result.status === 'selected')
      expect(result.rows.map((row) => row.id)).toEqual(['1', '2', '3', '4'])
  })

  it('usa consumed_at como fallback para registros sem provider id', () => {
    const result = selectMealRegistrationGroup(
      sameRegistration.map((row) => ({ ...row, raw_provider_message_id: null })),
      'frango',
    )
    expect(result.status).toBe('selected')
    if (result.status === 'selected') expect(result.rows).toHaveLength(4)
  })

  it('sem hint exige desambiguacao quando existem duas refeicoes', () => {
    const result = selectMealRegistrationGroup([
      ...sameRegistration,
      {
        id: '5',
        food_name: 'iogurte',
        kcal: 90,
        consumed_at: '2026-07-10T02:00:00Z',
        raw_provider_message_id: 'wamid-2',
      },
    ])
    expect(result.status).toBe('ambiguous')
    if (result.status === 'ambiguous') expect(result.groups).toHaveLength(2)
  })

  it('hint que aparece em dois registros continua ambiguo', () => {
    const result = selectMealRegistrationGroup(
      [
        ...sameRegistration,
        {
          id: '5',
          food_name: 'frango grelhado',
          kcal: 180,
          consumed_at: '2026-07-10T02:00:00Z',
          raw_provider_message_id: 'wamid-2',
        },
      ],
      'frango',
    )
    expect(result.status).toBe('ambiguous')
  })
})
