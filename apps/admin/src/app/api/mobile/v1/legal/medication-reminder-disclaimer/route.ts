import type { ServiceClient } from '@mpp/db'
import { mobileSuccess } from '@/lib/mobile-api/http'
import {
  createMobileRoute,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import {
  getMedicationDisclaimer,
  type RoutineAdherenceServiceDependencies,
} from '@/lib/mobile-api/routine-adherence-service'
import { createSupabaseRoutineAdherenceDependencies } from '@/lib/mobile-api/supabase-routine-adherence'

export const runtime = 'nodejs'

interface MedicationDisclaimerRouteDependencies {
  createRoutineAdherenceDependencies(
    supabase: ServiceClient,
    requestId: string,
  ): RoutineAdherenceServiceDependencies
}

const defaultDependencies: MedicationDisclaimerRouteDependencies = {
  createRoutineAdherenceDependencies: (supabase, requestId) =>
    createSupabaseRoutineAdherenceDependencies(supabase, { requestId }),
}

async function handleMedicationDisclaimerGet(
  context: MobileRouteContext,
  dependencies: MedicationDisclaimerRouteDependencies = defaultDependencies,
): Promise<Response> {
  return mobileSuccess(
    await getMedicationDisclaimer(
      dependencies.createRoutineAdherenceDependencies(context.supabase, context.requestId),
      context.auth,
    ),
    context.requestId,
  )
}

function createMedicationDisclaimerGetRoute(
  mobileRuntime?: MobileRouteRuntime,
  dependencies: MedicationDisclaimerRouteDependencies = defaultDependencies,
) {
  return createMobileRoute(
    (context) => handleMedicationDisclaimerGet(context, dependencies),
    mobileRuntime,
  )
}

export const GET = createMedicationDisclaimerGetRoute()
