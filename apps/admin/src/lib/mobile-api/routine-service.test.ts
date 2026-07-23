import { describe, expect, it, vi } from 'vitest'
import {
  createReminderRule,
  deactivateMobileDevice,
  getNotificationPreferences,
  patchReminderRule,
  type RoutineRepository,
  type RoutineServiceDependencies,
  recordHydration,
  registerMobileDevice,
} from './routine-service'

const deviceRecord = {
  id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9d',
  installation_id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9e',
  apns_environment: 'sandbox' as const,
  active: true,
  last_seen_at: '2026-07-20T12:00:00.000Z',
  created_at: '2026-07-20T12:00:00.000Z',
  updated_at: '2026-07-20T12:00:00.000Z',
}

const preferencesRecord = {
  push_enabled: true,
  quiet_hours_start: '22:00:00',
  quiet_hours_end: '07:00:00',
  daily_push_limit: 8,
  hydration_target_ml: 2400,
  routine_preview_mode: 'name' as const,
  created_at: '2026-07-20T12:00:00.000Z',
  updated_at: '2026-07-20T12:00:00.000Z',
}

function dependencies(overrides: Partial<RoutineRepository> = {}): RoutineServiceDependencies {
  return {
    repository: {
      listDevices: vi.fn().mockResolvedValue([]),
      upsertDevice: vi.fn().mockResolvedValue(deviceRecord),
      deactivateDevice: vi.fn().mockResolvedValue(true),
      getPreferences: vi.fn().mockResolvedValue(preferencesRecord),
      updatePreferences: vi.fn().mockResolvedValue(preferencesRecord),
      listReminders: vi.fn().mockResolvedValue([]),
      createReminder: vi.fn(),
      updateReminder: vi.fn(),
      findRoutineItem: vi.fn(),
      recordHydration: vi.fn(),
      ...overrides,
    },
  }
}

describe('mobile routine service', () => {
  it('registers a device without returning the APNs token', async () => {
    const upsertDevice = vi.fn().mockResolvedValue(deviceRecord)
    const deps = dependencies({ upsertDevice })

    const result = await registerMobileDevice(deps, 'patient-1', {
      installation_id: deviceRecord.installation_id,
      apns_environment: 'sandbox',
      apns_token: 'a'.repeat(64),
    })

    expect(upsertDevice).toHaveBeenCalledWith({
      userId: 'patient-1',
      installationId: deviceRecord.installation_id,
      apnsEnvironment: 'sandbox',
      apnsToken: 'a'.repeat(64),
    })
    expect(result).toEqual(deviceRecord)
    expect(JSON.stringify(result)).not.toContain('a'.repeat(64))
    expect(result).not.toHaveProperty('apns_token')
  })

  it('returns stable defaults before preferences are persisted', async () => {
    const deps = dependencies({ getPreferences: vi.fn().mockResolvedValue(null) })

    await expect(getNotificationPreferences(deps, 'patient-1')).resolves.toEqual({
      push_enabled: true,
      quiet_hours: null,
      daily_push_limit: 8,
      hydration_target_ml: null,
      routine_preview_mode: 'private',
      created_at: null,
      updated_at: null,
    })
  })

  it('returns only controlled preference data without routine item content', async () => {
    const result = await getNotificationPreferences(dependencies(), 'patient-1')

    expect(result).toMatchObject({ routine_preview_mode: 'name' })
    expect(JSON.stringify(result)).not.toMatch(
      /item_name|dose_text|supplement_name|medication_name/,
    )
  })

  it('does not expose another user through device deactivation', async () => {
    const deps = dependencies({ deactivateDevice: vi.fn().mockResolvedValue(false) })

    await expect(deactivateMobileDevice(deps, 'patient-1', deviceRecord.id)).rejects.toMatchObject({
      status: 404,
      code: 'device_not_found',
    })
  })

  it.each([
    'supplement',
    'medication',
  ] as const)('reserves %s schedules for versioned routine item CRUD', async (category) => {
    const routineItemId = '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c90'
    const createReminder = vi.fn()
    const findRoutineItem = vi.fn()
    const deps = dependencies({ createReminder, findRoutineItem })

    await expect(
      createReminderRule(deps, 'patient-1', {
        category,
        routine_item_id: routineItemId,
        local_time: '08:00',
        weekdays: [1, 2, 3, 4, 5],
      }),
    ).rejects.toMatchObject({
      status: 409,
      code: 'routine_schedule_conflict',
    })
    expect(findRoutineItem).not.toHaveBeenCalled()
    expect(createReminder).not.toHaveBeenCalled()
  })

  it('reserves existing routine schedules for versioned routine item PATCH', async () => {
    const routineItemId = '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c90'
    const updateReminder = vi.fn()
    const deps = dependencies({
      listReminders: vi.fn().mockResolvedValue([
        {
          id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c92',
          category: 'supplement',
          meal_type: null,
          routine_item_id: routineItemId,
          local_time: '08:00:00',
          weekdays: [1, 2, 3, 4, 5],
          active: true,
          created_at: '2026-07-20T12:00:00.000Z',
          updated_at: '2026-07-20T12:00:00.000Z',
        },
      ]),
      updateReminder,
    })

    await expect(
      patchReminderRule(deps, 'patient-1', '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c92', {
        active: true,
      }),
    ).rejects.toMatchObject({
      status: 409,
      code: 'routine_schedule_conflict',
    })
    expect(updateReminder).not.toHaveBeenCalled()
  })

  it('keeps non-routine reminder PATCH behavior unchanged', async () => {
    const reminderId = '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c93'
    const existing = {
      id: reminderId,
      category: 'hydration' as const,
      meal_type: null,
      routine_item_id: null,
      local_time: '08:00:00',
      weekdays: [1, 2, 3, 4, 5],
      active: true,
      created_at: '2026-07-20T12:00:00.000Z',
      updated_at: '2026-07-20T12:00:00.000Z',
    }
    const updateReminder = vi.fn().mockResolvedValue({
      ...existing,
      local_time: '09:00:00',
      updated_at: '2026-07-20T12:05:00.000Z',
    })
    const deps = dependencies({
      listReminders: vi.fn().mockResolvedValue([existing]),
      updateReminder,
    })

    await expect(
      patchReminderRule(deps, 'patient-1', reminderId, { local_time: '09:00' }),
    ).resolves.toMatchObject({ id: reminderId, category: 'hydration', local_time: '09:00' })
    expect(updateReminder).toHaveBeenCalledWith({
      userId: 'patient-1',
      reminderId,
      local_time: '09:00',
    })
  })

  it('derives hydration local_date from the authenticated patient timezone', async () => {
    const repositoryCall = vi.fn().mockResolvedValue({
      hydration_log_id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c91',
      inserted: true,
      water_consumed_ml: 850,
    })
    const deps = dependencies({ recordHydration: repositoryCall })

    await expect(
      recordHydration(
        deps,
        'patient-1',
        'America/New_York',
        { amount_ml: 350, occurred_at: '2026-07-21T03:30:00.000Z' },
        'hydration-request-1',
        new Date('2026-07-21T04:00:00.000Z'),
      ),
    ).resolves.toMatchObject({ inserted: true, water_consumed_ml: 850 })
    expect(repositoryCall).toHaveBeenCalledWith({
      userId: 'patient-1',
      localDate: '2026-07-20',
      amountMl: 350,
      idempotencyKey: 'hydration-request-1',
      occurredAt: '2026-07-21T03:30:00.000Z',
    })
  })

  it('rejects routine timestamps outside the bounded offline window', async () => {
    const hydrationRepository = vi.fn()
    const deps = dependencies({ recordHydration: hydrationRepository })
    const now = new Date('2026-07-20T12:00:00.000Z')

    await expect(
      recordHydration(
        deps,
        'patient-1',
        'America/New_York',
        { amount_ml: 350, occurred_at: '2026-07-20T12:06:00.000Z' },
        'hydration-request-2',
        now,
      ),
    ).rejects.toMatchObject({ status: 422, code: 'occurred_at_out_of_range' })
    await expect(
      recordHydration(
        deps,
        'patient-1',
        'America/New_York',
        { amount_ml: 350, occurred_at: '2026-07-13T11:59:59.000Z' },
        'hydration-request-3',
        now,
      ),
    ).rejects.toMatchObject({ status: 422, code: 'occurred_at_out_of_range' })
    expect(hydrationRepository).not.toHaveBeenCalled()
  })
})
