import type { ContentDraftInput } from '@mpp/core'
import type { AdminRole } from '@/lib/admin-rbac'
import type {
  ContentPublicationDetail,
  ContentPublicationSummary,
} from '@/lib/content/admin-service'

export type ContentLocale = 'pt-BR' | 'en-US'
export type EffectiveContentStatus =
  | 'draft'
  | 'in_review'
  | 'approved'
  | 'rejected'
  | 'scheduled'
  | 'published'
  | 'archived'

export type ContentCommand =
  | 'create'
  | 'create_draft'
  | 'save_draft'
  | 'submit'
  | 'cover'
  | 'approve'
  | 'reject'
  | 'publish'
  | 'schedule'
  | 'archive'

export interface PublicationListVersion {
  versionId: string
  version: number
  locale: ContentLocale
  category: ContentPublicationSummary['versions'][number]['category']
  title: string | null
  state: ContentPublicationSummary['versions'][number]['state']
  effectiveStatus: Exclude<EffectiveContentStatus, 'archived'>
  featuredToday: boolean
  authorId: string
  reviewerId: string | null
  publishAt: string | null
  updatedAt: string
}

export interface PublicationListRow {
  publicationId: string
  slug: string
  archivedAt: string | null
  createdAt: string
  updatedAt: string
  effectiveStatus: EffectiveContentStatus
  primaryVersionId: string | null
  locales: ContentLocale[]
  versions: PublicationListVersion[]
}

export interface DraftSaveState {
  versionId: string
  expectedUpdatedAt: string
  stale: boolean
  confirmedCover: { assetId: string; locale: ContentLocale } | null
}

export interface DraftEditBaseline {
  versionId: string
  draft: ContentDraftInput
}

export type LocaleSwitchDecision = 'stay' | 'switch' | 'confirm_discard'
export type StaleRecoveryDecision = 'cancel' | 'load_current'

const LOCALES = ['pt-BR', 'en-US'] as const
export const PUBLICATION_PAGE_SIZE = 25
export const PUBLICATION_BATCH_SIZE = 100
export const PUBLICATION_MAX_OFFSET = 10_000
export const PUBLICATION_DIRECT_MAX_PAGE =
  Math.floor(PUBLICATION_MAX_OFFSET / PUBLICATION_PAGE_SIZE) + 1
export const PUBLICATION_TEXT_MAX_PAGE = Math.ceil(
  (PUBLICATION_MAX_OFFSET + PUBLICATION_BATCH_SIZE) / PUBLICATION_PAGE_SIZE,
)

const COMMANDS_BY_ROLE: Record<AdminRole, readonly ContentCommand[]> = {
  support: [],
  content_editor: ['create', 'create_draft', 'save_draft', 'submit', 'cover'],
  nutrition_admin: ['approve', 'reject'],
  operations_admin: [],
  master_admin: ['publish', 'schedule', 'archive'],
}

const STATUS_PRIORITY: Record<EffectiveContentStatus, number> = {
  draft: 0,
  rejected: 1,
  approved: 2,
  in_review: 3,
  scheduled: 4,
  published: 5,
  archived: 6,
}

function byNewestVersion<T extends { version: number; updatedAt: string }>(left: T, right: T) {
  return right.version - left.version || right.updatedAt.localeCompare(left.updatedAt)
}

export function effectiveVersionStatus(
  version: ContentPublicationSummary['versions'][number],
  now: string,
  archivedAt: string | null = null,
): EffectiveContentStatus {
  if (archivedAt) return 'archived'
  if (version.state !== 'approved' || !version.publishAt) return version.state
  return Date.parse(version.publishAt) <= Date.parse(now) ? 'published' : 'scheduled'
}

export function localeCompleteness(
  versions: readonly ContentPublicationSummary['versions'][number][],
): { available: ContentLocale[]; missing: ContentLocale[]; complete: boolean } {
  const present = new Set(versions.map((version) => version.locale))
  const available = LOCALES.filter((locale) => present.has(locale))
  const missing = LOCALES.filter((locale) => !present.has(locale))
  return { available: [...available], missing: [...missing], complete: missing.length === 0 }
}

export function visibleContentCommands(role: AdminRole): ContentCommand[] {
  return [...COMMANDS_BY_ROLE[role]]
}

export function canReviewContentVersion(
  role: AdminRole,
  state: ContentPublicationDetail['versions'][number]['state'],
  archivedAt: string | null,
): boolean {
  return role === 'nutrition_admin' && state === 'in_review' && !archivedAt
}

export function canPublishContentVersion(
  role: AdminRole,
  state: ContentPublicationDetail['versions'][number]['state'],
  publishAt: string | null,
  archivedAt: string | null,
): boolean {
  return role === 'master_admin' && state === 'approved' && publishAt === null && !archivedAt
}

export function canCreateContentDraft(
  versions: readonly ContentPublicationDetail['versions'][number][],
  locale: ContentLocale,
  archivedAt: string | null,
): boolean {
  if (archivedAt) return false
  return !versions.some(
    (version) =>
      version.locale === locale &&
      (version.state === 'draft' ||
        version.state === 'in_review' ||
        (version.state === 'approved' && version.publishAt === null)),
  )
}

export function selectWorkflowContentVersion(
  versions: readonly ContentPublicationDetail['versions'][number][],
  locale: ContentLocale,
  role: AdminRole,
  archivedAt: string | null,
): ContentPublicationDetail['versions'][number] | null {
  if (archivedAt) return null
  const applicable = versions.filter((version) => {
    if (version.locale !== locale) return false
    if (role === 'nutrition_admin') return version.state === 'in_review'
    if (role === 'master_admin') return version.state === 'approved' && version.publishAt === null
    return false
  })
  return applicable.sort(byNewestVersion)[0] ?? null
}

export function contentWorkflowTargetLabel(
  version: ContentPublicationDetail['versions'][number],
): string {
  const title = version.title?.trim() || 'Sem titulo'
  return `${version.locale} · v${version.version} · ${title} · ${version.versionId.slice(0, 8)}...${version.versionId.slice(-4)}`
}

export function normalizeDraftTags(value: string | readonly string[]): string[] {
  const values = typeof value === 'string' ? value.split(/[,\n]/) : value
  return [
    ...new Set(
      values
        .map((tag) =>
          tag
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .toLowerCase()
            .trim()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-+|-+$/g, ''),
        )
        .filter(Boolean),
    ),
  ]
}

export function createDraftEditBaseline(
  version: ContentPublicationDetail['versions'][number],
): DraftEditBaseline {
  return {
    versionId: version.versionId,
    draft: {
      locale: version.locale,
      category: version.category ?? 'nutrition',
      title: version.title ?? '',
      excerpt: version.excerpt ?? '',
      bodyMarkdown: version.bodyMarkdown ?? '',
      tags: [...version.tags],
      featuredToday: version.featuredToday,
      coverAssetId: version.cover?.assetId ?? null,
      targeting: {
        protocols: [...version.targeting.protocols],
        plans: [...version.targeting.plans],
        personalities: [...version.targeting.personalities],
      },
    },
  }
}

export function draftsAreEquivalent(left: ContentDraftInput, right: ContentDraftInput): boolean {
  return JSON.stringify(comparableDraft(left)) === JSON.stringify(comparableDraft(right))
}

export function isDraftDirty(
  baseline: DraftEditBaseline,
  current: ContentDraftInput,
  editable: boolean,
): boolean {
  return editable && !draftsAreEquivalent(baseline.draft, current)
}

export function localeSwitchDecision(
  currentLocale: ContentLocale,
  nextLocale: ContentLocale,
  dirty: boolean,
  blocked: boolean,
): LocaleSwitchDecision {
  if (currentLocale === nextLocale || blocked) return 'stay'
  return dirty ? 'confirm_discard' : 'switch'
}

export function staleRecoveryDecision(confirmed: boolean): StaleRecoveryDecision {
  return confirmed ? 'load_current' : 'cancel'
}

function comparableDraft(draft: ContentDraftInput): ContentDraftInput {
  return {
    ...draft,
    tags: normalizeDraftTags(draft.tags).sort(),
    targeting: {
      protocols: [...draft.targeting.protocols].sort(),
      plans: [...draft.targeting.plans].sort(),
      personalities: [...draft.targeting.personalities].sort(),
    },
  }
}

export function findDraftVersionBaseline(
  versions: readonly ContentPublicationDetail['versions'][number][],
  versionId: string,
): { versionId: string; expectedUpdatedAt: string } | null {
  const version = versions.find(
    (candidate) => candidate.versionId === versionId && candidate.state === 'draft',
  )
  return version ? { versionId: version.versionId, expectedUpdatedAt: version.updatedAt } : null
}

export function markDraftSaveStale(state: DraftSaveState): DraftSaveState {
  return { ...state, stale: true }
}

export function recoverDraftSaveState(
  state: DraftSaveState,
  versions: readonly ContentPublicationDetail['versions'][number][],
):
  | { recovered: true; state: DraftSaveState; baseline: DraftEditBaseline }
  | { recovered: false; state: DraftSaveState } {
  const version = versions.find(
    (candidate) => candidate.versionId === state.versionId && candidate.state === 'draft',
  )
  if (!version) return { recovered: false, state }
  return {
    recovered: true,
    state: { ...state, expectedUpdatedAt: version.updatedAt, stale: false },
    baseline: createDraftEditBaseline(version),
  }
}

export function buildDraftSavePayload(
  state: DraftSaveState,
  draft: ContentDraftInput,
): { versionId: string; expectedUpdatedAt: string; draft: ContentDraftInput } | null {
  if (state.stale) return null
  return {
    versionId: state.versionId,
    expectedUpdatedAt: state.expectedUpdatedAt,
    draft,
  }
}

export function formatOperationalDate(value: string): string {
  const formatted = new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: 'UTC',
  }).format(new Date(value))
  return `${formatted} UTC`
}

export function parseUtcDateTimeLocal(value: string): string | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(value)
  if (!match) return null

  const [, yearPart, monthPart, dayPart, hourPart, minutePart] = match
  const year = Number(yearPart)
  const month = Number(monthPart)
  const day = Number(dayPart)
  const hour = Number(hourPart)
  const minute = Number(minutePart)
  if (year < 1 || month < 1 || month > 12 || hour > 23 || minute > 59) return null

  const parsed = new Date(0)
  parsed.setUTCFullYear(year, month - 1, day)
  parsed.setUTCHours(hour, minute, 0, 0)
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day ||
    parsed.getUTCHours() !== hour ||
    parsed.getUTCMinutes() !== minute
  ) {
    return null
  }
  return parsed.toISOString()
}

export function scheduleLabel(
  version: ContentPublicationSummary['versions'][number],
  now: string,
): { kind: 'none' | 'scheduled' | 'published'; label: string } {
  if (version.state !== 'approved' || !version.publishAt) {
    return { kind: 'none', label: 'Sem agendamento' }
  }
  const formatted = formatOperationalDate(version.publishAt)
  if (Date.parse(version.publishAt) <= Date.parse(now)) {
    return { kind: 'published', label: `Publicado em ${formatted}` }
  }
  return { kind: 'scheduled', label: `Agendado para ${formatted}` }
}

export function selectLocaleVersions(
  versions: readonly ContentPublicationDetail['versions'][number][],
  locale: ContentLocale,
  now: string,
): {
  latest: ContentPublicationDetail['versions'][number] | null
  previousPublished: ContentPublicationDetail['versions'][number] | null
  futureScheduled: ContentPublicationDetail['versions'][number] | null
} {
  const ordered = versions.filter((version) => version.locale === locale).sort(byNewestVersion)
  const latest = ordered[0] ?? null
  const previousPublished =
    ordered.find(
      (version) =>
        version.versionId !== latest?.versionId &&
        version.state === 'approved' &&
        version.publishAt !== null &&
        Date.parse(version.publishAt) <= Date.parse(now),
    ) ?? null
  const futureScheduled =
    ordered.find(
      (version) =>
        version.state === 'approved' &&
        version.publishAt !== null &&
        Date.parse(version.publishAt) > Date.parse(now),
    ) ?? null
  return { latest, previousPublished, futureScheduled }
}

export function filterPublicationSummaries(
  publications: readonly ContentPublicationSummary[],
  text: string,
): ContentPublicationSummary[] {
  const normalized = text.trim().toLocaleLowerCase('pt-BR')
  if (!normalized) return [...publications]
  return publications.filter((publication) => {
    const candidates = publication.matchedVersionId
      ? publication.versions.filter((version) => version.versionId === publication.matchedVersionId)
      : LOCALES.flatMap((locale) => {
          const latest = publication.versions
            .filter((version) => version.locale === locale)
            .sort(byNewestVersion)[0]
          return latest ? [latest] : []
        })
    return [publication.slug, ...candidates.map((version) => version.title ?? '')]
      .join(' ')
      .toLocaleLowerCase('pt-BR')
      .includes(normalized)
  })
}

export function paginatePublications(
  publications: readonly ContentPublicationSummary[],
  page: number,
  pageSize: number = PUBLICATION_PAGE_SIZE,
): {
  rows: ContentPublicationSummary[]
  page: number
  hasPrevious: boolean
  hasNext: boolean
  total: number
} {
  const stable = [...publications].sort(
    (left, right) =>
      right.updatedAt.localeCompare(left.updatedAt) ||
      left.publicationId.localeCompare(right.publicationId),
  )
  const safePage = Number.isInteger(page) && page > 0 ? page : 1
  const offset = (safePage - 1) * pageSize
  return {
    rows: stable.slice(offset, offset + pageSize),
    page: safePage,
    hasPrevious: safePage > 1,
    hasNext: offset + pageSize < stable.length,
    total: stable.length,
  }
}

export function directPublicationPage(
  publications: readonly ContentPublicationSummary[],
  page: number,
): {
  rows: ContentPublicationSummary[]
  hasPrevious: boolean
  hasNext: boolean
  truncated: boolean
} {
  const hasProbe = publications.length > PUBLICATION_PAGE_SIZE
  const atOffsetCeiling = page >= PUBLICATION_DIRECT_MAX_PAGE
  return {
    rows: publications.slice(0, PUBLICATION_PAGE_SIZE),
    hasPrevious: page > 1,
    hasNext: hasProbe && !atOffsetCeiling,
    truncated: hasProbe && atOffsetCeiling,
  }
}

export function parsePublicationPage(
  value: string | string[] | undefined,
  mode: 'direct' | 'text',
): number {
  const scalar = Array.isArray(value) ? value[0] : value
  if (!scalar || !/^\d+$/.test(scalar)) return 1
  const parsed = Number(scalar)
  if (!Number.isSafeInteger(parsed) || parsed < 1) return 1
  const maximum = mode === 'text' ? PUBLICATION_TEXT_MAX_PAGE : PUBLICATION_DIRECT_MAX_PAGE
  return Math.min(parsed, maximum)
}

export function toPublicationListRow(
  publication: ContentPublicationSummary,
  now: string,
): PublicationListRow {
  const versions = LOCALES.flatMap((locale) => {
    const latest = publication.versions
      .filter((version) => version.locale === locale)
      .sort(byNewestVersion)[0]
    if (!latest) return []
    const effectiveStatus = effectiveVersionStatus(latest, now)
    return [
      {
        versionId: latest.versionId,
        version: latest.version,
        locale: latest.locale,
        category: latest.category,
        title: latest.title,
        state: latest.state,
        effectiveStatus: effectiveStatus as Exclude<EffectiveContentStatus, 'archived'>,
        featuredToday: latest.featuredToday,
        authorId: latest.authorId,
        reviewerId: latest.reviewerId,
        publishAt: latest.publishAt,
        updatedAt: latest.updatedAt,
      },
    ]
  })

  const primaryVersion = versions.find(
    (version) => version.versionId === publication.matchedVersionId,
  )
  const effectiveStatus = publication.archivedAt
    ? 'archived'
    : (primaryVersion?.effectiveStatus ??
      versions
        .map((version) => version.effectiveStatus)
        .sort((left, right) => STATUS_PRIORITY[right] - STATUS_PRIORITY[left])[0] ??
      'draft')

  return {
    publicationId: publication.publicationId,
    slug: publication.slug,
    archivedAt: publication.archivedAt,
    createdAt: publication.createdAt,
    updatedAt: publication.updatedAt,
    effectiveStatus,
    primaryVersionId: primaryVersion?.versionId ?? null,
    locales: versions.map((version) => version.locale),
    versions,
  }
}
