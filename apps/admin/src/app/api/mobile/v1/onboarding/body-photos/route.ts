import { createMobileRoute } from '@/lib/mobile-api/route'
import {
  handleSignupBodyPhotosDelete,
  handleSignupBodyPhotosGet,
  handleSignupBodyPhotosPost,
} from './handler'

export const runtime = 'nodejs'

export const GET = createMobileRoute(handleSignupBodyPhotosGet)
export const POST = createMobileRoute(handleSignupBodyPhotosPost)
export const DELETE = createMobileRoute(handleSignupBodyPhotosDelete)
