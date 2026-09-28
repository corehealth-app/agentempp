import { planDraftPatchSchema, resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { discardPlanDraft, getPlanDraft, updatePlanDraft } from '@/lib/mobile-api/plan-draft-service'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'
import { createSupabasePlanDraftDependencies } from '@/lib/mobile-api/supabase-plan-drafts'

export const runtime = 'nodejs'

interface PlanDraftRouteContext {
  params: Promise<{ id: string }>
}

async function draftId(routeContext: PlanDraftRouteContext): Promise<string> {
  const { id } = await routeContext.params
  return resourceIdSchema.parse(id)
}

export const GET = createMobileRouteWithContext<PlanDraftRouteContext>(
  async (context, routeContext) =>
    mobileSuccess(
      await getPlanDraft(
        createSupabasePlanDraftDependencies(context.supabase),
        context.auth.userId,
        await draftId(routeContext),
      ),
      context.requestId,
    ),
)

export const PATCH = createMobileRouteWithContext<PlanDraftRouteContext>(
  async (context, routeContext) => {
    const id = await draftId(routeContext)
    const input = planDraftPatchSchema.parse(await readJsonBody(context.request, 256 * 1024))
    return executeSupabaseIdempotent(context, { plan_draft_id: id, ...input }, async () =>
      mobileSuccess(
        await updatePlanDraft(
          createSupabasePlanDraftDependencies(context.supabase),
          context.auth.userId,
          id,
          input,
        ),
        context.requestId,
      ),
    )
  },
)

export const DELETE = createMobileRouteWithContext<PlanDraftRouteContext>(
  async (context, routeContext) => {
    const id = await draftId(routeContext)
    return executeSupabaseIdempotent(context, { plan_draft_id: id }, async () =>
      mobileSuccess(
        await discardPlanDraft(
          createSupabasePlanDraftDependencies(context.supabase),
          context.auth.userId,
          id,
        ),
        context.requestId,
      ),
    )
  },
)
