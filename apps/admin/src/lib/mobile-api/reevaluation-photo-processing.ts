import { z } from 'zod'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  type PhotoUploadAsset,
  reevaluationPhotoAssetWireSchema,
  reevaluationPhotoRevisionSchema as revision,
  reevaluationPhotoTimestampSchema as timestamp,
} from './reevaluation-photo-upload'

const scopeSchema = z
  .object({ userId: uuid, cycleId: uuid, assetId: uuid, requestId: uuid })
  .strict()
const failureCode = z.enum([
  'storage_unavailable',
  'invalid_bytes',
  'provider_unavailable',
  'invalid_analysis',
])
const readingSchema = z
  .object({
    type: z.literal('body'),
    view: z.enum(['front', 'side', 'back']),
    bf_percent_estimate: z.number().finite().min(3).max(60),
  })
  .strict()
const attemptSchema = z
  .object({
    id: uuid,
    asset_id: uuid,
    user_id: uuid,
    signup_generation: uuid,
    cycle_id: uuid,
    consent_acceptance_id: uuid,
    pose: z.enum(['front', 'side', 'back']),
    source_revision: revision,
    processing_request_id: z.string().regex(/^[0-9a-f]{64}$/),
    claimed_at: timestamp,
    lease_until: timestamp,
    provider_started_at: timestamp.nullable(),
    provider_authorized_until: timestamp.nullable(),
    status: z.enum(['claimed', 'authorized', 'succeeded', 'failed', 'expired']),
    finished_at: timestamp.nullable(),
    result: readingSchema.nullable(),
    failure_code: failureCode.nullable(),
  })
  .strict()
const wireSchema = reevaluationPhotoAssetWireSchema
  .extend({ source_revision: revision, attempt: attemptSchema })
  .strict()
export type PhotoProcessingScope = z.infer<typeof scopeSchema>
export type PhotoProcessingWire = z.infer<typeof wireSchema>
export type PhotoProcessingReading = z.infer<typeof readingSchema>
export type PhotoProcessingFailure = z.infer<typeof failureCode>
export interface PhotoProviderBudget {
  signal: AbortSignal
  timeoutMs: number
}
export interface ReevaluationPhotoProcessingDependencies {
  now(): Date
  claim(scope: PhotoProcessingScope): Promise<unknown | null>
  download(asset: PhotoUploadAsset): Promise<Uint8Array>
  authorize(claim: PhotoProcessingWire): Promise<unknown | null>
  analyze(bytes: Uint8Array, mimeType: string, budget: PhotoProviderBudget): Promise<unknown>
  complete(claim: PhotoProcessingWire, result: PhotoProcessingReading): Promise<unknown>
  fail(claim: PhotoProcessingWire, code: PhotoProcessingFailure): Promise<boolean>
}
type Outcome =
  | { status: 'processed' }
  | { status: 'skipped' }
  | { status: 'failed'; reason: PhotoProcessingFailure }
export function photoProcessingError(changed = false) {
  return new MobileApiError(
    changed ? 409 : 503,
    `mobile_reevaluation_photo_processing_${changed ? 'changed' : 'unavailable'}`,
    'Photo processing is unavailable',
  )
}
function micros(value: string) {
  return BigInt(Date.parse(value)) * 1000n + BigInt(value.slice(23, 26))
}
export function parsePhotoProcessingWire(value: unknown, scope: PhotoProcessingScope) {
  const parsed = wireSchema.safeParse(value)
  if (!parsed.success) throw photoProcessingError()
  const w = parsed.data
  const a = w.asset
  const t = w.attempt
  if (
    a.id !== scope.assetId ||
    a.user_id !== scope.userId ||
    a.cycle_id !== scope.cycleId ||
    t.id !== scope.requestId ||
    t.asset_id !== a.id ||
    t.user_id !== a.user_id ||
    t.cycle_id !== a.cycle_id ||
    t.signup_generation !== a.signup_generation ||
    t.consent_acceptance_id !== a.consent_acceptance_id ||
    t.pose !== a.pose ||
    t.source_revision !== w.source_revision ||
    t.claimed_at < a.created_at ||
    t.lease_until <= t.claimed_at ||
    t.lease_until > a.retention_until ||
    micros(t.lease_until) - micros(t.claimed_at) > 300000000n ||
    (t.provider_started_at !== null &&
      (t.provider_started_at < t.claimed_at || t.provider_started_at >= t.lease_until)) ||
    (t.provider_started_at === null) !== (t.provider_authorized_until === null) ||
    (t.provider_authorized_until !== null &&
      (t.provider_authorized_until <= (t.provider_started_at ?? '') ||
        t.provider_authorized_until > t.lease_until)) ||
    (t.finished_at !== null && t.finished_at < (t.provider_started_at ?? t.claimed_at))
  )
    throw photoProcessingError()
  const active = t.status === 'claimed' || t.status === 'authorized'
  if (
    (active && (t.finished_at !== null || t.result !== null || t.failure_code !== null)) ||
    (t.status === 'claimed' && t.provider_started_at !== null) ||
    (t.status === 'authorized' && t.provider_started_at === null) ||
    (t.status === 'succeeded' &&
      (a.status !== 'processed' ||
        t.provider_started_at === null ||
        t.finished_at === null ||
        t.provider_authorized_until === null ||
        t.finished_at >= t.provider_authorized_until ||
        t.result === null ||
        t.result.view !== a.pose ||
        t.failure_code !== null)) ||
    (t.status !== 'succeeded' && a.status !== 'processing') ||
    (t.status === 'failed' &&
      (t.finished_at === null || t.result !== null || t.failure_code === null)) ||
    (t.status === 'expired' &&
      (t.finished_at === null || t.result !== null || t.failure_code !== null))
  )
    throw photoProcessingError()
  return w
}
function assetIdentity(a: PhotoUploadAsset) {
  const { status: _status, retention_until: _retention, ...identity } = a
  return identity
}
function attemptIdentity(t: PhotoProcessingWire['attempt']) {
  const {
    status: _status,
    provider_started_at: _start,
    provider_authorized_until: _deadline,
    finished_at: _end,
    result: _result,
    failure_code: _failure,
    ...identity
  } = t
  return identity
}
export function parsePhotoProcessingContinuation(
  value: unknown,
  before: PhotoProcessingWire,
  stage: 'authorized' | 'succeeded',
  reading?: PhotoProcessingReading,
) {
  const after = parsePhotoProcessingWire(value, {
    userId: before.asset.user_id,
    cycleId: before.asset.cycle_id,
    assetId: before.asset.id,
    requestId: before.attempt.id,
  })
  if (
    after.attempt.status !== stage ||
    after.source_revision !== before.source_revision ||
    BigInt(after.cycle_revision) < BigInt(before.cycle_revision) ||
    JSON.stringify(assetIdentity(after.asset)) !== JSON.stringify(assetIdentity(before.asset)) ||
    JSON.stringify(attemptIdentity(after.attempt)) !==
      JSON.stringify(attemptIdentity(before.attempt)) ||
    (stage === 'succeeded' &&
      (after.attempt.provider_started_at !== before.attempt.provider_started_at ||
        after.attempt.provider_authorized_until !== before.attempt.provider_authorized_until ||
        JSON.stringify(after.attempt.result) !== JSON.stringify(reading)))
  )
    throw photoProcessingError()
  return after
}
export function parsePhotoProcessingReading(value: unknown, pose: PhotoUploadAsset['pose']) {
  // Provider notes/usage/raw response may be present; none enters persistence.
  const parsed = readingSchema.strip().safeParse(value)
  if (!parsed.success || parsed.data.view !== pose) return null
  return parsed.data
}
function imageSignature(bytes: Uint8Array, mime: string) {
  const text = (start: number, length: number) =>
    String.fromCharCode(...bytes.slice(start, start + length))
  const prefix = (values: number[]) => values.every((v, i) => bytes[i] === v)
  if (mime === 'image/jpeg') return prefix([255, 216, 255])
  if (mime === 'image/png') return prefix([137, 80, 78, 71, 13, 10, 26, 10])
  if (mime === 'image/webp')
    return bytes.length >= 12 && text(0, 4) === 'RIFF' && text(8, 4) === 'WEBP'
  return (
    ['image/heic', 'image/heif'].includes(mime) &&
    bytes.length >= 12 &&
    text(4, 4) === 'ftyp' &&
    ['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(text(8, 4))
  )
}

/** No route/event/client startup consumes this before full disposal lifecycle.
 * Analyze is already configured: no async setup may follow the SQL fence. */
export async function processReevaluationPhoto(
  deps: ReevaluationPhotoProcessingDependencies,
  input: PhotoProcessingScope,
): Promise<Outcome> {
  const parsed = scopeSchema.safeParse(input)
  if (!parsed.success) throw photoProcessingError()
  try {
    const claimed = await deps.claim(parsed.data)
    if (claimed === null) return { status: 'skipped' }
    const before = parsePhotoProcessingWire(claimed, parsed.data)
    if (before.attempt.status === 'succeeded') return { status: 'processed' }
    if (before.attempt.status === 'failed' && before.attempt.failure_code !== null)
      return { status: 'failed', reason: before.attempt.failure_code }
    if (before.attempt.status !== 'claimed') return { status: 'skipped' }
    async function fail(code: PhotoProcessingFailure): Promise<Outcome> {
      const result = await deps.fail(before, code)
      if (typeof result !== 'boolean') throw photoProcessingError()
      return result ? { status: 'failed', reason: code } : { status: 'skipped' }
    }
    let bytes: Uint8Array
    try {
      bytes = await deps.download(before.asset)
    } catch {
      const closed = await fail('storage_unavailable')
      if (closed.status === 'skipped') return closed
      throw photoProcessingError()
    }
    if (
      !(bytes instanceof Uint8Array) ||
      bytes.length !== before.asset.size_bytes ||
      !imageSignature(bytes, before.asset.mime_type)
    )
      return await fail('invalid_bytes')
    const permission = await deps.authorize(before)
    if (permission === null) return { status: 'skipped' }
    const authorized = parsePhotoProcessingContinuation(permission, before, 'authorized')
    const now = deps.now().getTime()
    if (!Number.isFinite(now) || now < Date.parse(authorized.attempt.provider_started_at ?? ''))
      throw photoProcessingError()
    const remaining = Math.floor(
      Date.parse(authorized.attempt.provider_authorized_until ?? '') - now,
    )
    if (remaining <= 0) return { status: 'skipped' }
    const timeoutMs = Math.min(60000, remaining)
    const budget = { timeoutMs, signal: AbortSignal.timeout(timeoutMs) }
    let raw: unknown
    try {
      raw = await deps.analyze(bytes, authorized.asset.mime_type, budget)
    } catch {
      const closed = await fail('provider_unavailable')
      if (closed.status === 'skipped') return closed
      throw photoProcessingError()
    }
    const reading = parsePhotoProcessingReading(raw, authorized.asset.pose)
    if (reading === null) return await fail('invalid_analysis')
    // An ambiguous completion is never followed by fail or another paid call.
    // Retry of the same request observes the terminal private receipt, if any.
    parsePhotoProcessingContinuation(
      await deps.complete(authorized, reading),
      authorized,
      'succeeded',
      reading,
    )
    return { status: 'processed' }
  } catch (error) {
    if (error instanceof MobileApiError && error.status === 409) return { status: 'skipped' }
    throw photoProcessingError()
  }
}
