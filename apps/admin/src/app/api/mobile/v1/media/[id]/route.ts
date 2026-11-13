import { conversationMediaUploadTicketsEnabled } from '@mpp/core/conversation-photo-purpose'
import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { deleteMediaAsset, getMediaAsset } from '@/lib/mobile-api/media-service'
import { createOrdinaryMediaDisposal } from '@/lib/mobile-api/ordinary-media-disposal'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'
import { createSupabaseMediaDependencies } from '@/lib/mobile-api/supabase-media'

export const runtime = 'nodejs'

interface MediaRouteContext {
  params: Promise<{ id: string }>
}

async function mediaId(routeContext: MediaRouteContext): Promise<string> {
  const { id } = await routeContext.params
  return resourceIdSchema.parse(id)
}

export const GET = createMobileRouteWithContext<MediaRouteContext>(async (context, routeContext) =>
  mobileSuccess(
    await getMediaAsset(
      createSupabaseMediaDependencies(context.supabase, { reevaluationSchema: true }),
      context.auth.userId,
      await mediaId(routeContext),
    ),
    context.requestId,
  ),
)

export const DELETE = createMobileRouteWithContext<MediaRouteContext>(
  async (context, routeContext) => {
    const id = await mediaId(routeContext)
    return executeSupabaseIdempotent(context, { media_asset_id: id }, async () =>
      mobileSuccess(
        await deleteMediaAsset(
          createSupabaseMediaDependencies(context.supabase, {
            reevaluationSchema: true,
            ...(conversationMediaUploadTicketsEnabled()
              ? { ordinaryDisposals: createOrdinaryMediaDisposal(context.supabase) }
              : {}),
          }),
          context.auth.userId,
          id,
        ),
        context.requestId,
      ),
    )
  },
)
