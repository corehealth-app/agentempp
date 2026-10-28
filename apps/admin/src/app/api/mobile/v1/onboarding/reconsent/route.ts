import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { createLegacyOnboardingDocumentsRoutes } from '@/lib/mobile-api/legacy-onboarding-documents-http'

export const runtime = 'nodejs'
export const POST = selectCurrentClinicalRoute(
  () => createLegacyOnboardingDocumentsRoutes({ enabled: true }).POST,
)
