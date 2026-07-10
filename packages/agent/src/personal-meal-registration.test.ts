import { describe, expect, it } from 'vitest'
import {
  buildPersonalWindowsFromLogs,
  collapseMealRowsToRegistrations,
} from './personal-meal-windows.js'

describe('rotina pessoal por registro, nao por item', () => {
  it('colapsa todos os alimentos da mesma mensagem em uma refeicao', () => {
    const rows = Array.from({ length: 5 }, (_, index) => ({
      meal_type: 'jantar' as const,
      consumed_at: '2026-07-10T00:13:00.000Z',
      raw_provider_message_id: 'wamid-1',
      food_name: `item-${index}`,
    }))

    const registrations = collapseMealRowsToRegistrations(rows, 'America/New_York')
    expect(registrations).toHaveLength(1)
    expect(registrations[0]).toMatchObject({
      meal_type: 'jantar',
      hour: 20,
      local_date: '2026-07-09',
    })
  })

  it('descarta grupo parcialmente reclassificado com rotulos conflitantes', () => {
    const registrations = collapseMealRowsToRegistrations(
      [
        {
          meal_type: 'jantar' as const,
          consumed_at: '2026-07-10T00:13:00.000Z',
          raw_provider_message_id: 'wamid-1',
        },
        {
          meal_type: 'lanche' as const,
          consumed_at: '2026-07-10T00:13:00.000Z',
          raw_provider_message_id: 'wamid-1',
        },
      ],
      'America/New_York',
    )
    expect(registrations).toEqual([])
  })

  it('nao ativa janela com varias refeicoes em um unico dia', () => {
    const logs = Array.from({ length: 6 }, (_, index) => ({
      meal_type: 'jantar' as const,
      hour: 18 + (index % 2),
      local_date: '2026-07-01',
      registration_key: `r-${index}`,
    }))
    expect(buildPersonalWindowsFromLogs(logs).has('jantar')).toBe(false)
  })

  it('ativa janela com cinco dias distintos e rotina estavel', () => {
    const logs = Array.from({ length: 5 }, (_, index) => ({
      meal_type: 'jantar' as const,
      hour: 18 + (index % 2),
      local_date: `2026-07-0${index + 1}`,
      registration_key: `r-${index}`,
    }))
    expect(buildPersonalWindowsFromLogs(logs).get('jantar')).toMatchObject({
      sample_count: 5,
      distinct_day_count: 5,
    })
  })

  it('rejeita janela pessoal ruidosa com amplitude acima de seis horas', () => {
    const logs = [10, 12, 14, 17, 20].map((hour, index) => ({
      meal_type: 'jantar' as const,
      hour,
      local_date: `2026-07-0${index + 1}`,
      registration_key: `r-${index}`,
    }))
    expect(buildPersonalWindowsFromLogs(logs).has('jantar')).toBe(false)
  })
})
