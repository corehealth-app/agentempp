import { markRoutineTakenInputSchema, resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'
import { markRoutineTaken } from '@/lib/mobile-api/routine-service'
import { createSupabaseRoutineDependencies } from '@/lib/mobile-api/supabase-routine'

export const runtime = 'nodejs'

interface MedicationRouteContext {
  params: Promise<{ id: string }>
}

export const POST = createMobileRouteWithContext<MedicationRouteContext>(
  async (context, routeContext) => {
    const { id: rawId } = await routeContext.params
    const id = resourceIdSchema.parse(rawId)
    const input = markRoutineTakenInputSchema.parse(await readJsonBody(context.request))
    return executeSupabaseIdempotent(
      context,
      { routine_item_id: id, ...input },
      async (idempotencyKey) =>
        mobileSuccess(
          await markRoutineTaken(
            createSupabaseRoutineDependencies(context.supabase),
            context.auth.userId,
            id,
            'medication',
            input,
            idempotencyKey,
          ),
          context.requestId,
        ),
    )
  },
)
