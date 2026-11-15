/** Private server composition, not a route response. Reuses the existing workout
 * resolver, clinical/energy/strength writer and mandatory same-identity read.
 * Only the commit RPC is replaced by the original-login atomic completion.
 * No route, capability, feedback writer or native cutover is installed here. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import {
  type ConversationWorkoutBackendRPC,
  createConversationWorkoutBackend,
} from './conversation-workout-backend'
import {
  workoutClock,
  workoutHash,
  workoutSnapshot,
  workoutUUID,
} from './conversation-workout-contracts'
import {
  type BoundTrainingExecutionCompletion,
  bindTrainingExecutionCompletion,
} from './training-execution-completion-contracts'
import {
  readTrainingExecutionScope,
  readTrainingExecutionSession,
} from './training-execution-kernel'

type CompletionName =
  | 'observe_training_execution_finish_authenticated'
  | 'withdraw_training_execution_finish_authenticated'
  | 'reconcile_training_execution_progress_authenticated'
  | 'read_training_execution_state_v2_authenticated'
  | 'read_training_execution_home_v2_authenticated'
  | 'begin_training_execution_completion_authenticated'
  | 'read_training_execution_completion_authenticated'
  | 'cancel_training_execution_completion_authenticated'
  | 'commit_training_execution_completion_authenticated'
type Name = Parameters<ConversationWorkoutBackendRPC['rpc']>[0] | CompletionName
export interface TrainingExecutionCompletionRPC {
  rpc(name: Name, args: Readonly<Record<string, unknown>>): PromiseLike<unknown>
}
export interface TrainingExecutionCompletionScope {
  readonly owner_id: string
  readonly auth_user_id: string
  readonly auth_session_id: string
  /** Fresh verified original Auth + non-admin patient mapping + clinical epoch.
   * Must not bootstrap, refresh or adopt a replacement login. */
  checkCurrentScope(): Promise<boolean>
}
const claim = z
  .object({
    user_id: workoutUUID,
    completion_id: workoutUUID,
    session_id: workoutUUID,
    auth_user_id: workoutUUID,
    epoch: workoutUUID,
    time_zone: z.string(),
    original_revision: z.number().int().min(0).max(2147483646),
    command: z.unknown(),
    input_hash: workoutHash,
    workout_input: z.unknown(),
    workout_hash: workoutHash,
    frozen_state: z.unknown(),
    frozen_hash: workoutHash,
    status: z.enum(['reserved', 'completed', 'cancelled']),
    reserved_at: workoutClock,
    completed_at: workoutClock.nullable(),
    cancelled_at: workoutClock.nullable(),
    receipt: z.unknown().nullable(),
    cancel_receipt: z.unknown().nullable(),
  })
  .strict()
const context = z
  .object({
    action: z.enum(['reserved', 'replay', 'available']),
    scope: z.unknown(),
    session: z.unknown(),
    completion: claim,
    workout_is_live: z.boolean().nullable(),
  })
  .strict()
function pin(raw: BoundTrainingExecutionCompletion, owner: string) {
  const bound = bindTrainingExecutionCompletion(
    owner,
    `tfinish1:${raw.command.operation_id}`,
    raw.command,
  )
  if (!isDeepStrictEqual(raw, bound)) throw Error('Changed original completion')
  return bound
}
/** Internal trusted SQL proof, not a public response DTO or an authority from a
 * request body. The runtime must keep the actual original-login RPC boundary. */
export function readTrainingExecutionCompletionProof(
  raw: unknown,
  bound: BoundTrainingExecutionCompletion,
  auth: string,
) {
  const copy = workoutSnapshot(raw)
  if (Buffer.byteLength(JSON.stringify(copy), 'utf8') > 2_097_152)
    throw Error('Oversized completion')
  const value = context.parse(copy),
    r = value.completion,
    s = readTrainingExecutionScope(value.scope)
  if (
    !isDeepStrictEqual(value, copy) ||
    s.owner_id !== bound.ownerId ||
    s.auth_user_id !== auth ||
    s.epoch !== bound.command.expected_epoch ||
    r.user_id !== bound.ownerId ||
    r.auth_user_id !== auth ||
    r.completion_id !== bound.command.operation_id ||
    r.session_id !== bound.command.session_id ||
    r.epoch !== s.epoch ||
    r.time_zone !== s.time_zone ||
    r.original_revision !== bound.command.expected_revision ||
    r.input_hash !== bound.inputHash ||
    r.workout_hash !== bound.workout.inputHash ||
    !isDeepStrictEqual(r.command, bound.command) ||
    !isDeepStrictEqual(r.workout_input, bound.workout.command)
  )
    throw Error('Changed reserved completion')
  const frozen = readTrainingExecutionSession(r.frozen_state, s)
  if (
    frozen.id !== r.session_id ||
    frozen.revision !== r.original_revision ||
    frozen.phase !== 'in_progress'
  )
    throw Error('Changed frozen execution')
  if (r.status === 'reserved') {
    if (
      !isDeepStrictEqual(value.session, frozen) ||
      r.completed_at !== null ||
      r.receipt !== null ||
      r.cancelled_at !== null ||
      r.cancel_receipt !== null ||
      value.workout_is_live !== null
    )
      throw Error('Changed reserved execution')
  } else if (r.status === 'completed') {
    const receipt = z
      .object({
        schema: z.literal('training.execution-completed.v1'),
        owner_id: workoutUUID,
        auth_user_id: workoutUUID,
        epoch: workoutUUID,
        session_id: workoutUUID,
        completion_id: workoutUUID,
        input_hash: workoutHash,
        before_revision: z.number().int(),
        after_revision: z.number().int(),
        at: workoutClock,
        workout: z
          .object({
            owner_id: workoutUUID,
            command_id: workoutUUID,
            input_hash: workoutHash,
            epoch: workoutUUID,
            committed_at: workoutClock,
          })
          .passthrough(),
      })
      .strict()
      .parse(r.receipt)
    const w = receipt.workout
    if (
      receipt.owner_id !== bound.ownerId ||
      receipt.auth_user_id !== auth ||
      receipt.epoch !== r.epoch ||
      receipt.session_id !== r.session_id ||
      receipt.completion_id !== r.completion_id ||
      receipt.input_hash !== r.input_hash ||
      receipt.before_revision !== r.original_revision ||
      receipt.after_revision !== r.original_revision + 1 ||
      receipt.at !== w.committed_at ||
      w.owner_id !== bound.ownerId ||
      w.command_id !== r.completion_id ||
      w.epoch !== r.epoch ||
      w.input_hash !== r.workout_hash ||
      r.completed_at === null ||
      new Date(r.completed_at).getTime() !== new Date(receipt.at).getTime() ||
      r.cancelled_at !== null ||
      r.cancel_receipt !== null ||
      value.workout_is_live === null ||
      !isDeepStrictEqual(value.session, {
        ...frozen,
        schema: 'training.execution.v2',
        phase: 'completed',
        revision: r.original_revision + 1,
        updated_at: receipt.at,
      })
    )
      throw Error('Unproved completed execution')
  } else {
    const cancelled = z
      .object({
        schema: z.literal('training.execution-finish-cancelled.v1'),
        owner_id: workoutUUID,
        auth_user_id: workoutUUID,
        epoch: workoutUUID,
        session_id: workoutUUID,
        completion_id: workoutUUID,
        input_hash: workoutHash,
        at: workoutClock,
      })
      .strict()
      .parse(r.cancel_receipt)
    if (
      cancelled.owner_id !== r.user_id ||
      cancelled.auth_user_id !== auth ||
      cancelled.epoch !== r.epoch ||
      cancelled.session_id !== r.session_id ||
      cancelled.completion_id !== r.completion_id ||
      cancelled.input_hash !== r.input_hash ||
      r.cancelled_at === null ||
      new Date(r.cancelled_at).getTime() !== new Date(cancelled.at).getTime() ||
      r.completed_at !== null ||
      r.receipt !== null ||
      value.workout_is_live !== null
    )
      throw Error('Unproved cancelled completion')
  }
  return workoutSnapshot(value)
}

export function createTrainingExecutionCompletionBackend(
  port: TrainingExecutionCompletionRPC,
  original: TrainingExecutionCompletionScope,
) {
  const rpc = port.rpc.bind(port),
    check = original.checkCurrentScope.bind(original)
  const owner = workoutUUID.parse(original.owner_id),
    auth = workoutUUID.parse(original.auth_user_id),
    login = workoutUUID.parse(original.auth_session_id)
  function request(raw: BoundTrainingExecutionCompletion) {
    const bound = pin(raw, owner),
      args = workoutSnapshot({ p_user_id: owner, p_auth_user_id: auth, p_auth_session_id: login })
    let closed = false
    async function current() {
      if (closed) throw Error('Closed original training completion scope')
      try {
        if ((await check()) !== true) throw Error('Changed original training completion scope')
      } catch (error) {
        closed = true
        throw error
      }
    }
    async function call(name: Name, body: Readonly<Record<string, unknown>>) {
      await current()
      const result = workoutSnapshot(await rpc(name, body))
      await current()
      const envelope = z
        .object({ data: z.unknown(), error: z.unknown() })
        .passthrough()
        .parse(result)
      if (envelope.error !== null) throw Error('Training completion transport unavailable')
      return envelope.data
    }
    async function read() {
      return readTrainingExecutionCompletionProof(
        await call('read_training_execution_completion_authenticated', {
          ...args,
          p_completion_id: bound.command.operation_id,
        }),
        bound,
        auth,
      )
    }
    return { bound, args, current, call, read }
  }
  return Object.freeze({
    async read(raw: BoundTrainingExecutionCompletion) {
      return request(raw).read()
    },
    async cancel(raw: BoundTrainingExecutionCompletion) {
      const { bound, args, call, read } = request(raw)
      await read()
      const result = z
        .object({ action: z.enum(['cancelled', 'replay', 'completed']), receipt: z.unknown() })
        .strict()
        .parse(
          await call('cancel_training_execution_completion_authenticated', {
            ...args,
            p_completion_id: bound.command.operation_id,
            p_input_hash: bound.inputHash,
          }),
        )
      const after = await read(),
        r = after.completion
      if (
        r.status === 'reserved' ||
        !isDeepStrictEqual(
          result.receipt,
          r.status === 'completed' ? r.receipt : r.cancel_receipt,
        ) ||
        (r.status === 'completed') !== (result.action === 'completed')
      )
        throw Error('Unproved training completion cancellation')
      return after
    },
    async submit(raw: BoundTrainingExecutionCompletion) {
      const { bound, args, call, current } = request(raw)
      const beginning = readTrainingExecutionCompletionProof(
        await call('begin_training_execution_completion_authenticated', {
          ...args,
          p_command: bound.command,
        }),
        bound,
        auth,
      )
      if (beginning.completion.status === 'cancelled')
        return workoutSnapshot({ status: 'cancelled' as const })
      async function live() {
        const value = readTrainingExecutionCompletionProof(
          await call('read_training_execution_completion_authenticated', {
            ...args,
            p_completion_id: bound.command.operation_id,
          }),
          bound,
          auth,
        )
        if (value.completion.status === 'cancelled') throw Error('Cancelled training completion')
        return value
      }
      const backend = createConversationWorkoutBackend(
        {
          async rpc(name, body) {
            if (name !== 'commit_conversation_workout')
              return { data: await call(name, body), error: null }
            // Derive identity from the frozen accepted command, never the caller.
            if (
              body.p_user_id !== owner ||
              body.p_command_id !== bound.command.operation_id ||
              body.p_input_hash !== bound.workout.inputHash ||
              body.p_expected_epoch !== bound.command.expected_epoch
            )
              throw Error('Changed training workout commit')
            return {
              data: await call('commit_training_execution_completion_authenticated', {
                ...args,
                p_completion_id: bound.command.operation_id,
                p_input_hash: bound.inputHash,
                p_source_hash: body.p_source_hash,
                p_prepared_hash: body.p_prepared_hash,
                p_prepared: body.p_prepared,
              }),
              error: null,
            }
          },
        },
        {
          async checkCurrentScope() {
            await live()
            return true
          },
        },
      )
      const result = await backend.report(bound.workout, bound.command.expected_epoch)
      await current()
      if (result.status === 'saved') {
        const completed = await live()
        if (
          completed.completion.status !== 'completed' ||
          !isDeepStrictEqual(
            (completed.completion.receipt as { workout: unknown }).workout,
            result.effect.receipt,
          )
        )
          throw Error('Workout has no linked training completion')
        return workoutSnapshot({ ...result, completion: completed })
      }
      if (result.status === 'needs_reply' || result.status === 'not_reported')
        return workoutSnapshot(result)
      return workoutSnapshot({ status: 'pending' as const })
    },
  })
}
