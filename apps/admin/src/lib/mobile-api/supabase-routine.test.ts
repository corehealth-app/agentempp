import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createSupabaseRoutineDependencies } from './supabase-routine'

const reminder = {
  id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9d',
  category: 'hydration' as const,
  meal_type: null,
  routine_item_id: null,
  local_time: '09:00:00',
  weekdays: [1, 2, 3, 4, 5],
  active: true,
  created_at: '2026-07-20T12:00:00.000Z',
  updated_at: '2026-07-20T12:00:00.000Z',
}

describe('Supabase routine adapter', () => {
  it('recovers the existing logical reminder after a partial-failure retry', async () => {
    const insertMaybeSingle = vi.fn().mockResolvedValue({
      data: null,
      error: { code: '23505', message: 'duplicate' },
    })
    const insertSelect = vi.fn().mockReturnValue({ maybeSingle: insertMaybeSingle })
    const insert = vi.fn().mockReturnValue({ select: insertSelect })

    const recoveryQuery = {
      select: vi.fn(),
      eq: vi.fn(),
      is: vi.fn(),
      maybeSingle: vi.fn().mockResolvedValue({ data: reminder, error: null }),
    }
    recoveryQuery.select.mockReturnValue(recoveryQuery)
    recoveryQuery.eq.mockReturnValue(recoveryQuery)
    recoveryQuery.is.mockReturnValue(recoveryQuery)

    const from = vi.fn().mockReturnValueOnce({ insert }).mockReturnValueOnce(recoveryQuery)
    const deps = createSupabaseRoutineDependencies({ from } as unknown as ServiceClient)

    await expect(
      deps.repository.createReminder({
        userId: 'patient-1',
        category: 'hydration',
        local_time: '09:00',
        weekdays: [1, 2, 3, 4, 5],
      }),
    ).resolves.toEqual(reminder)
    expect(insert).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: 'patient-1', active: true }),
    )
    expect(recoveryQuery.eq).toHaveBeenCalledWith('weekdays', [1, 2, 3, 4, 5])
  })

  it('never selects the APNs token after device registration', async () => {
    const device = {
      id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9d',
      installation_id: '018f2c34-7c0a-7b1f-9db3-2e5f6a7b8c9e',
      apns_environment: 'sandbox',
      active: true,
      last_seen_at: '2026-07-20T12:00:00.000Z',
      created_at: '2026-07-20T12:00:00.000Z',
      updated_at: '2026-07-20T12:00:00.000Z',
    }
    const query = {
      select: vi.fn(),
      eq: vi.fn(),
      maybeSingle: vi.fn().mockResolvedValue({ data: device, error: null }),
    }
    query.select.mockReturnValue(query)
    query.eq.mockReturnValue(query)
    const supabase = {
      rpc: vi.fn().mockResolvedValue({ data: device.id, error: null }),
      from: vi.fn().mockReturnValue(query),
    } as unknown as ServiceClient

    const result = await createSupabaseRoutineDependencies(supabase).repository.upsertDevice({
      userId: 'patient-1',
      installationId: device.installation_id,
      apnsEnvironment: 'sandbox',
      apnsToken: 'a'.repeat(64),
    })

    const selection = String(query.select.mock.calls[0]?.[0])
    expect(selection).not.toContain('apns_token')
    expect(result).toEqual(device)
  })

  it.each([
    {
      databaseCode: '23505',
      expectedStatus: 409,
      expectedCode: 'reminder_conflict',
    },
    {
      databaseCode: '23514',
      expectedStatus: 422,
      expectedCode: 'reminder_invalid',
    },
  ])('maps reminder update constraint $databaseCode to a client error', async ({
    databaseCode,
    expectedStatus,
    expectedCode,
  }) => {
    const query = {
      update: vi.fn(),
      eq: vi.fn(),
      select: vi.fn(),
      maybeSingle: vi.fn().mockResolvedValue({
        data: null,
        error: { code: databaseCode, message: 'constraint violation' },
      }),
    }
    query.update.mockReturnValue(query)
    query.eq.mockReturnValue(query)
    query.select.mockReturnValue(query)
    const deps = createSupabaseRoutineDependencies({
      from: vi.fn().mockReturnValue(query),
    } as unknown as ServiceClient)

    await expect(
      deps.repository.updateReminder({
        userId: 'patient-1',
        reminderId: reminder.id,
        active: true,
      }),
    ).rejects.toMatchObject({ status: expectedStatus, code: expectedCode })
  })
})
