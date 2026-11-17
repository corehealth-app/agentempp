import { createHash } from 'node:crypto'
import {
  type PrivateMediaAssetV2,
  type PrivateMediaCatalogV2,
  privateMediaAssetV2Schema,
} from '@mpp/core/conversation-media'
import { parseConversationImageResult } from '@mpp/providers/vision/conversation-image-result'
import { z } from 'zod'
import {
  idempotencyKeySchema,
  type MediaUploadInput,
  mediaUploadInputSchema,
  resourceIdSchema,
} from './contracts'
import { MobileApiError } from './http'
import type { MediaSignedUpload } from './media-service'

// Existing public upload/worker limit. Keep this new private leaf independent
// of the legacy executable service; the 180001ms boundary is qualified below.
const maximumDeclaredAudioDurationMs = 180_000

const routeProof = z
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
export interface VersionedConversationMediaCreationPorts {
  enabled(): boolean
  photoEnabled(): boolean
  now(): Date
  nonce(): string
  resolve(userId: string, sourceRequestHash: string): Promise<unknown>
  catalog: Pick<PrivateMediaCatalogV2, 'create' | 'findByRequestHash' | 'findOwned'>
  issue(asset: PrivateMediaAssetV2): Promise<MediaSignedUpload>
}
function unavailable() {
  return new MobileApiError(503, 'media_catalog_unavailable', 'Media upload unavailable')
}
function conflict() {
  return new MobileApiError(
    409,
    'idempotency_key_conflict',
    'The original media request has changed',
  )
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

/** Creation only; an explicit database proof selects the old handler on replay.
 * No catch/fallback, public mirror, environment/provider construction or facts.
 * Existing key hashing is preserved so old technical retries keep their source. */
export async function createVersionedConversationMediaUpload(
  ports: VersionedConversationMediaCreationPorts,
  userId: string,
  raw: MediaUploadInput,
  requestKey: string,
) {
  const input = Object.freeze(mediaUploadInputSchema.parse(raw))
  const owner = resourceIdSchema.parse(userId)
  idempotencyKeySchema.parse(requestKey)
  const legacy = { action: 'legacy' as const }
  if (!['conversation_photo', 'audio_note'].includes(input.kind) || ports.enabled() !== true)
    return legacy
  let refused = false
  function current() {
    try {
      if (
        refused ||
        ports.enabled() !== true ||
        (input.kind === 'conversation_photo' && ports.photoEnabled() !== true)
      )
        throw unavailable()
    } catch {
      refused = true
      throw unavailable()
    }
  }
  current()
  if (
    input.kind === 'audio_note' &&
    input.duration_ms !== undefined &&
    input.duration_ms > maximumDeclaredAudioDurationMs
  )
    throw new MobileApiError(422, 'audio_too_long', 'Audio must be at most 180 seconds long')
  const sourceHash = createHash('sha256').update(requestKey).digest('hex')
  try {
    const rawProof = await ports.resolve(owner, sourceHash)
    current()
    const proof = rawProof === null ? null : routeProof.parse(rawProof)
    if (proof && proof.user_id !== owner) throw unavailable()
    if (proof?.catalog_version === 1) return legacy
    if (proof && proof.kind !== input.kind) throw conflict()
    const nonce = resourceIdSchema.parse(ports.nonce())
    const original = proof
      ? await ports.catalog.findByRequestHash(owner, sourceHash)
      : await ports.catalog.create({
          userId: owner,
          assetId: nonce,
          kind: input.kind as 'conversation_photo' | 'audio_note',
          mimeType: input.mime_type,
          declaredSizeBytes: input.size_bytes,
          contextText: input.context_text ?? null,
          sourceRequestHash: sourceHash,
        })
    current()
    const source = privateMediaAssetV2Schema.parse(original)
    function same(value: PrivateMediaAssetV2) {
      if (
        value.user_id !== owner ||
        value.source_request_hash !== sourceHash ||
        value.kind !== input.kind ||
        value.mime_type !== input.mime_type ||
        value.declared_size_bytes !== input.size_bytes ||
        value.context_text !== (input.context_text ?? null) ||
        (proof && value.id !== proof.asset_id)
      )
        throw conflict()
    }
    same(source)
    const at = ports.now().getTime()
    if (!Number.isFinite(at)) throw unavailable()
    if (source.status === 'deleted' || Date.parse(source.retention_until) <= at)
      throw new MobileApiError(410, 'media_expired', 'This media upload has expired')
    const upload = source.status === 'pending_upload' ? await ports.issue(source) : null
    current()
    const latest = privateMediaAssetV2Schema.parse(
      await ports.catalog.findOwned({ userId: owner, assetId: source.id }),
    )
    current()
    same(latest)
    const finalAt = ports.now().getTime()
    if (
      !Number.isFinite(finalAt) ||
      latest.id !== source.id ||
      latest.status === 'deleted' ||
      Date.parse(latest.retention_until) <= finalAt ||
      (upload !== null && latest.status !== 'pending_upload')
    )
      throw unavailable()
    return {
      action: 'private' as const,
      value: { asset: dto(latest), upload, replayed: proof !== null || source.id !== nonce },
    }
  } catch (error) {
    if (error instanceof MobileApiError) throw error
    throw unavailable()
  }
}
