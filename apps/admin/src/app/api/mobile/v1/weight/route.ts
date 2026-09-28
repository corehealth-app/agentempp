import { weightInputSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { createSupabaseWeightDependencies, recordWeight } from '@/lib/mobile-api/weight-service'

export const runtime = 'nodejs'

export const POST = createMobileRoute(async (context) => {
  const input = weightInputSchema.parse(await readJsonBody(context.request))
  return executeSupabaseIdempotent(context, input, async (idempotencyKey) =>
    mobileSuccess(
      await recordWeight(
        createSupabaseWeightDependencies(context.supabase),
        context.auth.userId,
        input,
        idempotencyKey,
      ),
      context.requestId,
      201,
    ),
  )
})
