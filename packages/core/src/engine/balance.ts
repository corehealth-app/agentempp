/**
 * Dois balanços distintos (ver docs/CALCULO-MPP.md §2):
 *  - COMIDA: consumido − meta (linha 🎯 Restam/Excedente do card; SEM exercício)
 *  - NET:    consumido − meta − exercício (déficit do dia; alimenta o bloco)
 *
 * Regra MPP (Roberto 2026-05-21): exercício NÃO entra no "Restam" (não libera
 * comer mais); ele acelera o bloco via netBalance.
 */
export function eatingBalance(caloriesConsumed: number, caloriesTarget: number): number {
  return caloriesConsumed - caloriesTarget
}

export function netBalance(
  caloriesConsumed: number,
  caloriesTarget: number,
  exerciseCalories: number,
): number {
  return caloriesConsumed - caloriesTarget - exerciseCalories
}

/**
 * Déficit REAL do dia = quanto ficou abaixo da MANUTENÇÃO (não da meta). É o que
 * realmente emagrece e o que o bloco 7700 credita. = déficit programado − netBalance.
 * Positivo = déficit (abaixo da manutenção); negativo = superávit real.
 *
 * A meta já é (manutenção − déficit programado); por isso o "saldo vs meta"
 * (netBalance) SOZINHO subestima o déficit real pelos N kcal embutidos na meta.
 * Decisão Roberto 2026-05-22: comunicar SEMPRE este número, não o saldo vs meta.
 * Ex: programado 500, netBalance −397 → déficit real 897 (NÃO 397).
 */
export function realDailyDeficit(designDeficit: number, net: number): number {
  return designDeficit - net
}

/**
 * Per-protocol switch of the "balanço do dia" (docs/CALCULO-MPP.md §2c).
 * `true` = the day's balance is measured against the day's EXPENDITURE, as the
 * client wrote it; `false` = the legacy number (netBalance against the target).
 *
 * Dito pelo cliente em 20/01/2026, 22/02/2026, 23/02/2026 e 09/03/2026;
 * implementado em 2026-10-04 a pedido do Eduardo; confirmação do cliente
 * pendente. To revert, set a protocol (or all three) to `false`.
 *
 * Read ONLY by `dayEnergyBalance` (app Today screen and Flow chat). The daily
 * closer, the block credit, the WhatsApp context and the generated column
 * `daily_snapshots.daily_balance` do not read it.
 */
export const DAY_BALANCE_AGAINST_EXPENDITURE: Readonly<
  Record<'recomposicao' | 'ganho_massa' | 'manutencao', boolean>
> = {
  recomposicao: true,
  ganho_massa: true,
  manutencao: true,
}

export interface DayEnergyBalanceInput {
  /** Any other value (null, unknown text) keeps the legacy number. */
  protocol: string | null | undefined
  caloriesConsumed: number
  /** The target of the day (the day row's, else the profile's). */
  caloriesTarget: number
  exerciseCalories: number
  /** `ganho_massa_surplus_multiplier` of the calc config. Ganho de massa only. */
  gainSurplusMultiplier?: number | null
  /**
   * Deficit built into the recomposição target, with the closer's expression:
   * recomposição ? (deficit_level ?? 500) : 0. Recomposição only.
   */
  programmedDeficitKcal?: number | null
  /**
   * `false` when the day's STORED target was written under another protocol's
   * rule (the protocol changed after the first registration of the day; see
   * `resolveDayBalanceInputs` in engine/day-balance-inputs.ts). The
   * expenditure cannot be derived from that target with this protocol's rule,
   * so the day keeps the legacy number. Absent = `true`.
   */
  targetMatchesProtocol?: boolean
}

export interface DayEnergyBalance {
  /** consumed − the day's expenditure. Negative = deficit, positive = surplus. */
  balance: number
  /** The expenditure the balance is measured against, WITHOUT exercise. */
  referenceKcal: number
  /** True when the day's exercise is subtracted on top of `referenceKcal`. */
  includesExercise: boolean
  /** 'expenditure' = the client's rule; 'target' = the legacy number. */
  basis: 'expenditure' | 'target'
}

// `+ 0` turns a rounded -0 into 0: the app decodes Int and no text prints "-0".
const roundKcal = (value: number): number => Math.round(value) + 0

/**
 * The day's balance as the client wrote it: "consumido − gasto do dia".
 *   recomposição: gasto = BMR × 1,2 + exercício do dia
 *   ganho de massa / manutenção: gasto = BMR × fator de atividade (the
 *     exercise is already inside the factor and is NOT added)
 *
 * The expenditure is derived from the TARGET OF THE DAY, never recomputed
 * from the profile: recomposição target = BMR × 1,2 − programmed deficit;
 * ganho target = BMR × fator × multiplier; manutenção target = BMR × fator
 * (engine/targets.ts). So the number stays tied to the target printed next to
 * it, works on a closed day (which stores only the target) and does not move
 * when the weight changes mid-day. Cost: up to 1 kcal away from
 * round(BMR × fator) in ganho de massa.
 *
 * In recomposição the result is netBalance − programmed deficit, i.e. minus
 * the "déficit real do dia" the closer credits to the 7700 block on a day
 * that credits normally (19/05: −832; 21/05: −897).
 *
 * This is NOT the food line: "Restam/Excedente" stays eatingBalance, against
 * the target and without exercise, in every protocol.
 */
export function dayEnergyBalance(input: DayEnergyBalanceInput): DayEnergyBalance {
  const { caloriesConsumed, caloriesTarget, exerciseCalories } = input
  // A target stored under another protocol's rule says nothing about this
  // protocol's expenditure: deriving from it gave a balance with the wrong
  // sign on the day the protocol changed (review of 2026-10-04). Legacy then.
  const protocol = input.targetMatchesProtocol === false ? null : input.protocol
  if (protocol === 'recomposicao' && DAY_BALANCE_AGAINST_EXPENDITURE.recomposicao) {
    const deficit = input.programmedDeficitKcal
    const programmed = deficit != null && Number.isFinite(deficit) && deficit > 0 ? deficit : 0
    const referenceKcal = roundKcal(caloriesTarget + programmed)
    return {
      balance: roundKcal(caloriesConsumed - referenceKcal - exerciseCalories),
      referenceKcal,
      includesExercise: true,
      basis: 'expenditure',
    }
  }
  if (protocol === 'ganho_massa' && DAY_BALANCE_AGAINST_EXPENDITURE.ganho_massa) {
    const m = input.gainSurplusMultiplier
    // An unusable multiplier never invents a reference: the target stands in.
    const referenceKcal =
      m != null && Number.isFinite(m) && m > 0
        ? roundKcal(caloriesTarget / m)
        : roundKcal(caloriesTarget)
    return {
      balance: roundKcal(caloriesConsumed - referenceKcal),
      referenceKcal,
      includesExercise: false,
      basis: 'expenditure',
    }
  }
  if (protocol === 'manutencao' && DAY_BALANCE_AGAINST_EXPENDITURE.manutencao) {
    const referenceKcal = roundKcal(caloriesTarget)
    return {
      balance: roundKcal(caloriesConsumed - referenceKcal),
      referenceKcal,
      includesExercise: false,
      basis: 'expenditure',
    }
  }
  // Protocol not set / unknown, the switch off, or a day whose stored target
  // belongs to another protocol's rule: the number of before, exactly.
  return {
    balance: netBalance(caloriesConsumed, caloriesTarget, exerciseCalories),
    referenceKcal: caloriesTarget,
    includesExercise: true,
    basis: 'target',
  }
}
