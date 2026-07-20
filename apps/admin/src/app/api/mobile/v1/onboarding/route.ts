import { saveOnboarding } from '@/lib/mobile-api/commands'
import { onboardingInputSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const POST = createMobileRoute(async (context) => {
  const input = onboardingInputSchema.parse(await readJsonBody(context.request))
  return executeSupabaseIdempotent(context, input, async () =>
    mobileSuccess(
      await saveOnboarding(
        context.supabase,
        context.auth,
        input,
        context.request.headers.get('idempotency-key') ?? '',
      ),
      context.requestId,
    ),
  )
})
