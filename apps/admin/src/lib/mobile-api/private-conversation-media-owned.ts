import { createHash } from 'node:crypto'
import {
  type ConversationMediaIdentityV2,
  type PrivateMediaAssetV2,
  type PrivateMediaCatalogV2,
  privateMediaAssetV2Schema,
  privateMediaIdentityOfV2,
} from '@mpp/core/conversation-media'
import { parseConversationImageResult } from '@mpp/providers/vision/conversation-image-result'
import { z } from 'zod'
import { idempotencyKeySchema, resourceIdSchema } from './contracts'
import { MobileApiError } from './http'

const proofSchema = z
  .object({
    schema: z.literal('conversation.media-catalog.v2'),
    catalog_version: z.union([z.literal(1), z.literal(2)]),
    asset_id: resourceIdSchema,
    user_id: resourceIdSchema,
    kind: z.enum([
      'meal_photo',
      'conversation_photo',
      'body_checkin_photo',
      'gym_photo',
      'audio_note',
      'content_cover',
      'plan_document',
    ]),
  })
  .strict()
const objectInfo = z
  .object({
    size: z.number().int().nonnegative(),
    contentType: z.string().nullable(),
    etag: z.string().max(512).nullable(),
  })
  .strict()
export interface OwnedConversationMediaPorts {
  enabled(): boolean
  photoEnabled(): boolean
  now(): Date
  storageOrigin: string
  resolve(userId: string, assetId: string): Promise<unknown>
  catalog: Pick<PrivateMediaCatalogV2, 'findOwned' | 'completeUpload'>
  info(identity: ConversationMediaIdentityV2): Promise<z.infer<typeof objectInfo> | null>
  signDownload(
    identity: ConversationMediaIdentityV2,
    seconds: number,
  ): Promise<{ signedUrl: string }>
  close(userId: string, assetId: string): Promise<boolean>
  /** Available only to the explicit processing route; no fact writer. */
  enqueue?(input: { userId: string; assetId: string; requestId: string }): Promise<void>
  /** A single committed revocation; never the worker's global sweep. */
  dispose?(identity: ConversationMediaIdentityV2): Promise<void>
}
function unavailable() {
  return new MobileApiError(503, 'media_catalog_unavailable', 'Media operation unavailable')
}
function dto(asset: PrivateMediaAssetV2) {
  return {
    id: asset.id,
    kind: asset.kind,
    mime_type: asset.mime_type,
    size_bytes: asset.actual_size_bytes ?? asset.declared_size_bytes,
    status: asset.status,
    failure_stage: asset.failure_stage,
    failure_code: asset.failure_code,
    has_context: Boolean(asset.context_text),
    retention_until: asset.retention_until,
    uploaded_at: asset.uploaded_at,
    processed_at: asset.processed_at,
    deleted_at: asset.deleted_at,
    result:
      asset.status !== 'processed'
        ? null
        : asset.kind === 'conversation_photo'
          ? parseConversationImageResult(asset.processing_result)
          : asset.processing_result,
    created_at: asset.created_at,
    updated_at: asset.updated_at,
  }
}

/** An opaque ID is resolved once by committed DB provenance. A legacy proof
 * delegates; missing/invalid/uncertain private reads never fall back. Upload
 * failures retain independent SQL disposal authority, without unversioned IO. */
export async function ownedConversationMediaOperation(
  ports: OwnedConversationMediaPorts,
  userId: string,
  assetId: string,
  operation: 'read' | 'complete' | 'process' | 'delete',
  requestKey?: string,
) {
  const owner = resourceIdSchema.parse(userId),
    id = resourceIdSchema.parse(assetId)
  if (ports.enabled() !== true) return { action: 'legacy' as const }
  let refused = false
  function current(kind?: string) {
    if (
      refused ||
      ports.enabled() !== true ||
      (operation !== 'delete' && kind === 'conversation_photo' && ports.photoEnabled() !== true)
    ) {
      refused = true
      throw unavailable()
    }
    const at = ports.now().getTime()
    if (!Number.isFinite(at)) throw unavailable()
    return at
  }
  try {
    current()
    const rawProof = await ports.resolve(owner, id)
    current()
    if (rawProof === null) throw new MobileApiError(404, 'media_not_found', 'Media was not found')
    const proof = proofSchema.parse(rawProof)
    if (proof.user_id !== owner || proof.asset_id !== id) throw unavailable()
    if (proof.catalog_version === 1) return { action: 'legacy' as const }
    current(proof.kind)
    const scope = { userId: owner, assetId: id }
    const original = privateMediaAssetV2Schema.parse(await ports.catalog.findOwned(scope))
    function live(raw: unknown) {
      const row = privateMediaAssetV2Schema.parse(raw),
        at = current(proof.kind)
      if (
        row.id !== id ||
        row.user_id !== owner ||
        row.kind !== proof.kind ||
        row.object_path !== original.object_path ||
        row.bucket_id !== original.bucket_id ||
        row.mime_type !== original.mime_type ||
        row.source_request_hash !== original.source_request_hash ||
        row.declared_size_bytes !== original.declared_size_bytes ||
        row.context_text !== original.context_text ||
        row.created_at !== original.created_at ||
        row.retention_until !== original.retention_until
      )
        throw unavailable()
      if (
        operation !== 'delete' &&
        row.status !== 'deleted' &&
        Date.parse(row.retention_until) <= at
      )
        throw new MobileApiError(410, 'media_expired', 'This media upload has expired')
      return row
    }
    let row = live(original)
    const identity = privateMediaIdentityOfV2(row)
    if (operation === 'delete') {
      if (!ports.dispose) throw unavailable()
      await ports.dispose(identity)
      const latest = live(await ports.catalog.findOwned(scope))
      if (latest.status !== 'deleted' || latest.processing_result !== null) throw unavailable()
      return { action: 'private' as const, value: dto(latest) }
    }
    if (operation === 'process') {
      if (typeof requestKey !== 'string') throw unavailable()
      idempotencyKeySchema.parse(requestKey)
      if (row.status === 'processed') return { action: 'private' as const, value: dto(row) }
      if (
        !['uploaded', 'processing'].includes(row.status) &&
        !(row.status === 'failed' && row.failure_stage === 'processing')
      )
        throw new MobileApiError(409, 'media_not_processable', 'Media asset is not processable')
      if (!ports.enqueue) throw unavailable()
      await ports.enqueue({
        userId: owner,
        assetId: id,
        requestId: createHash('sha256').update(requestKey).digest('hex'),
      })
      const latest = live(await ports.catalog.findOwned(scope))
      if (latest.status === 'deleted' || latest.status === 'pending_upload') throw unavailable()
      return { action: 'private' as const, value: dto(latest) }
    }
    if (operation === 'complete') {
      if (row.status === 'pending_upload') {
        const raw = await ports.info(identity)
        current(row.kind)
        const info = raw === null ? null : objectInfo.parse(raw)
        const mimeType = info?.contentType?.split(';', 1)[0]?.trim().toLowerCase() ?? null
        if (info === null || info.size !== row.declared_size_bytes || mimeType !== row.mime_type) {
          if ((await ports.close(owner, id)) !== true) throw unavailable()
          current(row.kind)
          throw new MobileApiError(
            422,
            info === null ? 'media_upload_missing' : 'media_upload_mismatch',
            info === null
              ? 'Uploaded media was not found'
              : 'Uploaded media does not match its declaration',
          )
        }
        row = live(
          await ports.catalog.completeUpload(scope, { size: info.size, mimeType, etag: info.etag }),
        )
      }
      if (!['uploaded', 'processing', 'processed'].includes(row.status))
        throw new MobileApiError(409, 'media_upload_not_pending', 'Media upload is not pending')
      const latest = live(await ports.catalog.findOwned(scope))
      if (!['uploaded', 'processing', 'processed'].includes(latest.status)) throw unavailable()
      return { action: 'private' as const, value: dto(latest) }
    }
    if (!['uploaded', 'processing', 'processed'].includes(row.status))
      return { action: 'private' as const, value: { ...dto(row), download: null } }
    const ttl = Math.min(
      300,
      Math.floor((Date.parse(row.retention_until) - current(row.kind)) / 1000),
    )
    if (ttl < 1) throw new MobileApiError(410, 'media_expired', 'This media upload has expired')
    const signed = await ports.signDownload(identity, ttl)
    current(row.kind)
    const base = new URL(ports.storageOrigin),
      url = new URL(signed.signedUrl)
    if (
      base.protocol !== 'https:' ||
      base.origin !== ports.storageOrigin ||
      url.origin !== base.origin ||
      url.username ||
      url.password ||
      url.hash ||
      url.pathname !== `/storage/v1/object/sign/${row.bucket_id}/${row.object_path}` ||
      [...url.searchParams.keys()].join(',') !== 'token' ||
      !url.searchParams.get('token')
    )
      throw unavailable()
    row = live(await ports.catalog.findOwned(scope))
    if (!['uploaded', 'processing', 'processed'].includes(row.status)) throw unavailable()
    return {
      action: 'private' as const,
      value: { ...dto(row), download: { signed_url: signed.signedUrl, expires_in_seconds: ttl } },
    }
  } catch (error) {
    if (error instanceof MobileApiError) throw error
    throw unavailable()
  }
}
