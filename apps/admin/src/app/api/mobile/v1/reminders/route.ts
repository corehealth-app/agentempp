import { createReminderInputSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { createReminderRule, listReminderRules } from '@/lib/mobile-api/routine-service'
import { createSupabaseRoutineDependencies } from '@/lib/mobile-api/supabase-routine'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(
    await listReminderRules(
      createSupabaseRoutineDependencies(context.supabase),
      context.auth.userId,
    ),
    context.requestId,
  ),
)

export const POST = createMobileRoute(async (context) => {
  const input = createReminderInputSchema.parse(await readJsonBody(context.request))
  return executeSupabaseIdempotent(context, input, async () =>
    mobileSuccess(
      await createReminderRule(
        createSupabaseRoutineDependencies(context.supabase),
        context.auth.userId,
        input,
      ),
      context.requestId,
      201,
    ),
  )
})
