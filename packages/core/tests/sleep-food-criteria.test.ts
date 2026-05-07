import { describe, expect, it } from 'vitest'
import { calcSleepHours, resolveProtocol } from '../src/protocol-router.js'
import type { UserMetrics, UserProfile } from '../src/types.js'

describe('calcSleepHours', () => {
  it('calcula horas com virada de meia-noite', () => {
    expect(calcSleepHours('23:00', '07:00')).toBe(8)
    expect(calcSleepHours('22:30', '06:30')).toBe(8)
    expect(calcSleepHours('00:00', '06:00')).toBe(6)
  })

  it('auto-corrige inversão de campos (>12h vira 24-x)', () => {
    // Paciente trocou bedTime/wakeTime: 07:00 → 23:00 = 16h. Sistema corrige pra 8h.
    expect(calcSleepHours('07:00', '23:00')).toBe(8)
  })

  it('retorna null quando faltar dado', () => {
    expect(calcSleepHours(null, '07:00')).toBe(null)
    expect(calcSleepHours('23:00', null)).toBe(null)
    expect(calcSleepHours(undefined, undefined)).toBe(null)
    expect(calcSleepHours('garbage', '07:00')).toBe(null)
  })

  it('formato HH:MM válido', () => {
    expect(calcSleepHours('23:30', '07:00')).toBe(7.5)
  })
})

describe('resolveProtocol — critérios novos Notion (sono + alimentação)', () => {
  const baseMetrics: UserMetrics = {
    age: 30,
    bmr: 2000,
    activityFactor: 1.55,
    lbm: 65,
    imc: 22,
    proteinFactor: 1.8,
  }

  const baseProfile: UserProfile = {
    sex: 'masculino',
    birthDate: new Date('1990-01-01'),
    heightCm: 180,
    weightKg: 80,
    bodyFatPercent: 17, // baixo, qualifica pra ganho
    activityLevel: 'moderado',
    trainingFrequency: 5, // ≥3
    waterIntake: 'moderado',
    hungerLevel: 'moderada',
    currentProtocol: null,
    goalType: null,
    goalValue: null,
    deficitLevel: null,
    bedTime: '23:00',
    wakeTime: '07:00', // 8h sono
    foodOrganization: 'sim',
  }

  it('com todos critérios → canChoose=true', () => {
    const r = resolveProtocol(baseProfile, baseMetrics)
    expect(r.canChoose).toBe(true)
    expect(r.blockers).toEqual([])
  })

  it('sono < 6h30 → bloqueia ganho', () => {
    const r = resolveProtocol(
      { ...baseProfile, bedTime: '01:00', wakeTime: '06:00' }, // 5h
      baseMetrics,
    )
    expect(r.canChoose).toBe(false)
    expect(r.blockers.some((b) => b.includes('sono'))).toBe(true)
  })

  it('foodOrganization=nao → bloqueia ganho', () => {
    const r = resolveProtocol({ ...baseProfile, foodOrganization: 'nao' }, baseMetrics)
    expect(r.canChoose).toBe(false)
    expect(r.blockers.some((b) => b.includes('alimentação'))).toBe(true)
  })

  it('bedTime/wakeTime ausente → bloqueia (sem dado)', () => {
    const r = resolveProtocol(
      { ...baseProfile, bedTime: null, wakeTime: null },
      baseMetrics,
    )
    expect(r.canChoose).toBe(false)
    expect(r.blockers.some((b) => b.includes('sono'))).toBe(true)
  })
})
