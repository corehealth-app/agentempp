import { z } from 'zod'
import { filterAdminListPublications, hasAdminListVersionFilters } from './admin-list-filter'
import {
  ContentAdminError,
  type ContentAdminErrorCode,
  type ContentAdminFilters,
  type ContentAdminRepository,
  type ContentAdminStorage,
  ContentStorageError,
  type InternalContentAsset,
} from './admin-service'

interface SupabaseResult {
  data: unknown
  error: unknown
}

interface ContentQueryBuilder extends PromiseLike<SupabaseResult> {
  select(...args: unknown[]): ContentQueryBuilder
  eq(...args: unknown[]): ContentQueryBuilder
  in(...args: unknown[]): ContentQueryBuilder
  is(...args: unknown[]): ContentQueryBuilder
  not(...args: unknown[]): ContentQueryBuilder
  gt(...args: unknown[]): ContentQueryBuilder
  lte(...args: unknown[]): ContentQueryBuilder
  order(...args: unknown[]): ContentQueryBuilder
  limit(...args: unknown[]): ContentQueryBuilder
  range(...args: unknown[]): ContentQueryBuilder
  maybeSingle(...args: unknown[]): ContentQueryBuilder
}

interface ContentStorageBucket {
  createSignedUploadUrl(objectPath: string, options: { upsert: false }): Promise<SupabaseResult>
  info(objectPath: string): Promise<SupabaseResult>
  remove(objectPaths: string[]): Promise<SupabaseResult>
}

export interface ContentSupabaseClient {
  rpc(name: string, params: Record<string, unknown>): PromiseLike<SupabaseResult>
  from(table: string): ContentQueryBuilder
  storage: { from(bucket: string): ContentStorageBucket }
}

const uuidSchema = z.string().uuid()
const timestampSchema = z.string().datetime({ offset: true })
const nullableTimestampSchema = timestampSchema.nullable()
const stateSchema = z.enum(['draft', 'in_review', 'approved', 'rejected'])
const localeSchema = z.enum(['pt-BR', 'en-US'])
const categorySchema = z
  .enum([
    'weight_loss',
    'hypertrophy',
    'nutrition',
    'training',
    'neuroscience',
    'habit_formation',
    'cardiovascular_health',
    'hydration',
    'supplementation',
    'sleep',
    'using_bodyflow',
  ])
  .nullable()
const mimeSchema = z.enum(['image/jpeg', 'image/png', 'image/webp'])
const assetStatusSchema = z.enum(['pending_upload', 'uploaded', 'deleted'])
const adminRoleSchema = z.enum([
  'support',
  'content_editor',
  'nutrition_admin',
  'operations_admin',
  'master_admin',
])

const versionSummaryRowSchema = z
  .object({
    id: uuidSchema,
    version: z.number().int().positive(),
    locale: localeSchema,
    category: categorySchema,
    title: z.string().nullable(),
    state: stateSchema,
    featured_today: z.boolean(),
    authored_by: uuidSchema,
    reviewed_by: uuidSchema.nullable(),
    publish_at: nullableTimestampSchema,
    updated_at: timestampSchema,
  })
  .strict()

const publicationListRowSchema = z
  .object({
    id: uuidSchema,
    slug: z.string(),
    archived_at: nullableTimestampSchema,
    created_at: timestampSchema,
    updated_at: timestampSchema,
    pt_versions: z.array(versionSummaryRowSchema),
    en_versions: z.array(versionSummaryRowSchema),
  })
  .strict()

const publicationDetailRowSchema = z
  .object({
    id: uuidSchema,
    slug: z.string(),
    created_by: uuidSchema,
    archived_by: uuidSchema.nullable(),
    archived_at: nullableTimestampSchema,
    created_at: timestampSchema,
    updated_at: timestampSchema,
  })
  .strict()

const versionDetailRowSchema = versionSummaryRowSchema
  .extend({
    excerpt: z.string().nullable(),
    body_markdown: z.string().nullable(),
    body_hash: z
      .string()
      .regex(/^[0-9a-f]{64}$/)
      .nullable(),
    reading_time_minutes: z.number().int().positive().nullable(),
    tags: z.array(z.string()),
    cover_asset_id: uuidSchema.nullable(),
    submitted_at: nullableTimestampSchema,
    reviewed_at: nullableTimestampSchema,
    rejection_reason: z.string().nullable(),
    published_by: uuidSchema.nullable(),
    published_at: nullableTimestampSchema,
  })
  .strict()

const protocolTargetRowSchema = z
  .object({
    content_version_id: uuidSchema,
    protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']),
  })
  .strict()
const planTargetRowSchema = z
  .object({
    content_version_id: uuidSchema,
    plan: z.enum(['trial', 'mensal', 'anual']),
  })
  .strict()
const personalityTargetRowSchema = z
  .object({
    content_version_id: uuidSchema,
    personality_code: z.enum(['focus', 'impulse', 'zen']),
  })
  .strict()
const safeAssetRowSchema = z
  .object({
    id: uuidSchema,
    mime_type: mimeSchema,
    declared_size_bytes: z.number().int().positive(),
    actual_size_bytes: z.number().int().positive().nullable(),
    status: assetStatusSchema,
  })
  .strict()
const adminIdentityRowSchema = z
  .object({ id: uuidSchema, name: z.string().nullable(), role: adminRoleSchema })
  .strict()
const internalAssetRowSchema = z
  .object({
    id: uuidSchema,
    bucket_id: z.literal('content-covers'),
    object_path: z.string().regex(/^content\/[0-9a-f-]{36}\.(?:jpg|png|webp)$/),
    mime_type: mimeSchema,
    declared_size_bytes: z.number().int().positive(),
    actual_size_bytes: z.number().int().positive().nullable(),
    etag: z.string().min(1).max(512).nullable(),
    status: assetStatusSchema,
  })
  .strict()
const versionValidationSnapshotRowSchema = z
  .object({
    id: uuidSchema,
    publication_id: uuidSchema,
    locale: localeSchema,
    state: stateSchema,
    body_markdown: z.string().nullable(),
    updated_at: timestampSchema,
    publish_at: nullableTimestampSchema,
  })
  .strict()

const publicationResultSchema = z
  .object({ publication_id: uuidSchema, slug: z.string(), created_at: timestampSchema })
  .strict()
const draftResultSchema = z
  .object({
    publication_id: uuidSchema,
    version_id: uuidSchema,
    version: z.number().int().positive(),
    locale: localeSchema,
    state: z.literal('draft'),
    updated_at: timestampSchema,
  })
  .strict()
const savedResultSchema = z
  .object({
    publication_id: uuidSchema,
    version_id: uuidSchema,
    version: z.number().int().positive(),
    state: z.literal('draft'),
    body_hash: z.string().regex(/^[0-9a-f]{64}$/),
    reading_time_minutes: z.number().int().positive(),
    updated_at: timestampSchema,
  })
  .strict()
const submittedResultSchema = z
  .object({
    publication_id: uuidSchema,
    version_id: uuidSchema,
    version: z.number().int().positive(),
    state: z.literal('in_review'),
    body_hash: z.string().regex(/^[0-9a-f]{64}$/),
    updated_at: timestampSchema,
  })
  .strict()
const reviewedResultSchema = z
  .object({
    publication_id: uuidSchema,
    version_id: uuidSchema,
    version: z.number().int().positive(),
    state: z.enum(['approved', 'rejected']),
    body_hash: z.string().regex(/^[0-9a-f]{64}$/),
    reviewed_at: timestampSchema,
    updated_at: timestampSchema,
  })
  .strict()
const publishedResultSchema = z
  .object({
    publication_id: uuidSchema,
    version_id: uuidSchema,
    version: z.number().int().positive(),
    state: z.literal('approved'),
    effective_state: z.enum(['published', 'scheduled']),
    publish_at: timestampSchema,
    body_hash: z.string().regex(/^[0-9a-f]{64}$/),
    updated_at: timestampSchema,
  })
  .strict()
const archiveResultSchema = z
  .object({
    outcome: z.enum(['archived', 'already_archived']),
    publication_id: uuidSchema,
    archived_at: timestampSchema,
  })
  .strict()
const createdAssetResultSchema = z
  .object({
    asset_id: uuidSchema,
    bucket_id: z.literal('content-covers'),
    object_path: z.string(),
    mime_type: mimeSchema,
    declared_size_bytes: z.number().int().positive(),
    status: z.literal('pending_upload'),
    created_at: timestampSchema,
  })
  .strict()
const completedAssetResultSchema = z
  .object({
    asset_id: uuidSchema,
    status: z.literal('uploaded'),
    actual_size_bytes: z.number().int().positive(),
    uploaded_at: timestampSchema,
    updated_at: timestampSchema,
  })
  .strict()
const deletedAssetResultSchema = z
  .object({
    asset_id: uuidSchema,
    status: z.literal('deleted'),
    deleted_at: timestampSchema,
    updated_at: timestampSchema.optional(),
  })
  .strict()

const VERSION_SUMMARY_SELECTION = `
  id,
  version,
  locale,
  category,
  title,
  state,
  featured_today,
  authored_by,
  reviewed_by,
  publish_at,
  updated_at
`
const LIST_SELECTION = `
  id,
  slug,
  archived_at,
  created_at,
  updated_at,
  pt_versions:content_versions (${VERSION_SUMMARY_SELECTION}),
  en_versions:content_versions (${VERSION_SUMMARY_SELECTION})
`
const PUBLICATION_SELECTION =
  'id, slug, created_by, archived_by, archived_at, created_at, updated_at'
const VERSION_SELECTION =
  'id, version, locale, category, title, excerpt, body_markdown, body_hash, reading_time_minutes, tags, featured_today, cover_asset_id, state, authored_by, submitted_at, reviewed_by, reviewed_at, rejection_reason, published_by, published_at, publish_at, updated_at'
const SAFE_ASSET_SELECTION = 'id, mime_type, declared_size_bytes, actual_size_bytes, status'
const INTERNAL_ASSET_SELECTION =
  'id, bucket_id, object_path, mime_type, declared_size_bytes, actual_size_bytes, etag, status'
const VERSION_VALIDATION_SNAPSHOT_SELECTION =
  'id, publication_id, locale, state, body_markdown, updated_at, publish_at'
const LIST_SCAN_BATCH_SIZE = 100
const LIST_SCAN_MAX_OFFSET = 10_000
const DETAIL_VERSION_LIMIT = 50

type Operation =
  | 'list'
  | 'get'
  | 'getVersionValidationSnapshot'
  | 'createPublication'
  | 'createDraft'
  | 'saveDraft'
  | 'submit'
  | 'review'
  | 'publish'
  | 'archive'
  | 'createAsset'
  | 'completeAsset'
  | 'deleteAsset'
  | 'getAssetInternal'

function sqlState(error: unknown): string | null {
  if (typeof error !== 'object' || error === null) return null
  const code = (error as { code?: unknown }).code
  return typeof code === 'string' ? code : null
}

function errorCode(operation: Operation, state: string | null): ContentAdminErrorCode {
  if (state === '40001') return 'stale'
  if (state === '23505') return 'duplicate'
  if (state === '23503') return 'not_found'
  if (state === '22023') return 'validation'
  if (state === '42501') return 'denied'
  if (state === '23514') {
    if (operation === 'deleteAsset') return 'cover_referenced'
    if (operation === 'completeAsset') return 'cover_mismatch'
    return 'lifecycle'
  }
  return 'database_unavailable'
}

function databaseFailure(operation: Operation, error?: unknown): never {
  throw new ContentAdminError(errorCode(operation, sqlState(error)), operation)
}

function parseDatabase<T>(schema: z.ZodType<T>, value: unknown, operation: Operation): T {
  const parsed = schema.safeParse(value)
  if (!parsed.success) databaseFailure(operation)
  return parsed.data
}

async function queryResult(
  query: PromiseLike<SupabaseResult>,
  operation: Operation,
): Promise<unknown> {
  const { data, error } = await query
  if (error) databaseFailure(operation, error)
  return data
}

async function rpcResult<T>(
  client: ContentSupabaseClient,
  operation: Operation,
  rpcName: string,
  params: Record<string, unknown>,
  schema: z.ZodType<T>,
): Promise<T> {
  const { data, error } = await client.rpc(rpcName, params)
  if (error) databaseFailure(operation, error)
  return parseDatabase(schema, data, operation)
}

function mapSummaryVersion(row: z.infer<typeof versionSummaryRowSchema>) {
  return {
    versionId: row.id,
    version: row.version,
    locale: row.locale,
    category: row.category,
    title: row.title,
    state: row.state,
    featuredToday: row.featured_today,
    authorId: row.authored_by,
    reviewerId: row.reviewed_by,
    publishAt: row.publish_at,
    updatedAt: row.updated_at,
  }
}

type PublicationListRow = z.infer<typeof publicationListRowSchema>

function mapPublicationListRow(row: PublicationListRow) {
  return {
    publicationId: row.id,
    slug: row.slug,
    archivedAt: row.archived_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    versions: [...row.pt_versions, ...row.en_versions].map(mapSummaryVersion),
  }
}

function boundListVersionEmbeds(query: ContentQueryBuilder): ContentQueryBuilder {
  return query
    .eq('pt_versions.locale', 'pt-BR')
    .order('version', { ascending: false, referencedTable: 'pt_versions' })
    .limit(1, { referencedTable: 'pt_versions' })
    .eq('en_versions.locale', 'en-US')
    .order('version', { ascending: false, referencedTable: 'en_versions' })
    .limit(1, { referencedTable: 'en_versions' })
}

function uniqueIds(values: Array<string | null>): string[] {
  return [...new Set(values.filter((value): value is string => value !== null))]
}

function createRepository(client: ContentSupabaseClient): ContentAdminRepository {
  async function listWithMetadata(filters: ContentAdminFilters) {
    const hasVersionFilter = hasAdminListVersionFilters(filters)
    if (!hasVersionFilter) {
      let query = boundListVersionEmbeds(
        client
          .from('content_publications')
          .select(LIST_SELECTION)
          .order('updated_at', { ascending: false })
          .order('id', { ascending: true })
          .range(filters.offset, filters.offset + filters.limit - 1),
      )
      query =
        filters.status === 'archived'
          ? query.not('archived_at', 'is', null)
          : query.is('archived_at', null)
      const rows = parseDatabase(
        z.array(publicationListRowSchema),
        await queryResult(query, 'list'),
        'list',
      )
      return {
        publications: rows.map(mapPublicationListRow),
        exhausted: rows.length < filters.limit,
        truncated: false,
      }
    }

    const now = Date.now()
    const matchingRows = []
    const requiredMatches = filters.offset + filters.limit

    for (let rawOffset = 0; rawOffset <= LIST_SCAN_MAX_OFFSET; rawOffset += LIST_SCAN_BATCH_SIZE) {
      let query = boundListVersionEmbeds(
        client
          .from('content_publications')
          .select(LIST_SELECTION)
          .order('updated_at', { ascending: false })
          .order('id', { ascending: true })
          .range(rawOffset, rawOffset + LIST_SCAN_BATCH_SIZE - 1),
      )
      query =
        filters.status === 'archived'
          ? query.not('archived_at', 'is', null)
          : query.is('archived_at', null)
      const rows = parseDatabase(
        z.array(publicationListRowSchema),
        await queryResult(query, 'list'),
        'list',
      )

      const matchingBatch = filterAdminListPublications(
        rows.map(mapPublicationListRow),
        filters,
        now,
      )
      for (const row of matchingBatch) {
        matchingRows.push(row)
        if (matchingRows.length >= requiredMatches) {
          return {
            publications: matchingRows.slice(filters.offset, requiredMatches),
            exhausted: false,
            truncated: false,
          }
        }
      }
      if (rows.length < LIST_SCAN_BATCH_SIZE) {
        return {
          publications: matchingRows.slice(filters.offset, requiredMatches),
          exhausted: true,
          truncated: false,
        }
      }
    }

    return {
      publications: matchingRows.slice(filters.offset, requiredMatches),
      exhausted: false,
      truncated: true,
    }
  }

  return {
    async list(filters: ContentAdminFilters) {
      return (await listWithMetadata(filters)).publications
    },

    listWithMetadata,

    async getVersionValidationSnapshot(versionId, expectedUpdatedAt) {
      let query = client
        .from('content_versions')
        .select(VERSION_VALIDATION_SNAPSHOT_SELECTION)
        .eq('id', versionId)
      if (expectedUpdatedAt !== undefined) {
        query = query.eq('updated_at', expectedUpdatedAt)
      }
      const data = await queryResult(
        query.maybeSingle(),
        'getVersionValidationSnapshot',
      )
      if (data === null) return null
      const row = parseDatabase(
        versionValidationSnapshotRowSchema,
        data,
        'getVersionValidationSnapshot',
      )
      return {
        versionId: row.id,
        publicationId: row.publication_id,
        locale: row.locale,
        state: row.state,
        bodyMarkdown: row.body_markdown,
        updatedAt: row.updated_at,
        publishAt: row.publish_at,
      }
    },

    async get(publicationId: string) {
      const publicationData = await queryResult(
        client
          .from('content_publications')
          .select(PUBLICATION_SELECTION)
          .eq('id', publicationId)
          .maybeSingle(),
        'get',
      )
      if (publicationData === null) return null
      const publication = parseDatabase(publicationDetailRowSchema, publicationData, 'get')
      const versionRows = parseDatabase(
        z.array(versionDetailRowSchema),
        await queryResult(
          client
            .from('content_versions')
            .select(VERSION_SELECTION)
            .eq('publication_id', publicationId)
            .order('version', { ascending: false })
            .limit(DETAIL_VERSION_LIMIT + 1),
          'get',
        ),
        'get',
      )
      const localeAnchorRows = (
        await Promise.all(
          (['pt-BR', 'en-US'] as const).map(async (locale) =>
            parseDatabase(
              z.array(versionDetailRowSchema),
              await queryResult(
                client
                  .from('content_versions')
                  .select(VERSION_SELECTION)
                  .eq('publication_id', publicationId)
                  .eq('locale', locale)
                  .order('version', { ascending: false })
                  .limit(1),
                'get',
              ),
              'get',
            ),
          ),
        )
      ).flat()
      const versionsById = new Map<string, z.infer<typeof versionDetailRowSchema>>()
      for (const version of localeAnchorRows) versionsById.set(version.id, version)
      for (const version of versionRows) {
        if (versionsById.size >= DETAIL_VERSION_LIMIT) break
        versionsById.set(version.id, version)
      }
      const versions = [...versionsById.values()].sort(
        (left, right) => right.version - left.version || left.id.localeCompare(right.id),
      )
      const availableVersionIds = new Set([
        ...versionRows.map((version) => version.id),
        ...localeAnchorRows.map((version) => version.id),
      ])
      const historyTruncated =
        versionRows.length > DETAIL_VERSION_LIMIT || availableVersionIds.size > versions.length
      const versionIds = versions.map((version) => version.id)
      const coverIds = uniqueIds(versions.map((version) => version.cover_asset_id))
      const identityIds = uniqueIds([
        publication.created_by,
        publication.archived_by,
        ...versions.flatMap((version) => [
          version.authored_by,
          version.reviewed_by,
          version.published_by,
        ]),
      ])

      const emptyResult: SupabaseResult = { data: [], error: null }
      const [protocolData, planData, personalityData, assetData, identityData] = await Promise.all([
        versionIds.length
          ? queryResult(
              client
                .from('content_version_target_protocols')
                .select('content_version_id, protocol')
                .in('content_version_id', versionIds),
              'get',
            )
          : emptyResult.data,
        versionIds.length
          ? queryResult(
              client
                .from('content_version_target_plans')
                .select('content_version_id, plan')
                .in('content_version_id', versionIds),
              'get',
            )
          : emptyResult.data,
        versionIds.length
          ? queryResult(
              client
                .from('content_version_target_personalities')
                .select('content_version_id, personality_code')
                .in('content_version_id', versionIds),
              'get',
            )
          : emptyResult.data,
        coverIds.length
          ? queryResult(
              client.from('content_assets').select(SAFE_ASSET_SELECTION).in('id', coverIds),
              'get',
            )
          : emptyResult.data,
        queryResult(
          client.from('admin_users').select('id, name, role').in('id', identityIds),
          'get',
        ),
      ])
      const protocols = parseDatabase(z.array(protocolTargetRowSchema), protocolData, 'get')
      const plans = parseDatabase(z.array(planTargetRowSchema), planData, 'get')
      const personalities = parseDatabase(
        z.array(personalityTargetRowSchema),
        personalityData,
        'get',
      )
      const assets = parseDatabase(z.array(safeAssetRowSchema), assetData, 'get')
      const identities = parseDatabase(z.array(adminIdentityRowSchema), identityData, 'get')
      const identityById = new Map(identities.map((identity) => [identity.id, identity]))
      const assetById = new Map(assets.map((asset) => [asset.id, asset]))
      const identity = (id: string | null) => {
        if (id === null) return null
        const row = identityById.get(id)
        if (!row) databaseFailure('get')
        return row
      }
      const requiredIdentity = (id: string) => {
        const row = identity(id)
        if (!row) databaseFailure('get')
        return row
      }

      return {
        publicationId: publication.id,
        slug: publication.slug,
        archivedAt: publication.archived_at,
        createdAt: publication.created_at,
        updatedAt: publication.updated_at,
        createdBy: requiredIdentity(publication.created_by),
        archivedBy: identity(publication.archived_by),
        historyTruncated,
        versions: versions.map((version) => {
          const cover = version.cover_asset_id ? assetById.get(version.cover_asset_id) : null
          if (version.cover_asset_id && !cover) databaseFailure('get')
          return {
            ...mapSummaryVersion(version),
            excerpt: version.excerpt,
            bodyMarkdown: version.body_markdown,
            bodyHash: version.body_hash,
            readingTimeMinutes: version.reading_time_minutes,
            tags: version.tags,
            cover: cover
              ? {
                  assetId: cover.id,
                  mimeType: cover.mime_type,
                  sizeBytes: cover.actual_size_bytes ?? cover.declared_size_bytes,
                  status: cover.status,
                }
              : null,
            targeting: {
              protocols: protocols
                .filter((target) => target.content_version_id === version.id)
                .map((target) => target.protocol),
              plans: plans
                .filter((target) => target.content_version_id === version.id)
                .map((target) => target.plan),
              personalities: personalities
                .filter((target) => target.content_version_id === version.id)
                .map((target) => target.personality_code),
            },
            author: requiredIdentity(version.authored_by),
            reviewer: identity(version.reviewed_by),
            publisher: identity(version.published_by),
            submittedAt: version.submitted_at,
            reviewedAt: version.reviewed_at,
            rejectionReason: version.rejection_reason,
            publishedAt: version.published_at,
          }
        }),
      }
    },

    async createPublication(input) {
      const row = await rpcResult(
        client,
        'createPublication',
        'create_content_publication',
        { p_actor_id: input.actorId, p_slug: input.slug },
        publicationResultSchema,
      )
      return { publicationId: row.publication_id, slug: row.slug, createdAt: row.created_at }
    },

    async createDraft(input) {
      const row = await rpcResult(
        client,
        'createDraft',
        'create_content_draft',
        {
          p_actor_id: input.actorId,
          p_publication_id: input.publicationId,
          p_locale: input.locale,
          p_source_version_id: input.sourceVersionId ?? null,
        },
        draftResultSchema,
      )
      return {
        publicationId: row.publication_id,
        versionId: row.version_id,
        version: row.version,
        locale: row.locale,
        state: row.state,
        updatedAt: row.updated_at,
      }
    },

    async saveDraft(input) {
      const row = await rpcResult(
        client,
        'saveDraft',
        'save_content_draft',
        {
          p_actor_id: input.actorId,
          p_version_id: input.versionId,
          p_expected_updated_at: input.expectedUpdatedAt,
          p_draft: input.draft,
        },
        savedResultSchema,
      )
      return {
        publicationId: row.publication_id,
        versionId: row.version_id,
        version: row.version,
        state: row.state,
        bodyHash: row.body_hash,
        readingTimeMinutes: row.reading_time_minutes,
        updatedAt: row.updated_at,
      }
    },

    async submit(input) {
      const row = await rpcResult(
        client,
        'submit',
        'submit_content_version',
        {
          p_actor_id: input.actorId,
          p_version_id: input.versionId,
          p_expected_updated_at: input.expectedUpdatedAt,
        },
        submittedResultSchema,
      )
      return {
        publicationId: row.publication_id,
        versionId: row.version_id,
        version: row.version,
        state: row.state,
        bodyHash: row.body_hash,
        updatedAt: row.updated_at,
      }
    },

    async review(input) {
      const row = await rpcResult(
        client,
        'review',
        'review_content_version',
        {
          p_actor_id: input.actorId,
          p_version_id: input.versionId,
          p_decision: input.decision,
          p_rejection_reason: input.rejectionReason,
        },
        reviewedResultSchema,
      )
      return {
        publicationId: row.publication_id,
        versionId: row.version_id,
        version: row.version,
        state: row.state,
        bodyHash: row.body_hash,
        reviewedAt: row.reviewed_at,
        updatedAt: row.updated_at,
      }
    },

    async publish(input) {
      const row = await rpcResult(
        client,
        'publish',
        'publish_content_version',
        {
          p_actor_id: input.actorId,
          p_version_id: input.versionId,
          p_publish_at: input.publishAt,
        },
        publishedResultSchema,
      )
      return {
        publicationId: row.publication_id,
        versionId: row.version_id,
        version: row.version,
        state: row.state,
        effectiveState: row.effective_state,
        publishAt: row.publish_at,
        bodyHash: row.body_hash,
        updatedAt: row.updated_at,
      }
    },

    async archive(input) {
      const row = await rpcResult(
        client,
        'archive',
        'archive_content_publication',
        { p_actor_id: input.actorId, p_publication_id: input.publicationId },
        archiveResultSchema,
      )
      return {
        outcome: row.outcome,
        publicationId: row.publication_id,
        archivedAt: row.archived_at,
      }
    },

    async createAsset(input) {
      const row = await rpcResult(
        client,
        'createAsset',
        'create_content_asset',
        {
          p_actor_id: input.actorId,
          p_asset_id: input.assetId,
          p_mime_type: input.mimeType,
          p_declared_size_bytes: input.declaredSizeBytes,
          p_object_path: input.objectPath,
        },
        createdAssetResultSchema,
      )
      return {
        assetId: row.asset_id,
        bucketId: row.bucket_id,
        objectPath: row.object_path,
        mimeType: row.mime_type,
        declaredSizeBytes: row.declared_size_bytes,
        status: row.status,
        createdAt: row.created_at,
      }
    },

    async getAssetInternal(assetId: string): Promise<InternalContentAsset | null> {
      const data = await queryResult(
        client
          .from('content_assets')
          .select(INTERNAL_ASSET_SELECTION)
          .eq('id', assetId)
          .maybeSingle(),
        'getAssetInternal',
      )
      if (data === null) return null
      const row = parseDatabase(internalAssetRowSchema, data, 'getAssetInternal')
      return {
        assetId: row.id,
        bucketId: row.bucket_id,
        objectPath: row.object_path,
        mimeType: row.mime_type,
        declaredSizeBytes: row.declared_size_bytes,
        actualSizeBytes: row.actual_size_bytes,
        etag: row.etag,
        status: row.status,
      }
    },

    async completeAsset(input) {
      const row = await rpcResult(
        client,
        'completeAsset',
        'complete_content_asset',
        {
          p_actor_id: input.actorId,
          p_asset_id: input.assetId,
          p_actual_size_bytes: input.actualSizeBytes,
          p_etag: input.etag,
        },
        completedAssetResultSchema,
      )
      return {
        assetId: row.asset_id,
        status: row.status,
        actualSizeBytes: row.actual_size_bytes,
        uploadedAt: row.uploaded_at,
        updatedAt: row.updated_at,
      }
    },

    async deleteAsset(input) {
      const row = await rpcResult(
        client,
        'deleteAsset',
        'delete_content_asset',
        {
          p_actor_id: input.actorId,
          p_asset_id: input.assetId,
          p_expected_status: input.expectedStatus,
        },
        deletedAssetResultSchema,
      )
      return {
        assetId: row.asset_id,
        status: row.status,
        deletedAt: row.deleted_at,
        ...(row.updated_at ? { updatedAt: row.updated_at } : {}),
      }
    },
  }
}

function storageStatus(error: unknown): number | null {
  if (typeof error !== 'object' || error === null) return null
  const candidate = error as { status?: unknown; statusCode?: unknown }
  const value = candidate.status ?? candidate.statusCode
  if (typeof value === 'number') return value
  if (typeof value === 'string' && /^\d+$/.test(value)) return Number(value)
  return null
}

function createStorage(client: ContentSupabaseClient): ContentAdminStorage {
  const bucket = () => client.storage.from('content-covers')
  return {
    async createSignedUpload(objectPath) {
      const { data, error } = await bucket().createSignedUploadUrl(objectPath, { upsert: false })
      if (error) throw new ContentStorageError('transient', 'create_upload')
      const parsed = z.object({ signedUrl: z.string().url() }).safeParse(data)
      if (!parsed.success) throw new ContentStorageError('transient', 'create_upload')
      return { signedUrl: parsed.data.signedUrl }
    },

    async getObjectInfo(objectPath) {
      const { data, error } = await bucket().info(objectPath)
      if (error) {
        const status = storageStatus(error)
        throw new ContentStorageError(status === 404 ? 'missing' : 'transient', 'info')
      }
      const parsed = z
        .object({
          size: z.number().int().nonnegative(),
          contentType: z.string().nullable().optional(),
          etag: z.string().nullable().optional(),
        })
        .safeParse(data)
      if (!parsed.success) throw new ContentStorageError('transient', 'info')
      return {
        size: parsed.data.size,
        contentType: parsed.data.contentType ?? null,
        etag: parsed.data.etag ?? null,
      }
    },

    async remove(objectPath) {
      const { error } = await bucket().remove([objectPath])
      if (!error) return
      const status = storageStatus(error)
      if (status === 404) return
      throw new ContentStorageError('transient', 'remove')
    },
  }
}

export function createSupabaseContentAdminDependencies(client: ContentSupabaseClient): {
  repository: ContentAdminRepository
  storage: ContentAdminStorage
} {
  return { repository: createRepository(client), storage: createStorage(client) }
}
