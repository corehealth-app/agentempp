import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import type { RoutineItemRepository } from '@/lib/mobile-api/routine-item-service'
import { RoutineItemRepositoryError } from '@/lib/mobile-api/routine-item-service'
import {
  handleRoutineCollectionGet,
  handleRoutineCollectionPost,
  type RoutineRouteDependencies,
} from '@/lib/mobile-api/routine-route-handlers'
import { GET, POST } from './route'

const USER_ID = '00000000-0000-0000-0000-000000000751'
const ITEM_ID = '00000000-0000-0000-0000-000000000752'

function context(method = 'GET', body?: unknown): MobileRouteContext {
  return {
    request: new Request('https://bodyflow.test/api/mobile/v1/medications', {
      method,
      headers:
        body === undefined
          ? undefined
          : {
              'content-type': 'application/json',
              'idempotency-key': 'routine-medication-0751',
            },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    requestId: 'request-medication-0751',
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

function repository(overrides: Partial<RoutineItemRepository> = {}): RoutineItemRepository {
  return {
    list: vi.fn(async () => ({ localDate: '2026-07-22', items: [] })),
    create: vi.fn(async () => ({ routineItemId: ITEM_ID, version: 1, archivedAt: null })),
    update: vi.fn(),
    archive: vi.fn(),
    history: vi.fn(),
    ...overrides,
  }
}

function dependencies(routineRepository: RoutineItemRepository): RoutineRouteDependencies {
  return {
    createRoutineItemDependencies: vi.fn(() => ({ repository: routineRepository })),
    executeIdempotent: vi.fn(async (_context, payload, operation) => {
      expect(payload).toMatchObject({ item_type: 'medication' })
      return operation('routine-medication-0751')
    }),
    now: vi.fn(() => new Date('2026-07-22T14:30:00.000Z')),
  }
}

describe('mobile medication collection route', () => {
  it('exports thin routes and closes both operations over medication', async () => {
    expect(GET).toBeTypeOf('function')
    expect(POST).toBeTypeOf('function')
    const routineRepository = repository()
    const deps = dependencies(routineRepository)

    await handleRoutineCollectionGet(context(), 'medication', deps)
    await handleRoutineCollectionPost(
      context('POST', {
        name: 'Medication',
        dose_text: '1 unit',
        origin: 'professional',
        reminders_enabled: true,
        schedules: [{ local_time: '08:00', weekdays: [1] }],
      }),
      'medication',
      deps,
    )

    expect(routineRepository.list).toHaveBeenCalledWith(
      expect.objectContaining({ itemType: 'medication' }),
    )
    expect(routineRepository.create).toHaveBeenCalledWith(
      expect.objectContaining({ itemType: 'medication' }),
    )
  })

  it('surfaces current medication disclaimer requirements as 428 without clinical copy', async () => {
    const routineRepository = repository({
      create: vi.fn(async () => {
        throw new RoutineItemRepositoryError('medication_disclaimer_required')
      }),
    })

    const error = await handleRoutineCollectionPost(
      context('POST', {
        name: 'Medication',
        dose_text: '1 unit',
        origin: 'professional',
        reminders_enabled: true,
        schedules: [{ local_time: '08:00', weekdays: [1] }],
      }),
      'medication',
      dependencies(routineRepository),
    ).catch((caught: unknown) => caught)

    expect(error).toMatchObject({ status: 428, code: 'medication_disclaimer_required' })
    expect((error as Error).message).not.toMatch(/take|stop|dose|treat|recommend/i)
  })
})
