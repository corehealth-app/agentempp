import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { MobileApiError } from '@/lib/mobile-api/http'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

interface ContentRouteContext {
  params: Promise<{ id: string }>
}

export const GET = createMobileRoute<ContentRouteContext>(async (_context, routeContext) => {
  if (!routeContext) {
    throw new MobileApiError(500, 'route_context_missing', 'Route context unavailable')
  }
  const { id } = await routeContext.params
  resourceIdSchema.parse(id)
  throw new MobileApiError(404, 'content_not_found', 'Content item not found')
})
