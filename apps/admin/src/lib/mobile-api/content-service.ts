import type { ContentListQuery, ContentReadInput, ContentSaveInput } from '@mpp/core'
import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'

type ContentCategory = NonNullable<ContentListQuery['category']>

export interface ContentCoverReference {
  bucketId: string
  objectPath: string
}

export interface ContentFeedRecord {
  publicationId: string
  slug: string
  locale: 'pt-BR' | 'en-US'
  title: string
  excerpt: string
  category: ContentCategory
  tags: string[]
  readingTimeMinutes: number
  publishAt: string
  featuredToday: boolean
  version: number
  saved: boolean
  completed: boolean
  cover: ContentCoverReference | null
}

export interface ContentRecord extends ContentFeedRecord {
  bodyMarkdown: string
}

export interface ContentFeedPage {
  items: ContentFeedRecord[]
  nextCursor: string | null
}

export interface ContentReadCommand extends ContentReadInput {
  userId: string
  publicationId: string
  idempotencyKey: string
}

export interface ContentSaveCommand extends ContentSaveInput {
  userId: string
  publicationId: string
  origin: 'library'
  idempotencyKey: string
}

export interface ContentUserState {
  publicationId: string
  version: number
  saved: boolean
  completed: boolean
  changed: boolean
  replayed: boolean
}

export interface ContentRepository {
  list(userId: string, query: ContentListQuery): Promise<ContentFeedPage>
  get(userId: string, publicationId: string): Promise<ContentRecord | null>
  recordRead(input: ContentReadCommand): Promise<ContentUserState>
  setSaved(input: ContentSaveCommand): Promise<ContentUserState>
}

export interface ContentCoverGateway {
  issue(input: {
    userId: string
    publicationId: string
    version: number
  }): Promise<{ token: string; expiresAt: string }>
}

export interface ContentServiceDependencies {
  repository: ContentRepository
  covers: ContentCoverGateway
}

export type ContentRepositoryErrorReason =
  | 'not_found'
  | 'version_changed'
  | 'invalid_cursor'
  | 'internal'

export class ContentRepositoryError extends Error {
  constructor(readonly reason: ContentRepositoryErrorReason) {
    super(reason)
    this.name = 'ContentRepositoryError'
  }
}

export interface ContentCoverDto {
  url: string
  expires_at: string
}

export interface ContentFeedItemDto {
  publication_id: string
  slug: string
  locale: 'pt-BR' | 'en-US'
  title: string
  excerpt: string
  category: ContentCategory
  tags: string[]
  reading_time_minutes: number
  publish_at: string
  featured_today: boolean
  version: number
  saved: boolean
  completed: boolean
  cover: ContentCoverDto | null
}

export interface ContentDetailDto extends ContentFeedItemDto {
  body_markdown: string
}

export interface ContentFeedDto {
  items: ContentFeedItemDto[]
  next_cursor: string | null
}

export interface ContentUserStateDto {
  publication_id: string
  version: number
  saved: boolean
  completed: boolean
  changed: boolean
  replayed: boolean
}

function contentNotFound(): MobileApiError {
  return new MobileApiError(404, 'content_not_found', 'Content item not found')
}

function internalError(): MobileApiError {
  return new MobileApiError(500, 'internal_error', 'Unexpected server error')
}

function mapRepositoryError(error: unknown): MobileApiError {
  if (!(error instanceof ContentRepositoryError)) return internalError()

  switch (error.reason) {
    case 'not_found':
      return contentNotFound()
    case 'version_changed':
      return new MobileApiError(409, 'content_version_changed', 'Content version changed')
    case 'invalid_cursor':
      return new MobileApiError(422, 'validation_failed', 'Request validation failed', {
        fields: [{ path: 'cursor', code: 'custom', message: 'Cursor is invalid' }],
      })
    case 'internal':
      return internalError()
  }
}

async function repositoryCall<T>(operation: () => Promise<T>): Promise<T> {
  try {
    return await operation()
  } catch (error) {
    throw mapRepositoryError(error)
  }
}

async function mapCover(
  dependencies: ContentServiceDependencies,
  cover: ContentCoverReference | null,
  input: { userId: string; publicationId: string; version: number },
): Promise<ContentCoverDto | null> {
  if (!cover) return null

  try {
    const capability = await dependencies.covers.issue(input)
    return {
      url: `/api/mobile/v1/content/covers/${capability.token}`,
      expires_at: capability.expiresAt,
    }
  } catch {
    throw internalError()
  }
}

async function mapFeedItem(
  dependencies: ContentServiceDependencies,
  record: ContentFeedRecord,
  userId: string,
): Promise<ContentFeedItemDto> {
  return {
    publication_id: record.publicationId,
    slug: record.slug,
    locale: record.locale,
    title: record.title,
    excerpt: record.excerpt,
    category: record.category,
    tags: record.tags,
    reading_time_minutes: record.readingTimeMinutes,
    publish_at: record.publishAt,
    featured_today: record.featuredToday,
    version: record.version,
    saved: record.saved,
    completed: record.completed,
    cover: await mapCover(dependencies, record.cover, {
      userId,
      publicationId: record.publicationId,
      version: record.version,
    }),
  }
}

function mapUserState(state: ContentUserState): ContentUserStateDto {
  return {
    publication_id: state.publicationId,
    version: state.version,
    saved: state.saved,
    completed: state.completed,
    changed: state.changed,
    replayed: state.replayed,
  }
}

export async function listContent(
  dependencies: ContentServiceDependencies,
  auth: MobileAuthContext,
  query: ContentListQuery,
): Promise<ContentFeedDto> {
  const page = await repositoryCall(() => dependencies.repository.list(auth.userId, query))

  return {
    items: await Promise.all(
      page.items.map((item) => mapFeedItem(dependencies, item, auth.userId)),
    ),
    next_cursor: page.nextCursor,
  }
}

export async function getContent(
  dependencies: ContentServiceDependencies,
  auth: MobileAuthContext,
  publicationId: string,
): Promise<ContentDetailDto> {
  const record = await repositoryCall(() => dependencies.repository.get(auth.userId, publicationId))
  if (!record) throw contentNotFound()

  return {
    ...(await mapFeedItem(dependencies, record, auth.userId)),
    body_markdown: record.bodyMarkdown,
  }
}

export async function recordContentRead(
  dependencies: ContentServiceDependencies,
  auth: MobileAuthContext,
  publicationId: string,
  input: ContentReadInput,
  idempotencyKey: string,
): Promise<ContentUserStateDto> {
  const state = await repositoryCall(() =>
    dependencies.repository.recordRead({
      userId: auth.userId,
      publicationId,
      event: input.event,
      origin: input.origin,
      version: input.version,
      idempotencyKey,
    }),
  )
  return mapUserState(state)
}

export async function setContentSaved(
  dependencies: ContentServiceDependencies,
  auth: MobileAuthContext,
  publicationId: string,
  input: ContentSaveInput,
  idempotencyKey: string,
): Promise<ContentUserStateDto> {
  const state = await repositoryCall(() =>
    dependencies.repository.setSaved({
      userId: auth.userId,
      publicationId,
      saved: input.saved,
      version: input.version,
      origin: 'library',
      idempotencyKey,
    }),
  )
  return mapUserState(state)
}
