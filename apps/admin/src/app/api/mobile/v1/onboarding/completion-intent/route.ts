import { createMobileRoute } from '@/lib/mobile-api/route'
import { handleSignupCompletionIntentGet, handleSignupCompletionIntentPost } from './handler'

export const runtime = 'nodejs'
export const GET = createMobileRoute(handleSignupCompletionIntentGet)
export const POST = createMobileRoute(handleSignupCompletionIntentPost)
