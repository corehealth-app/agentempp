import { createMobileRoute } from '@/lib/mobile-api/route'
import { handleOnboardingEligibilityPost } from './handler'

export const runtime = 'nodejs'

export const POST = createMobileRoute(handleOnboardingEligibilityPost)
