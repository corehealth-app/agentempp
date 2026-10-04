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
 * rule next to the numbers. No formula changes: both numbers come from the
 * same core functions the Today screen uses. Flow channel only — the legacy
 * WhatsApp context keeps its two lines byte for byte.
 */
import { eatingBalance, netBalance } from '@mpp/core'

export interface FlowEnergyInput {
  /** The target printed in the same context (the day row's, else the profile's). */
  caloriesTarget: number | null | undefined
  caloriesConsumed: number
  exerciseCalories: number
  protocol?: string | null
}

export interface FlowEnergyNumbers {
  target: number | null
  consumed: number
  exercise: number
  /** consumed − target, WITHOUT exercise (§2a). Negative = still left to eat. */
  food: number | null
  /** consumed − target − exercise (§2b). */
  net: number | null
}

const finiteOrZero = (value: number): number => (Number.isFinite(value) ? value : 0)

export function flowEnergyNumbers(input: FlowEnergyInput): FlowEnergyNumbers {
  const t = input.caloriesTarget
  const target = t != null && Number.isFinite(t) && t > 0 ? t : null
  const consumed = finiteOrZero(input.caloriesConsumed)
  const exercise = finiteOrZero(input.exerciseCalories)
  return {
    target,
    consumed,
    exercise,
    // `+ 0` turns a rounded -0 into 0, so no line ever prints "-0".
    food: target == null ? null : Math.round(eatingBalance(consumed, target)) + 0,
    net: target == null ? null : Math.round(netBalance(consumed, target, exercise)) + 0,
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
      // This number is NOT the block credit: the closer credits planned
      // deficit − net balance, and only at the day's closing (§3). Calling it
      // "the number the block uses" led the model to quote it as the credit.
      const whatItIsNot = recomp
        ? 'o crédito do bloco 7700 só é calculado no fechamento do dia (déficit programado − este número); até lá o valor é provisório e NÃO é o que resta para comer'
        : 'NÃO é o que resta para comer'
      lines.push(
        `- Balanço calórico de hoje COM exercício (consumido − meta − exercício): ${n.net} kcal (negativo=déficit, positivo=superávit) — ${whatItIsNot}`,
      )
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
  // The block wording is only for recomposição: whether exercise enters the
  // day balance in ganho de massa / manutenção is Roberto's open decision.
  lines.push(
    `- REGRA: exercício NÃO libera comida nem apaga excedente. A meta de hoje é a mesma com ou sem treino; ${whatCanBeEaten}. Se ele perguntar se pode comer a mais porque treinou, ${whatToShow}; o gasto do treino fica à parte${recomp ? ' (acelera o bloco 7700)' : ''}.`,
  )
  return lines
}
