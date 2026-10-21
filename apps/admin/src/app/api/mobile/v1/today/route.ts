import { closeOpenDaysOnRequest } from '@/lib/mobile-api/day-close-on-request'
import { mobileSuccess } from '@/lib/mobile-api/http'
import { loadToday } from '@/lib/mobile-api/read-model'
import { createMobileRoute } from '@/lib/mobile-api/route'
import { loadTodayStrengthTrainingWeek } from '@/lib/mobile-api/today-strength-training-week'

export const runtime = 'nodejs'

export const GET = createMobileRoute(async (context) => {
  // Off unless the test environment switched it on (see the module header).
  await closeOpenDaysOnRequest(context)
  const data = await loadToday(
    context.supabase,
    context.auth.userId,
    context.auth.patient.timezone ?? 'UTC',
  )
  const strengthWeek = await loadTodayStrengthTrainingWeek(
    context.supabase,
    context.auth.userId,
    data.current_protocol,
  )
  return mobileSuccess(
    strengthWeek === undefined ? data : { ...data, strength_training_week: strengthWeek },
    context.requestId,
  )
})
