import { fromMarkdown } from 'mdast-util-from-markdown'
import { gfmTableFromMarkdown } from 'mdast-util-gfm-table'
import { toMarkdown } from 'mdast-util-to-markdown'
import { gfmTable } from 'micromark-extension-gfm-table'
import { z } from 'zod'

const MAX_CONTENT_BODY_LENGTH = 50_000
const MIN_CONTENT_BODY_LENGTH = 100
const MAX_CONTENT_DEPTH = 8
const MAX_COVER_SIZE_BYTES = 10 * 1024 * 1024
const MAX_CONTENT_CURSOR_LENGTH = 512
export const MAX_CONTENT_VERSION = 2_147_483_647

export const contentLocaleSchema = z.enum(['pt-BR', 'en-US'])
export const contentCategorySchema = z.enum([
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
export const contentSurfaceSchema = z.enum(['today', 'library', 'saved'])
export const contentOriginSchema = z.enum(['today', 'library', 'push'])
export const contentReadEventSchema = z.enum(['impression', 'opened', 'completed'])

const contentProtocolSchema = z.enum(['recomposicao', 'ganho_massa', 'manutencao'])
const contentPlanSchema = z.enum(['trial', 'mensal', 'anual'])
const contentPersonalitySchema = z.enum(['focus', 'impulse', 'zen'])
export const contentVersionSchema = z.number().int().min(1).max(MAX_CONTENT_VERSION)

export interface ContentDraftInput {
  locale: z.infer<typeof contentLocaleSchema>
  category: z.infer<typeof contentCategorySchema>
  title: string
  excerpt: string
  bodyMarkdown: string
  tags: string[]
  featuredToday: boolean
  coverAssetId: string | null
  targeting: {
    protocols: z.infer<typeof contentProtocolSchema>[]
    plans: z.infer<typeof contentPlanSchema>[]
    personalities: z.infer<typeof contentPersonalitySchema>[]
  }
}

export interface ContentListQuery {
  surface: z.infer<typeof contentSurfaceSchema>
  category?: z.infer<typeof contentCategorySchema>
  limit: number
  cursor?: string
}

export interface ContentReadInput {
  event: z.infer<typeof contentReadEventSchema>
  origin: z.infer<typeof contentOriginSchema>
  version: number
}

export interface ContentSaveInput {
  saved: boolean
  version: number
}

export interface ContentCoverInput {
  mimeType: 'image/jpeg' | 'image/png' | 'image/webp'
  sizeBytes: number
}

function normalizeTag(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

const contentTagSchema = z
  .string()
  .trim()
  .min(1)
  .transform(normalizeTag)
  .pipe(
    z
      .string()
      .min(1)
      .max(40)
      .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
  )

function uniqueValues<T>(values: T[], context: z.RefinementCtx): void {
  if (new Set(values).size !== values.length) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'Values must be unique.' })
  }
}

const contentTargetingSchema = z
  .object({
    protocols: z.array(contentProtocolSchema).max(3),
    plans: z.array(contentPlanSchema).max(3),
    personalities: z.array(contentPersonalitySchema).max(3),
  })
  .strict()
  .superRefine((value, context) => {
    uniqueValues(value.protocols, context)
    uniqueValues(value.plans, context)
    uniqueValues(value.personalities, context)
  })

const contentMarkdownSchema = z.string().transform((value, context) => {
  try {
    return validateContentMarkdown(value).normalized
  } catch (error) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: error instanceof Error ? error.message : 'Invalid content Markdown',
    })
    return z.NEVER
  }
})

export const contentDraftInputSchema = z
  .object({
    locale: contentLocaleSchema,
    category: contentCategorySchema,
    title: z.string().trim().min(3).max(120),
    excerpt: z.string().trim().min(20).max(280),
    bodyMarkdown: contentMarkdownSchema,
    tags: z.array(contentTagSchema).max(20),
    featuredToday: z.boolean(),
    coverAssetId: z.string().uuid().nullable(),
    targeting: contentTargetingSchema,
  })
  .strict()
  .superRefine((value, context) =>
    uniqueValues(value.tags, context),
  ) satisfies z.ZodType<ContentDraftInput>

export const contentListQuerySchema = z
  .object({
    surface: contentSurfaceSchema.default('library'),
    category: contentCategorySchema.optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
    cursor: z.string().min(1).max(512).optional(),
  })
  .strict() satisfies z.ZodType<ContentListQuery, z.ZodTypeDef, unknown>

export const contentReadInputSchema = z
  .object({
    event: contentReadEventSchema,
    origin: contentOriginSchema,
    version: contentVersionSchema,
  })
  .strict() satisfies z.ZodType<ContentReadInput>

export const contentSaveInputSchema = z
  .object({
    saved: z.boolean(),
    version: contentVersionSchema,
  })
  .strict() satisfies z.ZodType<ContentSaveInput>

export const contentCoverInputSchema = z
  .object({
    mimeType: z.enum(['image/jpeg', 'image/png', 'image/webp']),
    sizeBytes: z.number().int().min(1).max(MAX_COVER_SIZE_BYTES),
  })
  .strict() satisfies z.ZodType<ContentCoverInput>

export type ContentMarkdownInline =
  | { type: 'text'; value: string }
  | { type: 'strong' | 'emphasis'; children: ContentMarkdownInline[] }
  | { type: 'link'; url: string; children: ContentMarkdownInline[] }

export type ContentMarkdownBlock =
  | { type: 'paragraph'; children: ContentMarkdownInline[] }
  | { type: 'heading'; level: 2 | 3; children: ContentMarkdownInline[] }
  | { type: 'blockquote'; children: ContentMarkdownBlock[] }
  | { type: 'list'; ordered: boolean; items: ContentMarkdownBlock[][] }

export interface ValidatedContentMarkdown {
  normalized: string
  blocks: ContentMarkdownBlock[]
  wordCount: number
  readingTimeMinutes: number
}

interface MarkdownNode {
  type: string
  [key: string]: unknown
}

function invalidMarkdown(message: string): never {
  throw new Error(`Invalid content Markdown: ${message}`)
}

function nodeChildren(node: MarkdownNode): MarkdownNode[] {
  if (!Array.isArray(node.children) || !node.children.every(isMarkdownNode)) {
    invalidMarkdown(`${node.type} has malformed children`)
  }
  return node.children
}

function isMarkdownNode(value: unknown): value is MarkdownNode {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as { type?: unknown }).type === 'string'
  )
}

function convertInline(node: MarkdownNode, depth: number): ContentMarkdownInline {
  switch (node.type) {
    case 'text':
      if (typeof node.value !== 'string') invalidMarkdown('text has no value')
      return { type: 'text', value: node.value }
    case 'strong':
    case 'emphasis':
      if (depth > MAX_CONTENT_DEPTH) invalidMarkdown('maximum nesting depth is eight')
      return {
        type: node.type,
        children: nodeChildren(node).map((child) => convertInline(child, depth + 1)),
      }
    case 'link': {
      if (typeof node.url !== 'string' || !isHttpsUrl(node.url)) {
        invalidMarkdown('links must use an absolute HTTPS URL')
      }
      if (node.title !== null) invalidMarkdown('links must not have titles')
      if (depth > MAX_CONTENT_DEPTH) invalidMarkdown('maximum nesting depth is eight')
      return {
        type: 'link',
        url: node.url,
        children: nodeChildren(node).map((child) => convertInline(child, depth + 1)),
      }
    }
    default:
      return invalidMarkdown(`unsupported inline node: ${node.type}`)
  }
}

function convertBlock(node: MarkdownNode, containerDepth: number): ContentMarkdownBlock {
  switch (node.type) {
    case 'paragraph':
      return {
        type: 'paragraph',
        children: nodeChildren(node).map((child) => convertInline(child, 1)),
      }
    case 'heading': {
      if (node.depth !== 2 && node.depth !== 3)
        invalidMarkdown('only H2 and H3 headings are supported')
      return {
        type: 'heading',
        level: node.depth,
        children: nodeChildren(node).map((child) => convertInline(child, 1)),
      }
    }
    case 'blockquote':
      if (containerDepth >= MAX_CONTENT_DEPTH) invalidMarkdown('maximum nesting depth is eight')
      return {
        type: 'blockquote',
        children: nodeChildren(node).map((child) => convertBlock(child, containerDepth + 1)),
      }
    case 'list': {
      if (typeof node.ordered !== 'boolean') invalidMarkdown('list has malformed ordered state')
      if (node.ordered && node.start !== undefined && node.start !== null && node.start !== 1) {
        invalidMarkdown('ordered lists must start at one')
      }
      if (containerDepth >= MAX_CONTENT_DEPTH) invalidMarkdown('maximum nesting depth is eight')
      const items = nodeChildren(node).map((item) => {
        if (item.type !== 'listItem') invalidMarkdown('list contains a malformed item')
        return nodeChildren(item).map((child) => convertBlock(child, containerDepth + 1))
      })
      return { type: 'list', ordered: node.ordered, items }
    }
    case 'table':
      return invalidMarkdown('tables are not supported')
    default:
      return invalidMarkdown(`unsupported block node: ${node.type}`)
  }
}

function isHttpsUrl(value: string): boolean {
  const hasOriginalHttpsAuthority =
    /^https:\/\/[^/?#\\\s\u0000-\u001f\u007f]+(?:[/?#]|$)/i.test(value)
  if (!hasOriginalHttpsAuthority) return false

  try {
    const url = new URL(value)
    return url.protocol === 'https:' && url.hostname.length > 0
  } catch {
    return false
  }
}

function countWords(value: string): number {
  return value.match(/[\p{L}\p{N}]+/gu)?.length ?? 0
}

export function validateContentMarkdown(value: string): ValidatedContentMarkdown {
  const source = value.replace(/\r\n?/g, '\n')
  if (source.length < MIN_CONTENT_BODY_LENGTH || source.length > MAX_CONTENT_BODY_LENGTH) {
    invalidMarkdown(
      `body must be between ${MIN_CONTENT_BODY_LENGTH} and ${MAX_CONTENT_BODY_LENGTH} characters`,
    )
  }

  const root = fromMarkdown(source, {
    extensions: [gfmTable()],
    mdastExtensions: [gfmTableFromMarkdown()],
  })
  const rootChildren: unknown[] = root.children
  if (!rootChildren.every(isMarkdownNode)) {
    invalidMarkdown('root has malformed children')
  }

  const blocks = rootChildren.map((child) => convertBlock(child, 0))
  const normalized = toMarkdown(root).replace(/\r\n?/g, '\n')
  if (normalized.length < MIN_CONTENT_BODY_LENGTH || normalized.length > MAX_CONTENT_BODY_LENGTH) {
    invalidMarkdown(
      `normalized body must be between ${MIN_CONTENT_BODY_LENGTH} and ${MAX_CONTENT_BODY_LENGTH} characters`,
    )
  }
  const wordCount = countWords(normalized)

  return {
    normalized,
    blocks,
    wordCount,
    readingTimeMinutes: Math.max(1, Math.ceil(wordCount / 200)),
  }
}

const contentCursorPayloadSchema = z
  .object({
    publishAt: z.string().datetime({ offset: true }),
    publicationId: z.string().uuid(),
  })
  .strict()

const contentCursorSchema = z
  .string()
  .min(1)
  .max(MAX_CONTENT_CURSOR_LENGTH)
  .regex(/^[A-Za-z0-9_-]+$/)

export function encodeContentCursor(input: { publishAt: string; publicationId: string }): string {
  const payload = contentCursorPayloadSchema.parse(input)
  const cursor = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url')
  if (cursor.length > MAX_CONTENT_CURSOR_LENGTH) invalidMarkdown('cursor exceeds maximum length')
  return cursor
}

export function decodeContentCursor(value: string): { publishAt: string; publicationId: string } {
  const cursor = contentCursorSchema.parse(value)
  const decoded = Buffer.from(cursor, 'base64url')
  if (decoded.toString('base64url') !== cursor) invalidMarkdown('cursor is not canonical base64url')

  try {
    return contentCursorPayloadSchema.parse(JSON.parse(decoded.toString('utf8')))
  } catch {
    invalidMarkdown('cursor payload is invalid')
  }
}
