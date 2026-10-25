import { z } from 'zod'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

// Supabase signed uploads last two hours. Permit bounded cross-server clock
// skew, never extend the bound by time spent in registration/current RPCs.
const PROVIDER_UPLOAD_LIFETIME_SECONDS = 7200
const PROVIDER_CLOCK_SKEW_SECONDS = 120

const timestamp = z.string().refine((value) => {
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/.test(value) || value.startsWith('0000'))
    return false
  const ms = `${value.slice(0, 23)}Z`
  const date = new Date(ms)
  return Number.isFinite(date.getTime()) && date.toISOString() === ms
})
const revision = z
  .string()
  .regex(/^[1-9][0-9]{0,18}$/)
  .refine((value) => value.length < 19 || value <= '9223372036854775807')
const extensions = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'image/heif': 'heif',
} as const
const assetSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    signup_generation: uuid,
    cycle_id: uuid,
    consent_acceptance_id: uuid,
    origin: z.literal('reevaluation_cycle_v1'),
    pose: z.enum(['front', 'side', 'back']),
    bucket_id: z.literal('body-checkin-photos'),
    object_path: z.string(),
    mime_type: z.enum(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
    size_bytes: z.number().int().min(1).max(15728640),
    status: z.enum(['pending_upload', 'uploaded', 'processing', 'processed', 'failed', 'deleted']),
    created_at: timestamp,
    retention_until: timestamp,
  })
  .strict()
  .refine((a) => a.object_path === `${a.user_id}/${a.id}.${extensions[a.mime_type]}`)
const assetWire = z
  .object({ version: z.literal(1), cycle_revision: revision, asset: assetSchema })
  .strict()

// Shared SQL identity contract; dedicated completion still adds its own
// authority/revision checks instead of using generic media completion.
export {
  assetWire as reevaluationPhotoAssetWireSchema,
  revision as reevaluationPhotoRevisionSchema,
  timestamp as reevaluationPhotoTimestampSchema,
}

const ticketSchema = z
  .object({
    id: uuid,
    asset_id: uuid,
    user_id: uuid,
    signup_generation: uuid,
    cycle_id: uuid,
    consent_acceptance_id: uuid,
    prepared_at: timestamp,
    provider_expires_at: timestamp.nullable(),
    registered_at: timestamp.nullable(),
  })
  .strict()
  .refine((t) => (t.provider_expires_at === null) === (t.registered_at === null))
const preparedSchema = assetWire.extend({ ticket: ticketSchema }).strict()
const receiptSchema = z.object({ version: z.literal(1), ticket: ticketSchema }).strict()
const scopeSchema = z.object({ userId: uuid, cycleId: uuid, assetId: uuid }).strict()
export type PhotoUploadScope = z.infer<typeof scopeSchema>
export type PhotoUploadAsset = z.infer<typeof assetSchema>
export type PreparedPhotoUpload = z.infer<typeof preparedSchema>

export interface ReevaluationPhotoUploadDependencies {
  storageOrigin: string
  now(): Date
  nonce(): string
  prepare(scope: PhotoUploadScope, ticketId: string): Promise<unknown>
  sign(asset: PhotoUploadAsset): Promise<{ signedUrl: string }>
  register(prepared: PreparedPhotoUpload, expiresAt: string): Promise<unknown>
  current(scope: PhotoUploadScope): Promise<unknown | null>
}

export function photoUploadError(kind: 'unavailable' | 'changed' | 'input' = 'unavailable') {
  return new MobileApiError(
    kind === 'changed' ? 409 : kind === 'input' ? 422 : 503,
    `mobile_reevaluation_photo_upload_${kind}`,
    'Photo upload is unavailable',
  )
}
function scoped(asset: PhotoUploadAsset, input: PhotoUploadScope) {
  return (
    asset.id === input.assetId && asset.user_id === input.userId && asset.cycle_id === input.cycleId
  )
}
export function parseCurrentPhotoUpload(value: unknown, scope: PhotoUploadScope) {
  const parsed = assetWire.safeParse(value)
  if (!parsed.success || !scoped(parsed.data.asset, scope)) throw photoUploadError()
  return parsed.data
}
export function parsePreparedPhotoUpload(
  value: unknown,
  scope: PhotoUploadScope,
  ticketId: string,
) {
  const parsed = preparedSchema.safeParse(value)
  if (!parsed.success) throw photoUploadError()
  const { asset, ticket } = parsed.data
  if (
    !scoped(asset, scope) ||
    ticket.id !== ticketId ||
    ticket.asset_id !== asset.id ||
    ticket.user_id !== asset.user_id ||
    ticket.cycle_id !== asset.cycle_id ||
    ticket.signup_generation !== asset.signup_generation ||
    ticket.consent_acceptance_id !== asset.consent_acceptance_id ||
    ticket.prepared_at < asset.created_at
  )
    throw photoUploadError()
  return parsed.data
}
export function parseRegisteredPhotoUpload(
  value: unknown,
  prepared: PreparedPhotoUpload,
  expiresAt: string,
) {
  const parsed = receiptSchema.safeParse(value)
  if (!parsed.success) throw photoUploadError()
  const ticket = parsed.data.ticket
  const { provider_expires_at: _expiry, registered_at: _at, ...identity } = ticket
  const {
    provider_expires_at: _previousExpiry,
    registered_at: _previousAt,
    ...expected
  } = prepared.ticket
  if (
    JSON.stringify(identity) !== JSON.stringify(expected) ||
    ticket.provider_expires_at === null ||
    ticket.registered_at === null ||
    ticket.registered_at < ticket.prepared_at ||
    Date.parse(ticket.provider_expires_at) !== Date.parse(expiresAt) ||
    ticket.provider_expires_at <= ticket.prepared_at
  )
    throw photoUploadError()
  return parsed.data
}

/** Metadata from the backend's own authenticated Storage response, not a user
 * JWT. Signature verification remains Storage's responsibility on PUT. */
function providerExpiry(signedUrl: string, asset: PhotoUploadAsset, storageOrigin: string): string {
  const base = new URL(storageOrigin)
  const url = new URL(signedUrl)
  const path = `${asset.bucket_id}/${asset.object_path}`
  if (
    base.protocol !== 'https:' ||
    base.username ||
    base.password ||
    base.pathname !== '/' ||
    base.search ||
    base.hash ||
    url.protocol !== 'https:' ||
    url.origin !== base.origin ||
    url.username ||
    url.password ||
    url.hash ||
    url.pathname !== `/storage/v1/object/upload/sign/${path}` ||
    [...url.searchParams.keys()].join(',') !== 'token'
  )
    throw photoUploadError()
  const parts = (url.searchParams.get('token') ?? '').split('.')
  if (
    parts.length !== 3 ||
    parts.some(
      (part) =>
        !/^[A-Za-z0-9_-]+$/.test(part) ||
        Buffer.from(part, 'base64url').toString('base64url') !== part,
    )
  )
    throw photoUploadError()
  const header = z
    .object({
      alg: z
        .string()
        .min(1)
        .refine((a) => a.toLowerCase() !== 'none'),
    })
    .parse(JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8')))
  if (!header.alg) throw photoUploadError()
  const claims = z
    .object({
      exp: z.number().int().positive().safe(),
      url: z.literal(path),
      upsert: z.literal(false),
    })
    .parse(JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')))
  const expiry = new Date(claims.exp * 1000)
  if (!Number.isFinite(expiry.getTime()) || expiry.getUTCFullYear() > 9999) throw photoUploadError()
  return expiry.toISOString()
}

/** No public route consumes this until upload/disposal/account purge are ready. */
export async function issueReevaluationPhotoUpload(
  deps: ReevaluationPhotoUploadDependencies,
  input: PhotoUploadScope,
) {
  const parsedInput = scopeSchema.safeParse(input)
  if (!parsedInput.success) throw photoUploadError('input')
  const scope = parsedInput.data
  try {
    const ticketId = uuid.parse(deps.nonce())
    const prepared = parsePreparedPhotoUpload(await deps.prepare(scope, ticketId), scope, ticketId)
    if (prepared.asset.status !== 'pending_upload' || prepared.ticket.provider_expires_at !== null)
      throw photoUploadError('changed')
    const signed = await deps.sign(prepared.asset)
    const signingResponseAt = deps.now().getTime()
    const expiresAt = providerExpiry(signed.signedUrl, prepared.asset, deps.storageOrigin)
    // Persist first, including when authorization closed during the external
    // await. Throwing after this independent commit cannot erase its expiry.
    parseRegisteredPhotoUpload(await deps.register(prepared, expiresAt), prepared, expiresAt)
    // Preserve the provider's actual expiry even for an anomalous capability,
    // but withhold its URL. Never truncate the stored resweep boundary.
    if (
      !Number.isFinite(signingResponseAt) ||
      Date.parse(expiresAt) >
        signingResponseAt + (PROVIDER_UPLOAD_LIFETIME_SECONDS + PROVIDER_CLOCK_SKEW_SECONDS) * 1000
    )
      throw photoUploadError()
    const current = await deps.current(scope)
    if (current === null) throw photoUploadError('changed')
    const fresh = parseCurrentPhotoUpload(current, scope)
    const { retention_until: _retention, ...before } = prepared.asset
    const { retention_until: _currentRetention, ...after } = fresh.asset
    if (JSON.stringify(before) !== JSON.stringify(after)) throw photoUploadError('changed')
    const now = deps.now().getTime()
    if (!Number.isFinite(now)) throw photoUploadError()
    if (Date.parse(expiresAt) <= now) throw photoUploadError('changed')
    return {
      asset: fresh.asset,
      upload: {
        signed_url: signed.signedUrl,
        method: 'PUT' as const,
        headers: { 'Content-Type': fresh.asset.mime_type, 'x-upsert': 'false' },
        expires_at: expiresAt,
      },
    }
  } catch (error) {
    // Never propagate raw provider/SQL failures, URLs or JWT contents.
    throw photoUploadError(
      error instanceof MobileApiError && error.status === 409 ? 'changed' : 'unavailable',
    )
  }
}
