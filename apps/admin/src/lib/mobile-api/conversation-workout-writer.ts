/** Transport and durable receipt validation. No public caller or legacy UI
 * confirmation is supplied. Rich mutation data
 * never acknowledges an effect; one actual same-identity read must prove it. */
import { isDeepStrictEqual } from 'node:util'
import { prepareRegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
import { confirmedWorkoutLogIDFromCapture } from '@mpp/agent/workout-strength-identity'
import { z } from 'zod'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import {
  type CapturedConversationWorkoutSource,
  parseConversationWorkoutSource,
  workoutClock,
  workoutDigest,
  workoutHash,
  workoutSnapshot,
  workoutText,
  workoutUUID,
} from './conversation-workout-contracts'

const number = z.number().finite(),
  intensity = z.enum(['leve', 'moderada', 'alta']).nullable()
const activitySchema = z
  .object({
    workout_type: workoutText(200),
    duration_min: number.int().min(1).max(1440),
    intensity,
    estimated_kcal: number.int().min(0).max(10000).nullable(),
  })
  .strict()
const receiptSchema = z
  .object({
    schema: z.literal('conversation.workout-effect.v1'),
    provenance: z.literal('conversation.workout.v1'),
    owner_id: workoutUUID,
    command_id: workoutUUID,
    input_hash: workoutHash,
    source_hash: workoutHash,
    epoch: workoutUUID,
    registration_id: workoutUUID,
    workout_id: workoutUUID,
    snapshot_id: workoutUUID,
    lifecycle_key: workoutUUID,
    operation_key: workoutText(200),
    prepared_hash: workoutHash,
    performed_at: workoutClock,
    local_date: z.string().date(),
    time_zone: workoutText(200),
    committed_at: workoutClock,
    effect_version: z.literal(1),
    activity: activitySchema,
  })
  .strict()
const effectSchema = z
  .object({
    action: z.literal('available'),
    receipt: receiptSchema,
    original_facts: z
      .object({
        workout: z
          .object({
            id: workoutUUID,
            user_id: workoutUUID,
            snapshot_id: workoutUUID,
            raw_provider_message_id: workoutText(200),
            workout_type: workoutText(200),
            duration_min: number.int().positive(),
            intensity,
            estimated_kcal: number.nonnegative().nullable(),
            performed_at: workoutClock,
          })
          .strict(),
        snapshot: z
          .object({ id: workoutUUID, user_id: workoutUUID, date: z.string().date() })
          .strict(),
        strength_capture: z.unknown(),
      })
      .strict(),
  })
  .strict()
export type ConversationWorkoutEffect = Readonly<z.infer<typeof effectSchema>>
function sourcePin(raw: CapturedConversationWorkoutSource) {
  const source = parseConversationWorkoutSource(raw.command, {
    source_hash: raw.sourceHash,
    context: raw.context,
  })
  if (!isDeepStrictEqual(raw, source)) throw new Error('Changed workout source')
  return source
}
function preparedPin(source: CapturedConversationWorkoutSource, raw: unknown) {
  const copy = workoutSnapshot(raw),
    decision = resolveConversationWorkoutReport(source)
  if (decision.status !== 'ready' || !copy || typeof copy !== 'object')
    throw new Error('Unproved workout report')
  const value = z.object({ activity: activitySchema }).passthrough().parse(copy)
  const kcal = value.activity.estimated_kcal,
    expected = {
      ...decision,
      activity: { ...decision.activity, estimated_kcal: kcal },
      performed_at: source.admittedAt,
      local_date: source.localDate,
      time_zone: source.clinical.timezone,
      energy:
        kcal === null
          ? { status: 'unavailable' }
          : {
              status: 'available',
              source: 'calc_workout_kcal',
              weight_kg: source.clinical.body.weight_kg,
            },
    }
  if (
    !isDeepStrictEqual(copy, expected) ||
    (kcal !== null &&
      (source.clinical.body.weight_kg === null || decision.activity.intensity === null))
  )
    throw new Error('Changed workout preparation')
  return workoutSnapshot(expected)
}
/** Full private projection plus real strength wire. Shape validation cannot
 * authenticate a fabricated SQL producer; the backend supplies trusted transport
 * and mandatory fresh scope observation. */
export function parseConversationWorkoutEffect(
  rawSource: CapturedConversationWorkoutSource,
  rawPrepared: unknown,
  raw: unknown,
): ConversationWorkoutEffect {
  const source = sourcePin(rawSource),
    prepared = preparedPin(source, rawPrepared),
    copy = workoutSnapshot(raw),
    value = effectSchema.parse(copy)
  if (!isDeepStrictEqual(copy, value)) throw new Error('Changed workout effect')
  const r = value.receipt,
    w = value.original_facts.workout,
    s = value.original_facts.snapshot,
    at = conversationJournalInstant
  if (
    r.owner_id !== source.command.ownerId ||
    r.command_id !== source.command.commandId ||
    r.registration_id !== r.command_id ||
    r.input_hash !== source.command.inputHash ||
    r.source_hash !== source.sourceHash ||
    r.epoch !== source.epoch ||
    r.prepared_hash !== workoutDigest(prepared) ||
    r.operation_key !== `cwork1:${r.command_id}` ||
    r.local_date !== source.localDate ||
    r.time_zone !== source.clinical.timezone ||
    at(r.performed_at) !== at(source.admittedAt) ||
    at(r.committed_at) < at(source.capturedAt) ||
    !isDeepStrictEqual(r.activity, prepared.activity) ||
    w.id !== r.workout_id ||
    w.user_id !== r.owner_id ||
    w.snapshot_id !== r.snapshot_id ||
    w.raw_provider_message_id !== r.operation_key ||
    w.workout_type !== r.activity.workout_type ||
    w.duration_min !== r.activity.duration_min ||
    w.intensity !== r.activity.intensity ||
    w.estimated_kcal !== r.activity.estimated_kcal ||
    at(w.performed_at) !== at(r.performed_at) ||
    s.id !== r.snapshot_id ||
    s.user_id !== r.owner_id ||
    s.date !== r.local_date
  )
    throw new Error('Unproved workout effect')
  const strength = value.original_facts.strength_capture
  if (
    confirmedWorkoutLogIDFromCapture(strength, r.owner_id, r.activity.workout_type) !== r.workout_id
  )
    throw new Error('Unproved workout strength effect')
  const shape = z
    .object({
      binding: z.object({
        lifecycleKey: workoutUUID,
        operationKey: z.string(),
        resolution: z.enum(['sql_insert', 'sql_replay']),
      }),
      fact: z.object({
        anchor: z.object({
          snapshotID: workoutUUID,
          storedWorkoutType: z.string(),
          performedAt: workoutClock,
          snapshotDate: z.string(),
        }),
        calendar: z.object({
          status: z.literal('proven'),
          timeZone: z.string(),
          localDate: z.string(),
        }),
      }),
    })
    .parse(strength)
  if (
    shape.binding.lifecycleKey !== r.lifecycle_key ||
    shape.binding.operationKey !== r.operation_key ||
    shape.fact.anchor.snapshotID !== r.snapshot_id ||
    shape.fact.anchor.storedWorkoutType !== r.activity.workout_type ||
    at(shape.fact.anchor.performedAt) !== at(r.performed_at) ||
    shape.fact.anchor.snapshotDate !== r.local_date ||
    shape.fact.calendar.timeZone !== r.time_zone ||
    shape.fact.calendar.localDate !== r.local_date
  )
    throw new Error('Changed workout strength anchor')
  const classification = z
    .object({
      fact: z.object({
        classification: z.object({
          status: z.literal('matched'),
          catalogue: z.object({
            id: workoutUUID,
            slug: z.string(),
            displayName: z.string(),
            updatedAtLiteral: workoutClock,
          }),
        }),
      }),
    })
    .parse(strength).fact.classification
  const captured = source.context.catalogue.find((row) => row.slug === r.activity.workout_type)
  if (
    !captured ||
    classification.catalogue.id !== captured.id ||
    classification.catalogue.slug !== captured.slug ||
    classification.catalogue.displayName !== captured.display_name ||
    at(classification.catalogue.updatedAtLiteral) !== at(captured.updated_at)
  )
    throw new Error('Changed workout catalogue proof')
  return workoutSnapshot(value)
}
/** Only original facts. Current policy/day, coverage, ledger, education and
 * public historical presentation remain separate required integration gates. */
export function projectConversationWorkoutFacts(effect: ConversationWorkoutEffect) {
  const r = effect.receipt,
    registration = prepareRegistrationFeedbackV2({
      registrationId: r.registration_id,
      localDate: r.local_date,
      locale: null,
      registration: { kind: 'workout', log_id: r.workout_id, ...r.activity },
      officialDay: null,
      policy: null,
      educationAvailable: false,
    }).registration
  return workoutSnapshot({
    registration,
    localDate: r.local_date,
    logIds: [r.workout_id],
    provenance: r.provenance,
  })
}
export interface ConversationWorkoutRPCPort {
  rpc(
    name: 'read_conversation_workout_effect' | 'commit_conversation_workout',
    args: Readonly<Record<string, unknown>>,
  ): PromiseLike<unknown>
}
export interface ConversationWorkoutWriterScope {
  checkCurrentScope(scope: {
    readonly owner_id: string
    readonly command_id: string
    readonly input_hash: string
    readonly source_hash: string
    readonly epoch: string
  }): Promise<boolean>
}
function data(raw: unknown) {
  const copy = workoutSnapshot(raw),
    envelope = z.object({ data: z.unknown(), error: z.unknown() }).passthrough().parse(copy)
  if (envelope.error !== null) throw new Error('Workout transport unavailable')
  return envelope.data
}
export function createConversationWorkoutWriter(
  port: ConversationWorkoutRPCPort,
  scopePort: ConversationWorkoutWriterScope,
) {
  const rpc = port.rpc.bind(port),
    check = scopePort.checkCurrentScope.bind(scopePort)
  async function run(
    rawSource: CapturedConversationWorkoutSource,
    rawPrepared: unknown,
    write: boolean,
  ) {
    const source = sourcePin(rawSource),
      prepared = preparedPin(source, rawPrepared),
      identity = workoutSnapshot({
        owner_id: source.command.ownerId,
        command_id: source.command.commandId,
        input_hash: source.command.inputHash,
        source_hash: source.sourceHash,
        epoch: source.epoch,
      })
    const args = workoutSnapshot({
      p_user_id: identity.owner_id,
      p_command_id: identity.command_id,
      p_input_hash: identity.input_hash,
      p_source_hash: identity.source_hash,
      p_expected_epoch: identity.epoch,
      p_prepared_hash: workoutDigest(prepared),
    })
    const uncertain = () =>
      workoutSnapshot({ status: 'reconciliation_required' as const, identity })
    let closed = false
    async function current() {
      if (closed) throw new Error('Closed workout scope')
      try {
        if ((await check(identity)) !== true || closed) throw new Error('Changed workout scope')
      } catch {
        closed = true
        throw new Error('Closed workout scope')
      }
    }
    async function call(name: Parameters<typeof rpc>[0], body: Readonly<Record<string, unknown>>) {
      await current()
      try {
        const result = workoutSnapshot(await rpc(name, body))
        await current()
        return data(result)
      } catch (error) {
        await current()
        throw error
      }
    }
    async function actual() {
      const raw = await call('read_conversation_workout_effect', args)
      if (isDeepStrictEqual(raw, { action: 'absent' })) return null
      return parseConversationWorkoutEffect(source, prepared, raw)
    }
    try {
      const existing = await actual()
      if (existing) return workoutSnapshot({ status: 'saved' as const, effect: existing })
      if (!write) return workoutSnapshot({ status: 'absent' as const, identity })
      try {
        await call('commit_conversation_workout', { ...args, p_prepared: prepared })
      } catch {
        if (closed) return uncertain()
      }
      const saved = await actual()
      return saved ? workoutSnapshot({ status: 'saved' as const, effect: saved }) : uncertain()
    } catch {
      return uncertain()
    }
  }
  return Object.freeze({
    commit: (source: CapturedConversationWorkoutSource, prepared: unknown) =>
      run(source, prepared, true),
    read: (source: CapturedConversationWorkoutSource, prepared: unknown) =>
      run(source, prepared, false),
  })
}

export { preparedPin as pinConversationWorkoutPreparation }
