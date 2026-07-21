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
  locales: ContentLocale[]
  versions: PublicationListVersion[]
}

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
  return publications.filter((publication) =>
    [publication.slug, ...publication.versions.map((version) => version.title ?? '')]
      .join(' ')
      .toLocaleLowerCase('pt-BR')
      .includes(normalized),
  )
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

  const effectiveStatus = publication.archivedAt
    ? 'archived'
    : (versions
        .map((version) => version.effectiveStatus)
        .sort((left, right) => STATUS_PRIORITY[right] - STATUS_PRIORITY[left])[0] ?? 'draft')

  return {
    publicationId: publication.publicationId,
    slug: publication.slug,
    archivedAt: publication.archivedAt,
    createdAt: publication.createdAt,
    updatedAt: publication.updatedAt,
    effectiveStatus,
    locales: versions.map((version) => version.locale),
    versions,
  }
}
