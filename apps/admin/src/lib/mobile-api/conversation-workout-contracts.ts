/** Dormant private workout contracts. Parsing is not SQL authority. No route,
 * default client, patient bootstrap, workout writer or UI-v1 proposal exists. */
import { createHash } from 'node:crypto'
import { isDeepStrictEqual } from 'node:util'
import { getLocalDateString } from '@mpp/agent'
import { z } from 'zod'
import {
  assertConversationIntakeMediaCapture,
  conversationIntakeMediaOriginSchema,
  conversationIntakeMediaProjectionSchema,
  conversationIntakeMediaSourceSchema,
} from './conversation-intake-media-origin'
import { detachConversationContinuationReadJson } from './conversation-meal-continuation-read-contracts'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { type CurrentClinicalSnapshot, readCurrentClinicalState } from './current-clinical-state'

export const workoutUUID = z
  .string()
  .uuid()
  .regex(/^[a-f0-9-]+$/u)
export const workoutHash = z.string().regex(/^[a-f0-9]{64}$/u)
export const workoutClock = z
  .string()
  .datetime({ offset: true })
  .refine((v) => {
    try {
      conversationJournalInstant(v)
      return true
    } catch {
      return false
    }
  })
export const workoutText = (max: number) =>
  z
    .string()
    .min(1)
    .max(max)
    .refine(
      (v) =>
        v.trim().length > 0 &&
        !Array.from(v).some((c) => {
          const code = c.charCodeAt(0)
          return (code < 32 && ![9, 10, 13].includes(code)) || code === 127
        }),
    )
export const conversationWorkoutCommandSchema = z
  .object({
    command_protocol: z.literal('conversation.command.v1'),
    command_id: workoutUUID,
    kind: z.literal('workout.report'),
    source: z.discriminatedUnion('channel', [
      z.object({ channel: z.literal('text'), text: workoutText(2000) }).strict(),
      z
        .object({
          channel: z.literal('media'),
          media_asset_id: workoutUUID,
          user_action: z.literal('register_performed_workout'),
          caption: workoutText(1000).optional(),
        })
        .strict(),
    ]),
  })
  .strict()
export const conversationWorkoutExecutionCommandSchema = z.union([
  conversationWorkoutCommandSchema,
  z
    .object({
      command_protocol: z.literal('conversation.command.v1'),
      command_id: workoutUUID,
      kind: z.literal('workout.report'),
      source: conversationIntakeMediaSourceSchema,
      intake_origin: conversationIntakeMediaOriginSchema,
    })
    .strict(),
])
export type ConversationWorkoutCommand = z.infer<typeof conversationWorkoutExecutionCommandSchema>
export interface BoundConversationWorkoutCommand {
  readonly ownerId: string
  readonly commandId: string
  readonly inputHash: string
  readonly command: Readonly<ConversationWorkoutCommand>
}
export function workoutCanonical(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(workoutCanonical).join(',')}]`
  return `{${Object.entries(value)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${JSON.stringify(k)}:${workoutCanonical(v)}`)
    .join(',')}}`
}
export const workoutDigest = (value: unknown) =>
  createHash('sha256').update(workoutCanonical(value)).digest('hex')
export function workoutSnapshot<T>(value: T): T {
  return freezeInterpretation(detachConversationContinuationReadJson(value) as T)
}
export function bindConversationWorkoutCommand(
  ownerId: string,
  key: string | null,
  raw: unknown,
): BoundConversationWorkoutCommand {
  const owner = workoutUUID.parse(ownerId),
    copy = workoutSnapshot(raw),
    command = conversationWorkoutExecutionCommandSchema.parse(copy)
  if (!isDeepStrictEqual(command, copy) || key !== `cmsg1:${command.command_id}`)
    throw new Error('Invalid original workout identity')
  return workoutSnapshot({
    ownerId: owner,
    commandId: command.command_id,
    inputHash: workoutDigest(command),
    command,
  })
}
export function pinConversationWorkoutCommand(raw: BoundConversationWorkoutCommand) {
  const copy = workoutSnapshot(raw),
    actual = bindConversationWorkoutCommand(copy.ownerId, `cmsg1:${copy.commandId}`, copy.command)
  if (!isDeepStrictEqual(copy, actual)) throw new Error('Changed workout binding')
  return actual
}
const mediaSchema = z
  .object({
    asset_id: workoutUUID,
    owner_id: workoutUUID,
    kind: z.enum(['audio_note', 'gym_photo', 'conversation_photo']),
    status: z.literal('processed'),
    processed_at: workoutClock,
    updated_at: workoutClock,
    context_text: z.string().max(2000).nullable(),
    processing_result: z.record(z.unknown()),
  })
  .strict()
const legacyContextSchema = z
  .object({
    schema: z.literal('conversation.workout-source.v1'),
    owner_id: workoutUUID,
    command_id: workoutUUID,
    input_hash: workoutHash,
    epoch: workoutUUID,
    source_input: conversationWorkoutCommandSchema,
    admitted_at: workoutClock,
    captured_at: workoutClock,
    clinical: z.unknown(),
    day_closed: z.literal(false),
    media: mediaSchema.nullable(),
    catalogue: z
      .array(
        z
          .object({
            id: workoutUUID,
            slug: workoutText(200),
            display_name: workoutText(200),
            is_active: z.literal(true),
            updated_at: workoutClock,
            category: z.enum(['musculacao', 'cardio', 'esporte', 'mobilidade']).optional(),
            kcal_per_min: z.number().finite().nonnegative().nullable().optional(),
          })
          .strict(),
      )
      .max(2048),
  })
  .strict()
const contextSchema = z.union([
  legacyContextSchema,
  legacyContextSchema
    .extend({
      schema: z.literal('conversation.workout-source.v2'),
      source_input: conversationWorkoutExecutionCommandSchema,
      intake_projection: conversationIntakeMediaProjectionSchema,
    })
    .strict(),
])
export type WorkoutSourceUnit =
  | 'command_text'
  | 'media_caption'
  | 'media_context'
  | 'media_transcript'
export interface CapturedConversationWorkoutSource {
  readonly command: BoundConversationWorkoutCommand
  readonly sourceHash: string
  readonly epoch: string
  readonly admittedAt: string
  readonly capturedAt: string
  readonly localDate: string
  readonly clinical: CurrentClinicalSnapshot
  readonly context: Readonly<z.infer<typeof contextSchema>>
  readonly sources: readonly { readonly unit: WorkoutSourceUnit; readonly text: string }[]
}
/** Only a backend capture transport may supply raw. A model/client cannot turn
 * this decoder into admission, proof of media ownership or a writer capability. */
export function parseConversationWorkoutSource(
  rawCommand: BoundConversationWorkoutCommand,
  raw: unknown,
): CapturedConversationWorkoutSource {
  const command = pinConversationWorkoutCommand(rawCommand),
    copy = workoutSnapshot(raw)
  const envelope = z
    .object({ source_hash: workoutHash, context: contextSchema })
    .strict()
    .parse(copy)
  if (!isDeepStrictEqual(copy, envelope)) throw new Error('Changed workout source')
  const c = envelope.context,
    clinical = readCurrentClinicalState(c.clinical, command.ownerId)
  const at = conversationJournalInstant,
    localDate = getLocalDateString(clinical.timezone, new Date(c.admitted_at))
  if (
    c.owner_id !== command.ownerId ||
    c.command_id !== command.commandId ||
    c.input_hash !== command.inputHash ||
    !isDeepStrictEqual(c.source_input, command.command) ||
    c.epoch !== clinical.epoch ||
    clinical.mode !== 'profile' ||
    localDate !== clinical.date ||
    at(c.captured_at) < at(c.admitted_at) ||
    at(clinical.observed_at) !== at(c.captured_at) ||
    new Set(c.catalogue.map((r) => r.id)).size !== c.catalogue.length ||
    new Set(c.catalogue.map((r) => r.slug)).size !== c.catalogue.length ||
    c.catalogue.some((r) => at(r.updated_at) > at(c.captured_at))
  )
    throw new Error('Workout source identity unavailable')
  if ('intake_origin' in command.command) assertConversationIntakeMediaCapture(command, c)
  else if (c.schema !== 'conversation.workout-source.v1' || c.media?.kind === 'conversation_photo')
    throw new Error('Changed workout source version')
  const sources: { unit: WorkoutSourceUnit; text: string }[] = []
  if (command.command.source.channel === 'text') {
    if (c.media !== null) throw new Error('Unexpected workout media')
    sources.push({ unit: 'command_text', text: command.command.source.text })
  } else {
    const m = c.media,
      s = command.command.source
    if (
      !m ||
      m.asset_id !== s.media_asset_id ||
      m.owner_id !== command.ownerId ||
      at(m.processed_at) > at(c.captured_at) ||
      at(m.updated_at) > at(c.captured_at) ||
      Buffer.byteLength(JSON.stringify(m.processing_result), 'utf8') > 1048576
    )
      throw new Error('Workout media unavailable')
    if (
      c.schema === 'conversation.workout-source.v1' &&
      s.caption &&
      m.context_text?.trim() &&
      s.caption !== m.context_text
    )
      throw new Error('Conflicting workout media captions')
    const caption =
      c.schema === 'conversation.workout-source.v2' ? s.caption : (s.caption ?? m.context_text)
    if (caption?.trim())
      sources.push({ unit: 'media_caption', text: workoutText(2000).parse(caption) })
    if (c.schema === 'conversation.workout-source.v2' && m.context_text?.trim())
      sources.push({ unit: 'media_context', text: workoutText(2000).parse(m.context_text) })
    if (m.kind === 'audio_note')
      sources.push({
        unit: 'media_transcript',
        text: workoutText(2000).parse(m.processing_result.text),
      })
    // Existing gym_photo processing describes equipment, not a performed activity.
    // Its pixels or model-suggested kcal never become a performed source.
  }
  return workoutSnapshot({
    command,
    sourceHash: envelope.source_hash,
    epoch: c.epoch,
    admittedAt: c.admitted_at,
    capturedAt: c.captured_at,
    localDate,
    clinical,
    context: c,
    sources,
  })
}
