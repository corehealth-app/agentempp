import { contentListQuerySchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import type { ContentServiceDependencies } from '@/lib/mobile-api/content-service'
import { listContent } from '@/lib/mobile-api/content-service'
import { mobileSuccess } from '@/lib/mobile-api/http'
import {
  createMobileRoute,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import { createSupabaseContentDependencies } from '@/lib/mobile-api/supabase-content'

export interface ContentListRouteDependencies {
  createContentDependencies(supabase: ServiceClient, requestId: string): ContentServiceDependencies
}

const defaultDependencies: ContentListRouteDependencies = {
  createContentDependencies: (supabase, requestId) =>
    createSupabaseContentDependencies(supabase, { requestId }),
}

function queryRecord(searchParams: URLSearchParams): Record<string, unknown> {
  const result: Record<string, unknown> = {}
  for (const [key, value] of searchParams) {
    const existing = result[key]
    result[key] =
      existing === undefined
        ? value
        : Array.isArray(existing)
          ? [...existing, value]
          : [existing, value]
  }
  return result
}

export async function handleContentList(
  context: MobileRouteContext,
  dependencies: ContentListRouteDependencies = defaultDependencies,
): Promise<Response> {
  const query = contentListQuerySchema.parse(queryRecord(new URL(context.request.url).searchParams))
  return mobileSuccess(
    await listContent(
      dependencies.createContentDependencies(context.supabase, context.requestId),
      context.auth,
      query,
    ),
    context.requestId,
  )
}

export function createContentListRoute(
  mobileRuntime?: MobileRouteRuntime,
  dependencies: ContentListRouteDependencies = defaultDependencies,
) {
  return createMobileRoute((context) => handleContentList(context, dependencies), mobileRuntime)
}
