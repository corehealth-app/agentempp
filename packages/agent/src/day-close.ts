/**
 * Day close for ONE explicit local date, and the sweep that closes the past
 * open days of one account (docs/CALCULO-MPP.md §3a).
 *
 * WHY THIS FILE EXISTS. The production closer (`daily-closer.ts`, in the
 * worker package) can only close "yesterday", between 00h and 04h local, from
 * inside the worker. On the test
 * environment the worker serves media processing only, by design, so no day is
 * ever closed there and the 7.700 block, streak, XP, level and medals of an
 * app account never move. The mobile API may not import the worker package,
 * so the closer's script is followed here, date by date.
 *
 * NO RULE IS RE-IMPLEMENTED. The numbers come from the functions and RPCs the
 * production closer calls: `calcDailyXP`, `creditDayToBloco`,
 * `computeProgress`, `resolveClosedDayStatus` (@mpp/core), `getGapForDate`,
 * `loadCalcConfig`, `loadDailyTargets` (this package) and the RPC
 * `finalize_daily_close_atomic`. What is duplicated is the script of reads and
 * writes; a parity test in the worker package compares the two, parameter by
 * parameter (daily-closer.parity.test.ts).
 *
 * NOTHING IS SENT. The only I/O is the database client received as a
 * parameter. No provider, no event bus, no HTTP call: a static test reads this
 * file and fails on any of them (day-close.no-send.test.ts).
 *
 * WHERE IT DIFFERS FROM THE PRODUCTION CLOSER, on purpose:
 *  - the date is explicit, and the caller's clock decides nothing but "is this
 *    date already over" and "is it a late close";
 *  - a LATE close keeps the calories/protein target already stored on the day
 *    row and falls back to the profile only when the stored value is null —
 *    decisão técnica de 2026-10-04; confirmação do cliente pendente. A close
 *    is late wherever production never closes: a date before yesterday, or
 *    yesterday once the local hour is 5 or later (production's closer only
 *    runs while the local hour is 0 to 4). Inside that window yesterday is
 *    closed exactly as production closes it (targets of the profile at
 *    closing time). The protocol written on the row and the programmed
 *    deficit of the credit come from the profile at closing time in BOTH
 *    cases: the day row does not store the deficit level (declared pending);
 *  - a day is only closed when it is later than `last_active_date` and later
 *    than every closed day of the account: closing an older day afterwards
 *    would move `last_active_date` backwards and restart the streak;
 *  - the day row is written with a conditional update (still open, and not
 *    touched since it was read) instead of an unconditional upsert, because
 *    here the person may be registering while the close runs;
 *  - telemetry events are written after the atomic finalization applied, never
 *    before, so a close that lost the race writes nothing;
 *  - an inactive day writes nothing at all: the sweep handles inactivity once,
 *    with a conditional update, and never writes the "skipped" event;
 *  - the sweep does not visit an open day row that has no meal, workout or
 *    inbound message (a day with water only): it costs no query and stays
 *    open, as in production;
 *  - in the sweep, a date is not finalized when a record appeared, since the
 *    sweep's first read, on an earlier date that is still open: the sweep
 *    stops and the next call closes that earlier date first;
 *  - the reassessment schedule is not advanced unless asked for.
 */

import type {
  DailySnapshot,
  DayStatus,
  FlowBloco7700Policy,
  ProfileRow,
  UserProgress,
} from '@mpp/core'
import {
  calcDailyXP,
  computeDailyTargets,
  computeProgress,
  creditDayToBloco,
  netBalance,
  resolveClosedDayStatus,
  resolveFlowBloco7700Policy,
} from '@mpp/core'
import type { Json, ServiceClient } from '@mpp/db'
import { loadCalcConfig } from './calc-config-loader.js'
import { loadDailyTargets } from './calc-targets.js'
import { getGapForDate } from './meal-patterns.js'
import {
  addIsoDateDays,
  getLocalDateString,
  getLocalDayUtcBounds,
  getLocalHour,
} from './timezone-utils.js'

/** Yesterday becomes closable this long after local midnight. */
export const DAY_CLOSE_GRACE_MS = 30 * 60 * 1000

/**
 * The last local hour in which the production closer closes yesterday
 * (`daily-closer.ts` skips an account whose local hour is greater than 4).
 * From 05:00 local on, a close of yesterday is one production would not make.
 */
export const PRODUCTION_CLOSE_LAST_LOCAL_HOUR = 4

/** PostgREST caps a response at 1000 rows; a full page means "there may be more". */
const DISCOVERY_PAGE = 1000

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

export type DayCloseSkipReason =
  /** The day row is already closed. */
  | 'already_closed'
  /** Today, a future date, or yesterday inside the 30 minutes after midnight. */
  | 'not_closable_yet'
  /** Not later than `last_active_date`, or a later day of the account is closed. */
  | 'behind_frontier'
  /** No meal, no workout and no inbound message on that local date. */
  | 'inactive'
  /** The day row was created or changed between the read and the write. */
  | 'changed_concurrently'
  /** Another close finalized the same day first; nothing was applied twice. */
  | 'closed_concurrently'
  /**
   * Sweep only. A meal, workout or inbound message appeared, after the sweep's
   * first read, on an earlier date that is still open. This date was not
   * finalized: closing it would move the frontier past the earlier one.
   */
  | 'earlier_date_changed'

/** `user_progress` as the close reads and writes it. */
export interface DayCloseProgress {
  xpTotal: number
  level: number
  currentStreak: number
  longestStreak: number
  blocksCompleted: number
  deficitBlock: number
  badgesEarned: string[]
  /** YYYY-MM-DD */
  lastActiveDate: string | null
}

export interface DayCloseDetail {
  caloriesConsumed: number
  exerciseCalories: number
  /** Target on the day row before the close; null when there was no row or no target. */
  storedCaloriesTarget: number | null
  /** Target the close writes (or would write, on a dry run). */
  caloriesTarget: number | null
  storedProteinTarget: number | null
  proteinTarget: number | null
  dayStatus: DayStatus
  xpEarned: number
  blockCredit: number
  /** Badges this day added. */
  newBadges: string[]
  /** `user_progress` after this day. */
  progress: DayCloseProgress
}

export interface DayCloseResult {
  date: string
  /** Written; on a dry run, "would be written". */
  closed: boolean
  dryRun: boolean
  /**
   * Stored targets are kept: a date before yesterday, or yesterday closed at
   * local hour 5 or later (outside the production closer's window).
   */
  late: boolean
  reason?: DayCloseSkipReason
  detail?: DayCloseDetail
}

export interface CloseLocalDayInput {
  userId: string
  /** IANA zone of the account. Never defaulted here: an account without one is not closed. */
  timezone: string
  /** Local date to close, YYYY-MM-DD. */
  date: string
  now?: Date
  /** Read and compute, write nothing. */
  dryRun?: boolean
  /** Servidor Flow opt-in; ausente mantém o crédito/progresso legado. */
  block7700Policy?: FlowBloco7700Policy['version']
  /** Explicit mobile caller: finalize only against the same official state. */
  finalizationFence?: 'mobile-current-v1'
  /**
   * Dry run only: the progress left by the previous simulated day, so a
   * simulated week carries streak, XP and block from one day to the next.
   */
  simulatedProgress?: DayCloseProgress | null
  /**
   * Also call `advance_reevaluation_schedule`, as the production closer does.
   * Off by default: 14 days after the first day row that RPC writes
   * `reevaluation.due`, which switches the reassessment context on in the Flow
   * for 48 h, and that context was never exercised in the app.
   */
  advanceReevaluation?: boolean
}

export interface ClosePastOpenDaysInput {
  userId: string
  timezone: string
  now?: Date
  /** First local date that may be closed, YYYY-MM-DD (inclusive). */
  from: string
  /**
   * Budget of ONE call. Counts days actually closed and elapsed time, never
   * dates visited: three inactive days at the frontier must not use it up.
   */
  limits?: { maxDays?: number; maxMs?: number }
  /** Milliseconds clock for the time budget; replaced in tests. */
  clock?: () => number
  dryRun?: boolean
  block7700Policy?: FlowBloco7700Policy['version']
  finalizationFence?: 'mobile-current-v1'
  advanceReevaluation?: boolean
  /** Complete opt-in authority. Both writes (close/reset) must use the same
   * clinical implementation. Absence preserves the original writer path. */
  clinicalAuthority?: DayCloseClinicalAuthority
}

export interface DayCloseClinicalAuthority {
  closeDate(
    scope: Readonly<{ userId: string; timezone: string; from: string; date: string }>,
  ): Promise<DayCloseResult>
  /** latestClosableDate is discovery metadata, not an authoritative SQL clock. */
  resetInactive(
    scope: Readonly<{ userId: string; timezone: string; from: string; latestClosableDate: string }>,
  ): Promise<DayCloseStreakReset | null>
}

function bindClinicalAuthority(value: DayCloseClinicalAuthority | undefined) {
  if (value === undefined) return null
  if (value === null || typeof value !== 'object')
    throw new Error('Complete clinical close authority required')
  const closeDate = value.closeDate,
    resetInactive = value.resetInactive
  if (typeof closeDate !== 'function' || typeof resetInactive !== 'function')
    throw new Error('Complete clinical close authority required')
  return Object.freeze({
    closeDate: closeDate.bind(value),
    resetInactive: resetInactive.bind(value),
  })
}

export interface DayCloseStreakReset {
  /** False on a dry run, or when another writer changed the row first. */
  applied: boolean
  previousStreak: number
  lastActiveDate: string
  gapDays: number
}

export interface ClosePastOpenDaysResult {
  /** Yesterday, or the day before while the 30 minutes after midnight run. */
  latestClosableDate: string
  /** Days attempted, ascending. */
  days: DayCloseResult[]
  /** Open dates with data at or behind the frontier: left open, as in production. */
  staleOpenDates: string[]
  /**
   * Open day rows past the frontier with no meal, workout or inbound message
   * (water, weight, supplement or medication only). Not visited: no query is
   * spent on them, they stay open as in production, and they neither use the
   * budget nor hold back a later date.
   */
  inactiveOpenDates: string[]
  /**
   * Dates found and left for the next call, ascending: the ones the budget
   * did not reach, or the date the sweep stopped at (it is also in `days`, as
   * `changed_concurrently` or `earlier_date_changed`) and every later one.
   */
  pendingDates: string[]
  /** Every date found was resolved; only then is inactivity looked at. */
  complete: boolean
  streakReset: DayCloseStreakReset | null
}

interface ProgressRow {
  xp_total: number
  level: number
  current_streak: number
  longest_streak: number
  blocks_completed: number
  deficit_block: number
  badges_earned: string[]
  last_active_date: string | null
}

const PROGRESS_COLUMNS =
  'xp_total, level, current_streak, longest_streak, blocks_completed, deficit_block, badges_earned, last_active_date'

function mobileDayCloseRpc(supabase: ServiceClient) {
  return supabase.rpc.bind(supabase) as unknown as (
    name: 'finalize_mobile_daily_close_atomic' | 'reset_mobile_inactive_streak_atomic',
    params: Record<string, unknown>,
  ) => Promise<{ data: Json | null; error: { message: string } | null }>
}

function assertIsoDate(value: string, name: string): void {
  if (!ISO_DATE.test(value)) throw new Error(`${name} must be YYYY-MM-DD`)
}

function progressFromRow(row: ProgressRow | null): DayCloseProgress {
  return {
    xpTotal: row?.xp_total ?? 0,
    level: row?.level ?? 1,
    currentStreak: row?.current_streak ?? 0,
    longestStreak: row?.longest_streak ?? 0,
    blocksCompleted: row?.blocks_completed ?? 0,
    deficitBlock: row?.deficit_block ?? 0,
    badgesEarned: row?.badges_earned ?? [],
    lastActiveDate: row?.last_active_date ?? null,
  }
}

/**
 * The latest local date that may be closed at `now`: yesterday once 30 minutes
 * of the new local day have passed, the day before until then. Today is never
 * returned. The wait exists because the person may still be confirming the
 * last meal of the day right after midnight; production's first tick of the
 * night is at 00:30 local in whole-hour zones.
 */
export function latestClosableLocalDate(timezone: string, now: Date = new Date()): string {
  const today = getLocalDateString(timezone, now)
  const todayStartMs = new Date(getLocalDayUtcBounds(timezone, today).startIso).getTime()
  const graceOver = now.getTime() - todayStartMs >= DAY_CLOSE_GRACE_MS
  return addIsoDateDays(today, graceOver ? -1 : -2)
}

/** Whole days between two YYYY-MM-DD dates, computed as the production closer does. */
function gapInDays(laterDate: string, earlierDate: string): number {
  return Math.floor(
    (new Date(laterDate).getTime() - new Date(earlierDate).getTime()) / (1000 * 60 * 60 * 24),
  )
}

/** `finalize_daily_close_atomic` answers `{ applied: boolean, ... }`. */
function wasApplied(value: unknown): boolean {
  return (
    typeof value === 'object' &&
    value !== null &&
    'applied' in value &&
    (value as { applied: unknown }).applied === true
  )
}

function mobileFinalizationRefusal(
  value: unknown,
  snapshotId: string,
  dayStatus: DayStatus,
): DayCloseSkipReason | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('invalid mobile daily close result')
  }
  const result = value as Record<string, unknown>
  if (result.snapshot_id !== snapshotId) throw new Error('mobile daily close identity mismatch')
  if (result.applied === true && result.already_closed === false) {
    if (result.day_status !== dayStatus) throw new Error('invalid mobile daily close result')
    return null
  }
  if (result.applied !== false) throw new Error('invalid mobile daily close result')
  if (result.already_closed === true && result.reason === 'already_closed') {
    return 'closed_concurrently'
  }
  if (
    result.already_closed === false &&
    typeof result.reason === 'string' &&
    [
      'context_changed',
      'snapshot_changed',
      'profile_changed',
      'progress_changed',
      'not_closable',
    ].includes(result.reason)
  ) {
    // A refusal is still an OPEN date. The sweep must stop without advancing
    // its frontier or resetting inactivity as if a peer had closed this day.
    return 'changed_concurrently'
  }
  throw new Error('unknown mobile daily close refusal')
}

function skipped(
  input: CloseLocalDayInput,
  late: boolean,
  reason: DayCloseSkipReason,
): DayCloseResult {
  return { date: input.date, closed: false, dryRun: input.dryRun === true, late, reason }
}

/**
 * Closes one local date of one account, following the production closer's
 * script. Returns what was (or, on a dry run, would be) written. Throws on a
 * failed read or write, like the closer: the caller decides whether that
 * stops a request.
 */
export function closeLocalDay(
  supabase: ServiceClient,
  input: CloseLocalDayInput,
): Promise<DayCloseResult> {
  return closeDay(supabase, input, null)
}

/**
 * `closeLocalDay`, plus the sweep's question asked right before the
 * finalization: "did a record appear on an earlier open date?". Null outside
 * the sweep: one explicit date has no earlier date to protect.
 */
async function closeDay(
  supabase: ServiceClient,
  input: CloseLocalDayInput,
  earlierDateChanged: (() => Promise<boolean>) | null,
): Promise<DayCloseResult> {
  const { userId, timezone, date } = input
  const now = input.now ?? new Date()
  const dryRun = input.dryRun === true
  const fenced = input.finalizationFence === 'mobile-current-v1'
  assertIsoDate(date, 'date')
  if (!timezone) throw new Error('timezone is required')

  const yesterday = addIsoDateDays(getLocalDateString(timezone, now), -1)
  // Production only ever closes yesterday, and only while the local hour is
  // 0 to 4. Anywhere else the profile may have changed since the night
  // production would have closed that day (a weigh-in this morning moves the
  // target), so the close is late and keeps what the day row stored.
  const late =
    date < yesterday ||
    (date === yesterday && getLocalHour(timezone, now) > PRODUCTION_CLOSE_LAST_LOCAL_HOUR)
  if (date > latestClosableLocalDate(timezone, now)) {
    return skipped(input, late, 'not_closable_yet')
  }

  const [existingResult, frontierResult, laterClosedResult] = await Promise.all([
    supabase
      .from('daily_snapshots')
      .select(
        'id, day_closed, day_status, gap_reminder_sent_at, calories_target, protein_target, updated_at',
      )
      .eq('user_id', userId)
      .eq('date', date)
      .maybeSingle(),
    supabase.from('user_progress').select('last_active_date').eq('user_id', userId).maybeSingle(),
    supabase
      .from('daily_snapshots')
      .select('date')
      .eq('user_id', userId)
      .eq('day_closed', true)
      .gt('date', date)
      .limit(1),
  ])
  if (existingResult.error) {
    throw new Error(existingResult.error.message ?? 'snapshot close lookup failed')
  }
  if (frontierResult.error) {
    throw new Error(frontierResult.error.message ?? 'progress frontier lookup failed')
  }
  if (laterClosedResult.error) {
    throw new Error(laterClosedResult.error.message ?? 'closed days lookup failed')
  }
  const existing = existingResult.data

  if (existing?.day_closed) return skipped(input, late, 'already_closed')

  // Monotonic frontier. `computeProgress` continues the streak only when
  // `last_active_date` is the day before, and the finalization writes the
  // closed date as the new `last_active_date`: an older day closed afterwards
  // would restart the streak and move that date backwards.
  const frontierDate = dryRun
    ? (input.simulatedProgress?.lastActiveDate ?? frontierResult.data?.last_active_date ?? null)
    : (frontierResult.data?.last_active_date ?? null)
  if (
    (frontierDate !== null && date <= frontierDate) ||
    (laterClosedResult.data ?? []).length > 0
  ) {
    return skipped(input, late, 'behind_frontier')
  }

  const { startIso, endExclusiveIso } = getLocalDayUtcBounds(timezone, date)
  const [mealsResult, workoutsResult, messagesResult] = await Promise.all([
    supabase
      .from('meal_logs')
      .select('kcal, protein_g, carbs_g, fat_g')
      .eq('user_id', userId)
      .gte('consumed_at', startIso)
      .lt('consumed_at', endExclusiveIso),
    supabase
      .from('workout_logs')
      .select('estimated_kcal')
      .eq('user_id', userId)
      .gte('performed_at', startIso)
      .lt('performed_at', endExclusiveIso),
    // The closer asks one thing of the messages: was there an inbound one. The
    // text is not read here.
    supabase
      .from('messages')
      .select('direction')
      .eq('user_id', userId)
      .eq('direction', 'in')
      .gte('created_at', startIso)
      .lt('created_at', endExclusiveIso)
      .limit(1),
  ])
  const historyError = mealsResult.error ?? workoutsResult.error ?? messagesResult.error
  if (historyError) throw new Error(historyError.message ?? 'daily close history lookup failed')
  const meals = mealsResult.data ?? []
  const workouts = workoutsResult.data ?? []
  const hadIncomingMessage = (messagesResult.data ?? []).length > 0

  if (meals.length === 0 && workouts.length === 0 && !hadIncomingMessage) {
    // Production leaves such a day open too. Its streak reset and its
    // "skipped" event are not repeated per date: see `closePastOpenDays`.
    return skipped(input, late, 'inactive')
  }

  const kcalConsumed = meals.reduce((sum, meal) => sum + (Number(meal.kcal) || 0), 0)
  const proteinG = meals.reduce((sum, meal) => sum + (Number(meal.protein_g) || 0), 0)
  const carbsG = meals.reduce((sum, meal) => sum + (Number(meal.carbs_g) || 0), 0)
  const fatG = meals.reduce((sum, meal) => sum + (Number(meal.fat_g) || 0), 0)
  const exerciseKcal = workouts.reduce(
    (sum, workout) => sum + (Number(workout.estimated_kcal) || 0),
    0,
  )
  const trainingDone = workouts.length > 0

  // `Number(...)`: a numeric column may arrive as text, as the production
  // closer also assumes when it reads the protein target back.
  const storedCaloriesTarget =
    existing?.calories_target == null ? null : Number(existing.calories_target)
  const storedProteinTarget =
    existing?.protein_target == null ? null : Number(existing.protein_target)
  // A late close reads the profile's targets only for the field the day row
  // does not have.
  const needsProfileTargets = !late || storedCaloriesTarget === null || storedProteinTarget === null

  const [profileResult, calcConfig] = await Promise.all([
    (fenced
      ? supabase.from('user_profiles').select('*')
      : supabase.from('user_profiles').select('current_protocol, deficit_level')
    )
      .eq('user_id', userId)
      .maybeSingle(),
    loadCalcConfig(supabase),
  ])
  if (profileResult.error) {
    throw new Error(profileResult.error.message ?? 'daily close profile lookup failed')
  }
  const profile = profileResult.data
  const profileTargets = needsProfileTargets
    ? fenced
      ? computeDailyTargets(profile as ProfileRow | null, calcConfig)
      : await loadDailyTargets(supabase, userId, calcConfig)
    : { calories_target: null, protein_target: null }
  const targets = late
    ? {
        calories_target: storedCaloriesTarget ?? profileTargets.calories_target,
        protein_target: storedProteinTarget ?? profileTargets.protein_target,
      }
    : profileTargets

  const xpEarned = calcDailyXP(
    {
      trainingDone,
      proteinG,
      caloriesConsumed: kcalConsumed,
      caloriesTarget: targets.calories_target ?? undefined,
      proteinTarget: targets.protein_target ?? undefined,
      mealsLogged: meals.length,
      // Not tracked by the production closer either.
      photoLogged: false,
      weightLogged: false,
    },
    calcConfig,
  )

  const dayFields = {
    calories_consumed: Math.round(kcalConsumed),
    calories_target: targets.calories_target,
    protein_g: Math.round(proteinG * 10) / 10,
    protein_target: targets.protein_target,
    carbs_g: Math.round(carbsG * 10) / 10,
    fat_g: Math.round(fatG * 10) / 10,
    exercise_calories: Math.round(exerciseKcal),
    training_done: trainingDone,
    xp_earned: xpEarned,
    current_protocol: profile?.current_protocol ?? null,
  }

  let snapshotId: string | null = existing?.id ?? null
  let expectedSnapshot: unknown = null
  // The generated column, as the database computes it (docs §2b). Only the dry
  // run uses this value; a real close reads the column back from the row.
  let dailyBalance = netBalance(
    dayFields.calories_consumed,
    dayFields.calories_target ?? 0,
    dayFields.exercise_calories,
  )

  if (!dryRun) {
    // Re-check right before the write: a request of the same account may have
    // closed the day, or a registration may have changed it, since the read.
    const { data: fresh, error: freshError } = await supabase
      .from('daily_snapshots')
      .select('id, day_closed, updated_at')
      .eq('user_id', userId)
      .eq('date', date)
      .maybeSingle()
    if (freshError) throw new Error(freshError.message ?? 'snapshot close re-check failed')
    if (fresh?.day_closed) return skipped(input, late, 'closed_concurrently')
    if (
      (fresh?.id ?? null) !== (existing?.id ?? null) ||
      (fresh?.updated_at ?? null) !== (existing?.updated_at ?? null)
    ) {
      // The sums above may predate that change. The sweep stops at this date
      // and the next call reads it again.
      return skipped(input, late, 'changed_concurrently')
    }

    const write = fresh
      ? supabase
          .from('daily_snapshots')
          .update(dayFields)
          .eq('id', fresh.id)
          .eq('day_closed', false)
          .eq('updated_at', fresh.updated_at)
      : supabase
          .from('daily_snapshots')
          // A day with messages only has no row yet. If one appears meanwhile
          // (a registration), it is left alone instead of being overwritten.
          .upsert(
            { user_id: userId, date, ...dayFields },
            { onConflict: 'user_id,date', ignoreDuplicates: true },
          )
    const written = fenced
      ? await write.select('*').maybeSingle()
      : await write.select('id, daily_balance').maybeSingle()
    if (written.error) throw new Error(written.error.message ?? 'failed to write snapshot')
    if (!written.data) return skipped(input, late, 'changed_concurrently')
    snapshotId = written.data.id
    dailyBalance = written.data.daily_balance ?? 0
    expectedSnapshot = written.data
  }

  // O default legado credita −daily_balance fora da recomposição. Os callers
  // Flow elegíveis pedem explicitamente o gate C3 (docs §3/§3a).
  const blockPolicy =
    input.block7700Policy === 'flow-recomposition-v1'
      ? resolveFlowBloco7700Policy(profile?.current_protocol)
      : undefined
  const blockEnabled = blockPolicy?.enabled !== false
  const designDeficit =
    profile?.current_protocol === 'recomposicao' ? (profile.deficit_level ?? 500) : 0
  // A message is not evidence of consumption: no meal and no workout = no credit.
  const hasActivity = meals.length > 0 || workouts.length > 0

  const gapInfo = hasActivity ? await getGapForDate(supabase, userId, timezone, date) : null
  const dayStatus = resolveClosedDayStatus({
    existingDayStatus: existing?.day_status ?? null,
    reminderSent: Boolean(existing?.gap_reminder_sent_at),
    hasActivity,
    gapCount: gapInfo?.gap.size ?? 0,
    skippedCount: gapInfo?.skipped.size ?? 0,
    fallbackPattern: gapInfo?.pattern.fallbackUsed ?? false,
  })

  const blockCredit = creditDayToBloco(
    {
      hasActivity,
      dayStatus,
      caloriesConsumed: kcalConsumed,
      caloriesTarget: targets.calories_target,
      dailyBalance,
      designDeficit,
    },
    blockPolicy,
  )

  // Read as late as possible: the finalization writes absolute values
  // computed from this row, so the shorter the distance to it, the smaller
  // the window in which another close of the same account could be lost.
  let expectedProgress: unknown = null
  const readPrevious = async (): Promise<DayCloseProgress> => {
    if (dryRun && input.simulatedProgress) return input.simulatedProgress
    const { data: progressRow, error: progressError } = await (fenced
      ? supabase.from('user_progress').select(`${PROGRESS_COLUMNS}, updated_at`)
      : supabase.from('user_progress').select(PROGRESS_COLUMNS)
    )
      .eq('user_id', userId)
      .maybeSingle()
    if (progressError) throw new Error(progressError.message ?? 'previous progress lookup failed')
    expectedProgress = progressRow
    return progressFromRow(progressRow)
  }
  // The sweep's question travels with that read, so it is also asked one
  // round trip before the finalization and adds none to the other window.
  const [previous, earlierChanged] = await Promise.all([
    readPrevious(),
    !dryRun && earlierDateChanged ? earlierDateChanged() : false,
  ])
  if (previous.lastActiveDate !== null && date <= previous.lastActiveDate) {
    // Another close moved the frontier past this date meanwhile.
    return skipped(input, late, 'behind_frontier')
  }
  if (earlierChanged) {
    // Finalizing now would move the frontier past that earlier date, and it
    // would stay open for good. The day row written above stays open and is
    // read again by the next call.
    return skipped(input, late, 'earlier_date_changed')
  }

  const prev: UserProgress = {
    xpTotal: previous.xpTotal,
    level: previous.level,
    currentStreak: previous.currentStreak,
    longestStreak: previous.longestStreak,
    blocksCompleted: previous.blocksCompleted,
    deficitBlock: previous.deficitBlock,
    badgesEarned: previous.badgesEarned,
    lastActiveDate: previous.lastActiveDate ? new Date(previous.lastActiveDate) : null,
  }
  const daySnapshot: DailySnapshot = {
    date: new Date(date),
    caloriesConsumed: dayFields.calories_consumed,
    caloriesTarget: dayFields.calories_target,
    proteinG: Number(dayFields.protein_g),
    proteinTarget: dayFields.protein_target ? Number(dayFields.protein_target) : null,
    exerciseCalories: dayFields.exercise_calories,
    trainingDone: dayFields.training_done,
    xpEarned: dayFields.xp_earned,
    dailyBalance,
  }
  const next = computeProgress(daySnapshot, prev, calcConfig, blockCredit, blockPolicy)
  const newBadges = next.badgesEarned.filter((badge) => !prev.badgesEarned.includes(badge))

  const result: DayCloseResult = {
    date,
    closed: true,
    dryRun,
    late,
    detail: {
      caloriesConsumed: dayFields.calories_consumed,
      exerciseCalories: dayFields.exercise_calories,
      storedCaloriesTarget,
      caloriesTarget: dayFields.calories_target,
      storedProteinTarget,
      proteinTarget: dayFields.protein_target,
      dayStatus,
      xpEarned,
      blockCredit,
      newBadges,
      progress: {
        xpTotal: next.xpTotal,
        level: next.level,
        currentStreak: next.currentStreak,
        longestStreak: next.longestStreak,
        blocksCompleted: next.blocksCompleted,
        deficitBlock: next.deficitBlock,
        badgesEarned: next.badgesEarned,
        lastActiveDate: date,
      },
    },
  }
  if (dryRun) return result
  if (snapshotId === null) throw new Error('daily snapshot id missing after write')

  // Snapshot and user_progress are finalized in one transaction. A day that
  // was closed meanwhile comes back with applied=false and nothing is applied
  // twice. The twelve parameters are compared with the production closer's by
  // the parity test.
  const payload = {
    p_user_id: userId,
    p_snapshot_id: snapshotId,
    p_day_status: dayStatus,
    p_xp_total: next.xpTotal,
    p_level: next.level,
    p_current_streak: next.currentStreak,
    p_longest_streak: next.longestStreak,
    p_blocks_completed: next.blocksCompleted,
    p_deficit_block: next.deficitBlock,
    p_badges_earned: next.badgesEarned,
    p_last_active_date: date,
    p_closed_at: now.toISOString(),
  }
  const { data: finalized, error: finalizeError } = fenced
    ? await mobileDayCloseRpc(supabase)('finalize_mobile_daily_close_atomic', {
        ...payload,
        p_expected_timezone: timezone,
        p_expected_snapshot: expectedSnapshot,
        p_expected_profile: profile,
        p_expected_progress: expectedProgress,
      })
    : await supabase.rpc('finalize_daily_close_atomic', payload)
  if (finalizeError) throw new Error(finalizeError.message ?? 'atomic daily close failed')
  if (!finalized) throw new Error('atomic daily close returned null')
  if (fenced) {
    const refusal = mobileFinalizationRefusal(finalized, snapshotId, dayStatus)
    if (refusal) return skipped(input, late, refusal)
  } else if (!wasApplied(finalized)) return skipped(input, late, 'closed_concurrently')

  // Telemetry, with the names and properties the production closer writes.
  // Written only now, in one insert: a close that lost the race above has
  // written none. A failed insert does not undo a closed day (as in
  // production, where the result of these inserts is not checked either).
  const events: Array<{
    user_id: string
    event: string
    properties: Record<string, string | number | boolean | string[] | null>
  }> = []
  if (blockEnabled && dayStatus === 'incomplete_no_response') {
    events.push({
      user_id: userId,
      event: 'bloco7700.skipped_incomplete_day',
      properties: {
        date,
        gap: Array.from(gapInfo?.gap ?? []),
        reason: 'lembrete enviado, paciente não respondeu',
      },
    })
  }
  if (blockEnabled && !hasActivity) {
    events.push({
      user_id: userId,
      event: 'bloco7700.skipped_inactive_day',
      properties: { date, calories_target: targets.calories_target },
    })
  } else if (
    blockEnabled &&
    dayStatus !== 'user_skipped' &&
    targets.calories_target != null &&
    targets.calories_target > 0 &&
    kcalConsumed < 0.5 * targets.calories_target
  ) {
    // Log only. How much an under-registered day credits is decided by
    // `creditDayToBloco`, above.
    events.push({
      user_id: userId,
      event: 'bloco7700.skipped_subregistro',
      properties: {
        date,
        day_status: dayStatus,
        calories_consumed: Math.round(kcalConsumed),
        calories_target: targets.calories_target,
        pct: Math.round((kcalConsumed / targets.calories_target) * 100),
      },
    })
  }
  if (newBadges.length > 0) {
    events.push({
      user_id: userId,
      event: 'badge.earned',
      properties: { badges: newBadges, snapshot_date: date },
    })
  }
  if (blockEnabled && next.blocksCompleted > prev.blocksCompleted) {
    events.push({
      user_id: userId,
      event: 'bloco7700.block_completed',
      properties: {
        snapshot_date: date,
        previous_count: prev.blocksCompleted,
        new_count: next.blocksCompleted,
        kg_estimate: next.blocksCompleted,
      },
    })
  }
  events.push({
    user_id: userId,
    event: 'daily_closer.completed',
    properties: {
      snapshot_date: date,
      calories_consumed: Math.round(kcalConsumed),
      calories_target: targets.calories_target,
      exercise_calories: Math.round(exerciseKcal),
      training_done: trainingDone,
      day_status: dayStatus,
      xp_earned: xpEarned,
      blocks_completed: next.blocksCompleted,
      blocks_completed_delta: next.blocksCompleted - prev.blocksCompleted,
    },
  })
  await supabase.from('product_events').insert(events)

  if (input.advanceReevaluation === true) {
    // Isolated, as in production: a failure here does not undo the close.
    const { data: schedule, error: scheduleError } = await supabase.rpc(
      'advance_reevaluation_schedule',
      { p_user_id: userId, p_closing_date: date },
    )
    if (scheduleError || !schedule) {
      await supabase.from('product_events').insert({
        user_id: userId,
        event: 'reevaluation.check_failed',
        properties: {
          snapshot_date: date,
          error: String(scheduleError?.message ?? 'reevaluation schedule returned no result').slice(
            0,
            300,
          ),
        },
      })
    }
  }

  return result
}

/**
 * Closes, in ascending order, the past open days of one account that are later
 * than its frontier, then looks at inactivity ONCE.
 *
 * Strictly in order: a date is attempted only after every earlier candidate
 * was closed (by this call or by another one), found inactive or found behind
 * the frontier. A date that changed while it was being closed stops the
 * sweep, and so does a record that appeared meanwhile on an earlier open
 * date; that date and the later ones are reported as pending.
 *
 * The dates come from the data (local dates with a meal, a workout or an
 * inbound message), never from walking the calendar: an account with twelve
 * empty dates before one registered day reaches that day in the first call,
 * and a second call with nothing to do writes nothing. An open day row with
 * none of the three is not a candidate: it is reported in
 * `inactiveOpenDates` and costs nothing, however many there are.
 */
export async function closePastOpenDays(
  supabase: ServiceClient,
  input: ClosePastOpenDaysInput,
): Promise<ClosePastOpenDaysResult> {
  const { userId, timezone, from } = input
  const clinicalAuthority = bindClinicalAuthority(input.clinicalAuthority)
  if (clinicalAuthority && (input.dryRun === true || input.advanceReevaluation === true))
    throw new Error('Unsupported clinical close mode')
  const suppliedNow = input.now ?? new Date()
  const now = clinicalAuthority ? new Date(suppliedNow.getTime()) : suppliedNow
  const clinicalLimits = clinicalAuthority
    ? {
        maxDays: input.limits?.maxDays ?? Number.POSITIVE_INFINITY,
        maxMs: input.limits?.maxMs ?? Number.POSITIVE_INFINITY,
      }
    : null
  const dryRun = input.dryRun === true
  const clock = input.clock ?? Date.now
  const startedAt = clock()
  assertIsoDate(from, 'from')
  if (!timezone) throw new Error('timezone is required')

  const latestClosableDate = latestClosableLocalDate(timezone, now)
  const result: ClosePastOpenDaysResult = {
    latestClosableDate,
    days: [],
    staleOpenDates: [],
    inactiveOpenDates: [],
    pendingDates: [],
    complete: true,
    streakReset: null,
  }
  // Nothing may be closed yet: not a single query.
  if (latestClosableDate < from) return result

  const fenced = input.finalizationFence === 'mobile-current-v1'
  const { data: progressRow, error: progressError } = await (fenced
    ? supabase.from('user_progress').select('current_streak, last_active_date, updated_at')
    : supabase.from('user_progress').select('current_streak, last_active_date')
  )
    .eq('user_id', userId)
    .maybeSingle()
  if (progressError) throw new Error(progressError.message ?? 'progress lookup failed')
  const lastActiveDate = progressRow?.last_active_date ?? null
  // The common case of every request after the first of the day: yesterday is
  // closed and nothing later can be. One query.
  if (lastActiveDate !== null && lastActiveDate >= latestClosableDate) return result

  const afterLastActive = lastActiveDate === null ? from : addIsoDateDays(lastActiveDate, 1)
  const firstCandidateDate = afterLastActive > from ? afterLastActive : from
  const windowStartIso = getLocalDayUtcBounds(timezone, firstCandidateDate).startIso
  const windowEndIso = getLocalDayUtcBounds(timezone, latestClosableDate).endExclusiveIso

  const [rowsResult, mealsResult, workoutsResult, messagesResult] = await Promise.all([
    supabase
      .from('daily_snapshots')
      .select('date, day_closed')
      .eq('user_id', userId)
      .gte('date', from)
      .lte('date', latestClosableDate)
      .order('date', { ascending: true })
      .limit(DISCOVERY_PAGE),
    supabase
      .from('meal_logs')
      .select('consumed_at')
      .eq('user_id', userId)
      .gte('consumed_at', windowStartIso)
      .lt('consumed_at', windowEndIso)
      .order('consumed_at', { ascending: true })
      .limit(DISCOVERY_PAGE),
    supabase
      .from('workout_logs')
      .select('performed_at')
      .eq('user_id', userId)
      .gte('performed_at', windowStartIso)
      .lt('performed_at', windowEndIso)
      .order('performed_at', { ascending: true })
      .limit(DISCOVERY_PAGE),
    supabase
      .from('messages')
      .select('created_at')
      .eq('user_id', userId)
      .eq('direction', 'in')
      .gte('created_at', windowStartIso)
      .lt('created_at', windowEndIso)
      .order('created_at', { ascending: true })
      .limit(DISCOVERY_PAGE),
  ])
  const discoveryError =
    rowsResult.error ?? mealsResult.error ?? workoutsResult.error ?? messagesResult.error
  if (discoveryError) throw new Error(discoveryError.message ?? 'open days lookup failed')
  const rows = rowsResult.data ?? []
  const mealTimes = (mealsResult.data ?? []).map((row) => row.consumed_at)
  const workoutTimes = (workoutsResult.data ?? []).map((row) => row.performed_at)
  const messageTimes = (messagesResult.data ?? []).map((row) => row.created_at)
  // A full page means later dates may be missing. They are found by the next
  // call, once the frontier has moved; until then the sweep is not complete.
  const truncated = [rows, mealTimes, workoutTimes, messageTimes].some(
    (list) => list.length >= DISCOVERY_PAGE,
  )

  let frontier = lastActiveDate
  const openRowDates: string[] = []
  for (const row of rows) {
    if (row.day_closed) {
      if (frontier === null || row.date > frontier) frontier = row.date
    } else {
      openRowDates.push(row.date)
    }
  }

  const found = new Set<string>(openRowDates)
  for (const time of [...mealTimes, ...workoutTimes, ...messageTimes]) {
    if (time) found.add(getLocalDateString(timezone, new Date(time)))
  }
  const closedDates = new Set(rows.filter((row) => row.day_closed).map((row) => row.date))
  const dates = [...found]
    .filter((date) => date >= from && date <= latestClosableDate && !closedDates.has(date))
    .sort()
  const frontierAtStart = frontier
  result.staleOpenDates = dates.filter(
    (date) => frontierAtStart !== null && date <= frontierAtStart,
  )
  // Every meal, workout and inbound message the reads above returned, as
  // instants. Two uses: telling which open rows have none of them, and
  // telling a record that appeared later from one already seen.
  const seenActivityMs = new Set<number>()
  for (const time of [...mealTimes, ...workoutTimes, ...messageTimes]) {
    if (time) seenActivityMs.add(Date.parse(time))
  }
  // The same test `closeLocalDay` applies to one date (its local-day bounds),
  // answered from the rows already read.
  const hasActivity = (date: string): boolean => {
    const bounds = getLocalDayUtcBounds(timezone, date)
    const startMs = Date.parse(bounds.startIso)
    const endMs = Date.parse(bounds.endExclusiveIso)
    for (const ms of seenActivityMs) if (ms >= startMs && ms < endMs) return true
    return false
  }
  const activityDates = new Set<string>()
  for (const time of [...mealTimes, ...workoutTimes, ...messageTimes]) {
    if (time) activityDates.add(getLocalDateString(timezone, new Date(time)))
  }
  const pastFrontier = dates.filter((date) => frontierAtStart === null || date > frontierAtStart)
  // An open row with no meal, workout or inbound message (water only) is not
  // visited: `closeLocalDay` would answer `inactive` after six queries, on
  // every request, and thirty of them in a row used up the time budget before
  // the day with a meal that follows them (review of 2026-10-05). On a full
  // page the rows read may not be all of them, so every open row is visited,
  // as before.
  const candidates = pastFrontier.filter(
    (date) => truncated || activityDates.has(date) || hasActivity(date),
  )
  result.inactiveOpenDates = pastFrontier.filter((date) => !candidates.includes(date))

  const maxDays = clinicalLimits?.maxDays ?? input.limits?.maxDays ?? Number.POSITIVE_INFINITY
  const maxMs = clinicalLimits?.maxMs ?? input.limits?.maxMs ?? Number.POSITIVE_INFINITY
  let closedCount = 0
  let unresolved = truncated
  let simulated: DayCloseProgress | null = null
  // The latest date known closed: no date up to it can still be open and
  // waiting. Moves as this call closes (or finds closed) one date after another.
  let closedUpTo = frontierAtStart

  // Asked right before each finalization (review of 2026-10-05): the dates
  // were fixed by the reads above, so a FIRST record that lands meanwhile on
  // an earlier date that had none (no row, or a row with water only) is not
  // among them. Finalizing the later date would leave that one open for good.
  // "Appeared" = an instant the reads above did not return, between the first
  // date that may still be open and the start of the date being closed. When
  // that date is the day after the frontier there is nothing in between and
  // no query is made.
  const earlierDateChangedBefore = (date: string) => async (): Promise<boolean> => {
    const afterClosed = closedUpTo === null ? firstCandidateDate : addIsoDateDays(closedUpTo, 1)
    const firstOpenDate = afterClosed > firstCandidateDate ? afterClosed : firstCandidateDate
    if (firstOpenDate >= date) return false
    const sinceIso = getLocalDayUtcBounds(timezone, firstOpenDate).startIso
    const untilIso = getLocalDayUtcBounds(timezone, date).startIso
    const [meals, workouts, messages] = await Promise.all([
      supabase
        .from('meal_logs')
        .select('consumed_at')
        .eq('user_id', userId)
        .gte('consumed_at', sinceIso)
        .lt('consumed_at', untilIso)
        .limit(DISCOVERY_PAGE),
      supabase
        .from('workout_logs')
        .select('performed_at')
        .eq('user_id', userId)
        .gte('performed_at', sinceIso)
        .lt('performed_at', untilIso)
        .limit(DISCOVERY_PAGE),
      supabase
        .from('messages')
        .select('created_at')
        .eq('user_id', userId)
        .eq('direction', 'in')
        .gte('created_at', sinceIso)
        .lt('created_at', untilIso)
        .limit(DISCOVERY_PAGE),
    ])
    const error = meals.error ?? workouts.error ?? messages.error
    if (error) throw new Error(error.message ?? 'earlier dates re-check failed')
    const times = [
      ...(meals.data ?? []).map((row) => row.consumed_at),
      ...(workouts.data ?? []).map((row) => row.performed_at),
      ...(messages.data ?? []).map((row) => row.created_at),
    ]
    return times.some((time) => Boolean(time) && !seenActivityMs.has(Date.parse(time as string)))
  }

  for (const [index, date] of candidates.entries()) {
    if (closedCount >= maxDays || clock() - startedAt >= maxMs) {
      result.pendingDates = candidates.slice(index)
      break
    }
    const day: DayCloseResult = clinicalAuthority
      ? structuredClone(
          await clinicalAuthority.closeDate(Object.freeze({ userId, timezone, from, date })),
        )
      : await closeDay(
          supabase,
          {
            userId,
            timezone,
            date,
            now,
            dryRun,
            block7700Policy: input.block7700Policy,
            finalizationFence: input.finalizationFence,
            simulatedProgress: simulated,
            advanceReevaluation: input.advanceReevaluation,
          },
          // On a full page "not returned" does not mean "appeared later".
          truncated ? null : earlierDateChangedBefore(date),
        )
    if (
      clinicalAuthority &&
      (!day ||
        typeof day !== 'object' ||
        day.date !== date ||
        day.dryRun !== false ||
        typeof day.closed !== 'boolean' ||
        typeof day.late !== 'boolean' ||
        (day.closed && day.detail?.progress?.lastActiveDate !== date) ||
        (!day.closed &&
          ![
            'already_closed',
            'closed_concurrently',
            'not_closable_yet',
            'behind_frontier',
            'earlier_date_changed',
            'changed_concurrently',
            'inactive',
          ].includes(day.reason ?? '')))
    )
      throw new Error('Invalid clinical close result')
    result.days.push(day)
    if (day.closed) {
      closedCount += 1
      if (dryRun && day.detail) simulated = day.detail.progress
      else closedUpTo = date
    } else if (day.reason === 'already_closed' || day.reason === 'closed_concurrently') {
      // Closed by another request: resolved, and nothing up to it is open.
      closedUpTo = date
    } else if (
      day.reason === 'changed_concurrently' ||
      day.reason === 'earlier_date_changed' ||
      (clinicalAuthority && (day.reason === 'not_closable_yet' || day.reason === 'behind_frontier'))
    ) {
      // Still open, with data, and NOT closed by this call. The sweep stops
      // here: closing a later date now would move the frontier past the date
      // that changed (this one, or an earlier one) and it would never close
      // again (its XP, block credit and streak day lost). The next call reads
      // the dates again and starts from the earliest.
      unresolved = true
      result.pendingDates = candidates.slice(index)
      break
    }
  }
  result.complete = !unresolved && result.pendingDates.length === 0
  // Inactivity is judged against the frontier the closes above left. While a
  // date with data is still waiting, zeroing the streak here would make that
  // date restart at 1 instead of continuing it.
  if (!result.complete) return result

  // SQL rechecks pending activity, frontier, health, config and its fresh civil
  // clock even when discovery was empty. Never enter the old reset/event path.
  if (clinicalAuthority) {
    const reset = structuredClone(
      await clinicalAuthority.resetInactive(
        Object.freeze({ userId, timezone, from, latestClosableDate }),
      ),
    )
    if (reset !== null) {
      if (
        !reset ||
        reset.applied !== true ||
        !Number.isInteger(reset.previousStreak) ||
        reset.previousStreak <= 0 ||
        !Number.isInteger(reset.gapDays) ||
        reset.gapDays < 2
      )
        throw new Error('Invalid clinical inactivity result')
      assertIsoDate(reset.lastActiveDate, 'clinical reset date')
    }
    result.streakReset = reset
    return result
  }

  let current: { currentStreak: number; lastActiveDate: string | null }
  let expectedResetProgress: unknown = progressRow
  if (simulated) {
    current = simulated
  } else if (closedCount > 0) {
    const { data: afterRow, error: afterError } = await (fenced
      ? supabase.from('user_progress').select('current_streak, last_active_date, updated_at')
      : supabase.from('user_progress').select('current_streak, last_active_date')
    )
      .eq('user_id', userId)
      .maybeSingle()
    if (afterError) throw new Error(afterError.message ?? 'inactive progress lookup failed')
    expectedResetProgress = afterRow
    current = {
      currentStreak: afterRow?.current_streak ?? 0,
      lastActiveDate: afterRow?.last_active_date ?? null,
    }
  } else {
    current = { currentStreak: progressRow?.current_streak ?? 0, lastActiveDate }
  }
  if (current.currentStreak <= 0 || current.lastActiveDate === null) return result

  // Same rule as the production closer's inactive branch: one day without
  // activity is tolerated, the second one zeroes the streak.
  const gapDays = gapInDays(latestClosableDate, current.lastActiveDate)
  if (gapDays < 2) return result

  const streakReset: DayCloseStreakReset = {
    applied: false,
    previousStreak: current.currentStreak,
    lastActiveDate: current.lastActiveDate,
    gapDays,
  }
  result.streakReset = streakReset
  if (dryRun) return result

  // Conditional on the values read: a close that finished in between has
  // written a new streak and a new date, and this update then changes nothing.
  if (fenced) {
    const { data: reset, error } = await mobileDayCloseRpc(supabase)(
      'reset_mobile_inactive_streak_atomic',
      {
        p_user_id: userId,
        p_expected_timezone: timezone,
        p_expected_progress: expectedResetProgress,
        p_expected_latest_date: latestClosableDate,
      },
    )
    if (error) throw new Error(error.message ?? 'inactive streak reset failed')
    if (typeof reset !== 'object' || reset === null || Array.isArray(reset)) {
      throw new Error('invalid mobile inactivity result')
    }
    if (reset.user_id !== userId) throw new Error('mobile inactivity identity mismatch')
    if (reset.applied === false) {
      if (
        typeof reset.reason !== 'string' ||
        !['context_changed', 'progress_changed', 'not_inactive'].includes(reset.reason)
      )
        throw new Error('unknown mobile inactivity refusal')
      return result
    }
    if (
      reset.applied !== true ||
      reset.previous_streak !== current.currentStreak ||
      reset.last_active_date !== current.lastActiveDate ||
      reset.gap_days !== gapDays ||
      reset.latest_closable_date !== latestClosableDate
    )
      throw new Error('invalid mobile inactivity result')
  } else {
    const { data: resetRows, error: resetError } = await supabase
      .from('user_progress')
      .update({ current_streak: 0, updated_at: now.toISOString() })
      .eq('user_id', userId)
      .eq('current_streak', current.currentStreak)
      .eq('last_active_date', current.lastActiveDate)
      .select('user_id')
    if (resetError) throw new Error(resetError.message ?? 'inactive streak reset failed')
    if ((resetRows ?? []).length === 0) return result
  }

  streakReset.applied = true
  await supabase.from('product_events').insert({
    user_id: userId,
    event: 'streak.reset_inactive',
    properties: {
      previous_streak: current.currentStreak,
      last_active_date: current.lastActiveDate,
      gap_days: gapDays,
      yesterday: latestClosableDate,
    },
  })
  return result
}
