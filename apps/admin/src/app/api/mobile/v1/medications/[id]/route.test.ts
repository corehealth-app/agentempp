import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import type { RoutineItemRepository } from '@/lib/mobile-api/routine-item-service'
import {
  handleRoutineItemArchive,
  handleRoutineItemPatch,
  type RoutineRouteDependencies,
} from '@/lib/mobile-api/routine-route-handlers'

const USER_ID = '00000000-0000-0000-0000-000000000761'
const ITEM_ID = '00000000-0000-0000-0000-000000000762'

function context(method: string, body: unknown): MobileRouteContext {
  return {
    request: new Request(`https://bodyflow.test/api/mobile/v1/medications/${ITEM_ID}`, {
      method,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': 'routine-medication-item-0761',
      },
      body: JSON.stringify(body),
    }),
    requestId: 'request-medication-item-0761',
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

function repository(): RoutineItemRepository {
  return {
    list: vi.fn(async () => ({
      localDate: '2026-07-22',
      items: [
        {
          id: ITEM_ID,
          itemType: 'medication' as const,
          name: 'Medication',
          doseText: '1 unit',
          origin: 'professional' as const,
          remindersEnabled: true,
          active: true,
          archivedAt: null,
          version: 2,
          createdAt: '2026-07-20T12:00:00.000Z',
          updatedAt: '2026-07-22T12:00:00.000Z',
          schedules: [],
        },
      ],
    })),
    create: vi.fn(),
    update: vi.fn(async () => ({ routineItemId: ITEM_ID, version: 3, archivedAt: null })),
    archive: vi.fn(async () => ({
      routineItemId: ITEM_ID,
      version: 4,
      archivedAt: '2026-07-22T15:00:00.000Z',
    })),
    history: vi.fn(),
  }
}

function dependencies(routineRepository: RoutineItemRepository): RoutineRouteDependencies {
  return {
    createRoutineItemDependencies: vi.fn(() => ({ repository: routineRepository })),
    executeIdempotent: vi.fn(async (_context, _payload, operation) =>
      operation('routine-medication-item-0761'),
    ),
    now: vi.fn(() => new Date('2026-07-22T14:30:00.000Z')),
  }
}

describe('mobile medication item route', () => {
  it('invokes exported PATCH and DELETE routes closed over medication', async () => {
    vi.resetModules()
    const patch = vi.fn(async () => new Response(null, { status: 200 }))
    const archive = vi.fn(async () => new Response(null, { status: 200 }))
    const createPatch = vi.fn(() => patch)
    const createArchive = vi.fn(() => archive)
    vi.doMock('@/lib/mobile-api/routine-route-handlers', () => ({
      createRoutineItemArchiveRoute: createArchive,
      createRoutineItemPatchRoute: createPatch,
    }))

    try {
      const routes = await import('./route')
      const request = new Request(`https://bodyflow.test/api/mobile/v1/medications/${ITEM_ID}`)
      const params = { params: Promise.resolve({ id: ITEM_ID }) }
      await routes.PATCH(request, params)
      await routes.DELETE(request, params)

      expect(createPatch).toHaveBeenCalledWith('medication')
      expect(createArchive).toHaveBeenCalledWith('medication')
      expect(patch).toHaveBeenCalledOnce()
      expect(archive).toHaveBeenCalledOnce()
    } finally {
      vi.doUnmock('@/lib/mobile-api/routine-route-handlers')
      vi.resetModules()
    }
  })

  it('forwards medication through patch and archive handlers', async () => {
    const routineRepository = repository()
    const deps = dependencies(routineRepository)
    const routeContext = { params: Promise.resolve({ id: ITEM_ID }) }

    await handleRoutineItemPatch(
      context('PATCH', { expected_version: 2, reminders_enabled: false }),
      routeContext,
      'medication',
      deps,
    )
    await handleRoutineItemArchive(context('DELETE', {}), routeContext, 'medication', deps)

    expect(vi.mocked(deps.executeIdempotent).mock.calls[0]?.[1]).toEqual({
      item_type: 'medication',
      routine_item_id: ITEM_ID,
      expected_version: 2,
      reminders_enabled: false,
    })
    expect(vi.mocked(deps.executeIdempotent).mock.calls[1]?.[1]).toEqual({
      routine_item_id: ITEM_ID,
    })
    expect(routineRepository.update).toHaveBeenCalledWith(
      expect.objectContaining({ itemType: 'medication', routineItemId: ITEM_ID }),
    )
    expect(routineRepository.archive).toHaveBeenCalledWith(
      expect.objectContaining({ itemType: 'medication', routineItemId: ITEM_ID }),
    )
  })

  it('returns one non-disclosing 404 for a supplement id on medication routes', async () => {
    const routineRepository = repository()
    vi.mocked(routineRepository.list).mockResolvedValue({ localDate: '2026-07-22', items: [] })

    await expect(
      handleRoutineItemPatch(
        context('PATCH', { expected_version: 2, reminders_enabled: false }),
        { params: Promise.resolve({ id: ITEM_ID }) },
        'medication',
        dependencies(routineRepository),
      ),
    ).rejects.toMatchObject({ status: 404, code: 'routine_item_not_found' })
    expect(routineRepository.update).not.toHaveBeenCalled()
  })
})
