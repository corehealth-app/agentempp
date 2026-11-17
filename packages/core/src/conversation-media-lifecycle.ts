import { z } from 'zod'
import { conversationMediaIdentityV2Schema } from './conversation-media-namespace'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const instant = z.string().datetime({ offset: true })
const hash = z.string().regex(/^[0-9a-f]{64}$/)
const status = z.enum([
  'pending_upload',
  'uploaded',
  'processing',
  'processed',
  'failed',
  'deleted',
])
const retentionMs = 30 * 24 * 60 * 60 * 1000

const rawAsset = z
  .object({
    id: uuid,
    user_id: uuid,
    kind: z.enum(['conversation_photo', 'audio_note']),
    bucket_id: z.enum(['meal-photos', 'audio-notes']),
    object_path: z.string().max(512),
    mime_type: z.string(),
    declared_size_bytes: z.number().int().positive().max(26214400),
    actual_size_bytes: z.number().int().positive().nullable(),
    etag: z.string().max(512).nullable(),
    status,
    failure_stage: z.enum(['upload', 'processing']).nullable(),
    failure_code: z.string().max(100).nullable(),
    context_text: z.string().min(1).max(1000).nullable(),
    processing_request_id: hash.nullable(),
    processing_result: z.unknown().nullable(),
    source_request_hash: hash,
    retention_until: instant,
    uploaded_at: instant.nullable(),
    processed_at: instant.nullable(),
    deleted_at: instant.nullable(),
    created_at: instant,
    updated_at: instant,
  })
  .strict()

function identityOf(value: z.infer<typeof rawAsset>) {
  return {
    catalog_version: 2 as const,
    asset_id: value.id,
    user_id: value.user_id,
    kind: value.kind,
    bucket_id: value.bucket_id,
    object_path: value.object_path,
    mime_type: value.mime_type,
    declared_size_bytes: value.declared_size_bytes,
  }
}

export const privateMediaAssetV2Schema = rawAsset.refine((value) => {
  const created = Date.parse(value.created_at),
    updated = Date.parse(value.updated_at)
  return (
    conversationMediaIdentityV2Schema.safeParse(identityOf(value)).success &&
    Date.parse(value.retention_until) - created === retentionMs &&
    updated >= created &&
    (value.actual_size_bytes === null || value.actual_size_bytes === value.declared_size_bytes) &&
    (value.status === 'failed'
      ? value.failure_stage !== null && value.failure_code !== null
      : value.failure_stage === null && value.failure_code === null) &&
    (!['uploaded', 'processing', 'processed'].includes(value.status) ||
      (value.actual_size_bytes !== null && value.uploaded_at !== null)) &&
    (!['processing', 'processed'].includes(value.status) || value.processing_request_id !== null) &&
    (value.status === 'processed'
      ? value.processed_at !== null &&
        value.processing_result !== null &&
        typeof value.processing_result === 'object' &&
        !Array.isArray(value.processing_result)
      : value.processing_result === null) &&
    (value.status !== 'deleted' || value.deleted_at !== null) &&
    [value.uploaded_at, value.processed_at, value.deleted_at].every(
      (time) => time === null || (Date.parse(time) >= created && Date.parse(time) <= updated),
    )
  )
})
export type PrivateMediaAssetV2 = z.infer<typeof privateMediaAssetV2Schema>
export function privateMediaIdentityOfV2(value: PrivateMediaAssetV2) {
  return conversationMediaIdentityV2Schema.parse(identityOf(value))
}
export const privateMediaAssetReplyV2Schema = z
  .object({
    schema: z.literal('conversation.media-asset.v2'),
    catalog_version: z.literal(2),
    asset: privateMediaAssetV2Schema,
  })
  .strict()

const state = z
  .object({ status, created_at: instant, retention_until: instant })
  .strict()
  .refine(
    (value) => Date.parse(value.retention_until) - Date.parse(value.created_at) === retentionMs,
  )
const wireAsset = z.object({ identity: conversationMediaIdentityV2Schema, state }).strict()
const ticket = z
  .object({
    id: uuid,
    asset_id: uuid,
    user_id: uuid,
    prepared_at: instant,
    provider_expires_at: instant.nullable(),
    registered_at: instant.nullable(),
  })
  .strict()
  .refine(
    (value) =>
      (value.provider_expires_at === null) === (value.registered_at === null) &&
      (value.registered_at === null ||
        Date.parse(value.registered_at) >= Date.parse(value.prepared_at)),
  )

export const privateMediaUploadPreparedV2Schema = z
  .object({
    schema: z.literal('conversation.upload-prepared.v2'),
    asset: wireAsset,
    ticket,
  })
  .strict()
  .refine(
    (value) =>
      value.asset.state.status === 'pending_upload' &&
      value.ticket.asset_id === value.asset.identity.asset_id &&
      value.ticket.user_id === value.asset.identity.user_id &&
      value.ticket.provider_expires_at === null &&
      value.ticket.registered_at === null,
  )
export const privateMediaUploadRegisteredV2Schema = z
  .object({
    schema: z.literal('conversation.upload-registered.v2'),
    ticket,
  })
  .strict()
  .refine(
    (value) => value.ticket.provider_expires_at !== null && value.ticket.registered_at !== null,
  )
export const privateMediaUploadStateV2Schema = z
  .object({
    schema: z.literal('conversation.upload-state.v2'),
    asset: wireAsset,
  })
  .strict()
  .refine((value) => value.asset.state.status === 'pending_upload')

const claimed = z
  .object({
    schema: z.literal('conversation.media-processing-claim.v2'),
    action: z.literal('claimed'),
    asset: z
      .object({
        identity: conversationMediaIdentityV2Schema,
        state,
        context_text: z.string().min(1).max(1000).nullable(),
        processing_request_id: hash,
      })
      .strict(),
    claim: z.object({ token: uuid, lease_until: instant }).strict(),
  })
  .strict()
  .refine(
    (value) =>
      value.asset.state.status === 'processing' &&
      Date.parse(value.claim.lease_until) > Date.parse(value.asset.state.created_at),
  )
const busy = z
  .object({
    schema: z.literal('conversation.media-processing-claim.v2'),
    action: z.literal('busy'),
    retry_at: instant,
  })
  .strict()
const unavailable = z
  .object({
    schema: z.literal('conversation.media-processing-claim.v2'),
    action: z.literal('unavailable'),
  })
  .strict()
export const privateMediaProcessingClaimV2Schema = z.union([claimed, busy, unavailable])
export type PrivateMediaProcessingClaimV2 = z.infer<typeof privateMediaProcessingClaimV2Schema>
