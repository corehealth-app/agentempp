/** In-memory Auth seam for legacy route golden tests. The exported route still
 * receives a real Request, so outer negotiation/target guards remain real. */
import type { MobileRouteContext } from '../route'

const contexts = new WeakMap<Request, MobileRouteContext>()
export function wrapContextRouteHandler(
  handler: (context: MobileRouteContext) => Promise<Response>,
) {
  return async (request: Request) => {
    const context = contexts.get(request)
    if (!context) throw new Error('Missing synthetic route context')
    return handler(context)
  }
}
export async function invokeContextRoute(
  route: (request: Request) => Promise<Response>,
  context: MobileRouteContext,
) {
  contexts.set(context.request, context)
  try {
    return await route(context.request)
  } finally {
    contexts.delete(context.request)
  }
}
