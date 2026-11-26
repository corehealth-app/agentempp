import { mobileDeviceInputSchema } from '@/lib/mobile-api/contracts'
import { loadMobileEntitlement } from '@/lib/mobile-api/entitlement-service'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { listMobileDevices, registerMobileDevice } from '@/lib/mobile-api/routine-service'
import { createSupabaseRoutineDependencies } from '@/lib/mobile-api/supabase-routine'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(
    await listMobileDevices(
      createSupabaseRoutineDependencies(context.supabase),
      context.auth.userId,
    ),
    context.requestId,
  ),
)

export const POST = createMobileRoute(async (context) => {
  const input = mobileDeviceInputSchema.parse(await readJsonBody(context.request))
  let topic: string | undefined
  if (input.flow_meal_gap) {
    const database = process.env.NEXT_PUBLIC_SUPABASE_URL
    const configured = process.env.MOBILE_FLOW_APNS_TOPIC
    if (
      process.env.MOBILE_FLOW_MEAL_GAP_PUSH_ENABLED !== 'true' ||
      database?.replace(/\/$/u, '') !== 'https://xitugspwfxkcluxvrdeg.supabase.co' ||
      !configured ||
      !/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/u.test(configured)
    ) {
      throw new MobileApiError(
        503,
        'flow_meal_gap_unavailable',
        'Flow meal reminders are unavailable',
      )
    }
    const entitlement = await loadMobileEntitlement(context.supabase, context.auth.userId)
    if (!entitlement.has_active_access) {
      throw new MobileApiError(402, 'subscription_required', 'An active subscription is required')
    }
    topic = configured
  }
  return executeSupabaseIdempotent(context, input, async () =>
    mobileSuccess(
      await registerMobileDevice(
        createSupabaseRoutineDependencies(context.supabase),
        context.auth.userId,
        input,
        topic,
      ),
      context.requestId,
      201,
    ),
  )
})
