import { z } from 'zod'
import {
  clinicalCivilDateSchema,
  clinicalDateOrdinal,
  evaluateReevaluationSafety,
} from './reevaluation-clinical-safety.js'
import {
  getKnownReevaluationAnswers,
  type ReevaluationAnswerKey,
  type ReevaluationFormDraft,
  reevaluationFormDraftSchema,
} from './reevaluation-form-contracts.js'
import {
  evaluateReevaluationWeightHistory,
  reevaluationWeightHistorySchema,
} from './reevaluation-weight-trend.js'

function boundSafety(form: ReevaluationFormDraft, input: unknown) {
  const safety = evaluateReevaluationSafety(input)
  const raw = input as { weightKg: unknown }
  if (form.answers.weightKg !== null && form.answers.weightKg !== raw.weightKg)
    throw new Error('Candidate weight is not bound to the safety context')
  return {
    safety,
    blocked: !safety.automaticTargetChangeAllowed || form.answers.healthCheck?.kind === 'risks',
  }
}
function missingAnswers(
  form: ReevaluationFormDraft,
  keys: readonly ReevaluationAnswerKey[],
): string[] {
  const result = getKnownReevaluationAnswers(form, keys)
  return result.status === 'missing' ? result.missing.map((item) => item.key) : []
}
const deficitSchema = z
  .object({
    form: reevaluationFormDraftSchema,
    safety: z.unknown(),
    count: z.number().int().safe().min(0),
    deficitLevel: z.union([z.literal(400), z.literal(500), z.literal(600)]),
    higherPriorityDecisionConfirmed: z.boolean(),
  })
  .strict()
interface DeficitDifficulty {
  status: 'evaluated' | 'not_evaluated'
  nextCount: number
  guidance: boolean
  reason: string
  missing: string[]
  proposal: null | {
    deficitBefore: 500 | 600
    deficitAfter: 400 | 500
    deltaKcal: 100
    countAfterConfirmation: 0
  }
}
/** n2. Returning nextCount/proposal does not persist either or clear a HOLD. */
export function evaluateDeficitDifficulty(input: unknown): DeficitDifficulty {
  const value = deficitSchema.parse(input)
  const { form } = value
  const result: DeficitDifficulty = {
    status: 'not_evaluated',
    nextCount: value.count,
    guidance: false,
    reason: 'review_kind_or_phase',
    missing: [],
    proposal: null,
  }
  const { blocked } = boundSafety(form, value.safety)
  if (form.kind !== 'REGULAR' || form.phase !== 'recomposicao') return result
  result.status = 'evaluated'
  const difficult = form.answers.hunger === 'muita' || form.answers.energy === 'baixa'
  // A difficulty fact still updates its counter; it must not emit the ordinary
  // recomposition coaching while clinical automation/guidance is paused.
  result.guidance = difficult && !blocked
  result.missing = missingAnswers(form, ['hunger', 'energy'])
  if (result.missing.length) return { ...result, nextCount: 0, reason: 'missing_answers' }
  if (!difficult) return { ...result, nextCount: 0, reason: 'not_difficult' }
  if (!Number.isSafeInteger(value.count + 1)) throw new RangeError('Difficulty counter overflow')
  result.nextCount = value.count + 1
  if (blocked) return { ...result, reason: 'safety' }
  if (value.higherPriorityDecisionConfirmed)
    return { ...result, reason: 'higher_priority_decision' }
  if (value.deficitLevel === 400) return { ...result, reason: 'minimum_deficit' }
  if (value.count < 1) return { ...result, reason: 'first_difficult' }
  return {
    ...result,
    reason: 'second_difficult',
    proposal: {
      deficitBefore: value.deficitLevel,
      deficitAfter: value.deficitLevel === 600 ? 500 : 400,
      deltaKcal: 100,
      countAfterConfirmation: 0,
    },
  }
}

const gainLimitsSchema = z
  .object({
    sex: z.enum(['masculino', 'feminino']).nullable(),
    bodyFatHundredths: z.number().int().min(1).max(10000).nullable(),
    startBodyFatHundredths: z.number().int().min(1).max(10000).nullable(),
    bmi: z.number().finite().positive().nullable(),
    startBMI: z.number().finite().positive().nullable(),
  })
  .strict()
type GainLimit = 'fat_increase' | 'bmi_increase' | 'fat_above_entry'
/** n17 facts only. Notice deduplication/confirmation belongs to durable receipts. */
export function evaluateGainReviewLimits(input: unknown): {
  active: GainLimit[]
  notEvaluated: GainLimit[]
} {
  const value = gainLimitsSchema.parse(input)
  const active: GainLimit[] = []
  const notEvaluated: GainLimit[] = []
  if (
    value.sex === null ||
    value.bodyFatHundredths === null ||
    value.startBodyFatHundredths === null
  )
    notEvaluated.push('fat_increase')
  else if (
    value.bodyFatHundredths - value.startBodyFatHundredths >=
    (value.sex === 'masculino' ? 300 : 400)
  )
    active.push('fat_increase')
  if (value.bmi === null || value.startBMI === null) notEvaluated.push('bmi_increase')
  else if (value.bmi - value.startBMI - 1.5 > 1e-9) active.push('bmi_increase')
  if (value.sex === null || value.bodyFatHundredths === null) notEvaluated.push('fat_above_entry')
  else if (value.bodyFatHundredths > (value.sex === 'masculino' ? 1900 : 2700))
    active.push('fat_above_entry')
  return { active, notEvaluated }
}
const frequency = z.number().int().min(0).max(7).nullable()
const phaseSchema = z
  .object({
    form: reevaluationFormDraftSchema,
    safety: z.unknown(),
    history: reevaluationWeightHistorySchema,
    // Already recomputed for candidate weight/current episode, before this step.
    currentTargetKcal: z.number().int().safe().positive(),
    floorKcal: z.number().int().safe().positive().nullable(),
    ledgerSteps: z.array(
      z
        .number()
        .int()
        .min(-200)
        .max(200)
        .refine((v) => v !== 0),
    ),
    maintenanceSince: clinicalCivilDateSchema.nullable(),
    activityChangedThisCycle: z.boolean(),
    transitionActive: z.boolean(),
    higherPriorityDecisionConfirmed: z.boolean(),
    sex: z.enum(['masculino', 'feminino']).nullable(),
    gainStartBMI: z.number().finite().positive().nullable(),
    gainStartBodyFatHundredths: z.number().int().min(1).max(10000).nullable(),
    gainStartFrequency: frequency,
    profileStrengthFrequency: frequency,
  })
  .strict()
type RuleStatus = 'proposed' | 'unchanged' | 'blocked' | 'not_evaluated' | 'missing'
interface PhaseCalorieEvaluation {
  status: RuleStatus
  reason: string
  missing: string[]
  proposal: null | {
    rule: 'n4' | 'n16'
    deltaKcal: number
    targetKcal: number
    ledgerAbsAfter: number
  }
}
function noStep(
  status: RuleStatus,
  reason: string,
  missing: string[] = [],
): PhaseCalorieEvaluation {
  return { status, reason, missing, proposal: null }
}
function canonicalBodyFat(value: unknown): number | null {
  if (value === null) return null
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    Math.abs(Math.round(value * 100) - value * 100) > 1e-9
  )
    throw new Error('Body fat must be the canonical two-decimal report')
  return Math.round(value * 100)
}

/** n4/n16 proposals only. BMR/floor/episode/profile/config/history must all be
 * reconstructed and bound by the subsequent authoritative clinical snapshot.
 * No use of this function itself authorizes a write or bypasses a confirmation. */
export function evaluatePhaseCalorieRule(input: unknown): PhaseCalorieEvaluation {
  const value = phaseSchema.parse(input)
  const { form } = value
  const { safety, blocked } = boundSafety(form, value.safety)
  const date = (value.safety as { date: string }).date
  if (value.history.date !== date) throw new Error('History is not bound to the clinical date')
  if (form.kind !== 'REGULAR' || form.phase === 'recomposicao')
    return noStep('not_evaluated', 'review_kind_or_phase')
  if (blocked) return noStep('blocked', 'safety')
  if (value.higherPriorityDecisionConfirmed) return noStep('blocked', 'higher_priority_decision')
  if (value.transitionActive) return noStep('blocked', 'transition')
  if (value.activityChangedThisCycle) return noStep('blocked', 'activity_changed')
  const adherenceMissing = missingAnswers(form, ['adherence'])
  if (adherenceMissing.length) return noStep('missing', 'missing_answers', adherenceMissing)
  if (
    form.answers.adherence === 'pouco_consistente' ||
    (form.phase === 'ganho_massa' && form.answers.adherence !== 'bem_consistente')
  )
    return noStep('blocked', 'adherence')
  if (form.phase === 'manutencao') {
    if (value.maintenanceSince === null)
      return noStep('missing', 'maintenance_reference', ['maintenanceSince'])
    if (clinicalDateOrdinal(date) - clinicalDateOrdinal(value.maintenanceSince) < 14)
      return noStep('not_evaluated', 'before_R_plus_14')
  } else {
    const missing = missingAnswers(form, ['strengthSessions', 'healthCheck'])
    if (value.gainStartFrequency === null) missing.push('gainStartFrequency')
    if (value.profileStrengthFrequency === null) missing.push('profileStrengthFrequency')
    if (value.sex === null) missing.push('sex')
    const sessions = form.answers.strengthSessions
    const initialFrequency = value.gainStartFrequency
    const profileFrequency = value.profileStrengthFrequency
    if (sessions === null || initialFrequency === null || profileFrequency === null)
      return noStep('missing', 'missing_answers', missing)
    if (missing.length) return noStep('missing', 'missing_answers', missing)
    if (form.answers.healthCheck?.kind !== 'none') return noStep('blocked', 'safety')
    if (sessions < Math.max(initialFrequency, profileFrequency))
      return noStep('blocked', 'training_baseline')
    const limits = evaluateGainReviewLimits({
      sex: value.sex,
      bodyFatHundredths: canonicalBodyFat(
        (value.safety as { bodyFatPercent: unknown }).bodyFatPercent,
      ),
      startBodyFatHundredths: value.gainStartBodyFatHundredths,
      bmi: safety.bmi,
      startBMI: value.gainStartBMI,
    })
    if (limits.active.length) return noStep('blocked', 'gain_limit')
  }
  const trend = evaluateReevaluationWeightHistory(value.history).fortnight
  if (trend.status !== 'known') return noStep('missing', trend.reason, ['weightHistory'])
  let delta: number
  if (form.phase === 'manutencao') {
    if (trend.direction === 'falling') return noStep('unchanged', 'weight_falling')
    const missing = missingAnswers(form, ['hunger', 'energy'])
    if (missing.length) return noStep('missing', 'missing_answers', missing)
    if (trend.direction === 'rising') {
      const difficultyMissing = missingAnswers(form, ['difficultToMaintain'])
      if (difficultyMissing.length) return noStep('missing', 'missing_answers', difficultyMissing)
      if (
        form.answers.hunger === 'muita' ||
        form.answers.energy === 'baixa' ||
        form.answers.difficultToMaintain === 'sim'
      )
        return noStep('blocked', 'signals_or_difficulty')
      delta = trend.aboveOnePercent ? -200 : -100
    } else {
      if (form.answers.hunger !== 'muita' || form.answers.energy !== 'baixa')
        return noStep('unchanged', 'conditions_not_met')
      delta = 100
    }
  } else {
    const progressionMissing = missingAnswers(form, ['strengthProgression'])
    if (progressionMissing.length) return noStep('missing', 'missing_answers', progressionMissing)
    if (form.answers.strengthProgression !== 'piorou_ou_travou')
      return noStep('unchanged', 'conditions_not_met')
    const missing = missingAnswers(form, ['hunger', 'energy'])
    if (missing.length) return noStep('missing', 'missing_answers', missing)
    const difficult = form.answers.hunger === 'muita' && form.answers.energy === 'baixa'
    if (trend.notRisen && difficult) {
      const fatMissing = missingAnswers(form, ['fatPerception'])
      if (fatMissing.length) return noStep('missing', 'missing_answers', fatMissing)
      if (form.answers.fatPerception !== 'nao_percebi')
        return noStep('unchanged', 'conditions_not_met')
      delta = 150
    } else if (trend.aboveHalfPercent && !difficult) delta = -150
    else return noStep('unchanged', 'conditions_not_met')
  }
  if (value.floorKcal === null) return noStep('missing', 'floor_unavailable', ['floorKcal'])
  if (value.currentTargetKcal < value.floorKcal) return noStep('blocked', 'floor')
  let target = value.currentTargetKcal + delta
  if (form.phase === 'ganho_massa') {
    target = Math.max(target, value.floorKcal)
    delta = target - value.currentTargetKcal
  } else if (target < value.floorKcal) return noStep('blocked', 'floor')
  if (delta === 0) return noStep('unchanged', 'at_floor')
  if (!Number.isSafeInteger(target)) throw new RangeError('Calorie target overflow')
  const used = value.ledgerSteps.reduce((sum, step) => sum + Math.abs(step), 0)
  if (used + Math.abs(delta) > 200) return noStep('blocked', 'cap')
  return {
    status: 'proposed',
    reason: 'conditions_met',
    missing: [],
    proposal: {
      rule: form.phase === 'manutencao' ? 'n4' : 'n16',
      deltaKcal: delta,
      targetKcal: target,
      ledgerAbsAfter: used + Math.abs(delta),
    },
  }
}
