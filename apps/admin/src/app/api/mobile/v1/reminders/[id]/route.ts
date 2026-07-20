import { patchReminderInputSchema, resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'
import { patchReminderRule } from '@/lib/mobile-api/routine-service'
import { createSupabaseRoutineDependencies } from '@/lib/mobile-api/supabase-routine'

export const runtime = 'nodejs'

interface ReminderRouteContext {
  params: Promise<{ id: string }>
}

export const PATCH = createMobileRouteWithContext<ReminderRouteContext>(
  async (context, routeContext) => {
    const { id: rawId } = await routeContext.params
    const id = resourceIdSchema.parse(rawId)
    const input = patchReminderInputSchema.parse(await readJsonBody(context.request))
    return executeSupabaseIdempotent(context, { reminder_id: id, ...input }, async () =>
      mobileSuccess(
        await patchReminderRule(
          createSupabaseRoutineDependencies(context.supabase),
          context.auth.userId,
          id,
          input,
        ),
        context.requestId,
      ),
    )
  },
)
