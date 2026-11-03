import { buildDailyState } from '@mpp/core'
import type { MobileAuthContext } from '../auth'

export const owner = '10000000-0000-4000-8000-000000000001'
export const other = '10000000-0000-4000-8000-000000000002'
export const registrationId = '20000000-0000-4000-8000-000000000001'
export const logId = '30000000-0000-4000-8000-000000000001'
export const snapshotId = '40000000-0000-4000-8000-000000000001'
export const instant = '2026-11-03T12:00:00.000001Z'
export const auth: MobileAuthContext = {
  userId: owner,
  authUserId: other,
  accessToken: 'synthetic-test-token',
  identity: { id: other, email: null, emailConfirmedAt: instant },
  patient: {
    id: owner,
    authUserId: other,
    email: null,
    name: 'Synthetic QA',
    locale: 'pt-BR',
    timezone: 'UTC',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}
export function clinical() {
  return {
    version: 1,
    user_id: owner,
    mode: 'profile',
    profile_present: true,
    epoch: '50000000-0000-4000-8000-000000000001',
    signup_generation: '50000000-0000-4000-8000-000000000002',
    generation_token: {
      onboarding_completed: true,
      onboarding_completed_at: '2026-11-02T12:00:00.000001Z',
      receipt_count: 1,
    },
    first_completion: false,
    observed_at: instant,
    date: '2026-11-03',
    timezone: 'UTC',
    body: {
      locale: 'pt-BR',
      timezone: 'UTC',
      sex: 'masculino',
      birth_date: '1990-01-01',
      height_cm: 180,
      weight_kg: 80,
      body_fat_percent: 24,
      training_frequency: 4,
    },
    assessment: 'complete',
    missing: [],
    health_state: {
      version: 1,
      user_id: owner,
      safety_revision: '0',
      hold_active: false,
      declared_no_plan: false,
      hide_protein: false,
      last_declared_at: null,
      items: [],
    },
    safety: {
      version: 1,
      no_plan: false,
      hold_active: false,
      loss_guard: false,
      hide_protein: false,
      recording_allowed: true,
      date: '2026-11-03',
      timezone: 'UTC',
      observed_at: instant,
    },
    phase_origin: { kind: 'assigned', phase: 'recomposicao' },
    calculation_config: [{ key: 'calc.training_min', value: 4, updated_at: instant }],
    profile_hash: 'a'.repeat(64),
    context_hash: 'b'.repeat(64),
  }
}
export function context() {
  return {
    version: 1,
    user_id: owner,
    registration_id: registrationId,
    confirmed: {
      id: registrationId,
      user_id: owner,
      status: 'confirmed',
      proposal: {
        kind: 'meal',
        mealType: 'cafe',
        registration_origin: 'mobile_app',
        source_provider_message_id: 'synthetic-v2-source',
        source_timestamp: '2026-11-03T11:00:00Z',
        source_timezone: 'UTC',
        source_local_date: '2026-11-03',
        items: [
          {
            name: 'leite integral',
            quantity_g: 206,
            quantity_basis: 'portion_reference',
            nutrition_source: 'product_label',
            kcal: 126.12,
            protein_g: 6.3,
            carbs_g: 9.5,
            fat_g: 6.5,
          },
        ],
        totals: { kcal: 126.1, protein_g: 6.3, carbs_g: 9.5, fat_g: 6.5 },
      },
    },
    logs: [
      {
        id: logId,
        user_id: owner,
        snapshot_id: snapshotId,
        raw_provider_message_id: 'synthetic-v2-source',
        consumed_at: '2026-11-03T11:00:00Z',
        meal_type: 'cafe',
        food_name: 'leite integral',
        quantity_g: 206,
        kcal: 126.12,
        protein_g: 6.3,
        carbs_g: 9.5,
        fat_g: 6.5,
        source: 'product_label',
      },
    ],
    workout_proof: null,
    snapshot: {
      id: snapshotId,
      user_id: owner,
      date: '2026-11-03',
      calories_consumed: 126,
      protein_g: 6.3,
      carbs_g: 9.5,
      fat_g: 6.5,
      calories_target: 1900,
      protein_target: 120,
      exercise_calories: 504,
    },
    progress: { user_id: owner, deficit_block: 500, blocks_completed: 2 },
    clinical: clinical(),
  }
}
export function day() {
  return buildDailyState({
    localDate: '2026-11-03',
    generatedAt: instant,
    protocol: 'recomposicao',
    calculatedTargets: { calories_target: 9999, protein_target: 999 },
    programmedDeficitKcal: 500,
    snapshot: {
      caloriesConsumed: 126,
      caloriesTarget: 1900,
      proteinG: 6.3,
      proteinTarget: 120,
      carbsG: 9.5,
      fatG: 6.5,
      exerciseCalories: 504,
      waterConsumedMl: 0,
      protocol: 'recomposicao',
      dayClosed: false,
      dayStatus: null,
      updatedAt: instant,
    },
    meals: context().logs,
    workouts: [],
    pendingRegistrations: [],
    hydrationTarget: null,
    routineItems: [],
    mealGap: {
      expected: [],
      registered: [],
      skipped: [],
      open: [],
      reliable: false,
      activeDays: 0,
    },
    progress: { blocksCompleted: 2, deficitBlock: 500, updatedAt: instant },
  })
}
export function legacyFeedback() {
  return {
    schema: 'registration.feedback.v1',
    registration_id: registrationId,
    kind: 'meal',
    locale: 'en',
    meal_totals: { kcal: 126.1, protein_g: 6.3, carbs_g: 9.5, fat_g: 6.5 },
    day: null,
    lines: [
      { key: 'meal_totals', text: 'Synthetic total' },
      { key: 'day_unavailable', text: 'Unavailable' },
    ],
    food_comment: null,
    incentive: null,
  }
}

export function fixtureFirst<T>(values: readonly T[]): T {
  const value = values[0]
  if (value === undefined) throw new Error('Fixture row missing')
  return value
}
