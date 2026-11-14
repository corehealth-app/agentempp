/** A finish report accepted explicitly by the person. This binding grants no
 * recording authority: the original-Auth SQL reservation and protected workout
 * writer must prove the execution, actual activity and linked receipt. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import {
  type BoundConversationWorkoutCommand,
  bindConversationWorkoutCommand,
  workoutDigest,
  workoutSnapshot,
  workoutText,
  workoutUUID,
} from './conversation-workout-contracts'

const commandSchema = z
  .object({
    schema: z.literal('training.execution.finish.v1'),
    session_id: workoutUUID,
    operation_id: workoutUUID,
    expected_epoch: workoutUUID,
    expected_revision: z.number().int().min(0).max(2147483646),
    source: z.object({ channel: z.literal('text'), text: workoutText(2000) }).strict(),
  })
  .strict()

export type TrainingExecutionCompletionCommand = Readonly<z.infer<typeof commandSchema>>
export interface BoundTrainingExecutionCompletion {
  readonly ownerId: string
  readonly command: TrainingExecutionCompletionCommand
  readonly inputHash: string
  readonly workout: BoundConversationWorkoutCommand
}

export function parseTrainingExecutionCompletionCommand(
  raw: unknown,
): TrainingExecutionCompletionCommand {
  const copy = workoutSnapshot(raw),
    command = commandSchema.parse(copy)
  if (
    !isDeepStrictEqual(copy, command) ||
    Buffer.byteLength(JSON.stringify(command), 'utf8') > 16384
  ) {
    throw new Error('Invalid original training completion')
  }
  return workoutSnapshot(command)
}

export function bindTrainingExecutionCompletion(
  originalOwner: string,
  key: string | null,
  raw: unknown,
): BoundTrainingExecutionCompletion {
  const ownerId = workoutUUID.parse(originalOwner)
  const command = parseTrainingExecutionCompletionCommand(raw)
  if (key !== `tfinish1:${command.operation_id}`) throw new Error('Changed training completion key')
  const workout = bindConversationWorkoutCommand(ownerId, `cmsg1:${command.operation_id}`, {
    command_protocol: 'conversation.command.v1',
    command_id: command.operation_id,
    kind: 'workout.report',
    source: command.source,
  })
  return workoutSnapshot({ ownerId, command, inputHash: workoutDigest(command), workout })
}
