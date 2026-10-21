import { closeOpenDaysOnRequest } from './day-close-on-request'
import { mobileSuccess } from './http'
import { loadToday } from './read-model'
import { createMobileRoute, type MobileRouteRuntime } from './route'
import { strengthTrainingWeekEnabled } from './strength-training-week-switch'
import { loadTodayStrengthTrainingWeek } from './today-strength-training-week'

/** Server composition only. The default route retains its auth/entitlement
 * wrapper and project switch; explicit runtimes use the same handler. */
export function createTodayGetRoute(
  runtime?: MobileRouteRuntime,
  enabled: () => boolean = strengthTrainingWeekEnabled,
) {
  return createMobileRoute(async (context) => {
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
      enabled,
    )
    return mobileSuccess(
      strengthWeek === undefined ? data : { ...data, strength_training_week: strengthWeek },
      context.requestId,
    )
  }, runtime)
}
