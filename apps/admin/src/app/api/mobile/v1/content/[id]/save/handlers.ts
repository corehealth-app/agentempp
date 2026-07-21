import { contentSaveInputSchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { type ContentServiceDependencies, setContentSaved } from '@/lib/mobile-api/content-service'
import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import {
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import { createSupabaseContentDependencies } from '@/lib/mobile-api/supabase-content'

export interface ContentSaveRouteContext {
  params: Promise<{ id: string }>
}

export interface ContentSaveRouteDependencies {
  createContentDependencies(supabase: ServiceClient): ContentServiceDependencies
  executeIdempotent: typeof executeSupabaseIdempotent
}

const defaultDependencies: ContentSaveRouteDependencies = {
  createContentDependencies: createSupabaseContentDependencies,
  executeIdempotent: executeSupabaseIdempotent,
}

export async function handleContentSave(
  context: MobileRouteContext,
  routeContext: ContentSaveRouteContext,
  dependencies: ContentSaveRouteDependencies = defaultDependencies,
): Promise<Response> {
  const { id: rawId } = await routeContext.params
  const publicationId = resourceIdSchema.parse(rawId)
  const input = contentSaveInputSchema.parse(await readJsonBody(context.request))

  return dependencies.executeIdempotent(
    context,
    { publication_id: publicationId, ...input },
    async (idempotencyKey) =>
      mobileSuccess(
        await setContentSaved(
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

export function createContentSaveRoute(
  mobileRuntime?: MobileRouteRuntime,
  dependencies: ContentSaveRouteDependencies = defaultDependencies,
) {
  return createMobileRouteWithContext<ContentSaveRouteContext>(
    (context, routeContext) => handleContentSave(context, routeContext, dependencies),
    mobileRuntime,
  )
}
