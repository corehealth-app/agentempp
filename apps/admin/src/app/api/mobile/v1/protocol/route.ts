import { createCurrentClinicalReadGetRoute as createCurrentClinicalGetRoute } from '@/lib/mobile-api/current-clinical-read-http'
import { createCurrentClinicalRuntimeReadDependencies } from '@/lib/mobile-api/current-clinical-read-runtime'
import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { handleProtocolGet } from './handler'

export const runtime = 'nodejs'

const legacyGET = createMobileRoute(handleProtocolGet)

export const GET = selectCurrentClinicalRoute(
  () =>
    createCurrentClinicalGetRoute(
      'protocol',
      undefined,
      createCurrentClinicalRuntimeReadDependencies(),
    ),
  legacyGET,
)
