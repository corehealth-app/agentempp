const ACTIVE_START_HOUR = 10
const ACTIVE_END_EXCLUSIVE_HOUR = 20

export function isProactiveReminderHour(localHour: number): boolean {
  return localHour >= ACTIVE_START_HOUR && localHour < ACTIVE_END_EXCLUSIVE_HOUR
}
