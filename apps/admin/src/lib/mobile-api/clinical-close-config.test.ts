import { calcDailyXP, DEFAULT_CALC_CONFIG } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { readClinicalCloseConfigRows } from './clinical-snapshot-calculation'

const at = '2026-10-26T12:00:00.000000Z'
const row = (key: string, value: unknown) => ({ key: `calc.${key}`, value, updated_at: at })
const legacy = { base: 4, training_bonus: 6, protein_bonus: 9, protein_threshold_g: 110 }

describe('fresh complete closer calculation config', () => {
  it('uses imported defaults only for whole absent keys, with independent copies', () => {
    const a = readClinicalCloseConfigRows([])
    expect(a.config).toEqual(DEFAULT_CALC_CONFIG)
    a.config.badges.length = 0
    expect(readClinicalCloseConfigRows([]).config.badges).toEqual(DEFAULT_CALC_CONFIG.badges)
  })
  it('preserves a legacy XP override without silently introducing MPP optional fields', () => {
    const { config } = readClinicalCloseConfigRows([row('xp_rules', legacy)])
    expect(config.xp_rules).toEqual(legacy)
    expect(Object.hasOwn(config.xp_rules, 'meal_xp')).toBe(false)
    expect(calcDailyXP({ trainingDone: true, proteinG: 110 }, config)).toBe(19)
  })
  it('retains the intentional zero-valued MPP selector and the existing no-target protein fallback', () => {
    const { config } = readClinicalCloseConfigRows([
      row('xp_rules', { ...legacy, meal_xp: 0, protein_meta_xp: 7 }),
    ])
    expect(calcDailyXP({ trainingDone: false, proteinG: 110 }, config)).toBe(7)
    expect(calcDailyXP({ trainingDone: false, proteinG: 109 }, config)).toBe(0)
  })
  it('keeps exact level order and empty badge or level overrides', () => {
    const levels = [
      { level: 3, name: 'custom first', min: 200, max: null },
      { level: 1, name: 'custom last', min: 0, max: 199 },
    ]
    expect(readClinicalCloseConfigRows([row('levels', levels)]).config.levels).toEqual(levels)
    const { config } = readClinicalCloseConfigRows([
      row('levels', []),
      row('badges', []),
      row('kcal_block', 5000),
    ])
    expect(config.levels).toEqual([])
    expect(config.badges).toEqual([])
    expect(config.kcal_block).toBe(5000)
  })
  it('reads changing rows without the legacy process cache', () => {
    expect(readClinicalCloseConfigRows([row('kcal_block', 7000)]).config.kcal_block).toBe(7000)
    expect(readClinicalCloseConfigRows([row('kcal_block', 8000)]).config.kcal_block).toBe(8000)
  })
  it.each([
    ['xp_rules', { base: 4 }],
    ['xp_rules', { ...legacy, protein_bonus: Number.NaN }],
    ['xp_rules', { ...legacy, unexpected: 1 }],
    ['levels', [{ level: 1, name: 'x', min: 0 }]],
    ['badges', [{ key: 'x', type: 'unknown', threshold: 1 }]],
    ['kcal_block', 0],
    ['kcal_block', Number.POSITIVE_INFINITY],
  ])('refuses malformed present %s instead of deep merging/defaulting', (key, value) => {
    expect(() => readClinicalCloseConfigRows([row(key as string, value)])).toThrow()
  })
  it('preserves duplicate/timestamp/formula validation of the existing parser', () => {
    expect(() =>
      readClinicalCloseConfigRows([row('kcal_block', 7000), row('kcal_block', 8000)]),
    ).toThrow()
    expect(() =>
      readClinicalCloseConfigRows([{ ...row('kcal_block', 7000), updated_at: 'bad' }]),
    ).toThrow()
    expect(() => readClinicalCloseConfigRows([row('protein_factors', { pouca: 1.8 })])).toThrow()
  })
})
