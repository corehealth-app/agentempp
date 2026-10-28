import { createCurrentClinicalQuestionnaireRuntimeRoutes } from '@/lib/mobile-api/current-clinical-full-runtime'
import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'

export const runtime = 'nodejs'

export const POST = selectCurrentClinicalRoute(
  () => createCurrentClinicalQuestionnaireRuntimeRoutes().DESCRIBE,
)
