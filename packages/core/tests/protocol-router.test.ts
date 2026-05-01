import { describe, expect, it } from 'vitest'
import { computeMetrics } from '../src/nutrition.js'
import { calcBFGoal, calcIMCGoal, resolveProtocol } from '../src/protocol-router.js'
import type { UserMetrics, UserProfile } from '../src/types.js'

const baseProfile: UserProfile = {
  sex: 'masculino',
  birthDate: new Date('1990-01-01'),
  heightCm: 180,
  weightKg: 90,
  bodyFatPercent: null,
  activityLevel: 'moderado',
  trainingFrequency: 5,
  waterIntake: 'moderado',
  hungerLevel: 'moderada',
  currentProtocol: null,
  goalType: null,
  goalValue: null,
  deficitLevel: null,
}

const baseMetrics: UserMetrics = {
  age: 36,
  bmr: 2000,
  activityFactor: 1.55,
  lbm: 72,
  imc: 22,
  proteinFactor: 1.8,
}

describe('calcBFGoal — escada progressiva', () => {
  it('BF > 30 → BF - 10 (arredondado)', () => {
    expect(calcBFGoal(35)).toBe(25)
    expect(calcBFGoal(45.5)).toBe(36)
  })

  it('escada: 30 → 20 → 18 → 15 → 10', () => {
    expect(calcBFGoal(28)).toBe(20)
    expect(calcBFGoal(22)).toBe(20)
    expect(calcBFGoal(20)).toBe(18)
    expect(calcBFGoal(18.5)).toBe(18)
    expect(calcBFGoal(17)).toBe(15)
    expect(calcBFGoal(14)).toBe(10)
  })
})

describe('calcIMCGoal — escada 30→25→23→22→21', () => {
  it('IMC alto desce de degrau em degrau', () => {
    expect(calcIMCGoal(30)).toBe(25)
    expect(calcIMCGoal(28)).toBe(25)
    expect(calcIMCGoal(24)).toBe(23)
    expect(calcIMCGoal(23.5)).toBe(22)
    expect(calcIMCGoal(22)).toBe(21)
  })

  it('IMC já saudável retorna meta mínima', () => {
    expect(calcIMCGoal(20)).toBe(21)
  })
})

describe('resolveProtocol — com BF', () => {
  it('homem com BF >= 20 → recomp obrigatória', () => {
    const decision = resolveProtocol({ ...baseProfile, bodyFatPercent: 25 }, baseMetrics)
    expect(decision.protocol).toBe('recomposicao')
    expect(decision.canChoose).toBe(false)
    expect(decision.blockers.length).toBeGreaterThan(0)
    expect(decision.goalType).toBe('BF')
    expect(decision.goalValue).toBe(20)
  })

  it('mulher com BF >= 28 → recomp obrigatória', () => {
    const decision = resolveProtocol(
      { ...baseProfile, sex: 'feminino', bodyFatPercent: 30 },
      baseMetrics,
    )
    expect(decision.protocol).toBe('recomposicao')
    expect(decision.canChoose).toBe(false)
  })

  it('homem com BF <= 19 + treino >= 3 → pode escolher', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: 17, trainingFrequency: 5 },
      baseMetrics,
    )
    expect(decision.canChoose).toBe(true)
    expect(decision.blockers).toEqual([])
  })

  it('homem com BF baixo mas treino insuficiente → recomp com blockers', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: 15, trainingFrequency: 1 },
      baseMetrics,
    )
    expect(decision.canChoose).toBe(false)
    expect(decision.blockers.some((b) => b.includes('musculação'))).toBe(true)
  })
})

describe('resolveProtocol — sem BF (fallback IMC)', () => {
  it('IMC >= 25 → recomp obrigatória', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: null },
      { ...baseMetrics, imc: 27 },
    )
    expect(decision.protocol).toBe('recomposicao')
    expect(decision.canChoose).toBe(false)
    expect(decision.goalType).toBe('IMC')
  })

  it('IMC < 25 + treino OK → pode escolher', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: null, trainingFrequency: 4 },
      { ...baseMetrics, imc: 22 },
    )
    expect(decision.canChoose).toBe(true)
    expect(decision.goalType).toBe('IMC')
  })

  it('IMC < 25 mas treino insuficiente → recomp', () => {
    const decision = resolveProtocol(
      { ...baseProfile, bodyFatPercent: null, trainingFrequency: 0 },
      { ...baseMetrics, imc: 22 },
    )
    expect(decision.canChoose).toBe(false)
    expect(decision.blockers.length).toBeGreaterThan(0)
  })
})

describe('resolveProtocol — integração com computeMetrics', () => {
  it('fluxo end-to-end: perfil real → métrica real → decisão', () => {
    const profile: UserProfile = {
      sex: 'masculino',
      birthDate: new Date('1985-06-15'),
      heightCm: 175,
      weightKg: 95,
      bodyFatPercent: 28,
      activityLevel: 'sedentario',
      trainingFrequency: 1,
      waterIntake: 'pouco',
      hungerLevel: 'muita',
      currentProtocol: null,
      goalType: null,
      goalValue: null,
      deficitLevel: null,
    }
    const metrics = computeMetrics(profile, new Date('2026-05-01'))
    const decision = resolveProtocol(profile, metrics)

    expect(decision.protocol).toBe('recomposicao')
    expect(decision.canChoose).toBe(false)
    expect(decision.goalType).toBe('BF')
    expect(decision.goalValue).toBe(20)
  })
})
