/**
 * Status a day receives when it is closed (docs/CALCULO-MPP.md §3, "Quando um
 * dia CREDITA o bloco").
 *
 * Moved here unchanged from the worker package (2026-10-04) so the production
 * closer and the shared close function of `@mpp/agent` read ONE rule: the
 * mobile API may not import the worker package, and a second copy of this
 * function would drift. `packages/inngest-functions/src/lib/day-status-policy.ts`
 * re-exports it.
 */
import type { DayStatus } from './bloco.js'

export interface ClosedDayStatusInput {
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
