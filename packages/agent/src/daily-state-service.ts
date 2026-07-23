import {
  buildDailyState,
  computeDailyTargets,
  type DailyStateDayStatus,
  type DailyStateMealType,
  type DailyStateRoutineItemInput,
  type ProfileRow,
  routineItemTypeSchema,
  routineOriginSchema,
} from '@mpp/core'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { loadCalcConfig } from './calc-config-loader.js'
import { getMealPattern, getSkippedMealsForDate } from './meal-patterns.js'
import { getLocalDateString } from './timezone-utils.js'

const MEAL_TYPE_ORDER: DailyStateMealType[] = ['cafe', 'almoco', 'lanche', 'jantar', 'ceia']
const PUBLIC_PENDING_MEAL_TYPES = new Set([...MEAL_TYPE_ORDER, 'outro'])

type MealPatternResult = Awaited<ReturnType<typeof getMealPattern>>
type SkippedMealsResult = Awaited<ReturnType<typeof getSkippedMealsForDate>>

export interface DailyStateServiceDependencies {
  loadConfig: typeof loadCalcConfig
  loadMealPattern: (
    supabase: ServiceClient,
    userId: string,
    timezone: string,
  ) => Promise<MealPatternResult>
  loadSkippedMeals: (
    supabase: ServiceClient,
    userId: string,
    timezone: string,
    localDate: string,
  ) => Promise<SkippedMealsResult>
}

const DEFAULT_DEPENDENCIES: DailyStateServiceDependencies = {
  loadConfig: loadCalcConfig,
  loadMealPattern: getMealPattern,
  loadSkippedMeals: getSkippedMealsForDate,
}

const SNAPSHOT_VERSION_SELECT =
  'id, calories_consumed, calories_target, protein_g, protein_target, carbs_g, fat_g, exercise_calories, water_consumed_ml, current_protocol, day_closed, day_status, updated_at'
const SNAPSHOT_WITH_LOGS_SELECT = `${SNAPSHOT_VERSION_SELECT}, meal_logs(id, meal_type, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, consumed_at, source), workout_logs(id, workout_type, duration_min, estimated_kcal, intensity, performed_at)`
const routineUuidSchema = z.string().uuid()
const routineDateTimeSchema = z.string().datetime({ offset: true })
const routineOccurrenceSchema = z
  .object({
    occurrence_key: z.string().regex(/^[0-9a-f]{64}$/),
    scheduled_for: routineDateTimeSchema,
    status: z.enum(['pending', 'taken', 'snoozed', 'skipped', 'missed']),
    last_action_at: routineDateTimeSchema.nullable(),
    snoozed_until: routineDateTimeSchema.nullable(),
  })
  .strict()
const routineScheduleSchema = z
  .object({
    id: routineUuidSchema,
    local_time: z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/),
    weekdays: z.array(z.number().int().min(0).max(6)).min(1).max(7),
    occurrence: routineOccurrenceSchema.nullable(),
  })
  .strict()
const routineItemSchema = z
  .object({
    id: routineUuidSchema,
    item_type: routineItemTypeSchema,
    name: z.string().trim().min(1).max(200),
    dose_text: z.string().trim().min(1).max(120).nullable(),
    origin: routineOriginSchema.nullable(),
    reminders_enabled: z.boolean(),
    active: z.literal(true),
    archived_at: z.null(),
    version: z.number().int().positive(),
    created_at: routineDateTimeSchema,
    updated_at: routineDateTimeSchema,
    schedules: z.array(routineScheduleSchema),
  })
  .strict()
const routinePageSchema = z
  .object({
    local_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    items: z.array(routineItemSchema),
  })
  .strict()

type RoutineRpc = (
  functionName: string,
  params: Record<string, unknown>,
) => Promise<{ data: unknown; error: { message?: string } | null }>

export class DailyStateLoadError extends Error {
  constructor(readonly operation: string) {
    super(`${operation} failed`)
    this.name = 'DailyStateLoadError'
  }
}

class DailyStateReadChangedError extends Error {
  constructor() {
    super('Daily state changed during read')
    this.name = 'DailyStateReadChangedError'
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

function parseRoutinePage(
  data: unknown,
  itemType: 'supplement' | 'medication',
  operation: string,
): { localDate: string; items: DailyStateRoutineItemInput[] } {
  const parsed = routinePageSchema.safeParse(data)
  if (!parsed.success || parsed.data.items.some((item) => item.item_type !== itemType)) {
    throw new DailyStateLoadError(operation)
  }

  return {
    localDate: parsed.data.local_date,
    items: parsed.data.items.map((item) => ({
      id: item.id,
      itemType: item.item_type,
      name: item.name,
      doseText: item.dose_text,
      origin: item.origin,
      remindersEnabled: item.reminders_enabled,
      schedules: item.schedules.map((schedule) => ({
        id: schedule.id,
        localTime: schedule.local_time,
        weekdays: schedule.weekdays,
      })),
      occurrences: item.schedules.flatMap((schedule) =>
        schedule.occurrence
          ? [
              {
                reminderRuleId: schedule.id,
                scheduledFor: schedule.occurrence.scheduled_for,
                status: schedule.occurrence.status,
                lastActionAt: schedule.occurrence.last_action_at,
                snoozedUntil: schedule.occurrence.snoozed_until,
              },
            ]
          : [],
      ),
      updatedAt: item.updated_at,
    })),
  }
}

function sourceFingerprint(value: unknown): string {
  return JSON.stringify(value ?? null)
}

function snapshotFingerprint(
  snapshot: {
    id: string
    calories_consumed: number
    calories_target: number | null
    protein_g: number
    protein_target: number | null
    carbs_g: number
    fat_g: number
    exercise_calories: number
    water_consumed_ml: number
    current_protocol: string | null
    day_closed: boolean
    day_status: string
    updated_at: string
  } | null,
): string {
  if (!snapshot) return 'null'
  return JSON.stringify({
    id: snapshot.id,
    calories_consumed: snapshot.calories_consumed,
    calories_target: snapshot.calories_target,
    protein_g: snapshot.protein_g,
    protein_target: snapshot.protein_target,
    carbs_g: snapshot.carbs_g,
    fat_g: snapshot.fat_g,
    exercise_calories: snapshot.exercise_calories,
    water_consumed_ml: snapshot.water_consumed_ml,
    current_protocol: snapshot.current_protocol,
    day_closed: snapshot.day_closed,
    day_status: snapshot.day_status,
    updated_at: snapshot.updated_at,
  })
}

async function loadOfficialDailyStateAttempt(
  supabase: ServiceClient,
  userId: string,
  timezone: string,
  now = new Date(),
  dependencies: DailyStateServiceDependencies = DEFAULT_DEPENDENCIES,
) {
  const localDate = getLocalDateString(timezone, now)
  const nowIso = now.toISOString()
  const routineRpc = supabase.rpc.bind(supabase) as unknown as RoutineRpc

  const profileQuery = supabase
    .from('user_profiles')
    .select(
      'sex, birth_date, height_cm, weight_kg, body_fat_percent, activity_level, training_frequency, water_intake, hunger_level, current_protocol, goal_type, goal_value, deficit_level',
    )
    .eq('user_id', userId)
    .maybeSingle()
  const snapshotQuery = supabase
    .from('daily_snapshots')
    .select(SNAPSHOT_WITH_LOGS_SELECT)
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
  const hydrationTargetQuery = supabase
    .from('notification_preferences')
    .select('hydration_target_ml, updated_at')
    .eq('user_id', userId)
    .maybeSingle()
  const supplementRoutineQuery = routineRpc('list_mobile_routine_items', {
    p_user_id: userId,
    p_item_type: 'supplement',
    p_include_archived: false,
    p_now: nowIso,
  })
  const medicationRoutineQuery = routineRpc('list_mobile_routine_items', {
    p_user_id: userId,
    p_item_type: 'medication',
    p_include_archived: false,
    p_now: nowIso,
  })

  const results = await Promise.all([
    profileQuery,
    snapshotQuery,
    progressQuery,
    pendingQuery,
    dependencies.loadConfig(supabase),
    dependencies.loadMealPattern(supabase, userId, timezone),
    dependencies.loadSkippedMeals(supabase, userId, timezone, localDate),
    hydrationTargetQuery,
    supplementRoutineQuery,
    medicationRoutineQuery,
  ]).catch(() => {
    throw new DailyStateLoadError('daily state dependency lookup')
  })
  const [
    profileResult,
    snapshotResult,
    progressResult,
    pendingResult,
    config,
    pattern,
    skipped,
    hydrationTargetResult,
    supplementRoutineResult,
    medicationRoutineResult,
  ] = results

  assertQuerySucceeded(profileResult.error, 'daily state profile lookup')
  assertQuerySucceeded(snapshotResult.error, 'daily state snapshot lookup')
  assertQuerySucceeded(progressResult.error, 'daily state progress lookup')
  assertQuerySucceeded(pendingResult.error, 'daily state pending lookup')
  assertQuerySucceeded(hydrationTargetResult.error, 'daily state hydration target lookup')
  assertQuerySucceeded(supplementRoutineResult.error, 'daily state routine items lookup')
  assertQuerySucceeded(medicationRoutineResult.error, 'daily state routine items lookup')
  const supplementRoutinePage = parseRoutinePage(
    supplementRoutineResult.data,
    'supplement',
    'daily state routine items lookup',
  )
  const medicationRoutinePage = parseRoutinePage(
    medicationRoutineResult.data,
    'medication',
    'daily state routine items lookup',
  )
  const snapshot = snapshotResult.data
  const meals: Array<{
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
  }> = (snapshot?.meal_logs ?? []).map((meal) => ({
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
  meals.sort(
    (left, right) =>
      left.consumed_at.localeCompare(right.consumed_at) || left.id.localeCompare(right.id),
  )
  const workouts: Array<{
    id: string
    workout_type: string | null
    duration_min: number | null
    estimated_kcal: number | null
    intensity: string | null
    performed_at: string
  }> = (snapshot?.workout_logs ?? []).map((workout) => ({
    id: workout.id,
    workout_type: workout.workout_type,
    duration_min: workout.duration_min,
    estimated_kcal: workout.estimated_kcal,
    intensity: workout.intensity,
    performed_at: workout.performed_at,
  }))
  workouts.sort(
    (left, right) =>
      left.performed_at.localeCompare(right.performed_at) || left.id.localeCompare(right.id),
  )

  const profile = profileRow(profileResult.data)
  const progress = progressResult.data
  const pendingRegistrations = (pendingResult.data ?? []).map((pending) => ({
    id: pending.id,
    kind: pendingKind(pending.proposal),
    meal_type: pendingMealType(pending.proposal),
    created_at: pending.created_at,
    expires_at: pending.expires_at,
  }))
  const routineItems = [...supplementRoutinePage.items, ...medicationRoutinePage.items]
  const registered = new Set<DailyStateMealType>()
  for (const meal of meals) {
    if (meal.meal_type && MEAL_TYPE_ORDER.includes(meal.meal_type as DailyStateMealType)) {
      registered.add(meal.meal_type as DailyStateMealType)
    }
  }
  const openGap = new Set<DailyStateMealType>()
  for (const mealType of pattern.expected) {
    if (!registered.has(mealType) && !skipped.has(mealType)) openGap.add(mealType)
  }

  // Registration/workout writes update the snapshot atomically. Re-reading its
  // scalar version prevents returning old totals with new embedded logs (or vice versa).
  const [
    currentSnapshotResult,
    currentHydrationTargetResult,
    currentSupplementRoutineResult,
    currentMedicationRoutineResult,
  ] = await Promise.all([
    supabase
      .from('daily_snapshots')
      .select(SNAPSHOT_VERSION_SELECT)
      .eq('user_id', userId)
      .eq('date', localDate)
      .maybeSingle(),
    supabase
      .from('notification_preferences')
      .select('hydration_target_ml, updated_at')
      .eq('user_id', userId)
      .maybeSingle(),
    routineRpc('list_mobile_routine_items', {
      p_user_id: userId,
      p_item_type: 'supplement',
      p_include_archived: false,
      p_now: nowIso,
    }),
    routineRpc('list_mobile_routine_items', {
      p_user_id: userId,
      p_item_type: 'medication',
      p_include_archived: false,
      p_now: nowIso,
    }),
  ]).catch(() => {
    throw new DailyStateLoadError('daily state consistency lookup')
  })
  assertQuerySucceeded(currentSnapshotResult.error, 'daily state consistency lookup')
  assertQuerySucceeded(
    currentHydrationTargetResult.error,
    'daily state hydration consistency lookup',
  )
  assertQuerySucceeded(
    currentSupplementRoutineResult.error,
    'daily state routine consistency lookup',
  )
  assertQuerySucceeded(
    currentMedicationRoutineResult.error,
    'daily state routine consistency lookup',
  )
  const currentSupplementRoutinePage = parseRoutinePage(
    currentSupplementRoutineResult.data,
    'supplement',
    'daily state routine consistency lookup',
  )
  const currentMedicationRoutinePage = parseRoutinePage(
    currentMedicationRoutineResult.data,
    'medication',
    'daily state routine consistency lookup',
  )
  if (
    snapshotFingerprint(snapshot) !== snapshotFingerprint(currentSnapshotResult.data) ||
    sourceFingerprint(hydrationTargetResult.data) !==
      sourceFingerprint(currentHydrationTargetResult.data) ||
    sourceFingerprint(supplementRoutinePage) !== sourceFingerprint(currentSupplementRoutinePage) ||
    sourceFingerprint(medicationRoutinePage) !== sourceFingerprint(currentMedicationRoutinePage)
  ) {
    throw new DailyStateReadChangedError()
  }

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
    hydrationTarget: hydrationTargetResult.data
      ? {
          targetMl: hydrationTargetResult.data.hydration_target_ml,
          updatedAt: hydrationTargetResult.data.updated_at,
        }
      : null,
    routineItems,
    mealGap: {
      expected: orderedMealTypes(pattern.expected),
      registered: orderedMealTypes(registered),
      skipped: orderedMealTypes(skipped),
      open: orderedMealTypes(openGap),
      reliable: !pattern.fallbackUsed,
      activeDays: pattern.activeDays,
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

export async function loadOfficialDailyState(
  supabase: ServiceClient,
  userId: string,
  timezone: string,
  now = new Date(),
  dependencies: DailyStateServiceDependencies = DEFAULT_DEPENDENCIES,
) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      return await loadOfficialDailyStateAttempt(supabase, userId, timezone, now, dependencies)
    } catch (error) {
      if (!(error instanceof DailyStateReadChangedError)) throw error
    }
  }
  throw new DailyStateLoadError('daily state consistency')
}
