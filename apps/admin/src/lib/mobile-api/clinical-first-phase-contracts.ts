/** Private first-phase transport. An old ACK is historical evidence, never
 * permission to restore a phase/target or override current health. */

import {
  clinicalDateOrdinal,
  clinicalCivilDateSchema as date,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

const phase = z.enum(['recomposicao', 'ganho_massa', 'manutencao'])
const deficit = z.union([z.literal(400), z.literal(500), z.literal(600)])
const kcal = z.number().int().positive().max(2147483647)
const protein = z.number().finite().min(0).max(9999.99)
const hash = z.string().regex(/^[a-f0-9]{64}$/)
export const clinicalFirstPhaseSelectionSchema = z.object({ phase }).strict()
export const clinicalFirstPhasePackageSchema = z
  .object({
    version: z.literal(1),
    phase,
    deficitLevel: deficit.nullable(),
    effectiveDate: date,
    targets: z
      .object({
        beforeKcal: kcal.nullable(),
        beforeProtein: protein.nullable(),
        afterKcal: kcal,
        afterProtein: protein,
        formulaAfterKcal: kcal,
      })
      .strict(),
    formulaBodyFat: z
      .object({
        origin: z.enum(['none', 'report', 'signup', 'recurring']),
        percent: z.number().finite().min(3).max(60).nullable(),
      })
      .strict(),
    episode: z
      .object({
        difficultyCount: z.literal(0).nullable(),
        ledgerSteps: z.array(z.never()).length(0).nullable(),
        schedule: z.null(),
        maintenanceSince: date.nullable(),
      })
      .strict(),
  })
  .strict()
  .refine((v) => (v.phase === 'recomposicao') === (v.deficitLevel !== null))
  .refine((v) =>
    v.phase === 'recomposicao'
      ? v.episode.difficultyCount === 0 && v.episode.ledgerSteps === null
      : v.episode.difficultyCount === null && v.episode.ledgerSteps !== null,
  )
  .refine((v) => v.targets.afterKcal === v.targets.formulaAfterKcal)
  .refine((v) =>
    ['none', 'report'].includes(v.formulaBodyFat.origin)
      ? v.formulaBodyFat.percent === null
      : v.formulaBodyFat.percent !== null,
  )
  .refine(
    (v) =>
      v.episode.maintenanceSince === null ||
      (v.phase === 'manutencao' && v.episode.maintenanceSince === v.effectiveDate),
  )
export const clinicalFirstPhasePreparedSchema = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    preview_id: uuid,
    prepare_operation_key: uuid,
    signup_generation: uuid,
    signup_epoch: uuid,
    context_hash: hash,
    selection: clinicalFirstPhaseSelectionSchema,
    package: clinicalFirstPhasePackageSchema,
    created_at: instant,
    valid_until: instant,
  })
  .strict()
  .refine((v) => v.valid_until > v.created_at && v.selection.phase === v.package.phase)
export const clinicalFirstPhaseResultSchema = z
  .object({
    version: z.literal(1),
    source: z.literal('confirmed_first_phase_v1'),
    first_phase_id: uuid,
    event_id: uuid,
    episode_id: uuid,
    signup_generation: uuid,
    signup_epoch: uuid,
    phase,
    deficit_level: deficit.nullable(),
    decision_date: date,
    effective_date: date,
    confirmed_at: instant,
    applied_snapshot_id: uuid.nullable(),
    targets: z
      .object({ calories_target: kcal, protein_target: protein, formula_target: kcal })
      .strict(),
    maintenance_since: date.nullable(),
  })
  .strict()
  .refine((v) => (v.phase === 'recomposicao') === (v.deficit_level !== null))
  .refine(
    (v) =>
      clinicalDateOrdinal(v.effective_date) ===
      clinicalDateOrdinal(v.decision_date) + (v.applied_snapshot_id === null ? 1 : 0),
  )
  .refine((v) => v.targets.calories_target === v.targets.formula_target)
  .refine(
    (v) =>
      v.maintenance_since ===
      (v.phase === 'manutencao' && v.applied_snapshot_id !== null ? v.decision_date : null),
  )
export const clinicalFirstPhaseConfirmedSchema = z
  .object({
    user_id: uuid,
    preview_id: uuid,
    operation_key: uuid,
    result: clinicalFirstPhaseResultSchema,
  })
  .strict()
  .refine((v) => v.preview_id === v.result.first_phase_id)
export const clinicalFirstPhaseReceiptSchema = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    preview_id: uuid,
    operation_key: uuid,
    operation_matched: z.boolean(),
    prepared: clinicalFirstPhasePreparedSchema,
    result: clinicalFirstPhaseResultSchema,
  })
  .strict()
export type ClinicalFirstPhasePackage = z.infer<typeof clinicalFirstPhasePackageSchema>
export type ClinicalFirstPhasePrepared = z.infer<typeof clinicalFirstPhasePreparedSchema>
export function clinicalFirstPhaseError(kind: 'invalid' | 'changed' | 'busy' | 'unavailable') {
  return new MobileApiError(
    kind === 'invalid' ? 422 : kind === 'unavailable' ? 503 : 409,
    `mobile_clinical_first_phase_${kind}`,
    'Unable to complete first phase selection',
  )
}
