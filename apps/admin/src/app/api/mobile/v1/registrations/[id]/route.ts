import {
  handleRegistrationDelete,
  handleRegistrationGet,
  handleRegistrationPatch,
} from '@/lib/mobile-api/registration-handlers'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

interface RegistrationRouteContext {
  params: Promise<{ id: string }>
}

async function registrationId(routeContext: RegistrationRouteContext): Promise<string> {
  const { id } = await routeContext.params
  return id
}

export const PATCH = createMobileRouteWithContext<RegistrationRouteContext>(
  async (context, routeContext) => {
    return handleRegistrationPatch(context, await registrationId(routeContext))
  },
)

export const DELETE = createMobileRouteWithContext<RegistrationRouteContext>(
  async (context, routeContext) => {
    return handleRegistrationDelete(context, await registrationId(routeContext))
  },
)

export const GET = createMobileRouteWithContext<RegistrationRouteContext>(
  async (context, routeContext) =>
    handleRegistrationGet(context, await registrationId(routeContext)),
)
