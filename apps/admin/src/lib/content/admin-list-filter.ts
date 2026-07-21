import type { ContentAdminFilters, ContentPublicationSummary } from './admin-service'

export type ContentAdminVersionFilters = Omit<ContentAdminFilters, 'limit' | 'offset'>

type SummaryVersion = ContentPublicationSummary['versions'][number]

const LOCALES = ['pt-BR', 'en-US'] as const

export function hasAdminListVersionFilters(filters: ContentAdminVersionFilters): boolean {
  return (
    (filters.status !== undefined && filters.status !== 'archived') ||
    filters.locale !== undefined ||
    filters.category !== undefined ||
    filters.authorId !== undefined ||
    filters.reviewerId !== undefined ||
    filters.schedule !== undefined ||
    filters.featuredToday !== undefined
  )
}

export function selectAdminListMatchedVersion(
  publication: ContentPublicationSummary,
  filters: ContentAdminVersionFilters,
  now: number,
): SummaryVersion | null {
  const latestByLocale = new Map<SummaryVersion['locale'], SummaryVersion>()

  for (const version of publication.versions) {
    if (filters.locale && version.locale !== filters.locale) continue
    const current = latestByLocale.get(version.locale)
    if (!current || compareVersions(version, current) < 0) {
      latestByLocale.set(version.locale, version)
    }
  }

  for (const locale of LOCALES) {
    const candidate = latestByLocale.get(locale)
    if (candidate && matchesVersionFilters(candidate, filters, now)) return candidate
  }
  return null
}

export function filterAdminListPublications(
  publications: readonly ContentPublicationSummary[],
  filters: ContentAdminVersionFilters,
  now: number,
): ContentPublicationSummary[] {
  const expectsArchived = filters.status === 'archived'
  const hasVersionFilters = hasAdminListVersionFilters(filters)
  const matches: ContentPublicationSummary[] = []

  for (const publication of publications) {
    if (Boolean(publication.archivedAt) !== expectsArchived) continue
    if (!hasVersionFilters) {
      matches.push(publication)
      continue
    }

    const matched = selectAdminListMatchedVersion(publication, filters, now)
    if (matched) matches.push({ ...publication, matchedVersionId: matched.versionId })
  }

  return matches
}

export function textAdminListScanFilters(
  filters: ContentAdminVersionFilters,
  offset: number,
  limit: number,
): ContentAdminFilters {
  return {
    ...(filters.status === 'archived' ? { status: 'archived' as const } : {}),
    limit,
    offset,
  }
}

function compareVersions(left: SummaryVersion, right: SummaryVersion): number {
  return (
    right.version - left.version ||
    right.updatedAt.localeCompare(left.updatedAt) ||
    left.versionId.localeCompare(right.versionId)
  )
}

function matchesVersionFilters(
  version: SummaryVersion,
  filters: ContentAdminVersionFilters,
  now: number,
): boolean {
  const publishAt = version.publishAt === null ? null : Date.parse(version.publishAt)
  const isScheduled = version.state === 'approved' && publishAt !== null && publishAt > now
  const isPublished = version.state === 'approved' && publishAt !== null && publishAt <= now

  if (filters.status && filters.status !== 'archived') {
    if (filters.status === 'scheduled' && !isScheduled) return false
    if (filters.status === 'published' && !isPublished) return false
    if (filters.status === 'approved' && (version.state !== 'approved' || publishAt !== null)) {
      return false
    }
    if (
      ['draft', 'in_review', 'rejected'].includes(filters.status) &&
      version.state !== filters.status
    ) {
      return false
    }
  }
  if (filters.category && version.category !== filters.category) return false
  if (filters.authorId && version.authorId !== filters.authorId) return false
  if (filters.reviewerId && version.reviewerId !== filters.reviewerId) return false
  if (filters.featuredToday !== undefined && version.featuredToday !== filters.featuredToday) {
    return false
  }
  if (filters.schedule === 'unscheduled' && version.publishAt !== null) return false
  if (filters.schedule === 'scheduled' && !isScheduled) return false
  if (filters.schedule === 'published' && !isPublished) return false
  return true
}
