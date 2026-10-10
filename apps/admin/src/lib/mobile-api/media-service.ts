import { createHash, randomUUID } from 'node:crypto'
import type { MediaUploadInput } from './contracts'
import { MobileApiError } from './http'

export type MediaAssetKind =
  | 'meal_photo'
  | 'body_checkin_photo'
  | 'gym_photo'
  | 'audio_note'
  | 'content_cover'
  | 'plan_document'

export type MediaAssetStatus =
  | 'pending_upload'
  | 'uploaded'
  | 'processing'
  | 'processed'
  | 'failed'
  | 'deleted'

export interface MediaAssetRecord {
  id: string
  user_id: string
  kind: MediaAssetKind
  bucket_id: string
  object_path: string
  mime_type: string
  declared_size_bytes: number
  actual_size_bytes: number | null
  status: MediaAssetStatus
  failure_stage: 'upload' | 'processing' | null
  failure_code: string | null
  context_text: string | null
  retention_until: string | null
  uploaded_at: string | null
  processed_at: string | null
  deleted_at: string | null
  processing_result?: unknown
  created_at: string
  updated_at: string
}

interface CreateMediaAssetRecord {
  id: string
  userId: string
  kind: Exclude<MediaAssetKind, 'content_cover'>
  bucketId: string
  objectPath: string
  mimeType: string
  declaredSizeBytes: number
  contextText: string | null
  sourceRequestHash: string
  /** null = no automatic retention date (plan documents). */
  retentionUntil: string | null
}

export interface MediaAssetRepository {
  findByRequestHash(userId: string, sourceRequestHash: string): Promise<MediaAssetRecord | null>
  create(input: CreateMediaAssetRecord): Promise<MediaAssetRecord>
  findOwned(userId: string, assetId: string): Promise<MediaAssetRecord | null>
  markUploaded(
    userId: string,
    assetId: string,
    details: { actualSizeBytes: number; etag: string | null; uploadedAt: string },
  ): Promise<MediaAssetRecord>
  markUploadFailed(userId: string, assetId: string, failureCode: string): Promise<void>
  markDeleted(userId: string, assetId: string, deletedAt: string): Promise<MediaAssetRecord>
}

export interface MediaStorageGateway {
  createSignedUpload(bucketId: string, objectPath: string): Promise<{ signedUrl: string }>
  getObjectInfo(
    bucketId: string,
    objectPath: string,
  ): Promise<{ size: number; contentType: string | null; etag: string | null }>
  createSignedDownload(bucketId: string, objectPath: string, expiresIn: number): Promise<string>
  remove(bucketId: string, objectPath: string): Promise<void>
}

export interface MediaProcessingEventGateway {
  sendProcessingRequested(input: {
    assetId: string
    userId: string
    requestId: string
  }): Promise<void>
}

export interface MediaServiceDependencies {
  repository: MediaAssetRepository
  storage: MediaStorageGateway
  events: MediaProcessingEventGateway
  /** Plan drafts that still depend on a document; absent = none exist. */
  planDrafts?: {
    hasOpenDraftOfMedia(userId: string, assetId: string): Promise<boolean>
  }
}

const mediaPolicy = {
  meal_photo: { bucketId: 'meal-photos', retentionDays: 30, downloadTtl: 300 },
  body_checkin_photo: {
    bucketId: 'body-checkin-photos',
    retentionDays: 730,
    downloadTtl: 60,
  },
  gym_photo: { bucketId: 'gym-photos', retentionDays: 90, downloadTtl: 300 },
  audio_note: { bucketId: 'audio-notes', retentionDays: 30, downloadTtl: 300 },
  // How long plan documents are kept is an open data-policy decision: no
  // date is set and nothing removes them on a timer; the patient deletes them.
  plan_document: { bucketId: 'plan-documents', retentionDays: null, downloadTtl: 300 },
} as const

const extensionByMimeType: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a',
  'audio/x-m4a': 'm4a',
  'audio/aac': 'aac',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav',
  'audio/ogg': 'ogg',
  'application/pdf': 'pdf',
}

const SIGNED_UPLOAD_TTL_SECONDS = 2 * 60 * 60

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex')
}

function addDays(now: Date, days: number): string {
  return new Date(now.getTime() + days * 24 * 60 * 60 * 1000).toISOString()
}

function mediaAssetDto(asset: MediaAssetRecord) {
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
    result: asset.status === 'processed' ? (asset.processing_result ?? null) : null,
    created_at: asset.created_at,
    updated_at: asset.updated_at,
  }
}

async function signedUpload(deps: MediaServiceDependencies, asset: MediaAssetRecord, now: Date) {
  const signed = await deps.storage.createSignedUpload(asset.bucket_id, asset.object_path)
  return {
    signed_url: signed.signedUrl,
    method: 'PUT' as const,
    headers: {
      'Content-Type': asset.mime_type,
      'x-upsert': 'false',
    },
    expires_at: new Date(now.getTime() + SIGNED_UPLOAD_TTL_SECONDS * 1000).toISOString(),
  }
}

function requireOwnedAsset(asset: MediaAssetRecord | null): MediaAssetRecord {
  if (!asset) throw new MobileApiError(404, 'media_asset_not_found', 'Media asset not found')
  return asset
}

/** Same limit the app and the worker enforce. */
export const MAX_AUDIO_DURATION_MS = 180_000

export async function createMediaAsset(
  deps: MediaServiceDependencies,
  userId: string,
  input: MediaUploadInput,
  requestKey: string,
  now = new Date(),
  assetId = randomUUID(),
) {
  if (
    input.kind === 'audio_note' &&
    input.duration_ms != null &&
    input.duration_ms > MAX_AUDIO_DURATION_MS
  ) {
    throw new MobileApiError(422, 'audio_too_long', 'Audio must be at most 180 seconds long')
  }
  const sourceRequestHash = sha256(requestKey)
  const existing = await deps.repository.findByRequestHash(userId, sourceRequestHash)
  if (existing) {
    return {
      asset: mediaAssetDto(existing),
      upload: existing.status === 'pending_upload' ? await signedUpload(deps, existing, now) : null,
      replayed: true,
    }
  }

  const policy = mediaPolicy[input.kind]
  const extension = extensionByMimeType[input.mime_type]
  if (!extension) {
    throw new MobileApiError(422, 'media_type_unsupported', 'Media type is unsupported')
  }
  const created = await deps.repository.create({
    id: assetId,
    userId,
    kind: input.kind,
    bucketId: policy.bucketId,
    objectPath: `${userId}/${assetId}.${extension}`,
    mimeType: input.mime_type,
    declaredSizeBytes: input.size_bytes,
    contextText: input.context_text ?? null,
    sourceRequestHash,
    retentionUntil: policy.retentionDays === null ? null : addDays(now, policy.retentionDays),
  })

  return {
    asset: mediaAssetDto(created),
    upload: await signedUpload(deps, created, now),
    replayed: false,
  }
}

export async function completeMediaUpload(
  deps: MediaServiceDependencies,
  userId: string,
  assetId: string,
  now = new Date(),
) {
  const asset = requireOwnedAsset(await deps.repository.findOwned(userId, assetId))
  if (['uploaded', 'processing', 'processed'].includes(asset.status)) return mediaAssetDto(asset)
  if (asset.status !== 'pending_upload') {
    throw new MobileApiError(409, 'media_upload_not_pending', 'Media upload is not pending')
  }

  let info: Awaited<ReturnType<MediaStorageGateway['getObjectInfo']>>
  try {
    info = await deps.storage.getObjectInfo(asset.bucket_id, asset.object_path)
  } catch (error) {
    if (error instanceof MobileApiError && error.code === 'media_upload_not_found') {
      await deps.repository.markUploadFailed(userId, assetId, 'object_missing')
      throw new MobileApiError(422, 'media_upload_missing', 'Uploaded media was not found')
    }
    throw error
  }
  const contentType = info.contentType?.split(';', 1)[0]?.trim().toLowerCase() ?? null
  if (info.size !== asset.declared_size_bytes || contentType !== asset.mime_type) {
    await deps.storage.remove(asset.bucket_id, asset.object_path)
    await deps.repository.markUploadFailed(userId, assetId, 'metadata_mismatch')
    throw new MobileApiError(
      422,
      'media_upload_mismatch',
      'Uploaded media does not match its declaration',
    )
  }

  return mediaAssetDto(
    await deps.repository.markUploaded(userId, assetId, {
      actualSizeBytes: info.size,
      etag: info.etag,
      uploadedAt: now.toISOString(),
    }),
  )
}

export async function getMediaAsset(
  deps: MediaServiceDependencies,
  userId: string,
  assetId: string,
) {
  const asset = requireOwnedAsset(await deps.repository.findOwned(userId, assetId))
  if (asset.status === 'deleted') return { ...mediaAssetDto(asset), download: null }
  if (!['uploaded', 'processing', 'processed'].includes(asset.status)) {
    return { ...mediaAssetDto(asset), download: null }
  }

  const policy = mediaPolicy[asset.kind as keyof typeof mediaPolicy]
  if (!policy) return { ...mediaAssetDto(asset), download: null }
  const signedUrl = await deps.storage.createSignedDownload(
    asset.bucket_id,
    asset.object_path,
    policy.downloadTtl,
  )
  return {
    ...mediaAssetDto(asset),
    download: {
      signed_url: signedUrl,
      expires_in_seconds: policy.downloadTtl,
    },
  }
}

export async function deleteMediaAsset(
  deps: MediaServiceDependencies,
  userId: string,
  assetId: string,
  now = new Date(),
) {
  const asset = requireOwnedAsset(await deps.repository.findOwned(userId, assetId))
  if (asset.status === 'deleted') return mediaAssetDto(asset)
  // A document under reading or review is its draft's source: the patient
  // discards the draft first, and then the document.
  if (
    asset.kind === 'plan_document' &&
    deps.planDrafts &&
    (await deps.planDrafts.hasOpenDraftOfMedia(userId, assetId))
  ) {
    throw new MobileApiError(
      409,
      'media_in_use_by_plan_draft',
      'Discard the plan draft of this document before deleting it',
    )
  }

  await deps.storage.remove(asset.bucket_id, asset.object_path)
  return mediaAssetDto(await deps.repository.markDeleted(userId, assetId, now.toISOString()))
}

export async function requestMediaProcessing(
  deps: MediaServiceDependencies,
  userId: string,
  assetId: string,
  requestKey: string,
) {
  const asset = requireOwnedAsset(await deps.repository.findOwned(userId, assetId))
  // A plan document is read only for a draft that waits for it, through
  // POST /plan-imports; reading it here would leave nothing to import.
  if (asset.kind === 'plan_document') {
    throw new MobileApiError(422, 'media_kind_not_supported', 'Plan documents are read on import')
  }
  // A body photo is never sent to AI reading by the app's server, whatever
  // the request carries and whatever state the asset is in: who evaluates it
  // is not defined yet. The kind is the one recorded at upload.
  if (asset.kind === 'body_checkin_photo') {
    throw new MobileApiError(422, 'media_kind_not_supported', 'Body photos are not read by AI')
  }
  const retryableFailure = asset.status === 'failed' && asset.failure_stage === 'processing'
  if (asset.status !== 'uploaded' && asset.status !== 'processing' && !retryableFailure) {
    throw new MobileApiError(409, 'media_not_processable', 'Media asset is not processable')
  }

  await deps.events.sendProcessingRequested({
    assetId,
    userId,
    requestId: sha256(requestKey),
  })
  return mediaAssetDto(asset)
}
