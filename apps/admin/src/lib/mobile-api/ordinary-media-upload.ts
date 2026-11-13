import { z } from 'zod'
import { MobileApiError } from './http'
import type { MediaAssetRecord, MediaSignedUpload } from './media-service'

const uuid = z
  .string()
  .uuid()
  .refine((v) => v === v.toLowerCase())
const timestamp = z.string().datetime({ offset: true })
const assetSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    kind: z.enum(['audio_note', 'conversation_photo']),
    bucket_id: z.enum(['audio-notes', 'meal-photos']),
    object_path: z.string().min(1).max(512),
    mime_type: z.string().min(1).max(80),
    size_bytes: z.number().int().positive().max(26214400),
    status: z.enum(['pending_upload', 'uploaded', 'processing', 'processed', 'failed', 'deleted']),
    retention_until: timestamp,
  })
  .strict()
  .refine(
    (a) =>
      a.bucket_id === (a.kind === 'audio_note' ? 'audio-notes' : 'meal-photos') &&
      (a.kind === 'audio_note'
        ? a.mime_type.startsWith('audio/')
        : a.mime_type.startsWith('image/') && a.size_bytes <= 15728640) &&
      new RegExp(`^${a.user_id}/${a.id}\\.[a-z0-9]+$`).test(a.object_path),
  )
const ticketSchema = z
  .object({
    id: uuid,
    asset_id: uuid,
    user_id: uuid,
    prepared_at: timestamp,
    provider_expires_at: timestamp.nullable(),
    registered_at: timestamp.nullable(),
  })
  .strict()
  .refine((t) => (t.provider_expires_at === null) === (t.registered_at === null))
const preparedSchema = z
  .object({
    schema: z.literal('conversation.upload-prepared.v1'),
    asset: assetSchema,
    ticket: ticketSchema,
  })
  .strict()
const registeredSchema = z
  .object({ schema: z.literal('conversation.upload-registered.v1'), ticket: ticketSchema })
  .strict()
const currentSchema = z
  .object({ schema: z.literal('conversation.upload-state.v1'), asset: assetSchema })
  .strict()
export interface OrdinaryUploadScope {
  userId: string
  assetId: string
}
export interface OrdinaryMediaUploadDependencies {
  storageOrigin: string
  now(): Date
  nonce(): string
  prepare(scope: OrdinaryUploadScope, ticketId: string): Promise<unknown>
  sign(asset: z.infer<typeof assetSchema>): Promise<{ signedUrl: string }>
  register(scope: OrdinaryUploadScope, ticketId: string, expiresAt: string): Promise<unknown>
  current(scope: OrdinaryUploadScope): Promise<unknown>
}
export function ordinaryMediaUploadError(changed = false) {
  return new MobileApiError(
    changed ? 409 : 503,
    changed ? 'ordinary_media_upload_changed' : 'ordinary_media_upload_unavailable',
    'Media upload is unavailable',
  )
}
function identity(a: z.infer<typeof assetSchema>) {
  return JSON.stringify([
    a.id,
    a.user_id,
    a.kind,
    a.bucket_id,
    a.object_path,
    a.mime_type,
    a.size_bytes,
  ])
}
/** Decode only an exact Storage SDK response. Storage verifies the JWT on PUT;
 * these claims determine a private resweep deadline, never user authorization. */
function providerExpiry(value: string, asset: z.infer<typeof assetSchema>, origin: string): string {
  if (typeof value !== 'string' || value.length > 8192) throw ordinaryMediaUploadError()
  const base = new URL(origin),
    url = new URL(value),
    path = `${asset.bucket_id}/${asset.object_path}`
  if (
    base.protocol !== 'https:' ||
    base.username ||
    base.password ||
    base.pathname !== '/' ||
    base.search ||
    base.hash ||
    url.origin !== base.origin ||
    url.username ||
    url.password ||
    url.hash ||
    url.pathname !== `/storage/v1/object/upload/sign/${path}` ||
    [...url.searchParams.keys()].join(',') !== 'token'
  )
    throw ordinaryMediaUploadError()
  const parts = (url.searchParams.get('token') ?? '').split('.')
  if (
    parts.length !== 3 ||
    parts.some(
      (p) => !/^[A-Za-z0-9_-]+$/.test(p) || Buffer.from(p, 'base64url').toString('base64url') !== p,
    )
  )
    throw ordinaryMediaUploadError()
  const header = z
    .object({
      alg: z
        .string()
        .min(1)
        .refine((a) => a.toLowerCase() !== 'none'),
    })
    .parse(JSON.parse(Buffer.from(parts[0] ?? '', 'base64url').toString('utf8')))
  if (!header.alg) throw ordinaryMediaUploadError()
  const claims = z
    .object({
      exp: z.number().int().positive().safe(),
      url: z.literal(path),
      upsert: z.literal(false),
    })
    .parse(JSON.parse(Buffer.from(parts[1] ?? '', 'base64url').toString('utf8')))
  const expiry = new Date(claims.exp * 1000)
  if (!Number.isFinite(expiry.getTime()) || expiry.getUTCFullYear() > 9999)
    throw ordinaryMediaUploadError()
  return expiry.toISOString()
}
/** One frozen ordinary asset, with durable prepare before external signing.
 * Registration is independent of current catalogue existence, so late responses
 * still reopen cleanup debt. No default route activation or raw error output. */
export async function issueOrdinaryMediaUpload(
  deps: OrdinaryMediaUploadDependencies,
  original: MediaAssetRecord,
): Promise<MediaSignedUpload> {
  try {
    const expected = assetSchema.parse({
      id: original.id,
      user_id: original.user_id,
      kind: original.kind,
      bucket_id: original.bucket_id,
      object_path: original.object_path,
      mime_type: original.mime_type,
      size_bytes: original.declared_size_bytes,
      status: original.status,
      retention_until: original.retention_until,
    })
    const frozenIdentity = identity(expected),
      scope = Object.freeze({ userId: expected.user_id, assetId: expected.id }),
      ticketId = uuid.parse(deps.nonce())
    const prepared = preparedSchema.parse(await deps.prepare(scope, ticketId)),
      ticket = prepared.ticket
    if (
      identity(prepared.asset) !== frozenIdentity ||
      prepared.asset.status !== 'pending_upload' ||
      ticket.id !== ticketId ||
      ticket.asset_id !== scope.assetId ||
      ticket.user_id !== scope.userId ||
      ticket.provider_expires_at !== null ||
      ticket.registered_at !== null
    )
      throw ordinaryMediaUploadError()
    const signed = await deps.sign(prepared.asset),
      responseAt = deps.now().getTime()
    const expiresAt = providerExpiry(signed.signedUrl, prepared.asset, deps.storageOrigin)
    // Persist first: changed authority, provider clock anomalies and expiration
    // must not erase a capability that might already exist at Storage.
    const registered = registeredSchema.parse(
      await deps.register(scope, ticketId, expiresAt),
    ).ticket
    if (
      registered.id !== ticket.id ||
      registered.asset_id !== ticket.asset_id ||
      registered.user_id !== ticket.user_id ||
      registered.prepared_at !== ticket.prepared_at ||
      registered.provider_expires_at === null ||
      Date.parse(registered.provider_expires_at) !== Date.parse(expiresAt) ||
      registered.registered_at === null ||
      Date.parse(registered.registered_at) < Date.parse(ticket.prepared_at)
    )
      throw ordinaryMediaUploadError()
    if (!Number.isFinite(responseAt) || Date.parse(expiresAt) > responseAt + (7200 + 120) * 1000)
      throw ordinaryMediaUploadError()
    const rawCurrent = await deps.current(scope)
    if (rawCurrent === null) throw ordinaryMediaUploadError(true)
    const current = currentSchema.parse(rawCurrent).asset
    const now = deps.now().getTime()
    if (
      identity(current) !== frozenIdentity ||
      current.status !== 'pending_upload' ||
      !Number.isFinite(now) ||
      Date.parse(current.retention_until) <= now ||
      Date.parse(expiresAt) <= now
    )
      throw ordinaryMediaUploadError(true)
    return {
      signed_url: signed.signedUrl,
      method: 'PUT',
      headers: { 'Content-Type': current.mime_type, 'x-upsert': 'false' },
      expires_at: expiresAt,
    }
  } catch (error) {
    throw ordinaryMediaUploadError(error instanceof MobileApiError && error.status === 409)
  }
}
