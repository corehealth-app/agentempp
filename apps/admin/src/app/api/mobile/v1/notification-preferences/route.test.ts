import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import type {
  RoutineRepository,
  RoutineServiceDependencies,
} from '@/lib/mobile-api/routine-service'
import { createSupabaseRoutineDependencies } from '@/lib/mobile-api/supabase-routine'

const USER_ID = '00000000-0000-0000-0000-000000000861'

function context(method = 'GET', body?: unknown): MobileRouteContext {
  return {
    request: new Request('https://bodyflow.test/api/mobile/v1/notification-preferences', {
      method,
      headers:
        body === undefined
          ? undefined
          : {
              'content-type': 'application/json',
              'idempotency-key': 'preferences-patch-0861',
            },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    requestId: 'request-preferences-0861',
    supabase: { rpc: vi.fn() } as unknown as ServiceClient,
    auth: {
      accessToken: 'redacted',
      authUserId: USER_ID,
      userId: USER_ID,
      identity: { id: USER_ID, email: null, emailConfirmedAt: null },
      patient: {
        id: USER_ID,
        authUserId: USER_ID,
        email: null,
        name: null,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function repository(overrides: Partial<RoutineRepository> = {}): RoutineRepository {
  const preferences = {
    push_enabled: true,
    quiet_hours_start: null,
    quiet_hours_end: null,
    daily_push_limit: 8,
    hydration_target_ml: null,
    routine_preview_mode: 'name_and_dose' as const,
    created_at: '2026-07-23T12:00:00.000Z',
    updated_at: '2026-07-23T12:00:00.000Z',
  }
  return {
    listDevices: vi.fn(async () => []),
    upsertDevice: vi.fn(),
    deactivateDevice: vi.fn(),
    getPreferences: vi.fn(async () => preferences),
    updatePreferences: vi.fn(async () => preferences),
    listReminders: vi.fn(async () => []),
    createReminder: vi.fn(),
    updateReminder: vi.fn(),
    findRoutineItem: vi.fn(),
    recordHydration: vi.fn(),
    ...overrides,
  }
}

async function loadRoutes(dependencies: RoutineServiceDependencies) {
  vi.resetModules()
  vi.doMock('@/lib/mobile-api/route', () => ({
    createMobileRoute: (handler: (mobileContext: MobileRouteContext) => Promise<Response>) =>
      handler,
  }))
  vi.doMock('@/lib/mobile-api/idempotency', () => ({
    executeSupabaseIdempotent: async (
      mobileContext: MobileRouteContext,
      _payload: unknown,
      operation: (idempotencyKey: string) => Promise<Response>,
    ) => operation(mobileContext.request.headers.get('idempotency-key') ?? ''),
  }))
  vi.doMock('@/lib/mobile-api/supabase-routine', () => ({
    createSupabaseRoutineDependencies: vi.fn(() => dependencies),
  }))

  return import('./route')
}

afterEach(() => {
  vi.doUnmock('@/lib/mobile-api/route')
  vi.doUnmock('@/lib/mobile-api/idempotency')
  vi.doUnmock('@/lib/mobile-api/supabase-routine')
  vi.resetModules()
})

describe('notification preferences route', () => {
  it('persists preview mode through the Supabase preference adapter', async () => {
    const row = {
      push_enabled: true,
      quiet_hours_start: null,
      quiet_hours_end: null,
      daily_push_limit: 8,
      hydration_target_ml: null,
      routine_preview_mode: 'name',
      created_at: '2026-07-23T12:00:00.000Z',
      updated_at: '2026-07-23T12:01:00.000Z',
    }
    const maybeSingle = vi.fn(async () => ({ data: row, error: null }))
    const select = vi.fn((_selection: string) => ({ maybeSingle }))
    const eq = vi.fn(() => ({ select }))
    const update = vi.fn(() => ({ eq }))
    const upsert = vi.fn(async () => ({ error: null }))
    const from = vi.fn(() => ({ update, upsert }))
    const dependencies = createSupabaseRoutineDependencies({
      from,
    } as unknown as ServiceClient)

    await expect(
      dependencies.repository.updatePreferences(USER_ID, { routine_preview_mode: 'name' }),
    ).resolves.toEqual(row)
    expect(upsert).toHaveBeenCalledWith(
      { user_id: USER_ID },
      { ignoreDuplicates: true, onConflict: 'user_id' },
    )
    expect(update).toHaveBeenCalledWith(expect.objectContaining({ routine_preview_mode: 'name' }))
    expect(select.mock.calls[0]?.[0]).toContain('routine_preview_mode')
  })

  it('returns the controlled preview mode without item name or dose', async () => {
    const routes = await loadRoutes({ repository: repository() })
    const get = routes.GET as unknown as (mobileContext: MobileRouteContext) => Promise<Response>

    const response = await get(context())
    const body = await response.json()

    expect(body.data.routine_preview_mode).toBe('name_and_dose')
    expect(JSON.stringify(body)).not.toMatch(/item_name|dose_text|supplement_name|medication_name/)
  })

  it.each([
    { routine_preview_mode: 'full' },
    { routine_preview_mode: 'private', item_name: 'forbidden' },
    { routine_preview_mode: 'name', dose_text: 'forbidden' },
  ])('rejects unknown preview input before repository access', async (patch) => {
    const routineRepository = repository()
    const routes = await loadRoutes({ repository: routineRepository })
    const patchRoute = routes.PATCH as unknown as (
      mobileContext: MobileRouteContext,
    ) => Promise<Response>

    await expect(patchRoute(context('PATCH', patch))).rejects.toThrow()
    expect(routineRepository.updatePreferences).not.toHaveBeenCalled()
  })

  it('persists each exact preview mode through the existing route', async () => {
    for (const mode of ['private', 'name', 'name_and_dose'] as const) {
      const updatePreferences = vi.fn(async () => ({
        push_enabled: true,
        quiet_hours_start: null,
        quiet_hours_end: null,
        daily_push_limit: 8,
        hydration_target_ml: null,
        routine_preview_mode: mode,
        created_at: '2026-07-23T12:00:00.000Z',
        updated_at: '2026-07-23T12:00:00.000Z',
      }))
      const routes = await loadRoutes({ repository: repository({ updatePreferences }) })
      const patchRoute = routes.PATCH as unknown as (
        mobileContext: MobileRouteContext,
      ) => Promise<Response>

      const response = await patchRoute(context('PATCH', { routine_preview_mode: mode }))
      expect(updatePreferences).toHaveBeenCalledWith(USER_ID, { routine_preview_mode: mode })
      await expect(response.json()).resolves.toMatchObject({
        data: { routine_preview_mode: mode },
      })
    }
  })
})
