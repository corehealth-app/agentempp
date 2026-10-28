import { afterEach, describe, expect, it, vi } from 'vitest'
import { DEFAULT_CALC_CONFIG } from '../calc-config.js'
import { calcBMR, calcTDEE } from '../nutrition.js'
import { computeDailyTargets, computeDailyTargetsOnCivilDate, type ProfileRow } from './targets.js'

const profile: ProfileRow = {
  sex: 'masculino',
  birth_date: '1990-10-26',
  height_cm: 175,
  weight_kg: 80,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: null,
  hunger_level: 'moderada',
  current_protocol: 'manutencao',
  goal_type: null,
  goal_value: null,
  deficit_level: 500,
}
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllEnvs()
})

describe('daily targets on the authoritative clinical civil date', () => {
  it('uses that birthday, not the host year or clock', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2040-12-31T23:59:59Z'))
    expect(computeDailyTargetsOnCivilDate(profile, DEFAULT_CALC_CONFIG, '2026-10-25')).toEqual({
      calories_target: 2672,
      protein_target: 120,
    })
    expect(computeDailyTargetsOnCivilDate(profile, DEFAULT_CALC_CONFIG, '2026-10-26')).toEqual({
      calories_target: 2664,
      protein_target: 120,
    })
  })
  it.each([
    'Pacific/Honolulu',
    'Asia/Tokyo',
    'America/Sao_Paulo',
    'UTC',
  ])('produces identical output under host timezone %s', (timezone) => {
    vi.stubEnv('TZ', timezone)
    expect(
      computeDailyTargetsOnCivilDate(profile, DEFAULT_CALC_CONFIG, '2026-10-26').calories_target,
    ).toBe(2664)
  })
  it.each([
    'recomposicao',
    'manutencao',
    'ganho_massa',
  ] as const)('shares the existing %s formula and protein resolution', (protocol) => {
    vi.stubEnv('TZ', 'UTC')
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-10-25T12:00:00Z'))
    for (const bodyFat of [null, 24])
      for (const hunger of ['pouca', 'moderada', 'muita'] as const) {
        const row = {
          ...profile,
          current_protocol: protocol,
          body_fat_percent: bodyFat,
          hunger_level: hunger,
        }
        expect(computeDailyTargetsOnCivilDate(row, DEFAULT_CALC_CONFIG, '2026-10-25')).toEqual(
          computeDailyTargets(row, DEFAULT_CALC_CONFIG),
        )
      }
  })
  it('uses the same Katch and activity config without changing their math', () => {
    const row = { ...profile, body_fat_percent: 25 }
    const bmr = calcBMR(
      { sex: 'masculino', weightKg: 80, heightCm: 175, age: 35, bodyFatPercent: 25 },
      DEFAULT_CALC_CONFIG,
    )
    expect(
      computeDailyTargetsOnCivilDate(row, DEFAULT_CALC_CONFIG, '2026-10-25').calories_target,
    ).toBe(Math.round(calcTDEE(bmr, 'moderado', DEFAULT_CALC_CONFIG)))
  })
  it('keeps incomplete targets unknown, not zero or an inferred age', () => {
    for (const row of [
      null,
      { ...profile, birth_date: null },
      { ...profile, weight_kg: null },
      { ...profile, activity_level: null },
    ]) {
      expect(computeDailyTargetsOnCivilDate(row, DEFAULT_CALC_CONFIG, '2026-10-25')).toEqual({
        calories_target: null,
        protein_target: null,
      })
    }
  })
  it.each([
    '2026-02-29',
    '0000-01-01',
    '2026-10-25T00:00:00Z',
    '2026-10-2',
  ])('refuses an invalid civil evaluation date %s', (date) => {
    expect(() => computeDailyTargetsOnCivilDate(profile, DEFAULT_CALC_CONFIG, date)).toThrow()
  })
  it('refuses a future birthdate instead of calculating with a negative age', () => {
    expect(() =>
      computeDailyTargetsOnCivilDate(
        { ...profile, birth_date: '2027-01-01' },
        DEFAULT_CALC_CONFIG,
        '2026-10-25',
      ),
    ).toThrow()
  })
})
