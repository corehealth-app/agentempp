import { mediaUploadInputSchema } from '@/lib/mobile-api/contracts'
import { MobileApiError, mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMediaAsset } from '@/lib/mobile-api/media-service'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { createSupabaseMediaDependencies } from '@/lib/mobile-api/supabase-media'

export const runtime = 'nodejs'

export const POST = createMobileRoute(async (context) => {
  const input = mediaUploadInputSchema.parse(await readJsonBody(context.request))
  if (input.kind === 'body_checkin_photo') {
    throw new MobileApiError(422, 'media_kind_not_supported', 'Body photos are uploaded on sign-up')
  }
  const createResponse = async () =>
    mobileSuccess(
      await createMediaAsset(
        createSupabaseMediaDependencies(context.supabase),
        context.auth.userId,
        input,
        context.request.headers.get('idempotency-key') ?? '',
        undefined,
        undefined,
        { rejectBodyPhotos: true },
      ),
      context.requestId,
      201,
    )
  return executeSupabaseIdempotent(context, input, createResponse, {
    refreshReplay: createResponse,
    responseBodyForStorage: () => ({ temporary_capability_redacted: true }),
  })
})
