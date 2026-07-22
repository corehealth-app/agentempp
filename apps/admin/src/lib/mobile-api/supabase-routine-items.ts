import {
  decodeRoutineHistoryCursor,
  encodeRoutineHistoryCursor,
  routineItemTypeSchema,
  routineOriginSchema,
  routineStoredStatusSchema,
} from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type RoutineItemRepository,
  RoutineItemRepositoryError,
  type RoutineItemRepositoryErrorReason,
  type RoutineItemServiceDependencies,
} from './routine-item-service'

const uuidSchema = z.string().uuid()
const dateTimeSchema = z.string().datetime({ offset: true })
const occurrenceKeySchema = z.string().regex(/^[0-9a-f]{64}$/)
const localTimeSchema = z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/)

const occurrenceSchema = z
  .object({
    occurrence_key: occurrenceKeySchema,
    scheduled_for: dateTimeSchema,
    status: z.enum(['pending', 'taken', 'snoozed', 'skipped', 'missed']),
    last_action_at: dateTimeSchema.nullable(),
    snoozed_until: dateTimeSchema.nullable(),
  })
  .strict()
  .transform((value) => ({
    occurrenceKey: value.occurrence_key,
    scheduledFor: value.scheduled_for,
    status: value.status,
    lastActionAt: value.last_action_at,
    snoozedUntil: value.snoozed_until,
  }))

const scheduleSchema = z
  .object({
    id: uuidSchema,
    local_time: localTimeSchema,
    weekdays: z.array(z.number().int().min(0).max(6)).min(1).max(7),
    occurrence: occurrenceSchema.nullable(),
  })
  .strict()
  .transform((value) => ({
    id: value.id,
    localTime: value.local_time,
    weekdays: value.weekdays,
    occurrence: value.occurrence,
  }))

const listItemSchema = z
  .object({
    id: uuidSchema,
    item_type: routineItemTypeSchema,
    name: z.string().trim().min(1).max(200),
    dose_text: z.string().trim().min(1).max(120),
    origin: routineOriginSchema,
    reminders_enabled: z.boolean(),
    active: z.boolean(),
    archived_at: dateTimeSchema.nullable(),
    version: z.number().int().positive(),
    created_at: dateTimeSchema,
    updated_at: dateTimeSchema,
    schedules: z.array(scheduleSchema),
  })
  .strict()
  .transform((value) => ({
    id: value.id,
    itemType: value.item_type,
    name: value.name,
    doseText: value.dose_text,
    origin: value.origin,
    remindersEnabled: value.reminders_enabled,
    active: value.active,
    archivedAt: value.archived_at,
    version: value.version,
    createdAt: value.created_at,
    updatedAt: value.updated_at,
    schedules: value.schedules,
  }))

const listPageSchema = z
  .object({
    local_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    items: z.array(listItemSchema),
  })
  .strict()
  .transform((value) => ({ localDate: value.local_date, items: value.items }))

const mutationSchema = z
  .object({
    routine_item_id: uuidSchema,
    version: z.number().int().positive(),
  })
  .strict()
  .transform((value) => ({
    routineItemId: value.routine_item_id,
    version: value.version,
    archivedAt: null,
  }))

const archiveSchema = z
  .object({
    routine_item_id: uuidSchema,
    version: z.number().int().positive(),
    archived_at: dateTimeSchema,
  })
  .strict()
  .transform((value) => ({
    routineItemId: value.routine_item_id,
    version: value.version,
    archivedAt: value.archived_at,
  }))

const historyItemSchema = z
  .object({
    id: uuidSchema,
    routine_item_id: uuidSchema,
    item_type: routineItemTypeSchema,
    status: routineStoredStatusSchema,
    reminder_rule_id: uuidSchema,
    occurrence_key: occurrenceKeySchema,
    scheduled_for: dateTimeSchema,
    occurred_at: dateTimeSchema,
    snoozed_until: dateTimeSchema.nullable(),
    source: z.enum(['patient', 'system', 'offline_sync']),
    supersedes_log_id: uuidSchema.nullable(),
    created_at: dateTimeSchema,
  })
  .strict()
  .transform((value) => ({
    id: value.id,
    routineItemId: value.routine_item_id,
    itemType: value.item_type,
    status: value.status,
    reminderRuleId: value.reminder_rule_id,
    occurrenceKey: value.occurrence_key,
    scheduledFor: value.scheduled_for,
    occurredAt: value.occurred_at,
    snoozedUntil: value.snoozed_until,
    source: value.source,
    supersedesLogId: value.supersedes_log_id,
    createdAt: value.created_at,
  }))

const historyCursorTupleSchema = z
  .object({ occurred_at: dateTimeSchema, log_id: uuidSchema })
  .strict()

const historyPageSchema = z
  .object({
    items: z.array(historyItemSchema),
    next_cursor: historyCursorTupleSchema.nullable(),
  })
  .strict()

type RpcResult = Promise<{
  data: unknown
  error: { code?: string; message?: string } | null
}>

type UntypedRpc = (functionName: string, params: Record<string, unknown>) => RpcResult

type SafeOperation =
  | 'list'
  | 'create'
  | 'update'
  | 'archive'
  | 'history'
  | 'parse_list'
  | 'parse_create'
  | 'parse_update'
  | 'parse_archive'
  | 'parse_history'

const approvedReasons = new Set<RoutineItemRepositoryErrorReason>([
  'routine_item_not_found',
  'routine_item_inactive',
  'routine_item_type_mismatch',
  'routine_item_version_conflict',
  'routine_schedule_invalid',
  'routine_schedule_conflict',
  'routine_occurrence_not_found',
  'routine_occurrence_ambiguous',
  'routine_transition_invalid',
  'routine_snooze_invalid',
  'routine_idempotency_conflict',
  'medication_disclaimer_required',
  'medication_disclaimer_version_stale',
])

const databaseMessageAliases: Readonly<Record<string, RoutineItemRepositoryErrorReason>> = {
  routine_mutation_idempotency_conflict: 'routine_idempotency_conflict',
  routine_action_idempotency_conflict: 'routine_idempotency_conflict',
  medication_legal_acceptance_required: 'medication_disclaimer_required',
  legal_document_version_mismatch: 'medication_disclaimer_version_stale',
  invalid_routine_schedules: 'routine_schedule_invalid',
  duplicate_routine_schedule: 'routine_schedule_invalid',
  invalid_routine_item_payload: 'routine_schedule_invalid',
  invalid_routine_item_patch: 'routine_schedule_invalid',
  routine_occurrence_schedule_mismatch: 'routine_occurrence_not_found',
  routine_occurrence_terminal: 'routine_transition_invalid',
  routine_occurrence_action_out_of_order: 'routine_transition_invalid',
  invalid_routine_snooze_time: 'routine_snooze_invalid',
}

const safeDatabaseCodes = new Set(['22023', '23505', '23514', '40001', 'P0002', 'invalid_response'])

function safeRequestId(requestId: string | undefined): string {
  return requestId && /^[A-Za-z0-9._:-]{8,128}$/.test(requestId) ? requestId : 'unknown'
}

function databaseReason(error: {
  code?: string
  message?: string
}): RoutineItemRepositoryErrorReason | null {
  if (error.message && approvedReasons.has(error.message as RoutineItemRepositoryErrorReason)) {
    return error.message as RoutineItemRepositoryErrorReason
  }
  if (error.message && databaseMessageAliases[error.message]) {
    return databaseMessageAliases[error.message]
  }
  if (error.code && approvedReasons.has(error.code as RoutineItemRepositoryErrorReason)) {
    return error.code as RoutineItemRepositoryErrorReason
  }
  if (error.code === 'P0002') return 'routine_item_not_found'
  return null
}

function operationFailure(
  requestId: string,
  operation: SafeOperation,
  error?: { code?: string; message?: string } | null,
): never {
  if (error) {
    const reason = databaseReason(error)
    if (reason) throw new RoutineItemRepositoryError(reason)
  }

  const rawCode = error?.code ?? 'invalid_response'
  console.error('[mobile-routine-items] operation_failed', {
    request_id: requestId,
    operation,
    database_code: safeDatabaseCodes.has(rawCode) ? rawCode : 'unknown_error',
  })
  throw new RoutineItemRepositoryError('internal')
}

function parseResult<T>(
  schema: z.ZodType<T, z.ZodTypeDef, unknown>,
  value: unknown,
  operation: SafeOperation,
  requestId: string,
): T {
  const parsed = schema.safeParse(value)
  if (!parsed.success) operationFailure(requestId, operation)
  return parsed.data
}

function createRepository(supabase: ServiceClient, requestId: string): RoutineItemRepository {
  const rpc = supabase.rpc.bind(supabase) as unknown as UntypedRpc

  return {
    async list(input) {
      const { data, error } = await rpc('list_mobile_routine_items', {
        p_user_id: input.userId,
        p_item_type: input.itemType,
        p_include_archived: input.includeArchived,
        p_now: input.now,
      })
      if (error) operationFailure(requestId, 'list', error)
      return parseResult(listPageSchema, data, 'parse_list', requestId)
    },

    async create(input) {
      const { data, error } = await rpc('create_mobile_routine_item', {
        p_user_id: input.userId,
        p_item_type: input.itemType,
        p_payload: input.input,
        p_idempotency_key: input.idempotencyKey,
        p_request_hash: input.requestHash,
      })
      if (error) operationFailure(requestId, 'create', error)
      return parseResult(mutationSchema, data, 'parse_create', requestId)
    },

    async update(input) {
      const { expected_version, ...patch } = input.input
      const { data, error } = await rpc('update_mobile_routine_item', {
        p_user_id: input.userId,
        p_item_id: input.routineItemId,
        p_expected_version: expected_version,
        p_patch: patch,
        p_idempotency_key: input.idempotencyKey,
        p_request_hash: input.requestHash,
      })
      if (error) operationFailure(requestId, 'update', error)
      return parseResult(mutationSchema, data, 'parse_update', requestId)
    },

    async archive(input) {
      const { data, error } = await rpc('archive_mobile_routine_item', {
        p_user_id: input.userId,
        p_item_id: input.routineItemId,
        p_idempotency_key: input.idempotencyKey,
        p_request_hash: input.requestHash,
      })
      if (error) operationFailure(requestId, 'archive', error)
      return parseResult(archiveSchema, data, 'parse_archive', requestId)
    },

    async history(input) {
      let cursor: { occurredAt: string; logId: string } | null = null
      if (input.cursor) {
        try {
          cursor = decodeRoutineHistoryCursor(input.cursor)
        } catch {
          throw new RoutineItemRepositoryError('invalid_cursor')
        }
      }

      const { data, error } = await rpc('list_mobile_routine_history', {
        p_user_id: input.userId,
        p_item_id: input.routineItemId,
        p_item_type: input.itemType,
        p_limit: input.limit,
        p_before_occurred_at: cursor?.occurredAt ?? null,
        p_before_log_id: cursor?.logId ?? null,
      })
      if (error) operationFailure(requestId, 'history', error)
      const page = parseResult(historyPageSchema, data, 'parse_history', requestId)
      return {
        items: page.items,
        nextCursor: page.next_cursor
          ? encodeRoutineHistoryCursor({
              occurredAt: page.next_cursor.occurred_at,
              logId: page.next_cursor.log_id,
            })
          : null,
      }
    },
  }
}

export function createSupabaseRoutineItemDependencies(
  supabase: ServiceClient,
  options: { requestId?: string } = {},
): RoutineItemServiceDependencies {
  return { repository: createRepository(supabase, safeRequestId(options.requestId)) }
}
