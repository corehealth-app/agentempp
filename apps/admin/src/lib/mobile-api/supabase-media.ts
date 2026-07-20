import type { ServiceClient } from '@mpp/db'
import { inngest } from '@mpp/inngest-functions'
import { z } from 'zod'
import { MobileApiError } from './http'
import type {
  MediaAssetRecord,
  MediaAssetRepository,
  MediaServiceDependencies,
  MediaStorageGateway,
} from './media-service'

const mediaAssetRowSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  kind: z.enum(['meal_photo', 'body_checkin_photo', 'gym_photo', 'audio_note', 'content_cover']),
  bucket_id: z.string().min(1),
  object_path: z.string().min(1),
  mime_type: z.string().min(1),
  declared_size_bytes: z.number().int().positive(),
  actual_size_bytes: z.number().int().positive().nullable(),
  status: z.enum(['pending_upload', 'uploaded', 'processing', 'processed', 'failed', 'deleted']),
  failure_stage: z.enum(['upload', 'processing']).nullable(),
  failure_code: z.string().nullable(),
  context_text: z.string().nullable(),
  retention_until: z.string().datetime({ offset: true }).nullable(),
  uploaded_at: z.string().datetime({ offset: true }).nullable(),
  processed_at: z.string().datetime({ offset: true }).nullable(),
  deleted_at: z.string().datetime({ offset: true }).nullable(),
  processing_result: z.unknown().nullable(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }),
})

const mediaSelection = [
  'id',
  'user_id',
  'kind',
  'bucket_id',
  'object_path',
  'mime_type',
  'declared_size_bytes',
  'actual_size_bytes',
  'status',
  'failure_stage',
  'failure_code',
  'context_text',
  'retention_until',
  'uploaded_at',
  'processed_at',
  'deleted_at',
  'processing_result',
  'created_at',
  'updated_at',
].join(', ')

function parseMediaAsset(row: unknown): MediaAssetRecord {
  const parsed = mediaAssetRowSchema.safeParse(row)
  if (!parsed.success) throw new Error('Invalid media asset database response')
  return parsed.data
}

function databaseFailure(action: string, error: { message: string } | null): never {
  console.error('[mobile-media] database_failure', {
    action,
    error_name: error ? 'PostgrestError' : 'EmptyResult',
  })
  throw new MobileApiError(500, 'media_storage_failed', 'Media operation failed')
}

function storageErrorStatus(error: unknown): number | null {
  if (!error || typeof error !== 'object') return null
  const record = error as { status?: unknown; statusCode?: unknown }
  const value = record.status ?? record.statusCode
  const parsed = typeof value === 'number' ? value : Number(value)
  return Number.isInteger(parsed) ? parsed : null
}

function createRepository(supabase: ServiceClient): MediaAssetRepository {
  const findByRequestHash: MediaAssetRepository['findByRequestHash'] = async (
    userId,
    sourceRequestHash,
  ) => {
    const { data, error } = await supabase
      .from('media_assets')
      .select(mediaSelection)
      .eq('user_id', userId)
      .eq('source_request_hash', sourceRequestHash)
      .maybeSingle()
    if (error) databaseFailure('find_by_request_hash', error)
    return data ? parseMediaAsset(data) : null
  }

  return {
    findByRequestHash,
    async create(input) {
      const { data, error } = await supabase
        .from('media_assets')
        .insert({
          id: input.id,
          user_id: input.userId,
          kind: input.kind,
          bucket_id: input.bucketId,
          object_path: input.objectPath,
          mime_type: input.mimeType,
          declared_size_bytes: input.declaredSizeBytes,
          context_text: input.contextText,
          source_request_hash: input.sourceRequestHash,
          retention_until: input.retentionUntil,
        })
        .select(mediaSelection)
        .maybeSingle()
      if (error?.code === '23505') {
        const existing = await findByRequestHash(input.userId, input.sourceRequestHash)
        if (existing) return existing
      }
      if (error || !data) databaseFailure('create', error)
      return parseMediaAsset(data)
    },
    async findOwned(userId, assetId) {
      const { data, error } = await supabase
        .from('media_assets')
        .select(mediaSelection)
        .eq('id', assetId)
        .eq('user_id', userId)
        .maybeSingle()
      if (error) databaseFailure('find_owned', error)
      return data ? parseMediaAsset(data) : null
    },
    async markUploaded(userId, assetId, details) {
      const { data, error } = await supabase
        .from('media_assets')
        .update({
          status: 'uploaded',
          actual_size_bytes: details.actualSizeBytes,
          etag: details.etag,
          uploaded_at: details.uploadedAt,
        })
        .eq('id', assetId)
        .eq('user_id', userId)
        .eq('status', 'pending_upload')
        .select(mediaSelection)
        .maybeSingle()
      if (error || !data) databaseFailure('mark_uploaded', error)
      return parseMediaAsset(data)
    },
    async markUploadFailed(userId, assetId, failureCode) {
      const { error } = await supabase
        .from('media_assets')
        .update({
          status: 'failed',
          failure_stage: 'upload',
          failure_code: failureCode,
        })
        .eq('id', assetId)
        .eq('user_id', userId)
        .eq('status', 'pending_upload')
      if (error) databaseFailure('mark_upload_failed', error)
    },
    async markDeleted(userId, assetId, deletedAt) {
      const { data, error } = await supabase
        .from('media_assets')
        .update({
          status: 'deleted',
          deleted_at: deletedAt,
          failure_stage: null,
          failure_code: null,
          processing_result: null,
        })
        .eq('id', assetId)
        .eq('user_id', userId)
        .neq('status', 'deleted')
        .select(mediaSelection)
        .maybeSingle()
      if (error || !data) databaseFailure('mark_deleted', error)
      return parseMediaAsset(data)
    },
  }
}

function createStorage(supabase: ServiceClient): MediaStorageGateway {
  return {
    async createSignedUpload(bucketId, objectPath) {
      const { data, error } = await supabase.storage
        .from(bucketId)
        .createSignedUploadUrl(objectPath, { upsert: false })
      if (error || !data)
        throw new MobileApiError(503, 'media_upload_url_failed', 'Upload unavailable')
      return { signedUrl: data.signedUrl }
    },
    async getObjectInfo(bucketId, objectPath) {
      const { data, error } = await supabase.storage.from(bucketId).info(objectPath)
      if (error) {
        if ([400, 404].includes(storageErrorStatus(error) ?? 0)) {
          throw new MobileApiError(409, 'media_upload_not_found', 'Uploaded media was not found')
        }
        throw new MobileApiError(503, 'media_storage_unavailable', 'Media storage is unavailable')
      }
      if (!data || typeof data.size !== 'number') {
        throw new MobileApiError(409, 'media_upload_not_found', 'Uploaded media was not found')
      }
      return {
        size: data.size,
        contentType: data.contentType ?? null,
        etag: data.etag ?? null,
      }
    },
    async createSignedDownload(bucketId, objectPath, expiresIn) {
      const { data, error } = await supabase.storage
        .from(bucketId)
        .createSignedUrl(objectPath, expiresIn, { download: false })
      if (error || !data) {
        throw new MobileApiError(503, 'media_download_url_failed', 'Download unavailable')
      }
      return data.signedUrl
    },
    async remove(bucketId, objectPath) {
      const { error } = await supabase.storage.from(bucketId).remove([objectPath])
      if (error) throw new MobileApiError(503, 'media_delete_failed', 'Media deletion failed')
    },
  }
}

export function createSupabaseMediaDependencies(supabase: ServiceClient): MediaServiceDependencies {
  return {
    repository: createRepository(supabase),
    storage: createStorage(supabase),
    events: {
      async sendProcessingRequested(input) {
        await inngest.send({
          id: `media-process:${input.assetId}:${input.requestId}`,
          name: 'media.asset.process.requested',
          data: input,
        })
      },
    },
  }
}
