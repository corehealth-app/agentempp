import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from '@/lib/mobile-api/http'
import { executeIdempotent, type MobileIdempotencyStore } from '@/lib/mobile-api/idempotency'
import type { MobileRouteContext, MobileRouteRuntime } from '@/lib/mobile-api/route'
import type {
  RoutineItemRepository,
  RoutineItemServiceDependencies,
} from '@/lib/mobile-api/routine-item-service'
import {
  createRoutineCollectionGetRoute,
  handleRoutineCollectionGet,
  handleRoutineCollectionPost,
  type RoutineRouteDependencies,
} from '@/lib/mobile-api/routine-route-handlers'

const USER_ID = '00000000-0000-0000-0000-000000000721'
const AUTH_USER_ID = '00000000-0000-0000-0000-000000000722'
const ITEM_ID = '00000000-0000-0000-0000-000000000723'
const NOW = new Date('2026-07-22T14:30:00.000Z')

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

function context(
  url: string,
  options: {
    method?: string
    body?: unknown
    contentType?: string | null
    idempotencyKey?: string
  } = {},
): MobileRouteContext {
  const headers = new Headers()
  if (options.body !== undefined && options.contentType !== null) {
    headers.set('content-type', options.contentType ?? 'application/json')
  }
  if (options.idempotencyKey) headers.set('idempotency-key', options.idempotencyKey)
  return {
    request: new Request(url, {
      method: options.method ?? 'GET',
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    }),
    requestId: 'request-routine-route-0721',
    supabase: { rpc: vi.fn() } as unknown as ServiceClient,
    auth: {
      accessToken: 'redacted',
      authUserId: AUTH_USER_ID,
      userId: USER_ID,
      identity: {
        id: AUTH_USER_ID,
        email: 'synthetic@example.invalid',
        emailConfirmedAt: '2026-07-22T10:00:00.000Z',
      },
      patient: {
        id: USER_ID,
        authUserId: AUTH_USER_ID,
        email: 'synthetic@example.invalid',
        name: 'Synthetic',
        locale: 'pt-BR',
        timezone: 'America/New_York',
        country: 'US',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function dependencies(
  service: RoutineItemServiceDependencies,
  executeIdempotentDependency: RoutineRouteDependencies['executeIdempotent'] = vi.fn(
    async (_context, _payload, operation) => operation('routine-route-key-0721'),
  ),
): RoutineRouteDependencies {
  return {
    createRoutineItemDependencies: vi.fn(() => service),
    executeIdempotent: executeIdempotentDependency,
    now: vi.fn(() => NOW),
  }
}

describe('mobile supplement collection route', () => {
  it('invokes exported GET and POST routes closed over supplement', async () => {
    vi.resetModules()
    const get = vi.fn(async () => new Response(null, { status: 204 }))
    const post = vi.fn(async () => new Response(null, { status: 201 }))
    const createGet = vi.fn(() => get)
    const createPost = vi.fn(() => post)
    vi.doMock('@/lib/mobile-api/routine-route-handlers', () => ({
      createRoutineCollectionGetRoute: createGet,
      createRoutineCollectionPostRoute: createPost,
    }))

    try {
      const routes = await import('./route')
      await routes.GET(new Request('https://bodyflow.test/api/mobile/v1/supplements'))
      await routes.POST(
        new Request('https://bodyflow.test/api/mobile/v1/supplements', { method: 'POST' }),
      )

      expect(createGet).toHaveBeenCalledWith('supplement')
      expect(createPost).toHaveBeenCalledWith('supplement')
      expect(get).toHaveBeenCalledOnce()
      expect(post).toHaveBeenCalledOnce()
    } finally {
      vi.doUnmock('@/lib/mobile-api/routine-route-handlers')
      vi.resetModules()
    }
  })

  it('authenticates before creating dependencies or reading the repository', async () => {
    const routineRepository = repository()
    const deps = dependencies({ repository: routineRepository })
    const runtime: MobileRouteRuntime = {
      authenticate: vi
        .fn()
        .mockRejectedValue(
          new MobileApiError(401, 'missing_access_token', 'Authentication required'),
        ),
      createServiceClient: vi.fn(() => ({ rpc: vi.fn() }) as unknown as ServiceClient),
      createRequestId: vi.fn(() => 'request-routine-auth-0721'),
    }
    const route = createRoutineCollectionGetRoute('supplement', runtime, deps)

    const response = await route(new Request('https://bodyflow.test/api/mobile/v1/supplements'))

    expect(response.status).toBe(401)
    expect(deps.createRoutineItemDependencies).not.toHaveBeenCalled()
    expect(routineRepository.list).not.toHaveBeenCalled()
  })

  it('strictly parses the archived filter and forwards no client timezone or date', async () => {
    const routineRepository = repository()
    const deps = dependencies({ repository: routineRepository })
    const mobileContext = context(
      'https://bodyflow.test/api/mobile/v1/supplements?include_archived=true',
    )

    const response = await handleRoutineCollectionGet(mobileContext, 'supplement', deps)

    expect(response.status).toBe(200)
    expect(routineRepository.list).toHaveBeenCalledWith({
      userId: USER_ID,
      itemType: 'supplement',
      includeArchived: true,
      now: NOW.toISOString(),
    })
    await expect(response.json()).resolves.toMatchObject({
      data: { local_date: '2026-07-22', items: [] },
      meta: { request_id: 'request-routine-route-0721' },
    })

    await expect(
      handleRoutineCollectionGet(
        context('https://bodyflow.test/api/mobile/v1/supplements?timezone=UTC'),
        'supplement',
        deps,
      ),
    ).rejects.toThrow()
    await expect(
      handleRoutineCollectionGet(
        context(
          'https://bodyflow.test/api/mobile/v1/supplements?include_archived=true&include_archived=false',
        ),
        'supplement',
        deps,
      ),
    ).rejects.toThrow()
  })

  it('requires JSON, a strict body, and Idempotency-Key before create access', async () => {
    const routineRepository = repository()
    const deps = dependencies({ repository: routineRepository })
    const body = {
      name: 'Creatina',
      dose_text: '3 g',
      origin: 'user',
      reminders_enabled: true,
      schedules: [{ local_time: '08:00', weekdays: [1, 3, 5] }],
    }

    await expect(
      handleRoutineCollectionPost(
        context('https://bodyflow.test/api/mobile/v1/supplements', {
          method: 'POST',
          body,
          contentType: null,
        }),
        'supplement',
        deps,
      ),
    ).rejects.toMatchObject({ status: 415, code: 'unsupported_media_type' })
    await expect(
      handleRoutineCollectionPost(
        context('https://bodyflow.test/api/mobile/v1/supplements', {
          method: 'POST',
          body: { ...body, item_type: 'medication' },
          idempotencyKey: 'routine-create-0721',
        }),
        'supplement',
        deps,
      ),
    ).rejects.toThrow()

    const noKeyDependencies = dependencies(
      { repository: routineRepository },
      (mobileContext, payload, operation, options) =>
        import('@/lib/mobile-api/idempotency').then(({ executeSupabaseIdempotent }) =>
          executeSupabaseIdempotent(mobileContext, payload, operation, options),
        ),
    )
    await expect(
      handleRoutineCollectionPost(
        context('https://bodyflow.test/api/mobile/v1/supplements', {
          method: 'POST',
          body,
        }),
        'supplement',
        noKeyDependencies,
      ),
    ).rejects.toMatchObject({ status: 400, code: 'missing_idempotency_key' })
    expect(routineRepository.create).not.toHaveBeenCalled()
  })

  it('creates with 201 and hashes the literal type with validated input', async () => {
    const routineRepository = repository()
    const execute = vi.fn(async (_context, payload, operation) => {
      expect(payload).toEqual({
        item_type: 'supplement',
        name: 'Creatina',
        dose_text: '3 g',
        origin: 'user',
        reminders_enabled: true,
        schedules: [{ local_time: '08:00', weekdays: [1, 3, 5] }],
      })
      return operation('routine-create-0721')
    }) as RoutineRouteDependencies['executeIdempotent']
    const deps = dependencies({ repository: routineRepository }, execute)

    const response = await handleRoutineCollectionPost(
      context('https://bodyflow.test/api/mobile/v1/supplements', {
        method: 'POST',
        body: {
          name: ' Creatina ',
          dose_text: ' 3 g ',
          origin: 'user',
          reminders_enabled: true,
          schedules: [{ local_time: '08:00', weekdays: [5, 1, 3] }],
        },
        idempotencyKey: 'routine-create-0721',
      }),
      'supplement',
      deps,
    )

    expect(response.status).toBe(201)
    expect(routineRepository.create).toHaveBeenCalledWith(
      expect.objectContaining({
        itemType: 'supplement',
        idempotencyKey: 'routine-create-0721',
        requestHash: expect.stringMatching(/^[0-9a-f]{64}$/),
      }),
    )
    await expect(response.json()).resolves.toMatchObject({
      data: { routine_item_id: ITEM_ID, version: 1 },
    })
  })

  it('replays POST without repository access', async () => {
    const routineRepository = repository()
    const store: MobileIdempotencyStore = {
      claim: vi.fn(async () => ({
        action: 'replay' as const,
        status: 201,
        body: {
          data: { routine_item_id: ITEM_ID, version: 1 },
          meta: { api_version: 'v1', request_id: 'old-request' },
        },
      })),
      complete: vi.fn(),
      fail: vi.fn(),
    }
    const execute: RoutineRouteDependencies['executeIdempotent'] = (
      mobileContext,
      payload,
      operation,
      options,
    ) => executeIdempotent(mobileContext, payload, store, operation, options)
    const deps = dependencies({ repository: routineRepository }, execute)

    const response = await handleRoutineCollectionPost(
      context('https://bodyflow.test/api/mobile/v1/supplements', {
        method: 'POST',
        body: {
          name: 'Creatina',
          dose_text: '3 g',
          origin: 'user',
          reminders_enabled: true,
          schedules: [{ local_time: '08:00', weekdays: [1] }],
        },
        idempotencyKey: 'routine-replay-0721',
      }),
      'supplement',
      deps,
    )

    expect(response.status).toBe(201)
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect(routineRepository.create).not.toHaveBeenCalled()
  })
})
