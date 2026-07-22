import { describe, expect, it, vi } from 'vitest'
import type { ContentRecord } from '@/lib/mobile-api/content-service'
import { MobileApiError } from '@/lib/mobile-api/http'
import type { MobileRouteRuntime } from '@/lib/mobile-api/route'
import {
  type ContentCoverProxyDependencies,
  createContentCoverProxyRoute,
  handleContentCoverProxy,
} from './handlers'

const USER_ID = '00000000-0000-0000-0000-000000000511'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000512'
const TOKEN = 'opaque-cover-capability'
const NOW_SECONDS = 1_784_635_200
const REQUEST_ID = 'request-cover-511'
const OTHER_USER_ID = '00000000-0000-0000-0000-000000000519'

function contentRecord(overrides: Partial<ContentRecord> = {}): ContentRecord {
  return {
    publicationId: PUBLICATION_ID,
    slug: 'hidratacao-pratica',
    locale: 'pt-BR',
    title: 'Hidratacao pratica',
    excerpt: 'Organize pequenos momentos de hidratacao ao longo de uma rotina possivel.',
    bodyMarkdown:
      '## Hidratacao ao longo do dia\n\nDistribua a ingestao de agua em momentos praticos e ajuste conforme sua sede e orientacao profissional.',
    category: 'hydration',
    tags: ['hidratacao'],
    readingTimeMinutes: 2,
    publishAt: '2026-07-21T10:00:00.000Z',
    featuredToday: true,
    version: 7,
    saved: false,
    completed: false,
    cover: {
      bucketId: 'content-covers',
      objectPath: 'content/private-hydration.webp',
    },
    ...overrides,
  }
}

function dependencies(): ContentCoverProxyDependencies {
  return {
    capabilities: {
      open: vi.fn(() => ({
        userId: USER_ID,
        publicationId: PUBLICATION_ID,
        version: 7,
        issuedAt: NOW_SECONDS,
        expiresAt: NOW_SECONDS + 300,
      })),
    },
    repository: { get: vi.fn(async () => contentRecord()) },
    storage: {
      download: vi.fn(
        async () =>
          new Blob([new Uint8Array([82, 73, 70, 70])], {
            type: 'image/webp',
          }),
      ),
    },
    clock: () => (NOW_SECONDS + 40) * 1000,
  }
}

function patientContext(userId = USER_ID) {
  return {
    accessToken: 'synthetic-access-token',
    authUserId: '00000000-0000-0000-0000-000000000510',
    userId,
    identity: {
      id: '00000000-0000-0000-0000-000000000510',
      email: 'patient@example.invalid',
      emailConfirmedAt: '2026-07-21T00:00:00.000Z',
    },
    patient: {
      id: userId,
      authUserId: '00000000-0000-0000-0000-000000000510',
      email: 'patient@example.invalid',
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
}

function runtime(overrides: Partial<MobileRouteRuntime> = {}): MobileRouteRuntime {
  return {
    authenticate: vi.fn().mockResolvedValue(patientContext()),
    createServiceClient: vi.fn().mockReturnValue({}),
    createRequestId: vi.fn().mockReturnValue(REQUEST_ID),
    ...overrides,
  } as MobileRouteRuntime
}

function handlerContext(userId = USER_ID) {
  return { auth: patientContext(userId), requestId: REQUEST_ID }
}

describe('content cover proxy route', () => {
  it('returns the existing mobile 401 envelope before opening a capability without bearer auth', async () => {
    const deps = dependencies()
    const route = createContentCoverProxyRoute(
      runtime({
        authenticate: vi
          .fn()
          .mockRejectedValue(
            new MobileApiError(401, 'missing_access_token', 'Authentication required'),
          ),
      }),
      () => deps,
    )

    const response = await route(
      new Request(`https://example.test/api/mobile/v1/content/covers/${TOKEN}`),
      { params: Promise.resolve({ token: TOKEN }) },
    )

    expect(response.status).toBe(401)
    await expect(response.json()).resolves.toEqual({
      error: {
        code: 'missing_access_token',
        message: 'Authentication required',
        request_id: REQUEST_ID,
      },
    })
    expect(response.headers.get('x-request-id')).toBe(REQUEST_ID)
    expect(response.headers.get('vary')).toBe('Authorization')
    expect(deps.capabilities.open).not.toHaveBeenCalled()
  })

  it.each([
    [401, 'invalid_access_token', 'Authentication required'],
    [403, 'patient_account_inactive', 'Patient account is not active'],
  ])('returns the existing mobile %i envelope before opening a capability for auth failure %s', async (status, code, message) => {
    const deps = dependencies()
    const route = createContentCoverProxyRoute(
      runtime({
        authenticate: vi.fn().mockRejectedValue(new MobileApiError(status, code, message)),
      }),
      () => deps,
    )

    const response = await route(
      new Request(`https://example.test/api/mobile/v1/content/covers/${TOKEN}`, {
        headers: { Authorization: 'Bearer rejected-access-token' },
      }),
      { params: Promise.resolve({ token: TOKEN }) },
    )

    expect(response.status).toBe(status)
    await expect(response.json()).resolves.toEqual({
      error: { code, message, request_id: REQUEST_ID },
    })
    expect(deps.capabilities.open).not.toHaveBeenCalled()
  })

  it('returns the opaque mobile 404 without repository access when the patient differs from the capability', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const deps = dependencies()
    const route = createContentCoverProxyRoute(
      runtime({ authenticate: vi.fn().mockResolvedValue(patientContext(OTHER_USER_ID)) }),
      () => deps,
    )

    const response = await route(
      new Request(`https://example.test/api/mobile/v1/content/covers/${TOKEN}`, {
        headers: { Authorization: 'Bearer synthetic-access-token' },
      }),
      { params: Promise.resolve({ token: TOKEN }) },
    )

    expect(response.status).toBe(404)
    await expect(response.json()).resolves.toEqual({
      error: {
        code: 'content_cover_not_found',
        message: 'Content cover not found',
        request_id: REQUEST_ID,
      },
    })
    expect(deps.repository.get).not.toHaveBeenCalled()
  })

  it('returns authenticated image bytes with request correlation and authorization variance', async () => {
    const deps = dependencies()
    const mobileRuntime = runtime()
    const createDependencies = vi.fn(() => deps)
    const route = createContentCoverProxyRoute(mobileRuntime, createDependencies)

    const request = new Request(`https://example.test/api/mobile/v1/content/covers/${TOKEN}`, {
      headers: { Authorization: 'Bearer synthetic-access-token' },
    })
    const response = await route(request, { params: Promise.resolve({ token: TOKEN }) })

    expect(mobileRuntime.authenticate).toHaveBeenCalledWith(request, {})
    expect(createDependencies).toHaveBeenCalledWith(
      expect.objectContaining({ requestId: REQUEST_ID, supabase: {} }),
    )
    expect(deps.repository.get).toHaveBeenCalledWith(USER_ID, PUBLICATION_ID)
    expect(response.status).toBe(200)
    expect(response.headers.get('x-request-id')).toBe(REQUEST_ID)
    expect(response.headers.get('vary')).toBe('Authorization')
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(new Uint8Array([82, 73, 70, 70]))
  })

  it('logs proxy failures with only request correlation and allowlisted technical fields', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const deps = dependencies()
    vi.mocked(deps.repository.get).mockRejectedValue(
      new Error('provider patient@example.invalid failed at content/private-hydration.webp'),
    )

    const response = await handleContentCoverProxy(
      handlerContext(),
      { params: Promise.resolve({ token: TOKEN }) },
      deps,
    )

    expect(response.status).toBe(500)
    await expect(response.json()).resolves.toEqual({
      error: {
        code: 'internal_error',
        message: 'Unexpected server error',
        request_id: REQUEST_ID,
      },
    })
    expect(consoleError).toHaveBeenCalledWith('[mobile-content-cover] operation_failed', {
      request_id: REQUEST_ID,
      operation: 'repository_get',
      error_code: 'repository_error',
    })
    expect(Object.keys(consoleError.mock.calls[0]?.[1] ?? {}).sort()).toEqual([
      'error_code',
      'operation',
      'request_id',
    ])
    expect(JSON.stringify(consoleError.mock.calls)).not.toMatch(
      /opaque-cover|private-hydration|content-covers|00000000|synthetic-access|patient@|provider/i,
    )
  })

  it('contains dependency initialization failures without logging route or provider details', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const route = createContentCoverProxyRoute(runtime(), () => {
      throw new Error(
        `secret failed for /api/mobile/v1/content/covers/${TOKEN} and patient@example.invalid`,
      )
    })

    const response = await route(
      new Request(`https://example.test/api/mobile/v1/content/covers/${TOKEN}`, {
        headers: { Authorization: 'Bearer synthetic-access-token' },
      }),
      { params: Promise.resolve({ token: TOKEN }) },
    )

    expect(response.status).toBe(500)
    await expect(response.json()).resolves.toEqual({
      error: {
        code: 'internal_error',
        message: 'Unexpected server error',
        request_id: REQUEST_ID,
      },
    })
    expect(consoleError).toHaveBeenCalledWith('[mobile-content-cover] operation_failed', {
      request_id: REQUEST_ID,
      operation: 'dependency_init',
      error_code: 'internal_error',
    })
    expect(JSON.stringify(consoleError.mock.calls)).not.toMatch(/opaque-cover|patient@|\/api\//i)
  })

  it('revalidates the capability and proxies allowed image bytes without a redirect', async () => {
    const deps = dependencies()

    const response = await handleContentCoverProxy(
      handlerContext(),
      { params: Promise.resolve({ token: TOKEN }) },
      deps,
    )

    expect(deps.capabilities.open).toHaveBeenCalledWith(TOKEN)
    expect(deps.repository.get).toHaveBeenCalledWith(USER_ID, PUBLICATION_ID)
    expect(deps.storage.download).toHaveBeenCalledWith(
      'content-covers',
      'content/private-hydration.webp',
    )
    expect(response.status).toBe(200)
    expect(response.headers.get('content-type')).toBe('image/webp')
    expect(response.headers.get('x-content-type-options')).toBe('nosniff')
    expect(response.headers.get('cache-control')).toBe('private, max-age=260')
    expect(response.headers.get('location')).toBeNull()
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(new Uint8Array([82, 73, 70, 70]))
    expect(JSON.stringify([...response.headers])).not.toContain('content/private-hydration.webp')
  })

  it('returns one opaque response for invalid, expired, ineligible, stale, and missing covers', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const cases: Array<(deps: ContentCoverProxyDependencies) => void> = [
      (deps) =>
        vi.mocked(deps.capabilities.open).mockImplementation(() => {
          throw new Error(TOKEN)
        }),
      (deps) => {
        vi.mocked(deps.capabilities.open).mockReturnValue({
          userId: USER_ID,
          publicationId: PUBLICATION_ID,
          version: 7,
          issuedAt: NOW_SECONDS - 300,
          expiresAt: NOW_SECONDS,
        })
        deps.clock = () => NOW_SECONDS * 1000
      },
      (deps) => vi.mocked(deps.repository.get).mockResolvedValue(null),
      (deps) =>
        vi
          .mocked(deps.repository.get)
          .mockResolvedValue(
            contentRecord({ publicationId: '00000000-0000-0000-0000-000000000599' }),
          ),
      (deps) => vi.mocked(deps.repository.get).mockResolvedValue(contentRecord({ version: 8 })),
      (deps) => vi.mocked(deps.repository.get).mockResolvedValue(contentRecord({ cover: null })),
      (deps) =>
        vi.mocked(deps.repository.get).mockResolvedValue(
          contentRecord({
            cover: { bucketId: 'patient-private-media', objectPath: 'patient/private.jpg' },
          }),
        ),
      (deps) =>
        vi
          .mocked(deps.storage.download)
          .mockRejectedValue(new Error('https://provider.invalid/signed/private-cover')),
    ]

    for (const arrange of cases) {
      const deps = dependencies()
      arrange(deps)

      const response = await handleContentCoverProxy(
        handlerContext(),
        { params: Promise.resolve({ token: TOKEN }) },
        deps,
      )

      expect(response.status).toBe(404)
      await expect(response.json()).resolves.toEqual({
        error: {
          code: 'content_cover_not_found',
          message: 'Content cover not found',
          request_id: REQUEST_ID,
        },
      })
    }

    expect(JSON.stringify(consoleError.mock.calls)).not.toMatch(
      /opaque-cover|private-hydration|patient-private|provider\.invalid|00000000/i,
    )
  })
})
