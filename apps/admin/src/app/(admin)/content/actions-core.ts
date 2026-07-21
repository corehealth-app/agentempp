import {
  contentCategorySchema,
  contentCoverInputSchema,
  contentDraftInputSchema,
  contentLocaleSchema,
} from '@mpp/core'
import { z } from 'zod'
import {
  type AdminRole,
  CONTENT_AUTHOR_ROLES,
  CONTENT_MODULE_ROLES,
  CONTENT_PUBLISH_ROLES,
  CONTENT_REVIEW_ROLES,
  hasAdminRole,
} from '@/lib/admin-rbac'
import {
  ContentAdminError,
  type ContentAdminFilters,
  type ContentAdminService,
} from '@/lib/content/admin-service'

const uuidSchema = z.string().uuid()
const timestampSchema = z.string().datetime({ offset: true })
const listFiltersSchema = z
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
  .strict() satisfies z.ZodType<ContentAdminFilters, z.ZodTypeDef, unknown>

const actionSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('list'), input: listFiltersSchema }).strict(),
  z
    .object({
      type: z.literal('get'),
      input: z.object({ publicationId: uuidSchema }).strict(),
    })
    .strict(),
  z
    .object({
      type: z.literal('createPublication'),
      input: z
        .object({
          slug: z
            .string()
            .min(3)
            .max(120)
            .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
        })
        .strict(),
    })
    .strict(),
  z
    .object({
      type: z.literal('createDraft'),
      input: z
        .object({
          publicationId: uuidSchema,
          locale: contentLocaleSchema,
          sourceVersionId: uuidSchema.optional(),
        })
        .strict(),
    })
    .strict(),
  z
    .object({
      type: z.literal('saveDraft'),
      input: z
        .object({
          versionId: uuidSchema,
          expectedUpdatedAt: timestampSchema,
          draft: contentDraftInputSchema,
        })
        .strict(),
    })
    .strict(),
  z
    .object({
      type: z.literal('submit'),
      input: z.object({ versionId: uuidSchema, expectedUpdatedAt: timestampSchema }).strict(),
    })
    .strict(),
  z
    .object({
      type: z.literal('review'),
      input: z
        .object({
          versionId: uuidSchema,
          decision: z.enum(['approve', 'reject']),
          rejectionReason: z.string().trim().min(10).max(1000).nullable().optional(),
        })
        .strict()
        .superRefine((value, context) => {
          if (value.decision === 'reject' && !value.rejectionReason) {
            context.addIssue({
              code: z.ZodIssueCode.custom,
              message: 'Rejection reason is required.',
            })
          }
          if (value.decision === 'approve' && value.rejectionReason != null) {
            context.addIssue({
              code: z.ZodIssueCode.custom,
              message: 'Approval has no rejection reason.',
            })
          }
        }),
    })
    .strict(),
  z
    .object({
      type: z.literal('publish'),
      input: z.object({ versionId: uuidSchema, publishAt: timestampSchema.nullable() }).strict(),
    })
    .strict(),
  z
    .object({
      type: z.literal('archive'),
      input: z.object({ publicationId: uuidSchema }).strict(),
    })
    .strict(),
  z.object({ type: z.literal('createCover'), input: contentCoverInputSchema }).strict(),
  z
    .object({
      type: z.literal('completeCover'),
      input: z.object({ assetId: uuidSchema }).strict(),
    })
    .strict(),
  z
    .object({
      type: z.literal('deleteCover'),
      input: z.object({ assetId: uuidSchema }).strict(),
    })
    .strict(),
])

export type ContentAdminAction = z.infer<typeof actionSchema>

export interface ContentAdminActionDependencies {
  loadAuthenticatedAdmin(): Promise<{ id: string; role: AdminRole }>
  createService(): ContentAdminService
  revalidatePath(path: string, type?: 'page'): void | Promise<void>
}

export class ContentActionAuthError extends Error {
  constructor(readonly kind: 'unauthenticated' | 'forbidden') {
    super(`Content action authorization failed: ${kind}`)
    this.name = 'ContentActionAuthError'
  }
}

const AUTHOR_ACTIONS = new Set<ContentAdminAction['type']>([
  'createPublication',
  'createDraft',
  'saveDraft',
  'submit',
  'createCover',
  'completeCover',
  'deleteCover',
])
const REVIEW_ACTIONS = new Set<ContentAdminAction['type']>(['review'])
const PUBLISH_ACTIONS = new Set<ContentAdminAction['type']>(['publish', 'archive'])
const MUTATIONS = new Set<ContentAdminAction['type']>([
  ...AUTHOR_ACTIONS,
  ...REVIEW_ACTIONS,
  ...PUBLISH_ACTIONS,
])

function requireRole(role: AdminRole, type: ContentAdminAction['type']): void {
  let allowed = hasAdminRole(role, CONTENT_MODULE_ROLES)
  if (AUTHOR_ACTIONS.has(type)) allowed = hasAdminRole(role, CONTENT_AUTHOR_ROLES)
  if (REVIEW_ACTIONS.has(type)) allowed = hasAdminRole(role, CONTENT_REVIEW_ROLES)
  if (PUBLISH_ACTIONS.has(type)) allowed = hasAdminRole(role, CONTENT_PUBLISH_ROLES)
  if (!allowed) throw new ContentActionAuthError('forbidden')
}

function parseAction(value: unknown): ContentAdminAction {
  const parsed = actionSchema.safeParse(value)
  if (!parsed.success) throw new ContentAdminError('validation', 'action')
  return parsed.data
}

function serializable(value: unknown): unknown {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (Array.isArray(value)) return value.map(serializable)
  if (typeof value !== 'object' || value instanceof Date || value instanceof Error) {
    throw new Error('Non-serializable content action result')
  }
  const prototype = Object.getPrototypeOf(value)
  if (prototype !== Object.prototype && prototype !== null) {
    throw new Error('Non-serializable content action result')
  }
  const output: Record<string, unknown> = {}
  for (const [key, entry] of Object.entries(value)) output[key] = serializable(entry)
  return output
}

function publicationIdFrom(action: ContentAdminAction, result: unknown): string | null {
  if (action.type === 'createDraft' || action.type === 'archive') return action.input.publicationId
  const parsed = z.object({ publicationId: uuidSchema }).passthrough().safeParse(result)
  return parsed.success ? parsed.data.publicationId : null
}

async function revalidateMutation(
  action: ContentAdminAction,
  result: unknown,
  dependencies: ContentAdminActionDependencies,
): Promise<void> {
  if (!MUTATIONS.has(action.type)) return
  await dependencies.revalidatePath('/content')
  const publicationId = publicationIdFrom(action, result)
  if (publicationId) {
    await dependencies.revalidatePath(`/content/${publicationId}`)
  } else {
    await dependencies.revalidatePath('/content/[id]', 'page')
  }
}

export async function executeContentAdminAction(
  untrustedAction: unknown,
  dependencies: ContentAdminActionDependencies,
): Promise<unknown> {
  const admin = await dependencies.loadAuthenticatedAdmin()
  const action = parseAction(untrustedAction)
  requireRole(admin.role, action.type)
  const service = dependencies.createService()
  let result: unknown

  switch (action.type) {
    case 'list':
      result = await service.list(action.input)
      break
    case 'get':
      result = await service.get(action.input)
      break
    case 'createPublication':
      result = await service.createPublication({ ...action.input, actorId: admin.id })
      break
    case 'createDraft':
      result = await service.createDraft({ ...action.input, actorId: admin.id })
      break
    case 'saveDraft':
      result = await service.saveDraft({ ...action.input, actorId: admin.id })
      break
    case 'submit':
      result = await service.submit({ ...action.input, actorId: admin.id })
      break
    case 'review':
      result = await service.review({
        ...action.input,
        rejectionReason: action.input.rejectionReason ?? null,
        actorId: admin.id,
      })
      break
    case 'publish':
      result = await service.publish({ ...action.input, actorId: admin.id })
      break
    case 'archive':
      result = await service.archive({ ...action.input, actorId: admin.id })
      break
    case 'createCover':
      result = await service.createCover({ ...action.input, actorId: admin.id })
      break
    case 'completeCover':
      result = await service.completeCover({ ...action.input, actorId: admin.id })
      break
    case 'deleteCover':
      result = await service.deleteCover({ ...action.input, actorId: admin.id })
      break
  }

  const safeResult = serializable(result)
  await revalidateMutation(action, safeResult, dependencies)
  return safeResult
}

function publicError(error: unknown): string {
  if (error instanceof ContentActionAuthError) {
    return error.kind === 'unauthenticated'
      ? 'Faça login novamente para continuar.'
      : 'Você não tem acesso a esta operação.'
  }
  if (!(error instanceof ContentAdminError)) return 'Não foi possível concluir a operação.'
  if (error.code === 'stale') {
    return 'Este conteúdo foi alterado. Recarregue e tente novamente.'
  }
  if (error.code === 'duplicate' && error.operation === 'createPublication') {
    return 'Já existe uma publicação com este slug.'
  }
  if (error.code === 'duplicate' && error.operation === 'createDraft') {
    return 'Já existe um rascunho para este idioma.'
  }
  if (error.code === 'not_found') return 'Conteúdo não encontrado.'
  if (error.code === 'denied') return 'Você não tem permissão para esta operação.'
  if (error.code === 'cover_referenced') return 'Esta capa está em uso e não pode ser excluída.'
  if (error.code === 'cover_mismatch') {
    return 'O arquivo da capa não corresponde ao envio solicitado.'
  }
  if (error.code === 'storage_unavailable') {
    return 'Não foi possível acessar o armazenamento de capas agora.'
  }
  if (error.code === 'validation') return 'Confira os dados informados e tente novamente.'
  if (error.code === 'lifecycle') return 'O estado atual não permite esta operação.'
  return 'Não foi possível concluir a operação.'
}

export type ContentAdminActionResult = { ok: true; data: unknown } | { ok: false; error: string }

export async function runContentAdminAction(
  action: unknown,
  dependencies: ContentAdminActionDependencies,
): Promise<ContentAdminActionResult> {
  try {
    return { ok: true, data: await executeContentAdminAction(action, dependencies) }
  } catch (error) {
    return { ok: false, error: publicError(error).slice(0, 160) }
  }
}
