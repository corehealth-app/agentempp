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

function formatOperationalDate(value: string): string {
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'UTC',
  }).format(new Date(value))
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
): {
  latest: ContentPublicationDetail['versions'][number] | null
  previousPublished: ContentPublicationDetail['versions'][number] | null
} {
  const ordered = versions.filter((version) => version.locale === locale).sort(byNewestVersion)
  const latest = ordered[0] ?? null
  const previousPublished =
    ordered.find((version) => version.versionId !== latest?.versionId && version.publishedAt) ??
    null
  return { latest, previousPublished }
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
