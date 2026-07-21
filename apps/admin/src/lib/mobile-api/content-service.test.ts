import {
  type ContentListQuery,
  type ContentReadInput,
  type ContentSaveInput,
  encodeContentCursor,
} from '@mpp/core'
import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  type ContentRecord,
  type ContentRepository,
  ContentRepositoryError,
  type ContentServiceDependencies,
  getContent,
  listContent,
  recordContentRead,
  setContentSaved,
} from './content-service'

const USER_ID = '00000000-0000-0000-0000-000000000401'
const AUTH_USER_ID = '00000000-0000-0000-0000-000000000402'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000403'
const PUBLISH_AT = '2026-07-21T12:00:00.000Z'
const CURSOR = encodeContentCursor({
  publishAt: '2026-07-21T13:00:00.000Z',
  publicationId: '00000000-0000-0000-0000-000000000405',
})
const NEXT_CURSOR = encodeContentCursor({
  publishAt: PUBLISH_AT,
  publicationId: PUBLICATION_ID,
})

const auth = {
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
}

function contentRecord(overrides: Partial<ContentRecord> = {}): ContentRecord {
  return {
    publicationId: PUBLICATION_ID,
    slug: 'sono-e-recuperacao',
    locale: 'pt-BR',
    title: 'Sono e recuperacao',
    excerpt: 'Entenda como uma rotina consistente ajuda na recuperacao diaria.',
    bodyMarkdown:
      '## Sono consistente\n\nUma rotina de sono previsivel ajuda a organizar a recuperacao e os habitos diarios.',
    category: 'sleep',
    tags: ['sono', 'recuperacao'],
    readingTimeMinutes: 2,
    publishAt: PUBLISH_AT,
    featuredToday: true,
    version: 3,
    saved: false,
    completed: false,
    cover: {
      bucketId: 'content-covers',
      objectPath: 'content/private-cover.webp',
    },
    ...overrides,
  }
}

function repository(overrides: Partial<ContentRepository> = {}): ContentRepository {
  return {
    list: vi.fn(async () => ({ items: [contentRecord()], nextCursor: NEXT_CURSOR })),
    get: vi.fn(async () => contentRecord()),
    recordRead: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      version: 3,
      saved: false,
      completed: true,
      changed: true,
      replayed: false,
    })),
    setSaved: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      version: 3,
      saved: true,
      completed: false,
      changed: true,
      replayed: false,
    })),
    ...overrides,
  }
}

function dependencies(
  repositoryOverrides: Partial<ContentRepository> = {},
): ContentServiceDependencies {
  return {
    repository: repository(repositoryOverrides),
    covers: {
      sign: vi.fn(async () => 'https://storage.example.test/signed-cover'),
    },
  }
}

afterEach(() => {
  vi.useRealTimers()
})

describe('mobile educational content service', () => {
  it('maps an eligible feed to the public snake_case DTO and signs covers for 300 seconds', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-21T12:05:00.000Z'))
    const deps = dependencies()
    const query: ContentListQuery = {
      surface: 'library',
      category: 'sleep',
      limit: 20,
      cursor: CURSOR,
    }

    const result = await listContent(deps, auth, query)

    expect(deps.repository.list).toHaveBeenCalledWith(USER_ID, query)
    expect(deps.covers.sign).toHaveBeenCalledWith(
      'content-covers',
      'content/private-cover.webp',
      300,
    )
    expect(result).toEqual({
      items: [
        {
          publication_id: PUBLICATION_ID,
          slug: 'sono-e-recuperacao',
          locale: 'pt-BR',
          title: 'Sono e recuperacao',
          excerpt: 'Entenda como uma rotina consistente ajuda na recuperacao diaria.',
          category: 'sleep',
          tags: ['sono', 'recuperacao'],
          reading_time_minutes: 2,
          publish_at: PUBLISH_AT,
          featured_today: true,
          version: 3,
          saved: false,
          completed: false,
          cover: {
            url: 'https://storage.example.test/signed-cover',
            expires_at: '2026-07-21T12:10:00.000Z',
          },
        },
      ],
      next_cursor: NEXT_CURSOR,
    })
    expect(JSON.stringify(result)).not.toContain('content-covers')
    expect(JSON.stringify(result)).not.toContain('private-cover.webp')
    expect(JSON.stringify(result)).not.toContain('body_markdown')
  })

  it('returns a localized detail DTO without falling back or leaking the cover path', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-21T12:05:00.000Z'))
    const deps = dependencies()

    const result = await getContent(deps, auth, PUBLICATION_ID)

    expect(deps.repository.get).toHaveBeenCalledWith(USER_ID, PUBLICATION_ID)
    expect(result).toMatchObject({
      publication_id: PUBLICATION_ID,
      locale: 'pt-BR',
      body_markdown: expect.stringContaining('## Sono consistente'),
      cover: {
        url: 'https://storage.example.test/signed-cover',
        expires_at: '2026-07-21T12:10:00.000Z',
      },
    })
    expect(JSON.stringify(result)).not.toContain('bucketId')
    expect(JSON.stringify(result)).not.toContain('objectPath')
  })

  it('returns the same non-disclosing 404 for missing or ineligible content', async () => {
    const deps = dependencies({ get: vi.fn(async () => null) })

    await expect(getContent(deps, auth, PUBLICATION_ID)).rejects.toMatchObject({
      status: 404,
      code: 'content_not_found',
      message: 'Content item not found',
    })
    expect(deps.covers.sign).not.toHaveBeenCalled()
  })

  it('fails opaquely when a private cover capability cannot be created', async () => {
    const deps = dependencies()
    vi.mocked(deps.covers.sign).mockRejectedValue(new Error('private storage detail'))

    await expect(listContent(deps, auth, { surface: 'library', limit: 20 })).rejects.toMatchObject({
      status: 500,
      code: 'internal_error',
      message: 'Unexpected server error',
    })
  })

  it('records read state with the authenticated patient and the same event key', async () => {
    const deps = dependencies()
    const input: ContentReadInput = { event: 'completed', origin: 'today', version: 3 }

    const result = await recordContentRead(
      deps,
      auth,
      PUBLICATION_ID,
      input,
      'content-read-request-401',
    )

    expect(deps.repository.recordRead).toHaveBeenCalledWith({
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      event: 'completed',
      origin: 'today',
      version: 3,
      idempotencyKey: 'content-read-request-401',
    })
    expect(result).toEqual({
      publication_id: PUBLICATION_ID,
      version: 3,
      saved: false,
      completed: true,
      changed: true,
      replayed: false,
    })
  })

  it('maps a stale visible version to content_version_changed', async () => {
    const deps = dependencies({
      recordRead: vi.fn(async () => {
        throw new ContentRepositoryError('version_changed')
      }),
    })

    await expect(
      recordContentRead(
        deps,
        auth,
        PUBLICATION_ID,
        { event: 'opened', origin: 'library', version: 2 },
        'content-read-request-402',
      ),
    ).rejects.toMatchObject({
      status: 409,
      code: 'content_version_changed',
      message: 'Content version changed',
    })
  })

  it('uses the fixed library origin when changing saved state', async () => {
    const deps = dependencies()
    const input: ContentSaveInput = { saved: true, version: 3 }

    const result = await setContentSaved(
      deps,
      auth,
      PUBLICATION_ID,
      input,
      'content-save-request-401',
    )

    expect(deps.repository.setSaved).toHaveBeenCalledWith({
      userId: USER_ID,
      publicationId: PUBLICATION_ID,
      saved: true,
      version: 3,
      origin: 'library',
      idempotencyKey: 'content-save-request-401',
    })
    expect(result).toEqual({
      publication_id: PUBLICATION_ID,
      version: 3,
      saved: true,
      completed: false,
      changed: true,
      replayed: false,
    })
  })
})
