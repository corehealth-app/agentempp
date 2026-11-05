/** Additive current-safe presentation of an already durable canonical v3.
 * No route, writer, canonical seal, Today calculation or reward is reachable.
 * Integration supplies one immutable canonical receipt read; K owns its store. */
import { isDeepStrictEqual } from 'node:util'
import {
  type FeedbackV3Registration,
  type FeedbackV3Section,
  parseFeedbackV3Registration,
  parseRegistrationFeedbackV3,
  prepareRegistrationFeedbackV3,
  type RegistrationFeedbackV3,
  renderRegistrationFeedbackV3,
} from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { conversationJournalBindingSchema } from './conversation-command-candidate-contracts'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import {
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
} from './conversation-current-scope'
import { parseConversationMealContinuationFeedbackBinding } from './conversation-meal-continuation-read-contracts'
import { isHistoricalMealFeedbackRestricted } from './conversation-meal-feedback-presentation'
import { parseConversationMealEffectReceipt } from './conversation-meal-feedback-store'
import {
  conversationJournalInstant,
  conversationJournalUUID,
} from './conversation-meal-journal-store'
import {
  type CapturedConversationWorkoutSource,
  parseConversationWorkoutSource,
  workoutClock,
  workoutSnapshot,
} from './conversation-workout-contracts'
import { parseConversationWorkoutEffect } from './conversation-workout-writer'
import {
  currentClinicalReadBinding,
  projectCurrentClinicalPublicPolicy,
} from './current-clinical-read-model'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

export type ConversationFeedbackPresentationV2Proof =
  | {
      readonly kind: 'meal.report'
      readonly command: BoundConversationMealCommand
      readonly serverBinding: unknown
      readonly receipt: unknown
    }
  | { readonly kind: 'meal.clarify'; readonly binding: unknown }
  | {
      readonly kind: 'workout.report'
      readonly source: CapturedConversationWorkoutSource
      readonly prepared: unknown
      readonly effect: unknown
    }
export interface ConversationFeedbackPresentationV2Input {
  readonly auth: MobileAuthContext
  readonly proof: ConversationFeedbackPresentationV2Proof
}
const uuid = conversationJournalUUID
const policySchema = z
  .object({
    version: z.literal(1),
    observed_at: workoutClock,
    assessment: z.enum(['complete', 'incomplete']),
    recording_allowed: z.literal(true),
    pause_weight_loss_guidance: z.boolean(),
    professional_assessment_recommended: z.boolean(),
    phase_selection_pending: z.boolean(),
    target_source: z.enum(['unavailable', 'official_only', 'assigned_phase']),
    hide: z
      .object({
        objective: z.boolean(),
        calories: z.boolean(),
        protein: z.boolean(),
        balance: z.boolean(),
        block: z.boolean(),
        budget: z.boolean(),
      })
      .strict(),
  })
  .strict()
type Policy = z.infer<typeof policySchema>
export interface ConversationFeedbackPresentationV2 {
  readonly schema: 'conversation.feedback-presentation.v2'
  readonly mode: 'historical'
  readonly assistant: 'Flow AI'
  readonly original: {
    readonly schema: 'registration.feedback.v3'
    readonly registration_id: string
    readonly kind: 'meal' | 'workout'
    readonly local_date: string
  }
  readonly status: 'available'
  readonly format: 'sections'
  readonly recorded: FeedbackV3Registration
  readonly sections: readonly FeedbackV3Section[]
  readonly current_policy: Policy
  readonly provenance: {
    readonly epoch: string
    readonly command_id: string
    readonly observed_at: string
  }
}
function invalid(): never {
  throw new Error('Current historical v3 presentation unavailable')
}
function exact<T>(schema: z.ZodType<T>, raw: unknown): T {
  const copy = workoutSnapshot(raw),
    value = schema.parse(copy)
  if (!isDeepStrictEqual(copy, value)) return invalid()
  return copy as T
}
const required = z.unknown().refine((v) => v !== undefined)
const proofSchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('meal.report'),
      command: required,
      serverBinding: required,
      receipt: required,
    })
    .strict(),
  z.object({ kind: z.literal('meal.clarify'), binding: required }).strict(),
  z
    .object({
      kind: z.literal('workout.report'),
      source: required,
      prepared: required,
      effect: required,
    })
    .strict(),
])
function bind(input: ConversationFeedbackPresentationV2Input) {
  const raw = workoutSnapshot(input),
    who = workoutSnapshot(raw.auth),
    owner = authenticatedReevaluationOwner(who),
    proof = exact(proofSchema, raw.proof)
  let commandId: string,
    inputHash: string,
    epoch: string,
    registrationId: string,
    localDate: string,
    admittedAt: string,
    effectAt: string,
    kind: 'meal' | 'workout',
    logIds: readonly string[],
    mealKind: string | undefined,
    workout: FeedbackV3Registration | undefined
  if (proof.kind === 'meal.report') {
    const given = proof.command as BoundConversationMealCommand,
      command = bindConversationCommand(owner, `cmsg1:${given.commandId}`, given.command),
      server = exact(conversationJournalBindingSchema, proof.serverBinding),
      receipt = parseConversationMealEffectReceipt(proof.receipt, command)
    if (
      !isDeepStrictEqual(given, command) ||
      server.owner_id !== owner ||
      server.command_id !== command.commandId ||
      server.input_hash !== command.inputHash
    )
      return invalid()
    commandId = command.commandId
    inputHash = command.inputHash
    epoch = server.epoch
    registrationId = receipt.registration_id
    localDate = receipt.local_date
    admittedAt = server.admitted_at
    effectAt = receipt.consumed_at
    kind = 'meal'
    logIds = receipt.log_ids
    mealKind = receipt.meal_type
  } else if (proof.kind === 'meal.clarify') {
    const b = parseConversationMealContinuationFeedbackBinding(proof.binding),
      c = b.childBinding,
      r = b.receipt
    if (c.owner_id !== owner) return invalid()
    commandId = c.command_id
    inputHash = c.input_hash
    epoch = c.epoch
    registrationId = r.registration_id
    localDate = r.local_date
    admittedAt = c.admitted_at
    effectAt = r.consumed_at
    kind = 'meal'
    logIds = r.log_ids
    mealKind = r.meal_type
  } else {
    const given = proof.source as CapturedConversationWorkoutSource,
      source = parseConversationWorkoutSource(given.command, {
        source_hash: given.sourceHash,
        context: given.context,
      })
    if (!isDeepStrictEqual(source, given) || source.command.ownerId !== owner) return invalid()
    const effect = parseConversationWorkoutEffect(source, proof.prepared, proof.effect),
      r = effect.receipt
    commandId = r.command_id
    inputHash = r.input_hash
    epoch = r.epoch
    registrationId = r.registration_id
    localDate = r.local_date
    admittedAt = source.admittedAt
    effectAt = r.committed_at
    kind = 'workout'
    logIds = [r.workout_id]
    workout = { kind: 'workout', log_id: r.workout_id, ...r.activity }
  }
  if (conversationJournalInstant(effectAt) < conversationJournalInstant(admittedAt))
    return invalid()
  return workoutSnapshot({
    who,
    proof: raw.proof,
    owner,
    commandId,
    inputHash,
    epoch,
    registrationId,
    localDate,
    admittedAt,
    effectAt,
    kind,
    logIds,
    ...(mealKind === undefined ? {} : { mealKind }),
    ...(workout === undefined ? {} : { workout }),
  })
}
type Binding = ReturnType<typeof bind>
function original(raw: unknown, b: Binding): RegistrationFeedbackV3 {
  const copy = workoutSnapshot(raw),
    value = parseRegistrationFeedbackV3(copy, { registrationId: b.registrationId, kind: b.kind })
  if (!isDeepStrictEqual(copy, value) || value.local_date !== b.localDate) return invalid()
  const r = value.registration
  if (r.kind === 'meal') {
    if (
      r.meal_kind !== b.mealKind ||
      !isDeepStrictEqual([...r.items.map((x) => x.log_id)].sort(), [...b.logIds].sort())
    )
      return invalid()
  } else if (!isDeepStrictEqual(r, b.workout)) return invalid()
  return workoutSnapshot(value)
}
function parsedOriginal(raw: RegistrationFeedbackV3): RegistrationFeedbackV3 {
  const copy = workoutSnapshot(raw),
    head = z
      .object({
        registration_id: uuid,
        registration: z.object({ kind: z.enum(['meal', 'workout']) }).passthrough(),
      })
      .passthrough()
      .parse(copy),
    value = parseRegistrationFeedbackV3(copy, {
      registrationId: head.registration_id,
      kind: head.registration.kind,
    })
  if (!isDeepStrictEqual(copy, value)) return invalid()
  return workoutSnapshot(value)
}
/** Render-only mask. This never becomes a canonical receipt or a new numerical
 * observation; factual consumption and original energy availability survive. */
export function renderHistoricalRegistrationFeedbackV3Sections(
  raw: RegistrationFeedbackV3,
  rawPolicy: ReturnType<typeof projectCurrentClinicalPublicPolicy>,
): readonly FeedbackV3Section[] {
  const saved = parsedOriginal(raw),
    policy = exact(policySchema, rawPolicy),
    display = structuredClone(saved),
    limited = isHistoricalMealFeedbackRestricted(policy),
    pause = policy.pause_weight_loss_guidance,
    incomplete = policy.assessment !== 'complete'
  if (limited) {
    display.education = { status: 'unavailable' }
    if (incomplete) display.guidance = 'unavailable'
    if (pause) {
      display.guidance = 'paused'
      display.education = prepareRegistrationFeedbackV3({
        registrationId: saved.registration_id,
        localDate: saved.local_date,
        locale: saved.locale,
        registration: saved.registration,
        officialDay: null,
        policy,
        preferencesKnown: false,
      }).education
    }
    const day = display.day
    if (day) {
      if (incomplete || pause || policy.hide.objective) day.current_protocol = null
      if (incomplete || pause || policy.hide.calories) {
        day.targets.calories_kcal = null
        day.calorie_percentage = null
      }
      if (incomplete || pause || policy.hide.protein) {
        day.targets.protein_g = null
        day.protein_percentage = null
      }
      if (
        incomplete ||
        pause ||
        policy.hide.balance ||
        policy.hide.budget ||
        day.targets.calories_kcal === null
      ) {
        day.remaining_food_kcal = null
        day.food_excess_kcal = null
      }
    }
    if (pause || policy.hide.block || policy.hide.objective) display.block = { status: 'protected' }
    else if (incomplete) display.block = { status: 'unavailable' }
  }
  const en = saved.locale === 'en'
  return workoutSnapshot(
    renderRegistrationFeedbackV3(display).map((section) => {
      if (section.key === 'day')
        return {
          ...section,
          text: `${en ? 'At the time of this registration' : 'No momento deste registro'} (${saved.local_date}):\n${section.text}`,
        }
      if (section.key === 'block') {
        const text =
          display.block.status === 'not_applicable'
            ? en
              ? 'The consolidated block did not apply to the objective at this registration.'
              : 'O bloco consolidado não se aplicava ao objetivo no momento deste registro.'
            : section.text
        return {
          ...section,
          text: `${limited ? (en ? 'Historical progress under current guidance' : 'Progresso histórico sob as orientações atuais') : en ? 'Historical consolidated progress' : 'Progresso consolidado no momento do registro'}:\n${text}`,
        }
      }
      if (section.key === 'education' && !limited && saved.education.status === 'available')
        return {
          ...section,
          text: `${en ? 'Educational comment at the time of registration' : 'Comentário educativo no momento do registro'}:\n${section.text}`,
        }
      return section
    }),
  )
}
const sectionSchema = z
  .object({
    key: z.enum(['saved', 'items', 'summary', 'day', 'block', 'education']),
    text: z
      .string()
      .min(1)
      .max(64000)
      .refine((v) => v.trim().length > 0),
  })
  .strict()
const wireSchema = z
  .object({
    schema: z.literal('conversation.feedback-presentation.v2'),
    mode: z.literal('historical'),
    assistant: z.literal('Flow AI'),
    original: z
      .object({
        schema: z.literal('registration.feedback.v3'),
        registration_id: uuid,
        kind: z.enum(['meal', 'workout']),
        local_date: z.string().date(),
      })
      .strict(),
    status: z.literal('available'),
    format: z.literal('sections'),
    recorded: required,
    sections: z.array(sectionSchema).length(6),
    current_policy: policySchema,
    provenance: z.object({ epoch: uuid, command_id: uuid, observed_at: workoutClock }).strict(),
  })
  .strict()
/** Private server parser additionally proves literal sections against the
 * immutable canonical. Native still requires trusted transport/current binding. */
export function parseConversationFeedbackPresentationV2(
  raw: unknown,
  input: ConversationFeedbackPresentationV2Input & { readonly canonical: unknown },
): ConversationFeedbackPresentationV2 {
  const b = bind(input),
    saved = original(input.canonical, b),
    value = exact(wireSchema, raw),
    p = value.provenance
  if (
    Buffer.byteLength(JSON.stringify(value), 'utf8') > 200000 ||
    value.original.registration_id !== b.registrationId ||
    value.original.local_date !== b.localDate ||
    value.original.kind !== b.kind ||
    p.command_id !== b.commandId ||
    p.epoch !== b.epoch ||
    p.observed_at !== value.current_policy.observed_at ||
    conversationJournalInstant(p.observed_at) < conversationJournalInstant(b.effectAt)
  )
    return invalid()
  const recorded = parseFeedbackV3Registration(value.recorded)
  if (
    !isDeepStrictEqual(recorded, value.recorded) ||
    !isDeepStrictEqual(recorded, saved.registration) ||
    !isDeepStrictEqual(
      value.sections,
      renderHistoricalRegistrationFeedbackV3Sections(saved, value.current_policy),
    )
  )
    return invalid()
  return workoutSnapshot({ ...value, recorded })
}
export interface ConversationFeedbackPresentationV2OriginalReader {
  /** One immutable, owned canonical receipt read only. The adapter must not
   * ensure, capture, seal, calculate, admit or hide multiple physical reads.
   * K owns the concrete store integration after its whole increment merges. */
  readOriginal(
    input: Readonly<{
      auth: MobileAuthContext
      proof: ConversationFeedbackPresentationV2Proof
      identity: Readonly<{
        userId: string
        registrationId: string
        kind: 'meal' | 'workout'
        commandId: string
        inputHash: string
        epoch: string
      }>
    }>,
  ): Promise<unknown>
}
export interface ConversationFeedbackPresentationV2Dependencies
  extends ConversationCurrentScopeDependencies {
  readonly original: ConversationFeedbackPresentationV2OriginalReader
}
export function createConversationFeedbackPresentationV2Service(
  db: ServiceClient,
  dependencies: ConversationFeedbackPresentationV2Dependencies,
) {
  const read = dependencies.original.readOriginal.bind(dependencies.original),
    observerDependencies: ConversationCurrentScopeDependencies = {
      ...(dependencies.auth
        ? {
            auth: Object.freeze({
              verifyAccessToken: dependencies.auth.verifyAccessToken.bind(dependencies.auth),
              loadPatient: dependencies.auth.loadPatient.bind(dependencies.auth),
              isAdmin: dependencies.auth.isAdmin.bind(dependencies.auth),
            }),
          }
        : {}),
      ...(dependencies.clinical
        ? {
            clinical: Object.freeze({
              capture: dependencies.clinical.capture.bind(dependencies.clinical),
            }),
          }
        : {}),
    }
  return Object.freeze({
    async readHistorical(
      input: ConversationFeedbackPresentationV2Input,
    ): Promise<ConversationFeedbackPresentationV2 | null> {
      try {
        const b = bind(input),
          scope = createConversationCurrentScope(
            db,
            b.who,
            {
              authUserId: b.who.authUserId,
              ownerId: b.owner,
              epoch: b.epoch,
              commandId: b.commandId,
              inputHash: b.inputHash,
            },
            observerDependencies,
          ),
          before = await scope.observe()
        if (conversationJournalInstant(before.observed_at) < conversationJournalInstant(b.effectAt))
          return null
        let raw: unknown,
          failed = false
        try {
          // Pin transport data before the post-scope await can invoke callbacks.
          raw = workoutSnapshot(
            await read(
              workoutSnapshot({
                auth: b.who,
                proof: b.proof,
                identity: {
                  userId: b.owner,
                  registrationId: b.registrationId,
                  kind: b.kind,
                  commandId: b.commandId,
                  inputHash: b.inputHash,
                  epoch: b.epoch,
                },
              }),
            ),
          )
        } catch {
          failed = true
        }
        const after = await scope.observe()
        if (failed || currentClinicalReadBinding(before) !== currentClinicalReadBinding(after))
          return null
        const saved = original(raw, b),
          policy = projectCurrentClinicalPublicPolicy(after)
        if (!policy.recording_allowed) return null
        return parseConversationFeedbackPresentationV2(
          {
            schema: 'conversation.feedback-presentation.v2',
            mode: 'historical',
            assistant: 'Flow AI',
            original: {
              schema: 'registration.feedback.v3',
              registration_id: b.registrationId,
              kind: b.kind,
              local_date: b.localDate,
            },
            status: 'available',
            format: 'sections',
            recorded: saved.registration,
            sections: renderHistoricalRegistrationFeedbackV3Sections(saved, policy),
            current_policy: policy,
            provenance: { epoch: b.epoch, command_id: b.commandId, observed_at: after.observed_at },
          },
          { auth: b.who, proof: b.proof, canonical: saved },
        )
      } catch {
        return null
      }
    },
  })
}
