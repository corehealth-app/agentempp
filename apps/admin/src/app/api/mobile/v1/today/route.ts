import { createCurrentClinicalGetRoute } from '@/lib/mobile-api/current-clinical-http'
import { createCurrentClinicalRuntimeReadDependencies } from '@/lib/mobile-api/current-clinical-read-runtime'
import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { createTodayGetRoute } from '@/lib/mobile-api/today-handler'

export const runtime = 'nodejs'

const legacyGET = createTodayGetRoute()

export const GET = selectCurrentClinicalRoute(
  () =>
    createCurrentClinicalGetRoute(
      'today',
      undefined,
      createCurrentClinicalRuntimeReadDependencies(),
    ),
  legacyGET,
)
