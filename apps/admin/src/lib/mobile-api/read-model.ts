import { DailyStateLoadError, loadOfficialDailyState } from '@mpp/agent'
import type { Json, ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import type { HistoryQuery } from './contracts'
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

function safePendingItem(value: Json): Record<string, string | number | null> | null {
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

export async function loadProfile(supabase: ServiceClient, userId: string) {
  const { data, error } = await supabase
    .from('user_profiles')
    .select(
      'sex, birth_date, height_cm, weight_kg, body_fat_percent, activity_level, training_frequency, water_intake, hunger_level, wake_time, bedtime, current_protocol, goal_type, goal_value, deficit_level, food_organization, onboarding_completed, onboarding_step, updated_at',
    )
    .eq('user_id', userId)
    .maybeSingle()
  throwQueryError(error, 'Profile lookup')
  return data
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
  const { data, error } = await supabase
    .from('user_progress')
    .select(
      'xp_total, level, current_streak, longest_streak, blocks_completed, deficit_block, current_weight, current_bf_percent, badges_earned, last_active_date, next_reevaluation, updated_at',
    )
    .eq('user_id', userId)
    .maybeSingle()
  throwQueryError(error, 'Progress lookup')
  return data
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
