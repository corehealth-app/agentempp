import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { createCurrentSignupEligibilityRoute } from '@/lib/mobile-api/current-signup-eligibility-http'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { handleOnboardingEligibilityPost } from './handler'

export const runtime = 'nodejs'

const legacyPOST = createMobileRoute(handleOnboardingEligibilityPost)

export const POST = selectCurrentClinicalRoute(
  () => createCurrentSignupEligibilityRoute({ enabled: true }),
  legacyPOST,
)
