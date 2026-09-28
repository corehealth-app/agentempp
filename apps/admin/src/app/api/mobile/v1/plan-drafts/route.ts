import { planDraftListQuerySchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { listPlanDrafts } from '@/lib/mobile-api/plan-draft-service'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { createSupabasePlanDraftDependencies } from '@/lib/mobile-api/supabase-plan-drafts'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) => {
  const query = planDraftListQuerySchema.parse(
    Object.fromEntries(new URL(context.request.url).searchParams),
  )
  return mobileSuccess(
    await listPlanDrafts(
      createSupabasePlanDraftDependencies(context.supabase),
      context.auth.userId,
      query,
    ),
    context.requestId,
  )
})
