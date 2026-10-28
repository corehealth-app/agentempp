import { trendsQuerySchema } from '@/lib/mobile-api/contracts'
import { createCurrentClinicalReadGetRoute as createCurrentClinicalGetRoute } from '@/lib/mobile-api/current-clinical-read-http'
import { createCurrentClinicalRuntimeReadDependencies } from '@/lib/mobile-api/current-clinical-read-runtime'
import { selectCurrentClinicalRoute } from '@/lib/mobile-api/current-clinical-runtime-route'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { loadTrends } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

const legacyGET = createMobileRoute(async (context) => {
  const url = new URL(context.request.url)
  const query = trendsQuerySchema.parse(Object.fromEntries(url.searchParams.entries()))
  return mobileSuccess(
    await loadTrends(
      context.supabase,
      context.auth.userId,
      query,
      context.auth.patient.timezone ?? 'UTC',
    ),
    context.requestId,
  )
})

export const GET = selectCurrentClinicalRoute(
  () =>
    createCurrentClinicalGetRoute(
      'trends',
      undefined,
      createCurrentClinicalRuntimeReadDependencies(),
    ),
  legacyGET,
)
