/**
 * The inputs of the per-protocol "balanço do dia" (docs/CALCULO-MPP.md §2c),
 * resolved in ONE place for the app's Today screen (daily-state-service) and
 * for the Flow chat (pipeline), so both hand `dayEnergyBalance` the same
 * protocol, the same programmed deficit, the same multiplier and the same
 * verdict about the day's stored target.
 *
 * Review of 2026-10-04 (balance lens), two defects of the first version:
 *
 *  1. Day of a protocol change. The registration RPCs keep the FIRST target of
 *     the day (COALESCE), so after a change of protocol the day row still
 *     carries the target of the OLD protocol, and the expenditure was derived
 *     from it with the NEW protocol's rule. Reproduced: homem 81 kg, 180 cm,
 *     44 anos, moderado; morning in ganho de massa stores 2799; at noon the
 *     profile becomes recomposição/500; consumed 2500 → "-799 against 3299",
 *     a deficit, when the client's rule gives 2500 − 2064 = +436, a surplus.
 *     Now such a day keeps the legacy number (against the stored target, with
 *     exercise) on the screen AND in the Flow.
 *
 *  2. Closed day whose row carries a protocol different from the profile's.
 *     The app used the row's protocol with the PROFILE protocol's programmed
 *     deficit and the Flow used only the profile's protocol: two numbers for
 *     one day. Now both use the effective protocol (the row's, else the
 *     profile's) and the programmed deficit of that protocol.
 *
 * Revert: `DAY_BALANCE_DAY_ROW_GUARD.enabled = false` brings back, for both
 * surfaces, exactly what they did before this file (profile protocol in the
 * Flow, profile protocol's deficit in the app, no check of the stored target).
 */
import { type CalcConfig, DEFAULT_CALC_CONFIG } from '../calc-config.js'
import { computeDailyTargets, type ProfileRow } from './targets.js'

export const DAY_BALANCE_DAY_ROW_GUARD: Readonly<{ enabled: boolean }> = { enabled: true }

type KnownProtocol = NonNullable<ProfileRow['current_protocol']>
const KNOWN_PROTOCOLS: readonly KnownProtocol[] = ['recomposicao', 'ganho_massa', 'manutencao']

/** The calorie target the profile gives NOW under each protocol's rule. */
export type DailyTargetByProtocol = Record<KnownProtocol, number | null>

/**
 * `computeDailyTargets` for the same profile and config under each of the
 * three rules (recomposição with the profile's current deficit_level). A
 * profile with no protocol yet is given the manutenção rule by
 * `computeDailyTargets`, so "manutencao" also stands for "not set".
 */
export function dailyTargetByProtocol(
  profile: ProfileRow | null,
  config: CalcConfig,
): DailyTargetByProtocol {
  const under = (protocol: KnownProtocol): number | null =>
    profile
      ? computeDailyTargets({ ...profile, current_protocol: protocol }, config).calories_target
      : null
  return {
    recomposicao: under('recomposicao'),
    ganho_massa: under('ganho_massa'),
    manutencao: under('manutencao'),
  }
}

export interface DayBalanceRuleInputs {
  /** The protocol the day's balance follows: the day row's, else the profile's. */
  protocol: string | null
  /** The daily closer's expression, for that protocol: recomposição ? (deficit_level ?? 500) : 0. */
  programmedDeficitKcal: number
  /** `ganho_massa_surplus_multiplier`, coerced to a number. */
  gainSurplusMultiplier: number
  /** False = the stored target belongs to another protocol's rule → legacy number. */
  targetMatchesProtocol: boolean
}

export interface ResolveDayBalanceInput {
  /** `user_profiles.current_protocol`. */
  profileProtocol: string | null | undefined
  /** `user_profiles.deficit_level`. */
  deficitLevel: number | null | undefined
  /**
   * `ganho_massa_surplus_multiplier` as the calc config holds it. `unknown`
   * on purpose: the loader copies the JSON value of `global_config` untouched,
   * so a row saved as the text "1.05" arrives here as a string.
   */
  gainSurplusMultiplier?: unknown
  /** `daily_snapshots.current_protocol` of the day (written at closing). */
  dayRowProtocol?: string | null
  /** `daily_snapshots.calories_target` of the day; absent/null = no stored target. */
  storedTargetKcal?: number | null
  /** `dailyTargetByProtocol(profile, config)`; absent = the stored target is not checked. */
  targetByProtocol?: DailyTargetByProtocol | null
}

const finiteOrNull = (value: number | null | undefined): number | null =>
  value != null && Number.isFinite(value) ? value : null

/**
 * Was the day's stored target written under the rule of `protocol`?
 *
 * Compared: the stored target of the day row against the three targets the
 * profile gives NOW (`dailyTargetByProtocol`: integers, `Math.round`, same
 * profile, same config). The stored target matches the protocol when it is at
 * least as close to that protocol's target as to each of the other two.
 *
 * Nearest rule, not equality, and no fixed tolerance: a weight registered
 * after the first meal moves the target by a few kcal (QA account, staging,
 * 2026-10-04: stored 2980 at 80 kg, profile at 80,5 kg gives 2988) and must
 * NOT throw the day back to the legacy number, while a change of protocol
 * moves it by hundreds (2799 → 1564). A tie keeps the protocol.
 *
 * No answer is possible, and the protocol stands, when there is no stored
 * target (the target then IS the profile's), when the protocol is not one of
 * the three, or when the profile cannot be computed.
 */
function storedTargetMatches(
  protocol: string | null,
  storedTargetKcal: number | null | undefined,
  targetByProtocol: DailyTargetByProtocol | null | undefined,
): boolean {
  const stored = finiteOrNull(storedTargetKcal)
  if (stored == null || stored <= 0 || !targetByProtocol) return true
  const own = KNOWN_PROTOCOLS.find((known) => known === protocol)
  if (!own) return true
  const ownTarget = finiteOrNull(targetByProtocol[own])
  if (ownTarget == null) return true
  const ownDistance = Math.abs(stored - ownTarget)
  return KNOWN_PROTOCOLS.every((other) => {
    if (other === own) return true
    const otherTarget = finiteOrNull(targetByProtocol[other])
    return otherTarget == null || Math.abs(stored - otherTarget) >= ownDistance
  })
}

export function resolveDayBalanceInputs(input: ResolveDayBalanceInput): DayBalanceRuleInputs {
  const profileProtocol = input.profileProtocol ?? null
  const guard = DAY_BALANCE_DAY_ROW_GUARD.enabled
  const protocol = guard ? (input.dayRowProtocol ?? profileProtocol) : profileProtocol
  return {
    protocol,
    programmedDeficitKcal: protocol === 'recomposicao' ? (input.deficitLevel ?? 500) : 0,
    // `Number()` is the coercion `tdee * multiplier` already applies when the
    // TARGET is computed (engine/targets.ts). Without it a multiplier stored
    // as the text "1.05" gave the target 2799 and the reference 2799 too.
    gainSurplusMultiplier: Number(
      input.gainSurplusMultiplier ?? DEFAULT_CALC_CONFIG.ganho_massa_surplus_multiplier,
    ),
    targetMatchesProtocol:
      !guard || storedTargetMatches(protocol, input.storedTargetKcal, input.targetByProtocol),
  }
}
