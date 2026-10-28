/** Private backend contracts, never accepted as client-calculated effects. */
import {
  clinicalCivilDateSchema as date,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import {
  isFullReevaluationKind,
  reevaluationFormDraftSchema,
  reevaluationGoalPreferenceSchema,
  requiresReevaluationPhotos,
} from '@mpp/core/reevaluation-form'
import { reevaluationPhaseScheduleSchema } from '@mpp/core/reevaluation-phase-schedule'
import { z } from 'zod'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

export const fullHash = z.string().regex(/^[a-f0-9]{64}$/)
export const fullKind = z.enum([
  'REGULAR',
  'EARLY_FULL',
  'TRANSITION_FULL',
  'SAFETY',
  'ROUTINE_REVIEW',
])
export const fullPhase = z.enum(['recomposicao', 'manutencao', 'ganho_massa'])
export const fullLevel = z.enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta'])
export const fullDeficit = z.union([z.literal(400), z.literal(500), z.literal(600)])
export const fullFrequency = z.number().int().min(0).max(7)
export const fullPrincipal = z.enum([
  'keep',
  'deficit_step',
  'activity',
  'phase_maintenance',
  'phase_gain',
  'phase_recomposition',
  'recomposition_transition',
  'gain_exit',
  'neutral_exit',
  'maintenance_step',
  'gain_step',
  'schedule_reconfirm',
  'schedule_pause',
])
export const fullCounter = z
  .string()
  .regex(/^(0|[1-9]\d{0,18})$/)
  .refine((v) => v.length < 19 || v <= '9223372036854775807')
export const fullPositiveCounter = fullCounter.refine((v) => v !== '0')
export const fullDifficulty = fullCounter.refine((v) => BigInt(v) <= 9007199254740991n)
export const fullLedger = z
  .array(
    z
      .number()
      .int()
      .min(-200)
      .max(200)
      .refine((v) => v !== 0),
  )
  .max(200)
  .refine((steps) => steps.reduce((sum, value) => sum + Math.abs(value), 0) <= 200)
const hundredths = (value: number) => Math.abs(value * 100 - Math.round(value * 100)) < 1e-9
export const fullWeight = z.number().finite().min(30).max(300).refine(hundredths)
export const fullBodyFat = z.number().finite().min(3).max(60).refine(hundredths)
const kcal = z.number().int().min(1).max(2147483647).nullable()
const protein = z.number().finite().min(0).max(9999.99).refine(hundredths).nullable()
export const fullScopeSchema = z
  .object({ userId: uuid, kind: fullKind, cycleId: uuid.nullable() })
  .strict()
  .refine((v) => isFullReevaluationKind(v.kind) === (v.cycleId !== null))
export type ClinicalFullScope = z.infer<typeof fullScopeSchema>
export const fullTargetsSchema = z
  .object({
    beforeKcal: kcal,
    beforeProtein: protein,
    afterKcal: kcal,
    afterProtein: protein,
    formulaAfterKcal: kcal,
  })
  .strict()
export const fullIntentSchema = z
  .object({
    principalConfirmed: z.boolean(),
    bodyFat: z
      .object({
        confirmed: z.literal(true),
        sourceHash: fullHash,
        meanHundredths: z.number().int().min(300).max(6000),
      })
      .strict()
      .nullable()
      .optional(),
  })
  .strict()
export const fullProposalSchema = z
  .object({
    version: z.literal(1),
    principal: fullPrincipal,
    clearHold: z.boolean(),
    profile: z
      .object({
        current_protocol: fullPhase.nullable(),
        deficit_level: fullDeficit.nullable(),
        activity_level: fullLevel.nullable(),
        training_frequency: fullFrequency.nullable(),
        hunger_level: z.enum(['pouca', 'moderada', 'muita']).nullable(),
      })
      .strict()
      .refine((v) => v.current_protocol === 'recomposicao' || v.deficit_level === null),
    targets: fullTargetsSchema,
    episode: z
      .object({
        difficultyCount: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER).nullable(),
        ledgerSteps: fullLedger.nullable(),
        schedule: reevaluationPhaseScheduleSchema.nullable(),
        maintenanceSince: date.nullable(),
      })
      .strict(),
  })
  .strict()
  .refine(
    (v) =>
      v.profile.current_protocol !== 'recomposicao' ||
      v.profile.deficit_level !== null ||
      (v.principal === 'keep' &&
        v.targets.formulaAfterKcal === null &&
        v.targets.beforeKcal === v.targets.afterKcal &&
        v.targets.beforeProtein === v.targets.afterProtein &&
        v.episode.ledgerSteps === null &&
        v.episode.schedule === null &&
        v.episode.maintenanceSince === null),
  )
export const fullPackageSchema = z
  .object({
    form: reevaluationFormDraftSchema,
    intent: fullIntentSchema,
    proposal: fullProposalSchema,
  })
  .strict()
  .refine(
    (v) =>
      requiresReevaluationPhotos(v.form.kind) === (v.intent.bodyFat != null) &&
      (v.proposal.principal === 'keep' || v.intent.principalConfirmed) &&
      (v.form.kind !== 'SAFETY' || v.proposal.principal === 'neutral_exit'),
  )
export const fullChoiceSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('keep') }).strict(),
  z.object({ kind: z.literal('phase'), phase: fullPhase }).strict(),
  z.object({ kind: z.literal('activity') }).strict(),
  z.object({ kind: z.literal('phase_calorie_step') }).strict(),
  z.object({ kind: z.literal('schedule'), action: z.enum(['reconfirm', 'pause']) }).strict(),
  z.object({ kind: z.literal('neutral_exit') }).strict(),
])
/** Canonical private identity: defaults/clinical refusals happen upstream. */
export const fullCommandSchema = z
  .object({
    form: reevaluationFormDraftSchema,
    choice: fullChoiceSchema,
    measureConfirmed: z.boolean(),
    bodyFat: fullIntentSchema.shape.bodyFat.unwrap().nullable(),
  })
  .strict()
export const fullNormalizationSchema = z
  .object({
    sex: z.enum(['masculino', 'feminino']).nullable(),
    heightCm: z.number().finite().positive().nullable(),
  })
  .strict()
type Preference = Extract<
  NonNullable<z.infer<typeof reevaluationGoalPreferenceSchema>>,
  { action: 'change' }
>['value']
const preferenceValue = z.custom<Preference>(
  (value) => reevaluationGoalPreferenceSchema.safeParse({ action: 'change', value }).success,
)
export const fullResultSchema = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    review_id: uuid,
    kind: fullKind,
    status: z.literal('confirmed'),
    principal: fullPrincipal,
    completed_at: instant,
    cycle_id: uuid.nullable(),
    cycle_revision: fullPositiveCounter.nullable(),
    safety_revision: fullCounter,
    next_due_date: date,
    targets: fullTargetsSchema,
    body_fat_percent: fullBodyFat.nullable(),
    preference: z
      .object({
        status: z.enum(['saved', 'removed', 'unchanged']),
        value: preferenceValue.nullable(),
      })
      .strict()
      .refine((v) =>
        v.status === 'saved' ? v.value !== null : v.status !== 'removed' || v.value === null,
      ),
  })
  .strict()
  .refine(
    (v) =>
      (v.kind === 'ROUTINE_REVIEW'
        ? v.cycle_id === null && v.cycle_revision === null
        : v.cycle_id !== null && v.cycle_revision !== null) &&
      (requiresReevaluationPhotos(v.kind)
        ? v.body_fat_percent !== null
        : v.body_fat_percent === null),
  )
export const fullPreviewSchema = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    preview_id: uuid,
    review_kind: fullKind,
    cycle_id: uuid.nullable(),
    context_hash: fullHash,
    rule_version: z.literal('clinical-v1'),
    created_at: instant,
    valid_until: instant,
  })
  .strict()
  .refine(
    (v) =>
      v.valid_until > v.created_at &&
      isFullReevaluationKind(v.review_kind) === (v.cycle_id !== null),
  )
export const fullPreparedSchema = z
  .object({
    user_id: uuid,
    operation_key: uuid,
    preview: fullPreviewSchema,
  })
  .strict()
export const fullConfirmedSchema = z
  .object({
    user_id: uuid,
    preview_id: uuid,
    operation_key: uuid,
    result: fullResultSchema,
  })
  .strict()
export const fullReceiptSchema = z
  .object({
    user_id: uuid,
    preview_id: uuid,
    operation_key: uuid,
    operation_matched: z.boolean(),
    review_no: fullPositiveCounter,
    form: reevaluationFormDraftSchema,
    intent: fullIntentSchema,
    proposal: fullProposalSchema,
    result: fullResultSchema,
  })
  .strict()
export const fullPresentationSchema = z
  .object({
    version: z.literal(1),
    hide: z
      .object({ objective: z.boolean(), calories: z.boolean(), protein: z.boolean() })
      .strict(),
    professionalAssessmentRecommended: z.boolean(),
    pauseWeightLossGuidance: z.boolean(),
  })
  .strict()
export const fullCommandPreparedSchema = fullPreparedSchema
  .extend({
    command_version: z.literal(1),
    command: fullCommandSchema,
    command_hash: fullHash,
    normalization_context: fullNormalizationSchema,
    package: fullPackageSchema,
    // Absence is historical unknown. Never default or infer a legacy mask.
    presentation: fullPresentationSchema.optional(),
  })
  .strict()
export const fullCommandReceiptSchema = fullReceiptSchema
  .extend({
    prepared: fullCommandPreparedSchema,
  })
  .strict()
export type ClinicalFullCommand = z.infer<typeof fullCommandSchema>
export type ClinicalFullCommandPrepared = z.infer<typeof fullCommandPreparedSchema>
export type ClinicalFullCommandReceipt = z.infer<typeof fullCommandReceiptSchema>
export type ClinicalFullProposal = z.infer<typeof fullProposalSchema>
export type ClinicalFullIntent = z.infer<typeof fullIntentSchema>
export type ClinicalFullPackage = z.infer<typeof fullPackageSchema>
export function clinicalFullError(kind: 'changed' | 'busy' | 'unavailable' | 'invalid') {
  return new MobileApiError(
    kind === 'invalid' ? 422 : kind === 'unavailable' ? 503 : 409,
    `mobile_clinical_full_${kind}`,
    kind === 'invalid'
      ? 'Invalid clinical review request'
      : 'Clinical review unavailable; refresh before trying again',
  )
}
