import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

const USER_ID = '00000000-0000-0000-0000-000000000841'
const BODY_HASH = 'd'.repeat(64)
const EXACT_BODY = '  Texto juridico armazenado.\n'

function context(): MobileRouteContext {
  return {
    request: new Request(
      'https://bodyflow.test/api/mobile/v1/legal/medication-reminder-disclaimer',
    ),
    requestId: 'request-legal-get-0841',
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

async function loadRoute() {
  vi.resetModules()
  const createMobileRoute = vi.fn(
    (handler: (mobileContext: MobileRouteContext) => Promise<Response>) => handler,
  )
  const getMedicationDisclaimer = vi.fn(async (..._args: unknown[]) => ({
    document_key: 'medication_reminder_disclaimer',
    version: '2026-07-22.1',
    locale: 'pt-BR',
    body: EXACT_BODY,
    body_hash: BODY_HASH,
    required_from: '2026-07-22T00:00:00.000Z',
  }))
  vi.doMock('@/lib/mobile-api/route', () => ({ createMobileRoute }))
  vi.doMock('@/lib/mobile-api/routine-adherence-service', () => ({
    getMedicationDisclaimer,
  }))
  vi.doMock('@/lib/mobile-api/supabase-routine-adherence', () => ({
    createSupabaseRoutineAdherenceDependencies: vi.fn(() => ({ repository: {} })),
  }))

  const routes = await import('./route')
  return { createMobileRoute, getMedicationDisclaimer, routes }
}

afterEach(() => {
  vi.doUnmock('@/lib/mobile-api/route')
  vi.doUnmock('@/lib/mobile-api/routine-adherence-service')
  vi.doUnmock('@/lib/mobile-api/supabase-routine-adherence')
  vi.resetModules()
})

describe('medication reminder disclaimer GET route', () => {
  it('uses the authenticated route wrapper and returns exact stored-locale fields', async () => {
    const { createMobileRoute, getMedicationDisclaimer, routes } = await loadRoute()
    const get = routes.GET as unknown as (mobileContext: MobileRouteContext) => Promise<Response>

    const response = await get(context())

    expect(createMobileRoute).toHaveBeenCalledOnce()
    expect(getMedicationDisclaimer.mock.calls[0]?.[1]).toMatchObject({ userId: USER_ID })
    expect(response.status).toBe(200)
    await expect(response.json()).resolves.toEqual({
      data: {
        document_key: 'medication_reminder_disclaimer',
        version: '2026-07-22.1',
        locale: 'pt-BR',
        body: EXACT_BODY,
        body_hash: BODY_HASH,
        required_from: '2026-07-22T00:00:00.000Z',
      },
      meta: { api_version: 'v1', request_id: 'request-legal-get-0841' },
    })
  })
})
