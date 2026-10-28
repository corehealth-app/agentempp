import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { createSignupHealthAdmissionRoutes } from '@/lib/mobile-api/signup-health-admission-http'

export const runtime = 'nodejs'

export const POST = selectCurrentClinicalRoute(
  () => createSignupHealthAdmissionRoutes({ enabled: true }).POST,
)
