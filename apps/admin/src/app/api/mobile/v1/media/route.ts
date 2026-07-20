import { mediaUploadInputSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMediaAsset } from '@/lib/mobile-api/media-service'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { createSupabaseMediaDependencies } from '@/lib/mobile-api/supabase-media'

export const runtime = 'nodejs'

export const POST = createMobileRoute(async (context) => {
  const input = mediaUploadInputSchema.parse(await readJsonBody(context.request))
  const createResponse = async () =>
    mobileSuccess(
      await createMediaAsset(
        createSupabaseMediaDependencies(context.supabase),
        context.auth.userId,
        input,
        context.request.headers.get('idempotency-key') ?? '',
      ),
      context.requestId,
      201,
    )
  return executeSupabaseIdempotent(context, input, createResponse, {
    refreshReplay: createResponse,
    responseBodyForStorage: () => ({ temporary_capability_redacted: true }),
  })
})
