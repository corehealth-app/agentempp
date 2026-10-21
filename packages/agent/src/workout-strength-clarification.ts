/** Pure current-authority wire decoders only. No factory, RPC, clock or catalogue lookup. */
import {
  parseStoredStrengthAnswerReceipt,
  type StoredStrengthAnswerReceipt,
  type WorkoutClarification,
} from './workout-strength-repository.js'
import { exactKeys, isRecord, isUUID } from './workout-strength-wire.js'

export type {
  AnswerWorkoutStrengthInput,
  AnswerWorkoutStrengthResult,
} from './workout-strength-repository.js'
export { parseWorkoutStrengthAnswerReply } from './workout-strength-repository.js'

type Anchor = Pick<StoredStrengthAnswerReceipt, 'ownerID' | 'workoutLogID'>
export type WorkoutStrengthClarificationResult =
  | {
      readonly status: 'available'
      readonly workoutLogID: string
      readonly lifecycleKey: string
      readonly factRevision: 0 | 1
      readonly clarification: WorkoutClarification
    }
  | { readonly status: 'unavailable'; readonly reason: 'provenance_gap' }
  | { readonly status: 'forbidden'; readonly reason: 'stale_lifecycle' | 'stale_workout' }

function invalid(): never {
  throw new TypeError('Invalid workout strength clarification reply')
}

export function parseWorkoutStrengthClarification(
  value: unknown,
  anchor: Anchor,
): WorkoutStrengthClarificationResult {
  if (!isRecord(value)) return invalid()
  if (value.status === 'unavailable' || value.status === 'forbidden') {
    if (!exactKeys(value, ['status', 'reason'])) return invalid()
    if (value.status === 'unavailable' && value.reason === 'provenance_gap')
      return { status: value.status, reason: value.reason }
    if (
      value.status === 'forbidden' &&
      (value.reason === 'stale_lifecycle' || value.reason === 'stale_workout')
    )
      return { status: value.status, reason: value.reason }
    return invalid()
  }
  if (
    !exactKeys(value, [
      'status',
      'workoutLogID',
      'lifecycleKey',
      'factRevision',
      'clarification',
    ]) ||
    value.status !== 'available' ||
    !isUUID(value.workoutLogID) ||
    value.workoutLogID !== anchor.workoutLogID ||
    !isUUID(value.lifecycleKey)
  )
    return invalid()
  const clarification = value.clarification
  if (!isRecord(clarification)) return invalid()
  let parsed: WorkoutClarification
  if (
    clarification.status === 'not_applicable' &&
    exactKeys(clarification, ['status']) &&
    value.factRevision === 0
  ) {
    parsed = { status: 'not_applicable' }
  } else if (
    clarification.status === 'unanswered' &&
    exactKeys(clarification, ['status', 'questionKey']) &&
    isUUID(clarification.questionKey) &&
    value.factRevision === 0
  ) {
    parsed = { status: 'unanswered', questionKey: clarification.questionKey }
  } else if (
    clarification.status === 'answered' &&
    exactKeys(clarification, ['status', 'receipt']) &&
    value.factRevision === 1
  ) {
    parsed = {
      status: 'answered',
      receipt: parseStoredStrengthAnswerReceipt(clarification.receipt, anchor),
    }
  } else return invalid()
  return {
    status: 'available',
    workoutLogID: value.workoutLogID,
    lifecycleKey: value.lifecycleKey,
    factRevision: parsed.status === 'answered' ? 1 : 0,
    clarification: parsed,
  }
}
