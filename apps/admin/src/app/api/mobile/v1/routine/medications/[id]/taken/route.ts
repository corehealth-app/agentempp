import type { ServiceClient } from '@mpp/db'
import { markRoutineTakenInputSchema, resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import {
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import {
  type RoutineAdherenceServiceDependencies,
  recordLegacyRoutineTaken,
} from '@/lib/mobile-api/routine-adherence-service'
import { createSupabaseRoutineAdherenceDependencies } from '@/lib/mobile-api/supabase-routine-adherence'

export const runtime = 'nodejs'
const ROUTINE_ITEM_TYPE = 'medication' as const

interface LegacyRoutineTakenRouteContext {
  params: Promise<{ id: string }>
}

interface LegacyRoutineTakenRouteDependencies {
  createRoutineAdherenceDependencies(
    supabase: ServiceClient,
    requestId: string,
  ): RoutineAdherenceServiceDependencies
  executeIdempotent: typeof executeSupabaseIdempotent
  now(): Date
}

const defaultDependencies: LegacyRoutineTakenRouteDependencies = {
  createRoutineAdherenceDependencies: (supabase, requestId) =>
    createSupabaseRoutineAdherenceDependencies(supabase, { requestId }),
  executeIdempotent: executeSupabaseIdempotent,
  now: () => new Date(),
}

async function handleLegacyRoutineTaken(
  context: MobileRouteContext,
  routeContext: LegacyRoutineTakenRouteContext,
  dependencies: LegacyRoutineTakenRouteDependencies = defaultDependencies,
): Promise<Response> {
  const { id: rawId } = await routeContext.params
  const routineItemId = resourceIdSchema.parse(rawId)
  const input = markRoutineTakenInputSchema.parse(await readJsonBody(context.request))
  return dependencies.executeIdempotent(
    context,
    { routine_item_id: routineItemId, ...input },
    async (idempotencyKey) =>
      mobileSuccess(
        await recordLegacyRoutineTaken(
          dependencies.createRoutineAdherenceDependencies(context.supabase, context.requestId),
          context.auth,
          routineItemId,
          ROUTINE_ITEM_TYPE,
          input,
          idempotencyKey,
          dependencies.now(),
        ),
        context.requestId,
      ),
  )
}

function createLegacyRoutineTakenRoute(
  mobileRuntime?: MobileRouteRuntime,
  dependencies: LegacyRoutineTakenRouteDependencies = defaultDependencies,
) {
  return createMobileRouteWithContext<LegacyRoutineTakenRouteContext>(
    (context, routeContext) => handleLegacyRoutineTaken(context, routeContext, dependencies),
    mobileRuntime,
  )
}

export const POST = createLegacyRoutineTakenRoute()
