import { mobileDeviceInputSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
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
  return executeSupabaseIdempotent(context, input, async () =>
    mobileSuccess(
      await registerMobileDevice(
        createSupabaseRoutineDependencies(context.supabase),
        context.auth.userId,
        input,
      ),
      context.requestId,
      201,
    ),
  )
})
