/** Public draft -> private server command. No client phase, clinical effect,
 * mean, raw photo proof, generation or context hash crosses this boundary. */
import { createHash } from 'node:crypto'
import {
  reevaluationAnswersSchema,
  reevaluationFormDraftSchema,
  reevaluationGoalPreferenceSchema,
  requiresReevaluationPhotos,
} from '@mpp/core/reevaluation-form'
import { z } from 'zod'
import { readClinicalFullContext } from './clinical-full-authority'
import {
  type ClinicalFullCommandPrepared,
  type ClinicalFullScope,
  clinicalFullError,
  fullChoiceSchema,
  fullHash,
} from './clinical-full-contracts'

export const clinicalFullPublicDraftSchema = z
  .object({
    activityPurpose: z.enum(['normal', 'consider_maintenance', 'end_deficit']),
    answers: reevaluationAnswersSchema,
    preference: reevaluationGoalPreferenceSchema,
    measureConfirmed: z.boolean(),
    bodyFat: z
      .object({ confirmed: z.literal(true), candidateId: fullHash })
      .strict()
      .nullable(),
  })
  .strict()
export const clinicalFullPublicInputSchema = clinicalFullPublicDraftSchema
  .extend({ choice: fullChoiceSchema })
  .strict()
const proofSchema = z
  .object({
    confirmed: z.literal(true),
    sourceHash: fullHash,
    meanHundredths: z.number().int().min(300).max(6000),
  })
  .strict()
type Proof = z.infer<typeof proofSchema>
type Source =
  | { context: ReturnType<typeof readClinicalFullContext> }
  | { prepared: ClinicalFullCommandPrepared }
export function clinicalFullPublicCandidateId(scope: ClinicalFullScope, rawProof: unknown): string {
  const proof = proofSchema.parse(rawProof)
  // A stable opaque display identity, not the private source hash. The server
  // compares it to its actual candidate and obtains the mean from that source.
  return createHash('sha256')
    .update(
      JSON.stringify({
        version: 1,
        domain: 'mobile_full_photo_display',
        owner: scope.userId.toLowerCase(),
        cycle: scope.cycleId?.toLowerCase() ?? null,
        source: proof.sourceHash,
        mean: proof.meanHundredths,
      }),
    )
    .digest('hex')
}
export function bindClinicalFullPublicCommand(
  raw: unknown,
  scope: ClinicalFullScope,
  source: Source,
) {
  const input = clinicalFullPublicInputSchema.parse(structuredClone(raw))
  let phase: 'recomposicao' | 'manutencao' | 'ganho_massa' | null
  let unassignedOrigin: unknown,
    proof: Proof | null = null
  if ('context' in source) {
    const context = readClinicalFullContext(source.context, scope)
    phase = context.facts.profile.current_protocol
    if (phase === null) unassignedOrigin = context.facts.protocol_authority.phase_origin
    const candidate = context.facts.protocol_authority.body_fat_candidate
    if (requiresReevaluationPhotos(scope.kind) && candidate?.availability === 'available')
      proof = {
        confirmed: true,
        sourceHash: candidate.source_hash,
        meanHundredths: candidate.mean_hundredths,
      }
  } else {
    const prepared = source.prepared
    if (
      prepared.preview.user_id.toLowerCase() !== scope.userId.toLowerCase() ||
      prepared.preview.review_kind !== scope.kind ||
      prepared.preview.cycle_id !== scope.cycleId
    )
      throw clinicalFullError('changed')
    const original = prepared.command.form
    phase = original.phase
    if (original.phase === null)
      unassignedOrigin = 'legacyOrigin' in original ? original.legacyOrigin : original.noPlanOrigin
    proof = prepared.command.bodyFat ?? null
  }
  if (requiresReevaluationPhotos(scope.kind)) {
    if (
      !proof ||
      !input.bodyFat ||
      clinicalFullPublicCandidateId(scope, proof) !== input.bodyFat.candidateId
    )
      throw clinicalFullError('changed')
  } else if (input.bodyFat !== null) throw clinicalFullError('invalid')
  else proof = null
  const form = reevaluationFormDraftSchema.parse({
    version: 1,
    phase,
    kind: scope.kind,
    ...(phase === null
      ? {
          [unassignedOrigin &&
          typeof unassignedOrigin === 'object' &&
          'kind' in unassignedOrigin &&
          unassignedOrigin.kind === 'legacy_transition_unassigned'
            ? 'legacyOrigin'
            : 'noPlanOrigin']: unassignedOrigin,
        }
      : {}),
    activityPurpose: input.activityPurpose,
    answers: input.answers,
    preference: input.preference,
  })
  return { form, choice: input.choice, measureConfirmed: input.measureConfirmed, bodyFat: proof }
}
