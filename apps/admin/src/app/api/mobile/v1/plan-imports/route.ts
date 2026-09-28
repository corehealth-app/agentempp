import { planImportInputSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createPlanImport } from '@/lib/mobile-api/plan-draft-service'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { createSupabasePlanDraftDependencies } from '@/lib/mobile-api/supabase-plan-drafts'

export const runtime = 'nodejs'

export const POST = createMobileRoute(async (context) => {
  const input = planImportInputSchema.parse(await readJsonBody(context.request))
  return executeSupabaseIdempotent(context, input, async (idempotencyKey) =>
    mobileSuccess(
      await createPlanImport(
        createSupabasePlanDraftDependencies(context.supabase),
        context.auth.userId,
        input,
        idempotencyKey,
      ),
      context.requestId,
      202,
    ),
  )
})
