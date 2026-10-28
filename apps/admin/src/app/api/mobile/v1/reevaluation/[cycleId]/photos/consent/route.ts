import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { createCurrentReevaluationPhotoConsentRuntimeRoutes } from '@/lib/mobile-api/current-reevaluation-photo-runtime'

export const runtime = 'nodejs'

export const GET = selectCurrentClinicalRoute(
  () => createCurrentReevaluationPhotoConsentRuntimeRoutes().GET,
)

export const POST = selectCurrentClinicalRoute(
  () => createCurrentReevaluationPhotoConsentRuntimeRoutes().ACCEPT,
)
