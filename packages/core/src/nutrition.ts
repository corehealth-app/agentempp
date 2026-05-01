/**
 * Cálculos nutricionais determinísticos.
 * Replica as fórmulas do Notion (Mifflin-St Jeor + Katch-McArdle).
 */
import type { ActivityLevel, HungerLevel, Sex, UserMetrics, UserProfile } from './types.js'

const ACTIVITY_FACTOR: Record<ActivityLevel, number> = {
  sedentario: 1.2,
  leve: 1.375,
  moderado: 1.55,
  alto: 1.725,
  atleta: 1.9,
}

const PROTEIN_FACTOR: Record<HungerLevel, number> = {
  pouca: 1.6,
  moderada: 1.8,
  muita: 2.0,
}

export function calcAge(birthDate: Date, today: Date = new Date()): number {
  let age = today.getFullYear() - birthDate.getFullYear()
  const monthDiff = today.getMonth() - birthDate.getMonth()
  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
    age--
  }
  return age
}

/**
 * BMR via Katch-McArdle quando há %BF, senão Mifflin-St Jeor.
 */
export function calcBMR(args: {
  sex: Sex
  weightKg: number
  heightCm: number
  age: number
  bodyFatPercent?: number | null
}): number {
  const { sex, weightKg, heightCm, age, bodyFatPercent } = args

  if (bodyFatPercent != null && bodyFatPercent > 0) {
    const lbm = weightKg * (1 - bodyFatPercent / 100)
    return 370 + 21.6 * lbm
  }

  const base = 10 * weightKg + 6.25 * heightCm - 5 * age
  return sex === 'masculino' ? base + 5 : base - 161
}

export function calcTDEE(bmr: number, activity: ActivityLevel): number {
  return bmr * ACTIVITY_FACTOR[activity]
}

export function calcLBM(weightKg: number, bodyFatPercent: number | null): number {
  if (bodyFatPercent == null) return weightKg
  return weightKg * (1 - bodyFatPercent / 100)
}

export function calcIMC(weightKg: number, heightCm: number): number {
  const heightM = heightCm / 100
  return weightKg / (heightM * heightM)
}

export function calcProteinTargetG(weightKg: number, hunger: HungerLevel): number {
  return weightKg * PROTEIN_FACTOR[hunger]
}

/**
 * Computa todas as métricas derivadas de um perfil.
 */
export function computeMetrics(profile: UserProfile, today: Date = new Date()): UserMetrics {
  const age = profile.birthDate ? calcAge(profile.birthDate, today) : null

  const bmr =
    profile.sex && profile.weightKg && profile.heightCm && age != null
      ? calcBMR({
          sex: profile.sex,
          weightKg: profile.weightKg,
          heightCm: profile.heightCm,
          age,
          bodyFatPercent: profile.bodyFatPercent,
        })
      : null

  const activityFactor = profile.activityLevel ? ACTIVITY_FACTOR[profile.activityLevel] : null

  const lbm =
    profile.weightKg != null ? calcLBM(profile.weightKg, profile.bodyFatPercent) : null

  const imc =
    profile.weightKg && profile.heightCm ? calcIMC(profile.weightKg, profile.heightCm) : null

  const proteinFactor = profile.hungerLevel ? PROTEIN_FACTOR[profile.hungerLevel] : null

  return { age, bmr, activityFactor, lbm, imc, proteinFactor }
}
