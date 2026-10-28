import { onboardingCurrentEligibilityInputSchema } from './contracts'
import { captureCurrentClinicalState, currentClinicalError } from './current-clinical-state'
import { presentCurrentSignupEligibility } from './current-signup-eligibility'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { requireIdempotencyKey } from './idempotency'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRoute, type MobileRouteRuntime } from './route'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

/** Injection-only V2 eligibility. No writes, cached config or mounted default. */
export function createCurrentSignupEligibilityRoute(
  dependencies: { readonly enabled: boolean },
  runtime?: MobileRouteRuntime,
) {
  const enabled = dependencies.enabled === true
  const fixed =
    runtime &&
    Object.freeze({
      authenticate: runtime.authenticate.bind(runtime),
      authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
      createServiceClient: runtime.createServiceClient.bind(runtime),
      createRequestId: runtime.createRequestId.bind(runtime),
    })
  return createMobileRoute(async (context) => {
    if (!enabled)
      throw new MobileApiError(
        404,
        'mobile_current_signup_disabled',
        'Current eligibility unavailable',
      )
    const owner = authenticatedReevaluationOwner(structuredClone(context.auth))
    if (new URL(context.request.url).searchParams.size)
      throw new MobileApiError(422, 'validation_failed', 'Request validation failed')
    requireIdempotencyKey(context.request)
    const { version: _, ...body } = onboardingCurrentEligibilityInputSchema.parse(
      await readJsonBody(context.request, 4096),
    )
    const state = await captureCurrentClinicalState(
      createSupabaseCurrentClinicalStateSource(context.supabase),
      {
        userId: owner,
        mode: 'signup',
        body,
      },
    )
    if (!state.first_completion) throw currentClinicalError('changed')
    return mobileSuccess(presentCurrentSignupEligibility(state), context.requestId)
  }, fixed)
}
