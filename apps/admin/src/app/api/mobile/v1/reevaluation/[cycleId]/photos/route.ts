import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { createCurrentReevaluationPhotoRuntimeRoutes } from '@/lib/mobile-api/current-reevaluation-photo-runtime'

export const runtime = 'nodejs'

export const GET = selectCurrentClinicalRoute(
  (target) => createCurrentReevaluationPhotoRuntimeRoutes(target).GET,
)

export const POST = selectCurrentClinicalRoute(
  (target) => createCurrentReevaluationPhotoRuntimeRoutes(target).ALLOCATE,
)
