import { describe, it, expect } from 'vitest'
import { computeDailyTargets, type ProfileRow } from './targets.js'
import { DEFAULT_CALC_CONFIG } from '../calc-config.js'

const cfg = DEFAULT_CALC_CONFIG

const completo: ProfileRow = {
  sex: 'masculino',
  birth_date: '1990-01-01',
  height_cm: 175,
  weight_kg: 80,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'recomposicao',
  goal_type: 'BF',
  goal_value: 15,
  deficit_level: 500,
}

describe('computeDailyTargets', () => {
  it('perfil null → { null, null }', () => {
    expect(computeDailyTargets(null, cfg)).toEqual({ calories_target: null, protein_target: null })
  })

  it('sem activity_level → { null, null }', () => {
    expect(computeDailyTargets({ ...completo, activity_level: null }, cfg)).toEqual({
      calories_target: null,
      protein_target: null,
    })
  })

  it('recomposição → meta e proteína positivas e inteiras', () => {
    const t = computeDailyTargets(completo, cfg)
    expect(t.calories_target).toBeGreaterThan(0)
    expect(Number.isInteger(t.calories_target)).toBe(true)
    expect(t.protein_target).toBeGreaterThan(0)
  })

  it('switch de protocolo: ganho_massa > manutenção > 0 (mesmo perfil)', () => {
    const ganho = computeDailyTargets({ ...completo, current_protocol: 'ganho_massa' }, cfg)
      .calories_target!
    const manut = computeDailyTargets({ ...completo, current_protocol: 'manutencao' }, cfg)
      .calories_target!
    expect(ganho).toBeGreaterThan(manut)
    expect(manut).toBeGreaterThan(0)
  })

  it('recomp = BMR×1,2 − déficit (déficit maior → meta menor)', () => {
    const d400 = computeDailyTargets({ ...completo, deficit_level: 400 }, cfg).calories_target!
    const d600 = computeDailyTargets({ ...completo, deficit_level: 600 }, cfg).calories_target!
    expect(d400 - d600).toBe(200) // só o déficit muda
  })
})
