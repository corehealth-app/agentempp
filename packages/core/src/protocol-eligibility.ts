/**
 * App signup composition eligibility, approved final.answers n9/n39.
 * BF decides the recomposition cut (>=20/28); without BF, BMI >=25 does.
 * At/above that cut signup assigns recomposition; below it the person chooses.
 * Gain independently requires BMI BELOW the configured cut, BF <=19/27 when
 * present, and >=3 strength sessions. BF below its recomp cut plus BMI above
 * its cut keeps recomp/maintenance as choices and never assigns a phase.
 * Accepted photo provenance cannot override that gain criterion.
 *
 * Limits come from the existing calc config, with its number-only fallback.
 * The caller canonicalizes body values to the profile's decimal storage.
 * The old 1e-9 BMI correction remains only for n9's no-BF assignment predicate;
 * n39 gain entry compares the original decimal weight/height exactly.
 *
 * This module does NOT evaluate n10 birth-date/declared health/HOLD/no-plan.
 * That full signup integration remains required before clinical activation.
 * The legacy WhatsApp resolveProtocol entry is separate and unchanged.
 */
import { DEFAULT_CALC_CONFIG } from './calc-config.js'
import { clinicalBmiBelow } from './clinical-bmi-comparison.js'
import { calcIMC } from './nutrition.js'
import type { Protocol, Sex } from './types.js'

/** Only the three raw configuration rows consumed by this rule. This allows
 * a coherent private snapshot without the legacy loader's process-wide cache.
 * Number-only fallbacks remain in readLimits, unchanged. */
export interface SignupEligibilityConfig {
  bf_limits?: unknown
  imc_limit_recomp?: unknown
  training_min?: unknown
}

/**
 * Slack of the BMI comparison. A rounding fix, NOT a clinical number and not
 * a number the client stated: `calcIMC` divides in binary floating point, so
 * 64 kg at 160 cm gives 24.999999999999996 where the arithmetic gives 25.0,
 * and a plain `>= 25` would let that person choose. A BMI less than this far
 * below the cut is read as being on the cut. Body fat is typed, not computed,
 * so it is compared as it is.
 */
export const SIGNUP_IMC_ROUNDING_TOLERANCE = 1e-9

/** What decided C1–C4: the informed body fat or, without it, the BMI. */
export type SignupEligibilityBasis = 'BF' | 'IMC'

/**
 * 'available'   — may be recorded for this person;
 * 'blocked'     — the client's rule bars it, `reasons` says why;
 * 'not_offered' — the rule offers no choice here and names no blocking reason
 *                 (manutenção of someone placed in recomposição).
 */
export type SignupObjectiveStatus = 'available' | 'blocked' | 'not_offered'

/**
 * Entry criterion of ganho de massa that is not met: 'composition' (C7a, or
 * the person is above the range) and 'training' (C7b). Always in this order.
 */
export type SignupBlockReason = 'composition' | 'training'

export type SignupEligibilityField =
  | 'sex'
  | 'heightCm'
  | 'weightKg'
  | 'bodyFatPercent'
  | 'trainingFrequency'

export interface SignupEligibilityInput {
  sex: Sex | null | undefined
  heightCm: number | null | undefined
  weightKg: number | null | undefined
  /** Optional. `null` or absent = not informed: the BMI decides (C0). */
  bodyFatPercent?: number | null
  /** Strength-training ("musculação") sessions per week. */
  trainingFrequency: number | null | undefined
}

export interface SignupObjectiveEligibility {
  status: SignupObjectiveStatus
  /** Empty unless `status` is 'blocked'. */
  reasons: SignupBlockReason[]
}

/** The cuts that were applied, for the caller that has to cite one. */
export interface SignupEligibilityLimits {
  /** `bf_limits[sex].recomp`: body fat from this up is placed in recomposição. */
  bodyFatRecomp: number
  /** `bf_limits[sex].gain`: body fat up to this meets C7a. */
  bodyFatGain: number
  /** `imc_limit_recomp`: without body fat, BMI from this up is placed in recomposição. */
  imcRecomp: number
  /** `training_min`: strength sessions per week from this up meet C7b. */
  trainingMin: number
}

interface SignupEligibilityDecided {
  basis: SignupEligibilityBasis
  /** As `calcIMC` gives it, not rounded (64 kg / 160 cm: 24.999999999999996). */
  imc: number
  objectives: Record<Protocol, SignupObjectiveEligibility>
  limits: SignupEligibilityLimits
}

/**
 * 'assigned'      — C1, C2 or C3: recomposição, not asked;
 * 'choice'        — C4: the person is asked;
 * 'invalid_input' — the rule cannot be computed; nothing is decided.
 */
export type SignupEligibility =
  | ({ outcome: 'assigned'; assignedProtocol: 'recomposicao' } & SignupEligibilityDecided)
  | ({ outcome: 'choice' } & SignupEligibilityDecided)
  | { outcome: 'invalid_input'; invalidFields: SignupEligibilityField[] }

/** Every field of the input, in the order of `SignupEligibilityInput`. */
const SIGNUP_ELIGIBILITY_FIELDS: readonly SignupEligibilityField[] = [
  'sex',
  'heightCm',
  'weightKg',
  'bodyFatPercent',
  'trainingFrequency',
]

function isSex(value: unknown): value is Sex {
  return value === 'masculino' || value === 'feminino'
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

function isPositiveNumber(value: unknown): value is number {
  return isFiniteNumber(value) && value > 0
}

function isNonNegativeNumber(value: unknown): value is number {
  return isFiniteNumber(value) && value >= 0
}

/**
 * One cut out of the config. At runtime the config rows come from
 * `global_config`, copied as they are by the loader, so each is read as
 * `unknown` (same reading as `imcGoalStepPoints`): a row that does not hold a
 * number (text such as "25", null, a missing sex) is a typing mistake and
 * gives the code default — it must never open the choice, nor throw.
 */
function configLimit(raw: unknown, codeDefault: number): number {
  return isFiniteNumber(raw) ? raw : codeDefault
}

type BodyFatLimitsRow = Partial<Record<Sex, { recomp?: unknown; gain?: unknown } | null>> | null

function readLimits(sex: Sex, config: SignupEligibilityConfig): SignupEligibilityLimits {
  const row = (config.bf_limits as BodyFatLimitsRow | undefined)?.[sex]
  return {
    bodyFatRecomp: configLimit(row?.recomp, DEFAULT_CALC_CONFIG.bf_limits[sex].recomp),
    bodyFatGain: configLimit(row?.gain, DEFAULT_CALC_CONFIG.bf_limits[sex].gain),
    imcRecomp: configLimit(config.imc_limit_recomp, DEFAULT_CALC_CONFIG.imc_limit_recomp),
    trainingMin: configLimit(config.training_min, DEFAULT_CALC_CONFIG.training_min),
  }
}

/** n39's two independent composition criteria, shared with the app's text
 * projection. Inputs are already canonical/stored body values. This neither
 * decides n10 nor changes the above-recomposition-cut assignment (n9). */
export function signupGainCompositionUnmet(
  input: { heightCm: number; weightKg: number; bodyFatPercent: number | null },
  limits: Pick<SignupEligibilityLimits, 'imcRecomp' | 'bodyFatGain'>,
): Array<'bmi' | 'body_fat'> {
  const unmet: Array<'bmi' | 'body_fat'> = []
  if (!(limits.imcRecomp > 0 && clinicalBmiBelow(input.weightKg, input.heightCm, limits.imcRecomp)))
    unmet.push('bmi')
  if (input.bodyFatPercent !== null && input.bodyFatPercent > limits.bodyFatGain)
    unmet.push('body_fat')
  return unmet
}

/** Shared composition predicate after canonical input validation. Provenance
 * policy belongs to the calling flow: confirmed photos retain the existing
 * BF-first route; a manual report may add n9's gain-only BMI veto. Neither
 * caller may turn that veto into an above-recomposition-cut assignment. */
export function compareProtocolComposition(
  input: { sex: Sex; imc: number; bodyFatPercent: number | null },
  config: SignupEligibilityConfig = DEFAULT_CALC_CONFIG,
) {
  if (
    !isSex(input.sex) ||
    !isPositiveNumber(input.imc) ||
    (input.bodyFatPercent !== null &&
      (!isPositiveNumber(input.bodyFatPercent) || input.bodyFatPercent >= 100))
  )
    throw new RangeError('Invalid canonical composition input')
  const limits = readLimits(input.sex, config ?? DEFAULT_CALC_CONFIG)
  const basis: SignupEligibilityBasis = input.bodyFatPercent !== null ? 'BF' : 'IMC'
  const aboveRange =
    input.bodyFatPercent !== null
      ? input.bodyFatPercent >= limits.bodyFatRecomp
      : input.imc >= limits.imcRecomp - SIGNUP_IMC_ROUNDING_TOLERANCE
  return {
    basis,
    limits,
    aboveRange,
    gainCompositionMet:
      !aboveRange && (input.bodyFatPercent === null || input.bodyFatPercent <= limits.bodyFatGain),
  }
}

/**
 * Applies C0–C7 to the data of the sign-up. See the header for the table, its
 * sources and what is still to be confirmed by the client.
 *
 * Invalid input — a sex that is not one of the two, a height or weight that is
 * not a number above zero (the BMI would be undefined), a body fat that is
 * informed but is not a number between 0 and 100 (exclusive), a training
 * frequency that is not a number from zero up — returns `invalid_input` with
 * the fields at fault, in the order of `SignupEligibilityInput`, and decides
 * nothing: neither "recomposição" nor "may choose" is a safe guess for data
 * the rule cannot read, and the client's text has no rule for it. Height and
 * weight are required even when body fat decides. Plausibility (a height typed
 * in metres, 9 sessions a week) is the contract's job, not this function's:
 * whatever can be computed is compared as it is.
 *
 * Outside the declared types, so that the function never throws: an `input`
 * that is not an object (absent, `null`, a number, a text) returns
 * `invalid_input` with the five fields, since none could be read; a `config`
 * passed as `null` is read as absent and gives the code default.
 */
export function decideSignupEligibility(
  input: SignupEligibilityInput,
  config: SignupEligibilityConfig = DEFAULT_CALC_CONFIG,
): SignupEligibility {
  if (typeof input !== 'object' || input === null) {
    return { outcome: 'invalid_input', invalidFields: [...SIGNUP_ELIGIBILITY_FIELDS] }
  }
  // The default parameter covers only `undefined`.
  const cuts: SignupEligibilityConfig = config ?? DEFAULT_CALC_CONFIG

  const { sex, heightCm, weightKg, trainingFrequency } = input
  const bodyFat: unknown = input.bodyFatPercent ?? null
  const bodyFatValid = bodyFat === null || (isPositiveNumber(bodyFat) && bodyFat < 100)

  if (
    !isSex(sex) ||
    !isPositiveNumber(heightCm) ||
    !isPositiveNumber(weightKg) ||
    !bodyFatValid ||
    !isNonNegativeNumber(trainingFrequency)
  ) {
    const invalidFields: SignupEligibilityField[] = []
    if (!isSex(sex)) invalidFields.push('sex')
    if (!isPositiveNumber(heightCm)) invalidFields.push('heightCm')
    if (!isPositiveNumber(weightKg)) invalidFields.push('weightKg')
    if (!bodyFatValid) invalidFields.push('bodyFatPercent')
    if (!isNonNegativeNumber(trainingFrequency)) invalidFields.push('trainingFrequency')
    return { outcome: 'invalid_input', invalidFields }
  }

  const imc = calcIMC(weightKg, heightCm)
  // Two valid numbers can still overflow the division (a height near zero).
  if (!isPositiveNumber(imc)) {
    return { outcome: 'invalid_input', invalidFields: ['heightCm', 'weightKg'] }
  }

  const informedBodyFat = isFiniteNumber(bodyFat) ? bodyFat : null
  const { limits, basis, aboveRange, gainCompositionMet } = compareProtocolComposition(
    { sex, imc, bodyFatPercent: informedBodyFat },
    cuts,
  )

  // C7: every entry criterion of ganho de massa that is not met.
  const reasons: SignupBlockReason[] = []
  if (
    !gainCompositionMet ||
    signupGainCompositionUnmet({ heightCm, weightKg, bodyFatPercent: informedBodyFat }, limits)
      .length > 0
  )
    reasons.push('composition')
  if (trainingFrequency < limits.trainingMin) reasons.push('training')
  const ganhoMassa: SignupObjectiveEligibility =
    reasons.length === 0 ? { status: 'available', reasons: [] } : { status: 'blocked', reasons }

  if (aboveRange) {
    return {
      outcome: 'assigned',
      assignedProtocol: 'recomposicao',
      basis,
      imc,
      objectives: {
        recomposicao: { status: 'available', reasons: [] },
        ganho_massa: ganhoMassa,
        manutencao: { status: 'not_offered', reasons: [] },
      },
      limits,
    }
  }

  // C4–C6: within the range → the person chooses.
  return {
    outcome: 'choice',
    basis,
    imc,
    objectives: {
      recomposicao: { status: 'available', reasons: [] },
      ganho_massa: ganhoMassa,
      manutencao: { status: 'available', reasons: [] },
    },
    limits,
  }
}
