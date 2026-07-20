import { notificationPreferencesPatchSchema } from '@/lib/mobile-api/contracts'
import { mobileSuccess, readJsonBody } from '@/lib/mobile-api/http'
import { executeSupabaseIdempotent } from '@/lib/mobile-api/idempotency'
import { createMobileRoute } from '@/lib/mobile-api/route'
import {
  getNotificationPreferences,
  patchNotificationPreferences,
} from '@/lib/mobile-api/routine-service'
import { createSupabaseRoutineDependencies } from '@/lib/mobile-api/supabase-routine'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(
    await getNotificationPreferences(
      createSupabaseRoutineDependencies(context.supabase),
      context.auth.userId,
    ),
    context.requestId,
  ),
)

export const PATCH = createMobileRoute(async (context) => {
  const input = notificationPreferencesPatchSchema.parse(await readJsonBody(context.request))
  return executeSupabaseIdempotent(context, input, async () =>
    mobileSuccess(
      await patchNotificationPreferences(
        createSupabaseRoutineDependencies(context.supabase),
        context.auth.userId,
        input,
      ),
      context.requestId,
    ),
  )
})
