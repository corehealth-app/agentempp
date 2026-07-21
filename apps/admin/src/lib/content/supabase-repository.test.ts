import { describe, expect, it, vi } from 'vitest'
import { ContentAdminError, ContentStorageError } from './admin-service'
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
  it('lists bounded publication summaries without selecting bodies or cover internals', async () => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [{ ...publicationRow(), content_versions: [versionSummaryRow()] }],
            error: null,
          },
        ],
      },
    })
    const { repository } = createSupabaseContentAdminDependencies(client)

    const result = await repository.list({
      status: 'draft',
      locale: 'pt-BR',
      category: 'nutrition',
      authorId: ACTOR_ID,
      reviewerId: REVIEWER_ID,
      schedule: 'unscheduled',
      featuredToday: false,
      limit: 25,
      offset: 5,
    })

    expect(result).toEqual([
      {
        publicationId: PUBLICATION_ID,
        slug: 'alimentacao-consciente',
        archivedAt: null,
        createdAt: UPDATED_AT,
        updatedAt: UPDATED_AT,
        versions: [
          {
            versionId: VERSION_ID,
            version: 1,
            locale: 'pt-BR',
            category: 'nutrition',
            title: 'Alimentação consciente',
            state: 'draft',
            featuredToday: false,
            authorId: ACTOR_ID,
            reviewerId: null,
            publishAt: null,
            updatedAt: UPDATED_AT,
          },
        ],
      },
    ])
    const selection = client.queryLog.find(
      (entry) => entry.table === 'content_publications' && entry.method === 'select',
    )?.args[0]
    expect(selection).toContain('content_versions!inner')
    expect(selection).not.toMatch(/body_markdown|object_path|bucket_id|etag|signed_url|token/)
    expect(
      client.queryLog
        .filter(
          (entry) =>
            entry.table === 'content_publications' &&
            (entry.method === 'order' || entry.method === 'range'),
        )
        .map(({ method, args }) => ({ method, args })),
    ).toEqual([
      { method: 'order', args: ['updated_at', { ascending: false }] },
      { method: 'order', args: ['id', { ascending: true }] },
      { method: 'range', args: [5, 29] },
    ])
  })

  it('keeps publications without versions when no version filter is active', async () => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [{ ...publicationRow(), content_versions: [] }],
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
    expect(selection).toContain('content_versions (')
    expect(selection).not.toContain('content_versions!inner')
  })

  it('strictly parses list rows instead of forwarding malformed unknown data', async () => {
    const client = fakeClient({
      tableResults: {
        content_publications: [
          {
            data: [
              {
                ...publicationRow(),
                content_versions: [{ ...versionSummaryRow(), version: 'one' }],
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
