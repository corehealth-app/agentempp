/**
 * Meta calórica e de proteína (fonte única — engine).
 *
 * Fórmulas oficiais MPP (ver docs/CALCULO-MPP.md §1):
 *   recomposição: BMR × 1,2 (FIXO, atividade NÃO entra) − déficit
 *   ganho_massa:  TDEE × 1,05 (superávit leve)
 *   manutenção:   TDEE
 *
 * Função pura: recebe a linha do perfil + config, devolve targets. Sem I/O
 * (o carregamento do banco fica em @mpp/agent/calc-targets.loadDailyTargets).
 */
import { calcProteinTargetG, calcTDEE, computeMetrics } from '../nutrition.js'
import type { CalcConfig } from '../calc-config.js'
import type { UserProfile } from '../types.js'

export interface DailyTargets {
  calories_target: number | null
  protein_target: number | null
}

export interface ProfileRow {
  sex: 'masculino' | 'feminino' | null
  birth_date: string | null
  height_cm: number | null
  weight_kg: number | null
  body_fat_percent: number | null
  activity_level: 'sedentario' | 'leve' | 'moderado' | 'alto' | 'atleta' | null
  training_frequency: number | null
  water_intake: 'pouco' | 'moderado' | 'bastante' | null
  hunger_level: 'pouca' | 'moderada' | 'muita' | null
  current_protocol: 'recomposicao' | 'ganho_massa' | 'manutencao' | null
  goal_type: 'BF' | 'IMC' | null
  goal_value: number | null
  deficit_level: 400 | 500 | 600 | null
}

function rowToProfile(row: ProfileRow): UserProfile {
  return {
    sex: row.sex,
    birthDate: row.birth_date ? new Date(row.birth_date) : null,
    heightCm: row.height_cm,
    weightKg: row.weight_kg,
    bodyFatPercent: row.body_fat_percent,
    activityLevel: row.activity_level,
    trainingFrequency: row.training_frequency,
    waterIntake: row.water_intake,
    hungerLevel: row.hunger_level,
    currentProtocol: row.current_protocol,
    goalType: row.goal_type,
    goalValue: row.goal_value,
    deficitLevel: row.deficit_level,
  }
}

export function computeDailyTargets(
  profileRow: ProfileRow | null,
  config: CalcConfig,
): DailyTargets {
  if (!profileRow) return { calories_target: null, protein_target: null }

  const profile = rowToProfile(profileRow)
  const metrics = computeMetrics(profile, new Date(), config)

  if (metrics.bmr == null || profile.activityLevel == null) {
    return { calories_target: null, protein_target: null }
  }

  const tdee = calcTDEE(metrics.bmr, profile.activityLevel, config)

  let caloriesTarget: number
  switch (profile.currentProtocol) {
    case 'recomposicao': {
      const recompMultiplier = config.recomp_bmr_multiplier ?? 1.2
      const bmrBase = metrics.bmr * recompMultiplier
      caloriesTarget = bmrBase - (profile.deficitLevel ?? 500)
      break
    }
    case 'ganho_massa': {
      const surplusMultiplier = config.ganho_massa_surplus_multiplier ?? 1.05
      caloriesTarget = tdee * surplusMultiplier
      break
    }
    case 'manutencao':
    default:
      caloriesTarget = tdee
      break
  }

  const effectiveHunger = profile.hungerLevel ?? 'moderada'
  const proteinTarget =
    profile.weightKg != null
      ? calcProteinTargetG(profile.weightKg, effectiveHunger, config, profile.trainingFrequency)
      : null

  return {
    calories_target: Math.round(caloriesTarget),
    protein_target: proteinTarget != null ? Math.round(proteinTarget * 10) / 10 : null,
  }
}
