import { mobileSuccess } from '@/lib/mobile-api/http'
import { loadPlan } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(await loadPlan(context.supabase, context.auth.userId), context.requestId),
)
