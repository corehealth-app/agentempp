/** Shape is not performed/auth authority. Only service-only capture plus fresh
 * scope checks and SQL recapture/CAS authenticate these private observations. */
import { isDeepStrictEqual } from 'node:util'
import { getLocalDateString } from '@mpp/agent'
import type { RegistrationFeedback } from '@mpp/agent/registration-feedback'
import {
  parseRegistrationFeedbackV2,
  type RegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import {
  type FeedbackV3Registration,
  parseFeedbackV3Registration,
  parseRegistrationFeedbackV3,
  type RegistrationFeedbackV3,
} from '@mpp/agent/registration-feedback-v3'
import { exerciseEnergyComplete } from '@mpp/core'
import type { Json } from '@mpp/db'
import { z } from 'zod'
import { parseConversationMealContinuationFeedbackBinding } from './conversation-meal-continuation-read-contracts'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
} from './conversation-workout-contracts'
import { parseConversationWorkoutEffect } from './conversation-workout-writer'
import { type CurrentClinicalSnapshot, readCurrentClinicalState } from './current-clinical-state'
import { parseRegistrationFeedback } from './registration-feedback-receipt'
import { parseFeedbackV2Capture } from './registration-feedback-v2-store'

const uuid = z.string().uuid(),
  amount = z.number().finite().nonnegative().max(Number.MAX_SAFE_INTEGER)
export const feedbackV3Json: z.ZodType<Json> = z.lazy(() =>
  z.union([
    z.null(),
    z.boolean(),
    z.number().finite(),
    z.string(),
    z.array(feedbackV3Json),
    z.record(feedbackV3Json),
  ]),
)
export const feedbackV3IdentitySchema = z
  .object({
    userId: uuid,
    registrationId: uuid,
    kind: z.enum(['meal', 'workout']),
    origin: z.enum(['pending_registration', 'conversation_workout']),
  })
  .strict()
export type FeedbackV3Identity = Readonly<z.infer<typeof feedbackV3IdentitySchema>>
const sourceSchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('pending_registration'),
      capture: feedbackV3Json,
      command: z
        .object({
          command_id: uuid,
          epoch: uuid,
          input_hash: z.string().regex(/^[a-f0-9]{64}$/u),
          receipt: feedbackV3Json,
          continuation: feedbackV3Json,
        })
        .strict()
        .nullable(),
    })
    .strict(),
  z
    .object({
      kind: z.literal('conversation_workout'),
      input: feedbackV3Json,
      captured: feedbackV3Json,
      prepared: feedbackV3Json,
      effect: feedbackV3Json,
      feedback_context: z.record(feedbackV3Json),
    })
    .strict(),
])
const captureSchema = z
  .object({
    version: z.literal(3),
    origin: z.enum(['pending_registration', 'conversation_workout']),
    user_id: uuid,
    registration_id: uuid,
    event_hash: z.string().regex(/^[a-f0-9]{64}$/u),
    local_date: z.string().date(),
    record: feedbackV3Json,
    source: sourceSchema,
    logs: z.array(z.record(feedbackV3Json)).min(1).max(30),
    snapshot: z.record(feedbackV3Json),
    day_workouts: z.array(z.record(feedbackV3Json)).max(10000).nullable(),
    progress: z.record(feedbackV3Json).nullable(),
    clinical: z.record(feedbackV3Json),
  })
  .strict()
const snapshotSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    date: z.string().date(),
    updated_at: z.string().datetime({ offset: true }),
    exercise_calories: amount.nullable(),
    exercise_energy_complete: z.boolean().optional(),
  })
  .passthrough()
const dayWorkoutSchema = z
  .object({ id: uuid, user_id: uuid, snapshot_id: uuid, estimated_kcal: amount.nullable() })
  .passthrough()
export type FeedbackV3SourceContext = z.infer<typeof captureSchema>
export interface FeedbackV3Observation {
  readonly context: Readonly<FeedbackV3SourceContext>
  readonly registration: FeedbackV3Registration
  readonly localDate: string
  readonly logIds: readonly string[]
  readonly energyComplete: boolean | null
  readonly energyUnavailableReason: 'unknown_workout_energy' | 'source_unavailable' | null
  readonly clinical: CurrentClinicalSnapshot
}
export type CanonicalRegistrationFeedback =
  | RegistrationFeedback
  | RegistrationFeedbackV2
  | RegistrationFeedbackV3
function invalid(): never {
  throw new Error('Invalid registration feedback v3 source or receipt')
}
export function freezeFeedbackV3<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freezeFeedbackV3(child)
    Object.freeze(value)
  }
  return value
}
export function pinFeedbackV3Identity(raw: FeedbackV3Identity): FeedbackV3Identity {
  return freezeFeedbackV3(feedbackV3IdentitySchema.parse(structuredClone(raw)))
}
export function parseCanonicalRegistrationFeedback(
  raw: unknown,
  rawIdentity: FeedbackV3Identity,
): CanonicalRegistrationFeedback {
  const i = pinFeedbackV3Identity(rawIdentity),
    value = structuredClone(raw)
  const schema = z.object({ schema: z.string() }).passthrough().parse(value).schema
  const identity = { userId: i.userId, registrationId: i.registrationId, kind: i.kind }
  if (schema === 'registration.feedback.v3')
    return freezeFeedbackV3(parseRegistrationFeedbackV3(value, identity))
  if (i.origin !== 'pending_registration') return invalid()
  if (schema === 'registration.feedback.v2')
    return freezeFeedbackV3(parseRegistrationFeedbackV2(value, identity))
  if (schema === 'registration.feedback.v1')
    return freezeFeedbackV3(parseRegistrationFeedback(value, identity))
  return invalid()
}
export function parseFeedbackV3Capture(
  raw: unknown,
  rawIdentity: FeedbackV3Identity,
): FeedbackV3Observation {
  const who = pinFeedbackV3Identity(rawIdentity),
    c = captureSchema.parse(structuredClone(raw))
  if (
    JSON.stringify(c).length > 1048576 ||
    c.user_id !== who.userId ||
    c.registration_id !== who.registrationId ||
    c.origin !== who.origin ||
    c.source.kind !== who.origin
  )
    invalid()
  const registration = parseFeedbackV3Registration(c.record)
  if (registration.kind !== who.kind) invalid()
  const frozen = c.source.kind === 'conversation_workout' || c.source.command !== null
  if (c.source.kind === 'pending_registration') {
    const original = parseFeedbackV2Capture(c.source.capture, {
      userId: who.userId,
      registrationId: who.registrationId,
      kind: who.kind,
    })
    if (
      !isDeepStrictEqual(registration, original.facts.registration) ||
      c.local_date !== original.facts.localDate
    )
      invalid()
    for (const key of ['logs', 'snapshot', 'progress', 'clinical'] as const)
      if (!isDeepStrictEqual(c[key], original.context[key])) invalid()
    const proposal = original.context.confirmed.proposal
    if (!proposal || typeof proposal !== 'object' || Array.isArray(proposal)) invalid()
    const command = c.source.command
    if (command === null) {
      if (proposal.command_protocol !== undefined || proposal.command_id !== undefined) invalid()
    } else {
      const continuation =
        command.continuation === null
          ? null
          : parseConversationMealContinuationFeedbackBinding(command.continuation)
      if (continuation && !isDeepStrictEqual(continuation.receipt, command.receipt)) invalid()
      const r =
        continuation?.receipt ??
        z
          .object({
            schema: z.literal('conversation.meal-effect.v1'),
            owner_id: uuid,
            command_id: uuid,
            input_hash: z.string().regex(/^[a-f0-9]{64}$/u),
            registration_id: uuid,
            provider_key: z.string(),
            meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']),
            local_date: z.string().date(),
            timezone: z.string().min(1),
            consumed_at: z.string().datetime({ offset: true }),
            log_ids: z.array(uuid).min(1).max(30),
            effect_version: z.string().regex(/^cmeal1:[a-f0-9]{64}$/u),
          })
          .strict()
          .parse(command.receipt)
      if (
        registration.kind !== 'meal' ||
        command.epoch !== original.clinical.epoch ||
        proposal.command_protocol !==
          (continuation ? 'conversation.clarification.v1' : 'conversation.command.v1') ||
        proposal.command_id !== command.command_id ||
        proposal.source_provider_message_id !== r.provider_key ||
        r.owner_id !== who.userId ||
        r.command_id !== command.command_id ||
        r.input_hash !== command.input_hash ||
        r.registration_id !== who.registrationId ||
        r.meal_type !== registration.meal_kind ||
        r.local_date !== c.local_date ||
        getLocalDateString(r.timezone, new Date(r.consumed_at)) !== c.local_date ||
        r.provider_key !==
          (continuation
            ? `conversation.clarification/${who.userId}/${continuation.parentBinding.command_id}`
            : `conversation.meal/${who.userId}/${command.command_id}`) ||
        new Set(r.log_ids).size !== r.log_ids.length ||
        !isDeepStrictEqual([...r.log_ids].sort(), [...original.facts.logIds].sort()) ||
        c.day_workouts !== null
      )
        invalid()
    }
  } else {
    if (
      who.kind !== 'workout' ||
      c.day_workouts !== null ||
      typeof c.snapshot.exercise_energy_complete !== 'boolean' ||
      typeof c.snapshot.exercise_calories !== 'number'
    )
      invalid()
    for (const key of ['logs', 'snapshot', 'progress', 'clinical'] as const)
      if (!isDeepStrictEqual(c[key], c.source.feedback_context[key])) invalid()
    const command = bindConversationWorkoutCommand(
      who.userId,
      `cmsg1:${who.registrationId}`,
      c.source.input,
    )
    if (command.commandId !== who.registrationId) invalid()
    const source = parseConversationWorkoutSource(command, c.source.captured)
    const effect = parseConversationWorkoutEffect(source, c.source.prepared, c.source.effect)
    const expected = {
      kind: 'workout',
      log_id: effect.receipt.workout_id,
      ...effect.receipt.activity,
    }
    if (
      !isDeepStrictEqual(registration, expected) ||
      c.local_date !== effect.receipt.local_date ||
      c.logs.length !== 1
    )
      invalid()
    const saved = c.logs[0]
    if (!saved) invalid()
    for (const [key, value] of Object.entries(effect.original_facts.workout)) {
      if (key === 'performed_at') {
        if (
          typeof saved[key] !== 'string' ||
          conversationJournalInstant(saved[key]) !== conversationJournalInstant(String(value))
        )
          invalid()
      } else if (!isDeepStrictEqual(saved[key], value)) invalid()
    }
    const current = readCurrentClinicalState(c.clinical, who.userId)
    if (current.epoch !== effect.receipt.epoch) invalid()
  }
  const snapshot = snapshotSchema.parse(c.snapshot)
  if (snapshot.user_id !== who.userId || snapshot.date !== c.local_date) invalid()
  const ids = c.logs.map((row) => uuid.parse(row.id))
  if (
    new Set(ids).size !== ids.length ||
    c.logs.some((row) => row.user_id !== who.userId || row.snapshot_id !== snapshot.id)
  )
    invalid()
  const recordIds =
    registration.kind === 'meal'
      ? registration.items.map((item) => item.log_id)
      : [registration.log_id]
  if (recordIds.length !== ids.length || recordIds.some((id) => !ids.includes(id))) invalid()
  if (
    !frozen &&
    (c.day_workouts === null ||
      snapshot.exercise_energy_complete === undefined ||
      snapshot.exercise_calories === null)
  )
    invalid()
  const workouts = (c.day_workouts ?? []).map((row) => dayWorkoutSchema.parse(row))
  if (
    new Set(workouts.map((row) => row.id)).size !== workouts.length ||
    workouts.some((row) => row.user_id !== who.userId || row.snapshot_id !== snapshot.id)
  )
    invalid()
  if (
    !frozen &&
    registration.kind === 'workout' &&
    workouts.filter(
      (row) => row.id === registration.log_id && row.estimated_kcal === registration.estimated_kcal,
    ).length !== 1
  )
    invalid()
  if (c.progress !== null && c.progress.user_id !== who.userId) invalid()
  const clinical = readCurrentClinicalState(c.clinical, who.userId)
  const energyComplete = frozen
    ? snapshot.exercise_energy_complete === undefined || snapshot.exercise_calories === null
      ? null
      : snapshot.exercise_energy_complete
    : exerciseEnergyComplete(workouts, snapshot.exercise_energy_complete)
  return freezeFeedbackV3({
    context: c,
    registration,
    localDate: c.local_date,
    logIds: ids,
    energyComplete,
    energyUnavailableReason:
      energyComplete === null
        ? 'source_unavailable'
        : energyComplete
          ? null
          : 'unknown_workout_energy',
    clinical,
  })
}
