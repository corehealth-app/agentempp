import { updateMe } from '@/lib/mobile-api/commands'
import { patchMeInputSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { meDto } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(meDto(context.auth), context.requestId),
)

export const PATCH = createMobileRoute(async (context) => {
  const input = patchMeInputSchema.parse(await readJsonBody(context.request))
  return executeSupabaseIdempotent(context, input, async () =>
    mobileSuccess(await updateMe(context.supabase, context.auth, input), context.requestId),
  )
})
