import { createHash } from 'node:crypto'
import { describe, expect, it, vi } from 'vitest'
import type { AdminRole } from '@/lib/admin-rbac'
import type {
  CoachAssistedRevisionRequest,
  CoachCatalogEntry,
  CoachCatalogRepository,
  CoachRevisionRequest,
} from '@/lib/coach-messages/admin-service'
import {
  type CoachMessageActionDependencies,
  type CoachMessageServiceContext,
  executeCoachMessageAction,
} from './actions-core'

const ACTOR_ID = '00000000-0000-0000-0000-000000000501'
const PACK_ID = '00000000-0000-0000-0000-000000000502'
const TEMPLATE_ID = '00000000-0000-0000-0000-000000000503'
const VERSION_ID = '00000000-0000-0000-0000-000000000504'

function snapshotHash(entries: readonly CoachCatalogEntry[]): string {
  return createHash('sha256')
    .update(
      [...entries]
        .sort((left, right) => left.templateId.localeCompare(right.templateId))
        .map((entry) => `${entry.templateId}:${entry.templateVersionId}`)
        .join(','),
      'utf8',
    )
    .digest('hex')
}

function catalogEntry(): CoachCatalogEntry {
  return {
    packId: PACK_ID,
    packSlug: 'bodyflow-actions-test',
    packLabel: 'BodyFlow actions test',
    packStatus: 'draft',
    templateId: TEMPLATE_ID,
    templateKey: 'focus.hydration.in_app.pt-br.v1',
    personality: 'focus',
    context: 'hydration',
    channel: 'in_app',
    locale: 'pt-BR',
    variant: 1,
    allowedVariables: ['name', 'water_remaining_ml'],
    requiredVariables: ['name', 'water_remaining_ml'],
    templateVersionId: VERSION_ID,
    version: 1,
    title: null,
    subject: null,
    body: '{{name}}, faltam {{water_remaining_ml}} ml no exemplo.',
    versionStatus: 'active',
    provenance: 'seed',
    createdAt: '2026-07-20T12:00:00.000Z',
  }
}

function catalogGroup(): CoachCatalogEntry[] {
  return ([1, 2, 3] as const).flatMap((variant) =>
    (['in_app', 'push', 'email'] as const).map((channel, channelIndex) => ({
      ...catalogEntry(),
      templateId: `00000000-0000-0000-0000-000000000${variant}${channelIndex + 1}1`,
      templateVersionId: `00000000-0000-0000-0000-000000000${variant}${channelIndex + 1}2`,
      templateKey: `focus.hydration.${channel}.pt-br.v${variant}`,
      variant,
      channel,
      title: channel === 'push' ? `Água ${variant}` : null,
      subject: channel === 'email' ? `Hidratação ${variant}` : null,
      body: `{{name}}, versão ${variant}: faltam {{water_remaining_ml}} ml.`,
    })),
  )
}

function assistedJson() {
  return JSON.stringify({
    variants: ([1, 2, 3] as const).map((variant) => ({
      variant,
      renditions: {
        in_app: {
          title: null,
          subject: null,
          body: `{{name}}, plano ${variant}: organize os {{water_remaining_ml}} ml restantes.`,
        },
        push: {
          title: `Água em foco ${variant}`,
          subject: null,
          body: `{{name}}, complete os {{water_remaining_ml}} ml do seu plano.`,
        },
        email: {
          title: null,
          subject: `Seu plano de hidratação ${variant}`,
          body: `Olá, {{name}}. Distribua os {{water_remaining_ml}} ml restantes no dia.`,
        },
      },
    })),
  })
}

function repository(): CoachCatalogRepository {
  const entry = catalogEntry()
  const activePackId = '00000000-0000-0000-0000-000000000500'
  return {
    listPacks: vi.fn(async () => [
      {
        id: activePackId,
        slug: 'bodyflow-active-test',
        label: 'BodyFlow active test',
        status: 'active' as const,
        parentPackId: null,
        effectiveAt: null,
        activatedAt: '2026-07-20T12:00:00.000Z',
        archivedAt: null,
        createdAt: '2026-07-20T12:00:00.000Z',
        updatedAt: '2026-07-20T12:00:00.000Z',
      },
      {
        id: PACK_ID,
        slug: 'bodyflow-actions-test',
        label: 'BodyFlow actions test',
        status: 'draft' as const,
        parentPackId: activePackId,
        effectiveAt: null,
        activatedAt: null,
        archivedAt: null,
        createdAt: '2026-07-20T12:00:00.000Z',
        updatedAt: '2026-07-20T12:00:00.000Z',
      },
    ]),
    listCatalog: vi.fn(async () => [entry]),
    listTemplateVersions: vi.fn(async () => []),
    getUsageSummary: vi.fn(async () => ({
      selected: 10,
      suppressed: 2,
      failed: 1,
      balancedFallback: 3,
    })),
    getPackEntries: vi.fn(async (packId) => [
      {
        ...entry,
        packId,
        packStatus: packId === PACK_ID ? ('draft' as const) : ('active' as const),
      },
    ]),
    reviseDraftEntries: vi.fn(async (input: CoachRevisionRequest) => ({
      outcome: 'revised' as const,
      packId: input.packId,
      revisionCount: input.revisions.length,
      revisions: input.revisions.map((revision) => ({
        templateId: revision.templateId,
        previousTemplateVersionId: revision.expectedTemplateVersionId,
        templateVersionId: '00000000-0000-0000-0000-000000000505',
        version: 2,
      })),
    })),
    reviseAssistedDraftEntries: vi.fn(async (input: CoachAssistedRevisionRequest) => ({
      outcome: 'revised' as const,
      packId: input.packId,
      revisionCount: input.revisions.length,
      revisions: input.revisions.map((revision) => ({
        templateId: revision.templateId,
        previousTemplateVersionId: revision.expectedTemplateVersionId,
        templateVersionId: '00000000-0000-0000-0000-000000000506',
        version: 2,
      })),
    })),
    cloneActivePack: vi.fn(async () => ({
      outcome: 'cloned' as const,
      packId: PACK_ID,
      parentPackId: '00000000-0000-0000-0000-000000000500',
      entryCount: 1080,
    })),
    validatePackStructure: vi.fn(async () => ({
      packId: PACK_ID,
      status: 'draft' as const,
      entryCount: 1,
      validEntryCount: 1,
      expectedEntryCount: 1,
      snapshotHash: snapshotHash([entry]),
      valid: true,
    })),
    schedulePack: vi.fn(async (input) => ({
      outcome: 'scheduled' as const,
      packId: input.packId,
      effectiveAt: input.effectiveAt,
      entryCount: 1080,
    })),
    activatePack: vi.fn(async (input) => ({
      outcome: 'activated' as const,
      packId: input.packId,
      previousPackId: null,
      entryCount: 1080,
      activatedAt: '2026-07-20T12:00:00.000Z',
    })),
    archivePack: vi.fn(async (input) => ({
      outcome: 'archived' as const,
      packId: input.packId,
      previousStatus: 'draft' as const,
      archivedAt: '2026-07-20T12:00:00.000Z',
    })),
    rollbackPack: vi.fn(async (input) => ({
      outcome: 'rolled_back' as const,
      packId: input.packId,
      replacedPackId: '00000000-0000-0000-0000-000000000599',
      entryCount: 1080,
      activatedAt: '2026-07-20T12:00:00.000Z',
    })),
  }
}

function dependencies(role: AdminRole, repo = repository()) {
  const order: string[] = []
  const context: CoachMessageServiceContext = {
    repository: repo,
    getOpenRouterCredential: vi.fn(async () => 'server-side-credential'),
    recordAssistedTelemetry: vi.fn(async () => undefined),
  }
  const deps: CoachMessageActionDependencies = {
    loadAuthenticatedAdmin: vi.fn(async () => {
      order.push('authenticated-role')
      return { id: ACTOR_ID, role }
    }),
    createServiceContext: vi.fn(() => {
      order.push('service-client')
      return context
    }),
    createAssistedProvider: vi.fn(() => ({
      complete: vi.fn(async () => {
        throw new Error('not used in authorization tests')
      }),
    })),
  }
  return { deps, context, repo, order }
}

describe('coach message admin actions', () => {
  it('loads the authenticated role before creating any service-role client', async () => {
    const { deps, repo, order } = dependencies('content_editor')

    await executeCoachMessageAction(
      {
        type: 'reviseDraft',
        input: {
          packId: PACK_ID,
          templateId: TEMPLATE_ID,
          expectedTemplateVersionId: VERSION_ID,
          title: null,
          subject: null,
          body: '{{name}}, complete os {{water_remaining_ml}} ml restantes.',
        },
      },
      deps,
    )

    expect(order).toEqual(['authenticated-role', 'service-client'])
    expect(repo.reviseDraftEntries).toHaveBeenCalledOnce()
  })

  it('returns copy-free aggregate usage to an authorized content editor', async () => {
    const { deps, repo } = dependencies('content_editor')

    const result = await executeCoachMessageAction({ type: 'getUsageSummary' }, deps)

    expect(result).toEqual({ selected: 10, suppressed: 2, failed: 1, balancedFallback: 3 })
    expect(repo.getUsageSummary).toHaveBeenCalledOnce()
  })

  it('does not create a service-role client for a forbidden role', async () => {
    const { deps } = dependencies('support')

    await expect(
      executeCoachMessageAction(
        {
          type: 'reviseDraft',
          input: {
            packId: PACK_ID,
            templateId: TEMPLATE_ID,
            expectedTemplateVersionId: VERSION_ID,
            title: null,
            subject: null,
            body: '{{name}}, complete os {{water_remaining_ml}} ml restantes.',
          },
        },
        deps,
      ),
    ).rejects.toThrow('Acesso negado')

    expect(deps.createServiceContext).not.toHaveBeenCalled()
  })

  it.each([
    'schedulePack',
    'activatePack',
    'archivePack',
    'rollbackPack',
  ] as const)('prevents content editors from executing %s', async (type) => {
    const { deps } = dependencies('content_editor')
    const input =
      type === 'schedulePack'
        ? { packId: PACK_ID, effectiveAt: '2026-08-20T12:00:00.000Z' }
        : { packId: PACK_ID }

    await expect(executeCoachMessageAction({ type, input } as never, deps)).rejects.toThrow(
      'Apenas master admin',
    )
    expect(deps.createServiceContext).not.toHaveBeenCalled()
  })

  it('allows a master admin to schedule an already validated pack', async () => {
    const { deps, repo } = dependencies('master_admin')

    const result = await executeCoachMessageAction(
      {
        type: 'schedulePack',
        input: { packId: PACK_ID, effectiveAt: '2026-08-20T12:00:00.000Z' },
      },
      deps,
    )

    expect(result).toMatchObject({ outcome: 'scheduled', packId: PACK_ID })
    expect(repo.schedulePack).toHaveBeenCalledWith({
      packId: PACK_ID,
      actorId: ACTOR_ID,
      effectiveAt: '2026-08-20T12:00:00.000Z',
      snapshotHash: snapshotHash([catalogEntry()]),
    })
  })

  it('reauthenticates every mutation instead of trusting a previous action', async () => {
    const { deps } = dependencies('master_admin')

    await executeCoachMessageAction({ type: 'activatePack', input: { packId: PACK_ID } }, deps)
    await executeCoachMessageAction({ type: 'archivePack', input: { packId: PACK_ID } }, deps)

    expect(deps.loadAuthenticatedAdmin).toHaveBeenCalledTimes(2)
    expect(deps.createServiceContext).toHaveBeenCalledTimes(2)
  })

  it('stores a validated assisted group as nine immutable drafts with copy-free telemetry', async () => {
    const repo = repository()
    vi.mocked(repo.getPackEntries).mockResolvedValue(catalogGroup())
    const { deps, context } = dependencies('content_editor', repo)
    deps.createAssistedProvider = vi.fn(() => ({
      complete: vi.fn(async () => ({
        content: assistedJson(),
        promptTokens: 700,
        completionTokens: 800,
        costUsd: 0.002,
        model: 'anthropic/claude-haiku-4.5',
        latencyMs: 450,
      })),
    }))

    await executeCoachMessageAction(
      {
        type: 'assistedRewrite',
        input: {
          packId: PACK_ID,
          personality: 'focus',
          context: 'hydration',
          locale: 'pt-BR',
        },
      },
      deps,
    )

    expect(repo.reviseAssistedDraftEntries).toHaveBeenCalledWith(
      expect.objectContaining({
        packId: PACK_ID,
        actorId: ACTOR_ID,
        groupKey: 'focus|hydration|pt-BR',
        model: 'anthropic/claude-haiku-4.5',
        promptTokens: 700,
        completionTokens: 800,
        revisions: expect.arrayContaining([expect.objectContaining({ body: expect.any(String) })]),
      }),
    )
    const revisionInput = vi.mocked(repo.reviseAssistedDraftEntries).mock.calls[0]?.[0]
    expect(revisionInput?.revisions).toHaveLength(9)

    expect(context.recordAssistedTelemetry).not.toHaveBeenCalled()
    const telemetry = JSON.stringify(
      vi.mocked(repo.reviseAssistedDraftEntries).mock.calls.map(([input]) => ({
        groupKey: input.groupKey,
        model: input.model,
        promptTokens: input.promptTokens,
        completionTokens: input.completionTokens,
        costUsd: input.costUsd,
        latencyMs: input.latencyMs,
      })),
    )
    expect(telemetry).not.toContain('plano 1')
    expect(telemetry).not.toContain('server-side-credential')
    expect(telemetry).not.toContain('water_remaining_ml')
  })

  it('sends only active approved copy to the provider and targets the current draft versions', async () => {
    const activePackId = '00000000-0000-0000-0000-000000000590'
    const activeRows = catalogGroup().map((row) => ({
      ...row,
      packId: activePackId,
      packSlug: 'bodyflow-active-source',
      packLabel: 'BodyFlow active source',
      packStatus: 'active' as const,
      versionStatus: 'active' as const,
    }))
    const draftRows = catalogGroup().map((row) => ({
      ...row,
      versionStatus: 'draft' as const,
      body: `${row.body} synthetic.patient@example.test`,
      templateVersionId: row.templateVersionId.replace(/2$/, '9'),
    }))
    const repo = repository()
    vi.mocked(repo.listPacks).mockResolvedValue([
      {
        id: activePackId,
        slug: 'bodyflow-active-source',
        label: 'BodyFlow active source',
        status: 'active',
        parentPackId: null,
        effectiveAt: null,
        activatedAt: '2026-07-20T12:00:00.000Z',
        archivedAt: null,
        createdAt: '2026-07-20T12:00:00.000Z',
        updatedAt: '2026-07-20T12:00:00.000Z',
      },
      {
        id: PACK_ID,
        slug: 'bodyflow-actions-test',
        label: 'BodyFlow actions test',
        status: 'draft',
        parentPackId: activePackId,
        effectiveAt: null,
        activatedAt: null,
        archivedAt: null,
        createdAt: '2026-07-20T12:00:00.000Z',
        updatedAt: '2026-07-20T12:00:00.000Z',
      },
    ])
    vi.mocked(repo.getPackEntries).mockImplementation(async (packId) =>
      packId === activePackId ? activeRows : draftRows,
    )
    const { deps } = dependencies('content_editor', repo)
    const complete = vi.fn(async () => ({
      content: assistedJson(),
      promptTokens: 700,
      completionTokens: 800,
      costUsd: 0.002,
      model: 'anthropic/claude-haiku-4.5',
      latencyMs: 450,
    }))
    deps.createAssistedProvider = vi.fn(() => ({ complete }))

    await executeCoachMessageAction(
      {
        type: 'assistedRewrite',
        input: {
          packId: PACK_ID,
          personality: 'focus',
          context: 'hydration',
          locale: 'pt-BR',
        },
      },
      deps,
    )

    expect(JSON.stringify(complete.mock.calls)).not.toContain('synthetic.patient@example.test')
    const revisions = vi.mocked(repo.reviseAssistedDraftEntries).mock.calls[0]?.[0].revisions ?? []
    expect(revisions).toHaveLength(9)
    expect(revisions.map((revision) => revision.expectedTemplateVersionId).sort()).toEqual(
      draftRows.map((row) => row.templateVersionId).sort(),
    )
  })

  it('records one copy-free failure event when atomic assisted storage fails', async () => {
    const repo = repository()
    vi.mocked(repo.getPackEntries).mockResolvedValue(catalogGroup())
    const { deps, context } = dependencies('content_editor', repo)
    deps.createAssistedProvider = vi.fn(() => ({
      complete: vi.fn(async () => ({
        content: assistedJson(),
        promptTokens: 700,
        completionTokens: 800,
        costUsd: 0.002,
        model: 'anthropic/claude-haiku-4.5',
        latencyMs: 450,
      })),
    }))
    vi.mocked(repo.reviseAssistedDraftEntries).mockRejectedValueOnce(
      new Error('atomic storage unavailable'),
    )

    await expect(
      executeCoachMessageAction(
        {
          type: 'assistedRewrite',
          input: {
            packId: PACK_ID,
            personality: 'focus',
            context: 'hydration',
            locale: 'pt-BR',
          },
        },
        deps,
      ),
    ).rejects.toThrow('atomic storage unavailable')

    expect(repo.reviseAssistedDraftEntries).toHaveBeenCalledOnce()
    expect(repo.reviseDraftEntries).not.toHaveBeenCalled()
    expect(context.recordAssistedTelemetry).toHaveBeenCalledOnce()
    expect(context.recordAssistedTelemetry).toHaveBeenCalledWith(
      expect.objectContaining({
        status: 'storage_failed',
        promptTokens: 700,
        completionTokens: 800,
      }),
    )
  })

  it('preserves provider usage metrics when generated JSON fails validation', async () => {
    const repo = repository()
    vi.mocked(repo.getPackEntries).mockResolvedValue(catalogGroup())
    const { deps, context } = dependencies('content_editor', repo)
    deps.createAssistedProvider = vi.fn(() => ({
      complete: vi.fn(async () => ({
        content: 'not-json',
        promptTokens: 321,
        completionTokens: 123,
        costUsd: 0.001,
        model: 'anthropic/claude-haiku-4.5',
        latencyMs: 222,
      })),
    }))

    await expect(
      executeCoachMessageAction(
        {
          type: 'assistedRewrite',
          input: {
            packId: PACK_ID,
            personality: 'focus',
            context: 'hydration',
            locale: 'pt-BR',
          },
        },
        deps,
      ),
    ).rejects.toThrow('valid JSON')

    expect(context.recordAssistedTelemetry).toHaveBeenCalledWith(
      expect.objectContaining({
        status: 'validation_failed',
        model: 'anthropic/claude-haiku-4.5',
        promptTokens: 321,
        completionTokens: 123,
        costUsd: 0.001,
        latencyMs: 222,
      }),
    )
    expect(repo.reviseAssistedDraftEntries).not.toHaveBeenCalled()
  })
})
