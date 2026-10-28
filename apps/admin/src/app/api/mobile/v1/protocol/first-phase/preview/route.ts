import { createCurrentClinicalFirstPhaseRuntimeRoutes } from '@/lib/mobile-api/current-clinical-first-phase-runtime'
import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'

export const runtime = 'nodejs'

export const POST = selectCurrentClinicalRoute(
  () => createCurrentClinicalFirstPhaseRuntimeRoutes().PREVIEW,
)
