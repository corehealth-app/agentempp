import { loadMobileEntitlement } from '@/lib/mobile-api/entitlement-service'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { createMobileRoute } from '@/lib/mobile-api/route'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(
    await loadMobileEntitlement(context.supabase, context.auth.userId),
    context.requestId,
  ),
)
