import { describe, expect, it, vi } from 'vitest'
import type { ContentRecord } from '@/lib/mobile-api/content-service'
import { type ContentCoverProxyDependencies, handleContentCoverProxy } from './handlers'

const USER_ID = '00000000-0000-0000-0000-000000000511'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000512'
const TOKEN = 'opaque-cover-capability'
const NOW_SECONDS = 1_784_635_200

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

describe('content cover proxy route', () => {
  it('revalidates the capability and proxies allowed image bytes without a redirect', async () => {
    const deps = dependencies()

    const response = await handleContentCoverProxy(
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
        { params: Promise.resolve({ token: TOKEN }) },
        deps,
      )

      expect(response.status).toBe(404)
      await expect(response.json()).resolves.toEqual({
        error: {
          code: 'content_cover_not_found',
          message: 'Content cover not found',
        },
      })
    }

    expect(JSON.stringify(consoleError.mock.calls)).not.toMatch(
      /opaque-cover|private-hydration|patient-private|provider\.invalid|00000000/i,
    )
  })
})
