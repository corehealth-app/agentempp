import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'
import { deactivateMobileDevice } from '@/lib/mobile-api/routine-service'
import { createSupabaseRoutineDependencies } from '@/lib/mobile-api/supabase-routine'

export const runtime = 'nodejs'

interface DeviceRouteContext {
  params: Promise<{ id: string }>
}

export const DELETE = createMobileRouteWithContext<DeviceRouteContext>(
  async (context, routeContext) => {
    const { id: rawId } = await routeContext.params
    const id = resourceIdSchema.parse(rawId)
    return executeSupabaseIdempotent(context, { device_id: id }, async () =>
      mobileSuccess(
        await deactivateMobileDevice(
          createSupabaseRoutineDependencies(context.supabase),
          context.auth.userId,
          id,
        ),
        context.requestId,
      ),
    )
  },
)
