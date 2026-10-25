import { z } from 'zod'
import {
  clinicalCivilDateSchema,
  clinicalDateOrdinal,
  clinicalTimestampSchema,
} from './reevaluation-clinical-safety.js'

/** Canonical evidence supplied and bound by the server. localDate must be
 * derived there from measuredAt + the authoritative timezone, never a UI date. */
const measurementSchema = z
  .object({
    id: z.string().uuid(),
    localDate: clinicalCivilDateSchema,
    measuredAt: clinicalTimestampSchema,
    weightHundredths: z.number().int().min(3000).max(30000),
  })
  .strict()
export const reevaluationWeightHistorySchema = z
  .object({
    date: clinicalCivilDateSchema,
    asOf: clinicalTimestampSchema,
    measurements: z.array(measurementSchema),
  })
  .strict()
export type ReevaluationWeightHistoryInput = z.infer<typeof reevaluationWeightHistorySchema>
export interface ClinicalWeightWeek {
  from: string
  to: string
  days: number
  sumHundredths: string
}
type UnknownWeightTrend = {
  status: 'unknown'
  reason: 'insufficient_days' | 'conflicting_measurements'
  missingWeeks: number[]
}
export type FortnightWeightTrend =
  | UnknownWeightTrend
  | {
      status: 'known'
      direction: 'rising' | 'falling' | 'stable'
      aboveOnePercent: boolean
      aboveHalfPercent: boolean
      notRisen: boolean
    }
export type FourWeekWeightTrend = UnknownWeightTrend | { status: 'known'; stable: boolean }
function civil(ordinal: number): string {
  const value = new Date(ordinal * 86400000).toISOString().slice(0, 10)
  return clinicalCivilDateSchema.parse(value)
}
function comparisons(previous: ClinicalWeightWeek, current: ClinicalWeightWeek) {
  const a = BigInt(current.sumHundredths) * BigInt(previous.days)
  const b = BigInt(previous.sumHundredths) * BigInt(current.days)
  return { a, b }
}
function unknown(
  reason: UnknownWeightTrend['reason'],
  missingWeeks: number[] = [],
): UnknownWeightTrend {
  return { status: 'unknown', reason, missingWeeks }
}

/** n4/n16/n19. No profile substitute or rounded mean can manufacture evidence. */
export function evaluateReevaluationWeightHistory(input: unknown): {
  weeks: ClinicalWeightWeek[]
  fortnight: FortnightWeightTrend
  fourWeeks: FourWeekWeightTrend
} {
  const value = reevaluationWeightHistorySchema.parse(input)
  const end = clinicalDateOrdinal(value.date)
  const start = end - 27
  const weeks: ClinicalWeightWeek[] = Array.from({ length: 4 }, (_, index) => ({
    from: civil(start + index * 7),
    to: civil(start + index * 7 + 6),
    days: 0,
    sumHundredths: '0',
  }))
  function weekAt(index: number): ClinicalWeightWeek {
    const week = weeks[index]
    if (!week) throw new RangeError('Invalid clinical week index')
    return week
  }
  const from = civil(start)
  const relevant = value.measurements.filter(
    (entry) =>
      entry.localDate >= from && entry.localDate <= value.date && entry.measuredAt <= value.asOf,
  )
  const byId = new Map<string, z.infer<typeof measurementSchema>>()
  const byInstant = new Map<string, z.infer<typeof measurementSchema>>()
  const latest = new Map<string, z.infer<typeof measurementSchema>>()
  for (const entry of relevant) {
    const previousId = byId.get(entry.id.toLowerCase())
    const previousInstant = byInstant.get(entry.measuredAt)
    if (
      (previousId &&
        (previousId.measuredAt !== entry.measuredAt ||
          previousId.localDate !== entry.localDate ||
          previousId.weightHundredths !== entry.weightHundredths)) ||
      (previousInstant &&
        (previousInstant.localDate !== entry.localDate ||
          previousInstant.weightHundredths !== entry.weightHundredths))
    )
      return {
        weeks,
        fortnight: unknown('conflicting_measurements'),
        fourWeeks: unknown('conflicting_measurements'),
      }
    byId.set(entry.id.toLowerCase(), entry)
    byInstant.set(entry.measuredAt, entry)
    const current = latest.get(entry.localDate)
    if (!current || current.measuredAt < entry.measuredAt) latest.set(entry.localDate, entry)
  }
  for (const entry of latest.values()) {
    const index = Math.floor((clinicalDateOrdinal(entry.localDate) - start) / 7)
    const week = weekAt(index)
    week.days++
    week.sumHundredths = String(BigInt(week.sumHundredths) + BigInt(entry.weightHundredths))
  }
  const previous = weekAt(2)
  const current = weekAt(3)
  const missingFortnight = [previous, current].flatMap((week, index) =>
    week.days < 3 ? [index + 1] : [],
  )
  let fortnight: FortnightWeightTrend = unknown('insufficient_days', missingFortnight)
  if (!missingFortnight.length) {
    const { a, b } = comparisons(previous, current)
    fortnight = {
      status: 'known',
      direction: 200n * a >= 201n * b ? 'rising' : 200n * a <= 199n * b ? 'falling' : 'stable',
      aboveOnePercent: 100n * a > 101n * b,
      aboveHalfPercent: 200n * a > 201n * b,
      notRisen: a <= b,
    }
  }
  const missingFour = weeks.flatMap((week, index) => (week.days < 3 ? [index + 1] : []))
  let fourWeeks: FourWeekWeightTrend = unknown('insufficient_days', missingFour)
  if (!missingFour.length) {
    const pairs = [
      [1, 0],
      [2, 0],
      [3, 0],
      [3, 1],
    ] as const
    const stable = pairs.every(([i, j]) => {
      const { a, b } = comparisons(weekAt(j), weekAt(i))
      const difference = a >= b ? a - b : b - a
      return difference * 1000n <= 5n * b
    })
    fourWeeks = { status: 'known', stable }
  }
  return { weeks, fortnight, fourWeeks }
}
