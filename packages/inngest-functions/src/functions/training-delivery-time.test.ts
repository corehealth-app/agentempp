import { describe, expect, it } from 'vitest'
import { resolveTrainingDeliveryClock } from './training-delivery-time.js'

describe('resolveTrainingDeliveryClock', () => {
  it('resolve hora, data e dia da semana em Orlando', () => {
    expect(
      resolveTrainingDeliveryClock(
        new Date('2026-07-12T11:00:00.000Z'),
        'America/New_York',
      ),
    ).toEqual({ localHour: 7, localDate: '2026-07-12', dayLabel: 'dom' })
  })

  it('usa o fuso recebido, não o fuso do servidor', () => {
    expect(
      resolveTrainingDeliveryClock(
        new Date('2026-07-12T11:00:00.000Z'),
        'America/Sao_Paulo',
      )?.localHour,
    ).toBe(8)
  })

  it('retorna null para timezone inválido', () => {
    expect(resolveTrainingDeliveryClock(new Date(), 'Invalid/Timezone')).toBeNull()
  })
})
