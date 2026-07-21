import type {
  CoachMessageChannel,
  CoachMessageContext,
  CoachMessageLocale,
  CoachPersonality,
} from '@mpp/core'
import {
  type AdminRole,
  CONTENT_ADMIN_ROLES,
  hasAdminRole,
  MASTER_ADMIN_ROLES,
} from '@/lib/admin-rbac'
import {
  type CoachCatalogFilters,
  type CoachCatalogRepository,
  createCoachMessageAdminService,
} from '@/lib/coach-messages/admin-service'
import {
  ASSISTED_REWRITE_MODEL,
  type AssistedRewriteProvider,
  AssistedRewriteValidationError,
  type CoachCatalogVariant,
  generateAssistedCoachRewrite,
} from '@/lib/coach-messages/assisted-rewrite'

export interface CoachAssistedTelemetry {
  actorId: string
  packId: string
  groupKey: string
  status: 'credential_missing' | 'provider_failed' | 'validation_failed' | 'storage_failed'
  model: string
  promptTokens: number
  completionTokens: number
  costUsd: number | null
  latencyMs: number
}

export interface CoachMessageServiceContext {
  repository: CoachCatalogRepository
  getOpenRouterCredential(): Promise<string | null>
  recordAssistedTelemetry(input: CoachAssistedTelemetry): Promise<void>
}

export interface CoachMessageActionDependencies {
  loadAuthenticatedAdmin(): Promise<{ id: string; role: AdminRole }>
  createServiceContext(): CoachMessageServiceContext
  createAssistedProvider(apiKey: string): AssistedRewriteProvider
}

export type CoachMessageAction =
  | { type: 'listPacks' }
  | { type: 'listCatalog'; input: CoachCatalogFilters }
  | { type: 'listTemplateVersions'; input: { templateId: string } }
  | { type: 'getUsageSummary' }
  | {
      type: 'previewDraft'
      input: {
        packId: string
        templateId: string
        expectedTemplateVersionId: string
        title: string | null
        subject: string | null
        body: string
      }
    }
  | {
      type: 'reviseDraft'
      input: {
        packId: string
        templateId: string
        expectedTemplateVersionId: string
        title: string | null
        subject: string | null
        body: string
      }
    }
  | { type: 'cloneActivePack'; input: { slug: string; label: string } }
  | { type: 'validatePack'; input: { packId: string } }
  | { type: 'schedulePack'; input: { packId: string; effectiveAt: string } }
  | { type: 'activatePack'; input: { packId: string } }
  | { type: 'archivePack'; input: { packId: string } }
  | { type: 'rollbackPack'; input: { packId: string } }
  | {
      type: 'assistedRewrite'
      input: {
        packId: string
        personality: CoachPersonality
        context: CoachMessageContext
        locale: CoachMessageLocale
      }
    }

const MASTER_ACTIONS = new Set<CoachMessageAction['type']>([
  'schedulePack',
  'activatePack',
  'archivePack',
  'rollbackPack',
])

function requireActionRole(role: AdminRole, action: CoachMessageAction['type']): void {
  if (!hasAdminRole(role, CONTENT_ADMIN_ROLES)) throw new Error('Acesso negado')
  if (MASTER_ACTIONS.has(action) && !hasAdminRole(role, MASTER_ADMIN_ROLES)) {
    throw new Error('Apenas master admin pode alterar o ciclo de vida do catálogo')
  }
}

function groupRows(
  rows: Awaited<ReturnType<CoachCatalogRepository['getPackEntries']>>,
  input: Extract<CoachMessageAction, { type: 'assistedRewrite' }>['input'],
): [CoachCatalogVariant, CoachCatalogVariant, CoachCatalogVariant] {
  const selected = rows.filter(
    (row) =>
      row.personality === input.personality &&
      row.context === input.context &&
      row.locale === input.locale,
  )
  if (selected.length !== 9) {
    throw new Error('Assisted rewrite requires one complete three-variant catalog group')
  }

  const variants = [1, 2, 3].map((variantNumber) => {
    const variantRows = selected.filter((row) => row.variant === variantNumber)
    if (variantRows.length !== 3) {
      throw new Error('Assisted rewrite requires one complete three-variant catalog group')
    }
    const rendition = (channel: CoachMessageChannel) => {
      const row = variantRows.find((candidate) => candidate.channel === channel)
      if (!row) throw new Error('Assisted rewrite catalog group is missing a channel')
      return {
        templateId: row.templateId,
        templateVersionId: row.templateVersionId,
        channel: row.channel,
        title: row.title,
        subject: row.subject,
        body: row.body,
        allowedVariables: row.allowedVariables,
        requiredVariables: row.requiredVariables,
      }
    }
    return {
      variant: variantNumber as 1 | 2 | 3,
      personality: input.personality,
      context: input.context,
      locale: input.locale,
      renditions: {
        in_app: rendition('in_app'),
        push: rendition('push'),
        email: rendition('email'),
      },
    }
  })
  return variants as [CoachCatalogVariant, CoachCatalogVariant, CoachCatalogVariant]
}

async function recordFailureTelemetry(
  context: CoachMessageServiceContext,
  telemetry: CoachAssistedTelemetry,
): Promise<void> {
  try {
    await context.recordAssistedTelemetry(telemetry)
  } catch {
    console.error('[coach-catalog] assisted failure telemetry unavailable')
  }
}

async function executeAssistedRewrite(
  input: Extract<CoachMessageAction, { type: 'assistedRewrite' }>['input'],
  actorId: string,
  context: CoachMessageServiceContext,
  createProvider: CoachMessageActionDependencies['createAssistedProvider'],
) {
  const groupKey = [input.personality, input.context, input.locale].join('|')
  const packs = await context.repository.listPacks()
  const targetPack = packs.find((pack) => pack.id === input.packId)
  const activePack = packs.find((pack) => pack.status === 'active')
  if (!targetPack || targetPack.status !== 'draft') {
    throw new Error('Assisted rewrite can only target a draft content pack')
  }
  if (!activePack) throw new Error('Assisted rewrite requires an active approved source pack')

  const [approvedRows, targetRows] = await Promise.all([
    context.repository.getPackEntries(activePack.id),
    context.repository.getPackEntries(targetPack.id),
  ])
  const sourceVersions = groupRows(approvedRows, { ...input, packId: activePack.id })
  const targetVersions = groupRows(targetRows, input)
  if (
    sourceVersions.some((variant) =>
      (['in_app', 'push', 'email'] as const).some(
        (channel) =>
          approvedRows.find(
            (row) =>
              row.templateId === variant.renditions[channel].templateId &&
              row.templateVersionId === variant.renditions[channel].templateVersionId,
          )?.versionStatus !== 'active',
      ),
    )
  ) {
    throw new Error('Assisted rewrite source copy must be active and approved')
  }

  const credential = await context.getOpenRouterCredential()
  if (!credential) {
    await recordFailureTelemetry(context, {
      actorId,
      packId: input.packId,
      groupKey,
      status: 'credential_missing',
      model: ASSISTED_REWRITE_MODEL,
      promptTokens: 0,
      completionTokens: 0,
      costUsd: null,
      latencyMs: 0,
    })
    throw new Error('OpenRouter não está configurado para a reescrita assistida')
  }

  const startedAt = Date.now()
  let rewrite: Awaited<ReturnType<typeof generateAssistedCoachRewrite>>
  try {
    rewrite = await generateAssistedCoachRewrite(
      { ...input, sourceVersions },
      createProvider(credential),
    )
  } catch (error) {
    const validationTelemetry =
      error instanceof AssistedRewriteValidationError ? error.telemetry : null
    await recordFailureTelemetry(context, {
      actorId,
      packId: input.packId,
      groupKey,
      status: validationTelemetry ? 'validation_failed' : 'provider_failed',
      model: validationTelemetry?.model ?? ASSISTED_REWRITE_MODEL,
      promptTokens: validationTelemetry?.promptTokens ?? 0,
      completionTokens: validationTelemetry?.completionTokens ?? 0,
      costUsd: validationTelemetry?.costUsd ?? null,
      latencyMs: validationTelemetry?.latencyMs ?? Math.max(0, Date.now() - startedAt),
    })
    throw error
  }

  const telemetry = {
    actorId,
    packId: input.packId,
    groupKey,
    model: rewrite.model,
    promptTokens: rewrite.promptTokens,
    completionTokens: rewrite.completionTokens,
    costUsd: rewrite.costUsd,
    latencyMs: rewrite.latencyMs,
  }
  const targetByTemplate = new Map(
    targetVersions.flatMap((targetVariant) =>
      (['in_app', 'push', 'email'] as const).map((channel) => {
        const rendition = targetVariant.renditions[channel]
        return [rendition.templateId, rendition] as const
      }),
    ),
  )
  const revisions = rewrite.variants.flatMap((variant) =>
    (['in_app', 'push', 'email'] as const).map((channel) => {
      const rendition = variant.renditions[channel]
      const targetVersion = targetByTemplate.get(rendition.templateId)
      if (!targetVersion) throw new Error('Assisted rewrite target group changed unexpectedly')
      return {
        templateId: rendition.templateId,
        expectedTemplateVersionId: targetVersion.templateVersionId,
        title: rendition.title,
        subject: rendition.subject,
        body: rendition.body,
      }
    }),
  )

  const service = createCoachMessageAdminService(context.repository)
  try {
    const result = await service.reviseAssistedDraftGroup({
      packId: input.packId,
      actorId,
      revisions,
      groupKey,
      model: rewrite.model,
      promptTokens: rewrite.promptTokens,
      completionTokens: rewrite.completionTokens,
      costUsd: rewrite.costUsd,
      latencyMs: rewrite.latencyMs,
    })
    return { rewrite, revision: result }
  } catch (error) {
    await recordFailureTelemetry(context, { ...telemetry, status: 'storage_failed' })
    throw error
  }
}

export async function executeCoachMessageAction(
  action: CoachMessageAction,
  dependencies: CoachMessageActionDependencies,
): Promise<unknown> {
  const admin = await dependencies.loadAuthenticatedAdmin()
  requireActionRole(admin.role, action.type)

  const context = dependencies.createServiceContext()
  const service = createCoachMessageAdminService(context.repository)

  switch (action.type) {
    case 'listPacks':
      return service.listPacks()
    case 'listCatalog':
      return service.listCatalog(action.input)
    case 'listTemplateVersions':
      return service.listTemplateVersions(action.input.templateId)
    case 'getUsageSummary':
      return service.getUsageSummary()
    case 'previewDraft':
      return service.previewDraft(action.input)
    case 'reviseDraft':
      return service.reviseDraft({ ...action.input, actorId: admin.id })
    case 'cloneActivePack':
      return service.cloneActivePack({ ...action.input, actorId: admin.id })
    case 'validatePack':
      return service.validatePack(action.input.packId)
    case 'schedulePack':
      return service.schedulePack({ ...action.input, actorId: admin.id })
    case 'activatePack':
      return service.activatePack({ ...action.input, actorId: admin.id })
    case 'archivePack':
      return service.archivePack({ ...action.input, actorId: admin.id })
    case 'rollbackPack':
      return service.rollbackPack({ ...action.input, actorId: admin.id })
    case 'assistedRewrite':
      return executeAssistedRewrite(
        action.input,
        admin.id,
        context,
        dependencies.createAssistedProvider,
      )
  }
}
