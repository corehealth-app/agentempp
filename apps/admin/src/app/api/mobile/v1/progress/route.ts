import { closeOpenDaysOnRequest } from '@/lib/mobile-api/day-close-on-request'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { loadProgress } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) => {
  // Off unless the test environment switched it on (see the module header).
  await closeOpenDaysOnRequest(context)
  return mobileSuccess(await loadProgress(context.supabase, context.auth.userId), context.requestId)
})
