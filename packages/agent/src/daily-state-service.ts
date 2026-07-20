import {
  buildDailyState,
  computeDailyTargets,
  type DailyStateDayStatus,
  type DailyStateMealType,
  type ProfileRow,
} from '@mpp/core'
import type { Json, ServiceClient } from '@mpp/db'
import { loadCalcConfig } from './calc-config-loader.js'
import { getGapForDate } from './meal-patterns.js'
import { getLocalDateString } from './timezone-utils.js'

const MEAL_TYPE_ORDER: DailyStateMealType[] = ['cafe', 'almoco', 'lanche', 'jantar', 'ceia']
const PUBLIC_PENDING_MEAL_TYPES = new Set([...MEAL_TYPE_ORDER, 'outro'])

type GapResult = Awaited<ReturnType<typeof getGapForDate>>

export interface DailyStateServiceDependencies {
  loadConfig: typeof loadCalcConfig
  loadGap: (
    supabase: ServiceClient,
    userId: string,
    timezone: string,
    localDate: string,
  ) => Promise<GapResult>
}

const DEFAULT_DEPENDENCIES: DailyStateServiceDependencies = {
  loadConfig: loadCalcConfig,
  loadGap: getGapForDate,
}

export class DailyStateLoadError extends Error {
  constructor(readonly operation: string) {
    super(`${operation} failed`)
    this.name = 'DailyStateLoadError'
  }
}

function assertQuerySucceeded(error: { message?: string } | null, operation: string): void {
  if (error) throw new DailyStateLoadError(operation)
}

function normalizeDeficitLevel(value: number | null): 400 | 500 | 600 | null {
  return value === 400 || value === 500 || value === 600 ? value : null
}

function normalizeDayStatus(value: string | null): DailyStateDayStatus {
  if (
    value === 'complete' ||
    value === 'user_skipped' ||
    value === 'incomplete_no_response' ||
    value === 'pending_close'
  ) {
    return value
  }
  return null
}

function profileRow(
  row: {
    sex: 'masculino' | 'feminino' | null
    birth_date: string | null
    height_cm: number | null
    weight_kg: number | null
    body_fat_percent: number | null
    activity_level: 'sedentario' | 'leve' | 'moderado' | 'alto' | 'atleta' | null
    training_frequency: number | null
    water_intake: 'pouco' | 'moderado' | 'bastante' | null
    hunger_level: 'pouca' | 'moderada' | 'muita' | null
    current_protocol: 'recomposicao' | 'ganho_massa' | 'manutencao' | null
    goal_type: 'BF' | 'IMC' | 'peso_kg' | null
    goal_value: number | null
    deficit_level: number | null
  } | null,
): ProfileRow | null {
  if (!row) return null
  return { ...row, deficit_level: normalizeDeficitLevel(row.deficit_level) }
}

function jsonRecord(value: Json): Record<string, Json | undefined> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, Json | undefined>)
    : null
}

function stringValue(value: Json | undefined): string | null {
  return typeof value === 'string' ? value : null
}

function pendingKind(value: Json): 'meal' | 'workout' | 'unknown' {
  const kind = stringValue(jsonRecord(value)?.kind)
  return kind === 'meal' || kind === 'workout' ? kind : 'unknown'
}

function pendingMealType(value: Json): string | null {
  const proposal = jsonRecord(value)
  const mealType = stringValue(proposal?.mealType) ?? stringValue(proposal?.meal_type)
  return mealType && PUBLIC_PENDING_MEAL_TYPES.has(mealType) ? mealType : null
}

function orderedMealTypes(values: Set<DailyStateMealType>): DailyStateMealType[] {
  return MEAL_TYPE_ORDER.filter((mealType) => values.has(mealType))
}

export async function loadOfficialDailyState(
  supabase: ServiceClient,
  userId: string,
  timezone: string,
  now = new Date(),
  dependencies: DailyStateServiceDependencies = DEFAULT_DEPENDENCIES,
) {
  const localDate = getLocalDateString(timezone, now)
  const nowIso = now.toISOString()

  const profileQuery = supabase
    .from('user_profiles')
    .select(
      'sex, birth_date, height_cm, weight_kg, body_fat_percent, activity_level, training_frequency, water_intake, hunger_level, current_protocol, goal_type, goal_value, deficit_level',
    )
    .eq('user_id', userId)
    .maybeSingle()
  const snapshotQuery = supabase
    .from('daily_snapshots')
    .select(
      'id, calories_consumed, calories_target, protein_g, protein_target, carbs_g, fat_g, exercise_calories, water_consumed_ml, current_protocol, day_closed, day_status, updated_at',
    )
    .eq('user_id', userId)
    .eq('date', localDate)
    .maybeSingle()
  const progressQuery = supabase
    .from('user_progress')
    .select('deficit_block, blocks_completed, updated_at')
    .eq('user_id', userId)
    .maybeSingle()
  const pendingQuery = supabase
    .from('pending_registrations')
    .select('id, proposal, status, created_at, expires_at')
    .eq('user_id', userId)
    .eq('status', 'pending')
    .gt('expires_at', nowIso)
    .order('created_at', { ascending: false })
    .limit(20)

  const results = await Promise.all([
    profileQuery,
    snapshotQuery,
    progressQuery,
    pendingQuery,
    dependencies.loadConfig(supabase),
    dependencies.loadGap(supabase, userId, timezone, localDate),
  ]).catch(() => {
    throw new DailyStateLoadError('daily state dependency lookup')
  })
  const [profileResult, snapshotResult, progressResult, pendingResult, config, gap] = results

  assertQuerySucceeded(profileResult.error, 'daily state profile lookup')
  assertQuerySucceeded(snapshotResult.error, 'daily state snapshot lookup')
  assertQuerySucceeded(progressResult.error, 'daily state progress lookup')
  assertQuerySucceeded(pendingResult.error, 'daily state pending lookup')

  const snapshot = snapshotResult.data
  let meals: Array<{
    id: string
    meal_type: string | null
    food_name: string
    quantity_g: number | null
    kcal: number | null
    protein_g: number | null
    carbs_g: number | null
    fat_g: number | null
    consumed_at: string
    nutrition_source: string | null
  }> = []
  let workouts: Array<{
    id: string
    workout_type: string | null
    duration_min: number | null
    estimated_kcal: number | null
    intensity: string | null
    performed_at: string
  }> = []

  if (snapshot) {
    const [mealResult, workoutResult] = await Promise.all([
      supabase
        .from('meal_logs')
        .select(
          'id, meal_type, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, consumed_at, source',
        )
        .eq('user_id', userId)
        .eq('snapshot_id', snapshot.id)
        .order('consumed_at', { ascending: true }),
      supabase
        .from('workout_logs')
        .select('id, workout_type, duration_min, estimated_kcal, intensity, performed_at')
        .eq('user_id', userId)
        .eq('snapshot_id', snapshot.id)
        .order('performed_at', { ascending: true }),
    ])
    assertQuerySucceeded(mealResult.error, 'daily state meals lookup')
    assertQuerySucceeded(workoutResult.error, 'daily state workouts lookup')
    meals = (mealResult.data ?? []).map((meal) => ({
      id: meal.id,
      meal_type: meal.meal_type,
      food_name: meal.food_name,
      quantity_g: meal.quantity_g,
      kcal: meal.kcal,
      protein_g: meal.protein_g,
      carbs_g: meal.carbs_g,
      fat_g: meal.fat_g,
      consumed_at: meal.consumed_at,
      nutrition_source: meal.source,
    }))
    workouts = (workoutResult.data ?? []).map((workout) => ({
      id: workout.id,
      workout_type: workout.workout_type,
      duration_min: workout.duration_min,
      estimated_kcal: workout.estimated_kcal,
      intensity: workout.intensity,
      performed_at: workout.performed_at,
    }))
  }

  const profile = profileRow(profileResult.data)
  const progress = progressResult.data
  const pendingRegistrations = (pendingResult.data ?? []).map((pending) => ({
    id: pending.id,
    kind: pendingKind(pending.proposal),
    meal_type: pendingMealType(pending.proposal),
    created_at: pending.created_at,
    expires_at: pending.expires_at,
  }))

  return buildDailyState({
    localDate,
    generatedAt: nowIso,
    protocol: profile?.current_protocol ?? null,
    calculatedTargets: computeDailyTargets(profile, config),
    snapshot: snapshot
      ? {
          caloriesConsumed: snapshot.calories_consumed,
          caloriesTarget: snapshot.calories_target,
          proteinG: snapshot.protein_g,
          proteinTarget: snapshot.protein_target,
          carbsG: snapshot.carbs_g,
          fatG: snapshot.fat_g,
          exerciseCalories: snapshot.exercise_calories,
          waterConsumedMl: snapshot.water_consumed_ml,
          protocol: snapshot.current_protocol,
          dayClosed: snapshot.day_closed,
          dayStatus: normalizeDayStatus(snapshot.day_status),
          updatedAt: snapshot.updated_at,
        }
      : null,
    meals,
    workouts,
    pendingRegistrations,
    mealGap: {
      expected: orderedMealTypes(gap.pattern.expected),
      registered: orderedMealTypes(gap.registered),
      skipped: orderedMealTypes(gap.skipped),
      open: orderedMealTypes(gap.gap),
      reliable: !gap.pattern.fallbackUsed,
      activeDays: gap.pattern.activeDays,
    },
    progress: progress
      ? {
          deficitBlock: progress.deficit_block,
          blocksCompleted: progress.blocks_completed,
          updatedAt: progress.updated_at,
        }
      : null,
  })
}
