import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { confirmRegistration } from '@/lib/mobile-api/registration-service'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

interface RegistrationRouteContext {
  params: Promise<{ id: string }>
}

export const POST = createMobileRouteWithContext<RegistrationRouteContext>(
  async (context, routeContext) => {
    const { id: rawId } = await routeContext.params
    const id = resourceIdSchema.parse(rawId)
    return executeSupabaseIdempotent(context, { registration_id: id }, async () =>
      mobileSuccess(
        await confirmRegistration(context.supabase, context.auth, id),
        context.requestId,
      ),
    )
  },
)
