import { mobileSuccess } from '@/lib/mobile-api/http'
import { meDto } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(meDto(context.auth), context.requestId),
)
