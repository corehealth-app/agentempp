import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import type {
  RoutineItemRepository,
  RoutineItemServiceDependencies,
} from '@/lib/mobile-api/routine-item-service'
import {
  handleRoutineItemArchive,
  handleRoutineItemPatch,
  type RoutineRouteDependencies,
} from '@/lib/mobile-api/routine-route-handlers'
import { DELETE, PATCH } from './route'

const USER_ID = '00000000-0000-0000-0000-000000000731'
const AUTH_USER_ID = '00000000-0000-0000-0000-000000000732'
const ITEM_ID = '00000000-0000-0000-0000-000000000733'

function listItem() {
  return {
    id: ITEM_ID,
    itemType: 'supplement' as const,
    name: 'Creatina',
    doseText: '3 g',
    origin: 'user' as const,
    remindersEnabled: true,
    active: true,
    archivedAt: null,
    version: 2,
    createdAt: '2026-07-20T12:00:00.000Z',
    updatedAt: '2026-07-22T12:00:00.000Z',
    schedules: [],
  }
}

function repository(overrides: Partial<RoutineItemRepository> = {}): RoutineItemRepository {
  return {
    list: vi.fn(async () => ({ localDate: '2026-07-22', items: [listItem()] })),
    create: vi.fn(),
    update: vi.fn(async () => ({ routineItemId: ITEM_ID, version: 3, archivedAt: null })),
    archive: vi.fn(async () => ({
      routineItemId: ITEM_ID,
      version: 3,
      archivedAt: '2026-07-22T15:00:00.000Z',
    })),
    history: vi.fn(),
    ...overrides,
  }
}

function context(method: string, body: unknown, key?: string, contentType = 'application/json') {
  const headers = new Headers({ 'content-type': contentType })
  if (key) headers.set('idempotency-key', key)
  return {
    request: new Request(`https://bodyflow.test/api/mobile/v1/supplements/${ITEM_ID}`, {
      method,
      headers,
      body: JSON.stringify(body),
    }),
    requestId: 'request-routine-item-0731',
    supabase: { rpc: vi.fn() } as unknown as ServiceClient,
    auth: {
      accessToken: 'redacted',
      authUserId: AUTH_USER_ID,
      userId: USER_ID,
      identity: { id: AUTH_USER_ID, email: null, emailConfirmedAt: null },
      patient: {
        id: USER_ID,
        authUserId: AUTH_USER_ID,
        email: null,
        name: null,
        locale: 'pt-BR' as const,
        timezone: 'America/New_York',
        country: 'US',
        countryConfirmed: true,
        status: 'active' as const,
      },
    },
  } satisfies MobileRouteContext
}

function dependencies(
  service: RoutineItemServiceDependencies,
  execute: RoutineRouteDependencies['executeIdempotent'] = vi.fn(
    async (_context, _payload, operation) => operation('routine-item-key-0731'),
  ),
): RoutineRouteDependencies {
  return {
    createRoutineItemDependencies: vi.fn(() => service),
    executeIdempotent: execute,
    now: vi.fn(() => new Date('2026-07-22T14:30:00.000Z')),
  }
}

const routeContext = (id = ITEM_ID) => ({ params: Promise.resolve({ id }) })

describe('mobile supplement item route', () => {
  it('exports thin PATCH and DELETE routes', () => {
    expect(PATCH).toBeTypeOf('function')
    expect(DELETE).toBeTypeOf('function')
  })

  it('validates the UUID and strict PATCH body before repository access', async () => {
    const routineRepository = repository()
    const deps = dependencies({ repository: routineRepository })

    await expect(
      handleRoutineItemPatch(
        context('PATCH', { expected_version: 2, dose_text: '5 g' }, 'routine-patch-0731'),
        routeContext('not-a-uuid'),
        'supplement',
        deps,
      ),
    ).rejects.toThrow()
    await expect(
      handleRoutineItemPatch(
        context(
          'PATCH',
          { expected_version: 2, dose_text: '5 g', item_type: 'medication' },
          'routine-patch-0731',
        ),
        routeContext(),
        'supplement',
        deps,
      ),
    ).rejects.toThrow()
    expect(routineRepository.update).not.toHaveBeenCalled()
  })

  it('patches with 200 and hashes literal type, route id, and validated input', async () => {
    const routineRepository = repository()
    const execute = vi.fn(async (_context, payload, operation) => {
      expect(payload).toEqual({
        item_type: 'supplement',
        routine_item_id: ITEM_ID,
        expected_version: 2,
        dose_text: '5 g',
      })
      return operation('routine-patch-0731')
    }) as RoutineRouteDependencies['executeIdempotent']

    const response = await handleRoutineItemPatch(
      context('PATCH', { expected_version: 2, dose_text: ' 5 g ' }, 'routine-patch-0731'),
      routeContext(),
      'supplement',
      dependencies({ repository: routineRepository }, execute),
    )

    expect(response.status).toBe(200)
    expect(routineRepository.update).toHaveBeenCalledWith(
      expect.objectContaining({ itemType: 'supplement', routineItemId: ITEM_ID }),
    )
  })

  it('requires JSON and Idempotency-Key for archive', async () => {
    const routineRepository = repository()
    const deps = dependencies({ repository: routineRepository }, executeSupabaseIdempotent)

    await expect(
      handleRoutineItemArchive(
        context('DELETE', {}, 'routine-delete-0731', 'text/plain'),
        routeContext(),
        'supplement',
        deps,
      ),
    ).rejects.toMatchObject({ status: 415, code: 'unsupported_media_type' })
    await expect(
      handleRoutineItemArchive(context('DELETE', {}), routeContext(), 'supplement', deps),
    ).rejects.toMatchObject({ status: 400, code: 'missing_idempotency_key' })
    expect(routineRepository.archive).not.toHaveBeenCalled()
  })

  it('archives with 200 and hashes only the typed route identity after an empty JSON body', async () => {
    const routineRepository = repository()
    const execute = vi.fn(async (_context, payload, operation) => {
      expect(payload).toEqual({ item_type: 'supplement', routine_item_id: ITEM_ID })
      return operation('routine-delete-0731')
    }) as RoutineRouteDependencies['executeIdempotent']

    const response = await handleRoutineItemArchive(
      context('DELETE', {}, 'routine-delete-0731'),
      routeContext(),
      'supplement',
      dependencies({ repository: routineRepository }, execute),
    )

    expect(response.status).toBe(200)
    await expect(response.json()).resolves.toMatchObject({
      data: { routine_item_id: ITEM_ID, archived_at: '2026-07-22T15:00:00.000Z' },
    })
  })
})
