import type { DayStatus } from '@mpp/core'

interface ClosedDayStatusInput {
  existingDayStatus: string | null
  reminderSent: boolean
  hasActivity: boolean
  gapCount: number
  skippedCount: number
  fallbackPattern: boolean
}

export function resolveClosedDayStatus(input: ClosedDayStatusInput): DayStatus {
  const unresolvedReminderGap =
    input.hasActivity && input.reminderSent && input.gapCount > 0 && !input.fallbackPattern
  if (unresolvedReminderGap) return 'incomplete_no_response'
  if (input.skippedCount > 0 || input.existingDayStatus === 'user_skipped') {
    return 'user_skipped'
  }
  return 'complete'
}
