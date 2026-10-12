import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'
import { asStoredBodyValue } from './protocol-eligibility-service'
import type { SignupPhotoSnapshot } from './signup-body-photo-confirmation'

const instant = z.string().datetime({ offset: true })
const fingerprint = z.string().regex(/^[0-9a-f]{64}$/)
const value = z
  .number()
  .finite()
  .min(3)
  .max(60)
  .refine((n) => asStoredBodyValue(n) === n)
const sourceIds = z
  .object({
    front: z.string().uuid(),
    side: z.string().uuid(),
    back: z.string().uuid(),
  })
  .strict()
  .refine((ids) => new Set(Object.values(ids).map((id) => id.toLowerCase())).size === 3)
const estimateValue = z.discriminatedUnion('usable', [
  z.object({ usable: z.literal(true), body_fat_percent: value }).strict(),
  z.object({ usable: z.literal(false), reason: z.literal('out_of_range') }).strict(),
])
const confirmation = z.discriminatedUnion('decision', [
  z
    .object({
      decision: z.literal('accepted'),
      method: z.literal('arithmetic_mean_v1'),
      source_ids: sourceIds,
      fingerprint,
      confirmed_body_fat_percent: value,
      decided_at: instant,
      invalidated_at: instant.nullable(),
      active: z.boolean(),
    })
    .strict(),
  z
    .object({
      decision: z.literal('declined'),
      method: z.null(),
      source_ids: z.null(),
      fingerprint: z.null(),
      confirmed_body_fat_percent: z.null(),
      decided_at: instant,
      invalidated_at: z.null(),
      active: z.literal(false),
    })
    .strict(),
])
const snapshotSchema = z
  .object({
    version: z.literal(1),
    user_id: z.string().uuid(),
    profile_present: z.boolean(),
    locale: z.string().nullable(),
    timezone: z.string().nullable(),
    generation_token: z
      .object({
        onboarding_completed: z.boolean(),
        onboarding_completed_at: instant.nullable(),
        receipt_count: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
      })
      .strict(),
    poses: z
      .array(
        z
          .object({
            pose: z.enum(['front', 'side', 'back']),
            photo: z
              .object({
                id: z.string().uuid(),
                status: z.enum(['uploaded', 'reading', 'read', 'unreadable', 'reading_failed']),
                created_at: instant,
              })
              .strict()
              .nullable(),
          })
          .strict(),
      )
      .max(3),
    remaining_uploads: z.number().int().min(0).max(9),
    consent: z
      .object({
        legal_document_id: z.string().uuid(),
        document_key: z.literal('body_photo_estimate_consent'),
        version: z.string().min(1),
        locale: z.enum(['pt-BR', 'en-US']),
        body: z.string().min(1),
        body_hash: fingerprint,
        accepted_at: instant.nullable(),
      })
      .strict()
      .nullable(),
    estimate: z
      .object({
        is_estimate: z.literal(true),
        by_sex: z.object({ masculino: estimateValue, feminino: estimateValue }).strict(),
      })
      .strict()
      .nullable(),
    candidate: z
      .object({
        method: z.literal('arithmetic_mean_v1'),
        body_fat_percent: value,
        source_ids: sourceIds,
        fingerprint,
      })
      .strict()
      .nullable(),
    confirmation: confirmation.nullable(),
  })
  .strict()

function lookupFailed(): never {
  // Never attach raw snapshots, consent text, readings or source identifiers.
  throw new MobileApiError(500, 'data_access_failed', 'Invalid body photo snapshot')
}

export async function loadSignupPhotoSnapshot(
  client: ServiceClient,
  userId: string,
  includeOpenPhotos: boolean,
): Promise<SignupPhotoSnapshot> {
  const rpc = client as unknown as {
    rpc(
      name: string,
      params: Record<string, unknown>,
    ): Promise<{
      data: unknown
      error: { code?: string; message?: string } | null
    }>
  }
  let result: Awaited<ReturnType<typeof rpc.rpc>>
  try {
    result = await rpc.rpc('get_mobile_signup_body_photo_snapshot', {
      p_user_id: userId,
      p_include_open_photos: includeOpenPhotos,
    })
  } catch {
    return lookupFailed()
  }
  if (result?.error?.code === 'P0002' && result.error.message === 'onboarding_user_not_found')
    throw new MobileApiError(404, 'patient_not_found', 'Patient profile not found')
  if (!result || result.error !== null) return lookupFailed()
  return parseSignupPhotoSnapshot(result.data, userId, includeOpenPhotos)
}

/** Validates one SQL snapshot; fingerprints remain opaque and server generated. */
export function parseSignupPhotoSnapshot(
  input: unknown,
  expectedUserId: string,
  includeOpenPhotos: boolean,
): SignupPhotoSnapshot {
  const parsed = snapshotSchema.safeParse(input)
  if (!parsed.success) return lookupFailed()
  const s = parsed.data
  if (s.user_id.toLowerCase() !== expectedUserId.toLowerCase()) return lookupFailed()
  const token = s.generation_token
  const open =
    s.profile_present && !token.onboarding_completed && token.onboarding_completed_at === null
  if (!s.profile_present && (token.onboarding_completed || token.onboarding_completed_at !== null))
    return lookupFailed()

  if (!includeOpenPhotos || !open) {
    if (
      s.poses.length !== 0 ||
      s.remaining_uploads !== 0 ||
      s.consent !== null ||
      s.estimate !== null ||
      s.candidate !== null
    )
      return lookupFailed()
  } else {
    if (s.poses.length !== 3 || s.poses.some((p, i) => p.pose !== ['front', 'side', 'back'][i]))
      return lookupFailed()
    const ids = s.poses.flatMap((p) => (p.photo ? [p.photo.id.toLowerCase()] : []))
    if (new Set(ids).size !== ids.length) return lookupFailed()
    if (s.consent === null) {
      if (
        s.remaining_uploads !== 0 ||
        ids.length !== 0 ||
        s.estimate !== null ||
        s.candidate !== null
      )
        return lookupFailed()
    } else if (
      s.consent.locale !== s.locale ||
      createHash('sha256').update(s.consent.body).digest('hex') !== s.consent.body_hash
    ) {
      return lookupFailed()
    }

    if (s.estimate !== null) {
      if (s.consent?.accepted_at == null || s.poses.some((p) => p.photo?.status !== 'read'))
        return lookupFailed()
      const { masculino, feminino } = s.estimate.by_sex
      if (masculino.usable !== feminino.usable) return lookupFailed()
      if (masculino.usable && feminino.usable) {
        if (
          !s.candidate ||
          masculino.body_fat_percent !== feminino.body_fat_percent ||
          masculino.body_fat_percent !== s.candidate.body_fat_percent
        )
          return lookupFailed()
      } else if (s.candidate !== null) return lookupFailed()
    } else if (s.candidate !== null) return lookupFailed()

    if (
      s.candidate &&
      s.poses.some(
        (p) => p.photo?.id.toLowerCase() !== s.candidate?.source_ids[p.pose].toLowerCase(),
      )
    )
      return lookupFailed()
  }

  if (s.confirmation) {
    if (!s.profile_present || token.onboarding_completed_at === null || token.receipt_count < 1)
      return lookupFailed()
    if (
      s.confirmation.active &&
      (!token.onboarding_completed || s.confirmation.invalidated_at !== null)
    )
      return lookupFailed()
  }
  return s
}
