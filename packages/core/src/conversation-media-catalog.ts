import { z } from 'zod'
import {
  privateMediaAssetReplyV2Schema,
  privateMediaProcessingClaimV2Schema,
  privateMediaUploadPreparedV2Schema,
  privateMediaUploadRegisteredV2Schema,
  privateMediaUploadStateV2Schema,
} from './conversation-media-lifecycle'
import { createConversationMediaIdentityV2 } from './conversation-media-namespace'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const scopeSchema = z.object({ userId: uuid, assetId: uuid }).strict()
const hash = z.string().regex(/^[0-9a-f]{64}$/)
const instant = z.string().datetime({ offset: true })
const createInput = z
  .object({
    userId: uuid,
    assetId: uuid,
    kind: z.enum(['audio_note', 'conversation_photo']),
    mimeType: z.string(),
    declaredSizeBytes: z.number().int().positive(),
    contextText: z.string().min(1).max(1000).nullable(),
    sourceRequestHash: hash,
  })
  .strict()
export type PrivateMediaScopeV2 = z.infer<typeof scopeSchema>
export type PrivateMediaCatalogRpcV2 = (
  name: string,
  args: Record<string, unknown>,
) => PromiseLike<{
  data: unknown
  error: { code?: string } | null
}>
export class PrivateMediaCatalogError extends Error {
  constructor(readonly kind: 'changed' | 'unavailable' = 'unavailable') {
    super('Private media operation unavailable')
  }
}

/** Pure, closed RPC port binding. No SDK, environment, auth lease, route,
 * provider, catalog fallback or automatic retry is created by this module. */
export function createPrivateMediaCatalogV2(transport: PrivateMediaCatalogRpcV2) {
  async function safe<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation()
    } catch (error) {
      throw error instanceof PrivateMediaCatalogError ? error : new PrivateMediaCatalogError()
    }
  }
  async function rpc(name: string, args: Record<string, unknown>) {
    const result = await transport(name, args)
    if (!result || result.error !== null)
      throw new PrivateMediaCatalogError(
        result?.error?.code === '40001' ? 'changed' : 'unavailable',
      )
    return result.data
  }
  function asset(raw: unknown, userId: string, assetId?: string, sourceHash?: string) {
    const value = privateMediaAssetReplyV2Schema.parse(raw).asset
    if (
      value.user_id !== userId ||
      (assetId !== undefined && value.id !== assetId) ||
      (sourceHash !== undefined && value.source_request_hash !== sourceHash)
    )
      throw new PrivateMediaCatalogError()
    return value
  }
  const argsOf = (scope: PrivateMediaScopeV2) => ({
    p_user_id: scope.userId,
    p_asset_id: scope.assetId,
  })
  return {
    create(input: z.infer<typeof createInput>) {
      return safe(async () => {
        const value = createInput.parse(input)
        createConversationMediaIdentityV2(value)
        const result = asset(
          await rpc('create_conversation_media_asset_v2', {
            p_user_id: value.userId,
            p_asset_id: value.assetId,
            p_kind: value.kind,
            p_mime_type: value.mimeType,
            p_declared_size_bytes: value.declaredSizeBytes,
            p_context_text: value.contextText,
            p_source_request_hash: value.sourceRequestHash,
          }),
          value.userId,
          undefined,
          value.sourceRequestHash,
        )
        if (
          result.kind !== value.kind ||
          result.mime_type !== value.mimeType ||
          result.declared_size_bytes !== value.declaredSizeBytes ||
          result.context_text !== value.contextText
        )
          throw new PrivateMediaCatalogError()
        return result
      })
    },
    findOwned(input: PrivateMediaScopeV2) {
      return safe(async () => {
        const scope = scopeSchema.parse(input)
        const raw = await rpc('get_conversation_media_asset_v2', {
          ...argsOf(scope),
          p_source_request_hash: null,
        })
        return raw === null ? null : asset(raw, scope.userId, scope.assetId)
      })
    },
    findByRequestHash(userId: string, sourceRequestHash: string) {
      return safe(async () => {
        const owner = uuid.parse(userId),
          sourceHash = hash.parse(sourceRequestHash)
        const raw = await rpc('get_conversation_media_asset_v2', {
          p_user_id: owner,
          p_asset_id: null,
          p_source_request_hash: sourceHash,
        })
        return raw === null ? null : asset(raw, owner, undefined, sourceHash)
      })
    },
    prepareUpload(input: PrivateMediaScopeV2, ticketId: string) {
      return safe(async () => {
        const scope = scopeSchema.parse(input),
          ticket = uuid.parse(ticketId)
        const value = privateMediaUploadPreparedV2Schema.parse(
          await rpc('prepare_conversation_media_upload_v2', {
            ...argsOf(scope),
            p_ticket_id: ticket,
          }),
        )
        if (
          value.ticket.id !== ticket ||
          value.asset.identity.asset_id !== scope.assetId ||
          value.asset.identity.user_id !== scope.userId
        )
          throw new PrivateMediaCatalogError()
        return value
      })
    },
    registerUpload(input: PrivateMediaScopeV2, ticketId: string, expiresAt: string) {
      return safe(async () => {
        const scope = scopeSchema.parse(input),
          ticket = uuid.parse(ticketId),
          expiry = instant.parse(expiresAt)
        const value = privateMediaUploadRegisteredV2Schema.parse(
          await rpc('register_conversation_media_upload_v2', {
            ...argsOf(scope),
            p_ticket_id: ticket,
            p_provider_expires_at: expiry,
          }),
        )
        if (
          value.ticket.id !== ticket ||
          value.ticket.asset_id !== scope.assetId ||
          value.ticket.user_id !== scope.userId ||
          Date.parse(value.ticket.provider_expires_at ?? '') !== Date.parse(expiry)
        )
          throw new PrivateMediaCatalogError()
        return value
      })
    },
    uploadState(input: PrivateMediaScopeV2) {
      return safe(async () => {
        const scope = scopeSchema.parse(input),
          raw = await rpc('get_conversation_media_upload_state_v2', argsOf(scope))
        if (raw === null) return null
        const value = privateMediaUploadStateV2Schema.parse(raw)
        if (
          value.asset.identity.asset_id !== scope.assetId ||
          value.asset.identity.user_id !== scope.userId
        )
          throw new PrivateMediaCatalogError()
        return value
      })
    },
    completeUpload(
      input: PrivateMediaScopeV2,
      info: { size: number; mimeType: string; etag: string | null },
    ) {
      return safe(async () => {
        const scope = scopeSchema.parse(input),
          value = z
            .object({
              size: z.number().int().positive().max(26214400),
              mimeType: z.string().min(1),
              etag: z.string().max(512).nullable(),
            })
            .strict()
            .parse(info)
        const result = asset(
          await rpc('complete_conversation_media_upload_v2', {
            ...argsOf(scope),
            p_actual_size_bytes: value.size,
            p_mime_type: value.mimeType,
            p_etag: value.etag,
          }),
          scope.userId,
          scope.assetId,
        )
        if (
          !['uploaded', 'processing', 'processed'].includes(result.status) ||
          result.actual_size_bytes !== value.size ||
          result.mime_type !== value.mimeType ||
          result.etag !== value.etag
        )
          throw new PrivateMediaCatalogError()
        return result
      })
    },
    claimProcessing(input: PrivateMediaScopeV2, requestId: string) {
      return safe(async () => {
        const scope = scopeSchema.parse(input),
          request = hash.parse(requestId)
        const value = privateMediaProcessingClaimV2Schema.parse(
          await rpc('claim_conversation_media_processing_v2', {
            ...argsOf(scope),
            p_request_id: request,
          }),
        )
        if (
          value.action === 'claimed' &&
          (value.asset.identity.user_id !== scope.userId ||
            value.asset.identity.asset_id !== scope.assetId ||
            value.asset.processing_request_id !== request)
        )
          throw new PrivateMediaCatalogError()
        return value
      })
    },
    completeProcessing(
      input: PrivateMediaScopeV2,
      requestId: string,
      claimToken: string,
      result: unknown,
    ) {
      return safe(async () => {
        const scope = scopeSchema.parse(input),
          request = hash.parse(requestId),
          token = uuid.parse(claimToken)
        const serialized = JSON.stringify(result)
        if (
          typeof serialized !== 'string' ||
          new TextEncoder().encode(serialized).byteLength > 1048576
        )
          throw new PrivateMediaCatalogError()
        const snapshot: unknown = JSON.parse(serialized)
        if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot))
          throw new PrivateMediaCatalogError()
        const value = await rpc('complete_conversation_media_processing_v2', {
          ...argsOf(scope),
          p_request_id: request,
          p_claim_token: token,
          p_result: snapshot,
        })
        if (typeof value !== 'boolean') throw new PrivateMediaCatalogError()
        return value
      })
    },
    failProcessing(
      input: PrivateMediaScopeV2,
      requestId: string,
      claimToken: string,
      reason: string,
    ) {
      return safe(async () => {
        const scope = scopeSchema.parse(input),
          request = hash.parse(requestId),
          token = uuid.parse(claimToken),
          failure = z
            .string()
            .regex(/^[a-z][a-z0-9_]{0,79}$/)
            .parse(reason)
        const value = await rpc('fail_conversation_media_processing_v2', {
          ...argsOf(scope),
          p_request_id: request,
          p_claim_token: token,
          p_failure_code: failure,
        })
        if (typeof value !== 'boolean') throw new PrivateMediaCatalogError()
        return value
      })
    },
  }
}
export type PrivateMediaCatalogV2 = ReturnType<typeof createPrivateMediaCatalogV2>
