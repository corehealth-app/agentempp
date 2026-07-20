import type {
  CreateReminderInput,
  HydrationInput,
  MarkRoutineTakenInput,
  MobileDeviceInput,
  NotificationPreferencesPatch,
  PatchReminderInput,
} from './contracts'
import { MobileApiError } from './http'

export type RoutineItemType = 'supplement' | 'medication'
export type ReminderCategory =
  | 'meal'
  | 'hydration'
  | RoutineItemType
  | 'workout'
  | 'reevaluation'
  | 'content'
  | 'reengagement'

export interface MobileDeviceRecord {
  id: string
  installation_id: string
  apns_environment: 'sandbox' | 'production'
  active: boolean
  last_seen_at: string
  created_at: string
  updated_at: string
}

export interface NotificationPreferencesRecord {
  push_enabled: boolean
  quiet_hours_start: string | null
  quiet_hours_end: string | null
  daily_push_limit: number
  hydration_target_ml: number | null
  created_at: string
  updated_at: string
}

export interface ReminderRecord {
  id: string
  category: ReminderCategory
  meal_type: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | null
  routine_item_id: string | null
  local_time: string
  weekdays: number[]
  active: boolean
  created_at: string
  updated_at: string
}

export interface RoutineItemRecord {
  id: string
  item_type: RoutineItemType
  active: boolean
}

interface UpsertDeviceInput {
  userId: string
  installationId: string
  apnsEnvironment: 'sandbox' | 'production'
  apnsToken: string
}

interface CreateReminderRepositoryInput extends CreateReminderInput {
  userId: string
}

interface UpdateReminderRepositoryInput extends PatchReminderInput {
  userId: string
  reminderId: string
}

interface RecordHydrationRepositoryInput {
  userId: string
  localDate: string
  amountMl: number
  idempotencyKey: string
  occurredAt: string
}

interface RecordTakenRepositoryInput {
  userId: string
  routineItemId: string
  itemType: RoutineItemType
  idempotencyKey: string
  occurredAt: string
}

export interface HydrationRecordResult {
  hydration_log_id: string
  inserted: boolean
  water_consumed_ml: number
}

export interface RoutineTakenResult {
  adherence_log_id: string
  inserted: boolean
}

export interface RoutineRepository {
  listDevices(userId: string): Promise<MobileDeviceRecord[]>
  upsertDevice(input: UpsertDeviceInput): Promise<MobileDeviceRecord>
  deactivateDevice(userId: string, deviceId: string): Promise<boolean>
  getPreferences(userId: string): Promise<NotificationPreferencesRecord | null>
  updatePreferences(
    userId: string,
    patch: NotificationPreferencesPatch,
  ): Promise<NotificationPreferencesRecord>
  listReminders(userId: string): Promise<ReminderRecord[]>
  createReminder(input: CreateReminderRepositoryInput): Promise<ReminderRecord>
  updateReminder(input: UpdateReminderRepositoryInput): Promise<ReminderRecord | null>
  findRoutineItem(userId: string, routineItemId: string): Promise<RoutineItemRecord | null>
  recordHydration(input: RecordHydrationRepositoryInput): Promise<HydrationRecordResult>
  recordTaken(input: RecordTakenRepositoryInput): Promise<RoutineTakenResult>
}

export interface RoutineServiceDependencies {
  repository: RoutineRepository
}

function timeToMinute(value: string): string {
  return value.slice(0, 5)
}

function deviceDto(device: MobileDeviceRecord): MobileDeviceRecord {
  return {
    id: device.id,
    installation_id: device.installation_id,
    apns_environment: device.apns_environment,
    active: device.active,
    last_seen_at: device.last_seen_at,
    created_at: device.created_at,
    updated_at: device.updated_at,
  }
}

function preferencesDto(preferences: NotificationPreferencesRecord | null) {
  if (!preferences) {
    return {
      push_enabled: true,
      quiet_hours: null,
      daily_push_limit: 8,
      hydration_target_ml: null,
      created_at: null,
      updated_at: null,
    }
  }

  return {
    push_enabled: preferences.push_enabled,
    quiet_hours:
      preferences.quiet_hours_start && preferences.quiet_hours_end
        ? {
            start: timeToMinute(preferences.quiet_hours_start),
            end: timeToMinute(preferences.quiet_hours_end),
          }
        : null,
    daily_push_limit: preferences.daily_push_limit,
    hydration_target_ml: preferences.hydration_target_ml,
    created_at: preferences.created_at,
    updated_at: preferences.updated_at,
  }
}

function reminderDto(reminder: ReminderRecord) {
  return {
    id: reminder.id,
    category: reminder.category,
    meal_type: reminder.meal_type,
    routine_item_id: reminder.routine_item_id,
    local_time: timeToMinute(reminder.local_time),
    weekdays: reminder.weekdays,
    active: reminder.active,
    created_at: reminder.created_at,
    updated_at: reminder.updated_at,
  }
}

async function requireRoutineItem(
  deps: RoutineServiceDependencies,
  userId: string,
  routineItemId: string,
  expectedType: RoutineItemType,
): Promise<RoutineItemRecord> {
  const item = await deps.repository.findRoutineItem(userId, routineItemId)
  if (!item) throw new MobileApiError(404, 'routine_item_not_found', 'Routine item not found')
  if (item.item_type !== expectedType) {
    throw new MobileApiError(
      422,
      'routine_item_type_mismatch',
      'Routine item type does not match the requested operation',
    )
  }
  if (!item.active) {
    throw new MobileApiError(409, 'routine_item_inactive', 'Routine item is inactive')
  }
  return item
}

function localDateAt(isoTimestamp: string, timezone: string): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(isoTimestamp))
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]))
  return `${values.year}-${values.month}-${values.day}`
}

function validateOccurredAt(occurredAt: string, now: Date): void {
  const timestamp = new Date(occurredAt).getTime()
  const futureBoundary = now.getTime() + 5 * 60 * 1000
  const pastBoundary = now.getTime() - 7 * 24 * 60 * 60 * 1000
  if (timestamp > futureBoundary || timestamp < pastBoundary) {
    throw new MobileApiError(
      422,
      'occurred_at_out_of_range',
      'occurred_at must be within the supported offline window',
    )
  }
}

export async function listMobileDevices(deps: RoutineServiceDependencies, userId: string) {
  return (await deps.repository.listDevices(userId)).map(deviceDto)
}

export async function registerMobileDevice(
  deps: RoutineServiceDependencies,
  userId: string,
  input: MobileDeviceInput,
) {
  return deviceDto(
    await deps.repository.upsertDevice({
      userId,
      installationId: input.installation_id,
      apnsEnvironment: input.apns_environment,
      apnsToken: input.apns_token,
    }),
  )
}

export async function deactivateMobileDevice(
  deps: RoutineServiceDependencies,
  userId: string,
  deviceId: string,
) {
  if (!(await deps.repository.deactivateDevice(userId, deviceId))) {
    throw new MobileApiError(404, 'device_not_found', 'Device not found')
  }
  return { id: deviceId, active: false }
}

export async function getNotificationPreferences(deps: RoutineServiceDependencies, userId: string) {
  return preferencesDto(await deps.repository.getPreferences(userId))
}

export async function patchNotificationPreferences(
  deps: RoutineServiceDependencies,
  userId: string,
  patch: NotificationPreferencesPatch,
) {
  return preferencesDto(await deps.repository.updatePreferences(userId, patch))
}

export async function listReminderRules(deps: RoutineServiceDependencies, userId: string) {
  return (await deps.repository.listReminders(userId)).map(reminderDto)
}

export async function createReminderRule(
  deps: RoutineServiceDependencies,
  userId: string,
  input: CreateReminderInput,
) {
  if (input.category === 'supplement' || input.category === 'medication') {
    await requireRoutineItem(deps, userId, input.routine_item_id as string, input.category)
  }
  return reminderDto(await deps.repository.createReminder({ ...input, userId }))
}

export async function patchReminderRule(
  deps: RoutineServiceDependencies,
  userId: string,
  reminderId: string,
  patch: PatchReminderInput,
) {
  const reminder = await deps.repository.updateReminder({
    ...patch,
    userId,
    reminderId,
  })
  if (!reminder) throw new MobileApiError(404, 'reminder_not_found', 'Reminder not found')
  return reminderDto(reminder)
}

export async function recordHydration(
  deps: RoutineServiceDependencies,
  userId: string,
  timezone: string,
  input: HydrationInput,
  idempotencyKey: string,
  now = new Date(),
) {
  const occurredAt = input.occurred_at
  validateOccurredAt(occurredAt, now)
  return deps.repository.recordHydration({
    userId,
    localDate: localDateAt(occurredAt, timezone),
    amountMl: input.amount_ml,
    idempotencyKey,
    occurredAt,
  })
}

export async function markRoutineTaken(
  deps: RoutineServiceDependencies,
  userId: string,
  routineItemId: string,
  itemType: RoutineItemType,
  input: MarkRoutineTakenInput,
  idempotencyKey: string,
  now = new Date(),
) {
  validateOccurredAt(input.occurred_at, now)
  await requireRoutineItem(deps, userId, routineItemId, itemType)
  return deps.repository.recordTaken({
    userId,
    routineItemId,
    itemType,
    idempotencyKey,
    occurredAt: input.occurred_at,
  })
}
