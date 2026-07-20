import { mobileSuccess } from '@/lib/mobile-api/http'
import { loadToday } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) => {
  const data = await loadToday(
    context.supabase,
    context.auth.userId,
    context.auth.patient.timezone ?? 'UTC',
  )
  return mobileSuccess(data, context.requestId)
})
