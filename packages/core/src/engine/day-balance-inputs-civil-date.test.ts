import { describe, expect, it, vi } from 'vitest'
import { DEFAULT_CALC_CONFIG } from '../calc-config.js'
import { dailyTargetByProtocol } from './day-balance-inputs.js'
import { computeDailyTargetsOnCivilDate, type ProfileRow } from './targets.js'

const profile: ProfileRow = {
  sex: 'masculino',
  birth_date: '1990-01-01',
  height_cm: 180,
  weight_kg: 80,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: null,
  hunger_level: 'moderada',
  current_protocol: 'recomposicao',
  goal_type: null,
  goal_value: null,
  deficit_level: 500,
}
describe('day protocol latch uses the same explicit civil date as clinical target calculation', () => {
  it('uses the supplied civil birthday independently of the host clock, preserving all three formulas', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2040-01-01T01:00:00Z'))
    try {
      const result = dailyTargetByProtocol(profile, DEFAULT_CALC_CONFIG, '2026-12-31')
      for (const phase of ['recomposicao', 'ganho_massa', 'manutencao'] as const) {
        expect(result[phase]).toBe(
          computeDailyTargetsOnCivilDate(
            { ...profile, current_protocol: phase },
            DEFAULT_CALC_CONFIG,
            '2026-12-31',
          ).calories_target,
        )
      }
      expect(result).not.toEqual(dailyTargetByProtocol(profile, DEFAULT_CALC_CONFIG))
    } finally {
      vi.useRealTimers()
    }
  })
  it('does not accept an invalid clinical date as a host-clock fallback', () => {
    expect(() => dailyTargetByProtocol(profile, DEFAULT_CALC_CONFIG, '2026-02-30')).toThrow()
  })
})
