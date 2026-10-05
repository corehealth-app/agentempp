import type { ServiceClient } from '@mpp/db'
import { saveOnboarding } from '@/lib/mobile-api/commands'
import { onboardingCompletionInputSchema, onboardingInputSchema } from '@/lib/mobile-api/contracts'
import { prepareEvaluationAccess } from '@/lib/mobile-api/evaluation-access'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import {
  completeOnboarding,
  getOnboardingState,
  type OnboardingRepository,
} from '@/lib/mobile-api/onboarding-service'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import { createSupabaseOnboardingRepository } from '@/lib/mobile-api/supabase-onboarding'

export interface OnboardingRouteDependencies {
  createOnboardingRepository(client: ServiceClient): OnboardingRepository
  executeIdempotent: typeof executeSupabaseIdempotent
  saveLegacyOnboarding: typeof saveOnboarding
}

const defaultDependencies: OnboardingRouteDependencies = {
  createOnboardingRepository: createSupabaseOnboardingRepository,
  executeIdempotent: executeSupabaseIdempotent,
  saveLegacyOnboarding: saveOnboarding,
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

export async function handleOnboardingGet(
  context: MobileRouteContext,
  dependencies: OnboardingRouteDependencies = defaultDependencies,
): Promise<Response> {
  const repository = dependencies.createOnboardingRepository(context.supabase)
  return mobileSuccess(
    await getOnboardingState(
      repository,
      context.auth.userId,
      onboardingLocale(context.auth.patient.locale),
    ),
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
  const repository = dependencies.createOnboardingRepository(context.supabase)
  const createResponse = async () => {
    // Evaluation access is off unless the test environment switched it on
    // (see the module header); off, it reads nothing and the returned function
    // does nothing. It is asked before the completion is recorded because
    // only a first completion is eligible. Neither call can throw.
    const grantEvaluationAccess = await prepareEvaluationAccess(context)
    const data = await completeOnboarding(repository, context.auth.userId, input)
    await grantEvaluationAccess()
    return mobileSuccess(data, context.requestId)
  }
  return dependencies.executeIdempotent(context, input, createResponse, {
    refreshReplay: createResponse,
  })
}
