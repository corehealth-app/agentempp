import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'
import { loadSignupPhotoSnapshot } from './signup-body-photo-snapshot'

export type ProgressBodyFatOrigin = 'signup_photos' | null

// Preserve the same DB timestamp literal as B4b. Do not collapse microseconds
// into Date milliseconds, round, or invent a normalization/tolerance contract.
const instant = z
  .string()
  .max(64)
  .datetime({ offset: true })
  .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/)
const profileIdentitySchema = z.object({
  user_id: z.string().uuid(),
  onboarding_completed: z.boolean(),
  onboarding_completed_at: instant.nullable(),
})

function originLookupFailed(): never {
  throw new MobileApiError(500, 'data_access_failed', 'Progress body fat origin lookup failed')
}

/** Presentation only, for a BF already selected from the profile fallback. */
export async function loadProgressBodyFatOrigin(
  client: ServiceClient,
  userId: string,
  profile: unknown,
  selectedBodyFatPercent: number,
): Promise<ProgressBodyFatOrigin> {
  const parsed = profileIdentitySchema.safeParse(profile)
  if (
    !parsed.success ||
    parsed.data.user_id.toLowerCase() !== userId.toLowerCase() ||
    !Number.isFinite(selectedBodyFatPercent)
  )
    return originLookupFailed()
  const row = parsed.data
  // Keep this loader's established typed 404 exception and safe 500 errors.
  // Its canonical closed projection validates the receipt, not public hints.
  const snapshot = await loadSignupPhotoSnapshot(client, userId, false)
  const generation = snapshot.generation_token
  if (
    !snapshot.profile_present ||
    snapshot.user_id.toLowerCase() !== row.user_id.toLowerCase() ||
    generation.onboarding_completed !== row.onboarding_completed ||
    generation.onboarding_completed_at !== row.onboarding_completed_at
  )
    return originLookupFailed()
  const receipt = snapshot.confirmation
  // A null current receipt may coexist with older receipts on the account or
  // a legitimate legacy completed profile with no completed-at timestamp.
  if (receipt === null || receipt.decision === 'declined') return null
  if (generation.onboarding_completed_at === null || generation.receipt_count < 1)
    return originLookupFailed()
  // Historical invalidated proof may retain a prior value after manual edits.
  // An uninvalidated accepted value mismatch is an error even when active=false.
  if (
    receipt.invalidated_at === null &&
    receipt.confirmed_body_fat_percent !== selectedBodyFatPercent
  )
    return originLookupFailed()
  const active =
    receipt.decision === 'accepted' &&
    receipt.method === 'arithmetic_mean_v1' &&
    receipt.invalidated_at === null &&
    generation.onboarding_completed &&
    receipt.confirmed_body_fat_percent === selectedBodyFatPercent
  if (receipt.active !== active) return originLookupFailed()
  return active ? 'signup_photos' : null
}
