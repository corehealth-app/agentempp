import { describe, expect, it, vi } from 'vitest'
import {
  ContentAdminError,
  type ContentAdminRepository,
  type ContentAdminStorage,
  type ContentPublicationDetail,
  type ContentPublicationSummary,
  type ContentVersionValidationSnapshot,
  ContentStorageError,
  createContentAdminService,
} from './admin-service'

const ACTOR_ID = '00000000-0000-0000-0000-000000000501'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000502'
const VERSION_ID = '00000000-0000-0000-0000-000000000503'
const SOURCE_VERSION_ID = '00000000-0000-0000-0000-000000000504'
const ASSET_ID = '00000000-0000-0000-0000-000000000505'
const UPDATED_AT = '2026-07-21T12:00:00.000Z'
const PIPE_TABLE_MARKDOWN = `## Plano alimentar

| Refeição | Escolha possível |
| --- | --- |
| Café da manhã | Aveia, fruta e iogurte natural |

Ajuste as escolhas com calma para manter uma rotina alimentar possível e sustentável.`
const ORDINARY_PIPE_MARKDOWN =
  'Proteína | contexto ajuda a comparar escolhas alimentares sem transformar esta frase em uma tabela ou alterar o texto editorial.'

function validationSnapshot(
  overrides: Partial<ContentVersionValidationSnapshot> = {},
): ContentVersionValidationSnapshot {
  return {
    versionId: VERSION_ID,
    publicationId: PUBLICATION_ID,
    locale: 'pt-BR',
    state: 'draft',
    bodyMarkdown:
      '## Comece com calma\n\nObserve seus sinais de fome e saciedade antes de montar cada refeição do dia com atenção.',
    updatedAt: UPDATED_AT,
    publishAt: null,
    ...overrides,
  }
}

function summary(): ContentPublicationSummary {
  return {
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
  }
}

function detail(): ContentPublicationDetail {
  return {
    ...summary(),
    createdBy: { id: ACTOR_ID, name: 'Editora', role: 'content_editor' },
    archivedBy: null,
    historyTruncated: false,
    versions: [
      {
        ...summary().versions[0],
        excerpt: 'Uma introdução suficientemente longa para o conteúdo.',
        bodyMarkdown:
          '## Comece com calma\n\nObserve seus sinais de fome e saciedade antes de montar cada refeição do dia.',
        bodyHash: 'a'.repeat(64),
        readingTimeMinutes: 1,
        tags: ['alimentacao-consciente'],
        cover: {
          assetId: ASSET_ID,
          mimeType: 'image/jpeg',
          sizeBytes: 1024,
          status: 'uploaded',
        },
        targeting: {
          protocols: ['recomposicao'],
          plans: ['mensal'],
          personalities: ['focus'],
        },
        author: { id: ACTOR_ID, name: 'Editora', role: 'content_editor' },
        reviewer: null,
        publisher: null,
        submittedAt: null,
        reviewedAt: null,
        rejectionReason: null,
        publishedAt: null,
      },
    ],
  }
}

function repository(): ContentAdminRepository {
  return {
    list: vi.fn(async () => [summary()]),
    get: vi.fn(async () => detail()),
    getVersionValidationSnapshot: vi.fn(async () => validationSnapshot()),
    createPublication: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      slug: 'alimentacao-consciente',
      createdAt: UPDATED_AT,
    })),
    createDraft: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      versionId: VERSION_ID,
      version: 1,
      locale: 'pt-BR',
      state: 'draft',
      updatedAt: UPDATED_AT,
    })),
    saveDraft: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      versionId: VERSION_ID,
      version: 1,
      state: 'draft',
      bodyHash: 'a'.repeat(64),
      readingTimeMinutes: 1,
      updatedAt: UPDATED_AT,
    })),
    submit: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      versionId: VERSION_ID,
      version: 1,
      state: 'in_review',
      bodyHash: 'a'.repeat(64),
      updatedAt: UPDATED_AT,
    })),
    review: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      versionId: VERSION_ID,
      version: 1,
      state: 'approved',
      bodyHash: 'a'.repeat(64),
      reviewedAt: UPDATED_AT,
      updatedAt: UPDATED_AT,
    })),
    publish: vi.fn(async () => ({
      publicationId: PUBLICATION_ID,
      versionId: VERSION_ID,
      version: 1,
      state: 'approved',
      effectiveState: 'published',
      publishAt: UPDATED_AT,
      bodyHash: 'a'.repeat(64),
      updatedAt: UPDATED_AT,
    })),
    archive: vi.fn(async () => ({
      outcome: 'archived',
      publicationId: PUBLICATION_ID,
      archivedAt: UPDATED_AT,
    })),
    createAsset: vi.fn(async () => ({
      assetId: ASSET_ID,
      bucketId: 'content-covers' as const,
      objectPath: `${ASSET_PATH}`,
      mimeType: 'image/jpeg' as const,
      declaredSizeBytes: 1024,
      status: 'pending_upload' as const,
      createdAt: UPDATED_AT,
    })),
    getAssetInternal: vi.fn(async () => ({
      assetId: ASSET_ID,
      bucketId: 'content-covers' as const,
      objectPath: ASSET_PATH,
      mimeType: 'image/jpeg' as const,
      declaredSizeBytes: 1024,
      actualSizeBytes: null,
      etag: null,
      status: 'pending_upload' as const,
    })),
    completeAsset: vi.fn(async () => ({
      assetId: ASSET_ID,
      status: 'uploaded',
      actualSizeBytes: 1024,
      uploadedAt: UPDATED_AT,
      updatedAt: UPDATED_AT,
    })),
    deleteAsset: vi.fn(async () => ({
      assetId: ASSET_ID,
      status: 'deleted',
      deletedAt: UPDATED_AT,
      updatedAt: UPDATED_AT,
    })),
  }
}

const ASSET_PATH = `content/${ASSET_ID}.jpg`

function storage(): ContentAdminStorage {
  return {
    createSignedUpload: vi.fn(async () => ({
      signedUrl: `https://storage.example.test/object/upload/sign/content-covers/${ASSET_PATH}?token=secret`,
    })),
    getObjectInfo: vi.fn(async () => ({
      size: 1024,
      contentType: 'image/jpeg',
      etag: 'exact-etag',
    })),
    remove: vi.fn(async () => undefined),
  }
}

function validDraft() {
  return {
    locale: 'pt-BR' as const,
    category: 'nutrition' as const,
    title: ' Alimentação consciente ',
    excerpt: ' Uma introdução suficientemente longa para o conteúdo. ',
    bodyMarkdown:
      '## Comece com calma\r\n\r\nObserve seus sinais de fome e saciedade antes de montar cada refeição do dia com atenção.',
    tags: [' Alimentação Consciente '],
    featuredToday: false,
    coverAssetId: null,
    targeting: {
      protocols: ['recomposicao' as const],
      plans: ['mensal' as const],
      personalities: ['focus' as const],
    },
  }
}

describe('content admin service', () => {
  it('validates bounded list filters and returns only summary fields', async () => {
    const repo = repository()
    const unsafe = {
      ...summary(),
      bodyMarkdown: 'must never leave the service',
      objectPath: 'content/private.jpg',
      bucketId: 'content-covers',
      etag: 'private-etag',
      signedUrl: 'https://storage.example.test/private?token=secret',
    }
    vi.mocked(repo.list).mockResolvedValue([unsafe])
    const service = createContentAdminService({ repository: repo, storage: storage() })

    const result = await service.list({
      status: 'draft',
      locale: 'pt-BR',
      category: 'nutrition',
      authorId: ACTOR_ID,
      reviewerId: ACTOR_ID,
      schedule: 'unscheduled',
      featuredToday: false,
      limit: 25,
      offset: 5,
    })

    expect(repo.list).toHaveBeenCalledWith({
      status: 'draft',
      locale: 'pt-BR',
      category: 'nutrition',
      authorId: ACTOR_ID,
      reviewerId: ACTOR_ID,
      schedule: 'unscheduled',
      featuredToday: false,
      limit: 25,
      offset: 5,
    })
    expect(result).toEqual({
      publications: [summary()],
      exhausted: false,
      truncated: false,
    })
    expect(JSON.stringify(result)).not.toMatch(/bodyMarkdown|objectPath|bucketId|etag|signedUrl/)

    await expect(service.list({ limit: 101 })).rejects.toBeInstanceOf(ContentAdminError)
    expect(repo.list).toHaveBeenCalledTimes(1)
  })

  it('returns strict detail DTOs without storage internals', async () => {
    const repo = repository()
    const unsafe = {
      ...detail(),
      objectPath: ASSET_PATH,
      bucketId: 'content-covers',
      etag: 'private-etag',
      token: 'private-token',
    }
    vi.mocked(repo.get).mockResolvedValue(unsafe)
    const service = createContentAdminService({ repository: repo, storage: storage() })

    const result = await service.get({ publicationId: PUBLICATION_ID })

    expect(result).toEqual(detail())
    expect(JSON.stringify(result)).not.toMatch(/objectPath|bucketId|etag|token|signedUrl/)
  })

  it('normalizes Task 1 Markdown and metadata before saving a draft', async () => {
    const repo = repository()
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await service.saveDraft({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      expectedUpdatedAt: UPDATED_AT,
      draft: validDraft(),
    })

    expect(repo.saveDraft).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      expectedUpdatedAt: UPDATED_AT,
      draft: {
        ...validDraft(),
        title: 'Alimentação consciente',
        excerpt: 'Uma introdução suficientemente longa para o conteúdo.',
        bodyMarkdown:
          '## Comece com calma\n\nObserve seus sinais de fome e saciedade antes de montar cada refeição do dia com atenção.\n',
        tags: ['alimentacao-consciente'],
      },
    })
  })

  it('rejects invalid Markdown before persistence and preserves stale conflicts', async () => {
    const repo = repository()
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await expect(
      service.saveDraft({
        actorId: ACTOR_ID,
        versionId: VERSION_ID,
        expectedUpdatedAt: UPDATED_AT,
        draft: { ...validDraft(), bodyMarkdown: `<script>${'x'.repeat(100)}</script>` },
      }),
    ).rejects.toMatchObject({ code: 'validation' })
    expect(repo.saveDraft).not.toHaveBeenCalled()

    const stale = new ContentAdminError('stale', 'submit')
    vi.mocked(repo.submit).mockRejectedValueOnce(stale)
    await expect(
      service.submit({ actorId: ACTOR_ID, versionId: VERSION_ID, expectedUpdatedAt: UPDATED_AT }),
    ).rejects.toBe(stale)
  })

  it('rejects a direct table-bearing service draft before persistence', async () => {
    const repo = repository()
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await expect(
      service.saveDraft({
        actorId: ACTOR_ID,
        versionId: VERSION_ID,
        expectedUpdatedAt: UPDATED_AT,
        draft: { ...validDraft(), bodyMarkdown: PIPE_TABLE_MARKDOWN },
      }),
    ).rejects.toMatchObject({ code: 'validation', operation: 'saveDraft' })

    expect(repo.saveDraft).not.toHaveBeenCalled()
  })

  it('leaves source-free createDraft unchanged and performs no validation snapshot read', async () => {
    const repo = repository()
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await service.createDraft({
      actorId: ACTOR_ID,
      publicationId: PUBLICATION_ID,
      locale: 'pt-BR',
    })

    expect(repo.getVersionValidationSnapshot).not.toHaveBeenCalled()
    expect(repo.createDraft).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      publicationId: PUBLICATION_ID,
      locale: 'pt-BR',
    })
  })

  it('rejects a table-bearing immutable source before createDraft can clone it', async () => {
    const repo = repository()
    vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(
      validationSnapshot({
        versionId: SOURCE_VERSION_ID,
        state: 'approved',
        bodyMarkdown: PIPE_TABLE_MARKDOWN,
      }),
    )
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await expect(
      service.createDraft({
        actorId: ACTOR_ID,
        publicationId: PUBLICATION_ID,
        locale: 'pt-BR',
        sourceVersionId: SOURCE_VERSION_ID,
      }),
    ).rejects.toMatchObject({ code: 'validation', operation: 'createDraft' })

    expect(repo.getVersionValidationSnapshot).toHaveBeenCalledWith(SOURCE_VERSION_ID)
    expect(repo.createDraft).not.toHaveBeenCalled()
  })

  it('rejects a legacy table-bearing draft before submit', async () => {
    const repo = repository()
    vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(
      validationSnapshot({ state: 'draft', bodyMarkdown: PIPE_TABLE_MARKDOWN }),
    )
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await expect(
      service.submit({ actorId: ACTOR_ID, versionId: VERSION_ID, expectedUpdatedAt: UPDATED_AT }),
    ).rejects.toMatchObject({ code: 'validation', operation: 'submit' })

    expect(repo.getVersionValidationSnapshot).toHaveBeenCalledWith(VERSION_ID, UPDATED_AT)
    expect(repo.submit).not.toHaveBeenCalled()
  })

  it('blocks approval for a table-bearing in-review version but keeps reject available', async () => {
    const approvingRepository = repository()
    vi.mocked(approvingRepository.getVersionValidationSnapshot).mockResolvedValueOnce(
      validationSnapshot({ state: 'in_review', bodyMarkdown: PIPE_TABLE_MARKDOWN }),
    )
    const approvingService = createContentAdminService({
      repository: approvingRepository,
      storage: storage(),
    })

    await expect(
      approvingService.review({
        actorId: ACTOR_ID,
        versionId: VERSION_ID,
        decision: 'approve',
        rejectionReason: null,
      }),
    ).rejects.toMatchObject({ code: 'validation', operation: 'review' })
    expect(approvingRepository.review).not.toHaveBeenCalled()

    const rejectingRepository = repository()
    const rejectingService = createContentAdminService({
      repository: rejectingRepository,
      storage: storage(),
    })
    await rejectingService.review({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      decision: 'reject',
      rejectionReason: 'A tabela não faz parte do contrato editorial.',
    })

    expect(rejectingRepository.getVersionValidationSnapshot).not.toHaveBeenCalled()
    expect(rejectingRepository.review).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      decision: 'reject',
      rejectionReason: 'A tabela não faz parte do contrato editorial.',
    })
  })

  it('rejects a table-bearing approved version before publish', async () => {
    const repo = repository()
    vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(
      validationSnapshot({ state: 'approved', bodyMarkdown: PIPE_TABLE_MARKDOWN }),
    )
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await expect(
      service.publish({ actorId: ACTOR_ID, versionId: VERSION_ID, publishAt: null }),
    ).rejects.toMatchObject({ code: 'validation', operation: 'publish' })

    expect(repo.getVersionValidationSnapshot).toHaveBeenCalledWith(VERSION_ID)
    expect(repo.publish).not.toHaveBeenCalled()
  })

  it('advances ordinary pipe Markdown through clone, submit, approve and publish unchanged', async () => {
    const repo = repository()
    vi.mocked(repo.getVersionValidationSnapshot)
      .mockResolvedValueOnce(
        validationSnapshot({
          versionId: SOURCE_VERSION_ID,
          state: 'approved',
          bodyMarkdown: ORDINARY_PIPE_MARKDOWN,
        }),
      )
      .mockResolvedValueOnce(
        validationSnapshot({ state: 'draft', bodyMarkdown: ORDINARY_PIPE_MARKDOWN }),
      )
      .mockResolvedValueOnce(
        validationSnapshot({ state: 'in_review', bodyMarkdown: ORDINARY_PIPE_MARKDOWN }),
      )
      .mockResolvedValueOnce(
        validationSnapshot({ state: 'approved', bodyMarkdown: ORDINARY_PIPE_MARKDOWN }),
      )
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await service.createDraft({
      actorId: ACTOR_ID,
      publicationId: PUBLICATION_ID,
      locale: 'pt-BR',
      sourceVersionId: SOURCE_VERSION_ID,
    })
    await service.submit({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      expectedUpdatedAt: UPDATED_AT,
    })
    await service.review({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      decision: 'approve',
      rejectionReason: null,
    })
    await service.publish({ actorId: ACTOR_ID, versionId: VERSION_ID, publishAt: null })

    expect(repo.getVersionValidationSnapshot).toHaveBeenCalledTimes(4)
    expect(repo.createDraft).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      publicationId: PUBLICATION_ID,
      locale: 'pt-BR',
      sourceVersionId: SOURCE_VERSION_ID,
    })
    expect(repo.submit).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      expectedUpdatedAt: UPDATED_AT,
    })
    expect(repo.review).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      decision: 'approve',
      rejectionReason: null,
    })
    expect(repo.publish).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      publishAt: null,
    })
    expect(repo.saveDraft).not.toHaveBeenCalled()
  })

  it('keeps the locked submit RPC authoritative for preflight and post-preflight races', async () => {
    const scenarios = [
      { snapshot: null, error: new ContentAdminError('stale', 'submit') },
      {
        snapshot: validationSnapshot({ state: 'draft' }),
        error: new ContentAdminError('stale', 'submit'),
      },
      {
        snapshot: validationSnapshot({ state: 'draft' }),
        error: new ContentAdminError('lifecycle', 'submit'),
      },
    ]

    for (const scenario of scenarios) {
      const repo = repository()
      vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(scenario.snapshot)
      vi.mocked(repo.submit).mockRejectedValueOnce(scenario.error)
      const service = createContentAdminService({ repository: repo, storage: storage() })

      await expect(
        service.submit({ actorId: ACTOR_ID, versionId: VERSION_ID, expectedUpdatedAt: UPDATED_AT }),
      ).rejects.toBe(scenario.error)
      expect(repo.getVersionValidationSnapshot).toHaveBeenCalledWith(VERSION_ID, UPDATED_AT)
      expect(repo.submit).toHaveBeenCalledWith({
        actorId: ACTOR_ID,
        versionId: VERSION_ID,
        expectedUpdatedAt: UPDATED_AT,
      })
    }
  })

  it('delegates a submit snapshot already outside draft so the locked RPC owns lifecycle', async () => {
    const repo = repository()
    const lifecycle = new ContentAdminError('lifecycle', 'submit')
    vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(
      validationSnapshot({ state: 'in_review' }),
    )
    vi.mocked(repo.submit).mockRejectedValueOnce(lifecycle)
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await expect(
      service.submit({ actorId: ACTOR_ID, versionId: VERSION_ID, expectedUpdatedAt: UPDATED_AT }),
    ).rejects.toBe(lifecycle)

    expect(repo.getVersionValidationSnapshot).toHaveBeenCalledWith(VERSION_ID, UPDATED_AT)
    expect(repo.submit).toHaveBeenCalledOnce()
  })

  it('fails absent source, approval and publish snapshots closed as not_found', async () => {
    const cases = [
      {
        operation: 'createDraft',
        invoke: (service: ReturnType<typeof createContentAdminService>) =>
          service.createDraft({
            actorId: ACTOR_ID,
            publicationId: PUBLICATION_ID,
            locale: 'pt-BR',
            sourceVersionId: SOURCE_VERSION_ID,
          }),
        mutation: 'createDraft' as const,
      },
      {
        operation: 'review',
        invoke: (service: ReturnType<typeof createContentAdminService>) =>
          service.review({
            actorId: ACTOR_ID,
            versionId: VERSION_ID,
            decision: 'approve',
            rejectionReason: null,
          }),
        mutation: 'review' as const,
      },
      {
        operation: 'publish',
        invoke: (service: ReturnType<typeof createContentAdminService>) =>
          service.publish({ actorId: ACTOR_ID, versionId: VERSION_ID, publishAt: null }),
        mutation: 'publish' as const,
      },
    ]

    for (const testCase of cases) {
      const repo = repository()
      vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(null)
      const service = createContentAdminService({ repository: repo, storage: storage() })

      await expect(testCase.invoke(service)).rejects.toMatchObject({
        code: 'not_found',
        operation: testCase.operation,
      })
      expect(repo[testCase.mutation]).not.toHaveBeenCalled()
    }
  })

  it.each([
    ['publication', { publicationId: ASSET_ID }],
    ['locale', { locale: 'en-US' as const }],
    ['draft lifecycle', { state: 'draft' as const }],
  ])('fails a clone source with mismatched %s locally as lifecycle', async (_case, overrides) => {
    const repo = repository()
    vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(
      validationSnapshot({
        versionId: SOURCE_VERSION_ID,
        state: 'approved',
        ...overrides,
      }),
    )
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await expect(
      service.createDraft({
        actorId: ACTOR_ID,
        publicationId: PUBLICATION_ID,
        locale: 'pt-BR',
        sourceVersionId: SOURCE_VERSION_ID,
      }),
    ).rejects.toMatchObject({ code: 'lifecycle', operation: 'createDraft' })
    expect(repo.createDraft).not.toHaveBeenCalled()
  })

  it('stops an in-review source locally even if a concurrent reject could make it cloneable', async () => {
    const repo = repository()
    vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(
      validationSnapshot({ versionId: SOURCE_VERSION_ID, state: 'in_review' }),
    )
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await expect(
      service.createDraft({
        actorId: ACTOR_ID,
        publicationId: PUBLICATION_ID,
        locale: 'pt-BR',
        sourceVersionId: SOURCE_VERSION_ID,
      }),
    ).rejects.toMatchObject({ code: 'lifecycle', operation: 'createDraft' })
    expect(repo.createDraft).not.toHaveBeenCalled()
  })

  it('fails approval and publish lifecycle mismatches locally without mutations', async () => {
    const approvalRepository = repository()
    vi.mocked(approvalRepository.getVersionValidationSnapshot).mockResolvedValueOnce(
      validationSnapshot({ state: 'draft' }),
    )
    const approvalService = createContentAdminService({
      repository: approvalRepository,
      storage: storage(),
    })
    await expect(
      approvalService.review({
        actorId: ACTOR_ID,
        versionId: VERSION_ID,
        decision: 'approve',
        rejectionReason: null,
      }),
    ).rejects.toMatchObject({ code: 'lifecycle', operation: 'review' })
    expect(approvalRepository.review).not.toHaveBeenCalled()

    for (const snapshot of [
      validationSnapshot({ state: 'in_review' }),
      validationSnapshot({ state: 'approved', publishAt: UPDATED_AT }),
    ]) {
      const publishRepository = repository()
      vi.mocked(publishRepository.getVersionValidationSnapshot).mockResolvedValueOnce(snapshot)
      const publishService = createContentAdminService({
        repository: publishRepository,
        storage: storage(),
      })
      await expect(
        publishService.publish({ actorId: ACTOR_ID, versionId: VERSION_ID, publishAt: null }),
      ).rejects.toMatchObject({ code: 'lifecycle', operation: 'publish' })
      expect(publishRepository.publish).not.toHaveBeenCalled()
    }
  })

  it('fails null stored Markdown closed before clone, submit, approve or publish', async () => {
    const cases = [
      {
        snapshot: validationSnapshot({
          versionId: SOURCE_VERSION_ID,
          state: 'approved',
          bodyMarkdown: null,
        }),
        operation: 'createDraft',
        mutation: 'createDraft' as const,
        invoke: (service: ReturnType<typeof createContentAdminService>) =>
          service.createDraft({
            actorId: ACTOR_ID,
            publicationId: PUBLICATION_ID,
            locale: 'pt-BR',
            sourceVersionId: SOURCE_VERSION_ID,
          }),
      },
      {
        snapshot: validationSnapshot({ state: 'draft', bodyMarkdown: null }),
        operation: 'submit',
        mutation: 'submit' as const,
        invoke: (service: ReturnType<typeof createContentAdminService>) =>
          service.submit({
            actorId: ACTOR_ID,
            versionId: VERSION_ID,
            expectedUpdatedAt: UPDATED_AT,
          }),
      },
      {
        snapshot: validationSnapshot({ state: 'in_review', bodyMarkdown: null }),
        operation: 'review',
        mutation: 'review' as const,
        invoke: (service: ReturnType<typeof createContentAdminService>) =>
          service.review({
            actorId: ACTOR_ID,
            versionId: VERSION_ID,
            decision: 'approve',
            rejectionReason: null,
          }),
      },
      {
        snapshot: validationSnapshot({ state: 'approved', bodyMarkdown: null }),
        operation: 'publish',
        mutation: 'publish' as const,
        invoke: (service: ReturnType<typeof createContentAdminService>) =>
          service.publish({ actorId: ACTOR_ID, versionId: VERSION_ID, publishAt: null }),
      },
    ]

    for (const testCase of cases) {
      const repo = repository()
      vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(testCase.snapshot)
      const service = createContentAdminService({ repository: repo, storage: storage() })

      await expect(testCase.invoke(service)).rejects.toMatchObject({
        code: 'validation',
        operation: testCase.operation,
      })
      expect(repo[testCase.mutation]).not.toHaveBeenCalled()
    }
  })

  it('preserves copy-from-version through the draft RPC boundary', async () => {
    const repo = repository()
    vi.mocked(repo.getVersionValidationSnapshot).mockResolvedValueOnce(
      validationSnapshot({ versionId: SOURCE_VERSION_ID, state: 'approved' }),
    )
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await service.createDraft({
      actorId: ACTOR_ID,
      publicationId: PUBLICATION_ID,
      locale: 'pt-BR',
      sourceVersionId: SOURCE_VERSION_ID,
    })

    expect(repo.createDraft).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      publicationId: PUBLICATION_ID,
      locale: 'pt-BR',
      sourceVersionId: SOURCE_VERSION_ID,
    })
  })

  it('generates the cover UUID/path server-side and returns one upload capability', async () => {
    const repo = repository()
    const coverStorage = storage()
    const service = createContentAdminService({
      repository: repo,
      storage: coverStorage,
      generateUuid: () => ASSET_ID,
    })

    const result = await service.createCover({
      actorId: ACTOR_ID,
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
    })

    expect(repo.createAsset).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      assetId: ASSET_ID,
      mimeType: 'image/jpeg',
      declaredSizeBytes: 1024,
      objectPath: ASSET_PATH,
    })
    expect(coverStorage.createSignedUpload).toHaveBeenCalledWith(ASSET_PATH)
    expect(result).toEqual({
      asset: {
        assetId: ASSET_ID,
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        status: 'pending_upload',
      },
      upload: {
        signedUrl: expect.stringContaining('token=secret'),
      },
    })
    expect(Object.keys(result.upload)).toEqual(['signedUrl'])
    expect(JSON.stringify(result.asset)).not.toMatch(/path|bucket|etag|token/i)
  })

  it.each([
    { mimeType: 'image/svg+xml', sizeBytes: 1024 },
    { mimeType: 'image/jpeg', sizeBytes: 0 },
    { mimeType: 'image/png', sizeBytes: 10 * 1024 * 1024 + 1 },
  ])('rejects invalid cover declaration $mimeType/$sizeBytes', async (input) => {
    const repo = repository()
    const service = createContentAdminService({ repository: repo, storage: storage() })

    await expect(
      service.createCover({ actorId: ACTOR_ID, ...input } as never),
    ).rejects.toMatchObject({ code: 'validation' })
    expect(repo.createAsset).not.toHaveBeenCalled()
  })

  it('audits and removes the pending asset when signed upload creation fails', async () => {
    const order: string[] = []
    const repo = repository()
    const coverStorage = storage()
    vi.mocked(repo.createAsset).mockImplementation(async () => {
      order.push('create-rpc')
      return {
        assetId: ASSET_ID,
        bucketId: 'content-covers',
        objectPath: ASSET_PATH,
        mimeType: 'image/jpeg',
        declaredSizeBytes: 1024,
        status: 'pending_upload',
        createdAt: UPDATED_AT,
      }
    })
    vi.mocked(coverStorage.createSignedUpload).mockImplementation(async () => {
      order.push('signed-upload')
      throw new ContentStorageError('transient', 'create_upload')
    })
    vi.mocked(repo.deleteAsset).mockImplementation(async () => {
      order.push('delete-rpc')
      return { assetId: ASSET_ID, status: 'deleted', deletedAt: UPDATED_AT, updatedAt: UPDATED_AT }
    })
    vi.mocked(coverStorage.remove).mockImplementation(async () => {
      order.push('storage-remove')
    })
    const service = createContentAdminService({
      repository: repo,
      storage: coverStorage,
      generateUuid: () => ASSET_ID,
    })

    await expect(
      service.createCover({ actorId: ACTOR_ID, mimeType: 'image/jpeg', sizeBytes: 1024 }),
    ).rejects.toMatchObject({ code: 'storage_unavailable' })
    expect(order).toEqual(['create-rpc', 'signed-upload', 'delete-rpc', 'storage-remove'])
  })

  it('completes only after exact Storage size, MIME, and ETag verification', async () => {
    const repo = repository()
    const coverStorage = storage()
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    const result = await service.completeCover({ actorId: ACTOR_ID, assetId: ASSET_ID })

    expect(coverStorage.getObjectInfo).toHaveBeenCalledWith(ASSET_PATH)
    expect(repo.completeAsset).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      assetId: ASSET_ID,
      actualSizeBytes: 1024,
      etag: 'exact-etag',
    })
    expect(result).toEqual({
      assetId: ASSET_ID,
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      status: 'uploaded',
    })
  })

  it('returns the uploaded asset when a concurrent completion wins the RPC race', async () => {
    const repo = repository()
    const coverStorage = storage()
    vi.mocked(repo.getAssetInternal)
      .mockResolvedValueOnce({
        assetId: ASSET_ID,
        bucketId: 'content-covers',
        objectPath: ASSET_PATH,
        mimeType: 'image/jpeg',
        declaredSizeBytes: 1024,
        actualSizeBytes: null,
        etag: null,
        status: 'pending_upload',
      })
      .mockResolvedValueOnce({
        assetId: ASSET_ID,
        bucketId: 'content-covers',
        objectPath: ASSET_PATH,
        mimeType: 'image/jpeg',
        declaredSizeBytes: 1024,
        actualSizeBytes: 1024,
        etag: 'winning-etag',
        status: 'uploaded',
      })
    vi.mocked(repo.completeAsset).mockRejectedValue(
      new ContentAdminError('cover_mismatch', 'completeAsset'),
    )
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    await expect(service.completeCover({ actorId: ACTOR_ID, assetId: ASSET_ID })).resolves.toEqual({
      assetId: ASSET_ID,
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      status: 'uploaded',
    })
    expect(repo.getAssetInternal).toHaveBeenCalledTimes(2)
    expect(repo.deleteAsset).not.toHaveBeenCalled()
    expect(coverStorage.remove).not.toHaveBeenCalled()
  })

  it('returns an already uploaded asset without another Storage or RPC operation', async () => {
    const repo = repository()
    const coverStorage = storage()
    vi.mocked(repo.getAssetInternal).mockResolvedValue({
      assetId: ASSET_ID,
      bucketId: 'content-covers',
      objectPath: ASSET_PATH,
      mimeType: 'image/jpeg',
      declaredSizeBytes: 1024,
      actualSizeBytes: 1024,
      etag: 'persisted-etag',
      status: 'uploaded',
    })
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    await expect(service.completeCover({ actorId: ACTOR_ID, assetId: ASSET_ID })).resolves.toEqual({
      assetId: ASSET_ID,
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      status: 'uploaded',
    })
    expect(coverStorage.getObjectInfo).not.toHaveBeenCalled()
    expect(repo.completeAsset).not.toHaveBeenCalled()
    expect(repo.deleteAsset).not.toHaveBeenCalled()
    expect(coverStorage.remove).not.toHaveBeenCalled()
  })

  it('maps a deleted asset after a completion race to lifecycle without cleanup', async () => {
    const repo = repository()
    const coverStorage = storage()
    vi.mocked(repo.getAssetInternal)
      .mockResolvedValueOnce({
        assetId: ASSET_ID,
        bucketId: 'content-covers',
        objectPath: ASSET_PATH,
        mimeType: 'image/jpeg',
        declaredSizeBytes: 1024,
        actualSizeBytes: null,
        etag: null,
        status: 'pending_upload',
      })
      .mockResolvedValueOnce({
        assetId: ASSET_ID,
        bucketId: 'content-covers',
        objectPath: ASSET_PATH,
        mimeType: 'image/jpeg',
        declaredSizeBytes: 1024,
        actualSizeBytes: null,
        etag: null,
        status: 'deleted',
      })
    vi.mocked(repo.completeAsset).mockRejectedValue(
      new ContentAdminError('cover_mismatch', 'completeAsset'),
    )
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    await expect(
      service.completeCover({ actorId: ACTOR_ID, assetId: ASSET_ID }),
    ).rejects.toMatchObject({ code: 'lifecycle', operation: 'completeCover' })
    expect(repo.getAssetInternal).toHaveBeenCalledTimes(2)
    expect(repo.deleteAsset).not.toHaveBeenCalled()
    expect(coverStorage.remove).not.toHaveBeenCalled()
  })

  it.each([
    { size: 2048, contentType: 'image/jpeg', etag: 'exact-etag' },
    { size: 1024, contentType: 'image/png', etag: 'exact-etag' },
    { size: 1024, contentType: 'image/jpeg', etag: null },
    { size: 1024, contentType: 'image/jpeg', etag: '   ' },
  ])('deletes the audited asset before removing a mismatched object', async (info) => {
    const order: string[] = []
    const repo = repository()
    const coverStorage = storage()
    vi.mocked(coverStorage.getObjectInfo).mockResolvedValue(info)
    vi.mocked(repo.deleteAsset).mockImplementation(async () => {
      order.push('delete-rpc')
      return { assetId: ASSET_ID, status: 'deleted', deletedAt: UPDATED_AT, updatedAt: UPDATED_AT }
    })
    vi.mocked(coverStorage.remove).mockImplementation(async () => {
      order.push('storage-remove')
    })
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    await expect(
      service.completeCover({ actorId: ACTOR_ID, assetId: ASSET_ID }),
    ).rejects.toMatchObject({ code: 'cover_mismatch' })
    expect(order).toEqual(['delete-rpc', 'storage-remove'])
    expect(repo.completeAsset).not.toHaveBeenCalled()
  })

  it('cleans up when the completion RPC detects a Storage metadata race', async () => {
    const order: string[] = []
    const repo = repository()
    const coverStorage = storage()
    vi.mocked(repo.completeAsset).mockImplementation(async () => {
      order.push('complete-rpc')
      throw new ContentAdminError('cover_mismatch', 'completeAsset')
    })
    vi.mocked(repo.deleteAsset).mockImplementation(async () => {
      order.push('delete-rpc')
      return { assetId: ASSET_ID, status: 'deleted', deletedAt: UPDATED_AT, updatedAt: UPDATED_AT }
    })
    vi.mocked(coverStorage.remove).mockImplementation(async () => {
      order.push('storage-remove')
    })
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    await expect(
      service.completeCover({ actorId: ACTOR_ID, assetId: ASSET_ID }),
    ).rejects.toMatchObject({ code: 'cover_mismatch' })
    expect(repo.getAssetInternal).toHaveBeenCalledTimes(2)
    expect(order).toEqual(['complete-rpc', 'delete-rpc', 'storage-remove'])
  })

  it('does not remove Storage when pending cleanup loses to an uploaded asset', async () => {
    const repo = repository()
    const coverStorage = storage()
    let persistedStatus: 'pending_upload' | 'uploaded' = 'pending_upload'
    vi.mocked(coverStorage.getObjectInfo).mockResolvedValue({
      size: 2048,
      contentType: 'image/jpeg',
      etag: 'changed-object',
    })
    vi.mocked(repo.deleteAsset).mockImplementation(async (input) => {
      persistedStatus = 'uploaded'
      expect(input).toEqual({
        actorId: ACTOR_ID,
        assetId: ASSET_ID,
        expectedStatus: 'pending_upload',
      })
      throw new ContentAdminError('stale', 'deleteAsset')
    })
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    await expect(
      service.completeCover({ actorId: ACTOR_ID, assetId: ASSET_ID }),
    ).rejects.toMatchObject({ code: 'stale', operation: 'deleteAsset' })
    expect(persistedStatus).toBe('uploaded')
    expect(repo.deleteAsset).toHaveBeenCalledOnce()
    expect(coverStorage.remove).not.toHaveBeenCalled()
  })

  it('cleans up a missing object but leaves pending state on transient info failures', async () => {
    const repo = repository()
    const coverStorage = storage()
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    vi.mocked(coverStorage.getObjectInfo).mockRejectedValueOnce(
      new ContentStorageError('missing', 'info'),
    )
    await expect(
      service.completeCover({ actorId: ACTOR_ID, assetId: ASSET_ID }),
    ).rejects.toMatchObject({ code: 'cover_mismatch' })
    expect(repo.deleteAsset).toHaveBeenCalledOnce()
    expect(coverStorage.remove).toHaveBeenCalledOnce()

    vi.clearAllMocks()
    vi.mocked(repo.getAssetInternal).mockResolvedValue({
      assetId: ASSET_ID,
      bucketId: 'content-covers',
      objectPath: ASSET_PATH,
      mimeType: 'image/jpeg',
      declaredSizeBytes: 1024,
      actualSizeBytes: null,
      etag: null,
      status: 'pending_upload',
    })
    vi.mocked(coverStorage.getObjectInfo).mockRejectedValueOnce(
      new ContentStorageError('transient', 'info'),
    )
    await expect(
      service.completeCover({ actorId: ACTOR_ID, assetId: ASSET_ID }),
    ).rejects.toMatchObject({ code: 'storage_unavailable' })
    expect(repo.deleteAsset).not.toHaveBeenCalled()
    expect(coverStorage.remove).not.toHaveBeenCalled()
  })

  it('calls the delete RPC before Storage and never removes a referenced cover', async () => {
    const order: string[] = []
    const repo = repository()
    const coverStorage = storage()
    vi.mocked(repo.deleteAsset).mockImplementation(async () => {
      order.push('delete-rpc')
      throw new ContentAdminError('cover_referenced', 'deleteCover')
    })
    vi.mocked(coverStorage.remove).mockImplementation(async () => {
      order.push('storage-remove')
    })
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    await expect(
      service.deleteCover({ actorId: ACTOR_ID, assetId: ASSET_ID }),
    ).rejects.toMatchObject({ code: 'cover_referenced' })
    expect(order).toEqual(['delete-rpc'])
  })

  it('retries orphan cleanup for an asset already marked deleted', async () => {
    const order: string[] = []
    const repo = repository()
    const coverStorage = storage()
    vi.mocked(repo.getAssetInternal).mockResolvedValue({
      assetId: ASSET_ID,
      bucketId: 'content-covers',
      objectPath: ASSET_PATH,
      mimeType: 'image/jpeg',
      declaredSizeBytes: 1024,
      actualSizeBytes: null,
      etag: null,
      status: 'deleted',
    })
    vi.mocked(repo.deleteAsset).mockImplementation(async () => {
      order.push('delete-rpc')
      return { assetId: ASSET_ID, status: 'deleted', deletedAt: UPDATED_AT, updatedAt: UPDATED_AT }
    })
    vi.mocked(coverStorage.remove).mockImplementation(async () => {
      order.push('storage-remove')
    })
    const service = createContentAdminService({ repository: repo, storage: coverStorage })

    await service.deleteCover({ actorId: ACTOR_ID, assetId: ASSET_ID })

    expect(order).toEqual(['delete-rpc', 'storage-remove'])
    expect(repo.deleteAsset).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      assetId: ASSET_ID,
      expectedStatus: 'deleted',
    })
  })

  it('does not log signed URLs, object paths, or provider details', async () => {
    const repo = repository()
    const coverStorage = storage()
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    vi.mocked(coverStorage.createSignedUpload).mockRejectedValue(
      new Error(`provider failed ${ASSET_PATH}?token=provider-secret`),
    )
    const service = createContentAdminService({
      repository: repo,
      storage: coverStorage,
      generateUuid: () => ASSET_ID,
    })

    const failure = await service
      .createCover({ actorId: ACTOR_ID, mimeType: 'image/jpeg', sizeBytes: 1024 })
      .catch((error: unknown) => error)

    expect(failure).toMatchObject({ code: 'storage_unavailable' })
    expect(String(failure)).not.toContain(ASSET_PATH)
    expect(String(failure)).not.toContain('provider-secret')
    expect(consoleError).not.toHaveBeenCalled()
    consoleError.mockRestore()
  })
})
