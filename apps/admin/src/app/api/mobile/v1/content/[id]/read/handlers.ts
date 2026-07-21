import { contentReadInputSchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import {
  type ContentServiceDependencies,
  recordContentRead,
} from '@/lib/mobile-api/content-service'
import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import {
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import { createSupabaseContentDependencies } from '@/lib/mobile-api/supabase-content'

export interface ContentReadRouteContext {
  params: Promise<{ id: string }>
}

export interface ContentReadRouteDependencies {
  createContentDependencies(supabase: ServiceClient, requestId: string): ContentServiceDependencies
  executeIdempotent: typeof executeSupabaseIdempotent
}

const defaultDependencies: ContentReadRouteDependencies = {
  createContentDependencies: (supabase, requestId) =>
    createSupabaseContentDependencies(supabase, { requestId }),
  executeIdempotent: executeSupabaseIdempotent,
}

export async function handleContentRead(
  context: MobileRouteContext,
  routeContext: ContentReadRouteContext,
  dependencies: ContentReadRouteDependencies = defaultDependencies,
): Promise<Response> {
  const { id: rawId } = await routeContext.params
  const publicationId = resourceIdSchema.parse(rawId)
  const input = contentReadInputSchema.parse(await readJsonBody(context.request))

  return dependencies.executeIdempotent(
    context,
    { publication_id: publicationId, ...input },
    async (idempotencyKey) =>
      mobileSuccess(
        await recordContentRead(
          dependencies.createContentDependencies(context.supabase, context.requestId),
          context.auth,
          publicationId,
          input,
          idempotencyKey,
        ),
        context.requestId,
      ),
  )
}

export function createContentReadRoute(
  mobileRuntime?: MobileRouteRuntime,
  dependencies: ContentReadRouteDependencies = defaultDependencies,
) {
  return createMobileRouteWithContext<ContentReadRouteContext>(
    (context, routeContext) => handleContentRead(context, routeContext, dependencies),
    mobileRuntime,
  )
}
