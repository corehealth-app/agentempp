import { loadCalcConfig } from '@mpp/agent'
import type { CalcConfig } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { onboardingEligibilityInputSchema } from '@/lib/mobile-api/contracts'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { requireIdempotencyKey } from '@/lib/mobile-api/idempotency'
import { resolveOnboardingEligibility } from '@/lib/mobile-api/protocol-eligibility-service'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

export interface OnboardingEligibilityRouteDependencies {
  loadCalcConfig(client: ServiceClient): Promise<CalcConfig>
}

const defaultDependencies: OnboardingEligibilityRouteDependencies = { loadCalcConfig }

/**
 * Answers which objectives the sign-up may record for the body values sent.
 *
 * It WRITES NOTHING. Its only database access is the read of the calc config
 * (the same loader the daily state uses); what runs before it is the
 * authentication every route shares. The `Idempotency-Key` header is
 * required, as on every POST, but no idempotency record is claimed or kept:
 * the answer depends only on the request and on the config, and the record
 * would hold the person's body values. Nothing of the request is logged.
 */
export async function handleOnboardingEligibilityPost(
  context: MobileRouteContext,
  dependencies: OnboardingEligibilityRouteDependencies = defaultDependencies,
): Promise<Response> {
  const input = onboardingEligibilityInputSchema.parse(await readJsonBody(context.request))
  requireIdempotencyKey(context.request)

  let config: CalcConfig
  try {
    config = await dependencies.loadCalcConfig(context.supabase)
  } catch {
    // The cuts come from the config: without it nothing is decided.
    throw new MobileApiError(500, 'data_access_failed', 'Calculation config lookup failed')
  }

  return mobileSuccess(resolveOnboardingEligibility(input, config), context.requestId)
}
