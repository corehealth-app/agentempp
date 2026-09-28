import { planDraftConfirmSchema, resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { confirmPlanDraft } from '@/lib/mobile-api/plan-draft-service'
import { createMobileRouteWithContext } from '@/lib/mobile-api/route'
import { createSupabasePlanDraftDependencies } from '@/lib/mobile-api/supabase-plan-drafts'

export const runtime = 'nodejs'

interface PlanDraftConfirmRouteContext {
  params: Promise<{ id: string }>
}

// The only way a draft becomes a plan: the patient's token, the version the
// patient reviewed and an idempotency key. No agent tool reaches this.
export const POST = createMobileRouteWithContext<PlanDraftConfirmRouteContext>(
  async (context, routeContext) => {
    const { id: rawId } = await routeContext.params
    const id = resourceIdSchema.parse(rawId)
    const input = planDraftConfirmSchema.parse(await readJsonBody(context.request))
    return executeSupabaseIdempotent(
      context,
      { plan_draft_id: id, ...input },
      async (idempotencyKey) =>
        mobileSuccess(
          await confirmPlanDraft(
            createSupabasePlanDraftDependencies(context.supabase),
            context.auth.userId,
            id,
            input,
            idempotencyKey,
          ),
          context.requestId,
        ),
    )
  },
)
