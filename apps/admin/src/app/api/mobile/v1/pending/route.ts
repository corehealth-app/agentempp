import { mobileSuccess } from '@/lib/mobile-api/http'
import { loadPending } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { loadWorkoutAwarePendingRegistrations } from '@/lib/mobile-api/workout-registration-service'
import { workoutRegistrationEnabled } from '@/lib/mobile-api/workout-registration-switch'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) =>
  mobileSuccess(
    await (workoutRegistrationEnabled()
      ? loadWorkoutAwarePendingRegistrations(context.supabase, context.auth.userId)
      : loadPending(context.supabase, context.auth.userId)),
    context.requestId,
  ),
)
