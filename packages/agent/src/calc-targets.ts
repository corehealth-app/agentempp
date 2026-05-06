/**
 * Computa calories_target e protein_target pra um paciente.
 *
 * Usado quando criamos/atualizamos daily_snapshots — popula campos
 * que antes ficavam null e quebravam o cálculo de bloco 7700.
 *
 * Fluxo:
 *   1. Lê user_profiles (sex, weight, height, birth, BF%, activity, hunger, deficit_level)
 *   2. computeMetrics → BMR + activityFactor → TDEE
 *   3. calories_target = TDEE - deficit_level
 *   4. protein_target = peso × protein_factor (do hunger_level)
 *
 * Sem perfil completo → retorna null/null (snapshot fica sem target,
 * comportamento legado mantido).
 */
import {
  calcProteinTargetG,
  calcTDEE,
  computeMetrics,
  type CalcConfig,
  type UserProfile,
} from '@mpp/core'

export interface DailyTargets {
  calories_target: number | null
  protein_target: number | null
}

interface ProfileRow {
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

  // Sem BMR ou activity, não dá pra calcular target → fallback null
  if (metrics.bmr == null || profile.activityLevel == null) {
    return { calories_target: null, protein_target: null }
  }

  const tdee = calcTDEE(metrics.bmr, profile.activityLevel, config)

  // Fórmulas oficiais MPP (doc Notion / regra agent_rules.recomposicao-meta-calorica)
  //
  // recomposição:  BMR × 1,2 (FIXO — atividade NÃO entra) − déficit
  //                Doc: "a meta calórica é calculada apenas pela dieta;
  //                exercício nunca entra no cálculo principal"
  //
  // ganho_massa:   BMR × fator_atividade × 1,05 (superávit leve)
  //                Doc: "evita superávit fraco e exagerado, ganho limpo"
  //
  // manutencao:    BMR × fator_atividade (sem ajuste, igual TDEE)
  //                Doc: "manutenção é definida por resposta real do corpo"
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

  // protein_target = peso × fator de fome.
  // Sem hunger_level salvo, usa 'moderada' (1.8g/kg) como default razoável.
  // Antes retornava null e o cron de engajamento alucinava o valor.
  const effectiveHunger = profile.hungerLevel ?? 'moderada'
  const proteinTarget =
    profile.weightKg != null
      ? calcProteinTargetG(profile.weightKg, effectiveHunger, config)
      : null

  return {
    calories_target: Math.round(caloriesTarget),
    protein_target: proteinTarget != null ? Math.round(proteinTarget * 10) / 10 : null,
  }
}

/**
 * Carrega user_profile + computa targets — atalho usado em hot paths.
 */
export async function loadDailyTargets(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  svc: any,
  userId: string,
  config: CalcConfig,
): Promise<DailyTargets> {
  const { data } = await svc
    .from('user_profiles')
    .select(
      'sex, birth_date, height_cm, weight_kg, body_fat_percent, activity_level, training_frequency, water_intake, hunger_level, current_protocol, goal_type, goal_value, deficit_level',
    )
    .eq('user_id', userId)
    .maybeSingle()
  return computeDailyTargets(data ?? null, config)
}
