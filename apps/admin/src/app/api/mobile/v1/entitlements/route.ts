import { mobileSuccess } from '@/lib/mobile-api/http'
import { loadEntitlements } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(await loadEntitlements(context.supabase, context.auth.userId), context.requestId),
)
