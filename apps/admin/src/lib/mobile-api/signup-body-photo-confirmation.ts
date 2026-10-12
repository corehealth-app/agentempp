import type { OnboardingCompletionInput } from './contracts'
import { MobileApiError } from './http'
import { asStoredBodyValue } from './protocol-eligibility-service'
import type { MobileRouteContext } from './route'
import {
  assertSignupBodyPhotoAge,
  type SignupBodyPhotoConsentDto,
  type SignupBodyPhotoPoseDto,
  signupBodyPhotosUnavailable,
} from './signup-body-photo-service'

export type OfficialOnboardingSubmission = Omit<
  OnboardingCompletionInput,
  'body_photo_confirmation'
>
export interface SignupPhotoSourceIds {
  front: string
  side: string
  back: string
}
export interface SignupPhotoGenerationToken {
  onboarding_completed: boolean
  onboarding_completed_at: string | null
  receipt_count: number
}
export interface SignupPhotoSnapshot {
  version: 1
  user_id: string
  profile_present: boolean
  locale: string | null
  timezone: string | null
  generation_token: SignupPhotoGenerationToken
  poses: SignupBodyPhotoPoseDto[]
  remaining_uploads: number
  consent: (SignupBodyPhotoConsentDto & { legal_document_id: string }) | null
  estimate: {
    is_estimate: true
    /** Optional only for older v1 snapshots. Numbers belong to their actual slots. */
    readings?: Array<{ pose: 'front' | 'side' | 'back'; body_fat_percent: number }>
    by_sex: {
      masculino:
        | { usable: true; body_fat_percent: number }
        | { usable: false; reason: 'out_of_range' }
      feminino:
        | { usable: true; body_fat_percent: number }
        | { usable: false; reason: 'out_of_range' }
    }
  } | null
  candidate: {
    method: 'arithmetic_mean_v1'
    body_fat_percent: number
    source_ids: SignupPhotoSourceIds
    fingerprint: string
  } | null
  confirmation: {
    decision: 'accepted' | 'declined'
    method: 'arithmetic_mean_v1' | null
    source_ids: SignupPhotoSourceIds | null
    fingerprint: string | null
    confirmed_body_fat_percent: number | null
    decided_at: string
    invalidated_at: string | null
    active: boolean
  } | null
}
export interface SignupPhotoConfirmationDependencies {
  targetAllowed: boolean
  photosEnabled: boolean
  loadSnapshot(userId: string, includeOpenPhotos: boolean): Promise<SignupPhotoSnapshot>
}
export interface PreparedSignupPhotoConfirmation {
  original: OnboardingCompletionInput
  effectiveSubmission: OfficialOnboardingSubmission
  mode: 'legacy' | 'manual' | 'decline' | 'fresh_accept' | 'historic_accept'
  snapshot: SignupPhotoSnapshot | null
}

function sameSources(left: SignupPhotoSourceIds, right: SignupPhotoSourceIds): boolean {
  return (['front', 'side', 'back'] as const).every(
    (pose) => left[pose].toLowerCase() === right[pose].toLowerCase(),
  )
}

function unavailableConfirmation(): never {
  throw new MobileApiError(
    409,
    'body_photo_confirmation_unavailable',
    'No official body photo estimate is available to confirm',
  )
}

/** Preclaim only. The checked SQL wrapper must revalidate and persist atomically. */
export async function prepareSignupPhotoConfirmation(
  context: Pick<MobileRouteContext, 'auth'>,
  input: OnboardingCompletionInput,
  dependencies: SignupPhotoConfirmationDependencies,
  now = new Date(),
): Promise<PreparedSignupPhotoConfirmation> {
  const { body_photo_confirmation: intent, ...official } = input
  if (!dependencies.targetAllowed) {
    if (intent) throw signupBodyPhotosUnavailable()
    return { original: input, effectiveSubmission: official, mode: 'legacy', snapshot: null }
  }

  let snapshot: SignupPhotoSnapshot
  try {
    snapshot = await dependencies.loadSnapshot(
      context.auth.userId,
      intent?.decision === 'accept' && dependencies.photosEnabled,
    )
  } catch (error) {
    if (error instanceof MobileApiError) throw error
    throw new MobileApiError(500, 'data_access_failed', 'Body photo snapshot lookup failed')
  }
  if (snapshot.user_id.toLowerCase() !== context.auth.userId.toLowerCase()) {
    throw new MobileApiError(500, 'data_access_failed', 'Body photo snapshot owner mismatch')
  }
  const prepared: PreparedSignupPhotoConfirmation = {
    original: input,
    effectiveSubmission: official,
    mode: 'manual',
    snapshot,
  }
  if (!intent) return prepared
  if (!snapshot.profile_present) throw signupBodyPhotosUnavailable()

  if (intent.decision === 'decline') {
    if (
      snapshot.confirmation?.decision === 'accepted' ||
      (snapshot.generation_token.onboarding_completed_at !== null &&
        snapshot.confirmation?.decision !== 'declined')
    )
      unavailableConfirmation()
    return { ...prepared, mode: 'decline' }
  }

  let value: number
  let sources: SignupPhotoSourceIds
  let fingerprint: string
  if (snapshot.generation_token.onboarding_completed_at !== null) {
    const receipt = snapshot.confirmation
    if (
      !snapshot.generation_token.onboarding_completed ||
      receipt?.decision !== 'accepted' ||
      receipt.method !== 'arithmetic_mean_v1' ||
      receipt.source_ids === null ||
      receipt.fingerprint === null ||
      receipt.confirmed_body_fat_percent === null
    )
      unavailableConfirmation()
    value = receipt.confirmed_body_fat_percent
    sources = receipt.source_ids
    fingerprint = receipt.fingerprint
    prepared.mode = 'historic_accept'
  } else {
    if (snapshot.generation_token.onboarding_completed) unavailableConfirmation()
    if (!dependencies.photosEnabled) throw signupBodyPhotosUnavailable()
    assertSignupBodyPhotoAge(input.birth_date, snapshot.timezone, now)
    if (!snapshot.consent) throw signupBodyPhotosUnavailable()
    if (snapshot.locale !== input.locale || snapshot.consent?.locale !== input.locale) {
      throw new MobileApiError(
        409,
        'body_photo_consent_locale_changed',
        'Reload body photo consent for the current account language',
      )
    }
    if (!snapshot.consent.accepted_at) {
      throw new MobileApiError(
        403,
        'body_photo_consent_required',
        'Accept the body photo consent first',
      )
    }
    if (!snapshot.candidate) unavailableConfirmation()
    value = snapshot.candidate.body_fat_percent
    sources = snapshot.candidate.source_ids
    fingerprint = snapshot.candidate.fingerprint
    prepared.mode = 'fresh_accept'
  }

  if (!Number.isFinite(value) || value < 3 || value > 60 || asStoredBodyValue(value) !== value) {
    throw new MobileApiError(500, 'data_access_failed', 'Invalid official body photo value')
  }
  if (!sameSources(intent.source_ids, sources) || intent.fingerprint !== fingerprint) {
    throw new MobileApiError(409, 'body_photo_confirmation_stale', 'Reload the body photo estimate')
  }
  if (input.body_fat_percent !== undefined && asStoredBodyValue(input.body_fat_percent) !== value) {
    throw new MobileApiError(
      422,
      'body_photo_confirmation_value_mismatch',
      'The supplied body value differs from the confirmed estimate',
    )
  }
  prepared.effectiveSubmission = { ...official, body_fat_percent: value }
  return prepared
}
