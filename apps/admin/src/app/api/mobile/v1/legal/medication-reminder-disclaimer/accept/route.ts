import { medicationDisclaimerAcceptanceInputSchema } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import {
  createMobileRoute,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import {
  acceptMedicationDisclaimer,
  MEDICATION_DISCLAIMER_KEY,
  type RoutineAdherenceServiceDependencies,
} from '@/lib/mobile-api/routine-adherence-service'
import { createSupabaseRoutineAdherenceDependencies } from '@/lib/mobile-api/supabase-routine-adherence'

export const runtime = 'nodejs'

interface MedicationDisclaimerAcceptRouteDependencies {
  createRoutineAdherenceDependencies(
    supabase: ServiceClient,
    requestId: string,
  ): RoutineAdherenceServiceDependencies
  executeIdempotent: typeof executeSupabaseIdempotent
}

const defaultDependencies: MedicationDisclaimerAcceptRouteDependencies = {
  createRoutineAdherenceDependencies: (supabase, requestId) =>
    createSupabaseRoutineAdherenceDependencies(supabase, { requestId }),
  executeIdempotent: executeSupabaseIdempotent,
}

async function handleMedicationDisclaimerAccept(
  context: MobileRouteContext,
  dependencies: MedicationDisclaimerAcceptRouteDependencies = defaultDependencies,
): Promise<Response> {
  const input = medicationDisclaimerAcceptanceInputSchema.parse(await readJsonBody(context.request))
  const hashInput = { document_key: MEDICATION_DISCLAIMER_KEY, ...input }
  return dependencies.executeIdempotent(context, hashInput, async (idempotencyKey) =>
    mobileSuccess(
      await acceptMedicationDisclaimer(
        dependencies.createRoutineAdherenceDependencies(context.supabase, context.requestId),
        context.auth,
        input,
        idempotencyKey,
      ),
      context.requestId,
    ),
  )
}

function createMedicationDisclaimerAcceptRoute(
  mobileRuntime?: MobileRouteRuntime,
  dependencies: MedicationDisclaimerAcceptRouteDependencies = defaultDependencies,
) {
  return createMobileRoute(
    (context) => handleMedicationDisclaimerAccept(context, dependencies),
    mobileRuntime,
  )
}

export const POST = createMedicationDisclaimerAcceptRoute()
