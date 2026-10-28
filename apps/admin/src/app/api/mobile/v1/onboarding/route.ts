import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { createCurrentOnboardingRoutes } from '@/lib/mobile-api/current-onboarding-http'
import { createMobileRoute } from '@/lib/mobile-api/route'
import {
  createSupabaseCurrentOnboardingDependencies,
  handleOnboardingGet,
  handleOnboardingPost,
} from './handler'

export const runtime = 'nodejs'

const legacyGET = createMobileRoute(handleOnboardingGet)
const legacyPOST = createMobileRoute(handleOnboardingPost)

export const GET = selectCurrentClinicalRoute(
  () =>
    createCurrentOnboardingRoutes({
      enabled: true,
      createDependencies: createSupabaseCurrentOnboardingDependencies,
    }).GET,
  legacyGET,
)

export const POST = selectCurrentClinicalRoute(
  () =>
    createCurrentOnboardingRoutes({
      enabled: true,
      createDependencies: createSupabaseCurrentOnboardingDependencies,
    }).POST,
  legacyPOST,
)
