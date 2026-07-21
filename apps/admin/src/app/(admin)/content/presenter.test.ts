import { describe, expect, it } from 'vitest'
import type {
  ContentPublicationDetail,
  ContentPublicationSummary,
} from '@/lib/content/admin-service'
import {
  effectiveVersionStatus,
  localeCompleteness,
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
    ).toEqual({ kind: 'scheduled', label: 'Agendado para 22/07/2026, 12:00' })
    expect(
      scheduleLabel(version({ state: 'approved', publishAt: '2026-07-21T11:00:00.000Z' }), NOW),
    ).toEqual({ kind: 'published', label: 'Publicado em 21/07/2026, 11:00' })
  })

  it('selects the newest locale version while retaining the prior published version', () => {
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
    const english = detailVersion({
      versionId: '00000000-0000-0000-0000-000000000607',
      locale: 'en-US',
      version: 1,
    })

    expect(selectLocaleVersions([english, published, latestDraft], 'pt-BR')).toEqual({
      latest: latestDraft,
      previousPublished: published,
    })
    expect(selectLocaleVersions([latestDraft], 'en-US')).toEqual({
      latest: null,
      previousPublished: null,
    })
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
