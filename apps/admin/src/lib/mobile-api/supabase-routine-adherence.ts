import { routineItemTypeSchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  MEDICATION_DISCLAIMER_KEY,
  type RoutineAdherenceRepository,
  RoutineAdherenceRepositoryError,
  type RoutineAdherenceRepositoryErrorReason,
  type RoutineAdherenceServiceDependencies,
} from './routine-adherence-service'

const uuidSchema = z.string().uuid()
const dateTimeSchema = z.string().datetime({ offset: true })
const occurrenceKeySchema = z.string().regex(/^[0-9a-f]{64}$/)
const bodyHashSchema = z.string().regex(/^[0-9a-f]{64}$/)
const actionStatusSchema = z.enum(['taken', 'snoozed', 'skipped'])

const actionResultSchema = z
  .object({
    adherence_log_id: uuidSchema,
    occurrence_key: occurrenceKeySchema,
    item_type: routineItemTypeSchema,
    status: actionStatusSchema,
  })
  .strict()
  .transform((value) => ({
    adherenceLogId: value.adherence_log_id,
    occurrenceKey: value.occurrence_key,
    itemType: value.item_type,
    status: value.status,
  }))

const legacyOccurrenceSchema = z.object({
  scheduled_for: dateTimeSchema,
  status: z.enum(['pending', 'taken', 'snoozed', 'skipped', 'missed']),
})

const legacyScheduleSchema = z.object({
  id: uuidSchema,
  occurrence: legacyOccurrenceSchema.nullable(),
})

const legacyItemSchema = z.object({
  id: uuidSchema,
  item_type: routineItemTypeSchema,
  schedules: z.array(legacyScheduleSchema),
})

const legacyPageSchema = z.object({
  local_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  items: z.array(legacyItemSchema),
})

const medicationDisclaimerSchema = z
  .object({
    document_key: z.literal(MEDICATION_DISCLAIMER_KEY),
    version: z.string().min(1).max(64),
    locale: z.enum(['pt-BR', 'en-US']),
    body: z.string().trim().min(1).max(4000),
    body_hash: bodyHashSchema,
    required_from: dateTimeSchema,
  })
  .strict()
  .transform((value) => ({
    documentKey: value.document_key,
    version: value.version,
    locale: value.locale,
    body: value.body,
    bodyHash: value.body_hash,
    requiredFrom: value.required_from,
  }))

const disclaimerAcceptanceSchema = z
  .object({
    document_key: z.literal(MEDICATION_DISCLAIMER_KEY),
    accepted_version: z.string().min(1).max(64),
    accepted_at: dateTimeSchema,
  })
  .strict()
  .transform((value) => ({
    documentKey: value.document_key,
    acceptedVersion: value.accepted_version,
    acceptedAt: value.accepted_at,
  }))

type RpcResult = Promise<{
  data: unknown
  error: { code?: string; message?: string } | null
}>

type UntypedRpc = (functionName: string, params: Record<string, unknown>) => RpcResult

type SafeOperation =
  | 'record'
  | 'resolve_legacy'
  | 'get_legal'
  | 'accept_legal'
  | 'parse_record'
  | 'parse_legacy'
  | 'parse_legal'
  | 'parse_acceptance'

const approvedReasons = new Set<RoutineAdherenceRepositoryErrorReason>([
  'routine_item_not_found',
  'routine_item_inactive',
  'routine_item_type_mismatch',
  'routine_occurrence_not_found',
  'routine_occurrence_ambiguous',
  'routine_transition_invalid',
  'routine_snooze_invalid',
  'routine_idempotency_conflict',
  'legal_document_not_available',
  'medication_disclaimer_version_stale',
])

const databaseMessageAliases: Readonly<Record<string, RoutineAdherenceRepositoryErrorReason>> = {
  routine_occurrence_schedule_mismatch: 'routine_occurrence_not_found',
  routine_occurrence_terminal: 'routine_transition_invalid',
  routine_occurrence_action_out_of_order: 'routine_transition_invalid',
  invalid_routine_snooze_time: 'routine_snooze_invalid',
  routine_action_idempotency_conflict: 'routine_idempotency_conflict',
  legal_document_version_mismatch: 'medication_disclaimer_version_stale',
}

const safeDatabaseCodes = new Set(['22023', '23505', '23514', '40001', 'P0002'])

function safeRequestId(requestId: string | undefined): string {
  return requestId && /^[A-Za-z0-9._:-]{8,128}$/.test(requestId) ? requestId : 'unknown'
}

function databaseReason(error: {
  code?: string
  message?: string
}): RoutineAdherenceRepositoryErrorReason | null {
  if (
    error.message &&
    approvedReasons.has(error.message as RoutineAdherenceRepositoryErrorReason)
  ) {
    return error.message as RoutineAdherenceRepositoryErrorReason
  }
  if (error.message && databaseMessageAliases[error.message]) {
    return databaseMessageAliases[error.message]
  }
  if (error.code && approvedReasons.has(error.code as RoutineAdherenceRepositoryErrorReason)) {
    return error.code as RoutineAdherenceRepositoryErrorReason
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
    if (reason) throw new RoutineAdherenceRepositoryError(reason)
  }

  const rawCode = error?.code ?? 'invalid_response'
  console.error('[mobile-routine-adherence] operation_failed', {
    request_id: requestId,
    operation,
    database_code: safeDatabaseCodes.has(rawCode) ? rawCode : 'unknown_error',
  })
  throw new RoutineAdherenceRepositoryError('internal')
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

function createRepository(supabase: ServiceClient, requestId: string): RoutineAdherenceRepository {
  const rpc = supabase.rpc.bind(supabase) as unknown as UntypedRpc

  return {
    async record(input) {
      const { data, error } = await rpc('record_routine_occurrence_action_atomic', {
        p_user_id: input.userId,
        p_item_id: input.routineItemId,
        p_expected_item_type: input.itemType,
        p_reminder_rule_id: input.input.reminder_rule_id,
        p_scheduled_for: input.input.scheduled_for,
        p_status: input.input.status,
        p_occurred_at: input.input.occurred_at,
        p_snoozed_until: input.input.snoozed_until ?? null,
        p_idempotency_key: input.idempotencyKey,
      })
      if (error) operationFailure(requestId, 'record', error)
      return parseResult(actionResultSchema, data, 'parse_record', requestId)
    },

    async resolveLegacyOccurrence(input) {
      const { data, error } = await rpc('list_mobile_routine_items', {
        p_user_id: input.userId,
        p_item_type: input.itemType,
        p_include_archived: false,
        p_now: input.occurredAt,
      })
      if (error) operationFailure(requestId, 'resolve_legacy', error)
      const page = parseResult(legacyPageSchema, data, 'parse_legacy', requestId)
      const eligible = page.items
        .filter((item) => item.id === input.routineItemId && item.item_type === input.itemType)
        .flatMap((item) => item.schedules)
        .filter(
          (schedule) =>
            schedule.occurrence &&
            schedule.occurrence.status !== 'taken' &&
            schedule.occurrence.status !== 'skipped',
        )

      if (eligible.length === 0) return { action: 'not_found' }
      if (eligible.length > 1) return { action: 'ambiguous' }
      const schedule = eligible[0]
      if (!schedule?.occurrence) return { action: 'not_found' }
      return {
        action: 'resolved',
        reminderRuleId: schedule.id,
        scheduledFor: schedule.occurrence.scheduled_for,
      }
    },

    async getMedicationDisclaimer(userId) {
      const { data, error } = await rpc('get_mobile_legal_document', {
        p_user_id: userId,
        p_document_key: MEDICATION_DISCLAIMER_KEY,
      })
      if (error) operationFailure(requestId, 'get_legal', error)
      return parseResult(medicationDisclaimerSchema, data, 'parse_legal', requestId)
    },

    async acceptMedicationDisclaimer(input) {
      const { data, error } = await rpc('accept_mobile_legal_document', {
        p_user_id: input.userId,
        p_document_key: input.documentKey,
        p_version: input.version,
        p_body_hash: input.bodyHash,
        p_idempotency_key: input.idempotencyKey,
      })
      if (error) operationFailure(requestId, 'accept_legal', error)
      return parseResult(disclaimerAcceptanceSchema, data, 'parse_acceptance', requestId)
    },
  }
}

export function createSupabaseRoutineAdherenceDependencies(
  supabase: ServiceClient,
  options: { requestId?: string } = {},
): RoutineAdherenceServiceDependencies {
  return { repository: createRepository(supabase, safeRequestId(options.requestId)) }
}
