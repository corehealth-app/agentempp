import { createHash } from 'node:crypto'
import { describe, expect, it, vi } from 'vitest'
import {
  type CoachAssistedRevisionRequest,
  type CoachCatalogEntry,
  type CoachCatalogRepository,
  type CoachRevisionRequest,
  createCoachMessageAdminService,
} from './admin-service'

function catalogEntry(overrides: Partial<CoachCatalogEntry> = {}): CoachCatalogEntry {
  return {
    packId: '00000000-0000-0000-0000-000000000101',
    packSlug: 'bodyflow-test-draft',
    packLabel: 'BodyFlow test draft',
    packStatus: 'draft',
    templateId: '00000000-0000-0000-0000-000000000102',
    templateKey: 'focus.progress.in_app.pt-br.v1',
    personality: 'focus',
    context: 'progress',
    channel: 'in_app',
    locale: 'pt-BR',
    variant: 1,
    allowedVariables: ['name', 'kcal_remaining'],
    requiredVariables: ['name', 'kcal_remaining'],
    templateVersionId: '00000000-0000-0000-0000-000000000103',
    version: 1,
    title: null,
    subject: null,
    body: 'Oi {{name}}, faltam {{kcal_remaining}} kcal no seu plano de hoje.',
    versionStatus: 'active',
    provenance: 'seed',
    createdAt: '2026-07-20T12:00:00.000Z',
    ...overrides,
  }
}

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

function repository(entry: CoachCatalogEntry = catalogEntry()): CoachCatalogRepository {
  return {
    listPacks: vi.fn(async () => []),
    listCatalog: vi.fn(async () => [entry]),
    listTemplateVersions: vi.fn(async () => [
      {
        id: entry.templateVersionId,
        templateId: entry.templateId,
        version: entry.version,
        title: entry.title,
        subject: entry.subject,
        body: entry.body,
        status: entry.versionStatus,
        provenance: entry.provenance,
        approvedAt: null,
        archivedAt: null,
        createdAt: entry.createdAt,
      },
    ]),
    getUsageSummary: vi.fn(async () => ({
      selected: 10,
      suppressed: 2,
      failed: 1,
      balancedFallback: 3,
    })),
    getPackEntries: vi.fn(async () => [entry]),
    reviseDraftEntries: vi.fn(async (input: CoachRevisionRequest) => ({
      outcome: 'revised' as const,
      packId: input.packId,
      revisionCount: input.revisions.length,
      revisions: input.revisions.map((revision, index) => ({
        templateId: revision.templateId,
        previousTemplateVersionId: revision.expectedTemplateVersionId,
        templateVersionId: `00000000-0000-0000-0000-00000000020${index + 1}`,
        version: 2,
      })),
    })),
    reviseAssistedDraftEntries: vi.fn(async (input: CoachAssistedRevisionRequest) => ({
      outcome: 'revised' as const,
      packId: input.packId,
      revisionCount: input.revisions.length,
      revisions: input.revisions.map((revision, index) => ({
        templateId: revision.templateId,
        previousTemplateVersionId: revision.expectedTemplateVersionId,
        templateVersionId: `00000000-0000-0000-0000-00000000021${index + 1}`,
        version: 2,
      })),
    })),
    cloneActivePack: vi.fn(async () => ({
      outcome: 'cloned' as const,
      packId: '00000000-0000-0000-0000-000000000301',
      parentPackId: entry.packId,
      entryCount: 1080,
    })),
    validatePackStructure: vi.fn(async () => ({
      packId: entry.packId,
      status: entry.packStatus,
      entryCount: 1,
      validEntryCount: 1,
      expectedEntryCount: 1,
      snapshotHash: snapshotHash([entry]),
      valid: true,
    })),
    schedulePack: vi.fn(async () => ({
      outcome: 'scheduled' as const,
      packId: entry.packId,
      effectiveAt: '2026-08-20T12:00:00.000Z',
      entryCount: 1080,
    })),
    activatePack: vi.fn(async () => ({
      outcome: 'activated' as const,
      packId: entry.packId,
      previousPackId: null,
      entryCount: 1080,
      activatedAt: '2026-07-20T12:00:00.000Z',
    })),
    archivePack: vi.fn(async () => ({
      outcome: 'archived' as const,
      packId: entry.packId,
      previousStatus: 'draft' as const,
      archivedAt: '2026-07-20T12:00:00.000Z',
    })),
    rollbackPack: vi.fn(async () => ({
      outcome: 'rolled_back' as const,
      packId: entry.packId,
      replacedPackId: '00000000-0000-0000-0000-000000000999',
      entryCount: 1080,
      activatedAt: '2026-07-20T12:00:00.000Z',
    })),
  }
}

describe('coach message admin service', () => {
  it('creates an immutable human draft revision from authoritative template metadata', async () => {
    const source = catalogEntry()
    const repo = repository(source)
    const service = createCoachMessageAdminService(repo)

    const result = await service.reviseDraft({
      packId: source.packId,
      actorId: '00000000-0000-0000-0000-000000000104',
      templateId: source.templateId,
      expectedTemplateVersionId: source.templateVersionId,
      title: null,
      subject: null,
      body: 'Oi {{name}}, ainda faltam {{kcal_remaining}} kcal no plano de hoje.',
    })

    expect(result.outcome).toBe('revised')
    expect(repo.reviseDraftEntries).toHaveBeenCalledWith({
      packId: source.packId,
      actorId: '00000000-0000-0000-0000-000000000104',
      provenance: 'human',
      revisions: [
        {
          templateId: source.templateId,
          expectedTemplateVersionId: source.templateVersionId,
          title: null,
          subject: null,
          body: 'Oi {{name}}, ainda faltam {{kcal_remaining}} kcal no plano de hoje.',
        },
      ],
    })
    expect(source.body).toBe('Oi {{name}}, faltam {{kcal_remaining}} kcal no seu plano de hoje.')
  })

  it('rejects unsafe copy before the repository can persist a revision', async () => {
    const source = catalogEntry()
    const repo = repository(source)
    const service = createCoachMessageAdminService(repo)

    await expect(
      service.reviseDraft({
        packId: source.packId,
        actorId: '00000000-0000-0000-0000-000000000104',
        templateId: source.templateId,
        expectedTemplateVersionId: source.templateVersionId,
        title: null,
        subject: null,
        body: 'Sem desculpas, {{name}}. Faltam {{kcal_remaining}} kcal.',
      }),
    ).rejects.toThrow('unsafe_language')

    expect(repo.reviseDraftEntries).not.toHaveBeenCalled()
  })

  it('renders previews with fixed synthetic values only', async () => {
    const source = catalogEntry()
    const repo = repository(source)
    const service = createCoachMessageAdminService(repo)

    const preview = await service.previewDraft({
      packId: source.packId,
      templateId: source.templateId,
      expectedTemplateVersionId: source.templateVersionId,
      title: null,
      subject: null,
      body: 'Olá {{name}}. Faltam {{kcal_remaining}} kcal no exemplo.',
    })

    expect(preview).toEqual({
      synthetic: true,
      title: null,
      subject: null,
      body: 'Olá Ana. Faltam 380 kcal no exemplo.',
    })
    expect(JSON.stringify(preview)).not.toContain('user')
    expect(JSON.stringify(preview)).not.toContain('patient')
  })

  it('fails closed when the draft entry changed after the editor loaded it', async () => {
    const source = catalogEntry()
    const repo = repository(source)
    const service = createCoachMessageAdminService(repo)

    await expect(
      service.reviseDraft({
        packId: source.packId,
        actorId: '00000000-0000-0000-0000-000000000104',
        templateId: source.templateId,
        expectedTemplateVersionId: '00000000-0000-0000-0000-000000000999',
        title: null,
        subject: null,
        body: source.body,
      }),
    ).rejects.toThrow('changed since it was loaded')

    expect(repo.reviseDraftEntries).not.toHaveBeenCalled()
  })

  it('combines database coverage with copy lint and variant distinctness', async () => {
    const rows = [
      catalogEntry({ variant: 1, body: 'Variante um {{name}}: {{kcal_remaining}} kcal.' }),
      catalogEntry({
        templateId: '00000000-0000-0000-0000-000000000112',
        templateVersionId: '00000000-0000-0000-0000-000000000113',
        variant: 2,
        body: 'Variante dois {{name}}: {{kcal_remaining}} kcal.',
      }),
      catalogEntry({
        templateId: '00000000-0000-0000-0000-000000000122',
        templateVersionId: '00000000-0000-0000-0000-000000000123',
        variant: 3,
        body: 'Variante dois {{name}}: {{kcal_remaining}} kcal.',
      }),
    ]
    const repo = repository(rows[0])
    vi.mocked(repo.getPackEntries).mockResolvedValue(rows)
    const service = createCoachMessageAdminService(repo)

    const validation = await service.validatePack(rows[0].packId)

    expect(validation.valid).toBe(false)
    expect(validation.issues).toContainEqual(
      expect.objectContaining({ code: 'duplicate_variant', variant: 3 }),
    )
  })

  it('blocks scheduling when full copy validation finds duplicate variants', async () => {
    const first = catalogEntry({ body: 'Mesmo texto {{name}}: {{kcal_remaining}} kcal.' })
    const second = catalogEntry({
      templateId: '00000000-0000-0000-0000-000000000132',
      templateVersionId: '00000000-0000-0000-0000-000000000133',
      variant: 2,
      body: first.body,
    })
    const repo = repository(first)
    vi.mocked(repo.getPackEntries).mockResolvedValue([first, second])
    vi.mocked(repo.validatePackStructure).mockResolvedValue({
      packId: first.packId,
      status: 'draft',
      entryCount: 2,
      validEntryCount: 2,
      expectedEntryCount: 2,
      snapshotHash: snapshotHash([first, second]),
      valid: true,
    })
    const service = createCoachMessageAdminService(repo)

    await expect(
      service.schedulePack({
        packId: first.packId,
        actorId: '00000000-0000-0000-0000-000000000104',
        effectiveAt: '2026-08-20T12:00:00.000Z',
      }),
    ).rejects.toThrow('full catalog validation')

    expect(repo.schedulePack).not.toHaveBeenCalled()
  })

  it('blocks lifecycle changes when the loaded catalog differs from the database snapshot', async () => {
    const source = catalogEntry()
    const repo = repository(source)
    vi.mocked(repo.validatePackStructure).mockResolvedValue({
      packId: source.packId,
      status: 'draft',
      entryCount: 1,
      validEntryCount: 1,
      expectedEntryCount: 1,
      snapshotHash: 'f'.repeat(64),
      valid: true,
    })
    const service = createCoachMessageAdminService(repo)

    const validation = await service.validatePack(source.packId)

    expect(validation.valid).toBe(false)
    expect(validation.issues).toContainEqual(expect.objectContaining({ code: 'snapshot_mismatch' }))
    await expect(
      service.activatePack({
        packId: source.packId,
        actorId: '00000000-0000-0000-0000-000000000104',
      }),
    ).rejects.toThrow('full catalog validation')
    expect(repo.activatePack).not.toHaveBeenCalled()
  })

  it('passes the validated snapshot to schedule and activation RPCs', async () => {
    const source = catalogEntry()
    const repo = repository(source)
    const expectedSnapshot = snapshotHash([source])
    const service = createCoachMessageAdminService(repo)

    await service.schedulePack({
      packId: source.packId,
      actorId: '00000000-0000-0000-0000-000000000104',
      effectiveAt: '2026-08-20T12:00:00.000Z',
    })
    await service.activatePack({
      packId: source.packId,
      actorId: '00000000-0000-0000-0000-000000000104',
    })

    expect(repo.schedulePack).toHaveBeenCalledWith({
      packId: source.packId,
      actorId: '00000000-0000-0000-0000-000000000104',
      effectiveAt: '2026-08-20T12:00:00.000Z',
      snapshotHash: expectedSnapshot,
    })
    expect(repo.activatePack).toHaveBeenCalledWith({
      packId: source.packId,
      actorId: '00000000-0000-0000-0000-000000000104',
      snapshotHash: expectedSnapshot,
    })
  })

  it('exposes safe version history and aggregate usage for the operational UI', async () => {
    const source = catalogEntry()
    const repo = repository(source)
    const service = createCoachMessageAdminService(repo)

    const [versions, usage] = await Promise.all([
      service.listTemplateVersions(source.templateId),
      service.getUsageSummary(),
    ])

    expect(versions).toEqual([
      expect.objectContaining({ id: source.templateVersionId, version: 1 }),
    ])
    expect(usage).toEqual({ selected: 10, suppressed: 2, failed: 1, balancedFallback: 3 })
    expect(repo.listTemplateVersions).toHaveBeenCalledWith(source.templateId)
    expect(repo.getUsageSummary).toHaveBeenCalledOnce()
  })
})
