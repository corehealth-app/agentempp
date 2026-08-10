import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import type {
  ContentFeedRecord,
  ContentRecord,
  ContentRepository,
  ContentServiceDependencies,
} from '@/lib/mobile-api/content-service'
import { MobileApiError } from '@/lib/mobile-api/http'
import {
  executeIdempotent,
  executeSupabaseIdempotent,
  type MobileIdempotencyStore,
} from '@/lib/mobile-api/idempotency'
import type { MobileRouteContext, MobileRouteRuntime } from '@/lib/mobile-api/route'
import {
  type ContentDetailRouteDependencies,
  createContentDetailRoute,
  handleContentDetail,
} from './[id]/handlers'
import { type ContentReadRouteDependencies, handleContentRead } from './[id]/read/handlers'
import { type ContentSaveRouteDependencies, handleContentSave } from './[id]/save/handlers'
import {
  type ContentListRouteDependencies,
  createContentListRoute,
  handleContentList,
} from './handlers'

const USER_ID = '00000000-0000-0000-0000-000000000421'
const AUTH_USER_ID = '00000000-0000-0000-0000-000000000422'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000423'
const PIPE_TABLE_MARKDOWN = `## Plano alimentar

| Refeição | Escolha possível |
| --- | --- |
| Café da manhã | Aveia, fruta e iogurte natural |

Ajuste as escolhas com calma para manter uma rotina alimentar possível e sustentável.`
const PORTABLE_INVALID_MARKDOWN = [
  ['strikethrough', `Texto com ~~conteúdo removido~~ e ${'orientação segura '.repeat(6)}`],
  ['checked task list', `- [x] Conclua este passo editorial com cuidado.\n\n${'orientação segura '.repeat(6)}`],
  ['uppercase checked task list', `- [X] Conclua este passo editorial com cuidado.\n\n${'orientação segura '.repeat(6)}`],
  ['unchecked task list', `- [ ] Conclua este passo editorial com cuidado.\n\n${'orientação segura '.repeat(6)}`],
  ['unclosed strong delimiter', `Texto com **ênfase sem fechamento ${'orientação segura '.repeat(6)}`],
] as const

function contentRecord(overrides: Partial<ContentRecord> = {}): ContentRecord {
  return {
    publicationId: PUBLICATION_ID,
    slug: 'nutricao-na-rotina',
    locale: 'pt-BR',
    title: 'Nutricao na rotina',
    excerpt: 'Organize escolhas consistentes que possam acompanhar seus horarios diarios.',
    bodyMarkdown:
      '## Escolhas consistentes\n\nOrganize refeicoes possiveis para sustentar sua rotina ao longo da semana.',
    category: 'nutrition',
    tags: ['nutricao', 'rotina'],
    readingTimeMinutes: 2,
    publishAt: '2026-07-21T12:00:00.000Z',
    featuredToday: false,
    version: 2,
    saved: false,
    completed: false,
    cover: null,
    ...overrides,
  }
}

function repository(overrides: Partial<ContentRepository> = {}): ContentRepository {
  return {
    list: vi.fn(async () => ({
      items: [contentRecord()] satisfies ContentFeedRecord[],
      nextCursor: null,
    })),
    get: vi.fn(async () => contentRecord()),
    recordRead: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      version: 2,
      saved: false,
      completed: true,
      changed: true,
      replayed: false,
    })),
    setSaved: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      version: 2,
      saved: true,
      completed: false,
      changed: true,
      replayed: false,
    })),
    ...overrides,
  }
}

function serviceDependencies(
  repositoryOverrides: Partial<ContentRepository> = {},
): ContentServiceDependencies {
  return {
    repository: repository(repositoryOverrides),
    covers: {
      issue: vi.fn(async () => ({
        token: 'opaque-cover-capability',
        expiresAt: '2026-07-21T12:10:00.000Z',
      })),
    },
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
  if (options.contentType !== null && options.body !== undefined) {
    headers.set('content-type', options.contentType ?? 'application/json')
  }
  if (options.idempotencyKey) headers.set('idempotency-key', options.idempotencyKey)

  return {
    request: new Request(url, {
      method: options.method ?? 'GET',
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    }),
    requestId: 'request-content-421',
    supabase: { rpc: vi.fn() } as unknown as ServiceClient,
    auth: {
      accessToken: 'redacted-test-token',
      authUserId: AUTH_USER_ID,
      userId: USER_ID,
      identity: {
        id: AUTH_USER_ID,
        email: 'synthetic@example.invalid',
        emailConfirmedAt: '2026-07-21T10:00:00.000Z',
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

function routeContext(id = PUBLICATION_ID) {
  return { params: Promise.resolve({ id }) }
}

function listDependencies(service: ContentServiceDependencies): ContentListRouteDependencies {
  return { createContentDependencies: vi.fn(() => service) }
}

function detailDependencies(service: ContentServiceDependencies): ContentDetailRouteDependencies {
  return { createContentDependencies: vi.fn(() => service) }
}

function readDependencies(
  service: ContentServiceDependencies,
  executeIdempotent: ContentReadRouteDependencies['executeIdempotent'] = vi.fn(
    async (_context, _payload, operation) => operation('content-read-normalized-421'),
  ),
): ContentReadRouteDependencies {
  return {
    createContentDependencies: vi.fn(() => service),
    executeIdempotent,
  }
}

function saveDependencies(
  service: ContentServiceDependencies,
  executeIdempotent: ContentSaveRouteDependencies['executeIdempotent'] = vi.fn(
    async (_context, _payload, operation) => operation('content-save-normalized-421'),
  ),
): ContentSaveRouteDependencies {
  return {
    createContentDependencies: vi.fn(() => service),
    executeIdempotent,
  }
}

describe('mobile educational content routes', () => {
  it('uses the authenticated route wrapper and short-circuits content access on auth failure', async () => {
    const service = serviceDependencies()
    const mobileRuntime: MobileRouteRuntime = {
      authenticate: vi
        .fn()
        .mockRejectedValue(
          new MobileApiError(401, 'missing_access_token', 'Authentication required'),
        ),
      authorizeEntitlement: vi.fn().mockResolvedValue(undefined),
      createServiceClient: vi.fn(() => ({ rpc: vi.fn() }) as unknown as ServiceClient),
      createRequestId: vi.fn(() => 'request-content-auth-421'),
    }
    const route = createContentListRoute(mobileRuntime, listDependencies(service))

    const response = await route(new Request('https://bodyflow.test/api/mobile/v1/content'))

    expect(response.status).toBe(401)
    expect(mobileRuntime.authenticate).toHaveBeenCalledOnce()
    expect(service.repository.list).not.toHaveBeenCalled()
  })

  it('lists only content returned for the authenticated patient with strict defaults', async () => {
    const service = serviceDependencies()
    const deps = listDependencies(service)
    const mobileContext = context('https://bodyflow.test/api/mobile/v1/content')

    const response = await handleContentList(mobileContext, deps)

    expect(response.status).toBe(200)
    expect(deps.createContentDependencies).toHaveBeenCalledWith(
      mobileContext.supabase,
      mobileContext.requestId,
    )
    expect(service.repository.list).toHaveBeenCalledWith(USER_ID, {
      surface: 'library',
      limit: 20,
    })
    await expect(response.json()).resolves.toMatchObject({
      data: {
        items: [{ publication_id: PUBLICATION_ID, locale: 'pt-BR' }],
        next_cursor: null,
      },
      meta: { api_version: 'v1', request_id: 'request-content-421' },
    })
  })

  it('rejects unknown and duplicate query keys before database access', async () => {
    const service = serviceDependencies()
    const deps = listDependencies(service)

    await expect(
      handleContentList(context('https://bodyflow.test/api/mobile/v1/content?locale=en-US'), deps),
    ).rejects.toThrow()
    await expect(
      handleContentList(
        context('https://bodyflow.test/api/mobile/v1/content?limit=10&limit=20'),
        deps,
      ),
    ).rejects.toThrow()
    expect(service.repository.list).not.toHaveBeenCalled()
  })

  it('returns eligible detail and validates the route UUID', async () => {
    const service = serviceDependencies()
    const deps = detailDependencies(service)
    const mobileContext = context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}`)

    const response = await handleContentDetail(mobileContext, routeContext(), deps)

    expect(response.status).toBe(200)
    expect(deps.createContentDependencies).toHaveBeenCalledWith(
      mobileContext.supabase,
      mobileContext.requestId,
    )
    expect(service.repository.get).toHaveBeenCalledWith(USER_ID, PUBLICATION_ID)
    await expect(response.json()).resolves.toMatchObject({
      data: {
        publication_id: PUBLICATION_ID,
        body_markdown: expect.stringContaining('Escolhas consistentes'),
      },
    })

    await expect(
      handleContentDetail(
        context('https://bodyflow.test/api/mobile/v1/content/not-a-uuid'),
        routeContext('not-a-uuid'),
        deps,
      ),
    ).rejects.toThrow()
  })

  it('returns one atomic opaque error for a legacy pipe-table detail without issuing a cover', async () => {
    const service = serviceDependencies({
      get: vi.fn(async () =>
        contentRecord({
          bodyMarkdown: PIPE_TABLE_MARKDOWN,
          cover: {
            bucketId: 'content-covers',
            objectPath: 'content/private-table-cover.webp',
          },
        }),
      ),
    })
    const baseContext = context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}`)
    const mobileRuntime: MobileRouteRuntime = {
      authenticate: vi.fn(async () => baseContext.auth),
      authorizeEntitlement: vi.fn(async () => undefined),
      createServiceClient: vi.fn(() => baseContext.supabase),
      createRequestId: vi.fn(() => 'request-content-table-421'),
    }
    const route = createContentDetailRoute(mobileRuntime, detailDependencies(service))

    const response = await route(baseContext.request, routeContext())
    const serialized = JSON.stringify(await response.json())

    expect(response.status).toBe(500)
    expect(JSON.parse(serialized)).toEqual({
      error: {
        code: 'internal_error',
        message: 'Unexpected server error',
        request_id: 'request-content-table-421',
      },
    })
    expect(serialized).not.toMatch(/body_markdown|Refeição|Aveia|Plano alimentar/)
    expect(service.covers.issue).not.toHaveBeenCalled()
  })

  it.each(PORTABLE_INVALID_MARKDOWN)(
    'returns one atomic opaque error for a legacy portable-invalid %s detail without issuing a cover',
    async (_description, bodyMarkdown) => {
      const service = serviceDependencies({
        get: vi.fn(async () =>
          contentRecord({
            bodyMarkdown,
            cover: {
              bucketId: 'content-covers',
              objectPath: 'content/private-nonportable-cover.webp',
            },
          }),
        ),
      })
      const baseContext = context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}`)
      const mobileRuntime: MobileRouteRuntime = {
        authenticate: vi.fn(async () => baseContext.auth),
        authorizeEntitlement: vi.fn(async () => undefined),
        createServiceClient: vi.fn(() => baseContext.supabase),
        createRequestId: vi.fn(() => 'request-content-nonportable-421'),
      }
      const route = createContentDetailRoute(mobileRuntime, detailDependencies(service))

      const response = await route(baseContext.request, routeContext())
      const serialized = JSON.stringify(await response.json())

      expect(response.status).toBe(500)
      expect(JSON.parse(serialized)).toEqual({
        error: {
          code: 'internal_error',
          message: 'Unexpected server error',
          request_id: 'request-content-nonportable-421',
        },
      })
      expect(serialized).not.toContain(bodyMarkdown)
      expect(serialized).not.toContain('body_markdown')
      expect(service.covers.issue).not.toHaveBeenCalled()
    },
  )

  it('uses one non-disclosing 404 for absent or ineligible detail', async () => {
    const service = serviceDependencies({ get: vi.fn(async () => null) })

    await expect(
      handleContentDetail(
        context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}`),
        routeContext(),
        detailDependencies(service),
      ),
    ).rejects.toMatchObject({ status: 404, code: 'content_not_found' })
  })

  it('requires JSON and Idempotency-Key for read mutations', async () => {
    const service = serviceDependencies()
    const noContentType = context(
      `https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/read`,
      {
        method: 'POST',
        body: { event: 'opened', origin: 'library', version: 2 },
        contentType: null,
      },
    )

    await expect(
      handleContentRead(noContentType, routeContext(), readDependencies(service)),
    ).rejects.toMatchObject({ status: 415, code: 'unsupported_media_type' })

    const noKey = context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/read`, {
      method: 'POST',
      body: { event: 'opened', origin: 'library', version: 2 },
    })
    await expect(
      handleContentRead(
        noKey,
        routeContext(),
        readDependencies(service, executeSupabaseIdempotent),
      ),
    ).rejects.toMatchObject({ status: 400, code: 'missing_idempotency_key' })
    expect(service.repository.recordRead).not.toHaveBeenCalled()
  })

  it('requires JSON and Idempotency-Key for save mutations', async () => {
    const service = serviceDependencies()
    const noContentType = context(
      `https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/save`,
      {
        method: 'POST',
        body: { saved: true, version: 2 },
        contentType: null,
      },
    )

    await expect(
      handleContentSave(noContentType, routeContext(), saveDependencies(service)),
    ).rejects.toMatchObject({ status: 415, code: 'unsupported_media_type' })

    const noKey = context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/save`, {
      method: 'POST',
      body: { saved: true, version: 2 },
    })
    await expect(
      handleContentSave(
        noKey,
        routeContext(),
        saveDependencies(service, executeSupabaseIdempotent),
      ),
    ).rejects.toMatchObject({ status: 400, code: 'missing_idempotency_key' })
    expect(service.repository.setSaved).not.toHaveBeenCalled()
  })

  it('rejects out-of-int32 read and save versions before idempotency or repository access', async () => {
    for (const version of [2_147_483_648, 1e100]) {
      const readService = serviceDependencies()
      const readDeps = readDependencies(readService)
      await expect(
        handleContentRead(
          context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/read`, {
            method: 'POST',
            body: { event: 'opened', origin: 'library', version },
            idempotencyKey: 'content-read-invalid-version-421',
          }),
          routeContext(),
          readDeps,
        ),
      ).rejects.toThrow()
      expect(readDeps.executeIdempotent).not.toHaveBeenCalled()
      expect(readService.repository.recordRead).not.toHaveBeenCalled()

      const saveService = serviceDependencies()
      const saveDeps = saveDependencies(saveService)
      await expect(
        handleContentSave(
          context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/save`, {
            method: 'POST',
            body: { saved: true, version },
            idempotencyKey: 'content-save-invalid-version-421',
          }),
          routeContext(),
          saveDeps,
        ),
      ).rejects.toThrow()
      expect(saveDeps.executeIdempotent).not.toHaveBeenCalled()
      expect(saveService.repository.setSaved).not.toHaveBeenCalled()
    }
  })

  it('passes the same normalized key through generic and database read idempotency', async () => {
    const service = serviceDependencies()
    const deps = readDependencies(service)
    const mobileContext = context(
      `https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/read`,
      {
        method: 'POST',
        body: { event: 'completed', origin: 'today', version: 2 },
        idempotencyKey: 'content-read-normalized-421',
      },
    )
    const response = await handleContentRead(mobileContext, routeContext(), deps)

    expect(deps.createContentDependencies).toHaveBeenCalledWith(
      mobileContext.supabase,
      mobileContext.requestId,
    )
    expect(deps.executeIdempotent).toHaveBeenCalledWith(
      expect.anything(),
      {
        publication_id: PUBLICATION_ID,
        event: 'completed',
        origin: 'today',
        version: 2,
      },
      expect.any(Function),
    )
    expect(service.repository.recordRead).toHaveBeenCalledWith({
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      event: 'completed',
      origin: 'today',
      version: 2,
      idempotencyKey: 'content-read-normalized-421',
    })
    await expect(response.json()).resolves.toMatchObject({
      data: {
        publication_id: PUBLICATION_ID,
        completed: true,
        saved: false,
      },
    })
  })

  it('replays a read response without applying another database mutation', async () => {
    const service = serviceDependencies()
    const replay = vi.fn(async () =>
      Response.json({
        data: {
          publication_id: PUBLICATION_ID,
          version: 2,
          saved: false,
          completed: true,
          changed: true,
          replayed: false,
        },
        meta: { api_version: 'v1', request_id: 'replayed-request' },
      }),
    )

    const response = await handleContentRead(
      context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/read`, {
        method: 'POST',
        body: { event: 'opened', origin: 'library', version: 2 },
        idempotencyKey: 'content-read-replay-421',
      }),
      routeContext(),
      readDependencies(service, replay),
    )

    expect(response.status).toBe(200)
    expect(service.repository.recordRead).not.toHaveBeenCalled()
  })

  it('uses server-owned library origin for save and returns only consolidated state', async () => {
    const service = serviceDependencies()
    const deps = saveDependencies(service)
    const mobileContext = context(
      `https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/save`,
      {
        method: 'POST',
        body: { saved: true, version: 2 },
        idempotencyKey: 'content-save-normalized-421',
      },
    )
    const response = await handleContentSave(mobileContext, routeContext(), deps)

    expect(deps.createContentDependencies).toHaveBeenCalledWith(
      mobileContext.supabase,
      mobileContext.requestId,
    )
    expect(service.repository.setSaved).toHaveBeenCalledWith({
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      saved: true,
      version: 2,
      origin: 'library',
      idempotencyKey: 'content-save-normalized-421',
    })
    const body = await response.json()
    expect(body.data).toEqual({
      publication_id: PUBLICATION_ID,
      version: 2,
      saved: true,
      completed: false,
      changed: true,
      replayed: false,
    })
    expect(JSON.stringify(body)).not.toContain('signed')
    expect(JSON.stringify(body)).not.toContain('bucket')
    expect(JSON.stringify(body)).not.toContain('path')
  })

  it('stores only consolidated state in generic idempotency completion', async () => {
    const service = serviceDependencies()
    const idempotencyStore: MobileIdempotencyStore = {
      claim: vi.fn(async () => ({ action: 'claimed' as const, claimId: 'claim-content-save-421' })),
      complete: vi.fn(async () => undefined),
      fail: vi.fn(async () => undefined),
    }
    const executeWithStore: typeof executeSupabaseIdempotent = (
      mobileContext,
      payload,
      operation,
      options,
    ) => executeIdempotent(mobileContext, payload, idempotencyStore, operation, options)

    const response = await handleContentSave(
      context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/save`, {
        method: 'POST',
        body: { saved: true, version: 2 },
        idempotencyKey: 'content-save-storage-421',
      }),
      routeContext(),
      saveDependencies(service, executeWithStore),
    )

    expect(response.status).toBe(200)
    expect(idempotencyStore.claim).toHaveBeenCalledWith(
      expect.objectContaining({ idempotencyKey: 'content-save-storage-421' }),
    )
    expect(service.repository.setSaved).toHaveBeenCalledWith(
      expect.objectContaining({ idempotencyKey: 'content-save-storage-421' }),
    )
    const storedBody = vi.mocked(idempotencyStore.complete).mock.calls[0]?.[3]
    expect(storedBody).toMatchObject({
      data: { publication_id: PUBLICATION_ID, saved: true },
    })
    expect(JSON.stringify(storedBody)).not.toMatch(/signed|url|bucket|object_path/i)
  })

  it('maps a stale read/save version to 409 content_version_changed', async () => {
    const stale = vi.fn(async () => {
      const { ContentRepositoryError } = await import('@/lib/mobile-api/content-service')
      throw new ContentRepositoryError('version_changed')
    })
    const readService = serviceDependencies({ recordRead: stale })
    const saveService = serviceDependencies({ setSaved: stale })

    await expect(
      handleContentRead(
        context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/read`, {
          method: 'POST',
          body: { event: 'opened', origin: 'library', version: 1 },
          idempotencyKey: 'content-read-stale-421',
        }),
        routeContext(),
        readDependencies(readService),
      ),
    ).rejects.toMatchObject({ status: 409, code: 'content_version_changed' })

    await expect(
      handleContentSave(
        context(`https://bodyflow.test/api/mobile/v1/content/${PUBLICATION_ID}/save`, {
          method: 'POST',
          body: { saved: true, version: 1 },
          idempotencyKey: 'content-save-stale-421',
        }),
        routeContext(),
        saveDependencies(saveService),
      ),
    ).rejects.toMatchObject({ status: 409, code: 'content_version_changed' })
  })
})
