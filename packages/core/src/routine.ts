import { z } from 'zod'

export type RoutineItemType = 'supplement' | 'medication'
export type RoutineOrigin = 'user' | 'professional' | 'protocol' | 'other'
export type RoutineStoredStatus = 'taken' | 'snoozed' | 'skipped' | 'missed'
export type RoutinePublicStatus = 'pending' | RoutineStoredStatus
export type RoutinePreviewMode = 'private' | 'name' | 'name_and_dose'

export interface RoutineScheduleInput {
  local_time: string
  weekdays: number[]
}

export interface RoutineItemCreateInput {
  name: string
  dose_text: string
  origin: RoutineOrigin
  reminders_enabled: boolean
  schedules: RoutineScheduleInput[]
}

export interface RoutineItemPatchInput {
  expected_version: number
  name?: string
  dose_text?: string
  origin?: RoutineOrigin
  reminders_enabled?: boolean
  schedules?: RoutineScheduleInput[]
}

export interface RoutineActionInput {
  status: 'taken' | 'snoozed' | 'skipped'
  reminder_rule_id: string
  scheduled_for: string
  occurred_at: string
  snoozed_until?: string
}

export interface RoutineHistoryCursor {
  occurredAt: string
  logId: string
}

export interface RoutineItemListQuery {
  include_archived: boolean
}

export interface MedicationDisclaimerAcceptanceInput {
  accepted: true
  version: string
  body_hash: string
}

export const routineItemTypeSchema = z.enum(['supplement', 'medication'])
export const routineOriginSchema = z.enum(['user', 'professional', 'protocol', 'other'])
export const routineStoredStatusSchema = z.enum(['taken', 'snoozed', 'skipped', 'missed'])
const routineDateTimeSchema = z.string().datetime({ offset: true })
const routineUuidSchema = z.string().uuid()

export const routinePreviewModeSchema = z.enum(['private', 'name', 'name_and_dose'])

const routineScheduleSchema = z
  .object({
    local_time: z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/),
    weekdays: z
      .array(z.number().int().min(0).max(6))
      .min(1)
      .max(7)
      .transform((weekdays) => [...new Set(weekdays)].sort((left, right) => left - right)),
  })
  .strict()

type CanonicalRoutineSchedule = z.infer<typeof routineScheduleSchema>

const scheduleKey = (schedule: RoutineScheduleInput): string =>
  `${schedule.local_time}:${schedule.weekdays.join(',')}`

const uniqueSchedules = (schedules: CanonicalRoutineSchedule[], context: z.RefinementCtx): void => {
  const keys = schedules.map(scheduleKey)
  if (new Set(keys).size !== keys.length) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['schedules'],
      message: 'Schedules must be unique',
    })
  }
}

const routineSchedulesSchema = z
  .array(routineScheduleSchema)
  .min(1)
  .max(16)
  .superRefine(uniqueSchedules)

export const routineItemCreateInputSchema = z
  .object({
    name: z.string().trim().min(1).max(200),
    dose_text: z.string().trim().min(1).max(120),
    origin: routineOriginSchema,
    reminders_enabled: z.boolean(),
    schedules: routineSchedulesSchema,
  })
  .strict() satisfies z.ZodType<RoutineItemCreateInput, z.ZodTypeDef, unknown>

export const routineItemPatchInputSchema = z
  .object({
    expected_version: z.number().int().positive(),
    name: z.string().trim().min(1).max(200).optional(),
    dose_text: z.string().trim().min(1).max(120).optional(),
    origin: routineOriginSchema.optional(),
    reminders_enabled: z.boolean().optional(),
    schedules: routineSchedulesSchema.optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).some((key) => key !== 'expected_version'), {
    message: 'At least one mutable field is required',
  }) satisfies z.ZodType<RoutineItemPatchInput, z.ZodTypeDef, unknown>

const routineActionStatusSchema = routineStoredStatusSchema.exclude(['missed'])

export const routineActionInputSchema = z
  .object({
    status: routineActionStatusSchema,
    reminder_rule_id: routineUuidSchema,
    scheduled_for: routineDateTimeSchema,
    occurred_at: routineDateTimeSchema,
    snoozed_until: routineDateTimeSchema.optional(),
  })
  .strict()
  .superRefine((value, context) => {
    if (value.status === 'snoozed' && value.snoozed_until === undefined) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['snoozed_until'],
        message: 'snoozed_until is required for snoozed actions',
      })
    }
    if (value.status !== 'snoozed' && value.snoozed_until !== undefined) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['snoozed_until'],
        message: 'snoozed_until is only valid for snoozed actions',
      })
    }
  }) satisfies z.ZodType<RoutineActionInput, z.ZodTypeDef, unknown>

const includeArchivedSchema = z.preprocess((value) => {
  if (value === undefined || value === false || value === 'false') return false
  if (value === true || value === 'true') return true
  return value
}, z.boolean())

export const routineItemListQuerySchema = z
  .object({ include_archived: includeArchivedSchema.default(false) })
  .strict() satisfies z.ZodType<RoutineItemListQuery, z.ZodTypeDef, unknown>

export const medicationDisclaimerAcceptanceInputSchema = z
  .object({
    accepted: z.literal(true),
    version: z.string().min(1).max(64),
    body_hash: z.string().regex(/^[a-f0-9]{64}$/),
  })
  .strict() satisfies z.ZodType<MedicationDisclaimerAcceptanceInput, z.ZodTypeDef, unknown>

const MAX_ROUTINE_CURSOR_LENGTH = 512
const routineHistoryCursorPayloadSchema = z
  .object({
    occurredAt: routineDateTimeSchema,
    logId: routineUuidSchema,
  })
  .strict()
const routineHistoryCursorSchema = z
  .string()
  .min(1)
  .max(MAX_ROUTINE_CURSOR_LENGTH)
  .regex(/^[A-Za-z0-9_-]+$/)

export const routineHistoryQuerySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(50).default(20),
    cursor: routineHistoryCursorSchema.optional(),
  })
  .strict()

export function encodeRoutineHistoryCursor(value: RoutineHistoryCursor): string {
  const payload = routineHistoryCursorPayloadSchema.parse(value)
  const cursor = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url')
  if (cursor.length > MAX_ROUTINE_CURSOR_LENGTH) {
    throw new Error('Routine history cursor exceeds maximum length')
  }
  return cursor
}

export function decodeRoutineHistoryCursor(value: string): RoutineHistoryCursor {
  const cursor = routineHistoryCursorSchema.parse(value)
  const decoded = Buffer.from(cursor, 'base64url')
  if (decoded.toString('base64url') !== cursor) {
    throw new Error('Routine history cursor is not canonical base64url')
  }

  let payload: unknown
  try {
    payload = JSON.parse(decoded.toString('utf8'))
  } catch {
    throw new Error('Routine history cursor payload is invalid')
  }
  const parsed = routineHistoryCursorPayloadSchema.parse(payload)
  if (encodeRoutineHistoryCursor(parsed) !== cursor) {
    throw new Error('Routine history cursor payload is not canonical JSON')
  }
  return parsed
}

type RoutineOccurrenceAction = {
  status: RoutineStoredStatus
  occurredAt: string
  createdAt: string
  id: string
}

function compareDescendingTimestamp(left: string, right: string): number {
  const leftTime = Date.parse(left)
  const rightTime = Date.parse(right)
  if (Number.isFinite(leftTime) && Number.isFinite(rightTime) && leftTime !== rightTime) {
    return rightTime - leftTime
  }
  return compareDescendingString(left, right)
}

function compareDescendingString(left: string, right: string): number {
  if (left === right) return 0
  return left > right ? -1 : 1
}

function compareAscendingTimestamp(left: string, right: string): number {
  const leftTime = Date.parse(left)
  const rightTime = Date.parse(right)
  if (Number.isFinite(leftTime) && Number.isFinite(rightTime) && leftTime !== rightTime) {
    return leftTime - rightTime
  }
  if (left === right) return 0
  return left > right ? 1 : -1
}

export function deriveRoutineOccurrenceStatus(input: {
  actions: Array<RoutineOccurrenceAction>
  now: string
  localDayEndExclusive: string
}): RoutinePublicStatus {
  const latest = [...input.actions].sort((left, right) => {
    return (
      compareDescendingTimestamp(left.occurredAt, right.occurredAt) ||
      compareDescendingTimestamp(left.createdAt, right.createdAt) ||
      compareDescendingString(left.id, right.id)
    )
  })[0]

  if (latest) return latest.status
  return compareAscendingTimestamp(input.now, input.localDayEndExclusive) >= 0
    ? 'missed'
    : 'pending'
}
