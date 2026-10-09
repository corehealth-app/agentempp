import type { DailyState } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { DailyStateLoadError, loadOfficialDailyState } from './daily-state-service.js'
import { flowMetricLocale } from './flow-public-metrics.js'

export interface FlowDayStatusProgress {
  currentStreak: number
  level: number
  xpTotal: number
}

export interface FlowDayStatusContext {
  today: DailyState
  accountName: string | null
  locale: string | null
  progress: FlowDayStatusProgress | null
}

export type LoadFlowDayStatusContext = (
  userId: string,
  text: string,
  timestamp: Date,
) => Promise<FlowDayStatusContext>

export interface FlowDayStatusReadOptions {
  timezone: string
  readToday: (
    supabase: ServiceClient,
    userId: string,
    timezone: string,
    now: Date,
  ) => Promise<DailyState>
}

/** Default Flow entry uses the same official reader as Today. */
export async function loadFlowDayStatusContext(
  supabase: ServiceClient,
  userId: string,
  text: string,
  timestamp: Date,
  options?: FlowDayStatusReadOptions,
): Promise<FlowDayStatusContext> {
  const { data: account, error: accountError } = await supabase
    .from('users')
    .select('id, name, locale, timezone')
    .eq('id', userId)
    .maybeSingle()
  if (accountError || !account || account.id !== userId) {
    throw new DailyStateLoadError('Flow status account lookup')
  }
  const [today, progressResult] = await Promise.all([
    (options?.readToday ?? loadOfficialDailyState)(
      supabase,
      userId,
      options?.timezone ?? account.timezone ?? 'UTC',
      timestamp,
    ),
    supabase
      .from('user_progress')
      .select('current_streak, level, xp_total')
      .eq('user_id', userId)
      .maybeSingle(),
  ])
  if (progressResult.error) throw new DailyStateLoadError('Flow status progress lookup')
  const row = progressResult.data
  let progress: FlowDayStatusProgress | null = null
  if (row) {
    const valid = (value: unknown, minimum: number) =>
      typeof value === 'number' &&
      Number.isFinite(value) &&
      Number.isInteger(value) &&
      value >= minimum
    if (!valid(row.current_streak, 0) || !valid(row.level, 1) || !valid(row.xp_total, 0)) {
      throw new DailyStateLoadError('Flow status progress data')
    }
    progress = { currentStreak: row.current_streak, level: row.level, xpTotal: row.xp_total }
  }
  return {
    today,
    accountName: account.name,
    locale: flowMetricLocale(text, account.locale),
    progress,
  }
}
