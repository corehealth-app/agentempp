import { registrationProposalInputSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { proposeRegistration } from '@/lib/mobile-api/registration-service'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const POST = createMobileRoute(async (context) => {
  const input = registrationProposalInputSchema.parse(await readJsonBody(context.request))
  return executeSupabaseIdempotent(context, input, async () =>
    mobileSuccess(
      await proposeRegistration(
        context.supabase,
        context.auth,
        input,
        context.request.headers.get('idempotency-key') ?? '',
      ),
      context.requestId,
      201,
    ),
  )
})
