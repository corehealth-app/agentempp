import { handleRegistrationConfirm } from '@/lib/mobile-api/registration-handlers'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

interface RegistrationRouteContext {
  params: Promise<{ id: string }>
}

export const POST = createMobileRouteWithContext<RegistrationRouteContext>(
  async (context, routeContext) => {
    const { id } = await routeContext.params
    return handleRegistrationConfirm(context, id)
  },
)
