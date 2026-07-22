import { describe, expect, it } from 'vitest'
import {
  filterAdminListPublications,
  selectAdminListMatchedVersion,
  textAdminListScanFilters,
} from './admin-list-filter'
import type { ContentAdminFilters, ContentPublicationSummary } from './admin-service'

const NOW = Date.parse('2026-07-21T12:00:00.000Z')
const PT_VERSION_ID = '00000000-0000-4000-8000-000000000101'
const EN_VERSION_ID = '00000000-0000-4000-8000-000000000102'
const PT_AUTHOR_ID = '00000000-0000-4000-8000-000000000201'
const EN_AUTHOR_ID = '00000000-0000-4000-8000-000000000202'

function summary(
  versions: ContentPublicationSummary['versions'],
  overrides: Partial<ContentPublicationSummary> = {},
): ContentPublicationSummary {
  return {
    publicationId: '00000000-0000-4000-8000-000000000001',
    slug: 'bilingual-publication',
    archivedAt: null,
    createdAt: '2026-07-20T12:00:00.000Z',
    updatedAt: '2026-07-21T12:00:00.000Z',
    versions,
    ...overrides,
  }
}

function version(
  overrides: Partial<ContentPublicationSummary['versions'][number]> = {},
): ContentPublicationSummary['versions'][number] {
  return {
    versionId: PT_VERSION_ID,
    version: 1,
    locale: 'pt-BR',
    category: 'nutrition',
    title: 'Versao em portugues',
    state: 'draft',
    featuredToday: false,
    authorId: PT_AUTHOR_ID,
    reviewerId: null,
    publishAt: null,
    updatedAt: '2026-07-21T11:00:00.000Z',
    ...overrides,
  }
}

describe('admin list version filter', () => {
  it('restricts locale and returns the latest en-US version that matched', () => {
    const publication = summary([
      version({ version: 3 }),
      version({ versionId: EN_VERSION_ID, locale: 'en-US', title: 'English version' }),
    ])

    expect(selectAdminListMatchedVersion(publication, { locale: 'en-US' }, NOW)?.versionId).toBe(
      EN_VERSION_ID,
    )
  })

  it('requires every condition on one latest locale candidate', () => {
    const publication = summary([
      version({ version: 2, category: 'nutrition', authorId: PT_AUTHOR_ID }),
      version({
        versionId: EN_VERSION_ID,
        locale: 'en-US',
        version: 4,
        category: 'training',
        authorId: EN_AUTHOR_ID,
      }),
    ])

    expect(
      selectAdminListMatchedVersion(
        publication,
        { category: 'training', authorId: EN_AUTHOR_ID },
        NOW,
      )?.versionId,
    ).toBe(EN_VERSION_ID)
    expect(
      selectAdminListMatchedVersion(
        publication,
        { category: 'nutrition', authorId: EN_AUTHOR_ID },
        NOW,
      ),
    ).toBeNull()
  })

  it('selects pt-BR deterministically when both latest locale candidates match', () => {
    const publication = summary([
      version({ versionId: EN_VERSION_ID, locale: 'en-US', version: 9 }),
      version({ version: 2 }),
    ])

    expect(
      selectAdminListMatchedVersion(publication, { featuredToday: false }, NOW)?.versionId,
    ).toBe(PT_VERSION_ID)
  })

  it('preserves every version while annotating the matched candidate', () => {
    const historicalPtVersionId = '00000000-0000-4000-8000-000000000103'
    const publication = summary([
      version({ versionId: historicalPtVersionId, version: 1, state: 'rejected' }),
      version({ version: 2 }),
      version({ versionId: EN_VERSION_ID, locale: 'en-US' }),
    ])

    expect(filterAdminListPublications([publication], { locale: 'pt-BR' }, NOW)).toEqual([
      expect.objectContaining({
        matchedVersionId: PT_VERSION_ID,
        versions: publication.versions,
      }),
    ])
  })

  it('requires text to match the exact latest locale candidate selected by structured filters', () => {
    const publication = summary([
      version({ versionId: '00000000-0000-4000-8000-000000000103', version: 1, title: 'Legado' }),
      version({ version: 2, title: 'Titulo atual' }),
      version({
        versionId: EN_VERSION_ID,
        locale: 'en-US',
        version: 3,
        category: 'training',
        title: 'Legacy English',
      }),
    ])
    const filterWithText = filterAdminListPublications as (
      publications: readonly ContentPublicationSummary[],
      filters: ContentAdminFilters,
      now: number,
      text: string,
    ) => ContentPublicationSummary[]

    expect(
      filterWithText([publication], { category: 'nutrition', limit: 25, offset: 0 }, NOW, 'legado'),
    ).toEqual([])
    expect(
      filterWithText([publication], { category: 'nutrition', limit: 25, offset: 0 }, NOW, 'atual'),
    ).toEqual([expect.objectContaining({ matchedVersionId: PT_VERSION_ID })])
  })

  it('builds raw text batches without version filters and keeps only archived partitioning', () => {
    const filters: ContentAdminFilters = {
      status: 'published',
      locale: 'en-US',
      category: 'training',
      authorId: EN_AUTHOR_ID,
      reviewerId: PT_AUTHOR_ID,
      schedule: 'published',
      featuredToday: true,
      limit: 25,
      offset: 50,
    }

    expect(textAdminListScanFilters(filters, 300, 100)).toEqual({ limit: 100, offset: 300 })
    expect(textAdminListScanFilters({ ...filters, status: 'archived' }, 400, 100)).toEqual({
      status: 'archived',
      limit: 100,
      offset: 400,
    })
  })
})
