import { personaInputSchema } from '@/lib/mobile-api/contracts'
import {
  MobileApiError,
  mobileErrorResponse,
  mobileSuccess,
  readJsonBody,
} from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
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

export const PATCH = createMobileRoute(async (context) => {
  const input = personaInputSchema.parse(await readJsonBody(context.request))
  return executeSupabaseIdempotent(context, input, async () =>
    mobileErrorResponse(
      new MobileApiError(
        501,
        'persona_module_not_configured',
        'Coach personas are not configured yet',
      ),
      context.requestId,
    ),
  )
})
