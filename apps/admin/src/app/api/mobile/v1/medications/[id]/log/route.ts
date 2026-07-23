import { routineActionInputSchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { resourceIdSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import {
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import {
  type RoutineAdherenceServiceDependencies,
  recordRoutineAction,
} from '@/lib/mobile-api/routine-adherence-service'
import { createSupabaseRoutineAdherenceDependencies } from '@/lib/mobile-api/supabase-routine-adherence'

export const runtime = 'nodejs'
const ROUTINE_ITEM_TYPE = 'medication' as const

interface RoutineActionLogRouteContext {
  params: Promise<{ id: string }>
}

interface RoutineActionLogRouteDependencies {
  createRoutineAdherenceDependencies(
    supabase: ServiceClient,
    requestId: string,
  ): RoutineAdherenceServiceDependencies
  executeIdempotent: typeof executeSupabaseIdempotent
  now(): Date
}

const defaultDependencies: RoutineActionLogRouteDependencies = {
  createRoutineAdherenceDependencies: (supabase, requestId) =>
    createSupabaseRoutineAdherenceDependencies(supabase, { requestId }),
  executeIdempotent: executeSupabaseIdempotent,
  now: () => new Date(),
}

async function handleRoutineActionLog(
  context: MobileRouteContext,
  routeContext: RoutineActionLogRouteContext,
  dependencies: RoutineActionLogRouteDependencies = defaultDependencies,
): Promise<Response> {
  const { id: rawId } = await routeContext.params
  const routineItemId = resourceIdSchema.parse(rawId)
  const input = routineActionInputSchema.parse(await readJsonBody(context.request))
  const hashInput = { item_type: ROUTINE_ITEM_TYPE, routine_item_id: routineItemId, ...input }
  return dependencies.executeIdempotent(context, hashInput, async (idempotencyKey) =>
    mobileSuccess(
      await recordRoutineAction(
        dependencies.createRoutineAdherenceDependencies(context.supabase, context.requestId),
        context.auth,
        ROUTINE_ITEM_TYPE,
        routineItemId,
        input,
        idempotencyKey,
        dependencies.now(),
      ),
      context.requestId,
    ),
  )
}

function createRoutineActionLogRoute(
  mobileRuntime?: MobileRouteRuntime,
  dependencies: RoutineActionLogRouteDependencies = defaultDependencies,
) {
  return createMobileRouteWithContext<RoutineActionLogRouteContext>(
    (context, routeContext) => handleRoutineActionLog(context, routeContext, dependencies),
    mobileRuntime,
  )
}

export const POST = createRoutineActionLogRoute()
