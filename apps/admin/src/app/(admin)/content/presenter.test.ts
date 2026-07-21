import { describe, expect, it } from 'vitest'
import type {
  ContentPublicationDetail,
  ContentPublicationSummary,
} from '@/lib/content/admin-service'
import {
  effectiveVersionStatus,
  filterPublicationSummaries,
  formatOperationalDate,
  localeCompleteness,
  paginatePublications,
  parsePublicationPage,
  parseUtcDateTimeLocal,
  scheduleLabel,
  selectLocaleVersions,
  toPublicationListRow,
  visibleContentCommands,
} from './presenter'

const NOW = '2026-07-21T12:00:00.000Z'
const AUTHOR_ID = '00000000-0000-0000-0000-000000000601'
const REVIEWER_ID = '00000000-0000-0000-0000-000000000602'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000603'

function version(
  overrides: Partial<ContentPublicationSummary['versions'][number]> = {},
): ContentPublicationSummary['versions'][number] {
  return {
    versionId: '00000000-0000-0000-0000-000000000604',
    version: 1,
    locale: 'pt-BR',
    category: 'nutrition',
    title: 'Alimentacao consciente',
    state: 'draft',
    featuredToday: false,
    authorId: AUTHOR_ID,
    reviewerId: null,
    publishAt: null,
    updatedAt: NOW,
    ...overrides,
  }
}

function detailVersion(
  overrides: Partial<ContentPublicationDetail['versions'][number]> = {},
): ContentPublicationDetail['versions'][number] {
  return {
    ...version(),
    excerpt: 'Uma introducao suficientemente longa para este conteudo.',
    bodyMarkdown:
      '## Comece com calma\n\nObserve seus sinais de fome e saciedade antes de montar cada refeicao do dia.',
    bodyHash: 'a'.repeat(64),
    readingTimeMinutes: 1,
    tags: ['alimentacao-consciente'],
    cover: null,
    targeting: { protocols: [], plans: [], personalities: [] },
    author: { id: AUTHOR_ID, name: 'Editora', role: 'content_editor' },
    reviewer: null,
    publisher: null,
    submittedAt: null,
    reviewedAt: null,
    rejectionReason: null,
    publishedAt: null,
    ...overrides,
  }
}

describe('content presenter', () => {
  it('derives archived, published, scheduled, and workflow statuses', () => {
    expect(effectiveVersionStatus(version(), NOW)).toBe('draft')
    expect(
      effectiveVersionStatus(
        version({ state: 'approved', publishAt: '2026-07-21T11:00:00.000Z' }),
        NOW,
      ),
    ).toBe('published')
    expect(
      effectiveVersionStatus(
        version({ state: 'approved', publishAt: '2026-07-22T12:00:00.000Z' }),
        NOW,
      ),
    ).toBe('scheduled')
    expect(effectiveVersionStatus(version({ state: 'approved' }), NOW, NOW)).toBe('archived')
  })

  it('reports publication locale completeness without treating duplicate versions as locales', () => {
    expect(localeCompleteness([version(), version({ version: 2 })])).toEqual({
      available: ['pt-BR'],
      missing: ['en-US'],
      complete: false,
    })
    expect(localeCompleteness([version(), version({ locale: 'en-US' })])).toEqual({
      available: ['pt-BR', 'en-US'],
      missing: [],
      complete: true,
    })
  })

  it('exposes commands only to their exact operational role', () => {
    expect(visibleContentCommands('content_editor')).toEqual([
      'create',
      'create_draft',
      'save_draft',
      'submit',
      'cover',
    ])
    expect(visibleContentCommands('nutrition_admin')).toEqual(['approve', 'reject'])
    expect(visibleContentCommands('master_admin')).toEqual(['publish', 'schedule', 'archive'])
    expect(visibleContentCommands('support')).toEqual([])
    expect(visibleContentCommands('operations_admin')).toEqual([])
  })

  it('labels unscheduled, scheduled, and published timing in Portuguese', () => {
    expect(scheduleLabel(version(), NOW)).toEqual({ kind: 'none', label: 'Sem agendamento' })
    expect(
      scheduleLabel(version({ state: 'approved', publishAt: '2026-07-22T12:00:00.000Z' }), NOW),
    ).toEqual({ kind: 'scheduled', label: 'Agendado para 22/07/2026, 12:00 UTC' })
    expect(
      scheduleLabel(version({ state: 'approved', publishAt: '2026-07-21T11:00:00.000Z' }), NOW),
    ).toEqual({ kind: 'published', label: 'Publicado em 21/07/2026, 11:00 UTC' })
  })

  it('parses datetime-local components as UTC and rejects invalid or rolled dates', () => {
    const parsed = parseUtcDateTimeLocal('2026-07-21T09:30')

    expect(parsed).toBe('2026-07-21T09:30:00.000Z')
    expect(parsed).not.toBe(new Date('2026-07-21T09:30:00-03:00').toISOString())
    expect(parseUtcDateTimeLocal('2026-02-29T09:30')).toBeNull()
    expect(parseUtcDateTimeLocal('2026-04-31T09:30')).toBeNull()
    expect(parseUtcDateTimeLocal('2026-07-21T24:00')).toBeNull()
    expect(parseUtcDateTimeLocal('not-a-date')).toBeNull()
  })

  it('formats every operational timestamp with an explicit UTC suffix', () => {
    expect(formatOperationalDate('2026-07-21T09:30:00.000Z')).toBe('21/07/2026, 09:30 UTC')
  })

  it('selects only effective approved publication context and separates future schedules', () => {
    const published = detailVersion({
      versionId: '00000000-0000-0000-0000-000000000605',
      version: 2,
      state: 'approved',
      publishAt: '2026-07-20T12:00:00.000Z',
      publishedAt: '2026-07-20T12:00:01.000Z',
    })
    const latestDraft = detailVersion({
      versionId: '00000000-0000-0000-0000-000000000606',
      version: 3,
      updatedAt: '2026-07-21T13:00:00.000Z',
    })
    const futureScheduled = detailVersion({
      versionId: '00000000-0000-0000-0000-000000000608',
      version: 4,
      state: 'approved',
      publishAt: '2026-07-22T12:00:00.000Z',
      publishedAt: '2026-07-21T12:30:00.000Z',
      updatedAt: '2026-07-21T12:30:00.000Z',
    })
    const rejectedWithPublicationCommand = detailVersion({
      versionId: '00000000-0000-0000-0000-000000000609',
      version: 1,
      state: 'rejected',
      publishAt: '2026-07-20T12:00:00.000Z',
      publishedAt: '2026-07-20T11:59:00.000Z',
    })
    const english = detailVersion({
      versionId: '00000000-0000-0000-0000-000000000607',
      locale: 'en-US',
      version: 1,
    })

    expect(
      selectLocaleVersions(
        [english, rejectedWithPublicationCommand, published, futureScheduled, latestDraft],
        'pt-BR',
        NOW,
      ),
    ).toEqual({
      latest: futureScheduled,
      previousPublished: published,
      futureScheduled,
    })
    expect(selectLocaleVersions([latestDraft], 'en-US', NOW)).toEqual({
      latest: null,
      previousPublished: null,
      futureScheduled: null,
    })
  })

  it('filters slug and locale titles across the complete server-filtered collection', () => {
    const summaries = [
      publicationSummary('00000000-0000-0000-0000-000000000611', 'rotina-matinal', 'Sono'),
      publicationSummary(
        '00000000-0000-0000-0000-000000000612',
        'alimentacao-consciente',
        'Nutrition basics',
      ),
      publicationSummary('00000000-0000-0000-0000-000000000613', 'hidratacao', 'Agua'),
    ]

    expect(filterPublicationSummaries(summaries, 'NUTRITION')).toEqual([summaries[1]])
    expect(filterPublicationSummaries(summaries, 'rotina-mat')).toEqual([summaries[0]])
  })

  it('paginates a stable filtered collection and safely parses requested pages', () => {
    const summaries = Array.from({ length: 5 }, (_, index) =>
      publicationSummary(
        `00000000-0000-0000-0000-${String(700 + index).padStart(12, '0')}`,
        `publicacao-${index + 1}`,
        `Publicacao ${index + 1}`,
        index < 2 ? '2026-07-21T13:00:00.000Z' : `2026-07-21T12:0${4 - index}:00.000Z`,
      ),
    )

    expect(paginatePublications(summaries, 2, 2)).toEqual({
      rows: [summaries[2], summaries[3]],
      page: 2,
      hasPrevious: true,
      hasNext: true,
      total: 5,
    })
    expect(parsePublicationPage('2')).toBe(2)
    expect(parsePublicationPage(['3', '8'])).toBe(3)
    expect(parsePublicationPage('-1')).toBe(1)
    expect(parsePublicationPage('1.5')).toBe(1)
    expect(parsePublicationPage('999999')).toBe(401)
    expect(parsePublicationPage(undefined)).toBe(1)
  })

  it('projects list rows without body Markdown or signed and storage data', () => {
    const unsafeSummary = {
      publicationId: PUBLICATION_ID,
      slug: 'alimentacao-consciente',
      archivedAt: null,
      createdAt: NOW,
      updatedAt: NOW,
      versions: [
        {
          ...version({ reviewerId: REVIEWER_ID }),
          bodyMarkdown: 'segredo editorial',
          signedUrl: 'https://storage.example.test/upload?token=secret',
          objectPath: 'content/private.jpg',
          bucketId: 'content-covers',
          cover: { objectPath: 'content/private.jpg' },
        },
      ],
    } as unknown as ContentPublicationSummary

    const row = toPublicationListRow(unsafeSummary, NOW)
    const serialized = JSON.stringify(row)

    expect(row).toMatchObject({
      publicationId: PUBLICATION_ID,
      slug: 'alimentacao-consciente',
      effectiveStatus: 'draft',
      locales: ['pt-BR'],
    })
    expect(serialized).not.toMatch(
      /bodyMarkdown|segredo editorial|signedUrl|token|objectPath|bucketId|content-covers/,
    )
  })
})

function publicationSummary(
  publicationId: string,
  slug: string,
  title: string,
  updatedAt = NOW,
): ContentPublicationSummary {
  return {
    publicationId,
    slug,
    archivedAt: null,
    createdAt: NOW,
    updatedAt,
    versions: [version({ title, updatedAt })],
  }
}
