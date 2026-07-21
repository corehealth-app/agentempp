import { createHash } from 'node:crypto'
import {
  type CoachMessageChannel,
  type CoachMessageContext,
  type CoachMessageLocale,
  type CoachPersonality,
  type CoachTemplateLintIssue,
  coachMessageChannelSchema,
  coachMessageContextSchema,
  coachMessageLocaleSchema,
  coachPersonalitySchema,
  lintCoachTemplate,
  renderCoachTemplate,
} from '@mpp/core'
import type { Database } from '@mpp/db'
import type { SupabaseClient } from '@supabase/supabase-js'
import { z } from 'zod'

export type CoachPackStatus = 'draft' | 'scheduled' | 'active' | 'archived'
export type CoachVersionStatus = 'draft' | 'active' | 'archived'
export type CoachVersionProvenance = 'seed' | 'human' | 'assisted_draft'

export interface CoachContentPackSummary {
  id: string
  slug: string
  label: string
  status: CoachPackStatus
  parentPackId: string | null
  effectiveAt: string | null
  activatedAt: string | null
  archivedAt: string | null
  createdAt: string
  updatedAt: string
}

export interface CoachCatalogEntry {
  packId: string
  packSlug: string
  packLabel: string
  packStatus: CoachPackStatus
  templateId: string
  templateKey: string
  personality: CoachPersonality
  context: CoachMessageContext
  channel: CoachMessageChannel
  locale: CoachMessageLocale
  variant: 1 | 2 | 3
  allowedVariables: string[]
  requiredVariables: string[]
  templateVersionId: string
  version: number
  title: string | null
  subject: string | null
  body: string
  versionStatus: CoachVersionStatus
  provenance: CoachVersionProvenance
  createdAt: string
}

export interface CoachCatalogFilters {
  packId: string
  personality?: CoachPersonality
  context?: CoachMessageContext
  channel?: CoachMessageChannel
  locale?: CoachMessageLocale
  variant?: 1 | 2 | 3
}

export interface CoachTemplateVersionSummary {
  id: string
  templateId: string
  version: number
  title: string | null
  subject: string | null
  body: string
  status: CoachVersionStatus
  provenance: CoachVersionProvenance
  approvedAt: string | null
  archivedAt: string | null
  createdAt: string
}

export interface CoachUsageSummary {
  selected: number
  suppressed: number
  failed: number
  balancedFallback: number
}

export interface CoachDraftRevision {
  templateId: string
  expectedTemplateVersionId: string
  title: string | null
  subject: string | null
  body: string
}

export interface CoachRevisionRequest {
  packId: string
  actorId: string
  provenance: Extract<CoachVersionProvenance, 'human' | 'assisted_draft'>
  revisions: CoachDraftRevision[]
}

export interface CoachAssistedRevisionRequest {
  packId: string
  actorId: string
  revisions: CoachDraftRevision[]
  groupKey: string
  model: string
  promptTokens: number
  completionTokens: number
  costUsd: number | null
  latencyMs: number
}

export interface CoachRevisionResult {
  outcome: 'revised'
  packId: string
  revisionCount: number
  revisions: Array<{
    templateId: string
    previousTemplateVersionId: string
    templateVersionId: string
    version: number
  }>
}

export interface CoachPackStructureValidation {
  packId: string
  status: CoachPackStatus
  entryCount: number
  validEntryCount: number
  expectedEntryCount: number
  snapshotHash: string
  valid: boolean
}

export interface CoachCatalogValidationIssue {
  code:
    | CoachTemplateLintIssue['code']
    | 'duplicate_variant'
    | 'repository_count_mismatch'
    | 'snapshot_mismatch'
  templateId?: string
  templateKey?: string
  variant?: 1 | 2 | 3
  field?: CoachTemplateLintIssue['field']
  message: string
}

export interface CoachCatalogValidationResult extends CoachPackStructureValidation {
  issues: CoachCatalogValidationIssue[]
}

export interface CoachCatalogRepository {
  listPacks(): Promise<CoachContentPackSummary[]>
  listCatalog(filters: CoachCatalogFilters): Promise<CoachCatalogEntry[]>
  listTemplateVersions(templateId: string): Promise<CoachTemplateVersionSummary[]>
  getUsageSummary(): Promise<CoachUsageSummary>
  getPackEntries(packId: string, templateIds?: readonly string[]): Promise<CoachCatalogEntry[]>
  reviseDraftEntries(input: CoachRevisionRequest): Promise<CoachRevisionResult>
  reviseAssistedDraftEntries(input: CoachAssistedRevisionRequest): Promise<CoachRevisionResult>
  cloneActivePack(input: { slug: string; label: string; actorId: string }): Promise<{
    outcome: 'cloned'
    packId: string
    parentPackId: string
    entryCount: number
  }>
  validatePackStructure(packId: string): Promise<CoachPackStructureValidation>
  schedulePack(input: {
    packId: string
    actorId: string
    effectiveAt: string
    snapshotHash: string
  }): Promise<{
    outcome: 'scheduled'
    packId: string
    effectiveAt: string
    entryCount: number
  }>
  activatePack(input: { packId: string; actorId: string; snapshotHash: string }): Promise<{
    outcome: 'activated' | 'already_active'
    packId: string
    previousPackId: string | null
    entryCount: number
    activatedAt: string
  }>
  archivePack(input: { packId: string; actorId: string }): Promise<{
    outcome: 'archived'
    packId: string
    previousStatus: CoachPackStatus
    archivedAt: string
  }>
  rollbackPack(input: { packId: string; actorId: string }): Promise<{
    outcome: 'rolled_back'
    packId: string
    replacedPackId: string
    entryCount: number
    activatedAt: string
  }>
}

const idSchema = z.string().uuid()
const revisionCopySchema = z.object({
  title: z.string().min(1).max(60).nullable(),
  subject: z.string().min(1).max(120).nullable(),
  body: z.string().min(1).max(4_000),
})

const SYNTHETIC_VARIABLES: Readonly<Record<CoachMessageLocale, Record<string, string | number>>> = {
  'pt-BR': {
    name: 'Ana',
    meal: 'almoço',
    protein_remaining_g: 42,
    kcal_remaining: 380,
    block_progress_percent: 64,
    water_remaining_ml: 750,
    supplement_name: 'creatina',
    medication_name: 'medicação programada',
    next_reevaluation_date: '15/09/2026',
    trial_days_remaining: 5,
  },
  'en-US': {
    name: 'Ana',
    meal: 'lunch',
    protein_remaining_g: 42,
    kcal_remaining: 380,
    block_progress_percent: 64,
    water_remaining_ml: 750,
    supplement_name: 'creatine',
    medication_name: 'scheduled medication',
    next_reevaluation_date: '09/15/2026',
    trial_days_remaining: 5,
  },
}

function copyLintInput(
  entry: CoachCatalogEntry,
  copy: { title: string | null; subject: string | null; body: string },
) {
  return {
    context: entry.context,
    channel: entry.channel,
    locale: entry.locale,
    title: copy.title,
    subject: copy.subject,
    body: copy.body,
    allowedVariables: entry.allowedVariables,
    requiredVariables: entry.requiredVariables,
  }
}

function assertValidCopy(
  entry: CoachCatalogEntry,
  copy: { title: string | null; subject: string | null; body: string },
): void {
  revisionCopySchema.parse(copy)
  const issues = lintCoachTemplate(copyLintInput(entry, copy))
  if (issues.length > 0) {
    throw new Error(
      `Coach draft failed lint (${issues.map((issue) => issue.code).join(',')}): ${issues[0]?.message}`,
    )
  }
}

function normalizeCopy(entry: CoachCatalogEntry): string {
  return [entry.title ?? '', entry.subject ?? '', entry.body]
    .join('\n')
    .normalize('NFKC')
    .toLocaleLowerCase(entry.locale)
    .replace(/\s+/g, ' ')
    .trim()
}

function catalogSnapshotHash(entries: readonly CoachCatalogEntry[]): string {
  const snapshot = [...entries]
    .sort((left, right) => left.templateId.localeCompare(right.templateId))
    .map((entry) => `${entry.templateId}:${entry.templateVersionId}`)
    .join(',')
  return createHash('sha256').update(snapshot, 'utf8').digest('hex')
}

async function authoritativeEntries(
  repository: CoachCatalogRepository,
  packId: string,
  revisions: readonly CoachDraftRevision[],
): Promise<Map<string, CoachCatalogEntry>> {
  idSchema.parse(packId)
  if (revisions.length < 1 || revisions.length > 9) {
    throw new Error('A coach draft operation requires between one and nine revisions')
  }

  const templateIds = revisions.map((revision) => idSchema.parse(revision.templateId))
  if (new Set(templateIds).size !== templateIds.length) {
    throw new Error('A coach draft operation cannot revise the same template twice')
  }

  const rows = await repository.getPackEntries(packId, templateIds)
  const byTemplate = new Map(rows.map((row) => [row.templateId, row]))
  if (byTemplate.size !== revisions.length) {
    throw new Error('One or more coach draft templates were not found')
  }
  return byTemplate
}

async function validateCatalogPack(
  repository: CoachCatalogRepository,
  packId: string,
): Promise<CoachCatalogValidationResult> {
  idSchema.parse(packId)
  const [structure, entries] = await Promise.all([
    repository.validatePackStructure(packId),
    repository.getPackEntries(packId),
  ])
  const issues: CoachCatalogValidationIssue[] = []

  if (entries.length !== structure.entryCount) {
    issues.push({
      code: 'repository_count_mismatch',
      message: `Catalog returned ${entries.length} rows for ${structure.entryCount} pack entries`,
    })
  }

  if (catalogSnapshotHash(entries) !== structure.snapshotHash) {
    issues.push({
      code: 'snapshot_mismatch',
      message: 'Catalog entries changed while the validated snapshot was being loaded',
    })
  }

  const normalizedByGroup = new Map<string, Map<string, CoachCatalogEntry>>()
  for (const entry of entries) {
    for (const issue of lintCoachTemplate(
      copyLintInput(entry, {
        title: entry.title,
        subject: entry.subject,
        body: entry.body,
      }),
    )) {
      issues.push({
        code: issue.code,
        templateId: entry.templateId,
        templateKey: entry.templateKey,
        variant: entry.variant,
        field: issue.field,
        message: issue.message,
      })
    }

    const groupKey = [entry.personality, entry.context, entry.channel, entry.locale].join('|')
    const normalized = normalizeCopy(entry)
    const group = normalizedByGroup.get(groupKey) ?? new Map<string, CoachCatalogEntry>()
    const duplicate = group.get(normalized)
    if (duplicate) {
      issues.push({
        code: 'duplicate_variant',
        templateId: entry.templateId,
        templateKey: entry.templateKey,
        variant: entry.variant,
        message: `Variant ${entry.variant} duplicates variant ${duplicate.variant}`,
      })
    } else {
      group.set(normalized, entry)
    }
    normalizedByGroup.set(groupKey, group)
  }

  return {
    ...structure,
    valid: structure.valid && issues.length === 0,
    issues,
  }
}

export function createCoachMessageAdminService(repository: CoachCatalogRepository) {
  async function validateDraftGroup(input: CoachRevisionRequest): Promise<void> {
    idSchema.parse(input.actorId)
    if (input.provenance !== 'human' && input.provenance !== 'assisted_draft') {
      throw new Error('Unsupported coach draft provenance')
    }

    const entries = await authoritativeEntries(repository, input.packId, input.revisions)
    for (const revision of input.revisions) {
      idSchema.parse(revision.expectedTemplateVersionId)
      const entry = entries.get(revision.templateId)
      if (!entry) throw new Error('Coach draft template was not found')
      if (entry.packStatus !== 'draft') {
        throw new Error('Only a draft coach content pack can be revised')
      }
      if (entry.templateVersionId !== revision.expectedTemplateVersionId) {
        throw new Error('Coach draft entry changed since it was loaded')
      }
      assertValidCopy(entry, revision)
    }
  }

  async function reviseDraftGroup(input: CoachRevisionRequest): Promise<CoachRevisionResult> {
    await validateDraftGroup(input)
    return repository.reviseDraftEntries({
      ...input,
      revisions: input.revisions.map((revision) => ({ ...revision })),
    })
  }

  return {
    listPacks: () => repository.listPacks(),

    async listCatalog(filters: CoachCatalogFilters) {
      idSchema.parse(filters.packId)
      if (filters.personality) coachPersonalitySchema.parse(filters.personality)
      if (filters.context) coachMessageContextSchema.parse(filters.context)
      if (filters.channel) coachMessageChannelSchema.parse(filters.channel)
      if (filters.locale) coachMessageLocaleSchema.parse(filters.locale)
      if (filters.variant !== undefined && ![1, 2, 3].includes(filters.variant)) {
        throw new Error('Coach message variant must be 1, 2, or 3')
      }
      return repository.listCatalog(filters)
    },

    async listTemplateVersions(templateId: string) {
      idSchema.parse(templateId)
      return repository.listTemplateVersions(templateId)
    },

    getUsageSummary: () => repository.getUsageSummary(),

    async reviseDraft(input: {
      packId: string
      actorId: string
      templateId: string
      expectedTemplateVersionId: string
      title: string | null
      subject: string | null
      body: string
    }) {
      return reviseDraftGroup({
        packId: input.packId,
        actorId: input.actorId,
        provenance: 'human',
        revisions: [
          {
            templateId: input.templateId,
            expectedTemplateVersionId: input.expectedTemplateVersionId,
            title: input.title,
            subject: input.subject,
            body: input.body,
          },
        ],
      })
    },

    reviseDraftGroup,

    async reviseAssistedDraftGroup(input: CoachAssistedRevisionRequest) {
      await validateDraftGroup({
        packId: input.packId,
        actorId: input.actorId,
        provenance: 'assisted_draft',
        revisions: input.revisions,
      })
      return repository.reviseAssistedDraftEntries({
        ...input,
        revisions: input.revisions.map((revision) => ({ ...revision })),
      })
    },

    async previewDraft(input: {
      packId: string
      templateId: string
      expectedTemplateVersionId: string
      title: string | null
      subject: string | null
      body: string
    }) {
      const revision: CoachDraftRevision = {
        templateId: input.templateId,
        expectedTemplateVersionId: input.expectedTemplateVersionId,
        title: input.title,
        subject: input.subject,
        body: input.body,
      }
      const entries = await authoritativeEntries(repository, input.packId, [revision])
      const entry = entries.get(input.templateId)
      if (!entry) throw new Error('Coach template was not found for preview')
      if (entry.templateVersionId !== input.expectedTemplateVersionId) {
        throw new Error('Coach draft entry changed since it was loaded')
      }
      assertValidCopy(entry, revision)

      const available = SYNTHETIC_VARIABLES[entry.locale]
      const variables = Object.fromEntries(
        entry.allowedVariables.map((name) => {
          const value = available[name]
          if (value === undefined) throw new Error(`Missing synthetic coach variable: ${name}`)
          return [name, value]
        }),
      )
      return {
        synthetic: true as const,
        ...renderCoachTemplate(copyLintInput(entry, revision), variables),
      }
    },

    async cloneActivePack(input: { slug: string; label: string; actorId: string }) {
      idSchema.parse(input.actorId)
      return repository.cloneActivePack(input)
    },

    validatePack: (packId: string) => validateCatalogPack(repository, packId),

    async schedulePack(input: { packId: string; actorId: string; effectiveAt: string }) {
      idSchema.parse(input.packId)
      idSchema.parse(input.actorId)
      z.string().datetime({ offset: true }).parse(input.effectiveAt)
      const validation = await validateCatalogPack(repository, input.packId)
      if (!validation.valid) {
        throw new Error('Coach content pack failed full catalog validation and cannot be scheduled')
      }
      return repository.schedulePack({ ...input, snapshotHash: validation.snapshotHash })
    },

    async activatePack(input: { packId: string; actorId: string }) {
      idSchema.parse(input.packId)
      idSchema.parse(input.actorId)
      const validation = await validateCatalogPack(repository, input.packId)
      if (!validation.valid) {
        throw new Error('Coach content pack failed full catalog validation and cannot be activated')
      }
      return repository.activatePack({ ...input, snapshotHash: validation.snapshotHash })
    },

    async archivePack(input: { packId: string; actorId: string }) {
      idSchema.parse(input.packId)
      idSchema.parse(input.actorId)
      return repository.archivePack(input)
    },

    async rollbackPack(input: { packId: string; actorId: string }) {
      idSchema.parse(input.packId)
      idSchema.parse(input.actorId)
      return repository.rollbackPack(input)
    },
  }
}

type CatalogJoinedRow = {
  pack_id: string
  template_id: string
  template_version_id: string
  pack: {
    id: string
    slug: string
    label: string
    status: string
  }
  template: {
    id: string
    template_key: string
    personality_code: string
    context: string
    channel: string
    locale: string
    variant: number
    allowed_variables: string[]
    required_variables: string[]
  }
  version: {
    id: string
    version: number
    title: string | null
    subject: string | null
    body: string
    status: string
    provenance: string
    created_at: string
  }
}

function mapJoinedRow(row: CatalogJoinedRow): CoachCatalogEntry {
  return {
    packId: row.pack.id,
    packSlug: row.pack.slug,
    packLabel: row.pack.label,
    packStatus: row.pack.status as CoachPackStatus,
    templateId: row.template.id,
    templateKey: row.template.template_key,
    personality: coachPersonalitySchema.parse(row.template.personality_code),
    context: coachMessageContextSchema.parse(row.template.context),
    channel: coachMessageChannelSchema.parse(row.template.channel),
    locale: coachMessageLocaleSchema.parse(row.template.locale),
    variant: z.union([z.literal(1), z.literal(2), z.literal(3)]).parse(row.template.variant),
    allowedVariables: row.template.allowed_variables,
    requiredVariables: row.template.required_variables,
    templateVersionId: row.version.id,
    version: row.version.version,
    title: row.version.title,
    subject: row.version.subject,
    body: row.version.body,
    versionStatus: row.version.status as CoachVersionStatus,
    provenance: row.version.provenance as CoachVersionProvenance,
    createdAt: row.version.created_at,
  }
}

function camelizeRpcResult(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Coach catalog RPC returned an invalid result')
  }
  return value as Record<string, unknown>
}

function requiredString(result: Record<string, unknown>, key: string): string {
  const value = result[key]
  if (typeof value !== 'string') throw new Error(`Coach catalog RPC omitted ${key}`)
  return value
}

function requiredNumber(result: Record<string, unknown>, key: string): number {
  const value = result[key]
  if (typeof value !== 'number') throw new Error(`Coach catalog RPC omitted ${key}`)
  return value
}

export function createSupabaseCoachCatalogRepository(
  client: SupabaseClient<Database>,
  now: () => Date = () => new Date(),
): CoachCatalogRepository {
  async function catalogRows(
    packId: string,
    templateIds?: readonly string[],
  ): Promise<CoachCatalogEntry[]> {
    let query = client
      .from('coach_content_pack_entries')
      .select(
        `
          pack_id,
          template_id,
          template_version_id,
          pack:coach_content_packs!coach_content_pack_entries_pack_id_fkey(
            id, slug, label, status
          ),
          template:coach_message_templates!coach_content_pack_entries_template_id_fkey(
            id, template_key, personality_code, context, channel, locale, variant,
            allowed_variables, required_variables
          ),
          version:coach_message_template_versions!coach_content_pack_entries_version_template_fkey(
            id, version, title, subject, body, status, provenance, created_at
          )
        `,
      )
      .eq('pack_id', packId)

    if (templateIds && templateIds.length > 0) query = query.in('template_id', [...templateIds])
    const { data, error } = await query.order('template_id')
    if (error) throw new Error(`Unable to load coach catalog: ${error.message}`)

    return ((data ?? []) as unknown as CatalogJoinedRow[]).map(mapJoinedRow)
  }

  async function rpc(name: keyof Database['public']['Functions'], args: Record<string, unknown>) {
    const { data, error } = await client.rpc(name, args as never)
    if (error) throw new Error(`Coach catalog ${name} failed: ${error.message}`)
    return camelizeRpcResult(data)
  }

  function revisionResult(result: Record<string, unknown>): CoachRevisionResult {
    const revisions = z
      .array(
        z.object({
          template_id: z.string().uuid(),
          previous_template_version_id: z.string().uuid(),
          template_version_id: z.string().uuid(),
          version: z.number().int().positive(),
        }),
      )
      .parse(result.revisions)
    return {
      outcome: z.literal('revised').parse(result.outcome),
      packId: requiredString(result, 'pack_id'),
      revisionCount: requiredNumber(result, 'revision_count'),
      revisions: revisions.map((revision) => ({
        templateId: revision.template_id,
        previousTemplateVersionId: revision.previous_template_version_id,
        templateVersionId: revision.template_version_id,
        version: revision.version,
      })),
    }
  }

  return {
    async listPacks() {
      const { data, error } = await client
        .from('coach_content_packs')
        .select(
          'id, slug, label, status, parent_pack_id, effective_at, activated_at, archived_at, created_at, updated_at',
        )
        .order('created_at', { ascending: false })
      if (error) throw new Error(`Unable to load coach content packs: ${error.message}`)
      return (data ?? []).map((pack) => ({
        id: pack.id,
        slug: pack.slug,
        label: pack.label,
        status: pack.status as CoachPackStatus,
        parentPackId: pack.parent_pack_id,
        effectiveAt: pack.effective_at,
        activatedAt: pack.activated_at,
        archivedAt: pack.archived_at,
        createdAt: pack.created_at,
        updatedAt: pack.updated_at,
      }))
    },

    async listCatalog(filters) {
      const rows = await catalogRows(filters.packId)
      return rows.filter(
        (row) =>
          (!filters.personality || row.personality === filters.personality) &&
          (!filters.context || row.context === filters.context) &&
          (!filters.channel || row.channel === filters.channel) &&
          (!filters.locale || row.locale === filters.locale) &&
          (!filters.variant || row.variant === filters.variant),
      )
    },

    async listTemplateVersions(templateId) {
      const { data, error } = await client
        .from('coach_message_template_versions')
        .select(
          'id, template_id, version, title, subject, body, status, provenance, approved_at, archived_at, created_at',
        )
        .eq('template_id', templateId)
        .order('version', { ascending: false })
      if (error) throw new Error(`Unable to load coach template versions: ${error.message}`)
      return (data ?? []).map((version) => ({
        id: version.id,
        templateId: version.template_id,
        version: version.version,
        title: version.title,
        subject: version.subject,
        body: version.body,
        status: version.status as CoachVersionStatus,
        provenance: version.provenance as CoachVersionProvenance,
        approvedAt: version.approved_at,
        archivedAt: version.archived_at,
        createdAt: version.created_at,
      }))
    },

    async getUsageSummary() {
      const count = async (column: 'outcome' | 'reason', value: string) => {
        const { count: total, error } = await client
          .from('coach_message_usage')
          .select('id', { count: 'exact', head: true })
          .eq(column, value)
        if (error) throw new Error(`Unable to aggregate coach message usage: ${error.message}`)
        return total ?? 0
      }
      const [selected, suppressed, failed, balancedFallback] = await Promise.all([
        count('outcome', 'selected'),
        count('outcome', 'suppressed'),
        count('outcome', 'failed'),
        count('reason', 'balanced_fallback'),
      ])
      return { selected, suppressed, failed, balancedFallback }
    },

    getPackEntries: catalogRows,

    async reviseDraftEntries(input) {
      const result = await rpc('revise_coach_draft_entries', {
        p_pack_id: input.packId,
        p_revisions: input.revisions.map((revision) => ({
          template_id: revision.templateId,
          expected_template_version_id: revision.expectedTemplateVersionId,
          title: revision.title,
          subject: revision.subject,
          body: revision.body,
        })),
        p_actor_id: input.actorId,
        p_provenance: input.provenance,
        p_now: now().toISOString(),
      })
      return revisionResult(result)
    },

    async reviseAssistedDraftEntries(input) {
      const result = await rpc('revise_coach_assisted_draft_entries', {
        p_pack_id: input.packId,
        p_revisions: input.revisions.map((revision) => ({
          template_id: revision.templateId,
          expected_template_version_id: revision.expectedTemplateVersionId,
          title: revision.title,
          subject: revision.subject,
          body: revision.body,
        })),
        p_actor_id: input.actorId,
        p_model: input.model,
        p_prompt_tokens: input.promptTokens,
        p_completion_tokens: input.completionTokens,
        p_cost_usd: input.costUsd,
        p_latency_ms: input.latencyMs,
        p_group_key: input.groupKey,
        p_now: now().toISOString(),
      })
      return revisionResult(result)
    },

    async cloneActivePack(input) {
      const result = await rpc('clone_active_coach_content_pack', {
        p_slug: input.slug,
        p_label: input.label,
        p_actor_id: input.actorId,
        p_now: now().toISOString(),
      })
      return {
        outcome: z.literal('cloned').parse(result.outcome),
        packId: requiredString(result, 'pack_id'),
        parentPackId: requiredString(result, 'parent_pack_id'),
        entryCount: requiredNumber(result, 'entry_count'),
      }
    },

    async validatePackStructure(packId) {
      const result = await rpc('validate_coach_content_pack', { p_pack_id: packId })
      return {
        packId: requiredString(result, 'pack_id'),
        status: z.enum(['draft', 'scheduled', 'active', 'archived']).parse(result.status),
        entryCount: requiredNumber(result, 'entry_count'),
        validEntryCount: requiredNumber(result, 'valid_entry_count'),
        expectedEntryCount: requiredNumber(result, 'expected_entry_count'),
        snapshotHash: requiredString(result, 'snapshot_hash'),
        valid: z.boolean().parse(result.valid),
      }
    },

    async schedulePack(input) {
      const result = await rpc('schedule_coach_content_pack', {
        p_pack_id: input.packId,
        p_actor_id: input.actorId,
        p_effective_at: input.effectiveAt,
        p_expected_snapshot_hash: input.snapshotHash,
        p_now: now().toISOString(),
      })
      return {
        outcome: z.literal('scheduled').parse(result.outcome),
        packId: requiredString(result, 'pack_id'),
        effectiveAt: requiredString(result, 'effective_at'),
        entryCount: requiredNumber(result, 'entry_count'),
      }
    },

    async activatePack(input) {
      const result = await rpc('approve_and_activate_coach_content_pack', {
        p_pack_id: input.packId,
        p_actor_id: input.actorId,
        p_expected_snapshot_hash: input.snapshotHash,
        p_now: now().toISOString(),
      })
      return {
        outcome: z.enum(['activated', 'already_active']).parse(result.outcome),
        packId: requiredString(result, 'pack_id'),
        previousPackId:
          typeof result.previous_pack_id === 'string' ? result.previous_pack_id : null,
        entryCount: typeof result.entry_count === 'number' ? result.entry_count : 1080,
        activatedAt: requiredString(result, 'activated_at'),
      }
    },

    async archivePack(input) {
      const result = await rpc('archive_coach_content_pack', {
        p_pack_id: input.packId,
        p_actor_id: input.actorId,
        p_now: now().toISOString(),
      })
      return {
        outcome: z.literal('archived').parse(result.outcome),
        packId: requiredString(result, 'pack_id'),
        previousStatus: z
          .enum(['draft', 'scheduled', 'active', 'archived'])
          .parse(result.previous_status),
        archivedAt: requiredString(result, 'archived_at'),
      }
    },

    async rollbackPack(input) {
      const result = await rpc('rollback_coach_content_pack', {
        p_pack_id: input.packId,
        p_actor_id: input.actorId,
        p_now: now().toISOString(),
      })
      return {
        outcome: z.literal('rolled_back').parse(result.outcome),
        packId: requiredString(result, 'pack_id'),
        replacedPackId: requiredString(result, 'replaced_pack_id'),
        entryCount: requiredNumber(result, 'entry_count'),
        activatedAt: requiredString(result, 'activated_at'),
      }
    },
  }
}
