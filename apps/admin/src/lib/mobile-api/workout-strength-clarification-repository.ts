import {
  type AnswerWorkoutStrengthInput,
  parseWorkoutStrengthAnswerReply,
  parseWorkoutStrengthClarification,
} from '@mpp/agent/workout-strength-clarification'
import { z } from 'zod'
import { workoutStrengthUUIDSchema } from './workout-strength-clarification-contracts'

type Anchor = { readonly ownerID: string; readonly workoutLogID: string }
interface ReadArgs {
  readonly p_user_id: string
  readonly p_workout_log_id: string
}
interface AnswerArgs extends ReadArgs {
  readonly p_expected_lifecycle_key: string
  readonly p_expected_fact_revision: number
  readonly p_question_key: string
  readonly p_answer: 'yes' | 'no'
  readonly p_operation_key: string
}
interface Reply {
  readonly data: unknown
  readonly error: unknown
}
/** Only the CURRENT-authority wrappers are callable from this adapter. */
export interface WorkoutStrengthClarificationPort {
  rpc(
    ...request:
      | [name: 'get_mobile_workout_strength_clarification', args: ReadArgs]
      | [name: 'answer_mobile_workout_strength_clarification', args: AnswerArgs]
  ): PromiseLike<Reply>
}

export function createWorkoutStrengthClarificationRepository(
  port: WorkoutStrengthClarificationPort,
) {
  async function call(...request: Parameters<WorkoutStrengthClarificationPort['rpc']>) {
    const reply = await port.rpc(...request)
    if (
      !reply ||
      typeof reply !== 'object' ||
      !('data' in reply) ||
      !('error' in reply) ||
      reply.error === undefined
    )
      throw new TypeError('Invalid workout strength RPC reply')
    if (reply.error !== null) throw reply.error
    return reply.data
  }
  return {
    async read(input: Anchor) {
      const anchor = Object.freeze({
        ownerID: workoutStrengthUUIDSchema.parse(input.ownerID),
        workoutLogID: workoutStrengthUUIDSchema.parse(input.workoutLogID),
      })
      return parseWorkoutStrengthClarification(
        await call('get_mobile_workout_strength_clarification', {
          p_user_id: anchor.ownerID,
          p_workout_log_id: anchor.workoutLogID,
        }),
        anchor,
      )
    },
    async answer(input: AnswerWorkoutStrengthInput) {
      const attempt = Object.freeze({
        ownerID: workoutStrengthUUIDSchema.parse(input.ownerID),
        workoutLogID: workoutStrengthUUIDSchema.parse(input.workoutLogID),
        expectedLifecycleKey: workoutStrengthUUIDSchema.parse(input.expectedLifecycleKey),
        expectedFactRevision: z
          .number()
          .int()
          .min(0)
          .max(2147483647)
          .parse(input.expectedFactRevision),
        questionKey: workoutStrengthUUIDSchema.parse(input.questionKey),
        answer: z.enum(['yes', 'no']).parse(input.answer),
        operationKey: z.string().min(1).parse(input.operationKey),
      })
      const data = await call('answer_mobile_workout_strength_clarification', {
        p_user_id: attempt.ownerID,
        p_workout_log_id: attempt.workoutLogID,
        p_expected_lifecycle_key: attempt.expectedLifecycleKey,
        p_expected_fact_revision: attempt.expectedFactRevision,
        p_question_key: attempt.questionKey,
        p_answer: attempt.answer,
        p_operation_key: attempt.operationKey,
      })
      return parseWorkoutStrengthAnswerReply(data, attempt)
    },
  }
}
