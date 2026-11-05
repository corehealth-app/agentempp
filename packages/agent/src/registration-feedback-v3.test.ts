import { buildDailyStateWithEnergy, type Protocol } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import type { FlowClinicalPolicy } from './flow-current-clinical.js'
import {
  parseRegistrationFeedbackV3,
  prepareRegistrationFeedbackV3,
  type RegistrationFeedbackV3Input,
  renderRegistrationFeedbackV3,
} from './registration-feedback-v3.js'

const ID = '10000000-0000-4000-8000-000000000001'
const LOG = '20000000-0000-4000-8000-000000000001'
function policy(): FlowClinicalPolicy {
  return {
    version: 1,
    observed_at: '2026-11-05T18:00:00Z',
    assessment: 'complete',
    recording_allowed: true,
    pause_weight_loss_guidance: false,
    professional_assessment_recommended: false,
    phase_selection_pending: false,
    target_source: 'official_only',
    hide: { objective: false, calories: false, protein: false, balance: false, block: false },
  }
}
function day(energy: number | null = null, protocol: Protocol = 'recomposicao') {
  return buildDailyStateWithEnergy({
    localDate: '2026-11-05',
    generatedAt: '2026-11-05T18:00:00Z',
    protocol,
    calculatedTargets: { calories_target: 2400, protein_target: 150 },
    programmedDeficitKcal: 500,
    snapshot: {
      caloriesConsumed: 1785,
      caloriesTarget: 2400,
      proteinG: 126,
      proteinTarget: 150,
      carbsG: 180,
      fatG: 45,
      // Private numeric storage is a known partial sum; it is never the public unknown value.
      exerciseCalories: energy === null ? 42 : energy,
      exerciseEnergyComplete: energy !== null,
      waterConsumedMl: 1000,
      protocol,
      dayClosed: false,
      dayStatus: null,
      updatedAt: '2026-11-05T18:00:00Z',
    },
    meals: [],
    workouts: [
      {
        id: LOG,
        workout_type: 'caminhada',
        duration_min: 30,
        estimated_kcal: energy,
        intensity: null,
        performed_at: '2026-11-05T17:00:00Z',
      },
    ],
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
    progress: { deficitBlock: 3120, blocksCompleted: 2, updatedAt: null },
  })
}
function input(
  energy: number | null = null,
  protocol: Protocol = 'recomposicao',
): RegistrationFeedbackV3Input & {
  policy: FlowClinicalPolicy
  officialDay: ReturnType<typeof day>
} {
  return {
    registrationId: ID,
    localDate: '2026-11-05',
    locale: 'pt-BR',
    policy: policy(),
    officialDay: day(energy, protocol),
    preferencesKnown: false,
    registration: {
      kind: 'workout' as const,
      log_id: LOG,
      workout_type: 'caminhada',
      duration_min: 30,
      intensity: null,
      estimated_kcal: energy,
    },
  }
}
const text = (f: ReturnType<typeof prepareRegistrationFeedbackV3>) =>
  renderRegistrationFeedbackV3(f)
    .map((s) => s.text)
    .join('\n')
const identity = { registrationId: ID, kind: 'workout' as const }

describe('closed feedback v3 independent field availability', () => {
  it('retains official food and protein with unknown exercise instead of dropping the day', () => {
    const i = input()
    expect(() => prepareRegistrationFeedbackV3(i)).not.toThrow()
    const f = prepareRegistrationFeedbackV3(i)
    expect(f).toMatchObject({
      schema: 'registration.feedback.v3',
      assistant: 'Flow AI',
      day: {
        consumed: { calories_kcal: 1785, protein_g: 126 },
        targets: { calories_kcal: 2400, protein_g: 150 },
        calorie_percentage: 74.4,
        protein_percentage: 84,
        remaining_food_kcal: 615,
        food_excess_kcal: 0,
        exercise_kcal: null,
        exercise_energy: { status: 'unavailable', reason: 'unknown_workout_energy' },
      },
      block: {
        status: 'available',
        current_kcal: 3120,
        completed_blocks: 2,
        total_credited_kcal: 18520,
      },
    })
    expect(i.officialDay.exercise_kcal).toBeNull()
    expect(f.day).not.toHaveProperty('daily_balance_kcal')
    expect(text(f)).toContain('615 kcal')
    expect(text(f)).toContain('Gasto de exercício indisponível')
    expect(text(f)).toContain('Gasto estimado indisponível')
    expect(text(f)).not.toMatch(/Gasto estimado: (0|400)/)
  })
  it.each([
    0, 42,
  ])('keeps proven known exercise %s distinct from unavailable and outside the food budget', (energy) => {
    const f = prepareRegistrationFeedbackV3(input(energy))
    expect(f.day).toMatchObject({
      exercise_kcal: energy,
      exercise_energy: { status: 'available' },
      remaining_food_kcal: 615,
    })
    expect(f.registration).toMatchObject({ estimated_kcal: energy })
    expect(f.block).toMatchObject({ current_kcal: 3120 })
  })
  it.each([
    'ganho_massa',
    'manutencao',
  ] as const)('keeps %s official targets and no invented activity block credit', (protocol) => {
    const f = prepareRegistrationFeedbackV3(input(null, protocol))
    expect(f.day).toMatchObject({
      current_protocol: protocol,
      targets: { calories_kcal: 2400 },
      exercise_kcal: null,
      remaining_food_kcal: 615,
    })
    expect(f.block).toEqual({ status: 'not_applicable' })
  })
  it('preserves factual intake while a clinical pause independently protects targets, objective and block', () => {
    const i = input()
    i.policy.pause_weight_loss_guidance = true
    i.policy.hide = { objective: true, calories: true, protein: true, balance: true, block: true }
    const f = prepareRegistrationFeedbackV3(i)
    expect(f).toMatchObject({
      guidance: 'paused',
      day: {
        consumed: { calories_kcal: 1785, protein_g: 126 },
        current_protocol: null,
        targets: { calories_kcal: null, protein_g: null },
        calorie_percentage: null,
        protein_percentage: null,
        remaining_food_kcal: null,
        food_excess_kcal: null,
        exercise_kcal: null,
      },
      block: { status: 'protected' },
      education: {
        provenance: { template_id: 'clinical_pause', catalog_version: 'registration.education.v1' },
      },
    })
    expect(text(f)).not.toMatch(/2[.,]400|150 g|615 kcal/)
  })
  it('does not erase proved intake when assessment is incomplete or invent a fallback target', () => {
    const i = input()
    i.policy.assessment = 'incomplete'
    i.policy.hide = { objective: true, calories: true, protein: true, balance: true, block: true }
    const f = prepareRegistrationFeedbackV3(i)
    expect(f).toMatchObject({
      guidance: 'unavailable',
      day: {
        consumed: { calories_kcal: 1785, protein_g: 126 },
        targets: { calories_kcal: null, protein_g: null },
        current_protocol: null,
      },
      block: { status: 'protected' },
    })
  })
  it('withholds only the hidden protein target while retaining the official calorie target and food budget', () => {
    const i = input()
    i.policy.hide.protein = true
    const f = prepareRegistrationFeedbackV3(i)
    expect(f.day).toMatchObject({
      targets: { calories_kcal: 2400, protein_g: null },
      calorie_percentage: 74.4,
      protein_percentage: null,
      remaining_food_kcal: 615,
      exercise_kcal: null,
    })
  })
  it('renders six ordered sections and pinned activity education in both locales', () => {
    for (const locale of ['pt-BR', 'en']) {
      const i = input()
      i.locale = locale
      const f = prepareRegistrationFeedbackV3(i)
      expect(renderRegistrationFeedbackV3(f).map((s) => s.key)).toEqual([
        'saved',
        'items',
        'summary',
        'day',
        'block',
        'education',
      ])
      expect(f.education).toMatchObject({
        status: 'available',
        provenance: {
          source: 'reviewed_template',
          catalog_version: 'registration.education.v1',
          template_id: 'activity_walking',
        },
      })
      expect(text(f)).toContain(
        locale === 'en' ? 'Exercise expenditure unavailable' : 'Gasto de exercício indisponível',
      )
      expect(text(f)).toContain(locale === 'en' ? 'already consolidated' : 'já consolidado')
    }
  })
  it.each([
    (f: Record<string, unknown>) => {
      ;(f.day as Record<string, unknown>).exercise_kcal = 0
    },
    (f: Record<string, unknown>) => {
      ;(f.day as Record<string, unknown>).exercise_energy = { status: 'available' }
    },
    (f: Record<string, unknown>) => {
      delete (f.day as Record<string, unknown>).exercise_energy
    },
    (f: Record<string, unknown>) => {
      ;((f.day as Record<string, unknown>).exercise_energy as Record<string, unknown>).reason =
        'estimated_zero'
    },
    (f: Record<string, unknown>) => {
      ;(f.day as Record<string, unknown>).remaining_food_kcal = 1119
    },
    (f: Record<string, unknown>) => {
      f.schema = 'registration.feedback.v2'
    },
    (f: Record<string, unknown>) => {
      f.private_context = {}
    },
    (f: Record<string, unknown>) => {
      ;(f.education as Record<string, unknown>).text = 'Perda de peso garantida'
    },
  ])('rejects contradictory availability, fabricated budgets, old schema and arbitrary text', (mutate) => {
    const f = structuredClone(prepareRegistrationFeedbackV3(input()))
    mutate(f as unknown as Record<string, unknown>)
    expect(() => parseRegistrationFeedbackV3(f, identity)).toThrow()
  })
})

it('rejects a same-day unknown workout paired with an available day exercise total', () => {
  const f = prepareRegistrationFeedbackV3(input(0))
  if (f.registration.kind !== 'workout') throw new Error('Expected workout fixture')
  f.registration.estimated_kcal = null
  expect(() => parseRegistrationFeedbackV3(f, identity)).toThrow()
})
it('retains a known individual workout while the full day contains another unknown activity', () => {
  const i = input()
  if (i.registration.kind !== 'workout') throw new Error('Expected workout fixture')
  i.registration.estimated_kcal = 42
  const f = prepareRegistrationFeedbackV3(i)
  expect(f.registration).toMatchObject({ estimated_kcal: 42 })
  expect(f.day).toMatchObject({ exercise_kcal: null, remaining_food_kcal: 615 })
})
it('preserves per-food facts, canonical decimal total and quantity references on an unknown-energy day', () => {
  const i = input()
  i.registration = {
    kind: 'meal',
    meal_kind: 'cafe',
    items: [
      {
        log_id: LOG,
        food_name: 'leite integral',
        quantity_g: 206,
        quantity: {
          value: 200,
          unit: 'mL',
          estimated: true,
          reference_id: 'fao-infoods-v2-whole-milk-tb',
        },
        kcal: 126,
        protein_g: 6.3,
        carbs_g: 9.5,
        fat_g: 6.5,
        nutrition_source: 'canonical_exact',
      },
    ],
    totals: { kcal: 126.004, protein_g: 6.304, carbs_g: 9.504, fat_g: 6.504 },
  }
  const f = prepareRegistrationFeedbackV3(i)
  expect(f.registration).toEqual(i.registration)
  expect(text(f)).toContain('leite integral · 200 mL')
  expect(f.day).toMatchObject({
    exercise_kcal: null,
    consumed: { calories_kcal: 1785, protein_g: 126 },
  })
})
