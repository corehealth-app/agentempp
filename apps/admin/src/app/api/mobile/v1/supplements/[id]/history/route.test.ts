import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import type { RoutineItemRepository } from '@/lib/mobile-api/routine-item-service'
import { RoutineItemRepositoryError } from '@/lib/mobile-api/routine-item-service'
import {
  handleRoutineItemHistory,
  type RoutineRouteDependencies,
} from '@/lib/mobile-api/routine-route-handlers'
import { GET } from './route'

const USER_ID = '00000000-0000-0000-0000-000000000741'
const ITEM_ID = '00000000-0000-0000-0000-000000000742'
const LOG_ID = '00000000-0000-0000-0000-000000000743'
const RULE_ID = '00000000-0000-0000-0000-000000000744'

function context(query = ''): MobileRouteContext {
  return {
    request: new Request(
      `https://bodyflow.test/api/mobile/v1/supplements/${ITEM_ID}/history${query}`,
    ),
    requestId: 'request-routine-history-0741',
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
        timezone: 'UTC',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function repository(overrides: Partial<RoutineItemRepository> = {}): RoutineItemRepository {
  return {
    list: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    archive: vi.fn(),
    history: vi.fn(async () => ({
      items: [
        {
          id: LOG_ID,
          routineItemId: ITEM_ID,
          itemType: 'supplement' as const,
          status: 'taken' as const,
          reminderRuleId: RULE_ID,
          occurrenceKey: 'a'.repeat(64),
          scheduledFor: '2026-07-22T12:00:00.000Z',
          occurredAt: '2026-07-22T12:03:00.000Z',
          snoozedUntil: null,
          source: 'patient' as const,
          supersedesLogId: null,
          createdAt: '2026-07-22T12:03:01.000Z',
        },
      ],
      nextCursor: 'opaque-next-cursor',
    })),
    ...overrides,
  }
}

function dependencies(routineRepository: RoutineItemRepository): RoutineRouteDependencies {
  return {
    createRoutineItemDependencies: vi.fn(() => ({ repository: routineRepository })),
    executeIdempotent: vi.fn(),
    now: vi.fn(() => new Date()),
  }
}

describe('mobile supplement history route', () => {
  it('exports a thin GET route and forwards strict pagination', async () => {
    expect(GET).toBeTypeOf('function')
    const routineRepository = repository()
    const response = await handleRoutineItemHistory(
      context('?limit=10'),
      { params: Promise.resolve({ id: ITEM_ID }) },
      'supplement',
      dependencies(routineRepository),
    )

    expect(routineRepository.history).toHaveBeenCalledWith({
      userId: USER_ID,
      itemType: 'supplement',
      routineItemId: ITEM_ID,
      limit: 10,
    })
    const body = await response.json()
    expect(body.data.next_cursor).toBe('opaque-next-cursor')
    expect(JSON.stringify(body)).not.toContain('occurrence_key')
  })

  it('rejects unknown or duplicate pagination and maps wrong-type history to 404', async () => {
    const routineRepository = repository()
    const deps = dependencies(routineRepository)
    await expect(
      handleRoutineItemHistory(
        context('?timezone=UTC'),
        { params: Promise.resolve({ id: ITEM_ID }) },
        'supplement',
        deps,
      ),
    ).rejects.toThrow()
    await expect(
      handleRoutineItemHistory(
        context('?limit=10&limit=20'),
        { params: Promise.resolve({ id: ITEM_ID }) },
        'supplement',
        deps,
      ),
    ).rejects.toThrow()

    const hiddenRepository = repository({
      history: vi.fn(async () => {
        throw new RoutineItemRepositoryError('routine_item_type_mismatch')
      }),
    })
    await expect(
      handleRoutineItemHistory(
        context(),
        { params: Promise.resolve({ id: ITEM_ID }) },
        'supplement',
        dependencies(hiddenRepository),
      ),
    ).rejects.toMatchObject({ status: 404, code: 'routine_item_not_found' })
  })
})
