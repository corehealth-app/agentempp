import { describe, it, expect } from 'vitest'
import { calcProteinTargetG, resolveProteinFactor } from '../src/nutrition.js'
import { DEFAULT_CALC_CONFIG } from '../src/calc-config.js'

// Roberto pediu (2026-05-15): protein_factors agora é flat 1.5 g/kg.
// Os testes do CASCATA mantêm cobertura usando um config explícito com os
// valores antigos — a LÓGICA da cascata continua válida pra qualquer config.
// O teste do default novo valida o valor de produção flat.
const cascadeCfg = {
  ...DEFAULT_CALC_CONFIG,
  protein_factors: {
    muita: 1.6,
    moderada: 1.8,
    pouca: 1.8,
    training_low: 1.7,
    optimal_mid_training: 1.9,
    optimal_high_training: 2.0,
  },
}

describe('resolveProteinFactor — cascata (lógica preservada)', () => {
  it('Priority 1: muita fome → factors.muita (perfil difícil)', () => {
    expect(resolveProteinFactor('muita', 5, cascadeCfg)).toBe(1.6)
    expect(resolveProteinFactor('muita', null, cascadeCfg)).toBe(1.6)
    expect(resolveProteinFactor('muita', 0, cascadeCfg)).toBe(1.6)
  })

  it('Priority 2: training < 3 → factors.training_low (mesmo se moderada/pouca)', () => {
    expect(resolveProteinFactor('moderada', 2, cascadeCfg)).toBe(1.7)
    expect(resolveProteinFactor('pouca', 1, cascadeCfg)).toBe(1.7)
    expect(resolveProteinFactor('moderada', 0, cascadeCfg)).toBe(1.7)
  })

  it('Priority 3: pouca + training ≥ 5 → factors.optimal_high_training', () => {
    expect(resolveProteinFactor('pouca', 5, cascadeCfg)).toBe(2.0)
    expect(resolveProteinFactor('pouca', 6, cascadeCfg)).toBe(2.0)
    expect(resolveProteinFactor('pouca', 7, cascadeCfg)).toBe(2.0)
  })

  it('Priority 4: pouca + training = 4 → factors.optimal_mid_training', () => {
    expect(resolveProteinFactor('pouca', 4, cascadeCfg)).toBe(1.9)
  })

  it('Default: moderada → factors.moderada', () => {
    expect(resolveProteinFactor('moderada', 3, cascadeCfg)).toBe(1.8)
    expect(resolveProteinFactor('moderada', 5, cascadeCfg)).toBe(1.8)
    expect(resolveProteinFactor('moderada', null, cascadeCfg)).toBe(1.8)
  })

  it('Pouca sem training info → factors.moderada (não atinge optimal)', () => {
    expect(resolveProteinFactor('pouca', null, cascadeCfg)).toBe(1.8)
    expect(resolveProteinFactor('pouca', undefined, cascadeCfg)).toBe(1.8)
  })

  it('Pouca + training=3 → factors.moderada (não atingiu threshold de 4)', () => {
    expect(resolveProteinFactor('pouca', 3, cascadeCfg)).toBe(1.8)
  })
})

describe('protein_factors — default de produção (2026-05-15: flat 1.5 g/kg)', () => {
  it('todos os fatores são 1.5 — Roberto pediu pra simplificar', () => {
    const f = DEFAULT_CALC_CONFIG.protein_factors
    expect(f.muita).toBe(1.5)
    expect(f.moderada).toBe(1.5)
    expect(f.pouca).toBe(1.5)
    expect(f.training_low).toBe(1.5)
    expect(f.optimal_mid_training).toBe(1.5)
    expect(f.optimal_high_training).toBe(1.5)
  })

  it('resolveProteinFactor retorna 1.5 pra qualquer combinação no default', () => {
    const cfg = DEFAULT_CALC_CONFIG
    expect(resolveProteinFactor('muita', 5, cfg)).toBe(1.5)
    expect(resolveProteinFactor('moderada', 2, cfg)).toBe(1.5)
    expect(resolveProteinFactor('pouca', 6, cfg)).toBe(1.5)
    expect(resolveProteinFactor('moderada', null, cfg)).toBe(1.5)
  })
})

describe('calcProteinTargetG — peso × fator (com cascadeCfg pra preservar variação)', () => {
  it('Roberto (99kg, moderada, 5 treinos) = 178.2g', () => {
    expect(calcProteinTargetG(99, 'moderada', cascadeCfg, 5)).toBeCloseTo(178.2, 1)
  })

  it('Luan-style (81kg, pouca, 5 treinos) = 162g (factor 2.0)', () => {
    expect(calcProteinTargetG(81, 'pouca', cascadeCfg, 5)).toBeCloseTo(162, 0)
  })

  it('Paciente sedentário (70kg, muita fome, 1 treino) = 112g (factor 1.6)', () => {
    expect(calcProteinTargetG(70, 'muita', cascadeCfg, 1)).toBeCloseTo(112, 0)
  })

  it('Paciente sem trainingFrequency (90kg, pouca) = 162g default', () => {
    expect(calcProteinTargetG(90, 'pouca', cascadeCfg)).toBeCloseTo(162, 0)
  })

  it('Default novo flat 1.5 — 62.5kg × 1.5 = 93.75g (caso Erika)', () => {
    expect(calcProteinTargetG(62.5, 'moderada', DEFAULT_CALC_CONFIG, 6)).toBeCloseTo(93.75, 1)
  })
})
