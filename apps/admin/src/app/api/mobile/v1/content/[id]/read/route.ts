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

export const runtime = 'nodejs'

export interface ContentReadRouteContext {
  params: Promise<{ id: string }>
}

export interface ContentReadRouteDependencies {
  createContentDependencies(supabase: ServiceClient): ContentServiceDependencies
  executeIdempotent: typeof executeSupabaseIdempotent
}

const defaultDependencies: ContentReadRouteDependencies = {
  createContentDependencies: createSupabaseContentDependencies,
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
          dependencies.createContentDependencies(context.supabase),
          context.auth,
          publicationId,
          input,
          idempotencyKey,
        ),
        context.requestId,
      ),
  )
}

export const handleContentReadPost = handleContentRead

export function createContentReadRoute(
  mobileRuntime?: MobileRouteRuntime,
  dependencies: ContentReadRouteDependencies = defaultDependencies,
) {
  return createMobileRouteWithContext<ContentReadRouteContext>(
    (context, routeContext) => handleContentRead(context, routeContext, dependencies),
    mobileRuntime,
  )
}

export const POST = createContentReadRoute()
