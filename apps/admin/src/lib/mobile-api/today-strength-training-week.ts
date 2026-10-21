import type { ServiceClient } from '@mpp/db'
import { MobileApiError } from './http'
import {
  readStrengthTrainingWeek,
  type StrengthWeekSummaryResult,
} from './strength-training-week-composer'
import { createStrengthWeekRepository } from './strength-training-week-service'
import { strengthTrainingWeekEnabled } from './strength-training-week-switch'

/** Additive public DTO. Never includes the internal target, binding, proofs or
 * workout identities. Its calendar is independent of the daily state read. */
export type TodayStrengthTrainingWeek =
  | Exclude<StrengthWeekSummaryResult, { readonly status: 'disabled' | 'available' }>
  | {
      readonly status: 'available'
      readonly week_start: string
      readonly as_of_local_date: string
      readonly time_zone: string
      readonly observed_at: string
      readonly completed_strength_days: number
      readonly planned_days: number | null
      readonly target_source: 'accepted_plan' | 'informed_frequency' | 'absent'
      readonly target_availability: 'available' | 'zero' | 'absent'
      readonly percentage: number | null
    }

/** Only GET/today calls this, after auth, entitlement, day-close and daily read.
 * RPC failures propagate. No retry, clock override or daily calendar inference. */
export async function loadTodayStrengthTrainingWeek(
  supabase: ServiceClient,
  userId: string,
  currentProtocol: string | null | undefined,
): Promise<TodayStrengthTrainingWeek | undefined> {
  if (
    !strengthTrainingWeekEnabled() ||
    (currentProtocol !== 'recomposicao' &&
      currentProtocol !== 'ganho_massa' &&
      currentProtocol !== 'manutencao')
  )
    return undefined

  const result = await readStrengthTrainingWeek(
    createStrengthWeekRepository(supabase, { enabled: true }),
    userId,
  )
  if (result.status === 'unavailable') return { status: 'unavailable', reason: result.reason }
  if (result.status === 'conflict') return { status: 'conflict', reason: result.reason }

  if (
    result.status !== 'available' ||
    result.summary.completedStrengthDays === null ||
    (result.summary.targetAvailability !== 'available' &&
      result.summary.targetAvailability !== 'zero' &&
      result.summary.targetAvailability !== 'absent')
  )
    throw new MobileApiError(
      500,
      'strength_week_invalid_response',
      'Invalid strength week response',
    )

  return {
    status: 'available',
    week_start: result.calendar.weekStartDate,
    as_of_local_date: result.calendar.asOfLocalDate,
    time_zone: result.calendar.timeZone,
    observed_at: result.observed_at,
    completed_strength_days: result.summary.completedStrengthDays,
    planned_days: result.summary.plannedDays,
    target_source: result.target.source,
    target_availability: result.summary.targetAvailability,
    percentage: result.summary.percentage,
  }
}
