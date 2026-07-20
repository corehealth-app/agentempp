import { mobileSuccess } from '@/lib/mobile-api/http'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(
    {
      available: false,
      selected: null,
      options: [],
      reason: 'persona_module_not_configured',
    },
    context.requestId,
  ),
)
