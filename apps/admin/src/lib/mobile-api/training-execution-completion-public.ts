/** Safe public projection from a trusted original-login SQL observation.
 * Private frozen snapshots, source captures and prepared authority stay server
 * side. Optional feedback is composed separately through the existing service. */
import { z } from 'zod'
import type { ConversationFeedbackPresentationV2 } from './conversation-feedback-presentation-v2'
import {
  workoutClock,
  workoutHash,
  workoutSnapshot,
  workoutText,
  workoutUUID,
} from './conversation-workout-contracts'
import { readTrainingExecutionCompletionProof } from './training-execution-completion-backend'
import type { BoundTrainingExecutionCompletion } from './training-execution-completion-contracts'
import {
  readTrainingExecutionScope,
  readTrainingExecutionSession,
} from './training-execution-kernel'

export type TrainingExecutionCompletionDecision =
  | {
      readonly status: 'needs_reply'
      readonly question: { readonly field: 'activity' | 'duration_min'; readonly text: string }
    }
  | { readonly status: 'not_recorded'; readonly reason: string }

// Keep the already distributed workout writer untouched. This closed reader
// consumes its literal receipt; it neither recalculates nor grants authority.
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
    activity: z
      .object({
        workout_type: workoutText(200),
        duration_min: z.number().int().min(1).max(1440),
        intensity: z.enum(['leve', 'moderada', 'alta']).nullable(),
        estimated_kcal: z.number().int().min(0).max(10000).nullable(),
      })
      .strict(),
  })
  .strict()

export function projectTrainingExecutionCompletion(
  raw: unknown,
  bound: BoundTrainingExecutionCompletion,
  auth: string,
) {
  const value = readTrainingExecutionCompletionProof(raw, bound, auth),
    r = value.completion
  const base = {
    schema: 'training.execution-completion.v1' as const,
    status: r.status,
    owner_id: r.user_id,
    auth_user_id: r.auth_user_id,
    epoch: r.epoch,
    session_id: r.session_id,
    completion_id: r.completion_id,
    input_hash: r.input_hash,
    before_revision: r.original_revision,
    scope: readTrainingExecutionScope(value.scope),
  }
  const receipt =
    r.status === 'reserved'
      ? null
      : {
          schema: 'training.execution-completion-receipt.v1' as const,
          kind: r.status,
          owner_id: r.user_id,
          auth_user_id: r.auth_user_id,
          epoch: r.epoch,
          session_id: r.session_id,
          completion_id: r.completion_id,
          input_hash: r.input_hash,
          before_revision: r.original_revision,
          after_revision: r.status === 'completed' ? r.original_revision + 1 : r.original_revision,
          at: (r.status === 'completed'
            ? (r.receipt as { at: string })
            : (r.cancel_receipt as { at: string })
          ).at,
        }
  // Receipt time is validated by the original SQL proof decoder above; do not
  // substitute current observation time for an immutable completed/cancelled ACK.
  const frozen = readTrainingExecutionSession(r.frozen_state, base.scope)
  const session =
    r.status === 'cancelled'
      ? null
      : r.status === 'reserved'
        ? frozen
        : {
            ...frozen,
            schema: 'training.execution.v2' as const,
            phase: 'completed' as const,
            revision: r.original_revision + 1,
            updated_at: (r.receipt as { at: string }).at,
          }
  const workout =
    r.status === 'completed'
      ? receiptSchema.parse((r.receipt as { workout: unknown }).workout)
      : null
  if (
    workout &&
    (workout.owner_id !== r.user_id ||
      workout.command_id !== r.completion_id ||
      workout.registration_id !== r.completion_id ||
      workout.epoch !== r.epoch ||
      workout.input_hash !== r.workout_hash)
  )
    throw Error('Changed linked original workout')
  return workoutSnapshot({
    ...base,
    session,
    receipt,
    workout:
      workout === null
        ? null
        : {
            kind: 'workout' as const,
            provenance: workout.provenance,
            registration_id: workout.registration_id,
            workout_id: workout.workout_id,
            performed_at: workout.performed_at,
            local_date: workout.local_date,
            time_zone: workout.time_zone,
            committed_at: workout.committed_at,
            ...workout.activity,
          },
    workout_state:
      workout === null ? null : value.workout_is_live ? ('present' as const) : ('removed' as const),
    feedback: null as ConversationFeedbackPresentationV2 | null,
    decision: null as TrainingExecutionCompletionDecision | null,
  })
}
export type PublicTrainingExecutionCompletion = ReturnType<
  typeof projectTrainingExecutionCompletion
>
