/** Neutral routing data only. Neither decoding, model choice nor a sealed
 * selection establishes Auth or proves a performed/consumed domain fact. */
import { isDeepStrictEqual } from 'node:util'
import { getLocalDateString } from '@mpp/agent'
import { z } from 'zod'
import {
  bindConversationCommand,
  type ConversationMealCommand,
} from './conversation-command-contracts'
import {
  type ConversationIntakeMediaProjection,
  conversationIntakeMediaProjectionSchema,
} from './conversation-intake-media-origin'
import { detachConversationContinuationReadJson } from './conversation-meal-continuation-read-contracts'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import {
  bindConversationWorkoutCommand,
  type ConversationWorkoutCommand,
  workoutClock,
  workoutDigest,
  workoutHash,
  workoutText,
  workoutUUID,
} from './conversation-workout-contracts'

export const conversationIntakeSchema = z
  .object({
    intake_protocol: z.literal('conversation.intake.v1'),
    intake_id: workoutUUID,
    source: z.discriminatedUnion('channel', [
      z.object({ channel: z.literal('text'), text: workoutText(2000) }).strict(),
      z
        .object({
          channel: z.literal('media'),
          media_asset_id: workoutUUID,
          user_action: z.literal('report_actual_record'),
          caption: workoutText(1000).optional(),
        })
        .strict(),
    ]),
    meal_type_hint: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']).optional(),
  })
  .strict()
export type ConversationIntake = z.infer<typeof conversationIntakeSchema>
export interface BoundConversationIntake {
  readonly ownerId: string
  readonly intakeId: string
  readonly inputHash: string
  readonly input: Readonly<ConversationIntake>
}
export interface ConversationIntakeIdentity {
  readonly ownerId: string
  readonly intakeId: string
  readonly inputHash: string
  readonly epoch: string
}
export const conversationIntakeBindingSchema = z
  .object({
    owner_id: workoutUUID,
    intake_id: workoutUUID,
    input_hash: workoutHash,
    epoch: workoutUUID,
    admitted_at: workoutClock,
  })
  .strict()
export type ConversationIntakeBinding = Readonly<z.infer<typeof conversationIntakeBindingSchema>>
export const conversationIntakeRoutingDecisionSchema = z
  .object({
    schema: z.literal('conversation.intake-routing.v1'),
    kind: z.enum(['meal.report', 'workout.report', 'not_reported', 'clarification_required']),
    reason: z.string().regex(/^[a-z_]{1,80}$/u),
    question: z
      .object({ field: z.enum(['record_kind', 'description']), text: workoutText(300) })
      .strict()
      .optional(),
  })
  .strict()
  .refine((d) => (d.kind === 'clarification_required') === (d.question !== undefined))
export type ConversationIntakeRoutingDecision = Readonly<
  z.infer<typeof conversationIntakeRoutingDecisionSchema>
>
const mediaSchema = z
  .object({
    asset_id: workoutUUID,
    owner_id: workoutUUID,
    kind: z.enum(['meal_photo', 'audio_note', 'gym_photo', 'conversation_photo']),
    status: z.literal('processed'),
    processed_at: workoutClock,
    updated_at: workoutClock,
    context_text: z.string().nullable(),
    processing_result: z.record(z.unknown()),
  })
  .strict()
const contextSchema = z
  .object({
    schema: z.literal('conversation.intake-source.v1'),
    owner_id: workoutUUID,
    intake_id: workoutUUID,
    input_hash: workoutHash,
    epoch: workoutUUID,
    source_input: conversationIntakeSchema,
    admitted_at: workoutClock,
    captured_at: workoutClock,
    time_zone: z.string().min(1).max(100),
    local_date: z.string().date(),
    media: mediaSchema.nullable(),
  })
  .strict()
export type ConversationIntakeContext = Readonly<z.infer<typeof contextSchema>>
export interface CapturedConversationIntakeSource {
  readonly intake: BoundConversationIntake
  readonly binding: ConversationIntakeBinding
  readonly sourceHash: string
  readonly context: ConversationIntakeContext
}
const selectedCommandSchema = z
  .object({
    kind: z.enum(['meal.report', 'workout.report']),
    owner_id: workoutUUID,
    command_id: workoutUUID,
    input_hash: workoutHash,
    epoch: workoutUUID,
    admitted_at: workoutClock,
    input: z.unknown(),
  })
  .strict()
export interface ConversationIntakeSelection {
  readonly schema: 'conversation.intake-selection.v1' | 'conversation.intake-selection.v2'
  readonly media_projection?: ConversationIntakeMediaProjection
  readonly intake: ConversationIntakeBinding
  readonly source_hash: string
  readonly decision_hash: string
  readonly decision: ConversationIntakeRoutingDecision
  readonly selected_at: string
  readonly command: Readonly<{
    kind: 'meal.report' | 'workout.report'
    owner_id: string
    command_id: string
    input_hash: string
    epoch: string
    admitted_at: string
    input: ConversationMealCommand | ConversationWorkoutCommand
  }> | null
}
const selectionSchema = z
  .object({
    schema: z.literal('conversation.intake-selection.v1'),
    intake: conversationIntakeBindingSchema,
    source_hash: workoutHash,
    decision_hash: workoutHash,
    decision: conversationIntakeRoutingDecisionSchema,
    selected_at: workoutClock,
    command: selectedCommandSchema.nullable(),
  })
  .strict()
const executionSelectionSchema = z.union([
  selectionSchema,
  selectionSchema
    .extend({
      schema: z.literal('conversation.intake-selection.v2'),
      media_projection: conversationIntakeMediaProjectionSchema,
    })
    .strict(),
])
export function intakeSnapshot<T>(raw: T): T {
  return detachConversationContinuationReadJson(raw) as T
}
function require(value: boolean): asserts value {
  if (!value) throw new Error('Invalid immutable conversation intake')
}
export function bindConversationIntake(
  owner: string,
  key: string | null,
  raw: unknown,
): BoundConversationIntake {
  const ownerId = workoutUUID.parse(owner),
    copy = intakeSnapshot(raw),
    input = conversationIntakeSchema.parse(copy)
  require(isDeepStrictEqual(input, copy) && key === `cintake1:${input.intake_id}`)
  return intakeSnapshot({
    ownerId,
    intakeId: input.intake_id,
    inputHash: workoutDigest(input),
    input,
  })
}
export function pinConversationIntake(raw: BoundConversationIntake): BoundConversationIntake {
  const copy = intakeSnapshot(raw),
    bound = bindConversationIntake(copy.ownerId, `cintake1:${copy.intakeId}`, copy.input)
  require(isDeepStrictEqual(copy, bound))
  return bound
}
export function parseConversationIntakeBinding(
  original: BoundConversationIntake,
  raw: unknown,
): ConversationIntakeBinding {
  const bound = pinConversationIntake(original),
    value = conversationIntakeBindingSchema.parse(intakeSnapshot(raw))
  require(
    value.owner_id === bound.ownerId &&
      value.intake_id === bound.intakeId &&
      value.input_hash === bound.inputHash,
  )
  return intakeSnapshot(value)
}
export function parseConversationIntakeRoutingDecision(
  raw: unknown,
): ConversationIntakeRoutingDecision {
  return intakeSnapshot(conversationIntakeRoutingDecisionSchema.parse(intakeSnapshot(raw)))
}
export function parseConversationIntakeSource(
  original: BoundConversationIntake,
  rawBinding: ConversationIntakeBinding,
  raw: unknown,
): CapturedConversationIntakeSource {
  const intake = pinConversationIntake(original),
    binding = parseConversationIntakeBinding(intake, rawBinding),
    envelope = z
      .object({ source_hash: workoutHash, context: contextSchema })
      .strict()
      .parse(intakeSnapshot(raw)),
    c = envelope.context,
    at = conversationJournalInstant
  require(Buffer.byteLength(JSON.stringify(c), 'utf8') <= 2097152)
  require(
    c.owner_id === binding.owner_id &&
      c.intake_id === binding.intake_id &&
      c.input_hash === binding.input_hash &&
      c.epoch === binding.epoch,
  )
  require(
    isDeepStrictEqual(c.source_input, intake.input) &&
      at(c.admitted_at) === at(binding.admitted_at) &&
      at(c.captured_at) >= at(binding.admitted_at),
  )
  // Validate the timezone before using the existing official local-date helper.
  new Intl.DateTimeFormat('en', { timeZone: c.time_zone }).format(new Date(0))
  require(
    getLocalDateString(c.time_zone, new Date(c.admitted_at)) === c.local_date &&
      getLocalDateString(c.time_zone, new Date(c.captured_at)) === c.local_date,
  )
  if (intake.input.source.channel === 'text') require(c.media === null)
  else {
    const m = c.media
    require(
      m !== null &&
        m.asset_id === intake.input.source.media_asset_id &&
        m.owner_id === intake.ownerId,
    )
    require(at(m.processed_at) <= at(c.captured_at) && at(m.updated_at) <= at(c.captured_at))
    require(Buffer.byteLength(JSON.stringify(m.processing_result), 'utf8') <= 1048576)
  }
  return intakeSnapshot({ intake, binding, sourceHash: envelope.source_hash, context: c })
}
export function parseConversationIntakeSelection(
  original: BoundConversationIntake,
  rawBinding: ConversationIntakeBinding,
  raw: unknown,
): ConversationIntakeSelection {
  const bound = pinConversationIntake(original),
    binding = parseConversationIntakeBinding(bound, rawBinding),
    value = executionSelectionSchema.parse(intakeSnapshot(raw)),
    at = conversationJournalInstant,
    actualBinding = parseConversationIntakeBinding(bound, value.intake)
  require(
    actualBinding.epoch === binding.epoch &&
      at(actualBinding.admitted_at) === at(binding.admitted_at),
  )
  require(
    at(value.selected_at) >= at(binding.admitted_at) &&
      value.decision_hash === workoutDigest(value.decision),
  )
  const decision = value.decision
  if (decision.kind === 'not_reported' || decision.kind === 'clarification_required') {
    require(value.schema === 'conversation.intake-selection.v1' && value.command === null)
    return intakeSnapshot({ ...value, command: null })
  }
  const c = value.command
  require(c !== null)
  require(
    c.kind === decision.kind &&
      c.owner_id === bound.ownerId &&
      c.epoch === binding.epoch &&
      c.command_id !== bound.intakeId,
  )
  require(
    at(c.admitted_at) >= at(binding.admitted_at) && at(c.admitted_at) <= at(value.selected_at),
  )
  const typed =
    c.kind === 'meal.report'
      ? bindConversationCommand(c.owner_id, `cmsg1:${c.command_id}`, c.input)
      : bindConversationWorkoutCommand(c.owner_id, `cmsg1:${c.command_id}`, c.input)
  require(
    typed.commandId === c.command_id &&
      typed.inputHash === c.input_hash &&
      typed.command.kind === c.kind,
  )
  if (bound.input.source.channel === 'text') {
    require(
      value.schema === 'conversation.intake-selection.v1' &&
        typed.command.source.channel === 'text' &&
        typed.command.source.text === bound.input.source.text,
    )
  } else {
    require(
      value.schema === 'conversation.intake-selection.v2' &&
        'media_projection' in value &&
        'intake_origin' in typed.command &&
        typed.command.source.channel === 'media' &&
        isDeepStrictEqual(typed.command.source, bound.input.source),
    )
    const p = value.media_projection,
      o = typed.command.intake_origin
    require(
      isDeepStrictEqual(o, p.origin) &&
        o.intake_id === bound.intakeId &&
        o.input_hash === bound.inputHash &&
        o.source_hash === value.source_hash &&
        o.decision_hash === value.decision_hash &&
        o.epoch === binding.epoch &&
        p.child_input_hash === typed.inputHash &&
        p.media.owner_id === bound.ownerId &&
        p.media.asset_id === bound.input.source.media_asset_id &&
        at(p.media.processed_at) <= at(value.selected_at) &&
        at(p.media.updated_at) <= at(value.selected_at) &&
        (typed.command.kind === 'meal.report'
          ? ['meal_photo', 'audio_note', 'conversation_photo'].includes(p.media.kind)
          : ['gym_photo', 'audio_note', 'conversation_photo'].includes(p.media.kind)),
    )
  }
  if (typed.command.kind === 'meal.report')
    require(typed.command.meal_type === bound.input.meal_type_hint)
  return intakeSnapshot({ ...value, command: { ...c, input: typed.command } })
}
