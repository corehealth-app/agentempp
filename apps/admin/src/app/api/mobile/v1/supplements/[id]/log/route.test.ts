import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { MobileApiError } from '@/lib/mobile-api/http'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

const USER_ID = '00000000-0000-0000-0000-000000000821'
const ITEM_ID = '00000000-0000-0000-0000-000000000822'
const RULE_ID = '00000000-0000-0000-0000-000000000823'
const LOG_ID = '00000000-0000-0000-0000-000000000824'
const OCCURRENCE_KEY = 'a'.repeat(64)

function context(body: unknown, idempotencyKey?: string): MobileRouteContext {
  const headers = new Headers({ 'content-type': 'application/json' })
  if (idempotencyKey) headers.set('idempotency-key', idempotencyKey)
  return {
    request: new Request(`https://bodyflow.test/api/mobile/v1/supplements/${ITEM_ID}/log`, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    }),
    requestId: 'request-routine-log-0821',
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

async function loadRoutes() {
  vi.resetModules()
  const recordRoutineAction = vi.fn(async (..._args: unknown[]) => ({
    adherence_log_id: LOG_ID,
    occurrence_key: OCCURRENCE_KEY,
    item_type: 'supplement',
    status: 'taken',
  }))
  const recordLegacyRoutineTaken = vi.fn(async (..._args: unknown[]) => ({
    adherence_log_id: LOG_ID,
    occurrence_key: OCCURRENCE_KEY,
    item_type: 'supplement',
    status: 'taken',
  }))
  const executeIdempotent = vi.fn(
    async (
      mobileContext: MobileRouteContext,
      _payload: unknown,
      operation: (idempotencyKey: string) => Promise<Response>,
    ) => {
      const key = mobileContext.request.headers.get('idempotency-key')
      if (!key) {
        throw new MobileApiError(400, 'missing_idempotency_key', 'Idempotency-Key is required')
      }
      return operation(key)
    },
  )
  vi.doMock('@/lib/mobile-api/route', () => ({
    createMobileRouteWithContext: (
      handler: (mobileContext: MobileRouteContext, routeContext: unknown) => Promise<Response>,
    ) => handler,
  }))
  vi.doMock('@/lib/mobile-api/idempotency', () => ({
    executeSupabaseIdempotent: executeIdempotent,
  }))
  vi.doMock('@/lib/mobile-api/routine-adherence-service', () => ({
    recordRoutineAction,
    recordLegacyRoutineTaken,
  }))
  vi.doMock('@/lib/mobile-api/supabase-routine-adherence', () => ({
    createSupabaseRoutineAdherenceDependencies: vi.fn(() => ({ repository: {} })),
  }))

  const log = await import('./route')
  const legacy = await import('../../../routine/supplements/[id]/taken/route')
  return { executeIdempotent, legacy, log, recordLegacyRoutineTaken, recordRoutineAction }
}

afterEach(() => {
  vi.doUnmock('@/lib/mobile-api/route')
  vi.doUnmock('@/lib/mobile-api/idempotency')
  vi.doUnmock('@/lib/mobile-api/routine-adherence-service')
  vi.doUnmock('@/lib/mobile-api/supabase-routine-adherence')
  vi.resetModules()
})

const routeContext = (id = ITEM_ID) => ({ params: Promise.resolve({ id }) })

describe('mobile supplement action routes', () => {
  it('wires exported POST to the literal supplement type and private DTO', async () => {
    const { log, recordRoutineAction } = await loadRoutes()
    const post = log.POST as unknown as (
      mobileContext: MobileRouteContext,
      params: ReturnType<typeof routeContext>,
    ) => Promise<Response>

    const response = await post(
      context(
        {
          status: 'taken',
          reminder_rule_id: RULE_ID,
          scheduled_for: '2026-07-23T11:00:00.000Z',
          occurred_at: '2026-07-23T11:03:00.000Z',
        },
        'routine-log-0821',
      ),
      routeContext(),
    )

    expect(recordRoutineAction.mock.calls[0]?.[2]).toBe('supplement')
    expect(recordRoutineAction.mock.calls[0]?.[3]).toBe(ITEM_ID)
    expect(response.status).toBe(200)
    const body = await response.json()
    expect(body.data).toEqual({
      adherence_log_id: LOG_ID,
      occurrence_key: OCCURRENCE_KEY,
      item_type: 'supplement',
      status: 'taken',
    })
    expect(JSON.stringify(body)).not.toMatch(/name|dose/i)
  })

  it.each([
    ['missed', { status: 'missed' }],
    ['source', { source: 'offline_sync' }],
    ['occurrence key', { occurrence_key: OCCURRENCE_KEY }],
    ['supersedes log', { supersedes_log_id: LOG_ID }],
    ['item type', { item_type: 'medication' }],
  ])('rejects client-owned %s before service access', async (_label, forbidden) => {
    const { log, recordRoutineAction } = await loadRoutes()
    const post = log.POST as unknown as (
      mobileContext: MobileRouteContext,
      params: ReturnType<typeof routeContext>,
    ) => Promise<Response>

    await expect(
      post(
        context(
          {
            status: 'taken',
            reminder_rule_id: RULE_ID,
            scheduled_for: '2026-07-23T11:00:00.000Z',
            occurred_at: '2026-07-23T11:03:00.000Z',
            ...forbidden,
          },
          'routine-log-forbidden-0821',
        ),
        routeContext(),
      ),
    ).rejects.toThrow()
    expect(recordRoutineAction).not.toHaveBeenCalled()
  })

  it('requires Idempotency-Key before service access', async () => {
    const { log, recordRoutineAction } = await loadRoutes()
    const post = log.POST as unknown as (
      mobileContext: MobileRouteContext,
      params: ReturnType<typeof routeContext>,
    ) => Promise<Response>

    await expect(
      post(
        context({
          status: 'skipped',
          reminder_rule_id: RULE_ID,
          scheduled_for: '2026-07-23T11:00:00.000Z',
          occurred_at: '2026-07-23T11:03:00.000Z',
        }),
        routeContext(),
      ),
    ).rejects.toMatchObject({ status: 400, code: 'missing_idempotency_key' })
    expect(recordRoutineAction).not.toHaveBeenCalled()
  })

  it('keeps the legacy body and wires it to exact-occurrence service resolution', async () => {
    const { legacy, recordLegacyRoutineTaken } = await loadRoutes()
    const post = legacy.POST as unknown as (
      mobileContext: MobileRouteContext,
      params: ReturnType<typeof routeContext>,
    ) => Promise<Response>

    const response = await post(
      context({ occurred_at: '2026-07-23T11:03:00.000Z' }, 'legacy-taken-0821'),
      routeContext(),
    )

    expect(response.status).toBe(200)
    expect(recordLegacyRoutineTaken.mock.calls[0]?.[2]).toBe(ITEM_ID)
    expect(recordLegacyRoutineTaken.mock.calls[0]?.[3]).toBe('supplement')
    expect(recordLegacyRoutineTaken.mock.calls[0]?.[4]).toEqual({
      occurred_at: '2026-07-23T11:03:00.000Z',
    })
  })
})
