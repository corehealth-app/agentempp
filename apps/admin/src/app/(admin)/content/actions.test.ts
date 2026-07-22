import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { AdminRole } from '@/lib/admin-rbac'
import { ContentAdminError, type ContentAdminService } from '@/lib/content/admin-service'
import {
  ContentActionAuthError,
  type ContentAdminAction,
  type ContentAdminActionDependencies,
  executeContentAdminAction,
  runContentAdminAction,
} from './actions-core'

const productionMocks = vi.hoisted(() => ({
  createClient: vi.fn(),
  createServiceClient: vi.fn(),
  revalidatePath: vi.fn(),
}))

vi.mock('@/lib/supabase/server', () => ({
  createClient: productionMocks.createClient,
  createServiceClient: productionMocks.createServiceClient,
}))
vi.mock('next/cache', () => ({ revalidatePath: productionMocks.revalidatePath }))

import * as productionActions from './actions'

const ACTOR_ID = '00000000-0000-0000-0000-000000000701'
const PUBLICATION_ID = '00000000-0000-0000-0000-000000000702'
const VERSION_ID = '00000000-0000-0000-0000-000000000703'
const ASSET_ID = '00000000-0000-0000-0000-000000000704'
const UPDATED_AT = '2026-07-21T12:00:00.000Z'

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
    coverAssetId: null,
    targeting: {
      protocols: ['recomposicao' as const],
      plans: ['mensal' as const],
      personalities: ['focus' as const],
    },
  }
}

function action(type: ContentAdminAction['type']): ContentAdminAction {
  switch (type) {
    case 'list':
      return { type, input: { limit: 20, offset: 0 } }
    case 'get':
      return { type, input: { publicationId: PUBLICATION_ID } }
    case 'createPublication':
      return { type, input: { slug: 'alimentacao-consciente' } }
    case 'createDraft':
      return { type, input: { publicationId: PUBLICATION_ID, locale: 'pt-BR' } }
    case 'saveDraft':
      return {
        type,
        input: {
          versionId: VERSION_ID,
          expectedUpdatedAt: UPDATED_AT,
          draft: validDraft(),
        },
      }
    case 'submit':
      return { type, input: { versionId: VERSION_ID, expectedUpdatedAt: UPDATED_AT } }
    case 'review':
      return {
        type,
        input: { versionId: VERSION_ID, decision: 'approve', rejectionReason: null },
      }
    case 'publish':
      return { type, input: { versionId: VERSION_ID, publishAt: null } }
    case 'archive':
      return { type, input: { publicationId: PUBLICATION_ID } }
    case 'createCover':
      return { type, input: { mimeType: 'image/jpeg', sizeBytes: 1024 } }
    case 'completeCover':
    case 'deleteCover':
      return { type, input: { assetId: ASSET_ID } }
  }
}

function service(): ContentAdminService {
  const result = { publicationId: PUBLICATION_ID, updatedAt: UPDATED_AT }
  return {
    list: vi.fn(async () => ({ publications: [], exhausted: true, truncated: false })),
    get: vi.fn(
      async () => ({ publicationId: PUBLICATION_ID, archivedAt: null, versions: [] }) as never,
    ),
    createPublication: vi.fn(async () => result),
    createDraft: vi.fn(async () => result),
    saveDraft: vi.fn(async () => result),
    submit: vi.fn(async () => result),
    review: vi.fn(async () => result),
    publish: vi.fn(async () => result),
    archive: vi.fn(async () => result),
    createCover: vi.fn(async () => ({
      asset: {
        assetId: ASSET_ID,
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        status: 'pending_upload',
      },
      upload: { signedUrl: 'https://storage.example.test/upload?token=signed-secret' },
    })),
    completeCover: vi.fn(async () => ({
      assetId: ASSET_ID,
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      status: 'uploaded',
    })),
    deleteCover: vi.fn(async () => ({
      assetId: ASSET_ID,
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      status: 'deleted',
    })),
  } as ContentAdminService
}

function dependencies(role: AdminRole, contentService = service()) {
  const order: string[] = []
  const deps: ContentAdminActionDependencies = {
    loadAuthenticatedAdmin: vi.fn(async () => {
      order.push('authenticated-role')
      return { id: ACTOR_ID, role }
    }),
    createService: vi.fn(() => {
      order.push('service-role')
      return contentService
    }),
    revalidatePath: vi.fn(async (path: string, type?: 'page') => {
      order.push(type ? `revalidate:${path}:${type}` : `revalidate:${path}`)
    }),
  }
  return { deps, contentService, order }
}

const roleMatrix: Record<ContentAdminAction['type'], AdminRole[]> = {
  list: ['content_editor', 'nutrition_admin', 'master_admin'],
  get: ['content_editor', 'nutrition_admin', 'master_admin'],
  createPublication: ['content_editor'],
  createDraft: ['content_editor'],
  saveDraft: ['content_editor'],
  submit: ['content_editor'],
  review: ['nutrition_admin'],
  publish: ['master_admin'],
  archive: ['master_admin'],
  createCover: ['content_editor'],
  completeCover: ['content_editor'],
  deleteCover: ['content_editor'],
}

describe('content admin action core', () => {
  it.each(
    (Object.keys(roleMatrix) as ContentAdminAction['type'][]).flatMap((type) =>
      (
        [
          'support',
          'content_editor',
          'nutrition_admin',
          'operations_admin',
          'master_admin',
        ] as AdminRole[]
      ).map((role) => ({ type, role, allowed: roleMatrix[type].includes(role) })),
    ),
  )('$role allowed=$allowed for $type', async ({ type, role, allowed }) => {
    const { deps } = dependencies(role)
    const operation = executeContentAdminAction(action(type), deps)

    if (allowed) {
      await expect(operation).resolves.toBeDefined()
      expect(deps.createService).toHaveBeenCalledOnce()
    } else {
      await expect(operation).rejects.toMatchObject({ kind: 'forbidden' })
      expect(deps.createService).not.toHaveBeenCalled()
    }
    expect(deps.loadAuthenticatedAdmin).toHaveBeenCalledOnce()
  })

  it('authenticates and validates input before creating the privileged adapter', async () => {
    const { deps, order } = dependencies('content_editor')

    await expect(
      executeContentAdminAction(
        { type: 'createPublication', input: { slug: 'INVALID SLUG' } },
        deps,
      ),
    ).rejects.toMatchObject({ code: 'validation' })

    expect(order).toEqual(['authenticated-role'])
    expect(deps.createService).not.toHaveBeenCalled()
  })

  it('reauthenticates and recreates service dependencies for every action', async () => {
    const { deps } = dependencies('content_editor')

    await executeContentAdminAction(action('createPublication'), deps)
    await executeContentAdminAction(action('createDraft'), deps)

    expect(deps.loadAuthenticatedAdmin).toHaveBeenCalledTimes(2)
    expect(deps.createService).toHaveBeenCalledTimes(2)
  })

  it('injects only the authenticated actor id into mutations', async () => {
    const { deps, contentService } = dependencies('nutrition_admin')

    await executeContentAdminAction(action('review'), deps)

    expect(contentService.review).toHaveBeenCalledWith({
      actorId: ACTOR_ID,
      versionId: VERSION_ID,
      decision: 'approve',
      rejectionReason: null,
    })
  })

  it.each([
    ['draft', 'pt-BR', 'draft', null, true],
    ['in review', 'pt-BR', 'in_review', null, true],
    ['approved without publication', 'pt-BR', 'approved', null, true],
    ['a different locale', 'en-US', 'draft', null, false],
    ['rejected', 'pt-BR', 'rejected', null, false],
    ['approved with publication', 'pt-BR', 'approved', UPDATED_AT, false],
  ] as const)('enforces the open workflow preflight for %s through the authenticated server action', async (_caseName, locale, state, publishAt, blocked) => {
    const guardedService = service()
    vi.mocked(guardedService.get).mockResolvedValue({
      publicationId: PUBLICATION_ID,
      archivedAt: null,
      versions: [
        {
          versionId: VERSION_ID,
          locale,
          state,
          publishAt,
        },
      ],
    } as never)
    const { deps } = dependencies('content_editor', guardedService)

    const operation = executeContentAdminAction(action('createDraft'), deps)

    if (blocked) {
      await expect(operation).rejects.toMatchObject({
        code: 'lifecycle',
        operation: 'createDraft',
      })
      expect(guardedService.createDraft).not.toHaveBeenCalled()
    } else {
      await expect(operation).resolves.toBeDefined()
      expect(guardedService.createDraft).toHaveBeenCalledOnce()
    }
  })

  it('uses one general public message for every blocked open workflow', async () => {
    const guardedService = service()
    vi.mocked(guardedService.get).mockResolvedValue({
      publicationId: PUBLICATION_ID,
      archivedAt: null,
      versions: [
        {
          versionId: VERSION_ID,
          locale: 'pt-BR',
          state: 'in_review',
          publishAt: null,
        },
      ],
    } as never)
    const { deps } = dependencies('content_editor', guardedService)

    const result = await runContentAdminAction(action('createDraft'), deps)

    expect(result).toEqual({
      ok: false,
      error: 'Já existe um fluxo editorial aberto para este idioma.',
    })
    expect(guardedService.createDraft).not.toHaveBeenCalled()
  })

  it('revalidates list and concrete publication pages after successful mutations', async () => {
    const { deps } = dependencies('content_editor')

    await executeContentAdminAction(action('saveDraft'), deps)

    expect(deps.revalidatePath).toHaveBeenNthCalledWith(1, '/content')
    expect(deps.revalidatePath).toHaveBeenNthCalledWith(2, `/content/${PUBLICATION_ID}`)
  })

  it('uses the dynamic page type when a mutation has no concrete publication id', async () => {
    const { deps } = dependencies('content_editor')

    await executeContentAdminAction(action('createCover'), deps)

    expect(deps.revalidatePath).toHaveBeenNthCalledWith(1, '/content')
    expect(deps.revalidatePath).toHaveBeenNthCalledWith(2, '/content/[id]', 'page')
  })

  it('does not revalidate failed mutations or reads', async () => {
    const failedService = service()
    vi.mocked(failedService.submit).mockRejectedValue(new ContentAdminError('stale', 'submit'))
    const failed = dependencies('content_editor', failedService)
    await expect(executeContentAdminAction(action('submit'), failed.deps)).rejects.toMatchObject({
      code: 'stale',
    })
    expect(failed.deps.revalidatePath).not.toHaveBeenCalled()

    const read = dependencies('master_admin')
    await executeContentAdminAction(action('list'), read.deps)
    expect(read.deps.revalidatePath).not.toHaveBeenCalled()
  })

  it('returns only an allowlisted stale code for editorial conflict recovery', async () => {
    const staleService = service()
    vi.mocked(staleService.saveDraft).mockRejectedValue(new ContentAdminError('stale', 'saveDraft'))
    const { deps } = dependencies('content_editor', staleService)

    const result = await runContentAdminAction(action('saveDraft'), deps)

    expect(result).toEqual({
      ok: false,
      error: 'Este rascunho foi alterado. Atualize a baseline antes de salvar novamente.',
      code: 'stale',
    })
  })

  it.each([
    [new ContentActionAuthError('unauthenticated'), 'Faça login novamente para continuar.'],
    [new ContentActionAuthError('forbidden'), 'Você não tem acesso a esta operação.'],
    [
      new ContentAdminError('duplicate', 'createPublication'),
      'Já existe uma publicação com este slug.',
    ],
    [new ContentAdminError('duplicate', 'createDraft'), 'Já existe um rascunho para este idioma.'],
    [new ContentAdminError('not_found', 'get'), 'Conteúdo não encontrado.'],
    [
      new ContentAdminError('cover_referenced', 'deleteCover'),
      'Esta capa está em uso e não pode ser excluída.',
    ],
    [
      new ContentAdminError('cover_mismatch', 'completeCover'),
      'O arquivo da capa não corresponde ao envio solicitado.',
    ],
    [
      new ContentAdminError('storage_unavailable', 'createCover'),
      'Não foi possível acessar o armazenamento de capas agora.',
    ],
    [
      new Error('SQL secret content/asset.jpg?token=signed-secret'),
      'Não foi possível concluir a operação.',
    ],
  ] as const)('returns a bounded allowlisted public error for %#', async (failure, message) => {
    const failedService = service()
    vi.mocked(failedService.createPublication).mockRejectedValue(failure)
    const { deps } = dependencies('content_editor', failedService)

    const result = await runContentAdminAction(action('createPublication'), deps)

    expect(result).toEqual({ ok: false, error: message })
    if (result.ok) throw new Error('Expected a public action failure')
    expect(result).not.toHaveProperty('code')
    expect(result.error.length).toBeLessThanOrEqual(160)
    expect(JSON.stringify(result)).not.toMatch(/SQL secret|token=|content\/asset|provider/i)
  })

  it.each([
    new Date(UPDATED_AT),
    1n,
    new Error('private provider error'),
  ])('rejects non-serializable service output %#', async (unsafe) => {
    const unsafeService = service()
    vi.mocked(unsafeService.list).mockResolvedValue(unsafe as never)
    const { deps } = dependencies('master_admin', unsafeService)

    const result = await runContentAdminAction(action('list'), deps)

    expect(result).toEqual({ ok: false, error: 'Não foi possível concluir a operação.' })
  })
})

function configureProductionAuth(role: AdminRole, order: string[]) {
  const roleQuery = {
    select: vi.fn(() => roleQuery),
    eq: vi.fn(() => roleQuery),
    maybeSingle: vi.fn(async () => {
      order.push('admin-role')
      return { data: { id: ACTOR_ID, role }, error: null }
    }),
  }
  productionMocks.createClient.mockImplementation(async () => {
    order.push('create-client')
    return {
      auth: {
        getUser: vi.fn(async () => {
          order.push('get-user')
          return { data: { user: { id: ACTOR_ID } }, error: null }
        }),
      },
      from: vi.fn(() => roleQuery),
    }
  })
}

describe('content admin production actions', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('exports only async server action functions', () => {
    expect(Object.keys(productionActions).sort()).toEqual([
      'archiveContentPublicationAction',
      'completeContentCoverAction',
      'createContentCoverAction',
      'createContentDraftAction',
      'createContentPublicationAction',
      'deleteContentCoverAction',
      'getContentPublicationAction',
      'listContentPublicationsAction',
      'publishContentVersionAction',
      'reviewContentVersionAction',
      'saveContentDraftAction',
      'submitContentVersionAction',
    ])
    for (const exported of Object.values(productionActions)) {
      expect(exported).toBeTypeOf('function')
      expect(exported.constructor.name).toBe('AsyncFunction')
    }
  })

  it('uses fresh session auth and canonical role lookup before service_role', async () => {
    const order: string[] = []
    configureProductionAuth('content_editor', order)
    productionMocks.createServiceClient.mockImplementation(() => {
      order.push('service-role')
      return {
        rpc: vi.fn(async () => ({
          data: {
            publication_id: PUBLICATION_ID,
            slug: 'alimentacao-consciente',
            created_at: UPDATED_AT,
          },
          error: null,
        })),
        storage: { from: vi.fn() },
      }
    })

    const result = await productionActions.createContentPublicationAction({
      slug: 'alimentacao-consciente',
    })

    expect(result).toMatchObject({ ok: true })
    expect(order).toEqual(['create-client', 'get-user', 'admin-role', 'service-role'])
    expect(productionMocks.revalidatePath).toHaveBeenCalledWith('/content')
    expect(productionMocks.revalidatePath).toHaveBeenCalledWith(`/content/${PUBLICATION_ID}`)
  })

  it('never creates a privileged adapter for forbidden canonical roles', async () => {
    const order: string[] = []
    configureProductionAuth('support', order)

    const result = await productionActions.createContentPublicationAction({
      slug: 'alimentacao-consciente',
    })

    expect(result).toEqual({ ok: false, error: 'Você não tem acesso a esta operação.' })
    expect(order).toEqual(['create-client', 'get-user', 'admin-role'])
    expect(productionMocks.createServiceClient).not.toHaveBeenCalled()
  })

  it('creates a fresh authenticated client for every production action', async () => {
    const order: string[] = []
    configureProductionAuth('support', order)

    await productionActions.createContentPublicationAction({ slug: 'alimentacao-consciente' })
    await productionActions.createContentPublicationAction({ slug: 'outro-conteudo' })

    expect(productionMocks.createClient).toHaveBeenCalledTimes(2)
    expect(order.filter((step) => step === 'get-user')).toHaveLength(2)
    expect(order.filter((step) => step === 'admin-role')).toHaveLength(2)
  })
})
