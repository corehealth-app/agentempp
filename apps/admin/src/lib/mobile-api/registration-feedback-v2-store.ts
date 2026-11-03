/** Private backend leaf. Construction is inert; no route, writer or phrase cursor. */
import { isDeepStrictEqual } from 'node:util'
import type { RegistrationFeedback } from '@mpp/agent/registration-feedback'
import {
  parseRegistrationFeedbackV2,
  type RegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { type CurrentClinicalSnapshot, readCurrentClinicalState } from './current-clinical-state'
import {
  parseRegistrationFeedback,
  type RegistrationFeedbackIdentity,
} from './registration-feedback-receipt'
import {
  type FeedbackV2RecordFacts,
  projectRegistrationFeedbackV2Facts,
} from './registration-feedback-v2-facts'

const uuid = z.string().uuid()
const json: z.ZodType<Json> = z.lazy(() =>
  z.union([z.null(), z.boolean(), z.number().finite(), z.string(), z.array(json), z.record(json)]),
)
const captureSchema = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    registration_id: uuid,
    confirmed: z.record(json),
    logs: z.array(z.record(json)).min(1).max(30),
    workout_proof: json,
    snapshot: z.record(json),
    progress: z.record(json).nullable(),
    clinical: z.record(json),
  })
  .strict()
type SourceContext = z.infer<typeof captureSchema>
export interface FeedbackV2Observation {
  readonly context: Readonly<SourceContext>
  readonly facts: FeedbackV2RecordFacts
  readonly clinical: CurrentClinicalSnapshot
}
export type FeedbackV2Read =
  | { action: 'available'; feedback: RegistrationFeedbackV2 }
  | { action: 'legacy'; feedback: RegistrationFeedback }
  | { action: 'absent' | 'event_conflict' }
export type FeedbackV2Commit =
  | { action: 'committed' | 'replay'; feedback: RegistrationFeedbackV2 }
  | { action: 'legacy'; feedback: RegistrationFeedback }
  | { action: 'source_conflict' | 'event_conflict' }
export interface RegistrationFeedbackV2Store {
  readReceipt(identity: RegistrationFeedbackIdentity): Promise<FeedbackV2Read>
  capture(
    identity: RegistrationFeedbackIdentity,
  ): Promise<
    { action: 'available'; observation: FeedbackV2Observation } | { action: 'event_conflict' }
  >
  commit(
    input: RegistrationFeedbackIdentity & {
      observation: FeedbackV2Observation
      feedback: RegistrationFeedbackV2
    },
  ): Promise<FeedbackV2Commit>
}
function invalid(): never {
  throw new Error('Invalid registration feedback v2 source or receipt')
}
function identity(input: RegistrationFeedbackIdentity): RegistrationFeedbackIdentity {
  return z
    .object({ userId: uuid, registrationId: uuid, kind: z.enum(['meal', 'workout']) })
    .strict()
    .parse(input)
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
/** SQL provenance is established by service-only capture and recapture/CAS,
 * never by a JSON shape or a mobile request supplying this private structure. */
export function parseFeedbackV2Capture(
  raw: unknown,
  who: RegistrationFeedbackIdentity,
): FeedbackV2Observation {
  const i = identity(who)
  const c = captureSchema.parse(raw)
  if (
    JSON.stringify(c).length > 1048576 ||
    c.user_id !== i.userId ||
    c.registration_id !== i.registrationId
  )
    invalid()
  const confirmed = z
    .object({
      id: uuid,
      user_id: uuid,
      status: z.literal('confirmed'),
      proposal: z.record(json),
      confirmedWorkoutId: uuid.optional(),
      workout_protocol: z.literal('ui-v1').optional(),
    })
    .strict()
    .parse(c.confirmed)
  let workoutProof: unknown
  if (i.kind === 'meal') {
    if (
      confirmed.proposal.registration_origin !== 'mobile_app' ||
      c.workout_proof !== null ||
      confirmed.workout_protocol !== undefined ||
      confirmed.confirmedWorkoutId !== undefined
    )
      invalid()
  } else if (confirmed.workout_protocol === 'ui-v1') {
    if (
      !c.workout_proof ||
      typeof c.workout_proof !== 'object' ||
      Array.isArray(c.workout_proof) ||
      c.workout_proof.kind !== 'ui-v1'
    )
      invalid()
    workoutProof = c.workout_proof
  } else {
    const direct = z
      .object({ kind: z.literal('direct-key'), operation_key: z.string().min(1), workout_id: uuid })
      .strict()
      .parse(c.workout_proof)
    if (
      confirmed.confirmedWorkoutId !== undefined ||
      direct.operation_key !== confirmed.proposal.source_provider_message_id ||
      direct.workout_id !== c.logs[0]?.id
    )
      invalid()
  }
  const facts = projectRegistrationFeedbackV2Facts({
    ...i,
    confirmed,
    logs: c.logs,
    ...(workoutProof === undefined ? {} : { workoutProof }),
  })
  if (!facts || facts.registration.kind !== i.kind) invalid()
  const snapshot = z.object({ id: uuid, user_id: uuid, date: z.string().date() }).parse(c.snapshot)
  if (
    snapshot.user_id !== i.userId ||
    snapshot.date !== facts.localDate ||
    c.logs.some((row) => row.snapshot_id !== snapshot.id)
  )
    invalid()
  if (c.progress !== null && c.progress.user_id !== i.userId) invalid()
  const clinical = readCurrentClinicalState(c.clinical, i.userId)
  return freeze({ context: c, facts, clinical })
}
function envelope(raw: unknown) {
  const value = z.object({ data: z.unknown(), error: z.unknown() }).parse(raw)
  if (value.error !== null) throw new Error('Unable to access registration feedback v2')
  return value.data
}
const empty = [
  z.object({ action: z.literal('absent') }).strict(),
  z.object({ action: z.literal('event_conflict') }).strict(),
] as const
const legacy = z.object({ action: z.literal('legacy'), feedback: z.unknown() }).strict()
/** Typed RPC arguments mirror the additive migration. All responses are unknown
 * until closed parsing; provider errors and private context never become a DTO. */
export function createSupabaseRegistrationFeedbackV2Store(
  db: ServiceClient,
): RegistrationFeedbackV2Store {
  const store: RegistrationFeedbackV2Store = {
    async readReceipt(input) {
      const i = identity(input)
      const result = z
        .discriminatedUnion('action', [
          z.object({ action: z.literal('available'), feedback: z.unknown() }).strict(),
          legacy,
          ...empty,
        ])
        .parse(
          envelope(
            await db.rpc('read_mobile_registration_feedback_v2', {
              p_user_id: i.userId,
              p_registration_id: i.registrationId,
            }),
          ),
        )
      if (result.action === 'available')
        return { action: 'available', feedback: parseRegistrationFeedbackV2(result.feedback, i) }
      if (result.action === 'legacy')
        return { action: 'legacy', feedback: parseRegistrationFeedback(result.feedback, i) }
      return result
    },
    async capture(input) {
      const i = identity(input)
      const result = z
        .discriminatedUnion('action', [
          z.object({ action: z.literal('available'), context: z.unknown() }).strict(),
          empty[1],
        ])
        .parse(
          envelope(
            await db.rpc('capture_mobile_registration_feedback_v2', {
              p_user_id: i.userId,
              p_registration_id: i.registrationId,
            }),
          ),
        )
      return result.action === 'available'
        ? { action: 'available', observation: parseFeedbackV2Capture(result.context, i) }
        : result
    },
    async commit(input) {
      const i = identity({
        userId: input.userId,
        registrationId: input.registrationId,
        kind: input.kind,
      })
      const observation = parseFeedbackV2Capture(input.observation.context, i)
      const feedback = freeze(parseRegistrationFeedbackV2(input.feedback, i))
      const result = z
        .discriminatedUnion('action', [
          z.object({ action: z.literal('committed'), feedback: z.unknown() }).strict(),
          z.object({ action: z.literal('replay'), feedback: z.unknown() }).strict(),
          legacy,
          z.object({ action: z.literal('source_conflict') }).strict(),
          empty[1],
        ])
        .parse(
          envelope(
            await db.rpc('commit_mobile_registration_feedback_v2', {
              p_user_id: i.userId,
              p_registration_id: i.registrationId,
              p_expected_context: observation.context,
              p_feedback: feedback as unknown as Json,
            }),
          ),
        )
      if (result.action === 'legacy')
        return { action: 'legacy', feedback: parseRegistrationFeedback(result.feedback, i) }
      if (result.action !== 'committed' && result.action !== 'replay') return result
      const saved = parseRegistrationFeedbackV2(result.feedback, i)
      if (result.action === 'committed' && !isDeepStrictEqual(saved, feedback)) invalid()
      return { action: result.action, feedback: saved }
    },
  }
  return Object.freeze(store)
}
