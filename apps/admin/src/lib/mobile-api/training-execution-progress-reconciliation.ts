/** Read-only bridge: an old immutable progress receipt is NOT a completed
 * workout receipt. Its original actual snapshot validates that old receipt;
 * only the independently proved CURRENT state is published to the caller. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import { workoutSnapshot, workoutUUID } from './conversation-workout-contracts'
import { MobileApiError } from './http'
import { readTrainingExecutionCompletionProof } from './training-execution-completion-backend'
import { bindTrainingExecutionCompletion } from './training-execution-completion-contracts'
import {
  type PublicTrainingExecutionCompletion,
  projectTrainingExecutionCompletion,
} from './training-execution-completion-public'
import {
  parseTrainingExecutionCommand,
  parseTrainingExecutionPersistence,
  readTrainingExecutionScope,
  readTrainingExecutionSession,
  type TrainingExecutionSession,
} from './training-execution-kernel'
export interface TrainingExecutionCurrentV2 {
  readonly schema: 'training.execution-state.v2'
  readonly scope: ReturnType<typeof readTrainingExecutionScope>
  readonly session:
    | TrainingExecutionSession
    | NonNullable<PublicTrainingExecutionCompletion['session']>
  readonly completion: PublicTrainingExecutionCompletion | null
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'training_execution_reconciliation_unavailable',
    'The original progress receipt is unavailable. Preserve the same operation.',
  )
}
export function projectTrainingExecutionProgressReconciliation(
  raw: unknown,
  rawCommand: unknown,
  original: { owner: string; auth: string },
) {
  const command = parseTrainingExecutionCommand(workoutSnapshot(rawCommand)),
    value = workoutSnapshot(raw)
  if (Buffer.byteLength(JSON.stringify(value), 'utf8') > 2_097_152) return unavailable()
  const header = z
    .object({ action: z.enum(['absent', 'available']), scope: z.unknown() })
    .passthrough()
    .parse(value)
  const scope = readTrainingExecutionScope(header.scope)
  if (
    scope.owner_id !== original.owner ||
    scope.auth_user_id !== original.auth ||
    scope.epoch !== command.expected_epoch
  )
    return unavailable()
  const absent = header.action === 'absent'
  const present = absent
    ? z
        .object({ action: z.literal('absent'), scope: z.unknown(), state: z.unknown() })
        .strict()
        .parse(value)
    : z
        .object({
          action: z.literal('available'),
          scope: z.unknown(),
          command: z.unknown(),
          receipt: z.unknown(),
          state: z.unknown(),
        })
        .strict()
        .parse(value)
  if (
    !absent &&
    'command' in present &&
    !isDeepStrictEqual(parseTrainingExecutionCommand(present.command), command)
  )
    return unavailable()
  const stateAction = z
    .object({ action: z.string(), scope: z.unknown().optional() })
    .passthrough()
    .parse(present.state)
  if (stateAction.action === 'absent') {
    z.object({ action: z.literal('absent'), scope: z.unknown() })
      .strict()
      .parse(present.state)
    if (!absent || !isDeepStrictEqual(readTrainingExecutionScope(stateAction.scope), scope))
      return unavailable()
    return workoutSnapshot({ action: 'absent' as const, scope, current: null })
  }
  const action = z
    .object({ action: z.enum(['progress', 'completion']) })
    .passthrough()
    .parse(present.state).action
  let current: TrainingExecutionCurrentV2, receiptState: TrainingExecutionSession
  if (action === 'progress') {
    const read = z
      .object({ action: z.literal('progress'), scope: z.unknown(), session: z.unknown() })
      .strict()
      .parse(present.state)
    const currentScope = readTrainingExecutionScope(read.scope),
      session = readTrainingExecutionSession(read.session, currentScope)
    if (!isDeepStrictEqual(scope, currentScope) || session.id !== command.session_id)
      return unavailable()
    receiptState = session
    current = {
      schema: 'training.execution-state.v2' as const,
      scope: currentScope,
      session,
      completion: null,
    }
  } else {
    const context = z
      .object({ action: z.literal('completion'), context: z.unknown() })
      .strict()
      .parse(present.state).context
    const stored = z
      .object({ completion: z.object({ command: z.unknown() }).passthrough() })
      .passthrough()
      .parse(context).completion.command
    const id = z.object({ operation_id: workoutUUID }).passthrough().parse(stored).operation_id
    const bound = bindTrainingExecutionCompletion(original.owner, `tfinish1:${id}`, stored)
    const proof = readTrainingExecutionCompletionProof(context, bound, original.auth)
    const completion = projectTrainingExecutionCompletion(context, bound, original.auth)
    if (
      completion.session === null ||
      completion.status === 'cancelled' ||
      completion.session_id !== command.session_id ||
      !isDeepStrictEqual(scope, completion.scope)
    )
      return unavailable()
    // This is the actual SQL-frozen progress snapshot, never a synthesized v1
    // version of the completed session. It is used only to verify the old ACK.
    receiptState = readTrainingExecutionSession(proof.completion.frozen_state, scope)
    current = {
      schema: 'training.execution-state.v2' as const,
      scope,
      session: completion.session,
      completion,
    }
  }
  if (
    command.schema === 'training.execution.start.v1' &&
    (command.plan_id !== receiptState.definition.plan_id ||
      command.plan_hash !== receiptState.definition.plan_hash ||
      command.day_index !== receiptState.definition.day_index ||
      command.expected_local_date !== receiptState.local_date)
  )
    return unavailable()
  if (absent) return workoutSnapshot({ action: 'absent' as const, scope, current })
  if (!('receipt' in present)) return unavailable()
  const originalReceipt = parseTrainingExecutionPersistence(
    { status: 'replayed', session: receiptState, receipt: present.receipt, audit: null },
    command,
    original,
  ).receipt
  return workoutSnapshot({ action: 'available' as const, receipt: originalReceipt, current })
}
