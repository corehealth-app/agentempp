import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

const USER_ID = '00000000-0000-0000-0000-000000000831'
const ITEM_ID = '00000000-0000-0000-0000-000000000832'
const RULE_ID = '00000000-0000-0000-0000-000000000833'
const LOG_ID = '00000000-0000-0000-0000-000000000834'

function context(body: unknown): MobileRouteContext {
  return {
    request: new Request(`https://bodyflow.test/api/mobile/v1/medications/${ITEM_ID}/log`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'idempotency-key': 'routine-medication-log-0831',
      },
      body: JSON.stringify(body),
    }),
    requestId: 'request-routine-log-0831',
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
        locale: 'en-US',
        timezone: 'UTC',
        country: 'US',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

async function loadRoutes() {
  vi.resetModules()
  const recordRoutineAction = vi.fn(async (..._args: unknown[]) => ({
    adherence_log_id: LOG_ID,
    occurrence_key: 'c'.repeat(64),
    item_type: 'medication',
    status: 'taken',
  }))
  const recordLegacyRoutineTaken = vi.fn(async (..._args: unknown[]) => ({
    adherence_log_id: LOG_ID,
    occurrence_key: 'c'.repeat(64),
    item_type: 'medication',
    status: 'taken',
  }))
  vi.doMock('@/lib/mobile-api/route', () => ({
    createMobileRouteWithContext: (
      handler: (mobileContext: MobileRouteContext, routeContext: unknown) => Promise<Response>,
    ) => handler,
  }))
  vi.doMock('@/lib/mobile-api/idempotency', () => ({
    executeSupabaseIdempotent: async (
      mobileContext: MobileRouteContext,
      _payload: unknown,
      operation: (idempotencyKey: string) => Promise<Response>,
    ) => operation(mobileContext.request.headers.get('idempotency-key') as string),
  }))
  vi.doMock('@/lib/mobile-api/routine-adherence-service', () => ({
    recordRoutineAction,
    recordLegacyRoutineTaken,
  }))
  vi.doMock('@/lib/mobile-api/supabase-routine-adherence', () => ({
    createSupabaseRoutineAdherenceDependencies: vi.fn(() => ({ repository: {} })),
  }))

  const log = await import('./route')
  const legacy = await import('../../../routine/medications/[id]/taken/route')
  return { legacy, log, recordLegacyRoutineTaken, recordRoutineAction }
}

afterEach(() => {
  vi.doUnmock('@/lib/mobile-api/route')
  vi.doUnmock('@/lib/mobile-api/idempotency')
  vi.doUnmock('@/lib/mobile-api/routine-adherence-service')
  vi.doUnmock('@/lib/mobile-api/supabase-routine-adherence')
  vi.resetModules()
})

const routeContext = { params: Promise.resolve({ id: ITEM_ID }) }

describe('mobile medication action routes', () => {
  it('wires the new log POST to the literal medication type', async () => {
    const { log, recordRoutineAction } = await loadRoutes()
    const post = log.POST as unknown as (
      mobileContext: MobileRouteContext,
      params: typeof routeContext,
    ) => Promise<Response>

    const response = await post(
      context({
        status: 'taken',
        reminder_rule_id: RULE_ID,
        scheduled_for: '2026-07-23T11:00:00.000Z',
        occurred_at: '2026-07-23T11:03:00.000Z',
      }),
      routeContext,
    )

    expect(response.status).toBe(200)
    expect(recordRoutineAction.mock.calls[0]?.[2]).toBe('medication')
    expect(recordRoutineAction.mock.calls[0]?.[3]).toBe(ITEM_ID)
  })

  it('wires the medication legacy POST to exact-occurrence resolution', async () => {
    const { legacy, recordLegacyRoutineTaken } = await loadRoutes()
    const post = legacy.POST as unknown as (
      mobileContext: MobileRouteContext,
      params: typeof routeContext,
    ) => Promise<Response>

    await post(context({ occurred_at: '2026-07-23T11:03:00.000Z' }), routeContext)

    expect(recordLegacyRoutineTaken.mock.calls[0]?.[2]).toBe(ITEM_ID)
    expect(recordLegacyRoutineTaken.mock.calls[0]?.[3]).toBe('medication')
  })
})
