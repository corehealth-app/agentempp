import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { MobileApiError, mobileErrorResponse, mobileSuccess } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { completeMediaUpload } from '@/lib/mobile-api/media-service'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'
import { createSupabaseMediaDependencies } from '@/lib/mobile-api/supabase-media'

export const runtime = 'nodejs'

interface MediaCompleteRouteContext {
  params: Promise<{ id: string }>
}

export const POST = createMobileRouteWithContext<MediaCompleteRouteContext>(
  async (context, routeContext) => {
    const { id: rawId } = await routeContext.params
    const id = resourceIdSchema.parse(rawId)
    return executeSupabaseIdempotent(context, { media_asset_id: id }, async () => {
      try {
        return mobileSuccess(
          await completeMediaUpload(
            createSupabaseMediaDependencies(context.supabase),
            context.auth.userId,
            id,
          ),
          context.requestId,
        )
      } catch (error) {
        if (
          error instanceof MobileApiError &&
          ['media_upload_mismatch', 'media_upload_missing'].includes(error.code)
        ) {
          return mobileErrorResponse(error, context.requestId)
        }
        throw error
      }
    })
  },
)
