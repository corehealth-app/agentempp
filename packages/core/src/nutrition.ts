/**
 * Cálculos nutricionais determinísticos.
 * Replica as fórmulas do Notion (Mifflin-St Jeor + Katch-McArdle).
 *
 * Todas as funções aceitam um CalcConfig opcional; sem ele usa
 * DEFAULT_CALC_CONFIG (constantes científicas padrão).
 */
import type { ActivityLevel, HungerLevel, Sex, UserMetrics, UserProfile } from './types.js'
import { DEFAULT_CALC_CONFIG, type CalcConfig } from './calc-config.js'

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
export function calcBMR(
  args: {
    sex: Sex
    weightKg: number
    heightCm: number
    age: number
    bodyFatPercent?: number | null
  },
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): number {
  const { sex, weightKg, heightCm, age, bodyFatPercent } = args

  if (bodyFatPercent != null && bodyFatPercent > 0) {
    const lbm = weightKg * (1 - bodyFatPercent / 100)
    return config.bmr_katch.base + config.bmr_katch.lbm_coef * lbm
  }

  const m = config.bmr_mifflin
  const base = m.weight_coef * weightKg + m.height_coef * heightCm - m.age_coef * age
  return sex === 'masculino' ? base + m.male_offset : base + m.female_offset
}

export function calcTDEE(
  bmr: number,
  activity: ActivityLevel,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): number {
  return bmr * config.activity_factors[activity]
}

export function calcLBM(weightKg: number, bodyFatPercent: number | null): number {
  if (bodyFatPercent == null) return weightKg
  return weightKg * (1 - bodyFatPercent / 100)
}

export function calcIMC(weightKg: number, heightCm: number): number {
  const heightM = heightCm / 100
  return weightKg / (heightM * heightM)
}

export function calcProteinTargetG(
  weightKg: number,
  hunger: HungerLevel,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
  trainingFrequency?: number | null,
): number {
  return weightKg * resolveProteinFactor(hunger, trainingFrequency, config)
}

/**
 * Resolve o fator de proteína (g/kg) seguindo a lógica oficial MPP do Notion.
 *
 * Cascata por prioridade:
 *   1. Muita fome (perfil comportamental difícil) → 1.6
 *   2. Training < 3 dias/sem → 1.7
 *   3. Pouca fome + Training ≥ 5 (perfil ótimo) → 2.0
 *   4. Pouca fome + Training ≥ 4 (quase-ótimo) → 1.9
 *   5. Default (inclui moderada) → 1.8
 *
 * Notion tem +3 fatores comportamentais (Diet History, Routine Stability,
 * Rule Following) que ainda não coletamos no onboarding. Quando coletarmos,
 * adicionar aqui pra completar a cascata oficial.
 *
 * Bug histórico: antes era simples lookup `protein_factors[hunger]` com
 * mapping invertido (pouca→1.6, muita→2.0) — exatamente o oposto da doc MPP.
 */
export function resolveProteinFactor(
  hunger: HungerLevel,
  trainingFrequency: number | null | undefined,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): number {
  const factors = config.protein_factors
  // Priority 1: perfil comportamental difícil
  if (hunger === 'muita') return factors.muita
  // Priority 2: training baixo
  if (trainingFrequency != null && trainingFrequency < 3) return factors.training_low ?? 1.7
  // Priority 3: perfil ótimo + training alto
  if (hunger === 'pouca' && trainingFrequency != null && trainingFrequency >= 5) {
    return factors.optimal_high_training ?? 2.0
  }
  // Priority 4: perfil ótimo + training moderado-alto
  if (hunger === 'pouca' && trainingFrequency != null && trainingFrequency >= 4) {
    return factors.optimal_mid_training ?? 1.9
  }
  // Default: moderada ou sem dado
  return factors.moderada
}

/**
 * Computa todas as métricas derivadas de um perfil.
 */
export function computeMetrics(
  profile: UserProfile,
  today: Date = new Date(),
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): UserMetrics {
  const age = profile.birthDate ? calcAge(profile.birthDate, today) : null

  const bmr =
    profile.sex && profile.weightKg && profile.heightCm && age != null
      ? calcBMR(
          {
            sex: profile.sex,
            weightKg: profile.weightKg,
            heightCm: profile.heightCm,
            age,
            bodyFatPercent: profile.bodyFatPercent,
          },
          config,
        )
      : null

  const activityFactor = profile.activityLevel
    ? config.activity_factors[profile.activityLevel]
    : null

  const lbm =
    profile.weightKg != null ? calcLBM(profile.weightKg, profile.bodyFatPercent) : null

  const imc =
    profile.weightKg && profile.heightCm ? calcIMC(profile.weightKg, profile.heightCm) : null

  const proteinFactor = profile.hungerLevel
    ? resolveProteinFactor(profile.hungerLevel, profile.trainingFrequency, config)
    : null

  return { age, bmr, activityFactor, lbm, imc, proteinFactor }
}
