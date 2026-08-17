import type { DayStatus } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'

interface DailyCloseFinalizerInput {
  userId: string
  snapshotId: string
  dayStatus: DayStatus
  xpTotal: number
  level: number
  currentStreak: number
  longestStreak: number
  blocksCompleted: number
  deficitBlock: number
  badgesEarned: string[]
  lastActiveDate: string
  closedAt: string
}

interface DailyCloseFinalizerResult {
  applied: boolean
  already_closed?: boolean
  snapshot_id: string
  day_status?: DayStatus
}

export async function finalizeDailyClose(
  supabase: ServiceClient,
  input: DailyCloseFinalizerInput,
): Promise<DailyCloseFinalizerResult> {
  const { data, error } = await (
    supabase as unknown as {
      rpc: (
        name: string,
        params: Record<string, unknown>,
      ) => Promise<{
        data: DailyCloseFinalizerResult | null
        error: { message?: string } | null
      }>
    }
  ).rpc('finalize_daily_close_atomic', {
    p_user_id: input.userId,
    p_snapshot_id: input.snapshotId,
    p_day_status: input.dayStatus,
    p_xp_total: input.xpTotal,
    p_level: input.level,
    p_current_streak: input.currentStreak,
    p_longest_streak: input.longestStreak,
    p_blocks_completed: input.blocksCompleted,
    p_deficit_block: input.deficitBlock,
    p_badges_earned: input.badgesEarned,
    p_last_active_date: input.lastActiveDate,
    p_closed_at: input.closedAt,
  })

  if (error) throw new Error(error.message ?? 'atomic daily close failed')
  if (!data) throw new Error('atomic daily close returned null')
  return data
}
