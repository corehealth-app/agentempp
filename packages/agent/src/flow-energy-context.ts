/**
 * The day's energy numbers as the Flow model reads them (pure, no I/O).
 *
 * iPhone, staging, 2026-10-04 — the patient asked in the Flow chat
 * "Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?"
 * and Flow answered "Sim! Sua meta já considera esse gasto…". The per-turn
 * context gave the model a single "Balanço calórico de hoje: -2761 kcal",
 * which is the NET balance (with exercise), under a generic label; the food
 * balance (2439 left) was nowhere, and no line said exercise frees no food.
 *
 * This module labels the two balances of docs/CALCULO-MPP.md §2 and states the
 * rule next to the numbers. Both numbers come from the same core functions
 * the Today screen uses. Flow channel only — the legacy WhatsApp context keeps
 * its two lines byte for byte.
 *
 * The day's balance (not the food line) is per protocol since 2026-10-04
 * (§2c, `dayEnergyBalance`): against the day's expenditure, with exercise
 * only in recomposição. Dito pelo cliente em 20/01/2026, 22/02/2026,
 * 23/02/2026 e 09/03/2026; implementado em 2026-10-04 a pedido do Eduardo;
 * confirmação do cliente pendente. Switch: DAY_BALANCE_AGAINST_EXPENDITURE.
 */
import {
  type CalcConfig,
  type DailyTargetByProtocol,
  dayEnergyBalance,
  eatingBalance,
  resolveDayBalanceInputs,
} from '@mpp/core'

/** What `dayEnergyBalance` needs besides the day's numbers. Server-owned. */
export interface FlowDayBalanceInputs {
  protocol: string | null
  gainSurplusMultiplier: number
  programmedDeficitKcal: number
  /**
   * False when the day's stored target was written under another protocol's
   * rule (the protocol changed after the first registration of the day): the
   * day then keeps the legacy balance. Absent = true.
   */
  targetMatchesProtocol?: boolean
}

/**
 * What the Flow context knows about the day row besides its totals, loaded
 * once per turn by the pipeline. Server-owned; never read from a payload.
 */
export interface FlowDayRow {
  /** `daily_snapshots.current_protocol` (written at closing). */
  protocol: string | null
  /** `daily_snapshots.calories_target`, when the day has one stored. */
  storedTargetKcal: number | null
  /** The target the profile gives NOW under each protocol's rule. */
  targetByProtocol: DailyTargetByProtocol | null
}

/**
 * The inputs of the day's balance for a Flow turn, from the profile, the
 * loaded calc config and the day row. A thin adapter over the core
 * `resolveDayBalanceInputs`, the same function the Today screen's service
 * calls, so the app and Flow say the same number: the effective protocol
 * (the day row's, else the profile's), the daily closer's programmed deficit
 * for that protocol (recomposição ? (deficit_level ?? 500) : 0), the
 * multiplier as a number, and whether the stored target of the day still
 * belongs to that protocol's rule. Without `day` nothing about the day row is
 * checked.
 */
export function flowDayBalanceInputs(
  profile: { currentProtocol: string | null; deficitLevel: number | null },
  calcConfig?: Pick<CalcConfig, 'ganho_massa_surplus_multiplier'>,
  day?: FlowDayRow | null,
): Required<FlowDayBalanceInputs> {
  return resolveDayBalanceInputs({
    profileProtocol: profile.currentProtocol,
    deficitLevel: profile.deficitLevel,
    gainSurplusMultiplier: calcConfig?.ganho_massa_surplus_multiplier,
    dayRowProtocol: day?.protocol,
    storedTargetKcal: day?.storedTargetKcal,
    targetByProtocol: day?.targetByProtocol,
  })
}

export interface FlowEnergyInput {
  /** The target printed in the same context (the day row's, else the profile's). */
  caloriesTarget: number | null | undefined
  caloriesConsumed: number
  exerciseCalories: number
  /** Absent/null = the legacy day balance (net, against the target). */
  protocol?: string | null
  /** `ganho_massa_surplus_multiplier` of the loaded calc config. */
  gainSurplusMultiplier?: number | null
  /** The closer's expression: recomposição ? (deficit_level ?? 500) : 0. */
  programmedDeficitKcal?: number | null
  /** False = the stored target is of another protocol's rule → legacy balance. */
  targetMatchesProtocol?: boolean
}

export interface FlowEnergyNumbers {
  target: number | null
  consumed: number
  exercise: number
  /** consumed − target, WITHOUT exercise (§2a). Negative = still left to eat. */
  food: number | null
  /** The day's balance of the protocol (§2c). Negative = deficit. */
  net: number | null
  /** What `net` was measured against, without exercise. Null with no target. */
  reference: number | null
  /** Whether the day's exercise is subtracted in `net`. */
  netIncludesExercise: boolean
  /** 'expenditure' = the rule of §2c; 'target' = the legacy net balance. */
  netBasis: 'expenditure' | 'target'
}

const finiteOrZero = (value: number): number => (Number.isFinite(value) ? value : 0)

export function flowEnergyNumbers(input: FlowEnergyInput): FlowEnergyNumbers {
  const t = input.caloriesTarget
  const target = t != null && Number.isFinite(t) && t > 0 ? t : null
  const consumed = finiteOrZero(input.caloriesConsumed)
  const exercise = finiteOrZero(input.exerciseCalories)
  const day =
    target == null
      ? null
      : dayEnergyBalance({
          protocol: input.protocol,
          caloriesConsumed: consumed,
          caloriesTarget: target,
          exerciseCalories: exercise,
          gainSurplusMultiplier: input.gainSurplusMultiplier,
          programmedDeficitKcal: input.programmedDeficitKcal,
          targetMatchesProtocol: input.targetMatchesProtocol,
        })
  return {
    target,
    consumed,
    exercise,
    // `+ 0` turns a rounded -0 into 0, so no line ever prints "-0".
    food: target == null ? null : Math.round(eatingBalance(consumed, target)) + 0,
    net: day == null ? null : Math.round(day.balance) + 0,
    reference: day == null ? null : Math.round(day.referenceKcal) + 0,
    netIncludesExercise: day?.includesExercise ?? true,
    netBasis: day?.basis ?? 'target',
  }
}

export interface FlowEnergyContextInput extends FlowEnergyInput {
  /**
   * False when the day has no row yet. Then only the food line and the rule
   * are printed: the legacy context has no balance line in the morning, and a
   * "-2980 déficit" there would be new and misleading.
   */
  hasSnapshot: boolean
}

/**
 * Lines for the "Dados numéricos REAIS" block of the Flow context. The
 * prefixes "Exercício hoje: N kcal queimadas" and "Balanço calórico de hoje"
 * are kept as substrings, in case a shared rule in the database cites them.
 */
export function flowEnergyContextLines(input: FlowEnergyContextInput): string[] {
  const n = flowEnergyNumbers(input)
  const recomp = input.protocol === 'recomposicao'
  const lines: string[] = []
  if (n.food != null) {
    lines.push(
      n.food > 0
        ? `- Para COMIDA hoje (consumido − meta, SEM exercício): excedente de ${n.food} kcal acima da meta`
        : `- Para COMIDA hoje (meta − consumido, SEM exercício): restam ${0 - n.food} kcal`,
    )
  }
  if (input.hasSnapshot) {
    lines.push(
      `- Exercício hoje: ${n.exercise} kcal queimadas — NÃO aumenta a meta e NÃO entra no que resta para comida`,
    )
    if (n.net != null) {
      // On the day the protocol changed, the legacy number is measured against
      // the OLD protocol's target, which the closer replaces at closing: the
      // recomposição wording "déficit programado − este número" would be
      // false there, so that day gets the plain legacy wording.
      lines.push(dayBalanceLine(n, recomp && input.targetMatchesProtocol !== false))
    }
  }
  // With a food surplus there is no "what is left" to show: the rule points
  // at the surplus instead of asking for a number the context does not have.
  const surplus = n.food != null && n.food > 0
  const whatCanBeEaten =
    n.food == null
      ? 'o que o paciente pode comer é só meta − consumido, sem exercício'
      : surplus
        ? 'a linha "Para COMIDA" mostra excedente, então não resta nada para comida hoje'
        : 'o que o paciente pode comer é só o que está na linha "Para COMIDA"'
  const whatToShow =
    n.food == null
      ? 'diga que o treino não muda isso'
      : surplus
        ? 'diga que o treino não muda isso e mostre meta, consumido e o excedente'
        : 'diga que o treino não muda isso e mostre meta, consumido e o que resta para comida'
  // The block wording is only for recomposição. In ganho de massa and
  // manutenção the workout "stays apart": it is not in the food line and, by
  // the client's rule (§2c), not in the day's balance either.
  lines.push(
    `- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; ${whatCanBeEaten}. Se ele perguntar se pode comer a mais porque treinou, ${whatToShow}; o gasto do treino fica à parte${recomp ? ' (acelera o bloco 7700)' : ''}.`,
  )
  return lines
}

/**
 * The "Balanço calórico de hoje" line. The prefix is kept in every shape.
 * `recomp` only chooses the wording of the legacy shape (block credit or not).
 */
function dayBalanceLine(n: FlowEnergyNumbers, recomp: boolean): string {
  const sign = '(negativo=déficit, positivo=superávit)'
  if (n.netBasis === 'target') {
    // Legacy (protocol not set, or the switch off): the text of before §2c.
    // This number is NOT the block credit: the closer credits planned
    // deficit − net balance, and only at the day's closing (§3). Calling it
    // "the number the block uses" led the model to quote it as the credit.
    const whatItIsNot = recomp
      ? 'o crédito do bloco 7700 só é calculado no fechamento do dia (déficit programado − este número); até lá o valor é provisório e NÃO é o que resta para comer'
      : 'NÃO é o que resta para comer'
    return `- Balanço calórico de hoje COM exercício (consumido − meta − exercício): ${n.net} kcal ${sign} — ${whatItIsNot}`
  }
  if (n.netIncludesExercise) {
    // Recomposição: consumed − (BMR × 1,2 + exercise) = minus the "déficit
    // real do dia". Provisional: the closer may credit another value on a
    // day that ends incomplete or under-logged (§3), and only at closing.
    return `- Balanço calórico de hoje COM exercício (consumido − gasto do dia; gasto do dia = ${n.reference} kcal de gasto de referência + ${n.exercise} kcal de exercício): ${n.net} kcal ${sign} — é o déficit ou superávit real do dia até agora, provisório até o dia fechar; o crédito no bloco 7700 só acontece no fechamento do dia e este número NÃO é o que resta para comer`
  }
  // Ganho de massa / manutenção: no exercise, and no block wording (the
  // client wrote on 08/05/2026 that a 14-day block replaces the 7700 block
  // in these protocols; that block is not defined yet).
  return `- Balanço calórico de hoje (consumido − gasto de referência de ${n.reference} kcal; o exercício já está considerado neste valor e não é somado): ${n.net} kcal ${sign} — NÃO é o que resta para comer`
}
