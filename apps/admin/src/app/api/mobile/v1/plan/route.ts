import { createCurrentClinicalReadGetRoute as createCurrentClinicalGetRoute } from '@/lib/mobile-api/current-clinical-read-http'
import { createCurrentClinicalRuntimeReadDependencies } from '@/lib/mobile-api/current-clinical-read-runtime'
import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { loadPlan } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

const legacyGET = createMobileRoute(async (context) =>
  mobileSuccess(await loadPlan(context.supabase, context.auth.userId), context.requestId),
)

export const GET = selectCurrentClinicalRoute(
  () =>
    createCurrentClinicalGetRoute(
      'plan',
      undefined,
      createCurrentClinicalRuntimeReadDependencies(),
    ),
  legacyGET,
)
