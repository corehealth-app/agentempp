import { registrationProposalInputSchema, resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { cancelRegistration, editRegistration } from '@/lib/mobile-api/registration-service'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

interface RegistrationRouteContext {
  params: Promise<{ id: string }>
}

async function registrationId(routeContext: RegistrationRouteContext): Promise<string> {
  const { id } = await routeContext.params
  return resourceIdSchema.parse(id)
}

export const PATCH = createMobileRouteWithContext<RegistrationRouteContext>(
  async (context, routeContext) => {
    const id = await registrationId(routeContext)
    const input = registrationProposalInputSchema.parse(await readJsonBody(context.request))
    return executeSupabaseIdempotent(context, { registration_id: id, input }, async () =>
      mobileSuccess(
        await editRegistration(
          context.supabase,
          context.auth,
          id,
          input,
          context.request.headers.get('idempotency-key') ?? '',
        ),
        context.requestId,
      ),
    )
  },
)

export const DELETE = createMobileRouteWithContext<RegistrationRouteContext>(
  async (context, routeContext) => {
    const id = await registrationId(routeContext)
    return executeSupabaseIdempotent(context, { registration_id: id }, async () =>
      mobileSuccess(
        await cancelRegistration(context.supabase, context.auth.userId, id),
        context.requestId,
      ),
    )
  },
)
