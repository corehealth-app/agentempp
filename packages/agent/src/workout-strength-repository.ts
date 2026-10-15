/** Backend RPC adapter. Shape checks do not authenticate DB provenance.
 * The trusted SQL producer, lifecycle and future callers remain separate gates. */
import type {
  WorkoutCatalogueObservation,
  WorkoutCatalogueRow,
  WorkoutClassification,
} from '@mpp/core/workout-strength-classification'
import { exactKeys, isCivilDate, isRecord, isUTCUS6, isUUID } from './workout-strength-wire.js'

export interface WorkoutOwnerScope {
  readonly ownerID: string
  readonly expectedLifecycleKey: string
}
export interface ConfirmedWorkoutAnchor {
  readonly ownerID: string
  readonly workoutLogID: string
  readonly lifecycleKey: string
  readonly snapshotID: string
  readonly storedWorkoutType: string
  readonly performedAt: string
  readonly snapshotDate: string
}
export type WorkoutCalendar =
  | {
      readonly status: 'proven'
      readonly performedAt: string
      readonly localDate: string
      readonly timeZone: string
      readonly zoneSource: 'official_owner_zone_at_recording'
      readonly zoneObservedAt: string
      readonly snapshotID: string
      readonly snapshotDate: string
    }
  | {
      readonly status: 'unavailable'
      readonly reason: 'zone_unproved' | 'calendar_conflict' | 'legacy_calendar_gap'
    }
export interface StoredStrengthAnswerReceipt {
  readonly ownerID: string
  readonly workoutLogID: string
  readonly questionKey: string
  readonly answer: 'yes' | 'no'
  readonly operationKey: string
  readonly acceptedAt: string
}
export type WorkoutClarification =
  | { readonly status: 'not_applicable' }
  | { readonly status: 'unanswered'; readonly questionKey: string }
  | { readonly status: 'answered'; readonly receipt: StoredStrengthAnswerReceipt }
export interface ConfirmedWorkoutStrengthFact {
  readonly anchor: ConfirmedWorkoutAnchor
  readonly classification: WorkoutClassification
  readonly calendar: WorkoutCalendar
  readonly clarification: WorkoutClarification
  readonly revision: number
}
export interface WorkoutOperationBinding {
  readonly ownerID: string
  readonly lifecycleKey: string
  readonly operationKey: string
  readonly originalOperationType: string
  readonly workoutLogID: string
  readonly resolution: 'sql_insert' | 'sql_replay' | 'provider_type_dedup' | 'recent6h_dedup'
}
export type WorkoutStrengthCaptureResult =
  | {
      readonly status: 'committed' | 'reuse_existing'
      readonly binding: WorkoutOperationBinding
      readonly fact: ConfirmedWorkoutStrengthFact
    }
  | {
      readonly status: 'unavailable'
      readonly reason: 'legacy_provenance_gap' | 'identity_unproved' | 'operation_key_missing'
      readonly confirmedWorkoutLogID: string | null
    }
  | {
      readonly status: 'conflict' | 'forbidden'
      readonly reason:
        | 'stale_lifecycle'
        | 'stale_workout'
        | 'mixed_owner'
        | 'source_observation_changed'
        | 'invalid_authority'
    }
export interface AnswerWorkoutStrengthInput extends WorkoutOwnerScope {
  readonly workoutLogID: string
  readonly expectedFactRevision: number
  readonly questionKey: string
  readonly answer: 'yes' | 'no'
  readonly operationKey: string
}
export type AnswerWorkoutStrengthResult =
  | {
      readonly status: 'accepted' | 'reuse_existing'
      readonly receipt: StoredStrengthAnswerReceipt
    }
  | {
      readonly status: 'conflict' | 'forbidden' | 'not_available'
      readonly reason:
        | 'answer_already_differs'
        | 'operation_content_conflict'
        | 'mixed_owner'
        | 'stale_workout'
        | 'stale_lifecycle'
        | 'stale_fact'
        | 'not_unrecognized'
    }
export interface WorkoutStrengthRepositoryPort {
  rpc(
    ...request:
      | [
          name: 'resolve_confirmed_workout_strength_capture',
          args: {
            readonly p_user_id: string
            readonly p_expected_lifecycle_key: string
            readonly p_operation_key: string
            readonly p_original_operation_type: string
          },
        ]
      | [
          name: 'answer_confirmed_workout_strength',
          args: {
            readonly p_user_id: string
            readonly p_expected_lifecycle_key: string
            readonly p_workout_log_id: string
            readonly p_expected_fact_revision: number
            readonly p_question_key: string
            readonly p_answer: 'yes' | 'no'
            readonly p_operation_key: string
          },
        ]
  ): PromiseLike<{ data: unknown; error: unknown | null }>
}
export interface WorkoutStrengthRepository {
  resolveConfirmedWorkoutStrengthCapture(
    scope: WorkoutOwnerScope,
    operationKey: string,
    originalOperationType: string,
  ): Promise<WorkoutStrengthCaptureResult>
  answerConfirmedWorkoutStrength(
    input: AnswerWorkoutStrengthInput,
  ): Promise<AnswerWorkoutStrengthResult>
}

export function createWorkoutStrengthRepository(
  port: WorkoutStrengthRepositoryPort,
): WorkoutStrengthRepository {
  return {
    async resolveConfirmedWorkoutStrengthCapture(scope, operationKey, originalOperationType) {
      // Read identity synchronously; a caller changing its scope while awaiting
      // the RPC cannot change this operation's request or response validation.
      if (!isRecord(scope)) throw new TypeError('Invalid workout strength request')
      const ownerID = scope.ownerID
      const expectedLifecycleKey = scope.expectedLifecycleKey
      if (
        !isUUID(ownerID) ||
        !isUUID(expectedLifecycleKey) ||
        typeof operationKey !== 'string' ||
        operationKey === '' ||
        !hasSQLBtrimContent(originalOperationType)
      )
        throw new TypeError('Invalid workout strength request')
      const request = { ownerID, expectedLifecycleKey }
      const rpc = port?.rpc
      if (typeof rpc !== 'function') {
        throw new TypeError('Workout strength port requires a callable rpc')
      }
      const reply: unknown = await rpc.call(port, 'resolve_confirmed_workout_strength_capture', {
        p_user_id: ownerID,
        p_expected_lifecycle_key: expectedLifecycleKey,
        p_operation_key: operationKey,
        p_original_operation_type: originalOperationType,
      })
      if (
        !isRecord(reply) ||
        !Object.hasOwn(reply, 'data') ||
        !Object.hasOwn(reply, 'error') ||
        reply.error === undefined
      )
        return invalidWire()
      if (reply.error !== null) throw new Error('Workout strength RPC failed')
      return parseResult(reply.data, request, operationKey, originalOperationType)
    },
    async answerConfirmedWorkoutStrength(input) {
      if (!isRecord(input)) throw new TypeError('Invalid workout strength request')
      const ownerID = input.ownerID
      const expectedLifecycleKey = input.expectedLifecycleKey
      const workoutLogID = input.workoutLogID
      const expectedFactRevision = input.expectedFactRevision
      const questionKey = input.questionKey
      const answer = input.answer
      const operationKey = input.operationKey
      if (
        !isUUID(ownerID) ||
        !isUUID(expectedLifecycleKey) ||
        !isUUID(workoutLogID) ||
        !Number.isInteger(expectedFactRevision) ||
        expectedFactRevision < 0 ||
        expectedFactRevision > 2147483647 ||
        !isUUID(questionKey) ||
        (answer !== 'yes' && answer !== 'no') ||
        typeof operationKey !== 'string' ||
        operationKey === ''
      )
        throw new TypeError('Invalid workout strength request')
      const request = {
        ownerID,
        expectedLifecycleKey,
        workoutLogID,
        expectedFactRevision,
        questionKey,
        answer,
        operationKey,
      }
      const rpc = port?.rpc
      if (typeof rpc !== 'function') {
        throw new TypeError('Workout strength port requires a callable rpc')
      }
      const reply: unknown = await rpc.call(port, 'answer_confirmed_workout_strength', {
        p_user_id: ownerID,
        p_expected_lifecycle_key: expectedLifecycleKey,
        p_workout_log_id: workoutLogID,
        p_expected_fact_revision: expectedFactRevision,
        p_question_key: questionKey,
        p_answer: answer,
        p_operation_key: operationKey,
      })
      if (
        !isRecord(reply) ||
        !Object.hasOwn(reply, 'data') ||
        !Object.hasOwn(reply, 'error') ||
        reply.error === undefined
      )
        return invalidWire()
      if (reply.error !== null) throw new Error('Workout strength RPC failed')
      return parseAnswerResult(reply.data, request)
    },
  }
}

function parseResult(
  value: unknown,
  scope: WorkoutOwnerScope,
  operationKey: string,
  rawType: string,
): WorkoutStrengthCaptureResult {
  if (!isRecord(value)) return invalidWire()
  if (value.status === 'committed' || value.status === 'reuse_existing') {
    shape(value, ['status', 'binding', 'fact'])
    const binding = parseBinding(value.binding, scope, operationKey, rawType)
    return { status: value.status, binding, fact: parseFact(value.fact, binding) }
  }
  if (value.status === 'unavailable') {
    shape(value, ['status', 'reason', 'confirmedWorkoutLogID'])
    const reason = value.reason
    if (
      reason !== 'legacy_provenance_gap' &&
      reason !== 'identity_unproved' &&
      reason !== 'operation_key_missing'
    )
      return invalidWire()
    const id = value.confirmedWorkoutLogID === null ? null : uuid(value.confirmedWorkoutLogID)
    return { status: 'unavailable', reason, confirmedWorkoutLogID: id }
  }
  if (value.status === 'conflict' || value.status === 'forbidden') {
    shape(value, ['status', 'reason'])
    const reason = value.reason
    if (
      reason !== 'stale_lifecycle' &&
      reason !== 'stale_workout' &&
      reason !== 'mixed_owner' &&
      reason !== 'source_observation_changed' &&
      reason !== 'invalid_authority'
    )
      return invalidWire()
    return { status: value.status, reason }
  }
  return invalidWire()
}

function parseAnswerResult(
  value: unknown,
  request: AnswerWorkoutStrengthInput,
): AnswerWorkoutStrengthResult {
  if (!isRecord(value)) return invalidWire()
  if (value.status === 'accepted' || value.status === 'reuse_existing') {
    shape(value, ['status', 'receipt'])
    const receipt = parseReceipt(value.receipt, request)
    if (receipt.questionKey !== request.questionKey || receipt.answer !== request.answer)
      return invalidWire()
    // A second operation may legitimately receive the first operation's receipt.
    return { status: value.status, receipt }
  }
  if (
    value.status === 'conflict' ||
    value.status === 'forbidden' ||
    value.status === 'not_available'
  ) {
    shape(value, ['status', 'reason'])
    const reason = value.reason
    if (
      reason !== 'answer_already_differs' &&
      reason !== 'operation_content_conflict' &&
      reason !== 'mixed_owner' &&
      reason !== 'stale_workout' &&
      reason !== 'stale_lifecycle' &&
      reason !== 'stale_fact' &&
      reason !== 'not_unrecognized'
    )
      return invalidWire()
    return { status: value.status, reason }
  }
  return invalidWire()
}

function parseBinding(
  value: unknown,
  scope: WorkoutOwnerScope,
  operationKey: string,
  rawType: string,
): WorkoutOperationBinding {
  const v = shape(value, [
    'ownerID',
    'lifecycleKey',
    'operationKey',
    'originalOperationType',
    'workoutLogID',
    'resolution',
  ])
  const ownerID = uuid(v.ownerID)
  const lifecycleKey = uuid(v.lifecycleKey)
  const key = text(v.operationKey)
  const originalOperationType = text(v.originalOperationType)
  const resolution = v.resolution
  if (
    ownerID !== scope.ownerID ||
    lifecycleKey !== scope.expectedLifecycleKey ||
    key !== operationKey ||
    originalOperationType !== rawType ||
    (resolution !== 'sql_insert' &&
      resolution !== 'sql_replay' &&
      resolution !== 'provider_type_dedup' &&
      resolution !== 'recent6h_dedup')
  )
    return invalidWire()
  return {
    ownerID,
    lifecycleKey,
    operationKey: key,
    originalOperationType,
    workoutLogID: uuid(v.workoutLogID),
    resolution,
  }
}

function parseFact(value: unknown, binding: WorkoutOperationBinding): ConfirmedWorkoutStrengthFact {
  const v = shape(value, ['anchor', 'classification', 'calendar', 'clarification', 'revision'])
  const a = shape(v.anchor, [
    'ownerID',
    'workoutLogID',
    'lifecycleKey',
    'snapshotID',
    'storedWorkoutType',
    'performedAt',
    'snapshotDate',
  ])
  const anchor: ConfirmedWorkoutAnchor = {
    ownerID: uuid(a.ownerID),
    workoutLogID: uuid(a.workoutLogID),
    lifecycleKey: uuid(a.lifecycleKey),
    snapshotID: uuid(a.snapshotID),
    storedWorkoutType: text(a.storedWorkoutType),
    performedAt: instant(a.performedAt),
    snapshotDate: civilDate(a.snapshotDate),
  }
  if (
    anchor.ownerID !== binding.ownerID ||
    anchor.workoutLogID !== binding.workoutLogID ||
    anchor.lifecycleKey !== binding.lifecycleKey ||
    !hasSQLBtrimContent(anchor.storedWorkoutType)
  )
    return invalidWire()
  const classification = parseClassification(v.classification)
  const calendar = parseCalendar(v.calendar, anchor)
  const clarification = parseClarification(v.clarification, anchor)
  const revision = v.revision
  if (classification.status === 'unrecognized') {
    if (
      (clarification.status === 'unanswered' && revision !== 0) ||
      (clarification.status === 'answered' && revision !== 1) ||
      clarification.status === 'not_applicable'
    )
      return invalidWire()
  } else if (clarification.status !== 'not_applicable' || revision !== 0) return invalidWire()
  if (revision !== 0 && revision !== 1) return invalidWire()
  return { anchor, classification, calendar, clarification, revision }
}

function parseClassification(value: unknown): WorkoutClassification {
  if (!isRecord(value)) return invalidWire()
  if (value.status === 'matched') {
    shape(value, ['status', 'observation', 'method', 'catalogue'])
    const method = value.method
    if (method !== 'active_slug' && method !== 'unique_active_display') return invalidWire()
    return {
      status: 'matched',
      observation: parseObservation(value.observation),
      method,
      catalogue: parseCatalogue(value.catalogue),
    }
  }
  if (value.status === 'unrecognized') {
    shape(value, ['status', 'observation', 'reason'])
    const reason = value.reason
    if (
      reason !== 'no_active_match' &&
      reason !== 'ambiguous_active_name' &&
      reason !== 'generic_outro'
    )
      return invalidWire()
    return { status: 'unrecognized', observation: parseObservation(value.observation), reason }
  }
  if (value.status === 'unavailable') {
    shape(value, ['status', 'reason'])
    const reason = value.reason
    if (
      reason !== 'catalogue_read_error' &&
      reason !== 'catalogue_invalid' &&
      reason !== 'catalogue_incomplete' &&
      reason !== 'legacy_provenance_gap'
    )
      return invalidWire()
    return { status: 'unavailable', reason }
  }
  return invalidWire()
}

function parseObservation(value: unknown): WorkoutCatalogueObservation {
  const v = shape(value, ['observedAt', 'matcherVersion', 'observationKey'])
  if (v.matcherVersion !== 'active_slug_then_unique_canonical_display_v1') return invalidWire()
  return {
    observedAt: instant(v.observedAt),
    matcherVersion: v.matcherVersion,
    observationKey: uuid(v.observationKey),
  }
}

function parseCatalogue(value: unknown): WorkoutCatalogueRow {
  const v = shape(value, ['id', 'slug', 'displayName', 'category', 'isActive', 'updatedAtLiteral'])
  const category = v.category
  const slug = text(v.slug)
  if (
    slug === 'outro' ||
    v.isActive !== true ||
    (category !== 'musculacao' &&
      category !== 'cardio' &&
      category !== 'esporte' &&
      category !== 'mobilidade')
  )
    return invalidWire()
  return {
    id: uuid(v.id),
    slug,
    displayName: text(v.displayName),
    category,
    isActive: true,
    updatedAtLiteral: instant(v.updatedAtLiteral),
  }
}

function parseCalendar(value: unknown, anchor: ConfirmedWorkoutAnchor): WorkoutCalendar {
  if (!isRecord(value)) return invalidWire()
  if (value.status === 'unavailable') {
    shape(value, ['status', 'reason'])
    const reason = value.reason
    if (
      reason !== 'zone_unproved' &&
      reason !== 'calendar_conflict' &&
      reason !== 'legacy_calendar_gap'
    )
      return invalidWire()
    return { status: 'unavailable', reason }
  }
  if (value.status !== 'proven') return invalidWire()
  shape(value, [
    'status',
    'performedAt',
    'localDate',
    'timeZone',
    'zoneSource',
    'zoneObservedAt',
    'snapshotID',
    'snapshotDate',
  ])
  const performedAt = instant(value.performedAt)
  const localDate = civilDate(value.localDate)
  const snapshotID = uuid(value.snapshotID)
  const snapshotDate = civilDate(value.snapshotDate)
  const timeZone = text(value.timeZone)
  if (
    performedAt !== anchor.performedAt ||
    snapshotID !== anchor.snapshotID ||
    snapshotDate !== anchor.snapshotDate ||
    localDate !== snapshotDate ||
    timeZone === '' ||
    value.zoneSource !== 'official_owner_zone_at_recording'
  )
    return invalidWire()
  return {
    status: 'proven',
    performedAt,
    localDate,
    timeZone,
    zoneSource: value.zoneSource,
    zoneObservedAt: instant(value.zoneObservedAt),
    snapshotID,
    snapshotDate,
  }
}

function parseClarification(value: unknown, anchor: ConfirmedWorkoutAnchor): WorkoutClarification {
  if (!isRecord(value)) return invalidWire()
  if (value.status === 'not_applicable') {
    shape(value, ['status'])
    return { status: 'not_applicable' }
  }
  if (value.status === 'unanswered') {
    shape(value, ['status', 'questionKey'])
    return { status: 'unanswered', questionKey: uuid(value.questionKey) }
  }
  if (value.status !== 'answered') return invalidWire()
  shape(value, ['status', 'receipt'])
  return { status: 'answered', receipt: parseReceipt(value.receipt, anchor) }
}

function parseReceipt(
  value: unknown,
  anchor: Pick<StoredStrengthAnswerReceipt, 'ownerID' | 'workoutLogID'>,
): StoredStrengthAnswerReceipt {
  const r = shape(value, [
    'ownerID',
    'workoutLogID',
    'questionKey',
    'answer',
    'operationKey',
    'acceptedAt',
  ])
  const ownerID = uuid(r.ownerID)
  const workoutLogID = uuid(r.workoutLogID)
  const answer = r.answer
  const operationKey = text(r.operationKey)
  if (
    ownerID !== anchor.ownerID ||
    workoutLogID !== anchor.workoutLogID ||
    (answer !== 'yes' && answer !== 'no') ||
    operationKey === ''
  )
    return invalidWire()
  return {
    ownerID,
    workoutLogID,
    questionKey: uuid(r.questionKey),
    answer,
    operationKey,
    acceptedAt: instant(r.acceptedAt),
  }
}

function shape(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (!exactKeys(value, keys)) return invalidWire()
  return value
}
function uuid(value: unknown): string {
  if (!isUUID(value)) return invalidWire()
  return value
}
function text(value: unknown): string {
  if (typeof value !== 'string') return invalidWire()
  return value
}
function instant(value: unknown): string {
  if (!isUTCUS6(value)) return invalidWire()
  return value
}
function civilDate(value: unknown): string {
  if (!isCivilDate(value)) return invalidWire()
  return value
}
function hasSQLBtrimContent(value: unknown): value is string {
  // PostgreSQL btrim(text) removes U+0020 only; tabs and other whitespace remain.
  return typeof value === 'string' && value.split(' ').join('') !== ''
}
function invalidWire(): never {
  throw new TypeError('Invalid workout strength reply')
}
