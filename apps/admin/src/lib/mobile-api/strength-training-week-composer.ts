import {
  type StrengthTrainingWeekSummary,
  summarizeStrengthTrainingWeek,
} from '@mpp/core/strength-training-week'
import { MobileApiError } from './http'
import {
  prepareStrengthWeekFreeze,
  type StrengthWeekFreezeResult,
  type StrengthWeekProjectionRepository,
  type StrengthWeekProjectionResult,
  type StrengthWeekRepository,
  type StrengthWeekUUID,
} from './strength-training-week-service'

/**
 * Acquires the repository's stored winner, never an earlier read or proposal.
 * Conflicts and failures remain visible; the caller decides when to refresh.
 * The caller controls activation; this composition never enables itself.
 */
export async function acquireStrengthWeekTarget(
  repository: StrengthWeekRepository,
  userId: StrengthWeekUUID,
): Promise<StrengthWeekFreezeResult> {
  const read = await repository.readContext(userId)
  const prepared = prepareStrengthWeekFreeze(read)
  if (prepared.status !== 'prepared') return prepared
  return repository.compareAndFreeze(prepared.input)
}

export type StrengthWeekSummaryResult =
  | Exclude<StrengthWeekFreezeResult, { readonly status: 'frozen' | 'reused' }>
  | Exclude<StrengthWeekProjectionResult, { readonly status: 'available' }>
  | (Extract<StrengthWeekProjectionResult, { readonly status: 'available' }> & {
      readonly summary: StrengthTrainingWeekSummary
    })

/** Internal composition with no implicit activation or retries. */
export async function readStrengthTrainingWeek(
  repository: StrengthWeekProjectionRepository,
  userId: StrengthWeekUUID,
): Promise<StrengthWeekSummaryResult> {
  const acquired = await acquireStrengthWeekTarget(repository, userId)
  if (acquired.status !== 'frozen' && acquired.status !== 'reused') return acquired
  const projected = await repository.projectAcquiredTarget(userId, acquired.target)
  if (projected.status !== 'available') return projected
  const { target, calendar, projection } = projected
  const summary = summarizeStrengthTrainingWeek({
    scope: {
      ownerKey: target.user_id,
      weekStartDate: target.week_start,
      asOfLocalDate: calendar.asOfLocalDate,
    },
    persistedTarget: {
      ownerKey: target.user_id,
      weekStartDate: target.week_start,
      plannedDays: target.planned_days,
      source: target.source,
      sourceKey: target.source_key,
    },
    workouts: projection.workouts,
  })
  if (summary.status !== 'counted')
    throw new MobileApiError(
      500,
      'strength_week_invalid_response',
      'Invalid strength week response',
    )
  return { ...projected, summary }
}
