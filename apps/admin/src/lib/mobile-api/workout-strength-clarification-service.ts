import type { ServiceClient } from '@mpp/db'
import { MobileApiError } from './http'
import type { WorkoutStrengthAnswerBody } from './workout-strength-clarification-contracts'
import {
  createWorkoutStrengthClarificationRepository,
  type WorkoutStrengthClarificationPort,
} from './workout-strength-clarification-repository'

function requireEnabled(enabled: boolean) {
  if (!enabled)
    throw new MobileApiError(
      503,
      'workout_strength_clarification_unavailable',
      'Workout clarification is unavailable',
    )
}
function unavailable(): never {
  throw new MobileApiError(
    409,
    'workout_strength_unavailable',
    'Workout clarification is no longer available',
  )
}
function answered(
  workoutID: string,
  lifecycleKey: string,
  questionKey: string,
  receipt: { readonly answer: 'yes' | 'no'; readonly acceptedAt: string },
) {
  return {
    status: 'answered' as const,
    workout_id: workoutID,
    lifecycle_key: lifecycleKey,
    fact_revision: 1 as const,
    question_key: questionKey,
    receipt: { answer: receipt.answer, accepted_at: receipt.acceptedAt },
  }
}

export async function loadWorkoutStrengthClarification(
  client: ServiceClient,
  ownerID: string,
  workoutID: string,
  enabled: boolean,
) {
  requireEnabled(enabled)
  const result = await createWorkoutStrengthClarificationRepository(
    client as unknown as WorkoutStrengthClarificationPort,
  ).read({ ownerID, workoutLogID: workoutID })
  if (result.status === 'forbidden') return unavailable()
  if (result.status === 'unavailable') return { status: result.status, reason: result.reason }
  const clarification = result.clarification
  if (clarification.status === 'answered')
    return answered(
      result.workoutLogID,
      result.lifecycleKey,
      clarification.receipt.questionKey,
      clarification.receipt,
    )
  const identity = {
    workout_id: result.workoutLogID,
    lifecycle_key: result.lifecycleKey,
    fact_revision: 0 as const,
  }
  return clarification.status === 'unanswered'
    ? { status: clarification.status, ...identity, question_key: clarification.questionKey }
    : { status: clarification.status, ...identity }
}

export async function answerWorkoutStrengthClarification(
  client: ServiceClient,
  ownerID: string,
  workoutID: string,
  body: WorkoutStrengthAnswerBody,
  operationKey: string,
  enabled: boolean,
) {
  requireEnabled(enabled)
  const attempt = Object.freeze({
    ownerID,
    workoutLogID: workoutID,
    expectedLifecycleKey: body.expected_lifecycle_key,
    expectedFactRevision: body.expected_fact_revision,
    questionKey: body.question_key,
    answer: body.answer,
    operationKey,
  })
  const result = await createWorkoutStrengthClarificationRepository(
    client as unknown as WorkoutStrengthClarificationPort,
  ).answer(attempt)
  if ('receipt' in result)
    return answered(
      workoutID,
      attempt.expectedLifecycleKey,
      result.receipt.questionKey,
      result.receipt,
    )
  if (
    result.reason === 'mixed_owner' ||
    result.reason === 'stale_workout' ||
    result.reason === 'stale_lifecycle'
  )
    return unavailable()
  throw new MobileApiError(
    409,
    'workout_strength_answer_conflict',
    'Workout clarification could not be saved; reload the workout',
  )
}
