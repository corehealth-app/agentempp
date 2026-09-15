import { createMobileRoute } from '@/lib/mobile-api/route'
import { handleOnboardingGet, handleOnboardingPost } from './handler'

export const runtime = 'nodejs'

export const GET = createMobileRoute(handleOnboardingGet)
export const POST = createMobileRoute(handleOnboardingPost)
