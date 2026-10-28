/** Backend-only projection of consumed FULL authority. No clock, I/O, public DTO
 * or activation. Unconsumed SQL fields never establish clinical provenance. */
import {
  clinicalCivilDateSchema as date,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import {
  legacyReevaluationOriginSchema,
  reevaluationFormDraftSchema,
  requiresReevaluationPhotos,
} from '@mpp/core/reevaluation-form'
import { reevaluationPhaseScheduleSchema } from '@mpp/core/reevaluation-phase-schedule'
import { z } from 'zod'
import {
  fullDeficit,
  fullDifficulty,
  fullFrequency,
  fullKind,
  fullLedger,
  fullLevel,
  fullPhase,
  fullPositiveCounter,
  fullPrincipal,
  fullScopeSchema,
  fullWeight,
} from './clinical-full-contracts'
import { readClinicalGenerationAuthority } from './clinical-generation-authority'
import { clinicalCalculationSnapshotSchema } from './clinical-snapshot-calculation'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

const baselineBF = z.number().finite().min(3).max(60)
const positive = z.number().finite().positive()
const bound = z.object({ user_id: uuid, signup_generation: uuid, signup_epoch: uuid })
const zone = z
  .string()
  .min(1)
  .max(256)
  .refine(
    (v) =>
      v === v.trim() && Array.from(v).every((c) => c.charCodeAt(0) > 31 && c.charCodeAt(0) !== 127),
  )
const episode = bound
  .extend({
    review_id: uuid.nullable(),
    first_phase_id: uuid.nullable().optional(),
    event_id: uuid,
    event_no: fullPositiveCounter,
    previous_event_id: uuid.nullable(),
    episode_id: uuid,
    phase: fullPhase,
    entry_origin: z.enum(['signup', 'confirmed_phase_change', 'legacy_unknown']),
    entry_date: date.nullable(),
    start_weight_kg: fullWeight.nullable(),
    start_height_cm: positive.nullable(),
    start_body_fat_percent: baselineBF.nullable(),
    start_training_frequency: fullFrequency.nullable(),
    maintenance_since: date.nullable(),
    deficit_level: fullDeficit.nullable(),
    difficulty_count: fullDifficulty.nullable(),
    ledger_steps: fullLedger.nullable(),
    schedule: reevaluationPhaseScheduleSchema.nullable(),
    applied_at: instant,
    rule_version: z.literal('clinical-v1'),
  })
  .strict()
  .refine(
    (v) =>
      (v.review_id !== null && v.first_phase_id == null) ||
      (v.review_id === null && v.first_phase_id != null),
  )
  .refine((v) =>
    v.phase === 'recomposicao'
      ? v.deficit_level !== null || v.entry_origin === 'legacy_unknown'
      : v.deficit_level === null,
  )
  .refine(
    (v) =>
      v.entry_origin !== 'legacy_unknown' ||
      [
        v.entry_date,
        v.start_weight_kg,
        v.start_height_cm,
        v.start_body_fat_percent,
        v.start_training_frequency,
      ].every((v) => v === null),
  )
const signup = bound
  .extend({
    episode_id: uuid,
    phase: fullPhase,
    started_at: instant,
    start_date: date,
    timezone_at_entry: zone,
    start_weight_kg: fullWeight,
    start_height_cm: positive,
    start_body_fat_percent: baselineBF.nullable(),
    start_training_frequency: fullFrequency.nullable(),
    start_activity_level: fullLevel.nullable(),
    deficit_level: fullDeficit.nullable(),
    maintenance_since: date.nullable(),
    captured_at: instant,
    rule_version: z.literal('clinical-v1'),
  })
  .strict()
  .refine(
    (v) =>
      v.captured_at >= v.started_at &&
      (v.phase === 'recomposicao') === (v.deficit_level !== null) &&
      (v.phase === 'manutencao') === (v.maintenance_since !== null) &&
      (v.maintenance_since === null || v.maintenance_since === v.start_date),
  )
const phaseOrigin = z.discriminatedUnion('kind', [
  legacyReevaluationOriginSchema,
  z.object({ kind: z.literal('assigned') }).strict(),
  z.object({ kind: z.literal('legacy_unassigned') }).strict(),
  z
    .object({
      kind: z.literal('confirmed_no_plan'),
      signupGeneration: uuid,
      signupEpoch: uuid,
      completedAt: instant,
    })
    .strict(),
])
const prior = z
  .object({
    review_id: uuid,
    kind: z.literal('REGULAR'),
    date,
    review_no: fullPositiveCounter,
    form: reevaluationFormDraftSchema,
    principal: fullPrincipal,
    activity_level_changed: z.boolean(),
  })
  .strict()
  .refine((v) => v.form.kind === 'REGULAR')
const routine = z
  .object({
    review_id: uuid,
    principal: z.enum(['keep', 'activity']),
    base_before: date,
    date,
    review_no: fullPositiveCounter,
    activity_level_changed: z.boolean(),
  })
  .strict()
const weight = z
  .object({
    id: uuid,
    user_id: uuid,
    weight_kg: fullWeight,
    measured_at: instant,
    instant_source: z.enum(['measured', 'recorded']),
    received_at: instant,
    observed_timezone: z.string().min(1).max(64),
    authority_epoch: uuid,
    local_date: date,
  })
  .strict()
const baseFacts = clinicalCalculationSnapshotSchema.shape.facts
const contextSchema = clinicalCalculationSnapshotSchema.extend({
  review_kind: fullKind,
  facts: baseFacts.extend({
    owner: baseFacts.shape.owner.extend({ updated_at: instant }),
    anchor: baseFacts.shape.anchor
      .extend({
        clock: z.object({ base_date: date, due_date: date, timezone: zone }).strict(),
        last_full_id: uuid.nullable(),
        reason: z.literal('not_due').nullable(),
        next_kind: z.enum(['REGULAR', 'TRANSITION_FULL']).optional(),
      })
      .strict(),
    protocol_authority: baseFacts.shape.protocol_authority.extend({
      phase_origin: phaseOrigin,
      episode: episode.nullable(),
      signup_origin: signup.nullable(),
      prior_regular_reviews: z.array(prior).max(2),
      routine_reviews_since_regular: z.array(routine),
    }),
    weight_history: z.array(weight),
  }),
})
const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase()
function invalid(): never {
  throw new Error('Invalid clinical FULL authority')
}

export function readClinicalFullContext(raw: unknown, expectedScope: unknown) {
  try {
    const scope = fullScopeSchema.parse(expectedScope)
    const context = contextSchema.parse(structuredClone(raw))
    const { facts } = context
    const { anchor, profile, protocol_authority: authority } = facts
    const owner = scope.userId
    if (
      [context.user_id, facts.owner.id, profile.user_id, facts.safety.user_id].some(
        (v) => !same(v, owner),
      ) ||
      context.review_kind !== scope.kind ||
      (context.cycle_id === null
        ? scope.cycleId !== null
        : scope.cycleId === null || !same(context.cycle_id, scope.cycleId)) ||
      context.valid_until <= context.observed_at ||
      new Set(facts.safety.items.map((v) => v.code)).size !== facts.safety.items.length ||
      facts.safety.hold_active !== facts.safety.items.length > 0 ||
      (facts.day && (!same(facts.day.user_id, owner) || facts.day.date !== facts.calculation_date))
    )
      invalid()
    const generationSource = readClinicalGenerationAuthority(anchor, {
      userId: owner,
      profileCompletedAt: profile.onboarding_completed_at,
      observedAt: context.observed_at,
    })
    if (
      generationSource.kind !== 'signup_receipt' &&
      (authority.signup_origin !== null ||
        authority.signup_body_fat_origin !== null ||
        authority.phase_origin.kind === 'confirmed_no_plan')
    )
      invalid()
    if (generationSource.kind === 'legacy_transition') {
      if (
        !anchor.next_kind ||
        (anchor.next_kind === 'TRANSITION_FULL') !== (anchor.last_full_id === null) ||
        (scope.kind === 'TRANSITION_FULL') !== (anchor.next_kind === 'TRANSITION_FULL') ||
        (anchor.next_kind === 'TRANSITION_FULL' && anchor.clock.base_date !== anchor.clock.due_date)
      )
        invalid()
    } else if (anchor.next_kind !== undefined || scope.kind === 'TRANSITION_FULL') invalid()
    const matches = (v: z.infer<typeof bound>) =>
      same(v.user_id, owner) &&
      same(v.signup_generation, anchor.signup_generation) &&
      same(v.signup_epoch, anchor.signup_epoch)
    if (
      [
        authority.episode,
        authority.signup_origin,
        authority.body_fat_origin,
        authority.signup_body_fat_origin,
      ].some((v) => v !== null && !matches(v))
    )
      invalid()
    if (
      authority.episode &&
      (authority.episode.phase !== profile.current_protocol ||
        authority.episode.applied_at > context.observed_at)
    )
      invalid()
    if (authority.signup_origin && authority.signup_origin.captured_at > context.observed_at)
      invalid()
    const origin = authority.phase_origin
    if ((origin.kind === 'assigned') !== (profile.current_protocol !== null)) invalid()
    if (
      origin.kind === 'legacy_transition_unassigned' &&
      (generationSource.kind !== 'legacy_transition' ||
        !same(origin.generation, generationSource.generation) ||
        !same(origin.epoch, generationSource.epoch) ||
        origin.admittedAt !== generationSource.admitted_at ||
        authority.episode !== null ||
        authority.signup_origin !== null)
    )
      invalid()
    if (
      origin.kind === 'confirmed_no_plan' &&
      (!same(origin.signupGeneration, anchor.signup_generation) ||
        !same(origin.signupEpoch, anchor.signup_epoch) ||
        origin.completedAt !== profile.onboarding_completed_at ||
        authority.episode !== null ||
        authority.signup_origin !== null)
    )
      invalid()
    if (
      authority.signup_body_fat_origin &&
      (authority.signup_body_fat_origin.onboarding_completed_at !==
        profile.onboarding_completed_at ||
        authority.signup_body_fat_origin.confirmed_body_fat_percent !== profile.body_fat_percent ||
        authority.signup_body_fat_origin.decided_at > context.observed_at)
    )
      invalid()
    if (
      authority.body_fat_origin &&
      (authority.body_fat_origin.mean_percent !== profile.body_fat_percent ||
        authority.body_fat_origin.confirmed_at !== profile.body_fat_measured_at ||
        authority.body_fat_origin.confirmed_at > context.observed_at)
    )
      invalid()
    const candidate = authority.body_fat_candidate
    if (
      candidate?.availability === 'available' &&
      (!matches(candidate) ||
        Math.abs(candidate.mean_percent * 100 - candidate.mean_hundredths) > 1e-9 ||
        (requiresReevaluationPhotos(scope.kind) &&
          (scope.cycleId === null || !same(candidate.cycle_id, scope.cycleId))))
    )
      invalid()
    if (
      facts.weight_history.some(
        (v) => !same(v.user_id, owner) || !same(v.authority_epoch, anchor.signup_epoch),
      )
    )
      invalid()
    for (const rows of [authority.prior_regular_reviews, authority.routine_reviews_since_regular]) {
      if (new Set(rows.map((v) => v.review_id.toLowerCase())).size !== rows.length) invalid()
      let previous: bigint | undefined
      for (const row of rows) {
        const current = BigInt(row.review_no)
        if (previous !== undefined && current <= previous) invalid()
        previous = current
      }
    }
    return context
  } catch {
    return invalid()
  }
}
