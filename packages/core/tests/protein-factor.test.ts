import { describe, it, expect } from 'vitest'
import { calcProteinTargetG, resolveProteinFactor } from '../src/nutrition.js'
import { DEFAULT_CALC_CONFIG } from '../src/calc-config.js'

const cfg = DEFAULT_CALC_CONFIG

describe('resolveProteinFactor — cascata oficial Notion', () => {
  it('Priority 1: muita fome → 1.6 (perfil difícil)', () => {
    expect(resolveProteinFactor('muita', 5, cfg)).toBe(1.6)
    expect(resolveProteinFactor('muita', null, cfg)).toBe(1.6)
    expect(resolveProteinFactor('muita', 0, cfg)).toBe(1.6)
  })

  it('Priority 2: training < 3 → 1.7 (mesmo se moderada/pouca)', () => {
    expect(resolveProteinFactor('moderada', 2, cfg)).toBe(1.7)
    expect(resolveProteinFactor('pouca', 1, cfg)).toBe(1.7)
    expect(resolveProteinFactor('moderada', 0, cfg)).toBe(1.7)
  })

  it('Priority 3: pouca + training ≥ 5 → 2.0', () => {
    expect(resolveProteinFactor('pouca', 5, cfg)).toBe(2.0)
    expect(resolveProteinFactor('pouca', 6, cfg)).toBe(2.0)
    expect(resolveProteinFactor('pouca', 7, cfg)).toBe(2.0)
  })

  it('Priority 4: pouca + training = 4 → 1.9', () => {
    expect(resolveProteinFactor('pouca', 4, cfg)).toBe(1.9)
  })

  it('Default: moderada → 1.8', () => {
    expect(resolveProteinFactor('moderada', 3, cfg)).toBe(1.8)
    expect(resolveProteinFactor('moderada', 5, cfg)).toBe(1.8)
    expect(resolveProteinFactor('moderada', null, cfg)).toBe(1.8)
  })

  it('Pouca sem training info → 1.8 default (não 2.0)', () => {
    // Sem trainingFrequency, não dá pra subir pra 2.0
    expect(resolveProteinFactor('pouca', null, cfg)).toBe(1.8)
    expect(resolveProteinFactor('pouca', undefined, cfg)).toBe(1.8)
  })

  it('Pouca + training=3 → 1.8 (não atingiu threshold de 4)', () => {
    expect(resolveProteinFactor('pouca', 3, cfg)).toBe(1.8)
  })
})

describe('calcProteinTargetG — peso × fator', () => {
  it('Roberto (99kg, moderada, 5 treinos) = 178.2g', () => {
    expect(calcProteinTargetG(99, 'moderada', cfg, 5)).toBeCloseTo(178.2, 1)
  })

  it('Luan-style (81kg, pouca, 5 treinos) = 162g (factor 2.0)', () => {
    expect(calcProteinTargetG(81, 'pouca', cfg, 5)).toBeCloseTo(162, 0)
  })

  it('Paciente sedentário (70kg, muita fome, 1 treino) = 112g (factor 1.6)', () => {
    expect(calcProteinTargetG(70, 'muita', cfg, 1)).toBeCloseTo(112, 0)
  })

  it('Paciente sem trainingFrequency (90kg, pouca) = 162g default', () => {
    expect(calcProteinTargetG(90, 'pouca', cfg)).toBeCloseTo(162, 0) // 90 × 1.8
  })
})
