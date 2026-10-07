/**
 * Sign-up eligibility check of the app (POST /onboarding/eligibility): which
 * objectives may be recorded for the body values the person typed, and the
 * text to show for each (docs/CALCULO-MPP.md §10l, docs/mobile/api-v1.md
 * "Conferência de objetivo no cadastro").
 *
 * The rule is `decideSignupEligibility` (@mpp/core) and nothing here decides
 * anything clinical: this file rounds the values to what the profile stores,
 * calls the rule and picks the texts. No I/O: the caller loads the calc config
 * and nothing is written anywhere.
 */
import {
  type CalcConfig,
  decideSignupEligibility,
  gainBlockedAboveRangeMessage,
  gainUnavailableBodyFatReason,
  gainUnavailableTrainingReason,
  type Protocol,
  type ProtocolMessageLocale,
  type SignupBlockReason,
  type SignupEligibility,
  type SignupEligibilityField,
  type SignupObjectiveStatus,
  signupAssignedNotice,
} from '@mpp/core'
import type { OnboardingEligibilityInput } from './contracts'
import { MobileApiError } from './http'

/**
 * Decimal places `user_profiles` keeps: `height_cm` and `weight_kg` are
 * numeric(5,2), `body_fat_percent` is numeric(4,2).
 */
const STORED_DECIMAL_PLACES = 2

/**
 * A body value as the profile will store it. The completion hands the number
 * to the database as its decimal text and Postgres rounds a `numeric` half
 * away from zero ON THAT TEXT, so the rounding here is done on the same text,
 * never in binary floating point: 19.025 is stored as 19.03, where both
 * `Math.round(19.025 * 100) / 100` and `(19.025).toFixed(2)` give 19.02; and
 * 27.005 is stored as 27.01 — above a cut of 27 — where `toFixed` gives 27.00.
 */
export function asStoredBodyValue(value: number): number {
  const decimal = /^(\d+)(?:\.(\d+))?$/.exec(String(value))
  // Exponent notation or a sign: not a value the contract's ranges let in.
  if (!decimal) return Number(value.toFixed(STORED_DECIMAL_PLACES))

  const [, whole = '0', fraction = ''] = decimal
  if (fraction.length <= STORED_DECIMAL_PLACES) return value

  const kept = Number(`${whole}${fraction.slice(0, STORED_DECIMAL_PLACES)}`)
  const roundsUp = Number(fraction.charAt(STORED_DECIMAL_PLACES)) >= 5
  return (kept + (roundsUp ? 1 : 0)) / 10 ** STORED_DECIMAL_PLACES
}

export type OnboardingEligibilityReason = 'gain_composition' | 'gain_training'

const PUBLIC_REASON: Record<SignupBlockReason, OnboardingEligibilityReason> = {
  composition: 'gain_composition',
  training: 'gain_training',
}

const REQUEST_FIELD: Record<SignupEligibilityField, string> = {
  sex: 'sex',
  heightCm: 'height_cm',
  weightKg: 'weight_kg',
  bodyFatPercent: 'body_fat_percent',
  trainingFrequency: 'training_frequency',
}

/** The order the options are always returned in. */
const OBJECTIVES: readonly Protocol[] = ['recomposicao', 'ganho_massa', 'manutencao']

export interface OnboardingEligibilityOption {
  objective: Protocol
  status: SignupObjectiveStatus
  reasons: OnboardingEligibilityReason[]
  /** Paragraphs to show under the option; empty when there is nothing to say. */
  message: string[]
}

export interface OnboardingEligibilityResult {
  decision: 'assigned' | 'choice'
  basis: 'body_fat' | 'bmi'
  /** The objective the person is placed in; null when the person chooses. */
  objective: 'recomposicao' | null
  /** Paragraphs for a person placed without being asked; null otherwise. */
  notice: string[] | null
  options: OnboardingEligibilityOption[]
}

type Decided = Exclude<SignupEligibility, { outcome: 'invalid_input' }>

/**
 * The text of an objective that cannot be recorded.
 *
 * A person PLACED in recomposição gets the client's blocking phrase (3.4.1)
 * and only it, whatever the reasons: it was written for the person led to
 * recomposição, and a strength training below the minimum is one more fact,
 * not a second notice. A person who CHOOSES gets one short reason per
 * criterion that is not met, each citing the cut the rule applied.
 */
function blockedMessage(
  decided: Decided,
  reasons: readonly SignupBlockReason[],
  informedSessions: number,
  locale: ProtocolMessageLocale,
): string[] {
  if (decided.outcome === 'assigned') return gainBlockedAboveRangeMessage(decided.basis, locale)
  return reasons.flatMap((reason) =>
    reason === 'composition'
      ? gainUnavailableBodyFatReason(decided.limits.bodyFatGain, locale)
      : gainUnavailableTrainingReason(decided.limits.trainingMin, informedSessions, locale),
  )
}

export function resolveOnboardingEligibility(
  input: OnboardingEligibilityInput,
  config: CalcConfig,
): OnboardingEligibilityResult {
  // Decided on what the profile will hold, so that the answer given here and
  // the stored profile can never disagree (a man with 19.995% is stored, and
  // decided, as 20.00%).
  const decided = decideSignupEligibility(
    {
      sex: input.sex,
      heightCm: asStoredBodyValue(input.height_cm),
      weightKg: asStoredBodyValue(input.weight_kg),
      bodyFatPercent:
        input.body_fat_percent === undefined ? null : asStoredBodyValue(input.body_fat_percent),
      trainingFrequency: input.training_frequency,
    },
    config,
  )

  // The request contract lets in nothing the rule cannot read; if that ever
  // changes, the request is refused rather than answered with a guess.
  if (decided.outcome === 'invalid_input') {
    throw new MobileApiError(422, 'validation_failed', 'Request validation failed', {
      fields: decided.invalidFields.map((field) => ({
        path: REQUEST_FIELD[field],
        code: 'custom',
        message: 'The objective cannot be decided on this value',
      })),
    })
  }

  const assigned = decided.outcome === 'assigned'
  return {
    decision: decided.outcome,
    basis: decided.basis === 'BF' ? 'body_fat' : 'bmi',
    objective: assigned ? decided.assignedProtocol : null,
    notice: assigned ? signupAssignedNotice(input.locale) : null,
    options: OBJECTIVES.map((objective) => {
      const { status, reasons } = decided.objectives[objective]
      return {
        objective,
        status,
        reasons: reasons.map((reason) => PUBLIC_REASON[reason]),
        message:
          status === 'blocked'
            ? blockedMessage(decided, reasons, input.training_frequency, input.locale)
            : [],
      }
    }),
  }
}
