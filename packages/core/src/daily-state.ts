import { eatingBalance, netBalance } from './engine/balance.js'
import type { DailyTargets } from './engine/targets.js'
import { KCAL_BLOCK } from './progress-calc.js'
import type { Protocol } from './types.js'

export const DAILY_STATE_CALCULATION_VERSION = 'bodyflow.daily-state.v1' as const

export type DailyStateMealType = 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia'
export type DailyStateDayStatus =
  | 'complete'
  | 'user_skipped'
  | 'incomplete_no_response'
  | 'pending_close'
  | null

export interface DailyStateSnapshotInput {
  caloriesConsumed: number
  caloriesTarget: number | null
  proteinG: number
  proteinTarget: number | null
  carbsG: number
  fatG: number
  exerciseCalories: number
  waterConsumedMl: number
  protocol: Protocol | null
  dayClosed: boolean
  dayStatus: DailyStateDayStatus
  updatedAt: string | null
}

export interface DailyStateMeal {
  id: string
  meal_type: string | null
  food_name: string
  quantity_g: number | null
  kcal: number | null
  protein_g: number | null
  carbs_g: number | null
  fat_g: number | null
  consumed_at: string
  nutrition_source?: string | null
}

export interface DailyStateWorkout {
  id: string
  workout_type: string | null
  duration_min: number | null
  estimated_kcal: number | null
  intensity: string | null
  performed_at: string
}

export interface DailyStatePendingRegistration {
  id: string
  kind: 'meal' | 'workout' | 'unknown'
  meal_type: string | null
  created_at: string
  expires_at: string
}

export interface DailyStateMealGapInput {
  expected: DailyStateMealType[]
  registered: DailyStateMealType[]
  skipped: DailyStateMealType[]
  open: DailyStateMealType[]
  reliable: boolean
  activeDays: number
}

export interface DailyStateProgressInput {
  deficitBlock: number
  blocksCompleted: number
  updatedAt: string | null
}

export interface DailyStateInput {
  localDate: string
  generatedAt: string
  protocol: Protocol | null
  calculatedTargets: DailyTargets
  snapshot: DailyStateSnapshotInput | null
  meals: DailyStateMeal[]
  workouts: DailyStateWorkout[]
  pendingRegistrations: DailyStatePendingRegistration[]
  mealGap: DailyStateMealGapInput
  progress: DailyStateProgressInput | null
}

type CompletionState =
  | 'open'
  | 'pending_information'
  | 'complete'
  | 'complete_with_explicit_skip'
  | 'insufficient_data'

function nonNegative(value: number): number {
  return Number.isFinite(value) ? Math.max(0, value) : 0
}

function positiveOrNull(value: number | null): number | null {
  return value !== null && Number.isFinite(value) && value > 0 ? value : null
}

function percentage(value: number, target: number): number {
  return target > 0 ? Math.round((value / target) * 100) : 0
}

function latestTimestamp(values: Array<string | null | undefined>): string | null {
  let latest: { value: string; time: number } | null = null
  for (const value of values) {
    if (!value) continue
    const time = Date.parse(value)
    if (!Number.isFinite(time)) continue
    if (!latest || time > latest.time) latest = { value, time }
  }
  return latest?.value ?? null
}

function completionStatus(
  snapshot: DailyStateSnapshotInput | null,
  hasObservedActivity: boolean,
  mealGap: DailyStateMealGapInput,
): {
  status: CompletionState
  day_closed: boolean
  has_sufficient_data: boolean | null
} {
  const dayClosed = snapshot?.dayClosed ?? false

  if (snapshot?.dayStatus === 'incomplete_no_response') {
    return {
      status: 'insufficient_data',
      day_closed: dayClosed,
      has_sufficient_data: false,
    }
  }
  if (dayClosed && snapshot?.dayStatus === 'user_skipped') {
    return {
      status: 'complete_with_explicit_skip',
      day_closed: true,
      has_sufficient_data: true,
    }
  }
  if (dayClosed && !hasObservedActivity) {
    return { status: 'insufficient_data', day_closed: true, has_sufficient_data: false }
  }
  if (dayClosed && (snapshot?.dayStatus !== 'pending_close' || mealGap.open.length === 0)) {
    return { status: 'complete', day_closed: true, has_sufficient_data: true }
  }
  if (snapshot?.dayStatus === 'pending_close' && mealGap.open.length > 0) {
    return {
      status: 'pending_information',
      day_closed: dayClosed,
      has_sufficient_data: null,
    }
  }
  return { status: 'open', day_closed: false, has_sufficient_data: null }
}

export function buildDailyState(input: DailyStateInput) {
  const snapshot = input.snapshot
  const snapshotCaloriesTarget = positiveOrNull(snapshot?.caloriesTarget ?? null)
  const calculatedCaloriesTarget = positiveOrNull(input.calculatedTargets.calories_target)
  const caloriesTarget = snapshotCaloriesTarget ?? calculatedCaloriesTarget
  const snapshotProteinTarget = positiveOrNull(snapshot?.proteinTarget ?? null)
  const calculatedProteinTarget = positiveOrNull(input.calculatedTargets.protein_target)
  const proteinTarget = snapshotProteinTarget ?? calculatedProteinTarget
  const caloriesTargetSource =
    snapshotCaloriesTarget !== null
      ? ('daily_snapshot' as const)
      : calculatedCaloriesTarget !== null
        ? ('profile_calculation' as const)
        : ('unavailable' as const)
  const proteinTargetSource =
    snapshotProteinTarget !== null
      ? ('daily_snapshot' as const)
      : calculatedProteinTarget !== null
        ? ('profile_calculation' as const)
        : ('unavailable' as const)
  const targetSource =
    caloriesTargetSource === proteinTargetSource ? caloriesTargetSource : ('mixed' as const)

  const caloriesConsumed = nonNegative(snapshot?.caloriesConsumed ?? 0)
  const proteinConsumed = nonNegative(snapshot?.proteinG ?? 0)
  const carbsConsumed = nonNegative(snapshot?.carbsG ?? 0)
  const fatConsumed = nonNegative(snapshot?.fatG ?? 0)
  const exerciseCalories = nonNegative(snapshot?.exerciseCalories ?? 0)
  const foodBalance =
    caloriesTarget === null ? null : eatingBalance(caloriesConsumed, caloriesTarget)
  const dailyBalance =
    caloriesTarget === null ? null : netBalance(caloriesConsumed, caloriesTarget, exerciseCalories)
  const hasObservedActivity =
    input.meals.length > 0 ||
    input.workouts.length > 0 ||
    caloriesConsumed > 0 ||
    exerciseCalories > 0
  const completion = completionStatus(snapshot, hasObservedActivity, input.mealGap)
  const dailyBalanceStatus =
    completion.status === 'insufficient_data'
      ? ('insufficient_data' as const)
      : completion.status === 'complete' || completion.status === 'complete_with_explicit_skip'
        ? ('final' as const)
        : ('provisional' as const)
  const protocol = snapshot?.protocol ?? input.protocol

  const blockCurrent = input.progress ? nonNegative(input.progress.deficitBlock) : null
  const completedBlocks = input.progress
    ? Math.floor(nonNegative(input.progress.blocksCompleted))
    : null
  const waterConsumed = nonNegative(snapshot?.waterConsumedMl ?? 0)
  const consumedSource = snapshot ? ('daily_snapshot' as const) : ('empty_day' as const)
  const progressSource = input.progress ? ('user_progress' as const) : ('unavailable' as const)

  const proteinRemaining =
    proteinTarget === null ? null : Math.max(0, proteinTarget - proteinConsumed)
  const proteinPercentage =
    proteinTarget === null ? null : percentage(proteinConsumed, proteinTarget)
  const proteinStatus =
    proteinTarget === null
      ? ('target_unavailable' as const)
      : proteinConsumed >= proteinTarget
        ? ('target_reached' as const)
        : ('below_target' as const)

  return {
    local_date: input.localDate,
    protocol,
    targets: {
      calories_kcal: caloriesTarget,
      protein_g: proteinTarget,
      source: targetSource,
      calories_source: caloriesTargetSource,
      protein_source: proteinTargetSource,
    },
    consumed: {
      calories_kcal: caloriesConsumed,
      protein_g: proteinConsumed,
      carbs_g: carbsConsumed,
      fat_g: fatConsumed,
      source: consumedSource,
    },
    remaining_food_kcal: foodBalance === null ? null : Math.max(0, -foodBalance),
    food_excess_kcal: foodBalance === null ? null : Math.max(0, foodBalance),
    exercise_kcal: exerciseCalories,
    daily_balance_kcal: dailyBalance,
    daily_balance_status: dailyBalanceStatus,
    protein_status: {
      consumed_g: proteinConsumed,
      target_g: proteinTarget,
      remaining_g: proteinRemaining,
      percentage: proteinPercentage,
      status: proteinStatus,
    },
    meals: input.meals,
    workouts: input.workouts,
    hydration: {
      consumed_ml: waterConsumed,
      target_ml: null,
      status: waterConsumed > 0 ? ('tracked_without_target' as const) : ('not_recorded' as const),
    },
    supplements: {
      availability: 'not_implemented' as const,
      items: [] as Array<Record<string, unknown>>,
    },
    medications: {
      availability: 'not_implemented' as const,
      items: [] as Array<Record<string, unknown>>,
    },
    pending_actions: {
      registrations: input.pendingRegistrations,
      meal_gaps: {
        expected: input.mealGap.expected,
        registered: input.mealGap.registered,
        skipped: input.mealGap.skipped,
        open: input.mealGap.open,
        reliable: input.mealGap.reliable,
        source: input.mealGap.reliable
          ? ('personalized_pattern' as const)
          : ('new_user_fallback' as const),
        active_days: input.mealGap.activeDays,
      },
    },
    block_7700: {
      enabled: protocol === 'recomposicao',
      availability: input.progress ? ('available' as const) : ('unavailable' as const),
      target_kcal: KCAL_BLOCK,
      current_kcal: blockCurrent,
      percentage: blockCurrent === null ? null : percentage(blockCurrent, KCAL_BLOCK),
      completed_blocks: completedBlocks,
      total_credited_kcal:
        completedBlocks === null || blockCurrent === null
          ? null
          : completedBlocks * KCAL_BLOCK + blockCurrent,
      source: progressSource,
    },
    completion_status: completion,
    sources: {
      targets: targetSource,
      consumed: consumedSource,
      exercise: consumedSource,
      meals: 'meal_logs' as const,
      workouts: 'workout_logs' as const,
      hydration: consumedSource,
      pending_actions: 'pending_registrations_and_meal_pattern' as const,
      block_7700: progressSource,
    },
    calculation_version: DAILY_STATE_CALCULATION_VERSION,
    updated_at: latestTimestamp([
      snapshot?.updatedAt,
      input.progress?.updatedAt,
      ...input.pendingRegistrations.map((registration) => registration.created_at),
    ]),
    generated_at: input.generatedAt,
  }
}

export type DailyState = ReturnType<typeof buildDailyState>
