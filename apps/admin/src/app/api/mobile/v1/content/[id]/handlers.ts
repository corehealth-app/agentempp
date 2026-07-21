import type { ServiceClient } from '@mpp/db'
import type { ContentServiceDependencies } from '@/lib/mobile-api/content-service'
import { getContent } from '@/lib/mobile-api/content-service'
import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess } from '@/lib/mobile-api/http'
import {
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import { createSupabaseContentDependencies } from '@/lib/mobile-api/supabase-content'

export interface ContentDetailRouteContext {
  params: Promise<{ id: string }>
}

export interface ContentDetailRouteDependencies {
  createContentDependencies(supabase: ServiceClient): ContentServiceDependencies
}

const defaultDependencies: ContentDetailRouteDependencies = {
  createContentDependencies: createSupabaseContentDependencies,
}

export async function handleContentDetail(
  context: MobileRouteContext,
  routeContext: ContentDetailRouteContext,
  dependencies: ContentDetailRouteDependencies = defaultDependencies,
): Promise<Response> {
  const { id: rawId } = await routeContext.params
  const publicationId = resourceIdSchema.parse(rawId)
  return mobileSuccess(
    await getContent(
      dependencies.createContentDependencies(context.supabase),
      context.auth,
      publicationId,
    ),
    context.requestId,
  )
}

export function createContentDetailRoute(
  mobileRuntime?: MobileRouteRuntime,
  dependencies: ContentDetailRouteDependencies = defaultDependencies,
) {
  return createMobileRouteWithContext<ContentDetailRouteContext>(
    (context, routeContext) => handleContentDetail(context, routeContext, dependencies),
    mobileRuntime,
  )
}
