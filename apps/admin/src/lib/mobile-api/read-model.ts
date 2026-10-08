import {
  DailyStateLoadError,
  isUnresolvedNutritionSource,
  loadOfficialDailyState,
} from '@mpp/agent'
import { normalizeProtocol, resolveFlowBloco7700Policy } from '@mpp/core'
import type { Json, ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import type { HistoryQuery, TrendsQuery } from './contracts'
import { MobileApiError } from './http'

type JsonRecord = Record<string, Json | undefined>

function record(value: Json | null | undefined): JsonRecord | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as JsonRecord) : null
}

function finiteNumber(value: Json | undefined): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function stringValue(value: Json | undefined): string | null {
  return typeof value === 'string' ? value : null
}

function throwQueryError(error: { message?: string } | null, operation: string): void {
  if (error) throw new MobileApiError(500, 'data_access_failed', `${operation} failed`)
}

export function meDto(auth: MobileAuthContext) {
  return {
    id: auth.userId,
    email: auth.identity.email,
    name: auth.patient.name,
    locale: auth.patient.locale,
    timezone: auth.patient.timezone,
    country: auth.patient.country,
    country_confirmed: auth.patient.countryConfirmed,
    status: auth.patient.status,
    email_confirmed: auth.identity.emailConfirmedAt !== null,
  }
}

function safePendingItem(value: Json): Record<string, string | number | string[] | null> | null {
  const item = record(value)
  if (!item) return null
  const name = stringValue(item.name) ?? stringValue(item.food_name)
  const quantity = finiteNumber(item.quantity_g)
  if (!name || quantity === null) return null

  return {
    name,
    quantity_g: quantity,
    kcal: finiteNumber(item.kcal),
    protein_g: finiteNumber(item.protein_g),
    carbs_g: finiteNumber(item.carbs_g),
    fat_g: finiteNumber(item.fat_g),
    // Calorie provenance already stored with the item: the patient's value as
    // received (null when none) and the source the server applied
    // ("user_kcal" only when that value was used). Always present, so a
    // client can tell "no override" from a response that lacks the fields.
    user_kcal: finiteNumber(item.user_kcal),
    nutrition_source: stringValue(item.nutrition_source),
    // "needs_clarification": the server has not calculated this item yet (it
    // is not a legitimate zero) and the registration cannot be confirmed until
    // the patient edits it. preparation_options lists the preparations to
    // choose from when that is the missing information.
    resolution: isUnresolvedNutritionSource(stringValue(item.nutrition_source))
      ? 'needs_clarification'
      : 'resolved',
    preparation_options: Array.isArray(item.preparation_options)
      ? item.preparation_options.filter((option): option is string => typeof option === 'string')
      : null,
    // How the patient's quantity was obtained ("stated", "visual_estimate",
    // "portion_reference"); null when the proposal did not record it.
    quantity_basis: stringValue(item.quantity_basis),
  }
}

function safeTotals(value: Json | undefined) {
  const totals = record(value)
  if (!totals) return null
  return {
    kcal: finiteNumber(totals.kcal),
    protein_g: finiteNumber(totals.protein_g),
    carbs_g: finiteNumber(totals.carbs_g),
    fat_g: finiteNumber(totals.fat_g),
  }
}

export function sanitizePendingProposal(value: Json) {
  const proposal = record(value)
  const kind = stringValue(proposal?.kind)

  if (kind === 'meal') {
    const items = Array.isArray(proposal?.items)
      ? proposal.items
          .map(safePendingItem)
          .filter((item): item is NonNullable<typeof item> => item !== null)
      : []
    return {
      kind,
      meal_type: stringValue(proposal?.mealType) ?? stringValue(proposal?.meal_type) ?? 'outro',
      items,
      totals: safeTotals(proposal?.totals),
      // Origin of the meal: the channel and, for media, the asset the patient
      // reviewed. Provider ids and raw text stay in the backend.
      source: {
        channel: stringValue(proposal?.sourceContentType) ?? 'mobile',
        media_asset_id: stringValue(proposal?.source_media_asset_id),
      },
      warnings: Array.isArray(proposal?.userWarnings)
        ? proposal.userWarnings.filter((warning): warning is string => typeof warning === 'string')
        : [],
    }
  }

  if (kind === 'workout') {
    return {
      kind,
      workout_type: stringValue(proposal?.workoutType) ?? stringValue(proposal?.workout_type),
      duration_min: finiteNumber(proposal?.durationMin) ?? finiteNumber(proposal?.duration_min),
      estimated_kcal: finiteNumber(proposal?.kcalEst) ?? finiteNumber(proposal?.estimated_kcal),
      intensity: stringValue(proposal?.intensity),
    }
  }

  return { kind: 'unknown' as const }
}

const PROFILE_COLUMNS =
  'sex, birth_date, height_cm, weight_kg, body_fat_percent, activity_level, training_frequency, water_intake, hunger_level, wake_time, bedtime, current_protocol, goal_type, goal_value, deficit_level, food_organization, onboarding_completed, onboarding_step, updated_at'

type ProfileQuery = (columns: string) => {
  eq(
    column: string,
    value: string,
  ): {
    maybeSingle(): PromiseLike<{
      data: Record<string, unknown> | null
      error: { code?: string; message: string } | null
    }>
  }
}

export async function loadProfile(supabase: ServiceClient, userId: string) {
  const select: ProfileQuery = (columns) =>
    (supabase.from('user_profiles') as unknown as { select: ProfileQuery }).select(columns)
  // weight_measured_at exists only after the weight migration. A database
  // without it (42703) still answers, with the instant reported as unknown.
  // weight_instant_source says whether that instant is the measurement's
  // ('measured') or only the time the value was written ('recorded').
  const dated = await select(`${PROFILE_COLUMNS}, weight_measured_at, weight_instant_source`)
    .eq('user_id', userId)
    .maybeSingle()
  if (dated.error?.code !== '42703') {
    throwQueryError(dated.error as never, 'Profile lookup')
    return dated.data
  }
  const legacy = await select(PROFILE_COLUMNS).eq('user_id', userId).maybeSingle()
  throwQueryError(legacy.error as never, 'Profile lookup')
  return legacy.data
    ? { ...legacy.data, weight_measured_at: null, weight_instant_source: null }
    : legacy.data
}

export async function loadToday(
  supabase: ServiceClient,
  userId: string,
  timezone: string,
  now = new Date(),
) {
  try {
    return await loadOfficialDailyState(supabase, userId, timezone, now)
  } catch (error) {
    if (error instanceof DailyStateLoadError) {
      throw new MobileApiError(500, 'data_access_failed', 'Daily state lookup failed')
    }
    throw error
  }
}

export async function loadPlan(supabase: ServiceClient, userId: string) {
  const now = new Date().toISOString()
  const [trainingResult, prescriptionResult] = await Promise.all([
    supabase
      .from('training_plans')
      .select(
        'id, plan_type, days_per_week, equipment_summary, weekly_schedule, generated_at, valid_until, version, notes',
      )
      .eq('user_id', userId)
      .eq('active', true)
      .or(`valid_until.is.null,valid_until.gte.${now}`)
      .order('generated_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from('prescriptions')
      .select('id, type, payload, generated_at, valid_until, version, notes')
      .eq('user_id', userId)
      .or(`valid_until.is.null,valid_until.gte.${now}`)
      .order('generated_at', { ascending: false })
      .limit(10),
  ])
  throwQueryError(trainingResult.error, 'Training plan lookup')
  throwQueryError(prescriptionResult.error, 'Prescription lookup')
  return {
    training: trainingResult.data,
    nutrition: prescriptionResult.data ?? [],
  }
}

export async function loadProgress(supabase: ServiceClient, userId: string) {
  const [progress, profile] = await Promise.all([
    supabase
      .from('user_progress')
      .select(
        'xp_total, level, current_streak, longest_streak, blocks_completed, deficit_block, current_weight, current_bf_percent, badges_earned, last_active_date, next_reevaluation, updated_at',
      )
      .eq('user_id', userId)
      .maybeSingle(),
    supabase.from('user_profiles').select('current_protocol').eq('user_id', userId).maybeSingle(),
  ])
  throwQueryError(progress.error, 'Progress lookup')
  throwQueryError(profile.error, 'Progress objective lookup')
  if (!progress.data) return null
  const currentProtocol = normalizeProtocol(profile.data?.current_protocol)
  return {
    ...progress.data,
    current_protocol: currentProtocol,
    block_7700_enabled: resolveFlowBloco7700Policy(currentProtocol).enabled,
  }
}

export interface TrendsSnapshotRow {
  date: string
  calories_consumed: number
  calories_target: number | null
  exercise_calories: number
  protein_g: number | string
  protein_target: number | string | null
  water_consumed_ml: number
  deficit_accumulated: number
  xp_earned: number
  day_closed: boolean
}

export interface TrendsWeightRow {
  evaluation_date: string
  weight_kg: number | string | null
}

/** The profile's current weight: the value `POST /weight` writes. */
export interface TrendsCurrentWeight {
  weight_kg: number | string | null
  weight_measured_at: string | null
  /** 'measured' = the instant of the measurement; 'recorded' = only when it was written. */
  weight_instant_source?: string | null
}

/** YYYY-MM-DD of an instant on the patient's own calendar. */
function localDateOf(instant: string, timezone: string): string | null {
  const date = new Date(instant)
  if (Number.isNaN(date.getTime())) return null
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(date)
  } catch {
    return null
  }
}

/**
 * Series for the mobile charts, exactly as stored: one row per day that has a
 * snapshot (days without one are absent, never filled in) and the dated
 * weights. Both ascend by date. Nothing is estimated.
 *
 * Weights are the reevaluations plus the profile's current weight on the day
 * it was measured (the patient's calendar). A weight registered in the app
 * only updates the profile; without this point the chart ended at the last
 * reevaluation while the same screen showed the newer weight. The profile
 * holds one value, so on a day that also has a reevaluation it replaces that
 * point (it is the newest reading). Left out: an undated weight, and a weight
 * whose instant is only when the value was written ('recorded'), since that
 * is not the day it was measured. The profile keeps a single value: this adds
 * the latest measurement, not a history of the weights typed in the app.
 */
export function shapeTrends(
  snapshots: TrendsSnapshotRow[],
  weights: TrendsWeightRow[],
  days: number,
  current?: { weight: TrendsCurrentWeight | null; timezone: string },
) {
  const byDate = [...snapshots].sort((a, b) => a.date.localeCompare(b.date)).slice(-days)
  let datedWeights = weights
    .filter((row) => row.weight_kg !== null)
    .map((row) => ({ date: row.evaluation_date, weight_kg: Number(row.weight_kg) }))
    .filter((row) => Number.isFinite(row.weight_kg))
    .sort((a, b) => a.date.localeCompare(b.date))
  const profile = current?.weight
  if (
    profile &&
    profile.weight_kg !== null &&
    profile.weight_measured_at &&
    profile.weight_instant_source === 'measured'
  ) {
    const date = localDateOf(profile.weight_measured_at, current.timezone || 'UTC')
    const value = Number(profile.weight_kg)
    const latest = datedWeights.at(-1)?.date
    if (date && Number.isFinite(value) && (latest === undefined || date >= latest)) {
      datedWeights = [
        ...datedWeights.filter((row) => row.date !== date),
        { date, weight_kg: value },
      ]
    }
  }
  return {
    days,
    daily: byDate.map((row) => ({
      date: row.date,
      calories_consumed: row.calories_consumed,
      calories_target: row.calories_target,
      exercise_calories: row.exercise_calories,
      protein_g: Number(row.protein_g),
      protein_target: row.protein_target === null ? null : Number(row.protein_target),
      water_consumed_ml: row.water_consumed_ml,
      deficit_accumulated: row.deficit_accumulated,
      xp_earned: row.xp_earned,
      day_closed: row.day_closed,
    })),
    weights: datedWeights,
  }
}

export async function loadTrends(
  supabase: ServiceClient,
  userId: string,
  query: TrendsQuery,
  timezone = 'UTC',
) {
  const [snapshotResult, weightResult, profile] = await Promise.all([
    supabase
      .from('daily_snapshots')
      .select(
        'date, calories_consumed, calories_target, exercise_calories, protein_g, protein_target, water_consumed_ml, deficit_accumulated, xp_earned, day_closed',
      )
      .eq('user_id', userId)
      .order('date', { ascending: false })
      .limit(query.days),
    supabase
      .from('reevaluations')
      .select('evaluation_date, weight_kg')
      .eq('user_id', userId)
      .order('evaluation_date', { ascending: false })
      .limit(12),
    // The charts never depended on the profile: if it cannot be read, the
    // series is the stored one, without the extra point.
    loadProfile(supabase, userId).catch(() => null),
  ])
  throwQueryError(snapshotResult.error, 'Trends snapshot lookup')
  throwQueryError(weightResult.error, 'Trends weight lookup')
  return shapeTrends(
    (snapshotResult.data ?? []) as TrendsSnapshotRow[],
    (weightResult.data ?? []) as TrendsWeightRow[],
    query.days,
    { weight: (profile ?? null) as TrendsCurrentWeight | null, timezone },
  )
}

export async function loadHistory(supabase: ServiceClient, userId: string, query: HistoryQuery) {
  let meals = supabase
    .from('meal_logs')
    .select('id, meal_type, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, consumed_at')
    .eq('user_id', userId)
    .order('consumed_at', { ascending: false })
    .limit(query.limit)
  let workouts = supabase
    .from('workout_logs')
    .select('id, workout_type, duration_min, estimated_kcal, intensity, performed_at')
    .eq('user_id', userId)
    .order('performed_at', { ascending: false })
    .limit(query.limit)

  if (query.before) {
    meals = meals.lt('consumed_at', query.before)
    workouts = workouts.lt('performed_at', query.before)
  }

  const [mealResult, workoutResult] = await Promise.all([meals, workouts])
  throwQueryError(mealResult.error, 'Meal history lookup')
  throwQueryError(workoutResult.error, 'Workout history lookup')
  return {
    meals: mealResult.data ?? [],
    workouts: workoutResult.data ?? [],
    pagination: { limit: query.limit, before: query.before ?? null },
  }
}

export async function loadPending(supabase: ServiceClient, userId: string) {
  const { data, error } = await supabase
    .from('pending_registrations')
    .select('id, proposal, status, created_at, expires_at')
    .eq('user_id', userId)
    .eq('status', 'pending')
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(20)
  throwQueryError(error, 'Pending registration lookup')
  return (data ?? []).map((row) => ({
    id: row.id,
    status: row.status,
    created_at: row.created_at,
    expires_at: row.expires_at,
    proposal: sanitizePendingProposal(row.proposal),
  }))
}
