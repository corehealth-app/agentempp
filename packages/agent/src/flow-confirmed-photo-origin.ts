/** Flow factual presentation only. No formula input or inferred public source. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'

// B4b keeps the official timestamp literal (including microseconds) in its CAS
// and repair contract. Both reads below come from the same DB timestamp column;
// compare validated literals, never Date milliseconds or rounded instants.
const instant = z
  .string()
  .max(64)
  .datetime({ offset: true })
  .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/)
const profileSchema = z.object({
  user_id: z.string().min(1),
  onboarding_completed: z.boolean(),
  onboarding_completed_at: instant.nullable(),
  body_fat_percent: z.number().finite(),
})
const confirmedValue = z
  .number()
  .finite()
  .min(3)
  .max(60)
  .refine((value) => /^\d+(?:\.\d{1,2})?$/.test(String(value)))
const confirmationSchema = z.discriminatedUnion('decision', [
  z.object({
    decision: z.literal('accepted'),
    method: z.literal('arithmetic_mean_v1'),
    confirmed_body_fat_percent: confirmedValue,
    invalidated_at: instant.nullable(),
    active: z.boolean(),
  }),
  z.object({
    decision: z.literal('declined'),
    method: z.null(),
    confirmed_body_fat_percent: z.null(),
    invalidated_at: z.null(),
    active: z.literal(false),
  }),
])
// Validate only the authority and closed-read projection. Other receipt fields
// (source IDs, fingerprint, decided_at) are not copied into the parsed value.
const snapshotSchema = z.object({
  version: z.literal(1),
  user_id: z.string().min(1),
  profile_present: z.boolean(),
  generation_token: z.object({
    onboarding_completed: z.boolean(),
    onboarding_completed_at: instant.nullable(),
    receipt_count: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),
  }),
  poses: z.array(z.never()).length(0),
  remaining_uploads: z.literal(0),
  consent: z.null(),
  estimate: z.null(),
  candidate: z.null(),
  confirmation: confirmationSchema.nullable(),
})

function lookupFailed(): never {
  // Context lookup errors already fail the turn. Never attach raw DB errors,
  // snapshots, source identities or fingerprints to an error or telemetry.
  throw new Error('Flow body photo origin lookup failed')
}

/** One existing profile-only RPC, once per relevant authenticated Flow context. */
export async function loadFlowConfirmedSignupPhotoBodyFat(
  client: ServiceClient,
  userId: string,
  profile: unknown,
): Promise<boolean> {
  const row = profileSchema.safeParse(profile)
  if (!row.success || row.data.user_id.toLowerCase() !== userId.toLowerCase()) lookupFailed()
  const rpc = client as unknown as {
    rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: unknown }>
  }
  let result: Awaited<ReturnType<typeof rpc.rpc>>
  try {
    result = await rpc.rpc('get_mobile_signup_body_photo_snapshot', {
      p_user_id: userId,
      p_include_open_photos: false,
    })
  } catch {
    return lookupFailed()
  }
  if (!result || result.error !== null) return lookupFailed()
  const parsed = snapshotSchema.safeParse(result.data)
  if (!parsed.success) return lookupFailed()
  const snapshot = parsed.data
  const generation = snapshot.generation_token
  if (
    snapshot.user_id.toLowerCase() !== userId.toLowerCase() ||
    !snapshot.profile_present ||
    generation.onboarding_completed !== row.data.onboarding_completed ||
    generation.onboarding_completed_at !== row.data.onboarding_completed_at
  )
    return lookupFailed()
  const receipt = snapshot.confirmation
  if (receipt === null) return false
  // A receipt is joined only by its official completed-at generation. Older
  // receipts may exist while an open/reopened profile has no current receipt.
  if (generation.onboarding_completed_at === null || generation.receipt_count < 1)
    return lookupFailed()
  if (receipt.decision === 'declined') return false
  // An uninvalidated accepted receipt cannot disagree with this context's
  // official BF, even when the snapshot reports active=false. Invalidated
  // proof may legitimately retain the former value after a manual edit.
  if (
    receipt.invalidated_at === null &&
    receipt.confirmed_body_fat_percent !== row.data.body_fat_percent
  )
    return lookupFailed()
  const active =
    receipt.invalidated_at === null &&
    generation.onboarding_completed &&
    receipt.confirmed_body_fat_percent === row.data.body_fat_percent
  if (receipt.active !== active) return lookupFailed()
  return active
}
