import { z } from 'zod'
import { type CalcConfig, DEFAULT_CALC_CONFIG } from './calc-config.js'
import { clinicalBmiBelow } from './clinical-bmi-comparison.js'
import { calcIMC } from './nutrition.js'
import {
  compareProtocolComposition,
  SIGNUP_IMC_ROUNDING_TOLERANCE,
} from './protocol-eligibility.js'
import {
  clinicalCivilDateSchema,
  clinicalDateOrdinal,
  evaluateReevaluationSafety,
  type ReevaluationSafetyInput,
} from './reevaluation-clinical-safety.js'
import { plannedReevaluationFormDraftSchema } from './reevaluation-form-contracts.js'
import {
  evaluateReevaluationWeightHistory,
  reevaluationWeightHistorySchema,
} from './reevaluation-weight-trend.js'

const bodyFat = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('absent') }).strict(),
  z
    .object({ kind: z.literal('manual_report'), hundredths: z.number().int().min(300).max(6000) })
    .strict(),
  z
    .object({ kind: z.literal('confirmed_photo'), hundredths: z.number().int().min(300).max(6000) })
    .strict(),
])
const compositionSchema = z
  .object({
    sex: z.enum(['masculino', 'feminino']).nullable(),
    heightCm: z.number().finite().min(100).max(250),
    weightKg: z.number().finite().min(30).max(300),
    bodyFat,
    sessions: z.number().int().min(0).max(7).nullable(),
  })
  .strict()

/** Pure n9 wrapper, not photo provenance authority. The server must prove a
 * confirmed-photo label against its active accepted snapshot. Numeric equality
 * with a photo result does not make a manually edited report a confirmed photo. */
export function decideReevaluationComposition(
  input: unknown,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
) {
  const value = compositionSchema.parse(input)
  if (value.sex === null)
    return {
      aboveCut: null,
      manualDisagreement: false,
      gainAvailable: false,
      gainReasons: ['sex_unknown'],
    }
  const imc = calcIMC(value.weightKg, value.heightCm)
  const common = compareProtocolComposition(
    {
      sex: value.sex,
      imc,
      bodyFatPercent: value.bodyFat.kind === 'absent' ? null : value.bodyFat.hundredths / 100,
    },
    config,
  )
  const manualDisagreement =
    value.bodyFat.kind === 'manual_report' &&
    !common.aboveRange &&
    imc >= common.limits.imcRecomp - SIGNUP_IMC_ROUNDING_TOLERANCE
  const gainReasons: string[] = []
  // Approved n39 keeps the measured-photo exception OFF: even reliable photo
  // provenance does not release gain at BMI >= the entry cut. The legacy
  // sign-up comparison remains unchanged; this is the clinical review gate.
  if (
    !common.gainCompositionMet ||
    !clinicalBmiBelow(value.weightKg, value.heightCm, common.limits.imcRecomp)
  )
    gainReasons.push('composition')
  if (value.sessions === null) gainReasons.push('sessions_unknown')
  else if (value.sessions < common.limits.trainingMin) gainReasons.push('training')
  return {
    aboveCut: common.aboveRange,
    manualDisagreement,
    gainAvailable: gainReasons.length === 0,
    gainReasons,
  }
}

const reviewSchema = z
  .object({
    id: z.string().uuid(),
    kind: z.enum(['REGULAR', 'EARLY_FULL', 'SAFETY']),
    date: clinicalCivilDateSchema,
    adherence: z.enum(['bem_consistente', 'mais_ou_menos', 'pouco_consistente']).nullable(),
    energy: z.enum(['boa', 'ok', 'baixa']).nullable(),
  })
  .strict()
const choicesSchema = z
  .object({
    form: plannedReevaluationFormDraftSchema,
    safety: z.unknown(),
    composition: compositionSchema,
    history: reevaluationWeightHistorySchema,
    maintenanceSince: clinicalCivilDateSchema.nullable(),
    transitionActiveOrPaused: z.boolean(),
    priorFulls: z.array(reviewSchema),
  })
  .strict()
type ChoiceStatus = 'offered' | 'not_offered' | 'blocked' | 'missing'
interface MaintenanceChoices {
  status: ChoiceStatus
  reasons: string[]
  gain: { available: boolean; reasons: string[] }
  recomposition: { available: boolean; deficitLevel: 400 | 500 | 600 | null; reasons: string[] }
}
function refused(status: ChoiceStatus, reason: string): MaintenanceChoices {
  return {
    status,
    reasons: [reason],
    gain: { available: false, reasons: [reason] },
    recomposition: { available: false, deficitLevel: null, reasons: [reason] },
  }
}

function boundContext(
  form: z.infer<typeof plannedReevaluationFormDraftSchema>,
  input: unknown,
  composition: z.infer<typeof compositionSchema>,
) {
  const safety = evaluateReevaluationSafety(input)
  const facts = input as ReevaluationSafetyInput
  if (
    facts.weightKg !== composition.weightKg ||
    facts.heightCm !== composition.heightCm ||
    (form.answers.weightKg !== null && form.answers.weightKg !== facts.weightKg) ||
    form.answers.strengthSessions !== composition.sessions ||
    facts.bodyFatPercent !==
      (composition.bodyFat.kind === 'absent' ? null : composition.bodyFat.hundredths / 100)
  )
    throw new Error('Composition and form must be bound to the same clinical context')
  return { safety, facts }
}

/** n6/n19 proposal eligibility, never a phase switch. The current REGULAR is
 * a candidate until the FULL transaction commits; the prior endpoints must
 * come from durable concluded FULL receipts, not the legacy calendar table. */
export function evaluateMaintenanceChoices(
  input: unknown,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): MaintenanceChoices {
  const value = choicesSchema.parse(input)
  const { form, composition } = value
  const { safety, facts } = boundContext(form, value.safety, composition)
  if (facts.date !== value.history.date)
    throw new Error('History must be bound to the clinical date')
  if (!safety.automaticTargetChangeAllowed || form.answers.healthCheck?.kind === 'risks')
    return refused('blocked', 'safety')
  if (form.phase !== 'manutencao' || form.kind !== 'REGULAR')
    return refused('not_offered', 'review_kind_or_phase')
  if (value.transitionActiveOrPaused) return refused('blocked', 'transition')
  if (form.answers.healthCheck?.kind !== 'none') return refused('missing', 'healthCheck')
  if (form.answers.weightKg === null) return refused('missing', 'weightKg')
  const composed = decideReevaluationComposition(composition, config)
  if (composed.aboveCut === null) return refused('missing', 'sex')
  if (composed.aboveCut) return refused('not_offered', 'composition_cut_use_n38_B')
  if (value.maintenanceSince === null) return refused('missing', 'maintenanceSince')
  const date = facts.date
  const r = clinicalDateOrdinal(value.maintenanceSince)
  if (clinicalDateOrdinal(date) - r < 28) return refused('not_offered', 'before_R_plus_28')
  const unique = new Map<string, z.infer<typeof reviewSchema>>()
  for (const review of value.priorFulls) {
    if (review.date >= date) throw new Error('Prior FULL receipt is not before this candidate')
    const previous = unique.get(review.id.toLowerCase())
    if (previous && JSON.stringify(previous) !== JSON.stringify(review))
      throw new Error('Conflicting FULL evidence')
    unique.set(review.id.toLowerCase(), review)
  }
  const previousRegulars = [...unique.values()]
    .filter((review) => review.kind === 'REGULAR')
    .sort((a, b) => b.date.localeCompare(a.date))
  const previous = previousRegulars[0]
  if (!previous) return refused('missing', 'previousRegular')
  if (previousRegulars[1]?.date === previous.date)
    throw new Error('Two regular endpoints on the same civil date')
  if (clinicalDateOrdinal(previous.date) - 13 < r || clinicalDateOrdinal(date) - 13 < r)
    return refused('not_offered', 'regular_window_before_R')
  for (const endpoint of [previous, form.answers]) {
    if (endpoint.adherence === null) return refused('missing', 'regular_adherence_unknown')
    if (endpoint.adherence !== 'bem_consistente') return refused('blocked', 'regular_adherence')
    if (endpoint.energy === null) return refused('missing', 'regular_energy_unknown')
    if (endpoint.energy === 'baixa') return refused('blocked', 'regular_energy')
  }
  const trend = evaluateReevaluationWeightHistory(value.history).fourWeeks
  if (trend.status !== 'known') return refused('missing', 'weightHistory')
  if (!trend.stable) return refused('not_offered', 'weight_not_stable')
  const hunger = form.answers.hunger
  return {
    status: 'offered',
    reasons: [],
    gain: { available: composed.gainAvailable, reasons: composed.gainReasons },
    recomposition: {
      available: hunger !== null,
      deficitLevel:
        hunger === null ? null : hunger === 'muita' ? 400 : hunger === 'moderada' ? 500 : 600,
      reasons: hunger === null ? ['hunger_unknown'] : [],
    },
  }
}

const reviewOptionsSchema = z
  .object({
    form: plannedReevaluationFormDraftSchema,
    safety: z.unknown(),
    composition: compositionSchema,
    maintenanceSince: clinicalCivilDateSchema.nullable(),
    transitionActiveOrPaused: z.boolean(),
    measureConfirmed: z.boolean(),
  })
  .strict()
type ReviewPhaseProposal =
  | { kind: 'maintenance_transition'; requiresActivityConfirmation: boolean }
  | {
      kind: 'recomposition_suggestion'
      deficitLevel: 400 | 500 | 600
      requiresSecondConfirmation: true
    }
/** n38 controls what may be offered. No crossing of a threshold changes a phase,
 * and B1 never consumes n19's separate 28-day choice/stability gate. */
export function evaluateRecompositionReviewOptions(
  input: unknown,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): {
  status: ChoiceStatus
  reason: string
  proposal: ReviewPhaseProposal | null
} {
  const value = reviewOptionsSchema.parse(input)
  const { form, composition } = value
  const { safety, facts } = boundContext(form, value.safety, composition)
  const no = (status: ChoiceStatus, reason: string) => ({ status, reason, proposal: null })
  if (!safety.automaticTargetChangeAllowed || form.answers.healthCheck?.kind === 'risks')
    return no('blocked', 'safety')
  if (!['REGULAR', 'EARLY_FULL', 'TRANSITION_FULL'].includes(form.kind))
    return no('not_offered', 'full_review_required')
  if (form.phase === 'ganho_massa') return no('not_offered', 'direct_phase_path_forbidden')
  if (value.transitionActiveOrPaused) return no('blocked', 'transition')
  if (form.answers.healthCheck?.kind !== 'none') return no('missing', 'healthCheck')
  if (form.answers.weightKg === null) return no('missing', 'weightKg')
  const compared = decideReevaluationComposition(composition, config)
  if (compared.aboveCut === null) return no('missing', 'sex')
  if (form.phase === 'recomposicao') {
    if (compared.aboveCut) return no('not_offered', 'at_or_above_composition_cut')
    return {
      status: 'offered',
      reason: 'below_composition_cut',
      proposal: {
        kind: 'maintenance_transition',
        requiresActivityConfirmation: form.answers.activity?.activityLevelConfirmed !== true,
      },
    }
  }
  if (form.kind !== 'REGULAR') return no('not_offered', 'regular_required')
  if (!compared.aboveCut)
    return no(
      'not_offered',
      compared.manualDisagreement ? 'manual_disagreement' : 'below_composition_cut',
    )
  if (value.maintenanceSince === null) return no('missing', 'maintenanceSince')
  if (clinicalDateOrdinal(facts.date) - clinicalDateOrdinal(value.maintenanceSince) < 14)
    return no('not_offered', 'before_R_plus_14')
  if (!value.measureConfirmed) return no('missing', 'measure_confirmation_required')
  const hunger = form.answers.hunger
  if (hunger === null) return no('missing', 'hunger_unknown')
  return {
    status: 'offered',
    reason: 'n38_B1',
    proposal: {
      kind: 'recomposition_suggestion',
      deficitLevel: hunger === 'muita' ? 400 : hunger === 'moderada' ? 500 : 600,
      requiresSecondConfirmation: true,
    },
  }
}
