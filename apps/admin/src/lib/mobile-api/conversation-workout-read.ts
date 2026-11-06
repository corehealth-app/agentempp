/** Private decoder/adapter over the existing STABLE reconciliation RPC. No
 * route, admission, capture, preparation, calculator, provider or writer. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
} from './conversation-current-scope'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import {
  bindConversationWorkoutCommand,
  type CapturedConversationWorkoutSource,
  conversationWorkoutExecutionCommandSchema,
  parseConversationWorkoutSource,
  workoutClock,
  workoutDigest,
  workoutHash,
  workoutSnapshot,
  workoutUUID,
} from './conversation-workout-contracts'
import {
  type ConversationWorkoutEffect,
  parseConversationWorkoutEffect,
  pinConversationWorkoutPreparation,
} from './conversation-workout-writer'
import { MobileApiError } from './http'

const identitySchema = z
  .object({
    ownerId: workoutUUID,
    commandId: workoutUUID,
    inputHash: workoutHash,
    epoch: workoutUUID,
  })
  .strict()
export type ConversationWorkoutReadIdentity = Readonly<z.infer<typeof identitySchema>>
const n = z.number().finite()
// These are the existing to_jsonb(public.workout_logs/daily_snapshots) rows.
// They are private evidence, not a public DTO or authority to recalculate a day.
const currentSchema = z.discriminatedUnion('status', [
  z.object({ status: z.literal('removed') }).strict(),
  z
    .object({
      status: z.literal('present'),
      workout: z
        .object({
          created_at: workoutClock,
          duration_min: n.int().nullable(),
          estimated_kcal: n.nullable(),
          id: workoutUUID,
          intensity: z.string().nullable(),
          notes: z.string().nullable(),
          performed_at: workoutClock,
          raw_message_id: workoutUUID.nullable(),
          raw_provider_message_id: z.string().nullable(),
          snapshot_id: workoutUUID.nullable(),
          user_id: workoutUUID,
          workout_type: z.string().nullable(),
        })
        .strict(),
      snapshot: z
        .object({
          calories_consumed: n,
          calories_target: n.nullable(),
          carbs_g: n,
          closed_at: workoutClock.nullable(),
          created_at: workoutClock,
          current_protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']).nullable(),
          daily_balance: n.nullable(),
          date: z.string().date(),
          day_closed: z.boolean(),
          day_status: z.string(),
          deficit_accumulated: n,
          exercise_calories: n,
          exercise_energy_complete: z.boolean(),
          fat_g: n,
          gap_reminder_sent_at: workoutClock.nullable(),
          id: workoutUUID,
          protein_g: n,
          protein_target: n.nullable(),
          sleep_hours: n.nullable(),
          steps: n.int().nullable(),
          training_done: z.boolean(),
          updated_at: workoutClock,
          user_id: workoutUUID,
          water_consumed_ml: n.int(),
          xp_earned: n.int(),
        })
        .strict(),
    })
    .strict(),
])
type StoredSource = Readonly<{
  source_hash: string
  context: CapturedConversationWorkoutSource['context']
}>
type StoredPreparation = Readonly<{ prepared_hash: string; prepared: unknown }>
export type ConversationWorkoutReconciliation =
  | Readonly<{ action: 'absent' | 'stale_epoch' | 'input_conflict' | 'effect_conflict' }>
  | Readonly<{
      action: 'available'
      source: StoredSource | null
      preparation: StoredPreparation | null
      effect: Omit<ConversationWorkoutEffect, 'action'> | null
      current?: Readonly<z.infer<typeof currentSchema>>
    }>
function invalid(): never {
  throw new Error('Invalid original workout reconciliation')
}
function exact<T>(schema: z.ZodType<T>, raw: unknown): T {
  const copy = workoutSnapshot(raw),
    value = schema.parse(copy)
  if (!isDeepStrictEqual(value, copy)) return invalid()
  return copy as T
}
function identity(raw: ConversationWorkoutReadIdentity) {
  return exact(identitySchema, raw)
}
const requiredJSON = z.unknown().refine((v) => v !== undefined)
const available = z
  .object({
    action: z.literal('available'),
    source: requiredJSON.nullable(),
    preparation: requiredJSON.nullable(),
    effect: requiredJSON.nullable(),
    current: requiredJSON.optional(),
  })
  .strict()
const refusal = z
  .object({
    action: z.enum(['absent', 'stale_epoch', 'input_conflict', 'effect_conflict']),
  })
  .strict()

/** Bind every original fact before returning the unchanged SQL DTO. SQL source
 * hashes stay opaque: numeric source literals cannot be rehashed after JSON
 * parsing. The immutable preparation/effect must carry that same source hash. */
export function parseConversationWorkoutReconciliation(
  raw: unknown,
  rawIdentity: ConversationWorkoutReadIdentity,
): ConversationWorkoutReconciliation {
  const expected = identity(rawIdentity),
    copy = workoutSnapshot(raw)
  const action = z.object({ action: z.string() }).parse(copy).action
  if (action !== 'available') return exact(refusal, copy)
  const value = exact(available, copy)
  if (value.source === null) {
    if (value.preparation !== null || value.effect !== null || Object.hasOwn(value, 'current'))
      return invalid()
    return value as ConversationWorkoutReconciliation
  }
  const storedSource = z
    .object({
      source_hash: workoutHash,
      context: z.object({ source_input: conversationWorkoutExecutionCommandSchema }).passthrough(),
    })
    .strict()
    .parse(value.source)
  const command = bindConversationWorkoutCommand(
    expected.ownerId,
    `cmsg1:${expected.commandId}`,
    storedSource.context.source_input,
  )
  if (command.inputHash !== expected.inputHash) return invalid()
  const source = parseConversationWorkoutSource(command, value.source)
  if (source.epoch !== expected.epoch) return invalid()
  if (value.preparation === null) {
    if (value.effect !== null || Object.hasOwn(value, 'current')) return invalid()
    return value as ConversationWorkoutReconciliation
  }
  const preparation = exact(
    z
      .object({
        prepared_hash: workoutHash,
        prepared: requiredJSON,
      })
      .strict(),
    value.preparation,
  )
  const decision = resolveConversationWorkoutReport(source)
  const prepared =
    decision.status === 'ready'
      ? pinConversationWorkoutPreparation(source, preparation.prepared)
      : decision
  if (
    !isDeepStrictEqual(prepared, preparation.prepared) ||
    workoutDigest(prepared) !== preparation.prepared_hash
  )
    return invalid()
  if (value.effect === null) {
    if (Object.hasOwn(value, 'current')) return invalid()
    return value as ConversationWorkoutReconciliation
  }
  const effect = exact(
    z.object({ receipt: requiredJSON, original_facts: requiredJSON }).strict(),
    value.effect,
  )
  const proved = parseConversationWorkoutEffect(source, prepared, {
    action: 'available',
    ...effect,
  })
  const current = exact(currentSchema, value.current)
  if (current.status === 'present') {
    const w = current.workout,
      s = current.snapshot,
      r = proved.receipt
    if (
      w.id !== r.workout_id ||
      w.user_id !== expected.ownerId ||
      w.raw_provider_message_id !== r.operation_key ||
      w.snapshot_id !== r.snapshot_id ||
      s.id !== w.snapshot_id ||
      s.user_id !== expected.ownerId ||
      s.date !== r.local_date ||
      (w.estimated_kcal === null && s.exercise_energy_complete)
    )
      return invalid()
  }
  return value as ConversationWorkoutReconciliation
}

function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_workout_read_unavailable',
    'Original workout reconciliation is unavailable',
  )
}
/** Bound original identity plus mandatory existing-account Auth observer.
 * Even thrown RPCs receive the after observation. There is no automatic retry
 * and a failed scope remains closed for every later read on this instance. */
export function createSupabaseConversationWorkoutReadStore(
  db: ServiceClient,
  originalAuth: MobileAuthContext,
  rawIdentity: ConversationWorkoutReadIdentity,
  dependencies: ConversationCurrentScopeDependencies = {},
) {
  const who = workoutSnapshot(originalAuth),
    expected = identity(rawIdentity),
    scope = createConversationCurrentScope(
      db,
      who,
      {
        authUserId: who.authUserId,
        ...expected,
      },
      dependencies,
    ),
    rpc = db.rpc.bind(db) as unknown as (
      name: 'reconcile_conversation_workout',
      args: Readonly<Record<string, unknown>>,
    ) => PromiseLike<unknown>,
    args = workoutSnapshot({
      p_user_id: expected.ownerId,
      p_command_id: expected.commandId,
      p_input_hash: expected.inputHash,
      p_expected_epoch: expected.epoch,
    })
  return Object.freeze({
    async read(): Promise<ConversationWorkoutReconciliation> {
      await scope.observe()
      let raw: unknown
      try {
        raw = workoutSnapshot(await rpc('reconcile_conversation_workout', args))
      } catch {
        await scope.observe()
        return unavailable()
      }
      await scope.observe()
      try {
        const envelope = z
          .object({ data: requiredJSON, error: requiredJSON })
          .passthrough()
          .parse(workoutSnapshot(raw))
        if (envelope.error !== null) return unavailable()
        return parseConversationWorkoutReconciliation(envelope.data, expected)
      } catch {
        return unavailable()
      }
    },
  })
}
