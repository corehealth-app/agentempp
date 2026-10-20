import {
  prepareStrengthWeekFreeze,
  type StrengthWeekFreezeResult,
  type StrengthWeekRepository,
  type StrengthWeekUUID,
} from './strength-training-week-service'

/**
 * Acquires the repository's stored winner, never an earlier read or proposal.
 * Conflicts and failures remain visible; the caller decides when to refresh.
 * No HTTP caller or activation is installed by this dormant composition.
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
