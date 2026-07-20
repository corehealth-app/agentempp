import { hydrationInputSchema } from '@/lib/mobile-api/contracts'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { recordHydration } from '@/lib/mobile-api/routine-service'
import { createSupabaseRoutineDependencies } from '@/lib/mobile-api/supabase-routine'

export const runtime = 'nodejs'

export const POST = createMobileRoute(async (context) => {
  const input = hydrationInputSchema.parse(await readJsonBody(context.request))
  const timezone = context.auth.patient.timezone
  if (!timezone) {
    throw new MobileApiError(
      409,
      'profile_timezone_required',
      'Patient timezone is required before recording hydration',
    )
  }
  return executeSupabaseIdempotent(context, input, async (idempotencyKey) =>
    mobileSuccess(
      await recordHydration(
        createSupabaseRoutineDependencies(context.supabase),
        context.auth.userId,
        timezone,
        input,
        idempotencyKey,
      ),
      context.requestId,
      201,
    ),
  )
})
