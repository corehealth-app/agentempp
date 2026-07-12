import type { ServiceClient } from '@mpp/db'
import { throwIfQueryFailed } from './db-query-error.js'

export type DeterministicDailySnapshot = {
  calories_consumed: number
  calories_target: number | null
  protein_g: number
  protein_target: number | null
  exercise_calories: number
}

export type DeterministicUserProgress = {
  deficit_block: number
  current_streak: number
  level: number
  xp_total: number
  blocks_completed: number
}

export async function loadDeterministicDailyState(
  supabase: ServiceClient,
  userId: string,
  localDate: string,
): Promise<{
  snapshot: DeterministicDailySnapshot | null
  progress: DeterministicUserProgress
}> {
  const [snapshotResult, progressResult] = await Promise.all([
    supabase
      .from('daily_snapshots')
      .select('calories_consumed, calories_target, protein_g, protein_target, exercise_calories')
      .eq('user_id', userId)
      .eq('date', localDate)
      .maybeSingle(),
    supabase
      .from('user_progress')
      .select('deficit_block, current_streak, level, xp_total, blocks_completed')
      .eq('user_id', userId)
      .maybeSingle(),
  ])

  throwIfQueryFailed(snapshotResult.error, 'deterministic daily snapshot lookup failed')
  throwIfQueryFailed(progressResult.error, 'deterministic user progress lookup failed')
  if (!progressResult.data) throw new Error('deterministic user progress missing')

  return {
    snapshot: (snapshotResult.data as DeterministicDailySnapshot | null) ?? null,
    progress: progressResult.data as DeterministicUserProgress,
  }
}

export async function loadReevaluationGate(
  supabase: ServiceClient,
  userId: string,
  now: Date = new Date(),
): Promise<{ due: boolean; currentProtocol: string | null }> {
  const since = new Date(now.getTime() - 48 * 60 * 60 * 1000).toISOString()
  const [dueResult, profileResult] = await Promise.all([
    supabase
      .from('product_events')
      .select('id')
      .eq('user_id', userId)
      .eq('event', 'reevaluation.due')
      .gte('occurred_at', since)
      .limit(1),
    supabase.from('user_profiles').select('current_protocol').eq('user_id', userId).maybeSingle(),
  ])

  throwIfQueryFailed(dueResult.error, 'reevaluation due lookup failed')
  throwIfQueryFailed(profileResult.error, 'reevaluation profile lookup failed')
  if (!profileResult.data) throw new Error('reevaluation profile missing')

  return {
    due: Array.isArray(dueResult.data) && dueResult.data.length > 0,
    currentProtocol:
      (profileResult.data as { current_protocol?: string | null }).current_protocol ?? null,
  }
}
