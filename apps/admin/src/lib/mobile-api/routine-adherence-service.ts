import type {
  MedicationDisclaimerAcceptanceInput,
  RoutineActionInput,
  RoutineItemType,
} from '@mpp/core'
import type { MobileAuthContext } from './auth'
import type { MarkRoutineTakenInput } from './contracts'
import { MobileApiError } from './http'

export const MEDICATION_DISCLAIMER_KEY = 'medication_reminder_disclaimer'

export interface RoutineActionResult {
  adherenceLogId: string
  occurrenceKey: string
  itemType: RoutineItemType
  status: RoutineActionInput['status']
}

export interface RecordRoutineActionCommand {
  userId: string
  routineItemId: string
  itemType: RoutineItemType
  input: RoutineActionInput
  idempotencyKey: string
}

export interface LegacyTakenCommand {
  userId: string
  routineItemId: string
  itemType: RoutineItemType
  occurredAt: string
}

export interface MedicationDisclaimerRecord {
  documentKey: string
  version: string
  locale: string
  body: string
  bodyHash: string
  requiredFrom: string
}

export interface AcceptDisclaimerCommand {
  userId: string
  documentKey: string
  version: string
  bodyHash: string
  idempotencyKey: string
}

export interface DisclaimerAcceptanceRecord {
  documentKey: string
  acceptedVersion: string
  acceptedAt: string
}

export interface RoutineAdherenceRepository {
  record(input: RecordRoutineActionCommand): Promise<RoutineActionResult>
  resolveLegacyOccurrence(
    input: LegacyTakenCommand,
  ): Promise<
    | { action: 'resolved'; reminderRuleId: string; scheduledFor: string }
    | { action: 'not_found' }
    | { action: 'ambiguous' }
  >
  getMedicationDisclaimer(userId: string): Promise<MedicationDisclaimerRecord>
  acceptMedicationDisclaimer(input: AcceptDisclaimerCommand): Promise<DisclaimerAcceptanceRecord>
}

export interface RoutineAdherenceServiceDependencies {
  repository: RoutineAdherenceRepository
}

export type RoutineAdherenceRepositoryErrorReason =
  | 'routine_item_not_found'
  | 'routine_item_inactive'
  | 'routine_item_type_mismatch'
  | 'routine_occurrence_not_found'
  | 'routine_occurrence_ambiguous'
  | 'routine_transition_invalid'
  | 'routine_snooze_invalid'
  | 'routine_idempotency_conflict'
  | 'legal_document_not_available'
  | 'medication_disclaimer_version_stale'
  | 'internal'

export class RoutineAdherenceRepositoryError extends Error {
  constructor(readonly reason: RoutineAdherenceRepositoryErrorReason) {
    super(reason)
    this.name = 'RoutineAdherenceRepositoryError'
  }
}

export interface RoutineActionDto {
  adherence_log_id: string
  occurrence_key: string
  item_type: RoutineItemType
  status: RoutineActionInput['status']
}

export interface MedicationDisclaimerDto {
  document_key: string
  version: string
  locale: string
  body: string
  body_hash: string
  required_from: string
}

export interface DisclaimerAcceptanceDto {
  document_key: string
  version: string
  accepted_at: string
}

function itemNotFound(): MobileApiError {
  return new MobileApiError(404, 'routine_item_not_found', 'Routine item not found')
}

function mapRepositoryError(error: unknown): MobileApiError {
  if (!(error instanceof RoutineAdherenceRepositoryError)) {
    return new MobileApiError(500, 'internal_error', 'Unexpected server error')
  }

  switch (error.reason) {
    case 'routine_item_not_found':
    case 'routine_item_inactive':
    case 'routine_item_type_mismatch':
    case 'routine_occurrence_not_found':
      return itemNotFound()
    case 'routine_occurrence_ambiguous':
      return new MobileApiError(
        409,
        'routine_occurrence_ambiguous',
        'More than one routine occurrence is eligible',
      )
    case 'routine_transition_invalid':
      return new MobileApiError(
        409,
        'routine_transition_invalid',
        'Routine occurrence transition is not allowed',
      )
    case 'routine_snooze_invalid':
      return new MobileApiError(422, 'routine_snooze_invalid', 'Routine snooze is invalid')
    case 'routine_idempotency_conflict':
      return new MobileApiError(
        409,
        'idempotency_key_conflict',
        'Idempotency-Key was already used for another request',
      )
    case 'legal_document_not_available':
      return new MobileApiError(
        404,
        'legal_document_not_available',
        'Legal document is not available',
      )
    case 'medication_disclaimer_version_stale':
      return new MobileApiError(
        409,
        'medication_disclaimer_version_stale',
        'Medication disclaimer version changed',
      )
    case 'internal':
      return new MobileApiError(500, 'internal_error', 'Unexpected server error')
  }
}

async function repositoryCall<T>(operation: () => Promise<T>): Promise<T> {
  try {
    return await operation()
  } catch (error) {
    throw mapRepositoryError(error)
  }
}

function validateOccurredAt(occurredAt: string, now: Date): void {
  const timestamp = Date.parse(occurredAt)
  const futureBoundary = now.getTime() + 5 * 60 * 1000
  const pastBoundary = now.getTime() - 7 * 24 * 60 * 60 * 1000
  if (!Number.isFinite(timestamp) || timestamp < pastBoundary || timestamp > futureBoundary) {
    throw new MobileApiError(
      422,
      'occurred_at_out_of_range',
      'occurred_at must be within the supported offline window',
    )
  }
}

function localDateAt(timestamp: string, timezone: string): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(timestamp))
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]))
  return `${values.year}-${values.month}-${values.day}`
}

function validateSnooze(input: RoutineActionInput, timezone: string | null): void {
  if (input.status !== 'snoozed') return

  const occurredAt = Date.parse(input.occurred_at)
  const snoozedUntil = Date.parse(input.snoozed_until as string)
  try {
    if (
      !timezone ||
      !Number.isFinite(snoozedUntil) ||
      snoozedUntil <= occurredAt ||
      localDateAt(input.scheduled_for, timezone) !==
        localDateAt(input.snoozed_until as string, timezone)
    ) {
      throw new Error('invalid snooze')
    }
  } catch {
    throw new MobileApiError(422, 'routine_snooze_invalid', 'Routine snooze is invalid')
  }
}

function actionDto(result: RoutineActionResult): RoutineActionDto {
  return {
    adherence_log_id: result.adherenceLogId,
    occurrence_key: result.occurrenceKey,
    item_type: result.itemType,
    status: result.status,
  }
}

export async function recordRoutineAction(
  dependencies: RoutineAdherenceServiceDependencies,
  auth: MobileAuthContext,
  itemType: RoutineItemType,
  routineItemId: string,
  input: RoutineActionInput,
  idempotencyKey: string,
  now = new Date(),
): Promise<RoutineActionDto> {
  validateOccurredAt(input.occurred_at, now)
  validateSnooze(input, auth.patient.timezone)
  return actionDto(
    await repositoryCall(() =>
      dependencies.repository.record({
        userId: auth.userId,
        routineItemId,
        itemType,
        input,
        idempotencyKey,
      }),
    ),
  )
}

export async function recordLegacyRoutineTaken(
  dependencies: RoutineAdherenceServiceDependencies,
  auth: MobileAuthContext,
  routineItemId: string,
  itemType: RoutineItemType,
  input: MarkRoutineTakenInput,
  idempotencyKey: string,
  now = new Date(),
): Promise<RoutineActionDto> {
  validateOccurredAt(input.occurred_at, now)
  const resolution = await repositoryCall(() =>
    dependencies.repository.resolveLegacyOccurrence({
      userId: auth.userId,
      routineItemId,
      itemType,
      occurredAt: input.occurred_at,
    }),
  )
  if (resolution.action === 'not_found') throw itemNotFound()
  if (resolution.action === 'ambiguous') {
    throw new MobileApiError(
      409,
      'routine_occurrence_ambiguous',
      'More than one routine occurrence is eligible',
    )
  }

  return recordRoutineAction(
    dependencies,
    auth,
    itemType,
    routineItemId,
    {
      status: 'taken',
      reminder_rule_id: resolution.reminderRuleId,
      scheduled_for: resolution.scheduledFor,
      occurred_at: input.occurred_at,
    },
    idempotencyKey,
    now,
  )
}

export async function getMedicationDisclaimer(
  dependencies: RoutineAdherenceServiceDependencies,
  auth: MobileAuthContext,
): Promise<MedicationDisclaimerDto> {
  const record = await repositoryCall(() =>
    dependencies.repository.getMedicationDisclaimer(auth.userId),
  )
  return {
    document_key: record.documentKey,
    version: record.version,
    locale: record.locale,
    body: record.body,
    body_hash: record.bodyHash,
    required_from: record.requiredFrom,
  }
}

export async function acceptMedicationDisclaimer(
  dependencies: RoutineAdherenceServiceDependencies,
  auth: MobileAuthContext,
  input: MedicationDisclaimerAcceptanceInput,
  idempotencyKey: string,
): Promise<DisclaimerAcceptanceDto> {
  const record = await repositoryCall(() =>
    dependencies.repository.acceptMedicationDisclaimer({
      userId: auth.userId,
      documentKey: MEDICATION_DISCLAIMER_KEY,
      version: input.version,
      bodyHash: input.body_hash,
      idempotencyKey,
    }),
  )
  return {
    document_key: record.documentKey,
    version: record.acceptedVersion,
    accepted_at: record.acceptedAt,
  }
}
