import { describe, expect, it, vi } from 'vitest'
import { filterAdminListPublications, textAdminListScanFilters } from './admin-list-filter'
import { ContentAdminError, type ContentAdminFilters, ContentStorageError } from './admin-service'
import {
  type ContentSupabaseClient,
  createSupabaseContentAdminDependencies,
} from './supabase-repository'

const ACTOR_ID = '00000000-0000-0000-0000-000000000601'
const REVIEWER_ID = '00000000-0000-0000-0000-000000000602'
const PUBLISHER_ID = '00000000-0000-0000-0000-000000000603'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000604'
const VERSION_ID = '00000000-0000-0000-0000-000000000605'
const SOURCE_VERSION_ID = '00000000-0000-0000-0000-000000000606'
const ENGLISH_VERSION_ID = '00000000-0000-0000-0000-000000000608'
const ASSET_ID = '00000000-0000-0000-0000-000000000607'
const UPDATED_AT = '2026-07-21T12:00:00.000Z'
const OBJECT_PATH = `content/${ASSET_ID}.jpg`

interface QueryLog {
  table: string
  method: string
  args: unknown[]
}

interface FakeClient extends ContentSupabaseClient {
  rpc: ReturnType<typeof vi.fn>
  from: ReturnType<typeof vi.fn>
  storage: {
    from: ReturnType<typeof vi.fn>
  }
  queryLog: QueryLog[]
  storageBucket: {
    createSignedUploadUrl: ReturnType<typeof vi.fn>
    info: ReturnType<typeof vi.fn>
    remove: ReturnType<typeof vi.fn>
  }
}

function fakeClient(options?: {
  rpcResults?: Array<{ data: unknown; error: unknown }>
  tableResults?: Record<string, Array<{ data: unknown; error: unknown }>>
}): FakeClient {
  const rpcResults = [...(options?.rpcResults ?? [])]
  const tableResults = new Map(
    Object.entries(options?.tableResults ?? {}).map(([table, values]) => [table, [...values]]),
  )
  const queryLog: QueryLog[] = []
  const from = vi.fn((table: string) => {
    const response = tableResults.get(table)?.shift() ?? { data: [], error: null }
    const builder: Record<string, unknown> = {}
    for (const method of [
      'select',
      'eq',
      'in',
      'is',
      'not',
      'gt',
      'lte',
      'order',
      'limit',
      'range',
      'maybeSingle',
    ]) {
      builder[method] = (...args: unknown[]) => {
        queryLog.push({ table, method, args })
        return builder
      }
    }
    // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are intentionally thenable.
    builder.then = (
      resolve: (value: { data: unknown; error: unknown }) => unknown,
      reject: (reason: unknown) => unknown,
    ) => Promise.resolve(response).then(resolve, reject)
    return builder
  })
  const storageBucket = {
    createSignedUploadUrl: vi.fn(async () => ({
      data: {
        signedUrl: `https://storage.example.test/object/upload/sign/content-covers/${OBJECT_PATH}?token=secret`,
        path: OBJECT_PATH,
        token: 'secret',
      },
      error: null,
    })),
    info: vi.fn(async () => ({
      data: { size: 1024, contentType: 'image/jpeg', etag: 'exact-etag' },
      error: null,
    })),
    remove: vi.fn(async () => ({ data: [], error: null })),
  }
  return {
    rpc: vi.fn(async () => rpcResults.shift() ?? { data: null, error: null }),
    from,
    storage: { from: vi.fn(() => storageBucket) },
    queryLog,
    storageBucket,
  } as unknown as FakeClient
}

function publicationRow() {
  return {
    id: PUBLICATION_ID,
    slug: 'alimentacao-consciente',
    archived_at: null,
    created_at: UPDATED_AT,
    updated_at: UPDATED_AT,
  }
}

function versionSummaryRow() {
  return {
    id: VERSION_ID,
    version: 1,
    locale: 'pt-BR',
    category: 'nutrition',
    title: 'Alimentação consciente',
    state: 'draft',
    featured_today: false,
    authored_by: ACTOR_ID,
    reviewed_by: null,
    publish_at: null,
    updated_at: UPDATED_AT,
  }
}

function testUuid(index: number): string {
  return `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`
}

function listRow(
  index: number,
  versions: Array<Record<string, unknown>>,
): ReturnType<typeof publicationRow> & {
  pt_versions: Array<Record<string, unknown>>
  en_versions: Array<Record<string, unknown>>
} {
  return {
    ...publicationRow(),
    id: testUuid(index),
    slug: `publication-${index}`,
    pt_versions: versions.filter((version) => version.locale !== 'en-US'),
    en_versions: versions.filter((version) => version.locale === 'en-US'),
  }
}

function summaryVersion(
  index: number,
  overrides: Record<string, unknown> = {},
): ReturnType<typeof versionSummaryRow> {
  return {
    ...versionSummaryRow(),
    id: testUuid(20_000 + index),
    ...overrides,
  }
}

function versionDetailRow() {
  return {
    ...versionSummaryRow(),
    excerpt: 'Uma introdução suficientemente longa para o conteúdo.',
    body_markdown:
      '## Comece com calma\n\nObserve seus sinais de fome e saciedade antes de montar cada refeição do dia com atenção.',
    body_hash: 'a'.repeat(64),
    reading_time_minutes: 1,
    tags: ['alimentacao-consciente'],
    cover_asset_id: ASSET_ID,
    submitted_at: UPDATED_AT,
    reviewed_at: null,
    rejection_reason: null,
    published_by: null,
    published_at: null,
  }
}

function versionValidationSnapshotRow(overrides: Record<string, unknown> = {}) {
  return {
    id: VERSION_ID,
    publication_id: PUBLICATION_ID,
    locale: 'pt-BR',
    state: 'draft',
    body_markdown:
      '## Comece com calma\n\nObserve seus sinais de fome e saciedade antes de montar cada refeição do dia com atenção.',
    updated_at: UPDATED_AT,
    publish_at: null,
    ...overrides,
  }
}

function validDraft() {
  return {
    locale: 'pt-BR' as const,
    category: 'nutrition' as const,
    title: 'Alimentação consciente',
    excerpt: 'Uma introdução suficientemente longa para o conteúdo.',
    bodyMarkdown:
      '## Comece com calma\n\nObserve seus sinais de fome e saciedade antes de montar cada refeição do dia com atenção.',
    tags: ['alimentacao-consciente'],
    featuredToday: false,
    coverAssetId: ASSET_ID,
    targeting: {
      protocols: ['recomposicao' as const],
      plans: ['mensal' as const],
      personalities: ['focus' as const],
    },
  }
}

describe('Supabase content admin repository', () => {
  it.each([
    ['status', { status: 'rejected' }, { state: 'rejected' }, { state: 'draft' }],
    ['category', { category: 'training' }, { category: 'training' }, { category: 'nutrition' }],
    ['author', { authorId: REVIEWER_ID }, { authored_by: REVIEWER_ID }, { authored_by: ACTOR_ID }],
    ['reviewer', { reviewerId: REVIEWER_ID }, { reviewed_by: REVIEWER_ID }, { reviewed_by: null }],
    [
      'schedule',
      { schedule: 'published' },
      { state: 'approved', publish_at: '2026-07-20T12:00:00.000Z' },
      { state: 'approved', publish_at: '2099-07-22T12:00:00.000Z' },
    ],
    ['featured', { featuredToday: true }, { featured_today: true }, { featured_today: false }],
  ] as Array<
    [string, Partial<ContentAdminFilters>, Record<string, unknown>, Record<string, unknown>]
  >)('does not match a historical %s value when the latest locale version diverges', async (_name, filter, historical, latest) => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [
              listRow(1, [
                summaryVersion(1, { version: 1, ...historical }),
                summaryVersion(2, { version: 2, ...latest }),
              ]),
            ],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await expect(repository.list({ ...filter, limit: 25, offset: 0 })).resolves.toEqual([])
  })

  it('requires every combined filter to match the same latest locale candidate', async () => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [
              listRow(1, [
                summaryVersion(1, {
                  version: 2,
                  locale: 'pt-BR',
                  category: 'nutrition',
                  authored_by: ACTOR_ID,
                }),
                summaryVersion(2, {
                  version: 3,
                  locale: 'en-US',
                  category: 'training',
                  authored_by: REVIEWER_ID,
                }),
              ]),
            ],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await expect(
      repository.list({
        category: 'nutrition',
        authorId: REVIEWER_ID,
        limit: 25,
        offset: 0,
      }),
    ).resolves.toEqual([])
  })

  it.each([
    ['approved', { status: 'approved' }, [1]],
    ['scheduled status', { status: 'scheduled' }, [2]],
    ['published status', { status: 'published' }, [3]],
    ['scheduled schedule', { schedule: 'scheduled' }, [2]],
    ['published schedule', { schedule: 'published' }, [3]],
  ] as Array<
    [string, Partial<ContentAdminFilters>, number[]]
  >)('evaluates %s from the approved latest version and one captured now', async (_name, filter, expectedIndexes) => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-21T12:00:00.000Z'))
    const rows = [
      listRow(1, [summaryVersion(1, { state: 'approved', publish_at: null })]),
      listRow(2, [
        summaryVersion(2, {
          state: 'approved',
          publish_at: '2026-07-21T12:00:00.001Z',
        }),
      ]),
      listRow(3, [
        summaryVersion(3, {
          state: 'approved',
          publish_at: '2026-07-21T12:00:00.000Z',
        }),
      ]),
      listRow(4, [
        summaryVersion(4, {
          state: 'draft',
          publish_at: '2026-07-21T12:00:00.001Z',
        }),
      ]),
    ]
    const client = fakeClient({
      tableResults: { content_publications: [{ data: rows, error: null }] },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    try {
      const result = await repository.list({ ...filter, limit: 25, offset: 0 })
      expect(result.map((publication) => publication.publicationId)).toEqual(
        expectedIndexes.map(testUuid),
      )
    } finally {
      vi.useRealTimers()
    }
  })

  it('returns the latest bilingual snapshots after filtering against one locale', async () => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [
              {
                ...publicationRow(),
                pt_versions: [summaryVersion(2, { version: 2, state: 'draft' })],
                en_versions: [
                  {
                    ...versionSummaryRow(),
                    id: ENGLISH_VERSION_ID,
                    locale: 'en-US',
                    title: 'Mindful eating',
                  },
                ],
              },
            ],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    const result = await repository.list({
      status: 'draft',
      locale: 'pt-BR',
      limit: 25,
      offset: 0,
    })

    expect(result).toHaveLength(1)
    expect(result[0]?.matchedVersionId).toBe(testUuid(20_002))
    expect(result[0]?.versions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ version: 2, locale: 'pt-BR', state: 'draft' }),
        expect.objectContaining({ versionId: ENGLISH_VERSION_ID, locale: 'en-US' }),
      ]),
    )
    const selection = client.queryLog.find(
      (entry) => entry.table === 'content_publications' && entry.method === 'select',
    )?.args[0]
    expect(selection).toContain('pt_versions:content_versions (')
    expect(selection).toContain('en_versions:content_versions (')
    expect(selection).not.toContain('content_versions!inner')
    expect(selection).not.toMatch(/body_markdown|object_path|bucket_id|etag|signed_url|token/)
  })

  it('identifies the exact locale candidate that satisfies combined filters', async () => {
    const englishVersionId = testUuid(20_002)
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [
              listRow(1, [
                summaryVersion(1, {
                  version: 5,
                  locale: 'pt-BR',
                  category: 'nutrition',
                  authored_by: ACTOR_ID,
                }),
                summaryVersion(2, {
                  id: englishVersionId,
                  locale: 'en-US',
                  category: 'training',
                  authored_by: REVIEWER_ID,
                }),
              ]),
            ],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    const result = await repository.list({
      category: 'training',
      authorId: REVIEWER_ID,
      limit: 25,
      offset: 0,
    })

    expect(result[0]).toMatchObject({
      matchedVersionId: englishVersionId,
      versions: expect.arrayContaining([
        expect.objectContaining({ locale: 'pt-BR' }),
        expect.objectContaining({ versionId: englishVersionId, locale: 'en-US' }),
      ]),
    })
  })

  it('chooses pt-BR deterministically when both latest locale candidates match', async () => {
    const portugueseVersionId = testUuid(20_001)
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [
              listRow(1, [
                summaryVersion(2, { locale: 'en-US', version: 9 }),
                summaryVersion(1, { id: portugueseVersionId, locale: 'pt-BR', version: 2 }),
              ]),
            ],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    const result = await repository.list({ featuredToday: false, limit: 25, offset: 0 })

    expect(result[0]?.matchedVersionId).toBe(portugueseVersionId)
  })

  it('applies offset and limit after latest-version filtering across stable raw batches', async () => {
    const firstBatch = Array.from({ length: 100 }, (_, index) =>
      listRow(index + 1, [summaryVersion(index + 1, { featured_today: index === 99 })]),
    )
    const secondBatch = Array.from({ length: 100 }, (_, index) =>
      listRow(index + 101, [
        summaryVersion(index + 101, { featured_today: index === 0 || index === 50 }),
      ]),
    )
    const client = fakeClient({
      tableResults: {
        content_publications: [
          { data: firstBatch, error: null },
          { data: secondBatch, error: null },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    const result = await repository.list({ featuredToday: true, limit: 2, offset: 1 })

    expect(result.map((publication) => publication.publicationId)).toEqual([
      testUuid(101),
      testUuid(151),
    ])
    expect(
      client.queryLog
        .filter((entry) => entry.table === 'content_publications' && entry.method === 'range')
        .map((entry) => entry.args),
    ).toEqual([
      [0, 99],
      [100, 199],
    ])
  })

  it('reports truncation instead of silently exhausting sparse structured matches at the raw ceiling', async () => {
    const rawBatches = Array.from({ length: 101 }, (_, batchIndex) => ({
      data: Array.from({ length: 100 }, (_, rowIndex) =>
        listRow(batchIndex * 100 + rowIndex + 1, [
          summaryVersion(batchIndex * 100 + rowIndex + 1, { featured_today: false }),
        ]),
      ),
      error: null,
    }))
    const client = fakeClient({ tableResults: { content_publications: rawBatches } })
    const { repository } = createSupabaseContentAdminDependencies(client)
    const listWithMetadata = repository as typeof repository & {
      listWithMetadata(filters: ContentAdminFilters): Promise<{
        publications: unknown[]
        exhausted: boolean
        truncated: boolean
      }>
    }

    await expect(
      listWithMetadata.listWithMetadata({ featuredToday: true, limit: 26, offset: 0 }),
    ).resolves.toEqual({ publications: [], exhausted: false, truncated: true })
  })

  it('reads each raw text batch once before applying version filters in memory', async () => {
    const firstBatch = Array.from({ length: 100 }, (_, index) =>
      listRow(index + 1, [
        summaryVersion(index + 1, { category: index === 99 ? 'training' : 'nutrition' }),
      ]),
    )
    const secondBatch = Array.from({ length: 100 }, (_, index) =>
      listRow(index + 101, [
        summaryVersion(index + 101, { category: index === 0 ? 'training' : 'nutrition' }),
      ]),
    )
    const client = fakeClient({
      tableResults: {
        content_publications: [
          { data: firstBatch, error: null },
          { data: secondBatch, error: null },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)
    const versionFilters = { category: 'training' as const }

    const loaded = [
      ...(await repository.list(textAdminListScanFilters(versionFilters, 0, 100))),
      ...(await repository.list(textAdminListScanFilters(versionFilters, 100, 100))),
    ]
    const filtered = filterAdminListPublications(
      loaded,
      versionFilters,
      Date.parse('2026-07-21T12:00:00.000Z'),
    )

    expect(filtered.map((publication) => publication.publicationId)).toEqual([
      testUuid(100),
      testUuid(101),
    ])
    expect(
      client.queryLog
        .filter((entry) => entry.table === 'content_publications' && entry.method === 'range')
        .map((entry) => entry.args),
    ).toEqual([
      [0, 99],
      [100, 199],
    ])
  })

  it('keeps publications without versions when no version filter is active', async () => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [{ ...publicationRow(), pt_versions: [], en_versions: [] }],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await expect(repository.list({ limit: 10, offset: 0 })).resolves.toHaveLength(1)

    const selection = client.queryLog.find(
      (entry) => entry.table === 'content_publications' && entry.method === 'select',
    )?.args[0]
    expect(selection).toContain('pt_versions:content_versions (')
    expect(selection).toContain('en_versions:content_versions (')
    expect(selection).not.toContain('content_versions!inner')
    expect(
      client.queryLog
        .filter((entry) => entry.table === 'content_publications')
        .map(({ method, args }) => ({ method, args })),
    ).toEqual([
      { method: 'select', args: [expect.any(String)] },
      { method: 'order', args: ['updated_at', { ascending: false }] },
      { method: 'order', args: ['id', { ascending: true }] },
      { method: 'range', args: [0, 9] },
      { method: 'eq', args: ['pt_versions.locale', 'pt-BR'] },
      {
        method: 'order',
        args: ['version', { ascending: false, referencedTable: 'pt_versions' }],
      },
      { method: 'limit', args: [1, { referencedTable: 'pt_versions' }] },
      { method: 'eq', args: ['en_versions.locale', 'en-US'] },
      {
        method: 'order',
        args: ['version', { ascending: false, referencedTable: 'en_versions' }],
      },
      { method: 'limit', args: [1, { referencedTable: 'en_versions' }] },
      { method: 'is', args: ['archived_at', null] },
    ])
  })

  it('bounds list history to one embedded version per locale', async () => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [{ ...publicationRow(), pt_versions: [], en_versions: [] }],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await repository.list({ limit: 10, offset: 0 })

    expect(
      client.queryLog
        .filter(
          (entry) =>
            entry.table === 'content_publications' &&
            ['eq', 'order', 'limit'].includes(entry.method),
        )
        .map(({ method, args }) => ({ method, args })),
    ).toEqual(
      expect.arrayContaining([
        { method: 'eq', args: ['pt_versions.locale', 'pt-BR'] },
        {
          method: 'order',
          args: ['version', { ascending: false, referencedTable: 'pt_versions' }],
        },
        { method: 'limit', args: [1, { referencedTable: 'pt_versions' }] },
        { method: 'eq', args: ['en_versions.locale', 'en-US'] },
        {
          method: 'order',
          args: ['version', { ascending: false, referencedTable: 'en_versions' }],
        },
        { method: 'limit', args: [1, { referencedTable: 'en_versions' }] },
      ]),
    )
  })

  it('strictly parses list rows instead of forwarding malformed unknown data', async () => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [
              {
                ...publicationRow(),
                pt_versions: [{ ...versionSummaryRow(), version: 'one' }],
                en_versions: [],
              },
            ],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await expect(repository.list({ limit: 10, offset: 0 })).rejects.toMatchObject({
      code: 'database_unavailable',
      operation: 'list',
    })
  })

  it('reads exactly the seven-field version validation snapshot without detail side queries', async () => {
    const client = fakeClient({
      tableResults: {
        content_versions: [{ data: versionValidationSnapshotRow(), error: null }],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await expect(repository.getVersionValidationSnapshot(VERSION_ID)).resolves.toEqual({
      versionId: VERSION_ID,
      publicationId: PUBLICATION_ID,
      locale: 'pt-BR',
      state: 'draft',
      bodyMarkdown:
        '## Comece com calma\n\nObserve seus sinais de fome e saciedade antes de montar cada refeição do dia com atenção.',
      updatedAt: UPDATED_AT,
      publishAt: null,
    })

    expect(client.queryLog).toEqual([
      {
        table: 'content_versions',
        method: 'select',
        args: ['id, publication_id, locale, state, body_markdown, updated_at, publish_at'],
      },
      { table: 'content_versions', method: 'eq', args: ['id', VERSION_ID] },
      { table: 'content_versions', method: 'maybeSingle', args: [] },
    ])
    expect(client.from).toHaveBeenCalledTimes(1)
    expect(client.from).toHaveBeenCalledWith('content_versions')
  })

  it('adds only the exact updated_at predicate when a snapshot precondition is supplied', async () => {
    const client = fakeClient({
      tableResults: {
        content_versions: [{ data: versionValidationSnapshotRow(), error: null }],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await repository.getVersionValidationSnapshot(VERSION_ID, UPDATED_AT)

    expect(client.queryLog).toEqual([
      {
        table: 'content_versions',
        method: 'select',
        args: ['id, publication_id, locale, state, body_markdown, updated_at, publish_at'],
      },
      { table: 'content_versions', method: 'eq', args: ['id', VERSION_ID] },
      { table: 'content_versions', method: 'eq', args: ['updated_at', UPDATED_AT] },
      { table: 'content_versions', method: 'maybeSingle', args: [] },
    ])
  })

  it('returns null for a missing validation snapshot and maps malformed/provider failures opaquely', async () => {
    const missing = fakeClient({
      tableResults: { content_versions: [{ data: null, error: null }] },
    })
    await expect(
      createSupabaseContentAdminDependencies(missing).repository.getVersionValidationSnapshot(
        VERSION_ID,
      ),
    ).resolves.toBeNull()

    const malformed = fakeClient({
      tableResults: {
        content_versions: [
          {
            data: versionValidationSnapshotRow({ provider_secret: 'must-not-leak' }),
            error: null,
          },
        ],
      },
    })
    const malformedFailure = await createSupabaseContentAdminDependencies(
      malformed,
    ).repository
      .getVersionValidationSnapshot(VERSION_ID)
      .catch((error: unknown) => error)
    expect(malformedFailure).toMatchObject({
      code: 'database_unavailable',
      operation: 'getVersionValidationSnapshot',
    })
    expect(String(malformedFailure)).not.toContain('must-not-leak')

    const provider = fakeClient({
      tableResults: {
        content_versions: [
          {
            data: null,
            error: { code: 'XX000', message: 'secret provider failure' },
          },
        ],
      },
    })
    const providerFailure = await createSupabaseContentAdminDependencies(provider).repository
      .getVersionValidationSnapshot(VERSION_ID)
      .catch((error: unknown) => error)
    expect(providerFailure).toMatchObject({
      code: 'database_unavailable',
      operation: 'getVersionValidationSnapshot',
    })
    expect(String(providerFailure)).not.toContain('secret provider failure')
  })

  it('composes detail, target, identity, and safe cover rows without leaking internals', async () => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: { ...publicationRow(), created_by: ACTOR_ID, archived_by: null },
            error: null,
          },
        ],
        content_versions: [{ data: [versionDetailRow()], error: null }],
        content_version_target_protocols: [
          { data: [{ content_version_id: VERSION_ID, protocol: 'recomposicao' }], error: null },
        ],
        content_version_target_plans: [
          { data: [{ content_version_id: VERSION_ID, plan: 'mensal' }], error: null },
        ],
        content_version_target_personalities: [
          { data: [{ content_version_id: VERSION_ID, personality_code: 'focus' }], error: null },
        ],
        content_assets: [
          {
            data: [
              {
                id: ASSET_ID,
                mime_type: 'image/jpeg',
                declared_size_bytes: 1024,
                actual_size_bytes: 1024,
                status: 'uploaded',
              },
            ],
            error: null,
          },
        ],
        admin_users: [
          {
            data: [
              { id: ACTOR_ID, name: 'Editora', role: 'content_editor' },
              { id: REVIEWER_ID, name: 'Revisora', role: 'nutrition_admin' },
              { id: PUBLISHER_ID, name: 'Publicadora', role: 'master_admin' },
            ],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    const result = await repository.get(PUBLICATION_ID)

    expect(result).toMatchObject({
      publicationId: PUBLICATION_ID,
      createdBy: { id: ACTOR_ID, name: 'Editora', role: 'content_editor' },
      versions: [
        {
          versionId: VERSION_ID,
          targeting: {
            protocols: ['recomposicao'],
            plans: ['mensal'],
            personalities: ['focus'],
          },
          cover: {
            assetId: ASSET_ID,
            mimeType: 'image/jpeg',
            sizeBytes: 1024,
            status: 'uploaded',
          },
          author: { id: ACTOR_ID, name: 'Editora', role: 'content_editor' },
        },
      ],
    })
    const serialized = JSON.stringify(result)
    expect(serialized).not.toMatch(/objectPath|object_path|bucket|etag|token|signedUrl/)
    const assetSelection = client.queryLog.find(
      (entry) => entry.table === 'content_assets' && entry.method === 'select',
    )?.args[0]
    expect(assetSelection).not.toMatch(/object_path|bucket_id|etag/)
  })

  it('caps detailed immutable history and reports retained older versions', async () => {
    const versions = Array.from({ length: 51 }, (_, index) => ({
      ...versionDetailRow(),
      id: testUuid(40_000 + index),
      version: 51 - index,
      cover_asset_id: null,
    }))
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: { ...publicationRow(), created_by: ACTOR_ID, archived_by: null },
            error: null,
          },
        ],
        content_versions: [{ data: versions, error: null }],
        content_version_target_protocols: [{ data: [], error: null }],
        content_version_target_plans: [{ data: [], error: null }],
        content_version_target_personalities: [{ data: [], error: null }],
        admin_users: [
          {
            data: [{ id: ACTOR_ID, name: 'Editora', role: 'content_editor' }],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    const result = await repository.get(PUBLICATION_ID)

    expect(result).toMatchObject({ historyTruncated: true })
    expect(result?.versions).toHaveLength(50)
    expect(
      client.queryLog.find(
        (entry) => entry.table === 'content_versions' && entry.method === 'limit',
      )?.args,
    ).toEqual([51])
    for (const entry of client.queryLog.filter(
      (candidate) => candidate.method === 'in' && candidate.args[0] === 'content_version_id',
    )) {
      expect(entry.args[1]).toHaveLength(50)
    }
  })

  it('reserves the latest version of each locale inside the bounded detail history', async () => {
    const portugueseVersions = Array.from({ length: 51 }, (_, index) => ({
      ...versionDetailRow(),
      id: testUuid(41_000 + index),
      version: 100 - index,
      state: 'approved',
      cover_asset_id: null,
    }))
    const englishDraft = {
      ...versionDetailRow(),
      id: ENGLISH_VERSION_ID,
      version: 1,
      locale: 'en-US',
      state: 'draft',
      cover_asset_id: null,
    }
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: { ...publicationRow(), created_by: ACTOR_ID, archived_by: null },
            error: null,
          },
        ],
        content_versions: [
          { data: portugueseVersions, error: null },
          { data: [portugueseVersions[0]], error: null },
          { data: [englishDraft], error: null },
        ],
        content_version_target_protocols: [{ data: [], error: null }],
        content_version_target_plans: [{ data: [], error: null }],
        content_version_target_personalities: [{ data: [], error: null }],
        admin_users: [
          {
            data: [{ id: ACTOR_ID, name: 'Editora', role: 'content_editor' }],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    const result = await repository.get(PUBLICATION_ID)

    expect(result).toMatchObject({ historyTruncated: true })
    expect(result?.versions).toHaveLength(50)
    expect(result?.versions.map((version) => version.versionId)).toContain(ENGLISH_VERSION_ID)
    expect(result?.versions.map((version) => version.versionId)).toContain(
      portugueseVersions[0]?.id,
    )
  })

  it('returns null detail and rejects malformed detail payloads', async () => {
    const missing = fakeClient({
      tableResults: { content_publications: [{ data: null, error: null }] },
    })
    await expect(
      createSupabaseContentAdminDependencies(missing).repository.get(PUBLICATION_ID),
    ).resolves.toBeNull()

    const malformed = fakeClient({
      tableResults: {
        content_publications: [
          { data: { ...publicationRow(), created_by: 'not-a-uuid' }, error: null },
        ],
      },
    })
    await expect(
      createSupabaseContentAdminDependencies(malformed).repository.get(PUBLICATION_ID),
    ).rejects.toMatchObject({ code: 'database_unavailable', operation: 'get' })
  })

  it('uses all ten Task 2 RPC names, exact snake_case params, and strict result mapping', async () => {
    const rpcResults = [
      {
        data: {
          publication_id: PUBLICATION_ID,
          slug: 'alimentacao-consciente',
          created_at: UPDATED_AT,
        },
        error: null,
      },
      {
        data: {
          publication_id: PUBLICATION_ID,
          version_id: VERSION_ID,
          version: 1,
          locale: 'pt-BR',
          state: 'draft',
          updated_at: UPDATED_AT,
        },
        error: null,
      },
      {
        data: {
          publication_id: PUBLICATION_ID,
          version_id: VERSION_ID,
          version: 1,
          state: 'draft',
          body_hash: 'a'.repeat(64),
          reading_time_minutes: 1,
          updated_at: UPDATED_AT,
        },
        error: null,
      },
      {
        data: {
          publication_id: PUBLICATION_ID,
          version_id: VERSION_ID,
          version: 1,
          state: 'in_review',
          body_hash: 'a'.repeat(64),
          updated_at: UPDATED_AT,
        },
        error: null,
      },
      {
        data: {
          publication_id: PUBLICATION_ID,
          version_id: VERSION_ID,
          version: 1,
          state: 'approved',
          body_hash: 'a'.repeat(64),
          reviewed_at: UPDATED_AT,
          updated_at: UPDATED_AT,
        },
        error: null,
      },
      {
        data: {
          publication_id: PUBLICATION_ID,
          version_id: VERSION_ID,
          version: 1,
          state: 'approved',
          effective_state: 'scheduled',
          publish_at: '2026-07-22T12:00:00.000Z',
          body_hash: 'a'.repeat(64),
          updated_at: UPDATED_AT,
        },
        error: null,
      },
      {
        data: { outcome: 'archived', publication_id: PUBLICATION_ID, archived_at: UPDATED_AT },
        error: null,
      },
      {
        data: {
          asset_id: ASSET_ID,
          bucket_id: 'content-covers',
          object_path: OBJECT_PATH,
          mime_type: 'image/jpeg',
          declared_size_bytes: 1024,
          status: 'pending_upload',
          created_at: UPDATED_AT,
        },
        error: null,
      },
      {
        data: {
          asset_id: ASSET_ID,
          status: 'uploaded',
          actual_size_bytes: 1024,
          uploaded_at: UPDATED_AT,
          updated_at: UPDATED_AT,
        },
        error: null,
      },
      {
        data: {
          asset_id: ASSET_ID,
          status: 'deleted',
          deleted_at: UPDATED_AT,
          updated_at: UPDATED_AT,
        },
        error: null,
      },
    ]
    const client = fakeClient({ rpcResults })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await repository.createPublication({ actorId: ACTOR_ID, slug: 'alimentacao-consciente' })
    await repository.createDraft({
      actorId: ACTOR_ID,
      publicationId: PUBLICATION_ID,
      locale: 'pt-BR',
      sourceVersionId: SOURCE_VERSION_ID,
    })
    await repository.saveDraft({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      expectedUpdatedAt: UPDATED_AT,
      draft: validDraft(),
    })
    await repository.submit({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      expectedUpdatedAt: UPDATED_AT,
    })
    await repository.review({
      actorId: REVIEWER_ID,
      versionId: VERSION_ID,
      decision: 'approve',
      rejectionReason: null,
    })
    await repository.publish({
      actorId: PUBLISHER_ID,
      versionId: VERSION_ID,
      publishAt: '2026-07-22T12:00:00.000Z',
    })
    await repository.archive({ actorId: PUBLISHER_ID, publicationId: PUBLICATION_ID })
    await repository.createAsset({
      actorId: ACTOR_ID,
      assetId: ASSET_ID,
      mimeType: 'image/jpeg',
      declaredSizeBytes: 1024,
      objectPath: OBJECT_PATH,
    })
    await repository.completeAsset({
      actorId: ACTOR_ID,
      assetId: ASSET_ID,
      actualSizeBytes: 1024,
      etag: 'exact-etag',
    })
    await repository.deleteAsset({
      actorId: ACTOR_ID,
      assetId: ASSET_ID,
      expectedStatus: 'uploaded',
    })

    expect(client.rpc.mock.calls).toEqual([
      ['create_content_publication', { p_actor_id: ACTOR_ID, p_slug: 'alimentacao-consciente' }],
      [
        'create_content_draft',
        {
          p_actor_id: ACTOR_ID,
          p_publication_id: PUBLICATION_ID,
          p_locale: 'pt-BR',
          p_source_version_id: SOURCE_VERSION_ID,
        },
      ],
      [
        'save_content_draft',
        {
          p_actor_id: ACTOR_ID,
          p_version_id: VERSION_ID,
          p_expected_updated_at: UPDATED_AT,
          p_draft: validDraft(),
        },
      ],
      [
        'submit_content_version',
        { p_actor_id: ACTOR_ID, p_version_id: VERSION_ID, p_expected_updated_at: UPDATED_AT },
      ],
      [
        'review_content_version',
        {
          p_actor_id: REVIEWER_ID,
          p_version_id: VERSION_ID,
          p_decision: 'approve',
          p_rejection_reason: null,
        },
      ],
      [
        'publish_content_version',
        {
          p_actor_id: PUBLISHER_ID,
          p_version_id: VERSION_ID,
          p_publish_at: '2026-07-22T12:00:00.000Z',
        },
      ],
      [
        'archive_content_publication',
        { p_actor_id: PUBLISHER_ID, p_publication_id: PUBLICATION_ID },
      ],
      [
        'create_content_asset',
        {
          p_actor_id: ACTOR_ID,
          p_asset_id: ASSET_ID,
          p_mime_type: 'image/jpeg',
          p_declared_size_bytes: 1024,
          p_object_path: OBJECT_PATH,
        },
      ],
      [
        'complete_content_asset',
        {
          p_actor_id: ACTOR_ID,
          p_asset_id: ASSET_ID,
          p_actual_size_bytes: 1024,
          p_etag: 'exact-etag',
        },
      ],
      [
        'delete_content_asset',
        {
          p_actor_id: ACTOR_ID,
          p_asset_id: ASSET_ID,
          p_expected_status: 'uploaded',
        },
      ],
    ])
  })

  it.each([
    ['saveDraft', '40001', 'stale'],
    ['createPublication', '23505', 'duplicate'],
    ['createDraft', '23505', 'duplicate'],
    ['submit', '23503', 'not_found'],
    ['review', '22023', 'validation'],
    ['publish', '42501', 'denied'],
    ['archive', '23514', 'lifecycle'],
    ['completeAsset', '23514', 'cover_mismatch'],
    ['deleteAsset', '23514', 'cover_referenced'],
    ['deleteAsset', '40001', 'stale'],
    ['createAsset', 'XX000', 'database_unavailable'],
  ] as const)('maps %s SQLSTATE %s to %s without DB messages', async (method, sqlstate, code) => {
    const client = fakeClient({
      rpcResults: [
        { data: null, error: { code: sqlstate, message: 'secret SQL/provider detail' } },
      ],
    })
    const { repository } = createSupabaseContentAdminDependencies(client)
    const calls = {
      saveDraft: () =>
        repository.saveDraft({
          actorId: ACTOR_ID,
          versionId: VERSION_ID,
          expectedUpdatedAt: UPDATED_AT,
          draft: validDraft(),
        }),
      createPublication: () =>
        repository.createPublication({ actorId: ACTOR_ID, slug: 'alimentacao-consciente' }),
      createDraft: () =>
        repository.createDraft({
          actorId: ACTOR_ID,
          publicationId: PUBLICATION_ID,
          locale: 'pt-BR',
        }),
      submit: () =>
        repository.submit({
          actorId: ACTOR_ID,
          versionId: VERSION_ID,
          expectedUpdatedAt: UPDATED_AT,
        }),
      review: () =>
        repository.review({
          actorId: REVIEWER_ID,
          versionId: VERSION_ID,
          decision: 'approve',
          rejectionReason: null,
        }),
      publish: () =>
        repository.publish({ actorId: PUBLISHER_ID, versionId: VERSION_ID, publishAt: null }),
      archive: () => repository.archive({ actorId: PUBLISHER_ID, publicationId: PUBLICATION_ID }),
      completeAsset: () =>
        repository.completeAsset({
          actorId: ACTOR_ID,
          assetId: ASSET_ID,
          actualSizeBytes: 1024,
          etag: 'exact-etag',
        }),
      deleteAsset: () =>
        repository.deleteAsset({
          actorId: ACTOR_ID,
          assetId: ASSET_ID,
          expectedStatus: 'pending_upload',
        }),
      createAsset: () =>
        repository.createAsset({
          actorId: ACTOR_ID,
          assetId: ASSET_ID,
          mimeType: 'image/jpeg',
          declaredSizeBytes: 1024,
          objectPath: OBJECT_PATH,
        }),
    }

    const failure = await calls[method]().catch((error: unknown) => error)

    expect(failure).toBeInstanceOf(ContentAdminError)
    expect(failure).toMatchObject({ code, operation: method })
    expect(String(failure)).not.toContain('secret SQL/provider detail')
  })

  it('rejects malformed RPC results instead of returning partial data', async () => {
    const client = fakeClient({
      rpcResults: [
        {
          data: { publication_id: PUBLICATION_ID, slug: 'alimentacao-consciente' },
          error: null,
        },
      ],
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await expect(
      repository.createPublication({ actorId: ACTOR_ID, slug: 'alimentacao-consciente' }),
    ).rejects.toMatchObject({ code: 'database_unavailable', operation: 'createPublication' })
  })

  it('reads internal assets only for server-side cover operations', async () => {
    const client = fakeClient({
      tableResults: {
        content_assets: [
          {
            data: {
              id: ASSET_ID,
              bucket_id: 'content-covers',
              object_path: OBJECT_PATH,
              mime_type: 'image/jpeg',
              declared_size_bytes: 1024,
              actual_size_bytes: null,
              etag: null,
              status: 'pending_upload',
            },
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    await expect(repository.getAssetInternal(ASSET_ID)).resolves.toEqual({
      assetId: ASSET_ID,
      bucketId: 'content-covers',
      objectPath: OBJECT_PATH,
      mimeType: 'image/jpeg',
      declaredSizeBytes: 1024,
      actualSizeBytes: null,
      etag: null,
      status: 'pending_upload',
    })
  })

  it('fixes content-covers, sets upsert false, and strips provider token/path', async () => {
    const client = fakeClient()
    const { storage } = createSupabaseContentAdminDependencies(client)

    const result = await storage.createSignedUpload(OBJECT_PATH)

    expect(client.storage.from).toHaveBeenCalledWith('content-covers')
    expect(client.storageBucket.createSignedUploadUrl).toHaveBeenCalledWith(OBJECT_PATH, {
      upsert: false,
    })
    expect(result).toEqual({ signedUrl: expect.stringContaining('token=secret') })
    expect(Object.keys(result)).toEqual(['signedUrl'])
  })

  it('maps exact Storage info and removes from the fixed bucket', async () => {
    const client = fakeClient()
    const { storage } = createSupabaseContentAdminDependencies(client)

    await expect(storage.getObjectInfo(OBJECT_PATH)).resolves.toEqual({
      size: 1024,
      contentType: 'image/jpeg',
      etag: 'exact-etag',
    })
    await storage.remove(OBJECT_PATH)

    expect(client.storageBucket.info).toHaveBeenCalledWith(OBJECT_PATH)
    expect(client.storageBucket.remove).toHaveBeenCalledWith([OBJECT_PATH])
    expect(client.storage.from).toHaveBeenCalledWith('content-covers')
  })

  it('classifies missing and transient Storage errors without provider leakage or logs', async () => {
    const client = fakeClient()
    client.storageBucket.info.mockResolvedValueOnce({
      data: null,
      error: { statusCode: 404, message: `missing ${OBJECT_PATH}?token=secret` },
    })
    client.storageBucket.createSignedUploadUrl.mockResolvedValueOnce({
      data: null,
      error: { statusCode: 503, message: `provider ${OBJECT_PATH}?token=secret` },
    })
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const { storage } = createSupabaseContentAdminDependencies(client)

    const missing = await storage.getObjectInfo(OBJECT_PATH).catch((error: unknown) => error)
    const transient = await storage.createSignedUpload(OBJECT_PATH).catch((error: unknown) => error)

    expect(missing).toBeInstanceOf(ContentStorageError)
    expect(missing).toMatchObject({ kind: 'missing', operation: 'info' })
    expect(transient).toBeInstanceOf(ContentStorageError)
    expect(transient).toMatchObject({ kind: 'transient', operation: 'create_upload' })
    expect(String(missing) + String(transient)).not.toMatch(/token=secret|content\//)
    expect(consoleError).not.toHaveBeenCalled()
    consoleError.mockRestore()
  })

  it('treats generic Storage 400 info and remove failures as transient', async () => {
    const client = fakeClient()
    client.storageBucket.info.mockResolvedValueOnce({
      data: null,
      error: {
        status: 400,
        statusCode: '400',
        message: `validation failed ${OBJECT_PATH}?token=secret`,
      },
    })
    client.storageBucket.remove.mockResolvedValueOnce({
      data: null,
      error: {
        status: 400,
        statusCode: '400',
        message: `provider rejected ${OBJECT_PATH}?token=secret`,
      },
    })
    const { storage } = createSupabaseContentAdminDependencies(client)

    const infoFailure = await storage.getObjectInfo(OBJECT_PATH).catch((error: unknown) => error)
    const removeFailure = await storage.remove(OBJECT_PATH).catch((error: unknown) => error)

    expect(infoFailure).toBeInstanceOf(ContentStorageError)
    expect(infoFailure).toMatchObject({ kind: 'transient', operation: 'info' })
    expect(removeFailure).toBeInstanceOf(ContentStorageError)
    expect(removeFailure).toMatchObject({ kind: 'transient', operation: 'remove' })
    expect(String(infoFailure) + String(removeFailure)).not.toMatch(/token=secret|content\//)
  })

  it('accepts only Storage 404 as missing during object removal', async () => {
    const client = fakeClient()
    client.storageBucket.remove.mockResolvedValueOnce({
      data: null,
      error: { status: 404, statusCode: 'NoSuchKey', message: 'Object not found' },
    })
    const { storage } = createSupabaseContentAdminDependencies(client)

    await expect(storage.remove(OBJECT_PATH)).resolves.toBeUndefined()
  })
})
