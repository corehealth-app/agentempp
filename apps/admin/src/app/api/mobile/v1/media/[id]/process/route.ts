import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { requestMediaProcessing } from '@/lib/mobile-api/media-service'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'
import { createSupabaseMediaDependencies } from '@/lib/mobile-api/supabase-media'

export const runtime = 'nodejs'

interface MediaProcessRouteContext {
  params: Promise<{ id: string }>
}

export const POST = createMobileRouteWithContext<MediaProcessRouteContext>(
  async (context, routeContext) => {
    const { id: rawId } = await routeContext.params
    const id = resourceIdSchema.parse(rawId)
    return executeSupabaseIdempotent(context, { media_asset_id: id }, async () =>
      mobileSuccess(
        await requestMediaProcessing(
          createSupabaseMediaDependencies(context.supabase),
          context.auth.userId,
          id,
          context.request.headers.get('idempotency-key') ?? '',
        ),
        context.requestId,
        202,
      ),
    )
  },
)
