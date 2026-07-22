import { randomUUID } from 'node:crypto'
import {
  type ContentDraftInput,
  contentCategorySchema,
  contentCoverInputSchema,
  contentDraftInputSchema,
  contentLocaleSchema,
} from '@mpp/core'
import { z } from 'zod'

const adminIdentitySchema = z.object({
  id: z.string().uuid(),
  name: z.string().nullable(),
  role: z.enum([
    'support',
    'content_editor',
    'nutrition_admin',
    'operations_admin',
    'master_admin',
  ]),
})

const timestampSchema = z.string().datetime({ offset: true })
const nullableTimestampSchema = timestampSchema.nullable()
const contentStateSchema = z.enum(['draft', 'in_review', 'approved', 'rejected'])
const assetStatusSchema = z.enum(['pending_upload', 'uploaded', 'deleted'])
const uuidSchema = z.string().uuid()

const versionSummarySchema = z.object({
  versionId: uuidSchema,
  version: z.number().int().positive(),
  locale: contentLocaleSchema,
  category: contentCategorySchema.nullable(),
  title: z.string().nullable(),
  state: contentStateSchema,
  featuredToday: z.boolean(),
  authorId: uuidSchema,
  reviewerId: uuidSchema.nullable(),
  publishAt: nullableTimestampSchema,
  updatedAt: timestampSchema,
})

const publicationSummarySchema = z.object({
  publicationId: uuidSchema,
  slug: z.string(),
  archivedAt: nullableTimestampSchema,
  createdAt: timestampSchema,
  updatedAt: timestampSchema,
  matchedVersionId: uuidSchema.nullable().optional(),
  versions: z.array(versionSummarySchema),
})

const safeAssetSchema = z.object({
  assetId: uuidSchema,
  mimeType: z.enum(['image/jpeg', 'image/png', 'image/webp']),
  sizeBytes: z
    .number()
    .int()
    .min(1)
    .max(10 * 1024 * 1024),
  status: assetStatusSchema,
})

const versionDetailSchema = versionSummarySchema.extend({
  excerpt: z.string().nullable(),
  bodyMarkdown: z.string().nullable(),
  bodyHash: z
    .string()
    .regex(/^[0-9a-f]{64}$/)
    .nullable(),
  readingTimeMinutes: z.number().int().positive().nullable(),
  tags: z.array(z.string()),
  cover: safeAssetSchema.nullable(),
  targeting: z.object({
    protocols: z.array(z.enum(['recomposicao', 'ganho_massa', 'manutencao'])),
    plans: z.array(z.enum(['trial', 'mensal', 'anual'])),
    personalities: z.array(z.enum(['focus', 'impulse', 'zen'])),
  }),
  author: adminIdentitySchema,
  reviewer: adminIdentitySchema.nullable(),
  publisher: adminIdentitySchema.nullable(),
  submittedAt: nullableTimestampSchema,
  reviewedAt: nullableTimestampSchema,
  rejectionReason: z.string().nullable(),
  publishedAt: nullableTimestampSchema,
})

const publicationDetailSchema = publicationSummarySchema.omit({ versions: true }).extend({
  createdBy: adminIdentitySchema,
  archivedBy: adminIdentitySchema.nullable(),
  historyTruncated: z.boolean().default(false),
  versions: z.array(versionDetailSchema),
})

const contentAdminFiltersSchema = z
  .object({
    status: z
      .enum(['draft', 'in_review', 'approved', 'rejected', 'scheduled', 'published', 'archived'])
      .optional(),
    locale: contentLocaleSchema.optional(),
    category: contentCategorySchema.optional(),
    authorId: uuidSchema.optional(),
    reviewerId: uuidSchema.optional(),
    schedule: z.enum(['unscheduled', 'scheduled', 'published']).optional(),
    featuredToday: z.boolean().optional(),
    limit: z.number().int().min(1).max(100).default(50),
    offset: z.number().int().min(0).max(10_000).default(0),
  })
  .strict()

const createPublicationSchema = z.object({
  actorId: uuidSchema,
  slug: z
    .string()
    .min(3)
    .max(120)
    .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
})
const createDraftSchema = z
  .object({
    actorId: uuidSchema,
    publicationId: uuidSchema,
    locale: contentLocaleSchema,
    sourceVersionId: uuidSchema.optional(),
  })
  .strict()
const saveDraftSchema = z
  .object({
    actorId: uuidSchema,
    versionId: uuidSchema,
    expectedUpdatedAt: timestampSchema,
    draft: contentDraftInputSchema,
  })
  .strict()
const preconditionSchema = z
  .object({ actorId: uuidSchema, versionId: uuidSchema, expectedUpdatedAt: timestampSchema })
  .strict()
const reviewSchema = z
  .object({
    actorId: uuidSchema,
    versionId: uuidSchema,
    decision: z.enum(['approve', 'reject']),
    rejectionReason: z.string().trim().min(10).max(1000).nullable().optional(),
  })
  .strict()
  .superRefine((value, context) => {
    if (value.decision === 'reject' && !value.rejectionReason) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: 'Rejection reason is required.' })
    }
    if (value.decision === 'approve' && value.rejectionReason != null) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'Approval has no rejection reason.',
      })
    }
  })
const publishSchema = z
  .object({ actorId: uuidSchema, versionId: uuidSchema, publishAt: timestampSchema.nullable() })
  .strict()
const archiveSchema = z.object({ actorId: uuidSchema, publicationId: uuidSchema }).strict()
const assetCommandSchema = z.object({ actorId: uuidSchema, assetId: uuidSchema }).strict()

export type ContentAdminErrorCode =
  | 'validation'
  | 'stale'
  | 'duplicate'
  | 'not_found'
  | 'denied'
  | 'lifecycle'
  | 'cover_referenced'
  | 'cover_mismatch'
  | 'storage_unavailable'
  | 'database_unavailable'

export class ContentAdminError extends Error {
  constructor(
    readonly code: ContentAdminErrorCode,
    readonly operation: string,
  ) {
    super(`Content admin operation failed: ${code}`)
    this.name = 'ContentAdminError'
  }
}

export class ContentStorageError extends Error {
  constructor(
    readonly kind: 'missing' | 'transient',
    readonly operation: 'create_upload' | 'info' | 'remove',
  ) {
    super(`Content storage operation failed: ${kind}`)
    this.name = 'ContentStorageError'
  }
}

export type ContentAdminFilters = z.infer<typeof contentAdminFiltersSchema>
export type ContentPublicationSummary = z.infer<typeof publicationSummarySchema>
export type ContentPublicationDetail = z.infer<typeof publicationDetailSchema>
export type SafeContentAsset = z.infer<typeof safeAssetSchema>
export interface ContentPublicationListResult {
  publications: ContentPublicationSummary[]
  exhausted: boolean
  truncated: boolean
}

export interface InternalContentAsset {
  assetId: string
  bucketId: 'content-covers'
  objectPath: string
  mimeType: 'image/jpeg' | 'image/png' | 'image/webp'
  declaredSizeBytes: number
  actualSizeBytes: number | null
  etag: string | null
  status: 'pending_upload' | 'uploaded' | 'deleted'
}

export interface ContentAdminRepository {
  list(filters: ContentAdminFilters): Promise<ContentPublicationSummary[]>
  listWithMetadata?(filters: ContentAdminFilters): Promise<ContentPublicationListResult>
  get(publicationId: string): Promise<ContentPublicationDetail | null>
  createPublication(input: { actorId: string; slug: string }): Promise<unknown>
  createDraft(input: {
    actorId: string
    publicationId: string
    locale: 'pt-BR' | 'en-US'
    sourceVersionId?: string
  }): Promise<unknown>
  saveDraft(input: {
    actorId: string
    versionId: string
    expectedUpdatedAt: string
    draft: ContentDraftInput
  }): Promise<unknown>
  submit(input: { actorId: string; versionId: string; expectedUpdatedAt: string }): Promise<unknown>
  review(input: {
    actorId: string
    versionId: string
    decision: 'approve' | 'reject'
    rejectionReason: string | null
  }): Promise<unknown>
  publish(input: { actorId: string; versionId: string; publishAt: string | null }): Promise<unknown>
  archive(input: { actorId: string; publicationId: string }): Promise<unknown>
  createAsset(input: {
    actorId: string
    assetId: string
    mimeType: 'image/jpeg' | 'image/png' | 'image/webp'
    declaredSizeBytes: number
    objectPath: string
  }): Promise<{
    assetId: string
    bucketId: 'content-covers'
    objectPath: string
    mimeType: 'image/jpeg' | 'image/png' | 'image/webp'
    declaredSizeBytes: number
    status: 'pending_upload'
    createdAt: string
  }>
  getAssetInternal(assetId: string): Promise<InternalContentAsset | null>
  completeAsset(input: {
    actorId: string
    assetId: string
    actualSizeBytes: number
    etag: string
  }): Promise<unknown>
  deleteAsset(input: {
    actorId: string
    assetId: string
    expectedStatus: InternalContentAsset['status']
  }): Promise<unknown>
}

export interface ContentAdminStorage {
  createSignedUpload(objectPath: string): Promise<{ signedUrl: string }>
  getObjectInfo(objectPath: string): Promise<{
    size: number
    contentType: string | null
    etag: string | null
  }>
  remove(objectPath: string): Promise<void>
}

export interface ContentAdminServiceDependencies {
  repository: ContentAdminRepository
  storage: ContentAdminStorage
  generateUuid?: () => string
}

function validationFailure(operation: string): ContentAdminError {
  return new ContentAdminError('validation', operation)
}

function parseInput<T>(schema: z.ZodType<T>, value: unknown, operation: string): T {
  const parsed = schema.safeParse(value)
  if (!parsed.success) throw validationFailure(operation)
  return parsed.data
}

function extensionFor(mimeType: 'image/jpeg' | 'image/png' | 'image/webp'): string {
  if (mimeType === 'image/jpeg') return 'jpg'
  if (mimeType === 'image/png') return 'png'
  return 'webp'
}

function storageFailure(error: unknown, operation: string): ContentAdminError {
  if (error instanceof ContentAdminError) return error
  return new ContentAdminError('storage_unavailable', operation)
}

function safeAsset(asset: InternalContentAsset): SafeContentAsset {
  return safeAssetSchema.parse({
    assetId: asset.assetId,
    mimeType: asset.mimeType,
    sizeBytes: asset.actualSizeBytes ?? asset.declaredSizeBytes,
    status: asset.status,
  })
}

export function createContentAdminService(dependencies: ContentAdminServiceDependencies) {
  const { repository, storage } = dependencies
  const generateUuid = dependencies.generateUuid ?? randomUUID

  async function loadAsset(assetId: string, operation: string): Promise<InternalContentAsset> {
    const asset = await repository.getAssetInternal(assetId)
    if (!asset) throw new ContentAdminError('not_found', operation)
    if (asset.bucketId !== 'content-covers') throw new ContentAdminError('lifecycle', operation)
    return asset
  }

  async function cleanupAsset(actorId: string, asset: InternalContentAsset): Promise<void> {
    await repository.deleteAsset({
      actorId,
      assetId: asset.assetId,
      expectedStatus: asset.status,
    })
    try {
      await storage.remove(asset.objectPath)
    } catch (error) {
      if (!(error instanceof ContentStorageError && error.kind === 'missing')) {
        throw storageFailure(error, 'deleteCover')
      }
    }
  }

  return {
    async list(input: unknown): Promise<ContentPublicationListResult> {
      const filters = parseInput(
        contentAdminFiltersSchema as z.ZodType<ContentAdminFilters>,
        input,
        'list',
      )
      const result = repository.listWithMetadata
        ? await repository.listWithMetadata(filters)
        : { publications: await repository.list(filters), exhausted: false, truncated: false }
      return {
        publications: z.array(publicationSummarySchema).parse(result.publications),
        exhausted: result.exhausted,
        truncated: result.truncated,
      }
    },

    async get(input: unknown): Promise<ContentPublicationDetail | null> {
      const parsed = parseInput(z.object({ publicationId: uuidSchema }).strict(), input, 'get')
      const row = await repository.get(parsed.publicationId)
      return row === null ? null : publicationDetailSchema.parse(row)
    },

    async createPublication(input: unknown) {
      return repository.createPublication(
        parseInput(createPublicationSchema, input, 'createPublication'),
      )
    },

    async createDraft(input: unknown) {
      return repository.createDraft(parseInput(createDraftSchema, input, 'createDraft'))
    },

    async saveDraft(input: unknown) {
      return repository.saveDraft(parseInput(saveDraftSchema, input, 'saveDraft'))
    },

    async submit(input: unknown) {
      return repository.submit(parseInput(preconditionSchema, input, 'submit'))
    },

    async review(input: unknown) {
      const parsed = parseInput(reviewSchema, input, 'review')
      return repository.review({
        ...parsed,
        rejectionReason: parsed.rejectionReason ?? null,
      })
    },

    async publish(input: unknown) {
      return repository.publish(parseInput(publishSchema, input, 'publish'))
    },

    async archive(input: unknown) {
      return repository.archive(parseInput(archiveSchema, input, 'archive'))
    },

    async createCover(input: unknown): Promise<{
      asset: SafeContentAsset
      upload: { signedUrl: string }
    }> {
      const command = parseInput(
        z.object({ actorId: uuidSchema }).merge(contentCoverInputSchema).strict(),
        input,
        'createCover',
      )
      const assetId = parseInput(uuidSchema, generateUuid(), 'createCover')
      const objectPath = `content/${assetId}.${extensionFor(command.mimeType)}`
      const created = await repository.createAsset({
        actorId: command.actorId,
        assetId,
        mimeType: command.mimeType,
        declaredSizeBytes: command.sizeBytes,
        objectPath,
      })
      const internal: InternalContentAsset = {
        assetId,
        bucketId: 'content-covers',
        objectPath,
        mimeType: command.mimeType,
        declaredSizeBytes: command.sizeBytes,
        actualSizeBytes: null,
        etag: null,
        status: created.status,
      }

      try {
        const upload = await storage.createSignedUpload(objectPath)
        const capability = parseInput(
          z.object({ signedUrl: z.string().url() }),
          upload,
          'createCover',
        )
        return { asset: safeAsset(internal), upload: capability }
      } catch (error) {
        try {
          await cleanupAsset(command.actorId, internal)
        } catch {
          throw new ContentAdminError('storage_unavailable', 'createCover')
        }
        throw storageFailure(error, 'createCover')
      }
    },

    async completeCover(input: unknown): Promise<SafeContentAsset> {
      const command = parseInput(assetCommandSchema, input, 'completeCover')
      const asset = await loadAsset(command.assetId, 'completeCover')
      if (asset.status === 'uploaded') return safeAsset(asset)
      if (asset.status !== 'pending_upload') {
        throw new ContentAdminError('lifecycle', 'completeCover')
      }

      let info: Awaited<ReturnType<ContentAdminStorage['getObjectInfo']>>
      try {
        info = await storage.getObjectInfo(asset.objectPath)
      } catch (error) {
        if (error instanceof ContentStorageError && error.kind === 'missing') {
          await cleanupAsset(command.actorId, asset)
          throw new ContentAdminError('cover_mismatch', 'completeCover')
        }
        throw storageFailure(error, 'completeCover')
      }

      const etag = info.etag
      const mismatch =
        info.size !== asset.declaredSizeBytes ||
        info.contentType !== asset.mimeType ||
        typeof etag !== 'string' ||
        etag.trim().length < 1 ||
        etag.length > 512
      if (mismatch) {
        await cleanupAsset(command.actorId, asset)
        throw new ContentAdminError('cover_mismatch', 'completeCover')
      }

      try {
        await repository.completeAsset({
          actorId: command.actorId,
          assetId: asset.assetId,
          actualSizeBytes: info.size,
          etag,
        })
      } catch (error) {
        if (error instanceof ContentAdminError && error.code === 'cover_mismatch') {
          const current = await repository.getAssetInternal(asset.assetId)
          if (!current || current.bucketId !== 'content-covers') {
            throw new ContentAdminError('lifecycle', 'completeCover')
          }
          if (current.status === 'uploaded') return safeAsset(current)
          if (current.status === 'pending_upload') {
            await cleanupAsset(command.actorId, current)
            throw new ContentAdminError('cover_mismatch', 'completeCover')
          }
          throw new ContentAdminError('lifecycle', 'completeCover')
        }
        throw error
      }
      return safeAsset({
        ...asset,
        actualSizeBytes: info.size,
        etag,
        status: 'uploaded',
      })
    },

    async deleteCover(input: unknown): Promise<SafeContentAsset> {
      const command = parseInput(assetCommandSchema, input, 'deleteCover')
      const asset = await loadAsset(command.assetId, 'deleteCover')
      await cleanupAsset(command.actorId, asset)
      return safeAsset({ ...asset, status: 'deleted' })
    },
  }
}

export type ContentAdminService = ReturnType<typeof createContentAdminService>
