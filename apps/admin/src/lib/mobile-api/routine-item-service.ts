import type {
  RoutineItemCreateInput,
  RoutineItemListQuery,
  RoutineItemPatchInput,
  RoutineItemType,
  RoutineOrigin,
  RoutinePublicStatus,
  RoutineStoredStatus,
} from '@mpp/core'
import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'

export interface RoutineOccurrenceRecord {
  occurrenceKey: string
  scheduledFor: string
  status: RoutinePublicStatus
  lastActionAt: string | null
  snoozedUntil: string | null
}

export interface RoutineScheduleRecord {
  id: string
  localTime: string
  weekdays: number[]
  occurrence: RoutineOccurrenceRecord | null
}

export interface RoutineItemListRecord {
  id: string
  itemType: RoutineItemType
  name: string
  doseText: string
  origin: RoutineOrigin
  remindersEnabled: boolean
  active: boolean
  archivedAt: string | null
  version: number
  createdAt: string
  updatedAt: string
  schedules: RoutineScheduleRecord[]
}

export interface RoutineItemRecord {
  routineItemId: string
  version: number
  archivedAt: string | null
}

export interface RoutineItemPageRecord {
  localDate: string
  items: RoutineItemListRecord[]
}

export interface RoutineHistoryRecord {
  id: string
  routineItemId: string
  itemType: RoutineItemType
  status: RoutineStoredStatus
  reminderRuleId: string
  occurrenceKey: string
  scheduledFor: string
  occurredAt: string
  snoozedUntil: string | null
  source: 'patient' | 'system' | 'offline_sync'
  supersedesLogId: string | null
  createdAt: string
}

export interface RoutineHistoryPageRecord {
  items: RoutineHistoryRecord[]
  nextCursor: string | null
}

export interface ListRoutineItemsCommand {
  userId: string
  itemType: RoutineItemType
  includeArchived: boolean
  now: string
}

export interface CreateRoutineItemCommand {
  userId: string
  itemType: RoutineItemType
  input: RoutineItemCreateInput
  idempotencyKey: string
  requestHash: string
}

export interface UpdateRoutineItemCommand {
  userId: string
  itemType: RoutineItemType
  routineItemId: string
  input: RoutineItemPatchInput
  idempotencyKey: string
  requestHash: string
}

export interface ArchiveRoutineItemCommand {
  userId: string
  itemType: RoutineItemType
  routineItemId: string
  idempotencyKey: string
  requestHash: string
}

export interface RoutineHistoryCommand {
  userId: string
  itemType: RoutineItemType
  routineItemId: string
  limit: number
  cursor?: string
}

export interface RoutineItemRepository {
  list(input: ListRoutineItemsCommand): Promise<RoutineItemPageRecord>
  create(input: CreateRoutineItemCommand): Promise<RoutineItemRecord>
  update(input: UpdateRoutineItemCommand): Promise<RoutineItemRecord>
  archive(input: ArchiveRoutineItemCommand): Promise<RoutineItemRecord>
  history(input: RoutineHistoryCommand): Promise<RoutineHistoryPageRecord>
}

export interface RoutineItemServiceDependencies {
  repository: RoutineItemRepository
}

export type RoutineItemRepositoryErrorReason =
  | 'routine_item_not_found'
  | 'routine_item_inactive'
  | 'routine_item_type_mismatch'
  | 'routine_item_version_conflict'
  | 'routine_schedule_invalid'
  | 'routine_schedule_conflict'
  | 'routine_occurrence_not_found'
  | 'routine_occurrence_ambiguous'
  | 'routine_transition_invalid'
  | 'routine_snooze_invalid'
  | 'routine_idempotency_conflict'
  | 'medication_disclaimer_required'
  | 'medication_disclaimer_version_stale'
  | 'invalid_cursor'
  | 'internal'

export class RoutineItemRepositoryError extends Error {
  constructor(readonly reason: RoutineItemRepositoryErrorReason) {
    super(reason)
    this.name = 'RoutineItemRepositoryError'
  }
}

export interface RoutineOccurrenceDto {
  scheduled_for: string
  status: RoutinePublicStatus
  last_action_at: string | null
  snoozed_until: string | null
}

export interface RoutineScheduleDto {
  id: string
  local_time: string
  weekdays: number[]
  occurrence: RoutineOccurrenceDto | null
}

export interface RoutineItemDto {
  id: string
  item_type: RoutineItemType
  name: string
  dose_text: string
  origin: RoutineOrigin
  reminders_enabled: boolean
  active: boolean
  archived_at: string | null
  version: number
  created_at: string
  updated_at: string
  frequency_summary: { times_per_week: number }
  schedules: RoutineScheduleDto[]
}

export interface RoutineItemListDto {
  local_date: string
  items: RoutineItemDto[]
}

export interface RoutineItemMutationDto {
  routine_item_id: string
  version: number
  archived_at?: string
}

export interface RoutineHistoryItemDto {
  id: string
  routine_item_id: string
  item_type: RoutineItemType
  status: RoutineStoredStatus
  reminder_rule_id: string
  scheduled_for: string
  occurred_at: string
  snoozed_until: string | null
  source: 'patient' | 'system' | 'offline_sync'
  supersedes_log_id: string | null
  created_at: string
}

export interface RoutineHistoryPageDto {
  items: RoutineHistoryItemDto[]
  next_cursor: string | null
}

function itemNotFound(): MobileApiError {
  return new MobileApiError(404, 'routine_item_not_found', 'Routine item not found')
}

function internalError(): MobileApiError {
  return new MobileApiError(500, 'internal_error', 'Unexpected server error')
}

function mapRepositoryError(error: unknown): MobileApiError {
  if (!(error instanceof RoutineItemRepositoryError)) return internalError()

  switch (error.reason) {
    case 'routine_item_not_found':
    case 'routine_item_inactive':
    case 'routine_item_type_mismatch':
    case 'routine_occurrence_not_found':
    case 'routine_occurrence_ambiguous':
      return itemNotFound()
    case 'routine_item_version_conflict':
      return new MobileApiError(
        409,
        'routine_item_version_conflict',
        'Routine item version changed',
      )
    case 'routine_schedule_conflict':
      return new MobileApiError(
        409,
        'routine_schedule_conflict',
        'Routine schedule conflicts with an existing schedule',
      )
    case 'routine_transition_invalid':
      return new MobileApiError(
        409,
        'routine_transition_invalid',
        'Routine occurrence transition is not allowed',
      )
    case 'routine_idempotency_conflict':
      return new MobileApiError(
        409,
        'idempotency_key_conflict',
        'Idempotency-Key was already used for another request',
      )
    case 'routine_schedule_invalid':
      return new MobileApiError(422, 'routine_schedule_invalid', 'Routine schedule is invalid')
    case 'routine_snooze_invalid':
      return new MobileApiError(422, 'routine_snooze_invalid', 'Routine snooze is invalid')
    case 'medication_disclaimer_required':
    case 'medication_disclaimer_version_stale':
      return new MobileApiError(
        428,
        'medication_disclaimer_required',
        'Medication disclaimer acceptance is required',
      )
    case 'invalid_cursor':
      return new MobileApiError(422, 'validation_failed', 'Request validation failed', {
        fields: [{ path: 'cursor', code: 'custom', message: 'Cursor is invalid' }],
      })
    case 'internal':
      return internalError()
  }
}

async function repositoryCall<T>(operation: () => Promise<T>): Promise<T> {
  try {
    return await operation()
  } catch (error) {
    throw mapRepositoryError(error)
  }
}

function mapOccurrence(record: RoutineOccurrenceRecord | null): RoutineOccurrenceDto | null {
  if (!record) return null
  return {
    scheduled_for: record.scheduledFor,
    status: record.status,
    last_action_at: record.lastActionAt,
    snoozed_until: record.snoozedUntil,
  }
}

function mapItem(record: RoutineItemListRecord): RoutineItemDto {
  return {
    id: record.id,
    item_type: record.itemType,
    name: record.name,
    dose_text: record.doseText,
    origin: record.origin,
    reminders_enabled: record.remindersEnabled,
    active: record.active,
    archived_at: record.archivedAt,
    version: record.version,
    created_at: record.createdAt,
    updated_at: record.updatedAt,
    frequency_summary: {
      times_per_week: record.schedules.reduce(
        (total, schedule) => total + schedule.weekdays.length,
        0,
      ),
    },
    schedules: record.schedules.map((schedule) => ({
      id: schedule.id,
      local_time: schedule.localTime,
      weekdays: schedule.weekdays,
      occurrence: mapOccurrence(schedule.occurrence),
    })),
  }
}

function mapMutation(record: RoutineItemRecord): RoutineItemMutationDto {
  return {
    routine_item_id: record.routineItemId,
    version: record.version,
    ...(record.archivedAt ? { archived_at: record.archivedAt } : {}),
  }
}

async function requireTypedActiveItem(
  dependencies: RoutineItemServiceDependencies,
  auth: MobileAuthContext,
  itemType: RoutineItemType,
  routineItemId: string,
  now: Date,
): Promise<void> {
  const page = await repositoryCall(() =>
    dependencies.repository.list({
      userId: auth.userId,
      itemType,
      includeArchived: false,
      now: now.toISOString(),
    }),
  )
  if (!page.items.some((item) => item.id === routineItemId)) throw itemNotFound()
}

export async function listRoutineItems(
  dependencies: RoutineItemServiceDependencies,
  auth: MobileAuthContext,
  itemType: RoutineItemType,
  query: RoutineItemListQuery,
  now = new Date(),
): Promise<RoutineItemListDto> {
  const page = await repositoryCall(() =>
    dependencies.repository.list({
      userId: auth.userId,
      itemType,
      includeArchived: query.include_archived,
      now: now.toISOString(),
    }),
  )
  return { local_date: page.localDate, items: page.items.map(mapItem) }
}

export async function createRoutineItem(
  dependencies: RoutineItemServiceDependencies,
  auth: MobileAuthContext,
  itemType: RoutineItemType,
  input: RoutineItemCreateInput,
  idempotencyKey: string,
  requestHash: string,
): Promise<RoutineItemMutationDto> {
  return mapMutation(
    await repositoryCall(() =>
      dependencies.repository.create({
        userId: auth.userId,
        itemType,
        input,
        idempotencyKey,
        requestHash,
      }),
    ),
  )
}

export async function updateRoutineItem(
  dependencies: RoutineItemServiceDependencies,
  auth: MobileAuthContext,
  itemType: RoutineItemType,
  routineItemId: string,
  input: RoutineItemPatchInput,
  idempotencyKey: string,
  requestHash: string,
  now = new Date(),
): Promise<RoutineItemMutationDto> {
  await requireTypedActiveItem(dependencies, auth, itemType, routineItemId, now)
  return mapMutation(
    await repositoryCall(() =>
      dependencies.repository.update({
        userId: auth.userId,
        itemType,
        routineItemId,
        input,
        idempotencyKey,
        requestHash,
      }),
    ),
  )
}

export async function archiveRoutineItem(
  dependencies: RoutineItemServiceDependencies,
  auth: MobileAuthContext,
  itemType: RoutineItemType,
  routineItemId: string,
  idempotencyKey: string,
  requestHash: string,
  now = new Date(),
): Promise<RoutineItemMutationDto> {
  await requireTypedActiveItem(dependencies, auth, itemType, routineItemId, now)
  return mapMutation(
    await repositoryCall(() =>
      dependencies.repository.archive({
        userId: auth.userId,
        itemType,
        routineItemId,
        idempotencyKey,
        requestHash,
      }),
    ),
  )
}

export async function listRoutineItemHistory(
  dependencies: RoutineItemServiceDependencies,
  auth: MobileAuthContext,
  itemType: RoutineItemType,
  routineItemId: string,
  query: { limit: number; cursor?: string },
): Promise<RoutineHistoryPageDto> {
  const page = await repositoryCall(() =>
    dependencies.repository.history({
      userId: auth.userId,
      itemType,
      routineItemId,
      limit: query.limit,
      ...(query.cursor ? { cursor: query.cursor } : {}),
    }),
  )
  return {
    items: page.items.map((record) => ({
      id: record.id,
      routine_item_id: record.routineItemId,
      item_type: record.itemType,
      status: record.status,
      reminder_rule_id: record.reminderRuleId,
      scheduled_for: record.scheduledFor,
      occurred_at: record.occurredAt,
      snoozed_until: record.snoozedUntil,
      source: record.source,
      supersedes_log_id: record.supersedesLogId,
      created_at: record.createdAt,
    })),
    next_cursor: page.nextCursor,
  }
}
