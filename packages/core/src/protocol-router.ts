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
import {
  DEFAULT_CALC_CONFIG,
  IMC_GOAL_STEP_POINTS,
  IMC_GOAL_STEP_POINTS_SANITY_MAX,
  type CalcConfig,
} from './calc-config.js'

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

/** A goal less than this many BMI points away is skipped (already in place). */
const IMC_GOAL_MIN_MARGIN = 1

/**
 * BMI points of one step of the first goal, or null when rule R3 is off.
 *
 * The value comes from a `global_config` row copied as it is by the loader, so
 * it is read as `unknown` (same reading as `fixedRecompProteinFactor`):
 *  - explicit `null` or `0` → off (the revert switch: the previous ladder);
 *  - a number in (0, IMC_GOAL_STEP_POINTS_SANITY_MAX] → that step;
 *  - anything else (absent key, text such as "5", NaN, a negative number, 50)
 *    → the code default. A typing mistake in the row must not switch the rule
 *    off without anyone noticing (review of 2026-10-04: the text "5" brought
 *    the previous ladder back, 32.7 → 30, with no error and no log).
 */
export function imcGoalStepPoints(config: CalcConfig = DEFAULT_CALC_CONFIG): number | null {
  const raw: unknown = config.imc_goal_step_points
  if (raw === null || raw === 0) return null
  if (typeof raw === 'number' && raw > 0 && raw <= IMC_GOAL_STEP_POINTS_SANITY_MAX) return raw
  return IMC_GOAL_STEP_POINTS
}

/**
 * First BMI goal.
 *
 * Above the normal range (`imc_limit_recomp`, 25) the goal drops
 * `imc_goal_step_points` (5) per step, to one decimal, and lands on 25 when the
 * step would stop less than 1 point above it: 32.7 → 27.7 → 25; 31 → 26;
 * 30.1 → 25. From there down it is the ladder of `imc_goal_steps` below 25
 * (23 → 22 → 21), as before.
 *
 * The rule lives here and not in the array because the array is overridden by
 * `global_config` at runtime (staging holds [30, 25, 23, 22, 21]).
 *
 * Stated by the client on 2026-01-26 (typed) and in his manual 9.4.3.1
 * (35→30, 34→29, 31→26). On 2026-02-07 he typed "perder 10 pontos do imc"
 * once; that conflict is open. Implemented on 2026-10-04 at Eduardo's request;
 * the client's confirmation is pending. Revert switch: `imc_goal_step_points`
 * null or 0 runs the previous ladder, untouched (any other value that is not a
 * usable step is the code default: see `imcGoalStepPoints`).
 */
export function calcIMCGoal(imc: number, config: CalcConfig = DEFAULT_CALC_CONFIG): number {
  const steps = config.imc_goal_steps
  const lowest = steps[steps.length - 1] ?? 21
  const stepPoints = imcGoalStepPoints(config)

  if (stepPoints == null) {
    for (const meta of steps) {
      if (imc - meta >= IMC_GOAL_MIN_MARGIN) return meta
    }
    return lowest
  }

  const normal = config.imc_limit_recomp
  if (imc - normal >= IMC_GOAL_MIN_MARGIN) {
    const stepped = Math.round((imc - stepPoints) * 10) / 10
    return stepped - normal < IMC_GOAL_MIN_MARGIN ? normal : stepped
  }
  for (const meta of steps) {
    if (meta < normal && imc - meta >= IMC_GOAL_MIN_MARGIN) return meta
  }
  return lowest
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
