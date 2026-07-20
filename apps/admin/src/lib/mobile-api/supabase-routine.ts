import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'
import type {
  HydrationRecordResult,
  MobileDeviceRecord,
  NotificationPreferencesRecord,
  ReminderRecord,
  RoutineItemRecord,
  RoutineRepository,
  RoutineServiceDependencies,
  RoutineTakenResult,
} from './routine-service'

const deviceRowSchema = z.object({
  id: z.string().uuid(),
  installation_id: z.string().min(1),
  apns_environment: z.enum(['sandbox', 'production']),
  active: z.boolean(),
  last_seen_at: z.string().datetime({ offset: true }),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }),
})

const preferencesRowSchema = z.object({
  push_enabled: z.boolean(),
  quiet_hours_start: z.string().nullable(),
  quiet_hours_end: z.string().nullable(),
  daily_push_limit: z.number().int(),
  hydration_target_ml: z.number().int().nullable(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }),
})

const reminderRowSchema = z.object({
  id: z.string().uuid(),
  category: z.enum([
    'meal',
    'hydration',
    'supplement',
    'medication',
    'workout',
    'reevaluation',
    'content',
    'reengagement',
  ]),
  meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia']).nullable(),
  routine_item_id: z.string().uuid().nullable(),
  local_time: z.string().min(1),
  weekdays: z.array(z.number().int().min(0).max(6)),
  active: z.boolean(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }),
})

const routineItemRowSchema = z.object({
  id: z.string().uuid(),
  item_type: z.enum(['supplement', 'medication']),
  active: z.boolean(),
})

const hydrationResultSchema = z.object({
  hydration_log_id: z.string().uuid(),
  inserted: z.boolean(),
  water_consumed_ml: z.number().int().nonnegative(),
})

const routineTakenResultSchema = z.object({
  adherence_log_id: z.string().uuid(),
  inserted: z.boolean(),
})

const deviceSelection = [
  'id',
  'installation_id',
  'apns_environment',
  'active',
  'last_seen_at',
  'created_at',
  'updated_at',
].join(', ')

const preferencesSelection = [
  'push_enabled',
  'quiet_hours_start',
  'quiet_hours_end',
  'daily_push_limit',
  'hydration_target_ml',
  'created_at',
  'updated_at',
].join(', ')

const reminderSelection = [
  'id',
  'category',
  'meal_type',
  'routine_item_id',
  'local_time',
  'weekdays',
  'active',
  'created_at',
  'updated_at',
].join(', ')

function parseDevice(row: unknown): MobileDeviceRecord {
  const parsed = deviceRowSchema.safeParse(row)
  if (!parsed.success) throw new Error('Invalid mobile device database response')
  return parsed.data
}

function parsePreferences(row: unknown): NotificationPreferencesRecord {
  const parsed = preferencesRowSchema.safeParse(row)
  if (!parsed.success) throw new Error('Invalid notification preferences database response')
  return parsed.data
}

function parseReminder(row: unknown): ReminderRecord {
  const parsed = reminderRowSchema.safeParse(row)
  if (!parsed.success) throw new Error('Invalid reminder database response')
  return parsed.data
}

function parseRoutineItem(row: unknown): RoutineItemRecord {
  const parsed = routineItemRowSchema.safeParse(row)
  if (!parsed.success) throw new Error('Invalid routine item database response')
  return parsed.data
}

function databaseFailure(action: string, error: { code?: string; message: string } | null): never {
  console.error('[mobile-routine] database_failure', {
    action,
    error_code: error?.code ?? 'empty_result',
  })
  throw new MobileApiError(500, 'routine_storage_failed', 'Routine operation failed')
}

function createRepository(supabase: ServiceClient): RoutineRepository {
  return {
    async listDevices(userId) {
      const { data, error } = await supabase
        .from('mobile_devices')
        .select(deviceSelection)
        .eq('user_id', userId)
        .order('created_at', { ascending: true })
      if (error) databaseFailure('list_devices', error)
      return (data ?? []).map(parseDevice)
    },
    async upsertDevice(input) {
      const { data: deviceId, error: rpcError } = await supabase.rpc('upsert_mobile_device', {
        p_user_id: input.userId,
        p_installation_id: input.installationId,
        p_apns_environment: input.apnsEnvironment,
        p_apns_token: input.apnsToken,
      })
      if (rpcError?.code === '23505') {
        throw new MobileApiError(
          409,
          'device_registration_conflict',
          'Device registration conflicts with an active installation',
        )
      }
      if (rpcError || !deviceId) databaseFailure('upsert_device', rpcError)

      const { data, error } = await supabase
        .from('mobile_devices')
        .select(deviceSelection)
        .eq('id', deviceId)
        .eq('user_id', input.userId)
        .maybeSingle()
      if (error || !data) databaseFailure('read_upserted_device', error)
      return parseDevice(data)
    },
    async deactivateDevice(userId, deviceId) {
      const { data, error } = await supabase.rpc('deactivate_mobile_device', {
        p_user_id: userId,
        p_device_id: deviceId,
      })
      if (error) databaseFailure('deactivate_device', error)
      return data === true
    },
    async getPreferences(userId) {
      const { data, error } = await supabase
        .from('notification_preferences')
        .select(preferencesSelection)
        .eq('user_id', userId)
        .maybeSingle()
      if (error) databaseFailure('get_preferences', error)
      return data ? parsePreferences(data) : null
    },
    async updatePreferences(userId, patch) {
      const { data, error } = await supabase.rpc('update_notification_preferences_atomic', {
        p_user_id: userId,
        p_patch: patch,
      })
      if (error || !data) databaseFailure('update_preferences', error)
      return parsePreferences(data)
    },
    async listReminders(userId) {
      const { data, error } = await supabase
        .from('reminder_rules')
        .select(reminderSelection)
        .eq('user_id', userId)
        .order('local_time', { ascending: true })
        .order('created_at', { ascending: true })
      if (error) databaseFailure('list_reminders', error)
      return (data ?? []).map(parseReminder)
    },
    async createReminder(input) {
      const payload = {
        user_id: input.userId,
        category: input.category,
        meal_type: input.meal_type ?? null,
        routine_item_id: input.routine_item_id ?? null,
        local_time: input.local_time,
        weekdays: input.weekdays,
        active: true,
      }
      const { data, error } = await supabase
        .from('reminder_rules')
        .insert(payload)
        .select(reminderSelection)
        .maybeSingle()
      if (error?.code === '23505') {
        let query = supabase
          .from('reminder_rules')
          .select(reminderSelection)
          .eq('user_id', input.userId)
          .eq('category', input.category)
          .eq('local_time', input.local_time)
          .eq('weekdays', input.weekdays)
          .eq('active', true)
          .is('template_key', null)
        query = input.meal_type
          ? query.eq('meal_type', input.meal_type)
          : query.is('meal_type', null)
        query = input.routine_item_id
          ? query.eq('routine_item_id', input.routine_item_id)
          : query.is('routine_item_id', null)
        const { data: existing, error: existingError } = await query.maybeSingle()
        if (!existingError && existing) return parseReminder(existing)
      }
      if (error?.code === '23503' || error?.code === '23514') {
        throw new MobileApiError(422, 'reminder_invalid', 'Reminder configuration is invalid')
      }
      if (error || !data) databaseFailure('create_reminder', error)
      return parseReminder(data)
    },
    async updateReminder(input) {
      const patch = {
        ...(input.local_time === undefined ? {} : { local_time: input.local_time }),
        ...(input.weekdays === undefined ? {} : { weekdays: input.weekdays }),
        ...(input.active === undefined ? {} : { active: input.active }),
        updated_at: new Date().toISOString(),
      }
      const { data, error } = await supabase
        .from('reminder_rules')
        .update(patch)
        .eq('id', input.reminderId)
        .eq('user_id', input.userId)
        .select(reminderSelection)
        .maybeSingle()
      if (error?.code === '23505') {
        throw new MobileApiError(
          409,
          'reminder_conflict',
          'An active reminder already uses this schedule',
        )
      }
      if (error?.code === '23503' || error?.code === '23514') {
        throw new MobileApiError(422, 'reminder_invalid', 'Reminder configuration is invalid')
      }
      if (error) databaseFailure('update_reminder', error)
      return data ? parseReminder(data) : null
    },
    async findRoutineItem(userId, routineItemId) {
      const { data, error } = await supabase
        .from('routine_items')
        .select('id, item_type, active')
        .eq('id', routineItemId)
        .eq('user_id', userId)
        .maybeSingle()
      if (error) databaseFailure('find_routine_item', error)
      return data ? parseRoutineItem(data) : null
    },
    async recordHydration(input) {
      const { data, error } = await supabase.rpc('record_hydration_atomic', {
        p_user_id: input.userId,
        p_local_date: input.localDate,
        p_amount_ml: input.amountMl,
        p_idempotency_key: input.idempotencyKey,
        p_occurred_at: input.occurredAt,
      })
      if (error || !data) databaseFailure('record_hydration', error)
      const parsed = hydrationResultSchema.safeParse(data)
      if (!parsed.success) databaseFailure('parse_hydration_result', null)
      return parsed.data as HydrationRecordResult
    },
    async recordTaken(input) {
      const { data, error } = await supabase.rpc('record_routine_adherence_atomic', {
        p_user_id: input.userId,
        p_routine_item_id: input.routineItemId,
        p_expected_item_type: input.itemType,
        p_idempotency_key: input.idempotencyKey,
        p_taken_at: input.occurredAt,
      })
      if (error || !data) databaseFailure('record_taken', error)
      const parsed = routineTakenResultSchema.safeParse(data)
      if (!parsed.success) databaseFailure('parse_taken_result', null)
      return parsed.data as RoutineTakenResult
    },
  }
}

export function createSupabaseRoutineDependencies(
  supabase: ServiceClient,
): RoutineServiceDependencies {
  return { repository: createRepository(supabase) }
}
