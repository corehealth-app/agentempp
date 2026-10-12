import type { ServiceClient } from '@mpp/db'
import { saveOnboarding } from '@/lib/mobile-api/commands'
import {
  type OnboardingCompletionInput,
  onboardingCompletionInputSchema,
  onboardingInputSchema,
} from '@/lib/mobile-api/contracts'
import { prepareEvaluationAccess } from '@/lib/mobile-api/evaluation-access'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent, requireIdempotencyKey } from '@/lib/mobile-api/idempotency'
import { assertOnboardingObjectiveEligible } from '@/lib/mobile-api/onboarding-eligibility-guard'
import {
  completeOnboarding,
  getOnboardingState,
  MAX_PUBLIC_ONBOARDING_STATE_BYTES,
  type OnboardingRepository,
} from '@/lib/mobile-api/onboarding-service'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import {
  readSignupBodyPhotoCleanupScope,
  signupCleanupGenerationSchema,
  signupCleanupScopeSchema,
} from '@/lib/mobile-api/signup-body-photo-cleanup-scope'
import {
  type PreparedSignupPhotoConfirmation,
  prepareSignupPhotoConfirmation,
} from '@/lib/mobile-api/signup-body-photo-confirmation'
import { signupBodyPhotosUnavailable } from '@/lib/mobile-api/signup-body-photo-service'
import { loadSignupPhotoSnapshot } from '@/lib/mobile-api/signup-body-photo-snapshot'
import { signupBodyPhotosEnabled } from '@/lib/mobile-api/signup-body-photo-switch'
import {
  createSupabaseOnboardingRepository,
  type SupabaseOnboardingOptions,
} from '@/lib/mobile-api/supabase-onboarding'
import {
  finalizeSignupBodyPhotosAfterOnboarding,
  signupBodyPhotoFinalizationTargetAllowed,
} from '@/lib/mobile-api/supabase-signup-body-photo-finalization'

export interface OnboardingRouteDependencies {
  createOnboardingRepository(
    client: ServiceClient,
    options?: SupabaseOnboardingOptions,
  ): OnboardingRepository
  executeIdempotent: typeof executeSupabaseIdempotent
  saveLegacyOnboarding: typeof saveOnboarding
  readSignupBodyPhotoCleanupScope?: typeof readSignupBodyPhotoCleanupScope
  finalizeSignupBodyPhotos(
    context: MobileRouteContext,
    input: OnboardingCompletionInput,
    generation: string,
  ): Promise<void>
}

const defaultDependencies: OnboardingRouteDependencies = {
  createOnboardingRepository: createSupabaseOnboardingRepository,
  executeIdempotent: executeSupabaseIdempotent,
  saveLegacyOnboarding: saveOnboarding,
  readSignupBodyPhotoCleanupScope,
  finalizeSignupBodyPhotos: finalizeSignupBodyPhotosAfterOnboarding,
}

function onboardingLocale(locale: string | null): 'pt-BR' | 'en-US' {
  if (locale === null || locale === 'pt-BR') return 'pt-BR'
  if (locale === 'en-US') return locale
  throw new MobileApiError(
    409,
    'onboarding_locale_unsupported',
    'Onboarding is not available for this locale',
  )
}

/**
 * What the idempotency record keeps of a completion: the response without
 * `protocol_welcome`. That text carries the person's name and is never read
 * back, because a replay rebuilds the whole response (`refreshReplay`).
 */
function completionBodyForStorage(body: unknown): unknown {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return body
  const envelope = body as Record<string, unknown>
  const data = envelope.data
  if (!data || typeof data !== 'object' || Array.isArray(data)) return body
  const {
    protocol_welcome: _welcome,
    body_photo_cleanup: _scope,
    ...stored
  } = data as Record<string, unknown>
  return { ...envelope, data: stored }
}

async function withCleanupScope<T extends object>(
  context: MobileRouteContext,
  dependencies: OnboardingRouteDependencies,
  data: T,
  generation: string | null,
) {
  if (
    !signupBodyPhotoFinalizationTargetAllowed() ||
    !dependencies.readSignupBodyPhotoCleanupScope ||
    generation === null ||
    !signupCleanupGenerationSchema.safeParse(generation).success
  )
    return data
  let scope = { generation, state: 'unknown' as 'unknown' | 'pending' | 'not_required' }
  try {
    const parsed = signupCleanupScopeSchema.safeParse(
      await dependencies.readSignupBodyPhotoCleanupScope(
        context.supabase,
        context.auth.userId,
        generation,
      ),
    )
    if (parsed.success && parsed.data.generation === generation) scope = parsed.data
  } catch {
    /* Official completion and base GET remain valid. */
  }
  return { ...data, body_photo_cleanup: scope }
}

export async function handleOnboardingGet(
  context: MobileRouteContext,
  dependencies: OnboardingRouteDependencies = defaultDependencies,
): Promise<Response> {
  const queries = new URL(context.request.url).searchParams.getAll('body_photo_cleanup_generation')
  if (
    queries.length > 1 ||
    (queries.length === 1 && !signupCleanupGenerationSchema.safeParse(queries[0]).success)
  )
    throw new MobileApiError(
      400,
      'invalid_body_photo_cleanup_generation',
      'Invalid cleanup generation',
    )
  const repository = dependencies.createOnboardingRepository(context.supabase)
  const data = await getOnboardingState(
    repository,
    context.auth.userId,
    onboardingLocale(context.auth.patient.locale),
  )
  const generation = queries[0] ?? data.completion.completed_at
  const enriched = await withCleanupScope(context, dependencies, data, generation)
  // Base DTO already passed its limit. If metadata alone exceeds it, omit metadata.
  return mobileSuccess(
    new TextEncoder().encode(JSON.stringify(enriched)).byteLength >
      MAX_PUBLIC_ONBOARDING_STATE_BYTES
      ? data
      : enriched,
    context.requestId,
  )
}

export async function handleOnboardingPost(
  context: MobileRouteContext,
  dependencies: OnboardingRouteDependencies = defaultDependencies,
): Promise<Response> {
  const body = await readJsonBody(context.request)
  const isCompletion = typeof body === 'object' && body !== null && 'document_actions' in body

  if (!isCompletion) {
    const input = onboardingInputSchema.parse(body)
    const safeInput = { ...input }
    delete safeInput.onboarding_completed
    return dependencies.executeIdempotent(context, safeInput, async (requestKey) =>
      mobileSuccess(
        await dependencies.saveLegacyOnboarding(
          context.supabase,
          context.auth,
          safeInput,
          requestKey,
        ),
        context.requestId,
      ),
    )
  }

  const input = onboardingCompletionInputSchema.parse(body)
  // A first completion asking for an objective the rule does not allow is
  // refused here (422, or 500 when the profile or the calc config cannot be
  // read), before anything is read for the grant or recorded. An account that
  // already has a completion time — a re-acceptance of documents, a replay —
  // is not checked and goes on as before. The submission reaches the SQL
  // function whole either way.
  //
  // It runs BEFORE the Idempotency-Key is claimed, on purpose. A claim that is
  // released stays in the ledger as 'failed', with the hash of the refused
  // request, and the ledger compares the hash before it looks at the state
  // (20260720130537_mobile_api_idempotency.sql): the same key sent again with
  // the objective corrected would be answered 409 idempotency_key_conflict,
  // and the published app keeps its key after a refusal. So the header is only
  // read here (without it the answer is still 400, before anything is read),
  // and a refusal leaves no record at all.
  requireIdempotencyKey(context.request)
  if (input.body_photo_confirmation && !signupBodyPhotoFinalizationTargetAllowed()) {
    throw signupBodyPhotosUnavailable()
  }
  const prepare = async () => {
    const prepared = await prepareSignupPhotoConfirmation(context, input, {
      targetAllowed: signupBodyPhotoFinalizationTargetAllowed(),
      photosEnabled: signupBodyPhotosEnabled(),
      loadSnapshot: async (owner, includeOpenPhotos) => {
        try {
          return await loadSignupPhotoSnapshot(context.supabase, owner, includeOpenPhotos)
        } catch (error) {
          if (
            error instanceof MobileApiError &&
            error.status === 500 &&
            error.code === 'data_access_failed'
          )
            throw new MobileApiError(
              500,
              'data_access_failed',
              'Onboarding completion lookup failed',
            )
          throw error
        }
      },
    })
    await assertOnboardingObjectiveEligible(
      context,
      prepared.effectiveSubmission,
      prepared.snapshot?.generation_token,
    )
    return prepared
  }
  const prepared = await prepare()
  const createResponse = async (current: PreparedSignupPhotoConfirmation) => {
    const repository = dependencies.createOnboardingRepository(context.supabase, {
      signupPhotoConfirmation: current,
    })
    // Evaluation access is off unless the test environment switched it on
    // (see the module header); off, it reads nothing and the returned function
    // does nothing. It is asked before the completion is recorded because
    // only a first completion is eligible. Neither call can throw.
    const grantEvaluationAccess = await prepareEvaluationAccess(context)
    const data = await completeOnboarding(repository, context.auth.userId, input)
    await grantEvaluationAccess()
    // Completion is already accepted. A photo failure cannot undo it or
    // release its idempotency claim. The default hook has its own budget.
    try {
      await dependencies.finalizeSignupBodyPhotos(context, input, data.completed_at)
    } catch {
      console.warn('[mobile-signup-body-photos] finalization_hook_failed')
    }
    return mobileSuccess(
      await withCleanupScope(context, dependencies, data, data.completed_at),
      context.requestId,
    )
  }
  return dependencies.executeIdempotent(context, input, () => createResponse(prepared), {
    refreshReplay: async () =>
      createResponse(prepared.mode === 'legacy' ? prepared : await prepare()),
    responseBodyForStorage: completionBodyForStorage,
  })
}
