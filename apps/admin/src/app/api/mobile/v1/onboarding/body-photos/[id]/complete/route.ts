import { createMobileRouteWithContext } from '@/lib/mobile-api/route'
import {
  handleSignupBodyPhotoCompletePost,
  type SignupBodyPhotoCompleteRouteContext,
} from '../../handler'

export const runtime = 'nodejs'

export const POST = createMobileRouteWithContext<SignupBodyPhotoCompleteRouteContext>(
  handleSignupBodyPhotoCompletePost,
)
