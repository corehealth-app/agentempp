import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { MobileApiError } from '@/lib/mobile-api/http'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

interface ContentRouteContext {
  params: Promise<{ id: string }>
}

export const GET = createMobileRouteWithContext<ContentRouteContext>(
  async (_context, routeContext) => {
    const { id } = await routeContext.params
    resourceIdSchema.parse(id)
    throw new MobileApiError(404, 'content_not_found', 'Content item not found')
  },
)
