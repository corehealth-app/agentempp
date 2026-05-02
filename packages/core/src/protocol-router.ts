/**
 * Roteamento determinístico de protocolo.
 * Replica a lógica do nó "User Route" do n8n original.
 *
 * Fluxo:
 *   1. Se BF disponível → decide por BF
 *   2. Senão → decide por IMC
 *   3. Treino abaixo de training_min é blocker para "ganho_massa"
 *   4. Default sempre é "recomposicao" (mais conservador)
 */
import type { ProtocolDecision, UserMetrics, UserProfile } from './types.js'
import { DEFAULT_CALC_CONFIG, type CalcConfig } from './calc-config.js'

export function calcBFGoal(bf: number, config: CalcConfig = DEFAULT_CALC_CONFIG): number {
  for (const rule of config.bf_goal_rules) {
    if (bf > rule.above) {
      if ('subtract' in rule) return Math.round(bf - rule.subtract)
      return rule.target
    }
  }
  // Fallback (não deveria chegar aqui se houver regra com above:0)
  return 10
}

export function calcIMCGoal(imc: number, config: CalcConfig = DEFAULT_CALC_CONFIG): number {
  for (const meta of config.imc_goal_steps) {
    if (imc - meta >= 1) return meta
  }
  return config.imc_goal_steps[config.imc_goal_steps.length - 1] ?? 21
}

export function resolveProtocol(
  profile: UserProfile,
  metrics: UserMetrics,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): ProtocolDecision {
  if (!profile.sex) {
    throw new Error('Cannot resolve protocol without sex defined')
  }

  const limits = config.bf_limits[profile.sex]
  const blockers: string[] = []

  const trainingFreq = profile.trainingFrequency ?? 0
  if (trainingFreq < config.training_min) {
    blockers.push(
      `musculação insuficiente (atual: ${trainingFreq}x/semana, mínimo: ${config.training_min}x)`,
    )
  }

  // ----- Decisão por BF (preferencial) -----
  if (profile.bodyFatPercent != null) {
    const bf = profile.bodyFatPercent
    const goalValue = calcBFGoal(bf, config)

    if (bf >= limits.recomp) {
      return {
        protocol: 'recomposicao',
        canChoose: false,
        blockers: ['gordura corporal acima do limite para ganho de massa'],
        goalType: 'BF',
        goalValue,
      }
    }

    if (bf <= limits.gain && blockers.length === 0) {
      return {
        protocol: 'recomposicao',
        canChoose: true,
        blockers: [],
        goalType: 'BF',
        goalValue,
      }
    }

    return {
      protocol: 'recomposicao',
      canChoose: false,
      blockers,
      goalType: 'BF',
      goalValue,
    }
  }

  // ----- Decisão por IMC (fallback) -----
  if (metrics.imc == null) {
    throw new Error('Cannot resolve protocol without BF or IMC')
  }

  const goalValue = calcIMCGoal(metrics.imc, config)

  if (metrics.imc >= config.imc_limit_recomp) {
    return {
      protocol: 'recomposicao',
      canChoose: false,
      blockers: ['IMC acima do limite saudável para ganho de massa'],
      goalType: 'IMC',
      goalValue,
    }
  }

  if (blockers.length === 0) {
    return {
      protocol: 'recomposicao',
      canChoose: true,
      blockers: [],
      goalType: 'IMC',
      goalValue,
    }
  }

  return {
    protocol: 'recomposicao',
    canChoose: false,
    blockers,
    goalType: 'IMC',
    goalValue,
  }
}
