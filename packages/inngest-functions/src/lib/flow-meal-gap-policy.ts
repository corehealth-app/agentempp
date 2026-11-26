import type { MealType } from '@mpp/core'
import { isProactiveReminderHour } from '../functions/proactive-reminder-policy.js'

export type FlowMealGapMode = 'daytime' | 'before_close'

export interface FlowMealGapFacts {
  now: number
  localHour: number
  optedIn: boolean
  daytimeEnabled: boolean
  dayClosed: boolean
  patternReliable: boolean
  expected: ReadonlySet<MealType>
  registered: ReadonlySet<MealType>
  skipped: ReadonlySet<MealType>
  personalEndHours: Partial<Record<MealType, number>>
  dayProteinGrams: number | null
  dayProteinTargetGrams: number | null
  lastMealLoggedAt: number | null
  lastIntakeAt: number | null
  intakeProcessing: boolean
  dailyLimit: number
  priorNotices: readonly { mode: FlowMealGapMode; meal: MealType; at: number }[]
}

// Ceia's usual window spans midnight. The previous civil day must not be
// chased on the next morning. A personally earlier ceia can still be due.
const defaultFirstReminderHour: Readonly<Record<MealType, number>> = {
  cafe: 11,
  almoco: 15,
  lanche: 18,
  jantar: 21,
  ceia: 24,
}
const hourMs = 3_600_000

export function selectFlowMealGap(facts: FlowMealGapFacts): {
  mode: FlowMealGapMode
  meal: MealType
} | null {
  if (
    !facts.optedIn ||
    facts.dayClosed ||
    !facts.patternReliable ||
    facts.intakeProcessing ||
    facts.priorNotices.length >= facts.dailyLimit
  )
    return null

  const beforeClose = facts.localHour >= 21 && facts.localHour < 24
  const mode = beforeClose ? 'before_close' : 'daytime'
  const sentInMode = facts.priorNotices.filter((notice) => notice.mode === mode)
  if (beforeClose) {
    if (sentInMode.length > 0) return null
  } else if (
    !facts.daytimeEnabled ||
    !isProactiveReminderHour(facts.localHour) ||
    facts.lastMealLoggedAt === null ||
    facts.now - facts.lastMealLoggedAt < 4 * hourMs ||
    (facts.lastIntakeAt !== null && facts.now - facts.lastIntakeAt < hourMs) ||
    facts.dayProteinGrams === null ||
    facts.dayProteinTargetGrams === null ||
    facts.dayProteinTargetGrams <= 0 ||
    facts.dayProteinGrams >= 0.6 * facts.dayProteinTargetGrams ||
    sentInMode.length >= 2 ||
    sentInMode.some((notice) => facts.now - notice.at < 4 * hourMs)
  )
    return null

  const missing = [...facts.expected]
    .filter((meal) => !facts.registered.has(meal) && !facts.skipped.has(meal))
    .filter((meal) => !sentInMode.some((notice) => notice.meal === meal))
    .map((meal) => {
      const personalEndHour = facts.personalEndHours[meal]
      const dueHour =
        personalEndHour === undefined || (meal === 'ceia' && personalEndHour < 5)
          ? defaultFirstReminderHour[meal]
          : personalEndHour + 1
      return { meal, dueHour }
    })
    .filter(({ dueHour }) => facts.localHour >= dueHour)
    .sort((a, b) => b.dueHour - a.dueHour || a.meal.localeCompare(b.meal))
  const mostRecent = missing[0]
  return mostRecent ? { mode, meal: mostRecent.meal } : null
}
