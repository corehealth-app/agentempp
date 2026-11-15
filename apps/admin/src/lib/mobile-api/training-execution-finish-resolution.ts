/** An atomic original-login observation/withdrawal is not a workout ACK.
 * Current state, original completion and future-denial marker remain distinct. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import {
  workoutClock,
  workoutHash,
  workoutSnapshot,
  workoutUUID,
} from './conversation-workout-contracts'
import type { BoundTrainingExecutionCompletion } from './training-execution-completion-contracts'
import {
  bindTrainingExecutionCompletion,
  parseTrainingExecutionCompletionCommand,
} from './training-execution-completion-contracts'
import {
  type PublicTrainingExecutionCompletion,
  projectTrainingExecutionCompletion,
} from './training-execution-completion-public'
import { trainingExecutionInstant } from './training-execution-instant'
import {
  readTrainingExecutionScope,
  readTrainingExecutionSession,
} from './training-execution-kernel'
import type { TrainingExecutionCurrentV2 } from './training-execution-progress-reconciliation'

export function parseTrainingExecutionFinishResolutionRequest(raw: unknown) {
  const body = z
    .object({
      schema: z.literal('training.execution.finish-resolution.v1'),
      mode: z.enum(['observe', 'withdraw']),
      command: z.unknown(),
    })
    .strict()
    .parse(workoutSnapshot(raw))
  return workoutSnapshot({
    ...body,
    command: parseTrainingExecutionCompletionCommand(body.command),
  })
}
export type TrainingExecutionFinishResolutionMode = 'observe' | 'withdraw'

const identity = z
  .object({
    session_id: workoutUUID,
    operation_id: workoutUUID,
    epoch: workoutUUID,
    before_revision: z.number().int().min(0).max(2147483646),
    input_hash: workoutHash,
  })
  .strict()
const withdrawal = identity
  .extend({
    schema: z.literal('training.execution-finish-withdrawal.v1'),
    owner_id: workoutUUID,
    auth_user_id: workoutUUID,
    at: workoutClock,
  })
  .strict()
function currentState(
  raw: unknown,
  scope: ReturnType<typeof readTrainingExecutionScope>,
  owner: string,
  auth: string,
): TrainingExecutionCurrentV2 | null {
  const action = z
    .object({ action: z.enum(['absent', 'progress', 'completion']) })
    .passthrough()
    .parse(raw).action
  if (action === 'absent') {
    const v = z
      .object({ action: z.literal('absent'), scope: z.unknown() })
      .strict()
      .parse(raw)
    if (!isDeepStrictEqual(readTrainingExecutionScope(v.scope), scope))
      throw Error('Changed absent current scope')
    return null
  }
  if (action === 'progress') {
    const v = z
      .object({ action: z.literal('progress'), scope: z.unknown(), session: z.unknown() })
      .strict()
      .parse(raw)
    if (!isDeepStrictEqual(readTrainingExecutionScope(v.scope), scope))
      throw Error('Changed current progress scope')
    const session = readTrainingExecutionSession(v.session, scope)
    return { schema: 'training.execution-state.v2', scope, session, completion: null }
  }
  const v = z
    .object({ action: z.literal('completion'), context: z.unknown() })
    .strict()
    .parse(raw)
  const command = z
    .object({ completion: z.object({ command: z.unknown() }).passthrough() })
    .passthrough()
    .parse(v.context).completion.command
  const id = z.object({ operation_id: workoutUUID }).passthrough().parse(command).operation_id
  const bound = bindTrainingExecutionCompletion(owner, `tfinish1:${id}`, command)
  const completion = projectTrainingExecutionCompletion(v.context, bound, auth)
  if (
    completion.status === 'cancelled' ||
    completion.session === null ||
    !isDeepStrictEqual(completion.scope, scope)
  )
    throw Error('Changed current completion')
  return { schema: 'training.execution-state.v2', scope, session: completion.session, completion }
}
export function projectTrainingExecutionFinishResolution(
  raw: unknown,
  bound: BoundTrainingExecutionCompletion,
  auth: string,
  mode: TrainingExecutionFinishResolutionMode = 'observe',
) {
  const copy = workoutSnapshot(raw)
  if (Buffer.byteLength(JSON.stringify(copy), 'utf8') > 2_097_152)
    throw Error('Oversized finish resolution')
  const base = z.object({
    action: z.enum(['absent', 'available', 'withdrawn']),
    request: identity,
    scope: z.unknown(),
    state: z.unknown(),
  })
  const header = base.passthrough().parse(copy)
  const v =
    header.action === 'absent'
      ? base.strict().parse(copy)
      : header.action === 'available'
        ? base.extend({ completion: z.unknown() }).strict().parse(copy)
        : base.extend({ withdrawal }).strict().parse(copy)
  if (v.action === 'available' && !('completion' in v))
    throw Error('Missing original completion proof')
  const expected = {
    session_id: bound.command.session_id,
    operation_id: bound.command.operation_id,
    epoch: bound.command.expected_epoch,
    before_revision: bound.command.expected_revision,
    input_hash: bound.inputHash,
  }
  const scope = readTrainingExecutionScope(v.scope)
  if (
    !isDeepStrictEqual(v.request, expected) ||
    scope.owner_id !== bound.ownerId ||
    scope.auth_user_id !== auth
  )
    throw Error('Changed original finish identity')
  const current = currentState(v.state, scope, bound.ownerId, auth)
  if (current && current.session.id !== bound.command.session_id)
    throw Error('Unrelated current execution')
  let completion: PublicTrainingExecutionCompletion | null = null,
    marker: z.infer<typeof withdrawal> | null = null
  let status: 'available' | 'withdrawn' | 'fenced' | 'ready' | 'pending',
    reason: string | null = null
  if ('completion' in v) {
    completion = projectTrainingExecutionCompletion(v.completion, bound, auth)
    if (
      completion.scope.epoch !== scope.epoch ||
      completion.scope.time_zone !== scope.time_zone ||
      trainingExecutionInstant(completion.scope.observed_at) >
        trainingExecutionInstant(scope.observed_at)
    )
      throw Error('Changed original completion observation')
    if (
      completion.status !== 'cancelled' &&
      (!current ||
        current.completion?.completion_id !== completion.completion_id ||
        current.completion.status !== completion.status ||
        !isDeepStrictEqual(current.session, completion.session))
    )
      throw Error('Original completion is not current')
    status = 'available'
  } else if ('withdrawal' in v) {
    marker = withdrawal.parse(v.withdrawal)
    const { owner_id, auth_user_id, at } = marker
    const id = {
      session_id: marker.session_id,
      operation_id: marker.operation_id,
      epoch: marker.epoch,
      before_revision: marker.before_revision,
      input_hash: marker.input_hash,
    }
    if (
      owner_id !== bound.ownerId ||
      auth_user_id !== auth ||
      !isDeepStrictEqual(id, expected) ||
      trainingExecutionInstant(at) > trainingExecutionInstant(scope.observed_at)
    )
      throw Error('Changed withdrawal marker')
    if (scope.epoch !== bound.command.expected_epoch && current !== null)
      throw Error('Do not adopt an old withdrawal execution in another epoch')
    status = 'withdrawn'
  } else if (scope.epoch !== bound.command.expected_epoch) {
    if (current !== null) throw Error('Do not adopt an old execution in another epoch')
    status = 'fenced'
    reason = 'epoch_changed'
  } else if (current?.session.phase !== 'in_progress' && current !== null) {
    status = 'fenced'
    reason = 'terminal'
  } else if (current && current.session.revision > bound.command.expected_revision) {
    status = 'fenced'
    reason = 'revision_advanced'
  } else if (current && current.session.local_date < scope.current_local_date) {
    status = 'fenced'
    reason = 'date_passed'
  } else if (current?.completion?.status === 'reserved') {
    status = 'pending'
    reason = 'other_reservation'
  } else if (!current) {
    status = 'pending'
    reason = 'session_unavailable'
  } else if (!scope.recording_allowed || scope.open_local_date !== current.session.local_date) {
    status = 'pending'
    reason = 'recording_unavailable'
  } else if (current.session.revision !== bound.command.expected_revision) {
    status = 'pending'
    reason = 'revision_unavailable'
  } else {
    status = 'ready'
  }
  return workoutSnapshot({
    schema: 'training.execution-finish-resolution.v1' as const,
    mode,
    status,
    reason,
    scope,
    session_id: expected.session_id,
    operation_id: expected.operation_id,
    input_hash: expected.input_hash,
    before_revision: expected.before_revision,
    expected_epoch: expected.epoch,
    current,
    completion,
    withdrawal: marker,
  })
}
export type PublicTrainingExecutionFinishResolution = ReturnType<
  typeof projectTrainingExecutionFinishResolution
>
