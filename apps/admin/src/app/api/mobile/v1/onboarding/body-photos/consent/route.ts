import { createMobileRoute } from '@/lib/mobile-api/route'
import { handleSignupBodyPhotoConsentPost } from '../handler'

export const runtime = 'nodejs'

export const POST = createMobileRoute(handleSignupBodyPhotoConsentPost)
