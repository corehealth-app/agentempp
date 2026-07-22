import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import type { RoutineItemRepository } from '@/lib/mobile-api/routine-item-service'
import {
  handleRoutineItemHistory,
  type RoutineRouteDependencies,
} from '@/lib/mobile-api/routine-route-handlers'
import { GET } from './route'

const USER_ID = '00000000-0000-0000-0000-000000000771'
const ITEM_ID = '00000000-0000-0000-0000-000000000772'

function context(query = ''): MobileRouteContext {
  return {
    request: new Request(
      `https://bodyflow.test/api/mobile/v1/medications/${ITEM_ID}/history${query}`,
    ),
    requestId: 'request-medication-history-0771',
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

describe('mobile medication history route', () => {
  it('exports a thin route and forwards medication with opaque pagination', async () => {
    expect(GET).toBeTypeOf('function')
    const history = vi.fn(async () => ({ items: [], nextCursor: 'opaque-medication-cursor' }))
    const routineRepository: RoutineItemRepository = {
      list: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      archive: vi.fn(),
      history,
    }
    const deps: RoutineRouteDependencies = {
      createRoutineItemDependencies: vi.fn(() => ({ repository: routineRepository })),
      executeIdempotent: vi.fn(),
      now: vi.fn(() => new Date()),
    }

    const response = await handleRoutineItemHistory(
      context('?limit=5'),
      { params: Promise.resolve({ id: ITEM_ID }) },
      'medication',
      deps,
    )

    expect(history).toHaveBeenCalledWith({
      userId: USER_ID,
      itemType: 'medication',
      routineItemId: ITEM_ID,
      limit: 5,
    })
    await expect(response.json()).resolves.toMatchObject({
      data: { items: [], next_cursor: 'opaque-medication-cursor' },
    })
  })
})
