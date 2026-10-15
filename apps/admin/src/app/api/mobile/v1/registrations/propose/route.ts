import { handleRegistrationPropose } from '@/lib/mobile-api/registration-handlers'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const POST = createMobileRoute((context) => handleRegistrationPropose(context))
