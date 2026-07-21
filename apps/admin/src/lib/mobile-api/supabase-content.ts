import {
  type ContentListQuery,
  contentCategorySchema,
  contentLocaleSchema,
  decodeContentCursor,
  encodeContentCursor,
} from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type ContentCoverCapabilityCodec,
  createDefaultContentCoverCapabilityCodec,
} from './content-cover-capability'
import {
  type ContentRepository,
  ContentRepositoryError,
  type ContentServiceDependencies,
} from './content-service'

const CONTENT_COVERS_BUCKET = 'content-covers'

const coverReferenceSchema = z
  .object({
    bucketId: z.literal(CONTENT_COVERS_BUCKET),
    objectPath: z.string().min(1),
  })
  .strict()

const cursorTupleSchema = z
  .object({
    publishAt: z.string().datetime({ offset: true }),
    publicationId: z.string().uuid(),
  })
  .strict()

const contentTagSchema = z
  .string()
  .min(1)
  .max(40)
  .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)

const feedItemSchema = z
  .object({
    publicationId: z.string().uuid(),
    slug: z
      .string()
      .min(3)
      .max(120)
      .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
    locale: contentLocaleSchema,
    title: z.string().min(3).max(120),
    excerpt: z.string().min(20).max(280),
    category: contentCategorySchema,
    tags: z
      .array(contentTagSchema)
      .max(20)
      .refine((tags) => new Set(tags).size === tags.length),
    readingTimeMinutes: z.number().int().positive(),
    publishAt: z.string().datetime({ offset: true }),
    featuredToday: z.boolean(),
    version: z.number().int().positive(),
    saved: z.boolean(),
    completed: z.boolean(),
    cover: coverReferenceSchema.nullable(),
  })
  .strict()

const detailSchema = feedItemSchema
  .extend({
    bodyMarkdown: z.string().min(100).max(50_000),
  })
  .strict()

const feedPageSchema = z
  .object({
    items: z.array(feedItemSchema),
    nextCursor: cursorTupleSchema.nullable(),
  })
  .strict()

const userStateSchema = z
  .object({
    publicationId: z.string().uuid(),
    version: z.number().int().positive(),
    saved: z.boolean(),
    completed: z.boolean(),
    changed: z.boolean(),
    replayed: z.boolean(),
  })
  .strict()

type RpcResult = Promise<{
  data: unknown
  error: { code?: string; message?: string } | null
}>

type UntypedRpc = (functionName: string, params: Record<string, unknown>) => RpcResult

function safeErrorCode(code: string | undefined): string {
  return code && /^[A-Za-z0-9_]{1,32}$/.test(code) ? code : 'unknown_error'
}

function operationFailure(
  operation: string,
  error?: { code?: string } | null,
  publicationId?: string,
): never {
  const repositoryCode = error?.code ?? 'invalid_response'
  console.error('[mobile-content] operation_failed', {
    operation,
    ...(publicationId ? { publication_id: publicationId } : {}),
    error_code: safeErrorCode(repositoryCode),
  })

  if (repositoryCode === 'P0002') throw new ContentRepositoryError('not_found')
  if (repositoryCode === '40001') throw new ContentRepositoryError('version_changed')
  throw new ContentRepositoryError('internal')
}

function parseResult<T>(
  schema: z.ZodType<T>,
  value: unknown,
  operation: string,
  publicationId?: string,
): T {
  const parsed = schema.safeParse(value)
  if (!parsed.success) operationFailure(operation, null, publicationId)
  return parsed.data
}

function decodeCursor(query: ContentListQuery) {
  if (!query.cursor) return null
  try {
    return decodeContentCursor(query.cursor)
  } catch {
    throw new ContentRepositoryError('invalid_cursor')
  }
}

function createRepository(supabase: ServiceClient): ContentRepository {
  const rpc = supabase.rpc.bind(supabase) as unknown as UntypedRpc

  return {
    async list(userId, query) {
      const cursor = decodeCursor(query)
      const { data, error } = await rpc('list_mobile_content', {
        p_user_id: userId,
        p_surface: query.surface,
        p_category: query.category ?? null,
        p_limit: query.limit,
        p_cursor_publish_at: cursor?.publishAt ?? null,
        p_cursor_publication_id: cursor?.publicationId ?? null,
      })
      if (error) operationFailure('list', error)
      const page = parseResult(feedPageSchema, data, 'parse_list')
      return {
        items: page.items,
        nextCursor: page.nextCursor ? encodeContentCursor(page.nextCursor) : null,
      }
    },

    async get(userId, publicationId) {
      const { data, error } = await rpc('get_mobile_content', {
        p_user_id: userId,
        p_publication_id: publicationId,
      })
      if (error?.code === 'P0002') return null
      if (error) operationFailure('get', error, publicationId)
      if (data === null) return null
      return parseResult(detailSchema, data, 'parse_detail', publicationId)
    },

    async recordRead(input) {
      const { data, error } = await rpc('record_mobile_content_event', {
        p_user_id: input.userId,
        p_publication_id: input.publicationId,
        p_version: input.version,
        p_event_type: input.event,
        p_origin: input.origin,
        p_event_key: input.idempotencyKey,
      })
      if (error) operationFailure('record_read', error, input.publicationId)
      return parseResult(userStateSchema, data, 'parse_read_state', input.publicationId)
    },

    async setSaved(input) {
      const { data, error } = await rpc('set_mobile_content_saved', {
        p_user_id: input.userId,
        p_publication_id: input.publicationId,
        p_version: input.version,
        p_saved: input.saved,
        p_origin: input.origin,
        p_event_key: input.idempotencyKey,
      })
      if (error) operationFailure('set_saved', error, input.publicationId)
      return parseResult(userStateSchema, data, 'parse_saved_state', input.publicationId)
    },
  }
}

function createCoverGateway(
  injectedCapabilities?: Pick<ContentCoverCapabilityCodec, 'issue'>,
): ContentServiceDependencies['covers'] {
  return {
    async issue(input) {
      const capabilities = injectedCapabilities ?? createDefaultContentCoverCapabilityCodec()
      return capabilities.issue(input)
    },
  }
}

export function createSupabaseContentDependencies(
  supabase: ServiceClient,
  options: { coverCapabilities?: Pick<ContentCoverCapabilityCodec, 'issue'> } = {},
): ContentServiceDependencies {
  return {
    repository: createRepository(supabase),
    covers: createCoverGateway(options.coverCapabilities),
  }
}
