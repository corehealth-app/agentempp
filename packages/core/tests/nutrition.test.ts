import { describe, expect, it } from 'vitest'
import {
  calcAge,
  calcBMR,
  calcIMC,
  calcLBM,
  calcProteinTargetG,
  calcTDEE,
  computeMetrics,
} from '../src/nutrition.js'
import type { UserProfile } from '../src/types.js'

describe('calcAge', () => {
  it('calcula idade simples', () => {
    expect(calcAge(new Date('1990-01-01'), new Date('2026-05-01'))).toBe(36)
  })

  it('considera mês/dia (aniversário não passou)', () => {
    expect(calcAge(new Date('1990-12-31'), new Date('2026-05-01'))).toBe(35)
  })

  it('aniversário hoje', () => {
    expect(calcAge(new Date('1990-05-01'), new Date('2026-05-01'))).toBe(36)
  })
})

describe('calcBMR', () => {
  it('Mifflin-St Jeor — masculino sem BF', () => {
    // 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780
    expect(calcBMR({ sex: 'masculino', weightKg: 80, heightCm: 180, age: 30 })).toBe(1780)
  })

  it('Mifflin-St Jeor — feminino sem BF', () => {
    // 10*60 + 6.25*165 - 5*30 - 161 = 600 + 1031.25 - 150 - 161 = 1320.25
    expect(calcBMR({ sex: 'feminino', weightKg: 60, heightCm: 165, age: 30 })).toBe(1320.25)
  })

  it('Katch-McArdle — quando há BF', () => {
    // LBM = 80 * (1 - 20/100) = 64; BMR = 370 + 21.6*64 = 370 + 1382.4 = 1752.4
    expect(
      calcBMR({ sex: 'masculino', weightKg: 80, heightCm: 180, age: 30, bodyFatPercent: 20 }),
    ).toBeCloseTo(1752.4, 1)
  })
})

describe('calcTDEE', () => {
  it('multiplica BMR pelo fator de atividade', () => {
    expect(calcTDEE(1800, 'sedentario')).toBe(2160) // 1.2
    expect(calcTDEE(1800, 'leve')).toBe(2475) // 1.375
    expect(calcTDEE(1800, 'moderado')).toBe(2790) // 1.55
    expect(calcTDEE(1800, 'alto')).toBe(3105) // 1.725
    expect(calcTDEE(1800, 'atleta')).toBe(3420) // 1.9
  })
})

describe('calcLBM', () => {
  it('com BF retorna massa magra', () => {
    expect(calcLBM(80, 25)).toBe(60)
  })

  it('sem BF retorna o peso (fallback conservador)', () => {
    expect(calcLBM(80, null)).toBe(80)
  })
})

describe('calcIMC', () => {
  it('peso/altura² em metros', () => {
    expect(calcIMC(80, 180)).toBeCloseTo(24.69, 2)
    expect(calcIMC(60, 165)).toBeCloseTo(22.04, 2)
  })
})

describe('calcProteinTargetG', () => {
  it('aplica fator por hunger level', () => {
    expect(calcProteinTargetG(80, 'pouca')).toBe(128) // 1.6
    expect(calcProteinTargetG(80, 'moderada')).toBe(144) // 1.8
    expect(calcProteinTargetG(80, 'muita')).toBe(160) // 2.0
  })
})

describe('computeMetrics', () => {
  it('integra todas as métricas de um perfil completo', () => {
    const profile: UserProfile = {
      sex: 'masculino',
      birthDate: new Date('1990-01-01'),
      heightCm: 180,
      weightKg: 80,
      bodyFatPercent: 20,
      activityLevel: 'moderado',
      trainingFrequency: 5,
      waterIntake: 'moderado',
      hungerLevel: 'moderada',
      currentProtocol: null,
      goalType: null,
      goalValue: null,
      deficitLevel: null,
    }
    const m = computeMetrics(profile, new Date('2026-05-01'))

    expect(m.age).toBe(36)
    expect(m.bmr).toBeCloseTo(1752.4, 1) // Katch-McArdle
    expect(m.activityFactor).toBe(1.55)
    expect(m.lbm).toBe(64)
    expect(m.imc).toBeCloseTo(24.69, 2)
    expect(m.proteinFactor).toBe(1.8)
  })

  it('retorna nulls quando perfil incompleto', () => {
    const profile: UserProfile = {
      sex: null,
      birthDate: null,
      heightCm: null,
      weightKg: null,
      bodyFatPercent: null,
      activityLevel: null,
      trainingFrequency: null,
      waterIntake: null,
      hungerLevel: null,
      currentProtocol: null,
      goalType: null,
      goalValue: null,
      deficitLevel: null,
    }
    const m = computeMetrics(profile)

    expect(m.age).toBeNull()
    expect(m.bmr).toBeNull()
    expect(m.activityFactor).toBeNull()
    expect(m.imc).toBeNull()
  })
})
