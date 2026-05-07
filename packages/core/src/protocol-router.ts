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

/**
 * Calcula horas de sono a partir de bedTime/wakeTime (HH:MM).
 * Trata virada de meia-noite. Auto-corrige inversão (>12h vira 24-h).
 * Replica n8n code do Notion.
 */
export function calcSleepHours(
  bedTime: string | null | undefined,
  wakeTime: string | null | undefined,
): number | null {
  if (!bedTime || !wakeTime) return null
  const bed = bedTime.split(':').map(Number)
  const wake = wakeTime.split(':').map(Number)
  if (bed.length < 2 || wake.length < 2) return null
  const [bh, bm] = bed
  const [wh, wm] = wake
  if ([bh, bm, wh, wm].some((n) => n == null || Number.isNaN(n))) return null
  let bedMin = bh! * 60 + bm!
  let wakeMin = wh! * 60 + wm!
  if (wakeMin <= bedMin) wakeMin += 24 * 60 // virada de meia-noite
  let hours = (wakeMin - bedMin) / 60
  // Se >12h, provavelmente os campos foram invertidos pelo paciente.
  if (hours > 12) hours = 24 - hours
  return hours
}

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

  // Critérios oficiais Notion pra Ganho de Massa (TODOS obrigatórios):
  // - Treino ≥ 3x/sem (acima)
  // - Sono ≥ 6h30/noite
  // - Alimentação estruturada (foodOrganization='sim')
  const sleepHours = calcSleepHours(profile.bedTime, profile.wakeTime)
  const sleepMin = config.sleep_min_hours
  if (sleepHours != null && sleepHours < sleepMin) {
    blockers.push(
      `sono insuficiente (${sleepHours.toFixed(1)}h, mínimo ${sleepMin.toFixed(1)}h)`,
    )
  } else if (sleepHours == null) {
    blockers.push('horários de sono não informados')
  }
  if (profile.foodOrganization === 'nao') {
    blockers.push('alimentação não estruturada')
  } else if (profile.foodOrganization == null) {
    blockers.push('estruturação alimentar não informada')
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
