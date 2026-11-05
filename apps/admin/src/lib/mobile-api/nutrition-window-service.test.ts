import { writeFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import {
  nutritionWindowDates,
  projectNutritionWindow,
  readNutritionWindow,
} from './nutrition-window-service'

const OWNER = 'a1111111-1111-4111-8111-111111111111',
  AUTH = 'a2222222-2222-4222-8222-222222222222',
  EPOCH = 'a3333333-3333-4333-8333-333333333333'
const ID = 'a4444444-4444-4444-8444-444444444444'
const policy = {
  version: 1 as const,
  observed_at: '2026-11-04T15:00:00.000000Z',
  assessment: 'complete' as const,
  recording_allowed: true,
  pause_weight_loss_guidance: false,
  professional_assessment_recommended: false,
  phase_selection_pending: false,
  target_source: 'official_only' as const,
  hide: {
    objective: false,
    calories: false,
    protein: false,
    balance: false,
    block: false,
    budget: false,
  },
}
const scope = () => ({
  authUserID: AUTH,
  ownerID: OWNER,
  epoch: EPOCH,
  timezone: 'America/Sao_Paulo',
  currentLocalDate: '2026-11-04',
  observedAt: policy.observed_at,
  binding: 'current-owned-clinical-binding',
  policy: structuredClone(policy),
})
const empty = () => ({
  meals: [] as Record<string, unknown>[],
  snapshots: [] as Record<string, unknown>[],
  prescriptions: [] as Record<string, unknown>[],
  counts: { meals: 0, snapshots: 0, prescriptions: 0 },
})
const meal = (id = ID, provider = 'conversation.clarification/owned/original') => ({
  id,
  user_id: OWNER,
  snapshot_id: 'a5555555-5555-4555-8555-555555555555',
  meal_type: 'almoco',
  food_name: 'Arroz branco cozido',
  quantity_g: 150,
  kcal: 192.45,
  protein_g: 3.78,
  carbs_g: 42.09,
  fat_g: 0.345,
  consumed_at: '2026-11-04T15:00:00.000000Z',
  raw_provider_message_id: provider,
  source: 'canonical_fuzzy',
})
const day = () => ({
  id: 'a5555555-5555-4555-8555-555555555555',
  user_id: OWNER,
  date: '2026-11-04',
  calories_consumed: 192,
  protein_g: 3.78,
  carbs_g: 42.09,
  fat_g: 0.345,
  calories_target: null,
  protein_target: null,
  current_protocol: null,
  day_closed: false,
  updated_at: '2026-11-04T15:00:00.000000Z',
})
const prescription = (payload: unknown) => ({
  id: 'a6666666-6666-4666-8666-666666666666',
  user_id: OWNER,
  type: 'diet',
  payload,
  generated_at: '2026-11-02T03:00:00.000000Z',
  valid_until: '2026-11-09T03:00:00.000000Z',
  version: 1,
  notes: null,
})
const plannedMeal = (weekday?: number) => ({
  meal_type: 'almoco',
  ...(weekday ? { day_of_week: weekday } : {}),
  items: [
    {
      food_name: 'Feijão cozido',
      quantity_g: 100,
      kcal: 76,
      protein_g: 4.8,
      carbs_g: 13.6,
      fat_g: 0.5,
    },
  ],
  total_kcal: 76,
  total_protein_g: 4.8,
})
const auth = { userId: OWNER, authUserId: AUTH }

describe('Complete owned nutrition window: planned is never consumed', () => {
  it('uses official civil Monday–Sunday across DST, refusing impossible dates', () => {
    const dates = nutritionWindowDates('America/New_York', '2026-11-01')
    expect(dates.dates).toEqual([
      '2026-10-26',
      '2026-10-27',
      '2026-10-28',
      '2026-10-29',
      '2026-10-30',
      '2026-10-31',
      '2026-11-01',
    ])
    expect(dates.startUTC).toBe('2026-10-26T04:00:00.000Z')
    expect(dates.endUTC).toBe('2026-11-02T05:00:00.000Z')
    expect(() => nutritionWindowDates('America/New_York', '2026-02-30')).toThrow()
  })
  it('proves empty consumed days independently of null targets and missing day snapshots', () => {
    const value = projectNutritionWindow(scope(), undefined, empty())
    expect(value.completeness).toBe('complete')
    expect(value.days).toHaveLength(7)
    expect(
      value.days.every(
        (d) =>
          d.meals.length === 0 &&
          d.totals.source === 'empty_confirmed_set' &&
          d.totals.kcal === 0 &&
          d.targets.calories_kcal === null,
      ),
    ).toBe(true)
  })
  it('keeps real changed facts and official stored totals, preserving equal legitimate registrations', () => {
    const raw = empty()
    raw.meals = [
      meal(),
      meal('a7777777-7777-4777-8777-777777777777', 'conversation/another-real-command'),
    ]
    raw.snapshots = [
      { ...day(), calories_consumed: 385, protein_g: 7.56, carbs_g: 84.18, fat_g: 0.69 },
    ]
    raw.counts = { meals: 2, snapshots: 1, prescriptions: 0 }
    const actual = projectNutritionWindow(scope(), undefined, raw).days[2]
    expect(actual.meals.map((m) => m.quantity_g)).toEqual([150, 150])
    expect(new Set(actual.meals.map((m) => m.registration_key)).size).toBe(2)
    expect(actual.totals).toMatchObject({ source: 'daily_snapshot', kcal: 385, protein_g: 7.56 })
    expect(actual.targets.calories_kcal).toBeNull()
    if (process.env.NUTRITION_WINDOW_FIXTURE_OUTPUT) {
      raw.prescriptions = [prescription({ horizon: 'weekly', daily_meals: [plannedMeal(3)] })]
      raw.counts.prescriptions = 1
      writeFileSync(
        process.env.NUTRITION_WINDOW_FIXTURE_OUTPUT,
        `${JSON.stringify(
          {
            provenance:
              'Controlled synthetic projection of actual nutrition-window service; not a live HTTP/SQL/provider capture',
            window: projectNutritionWindow(scope(), undefined, raw),
          },
          null,
          2,
        )}\n`,
      )
    }
  })
  it('groups foods only by the actual provider identity and keeps provider-less records distinct', () => {
    const raw = empty()
    raw.meals = [
      meal(),
      { ...meal('a7777777-7777-4777-8777-777777777777'), food_name: 'Feijão' },
      { ...meal('a8888888-8888-4888-8888-888888888888'), raw_provider_message_id: null },
      { ...meal('a9999999-9999-4999-8999-999999999999'), raw_provider_message_id: null },
    ]
    raw.counts.meals = 4
    const rows = projectNutritionWindow(scope(), undefined, raw).days[2].meals
    expect(rows).toHaveLength(4)
    expect(rows[0].registration_key).toBe(rows[1].registration_key)
    expect(rows[2].registration_key).not.toBe(rows[3].registration_key)
  })
  it('projects proven current literal milk/whey units and approximate saved ratios without name conversion', () => {
    const raw = empty()
    const milk = { ...meal(), food_name: 'leite', quantity_g: 206 }
    const whey = {
      ...meal('a7777777-7777-4777-8777-777777777777', 'another-provider'),
      food_name: 'whey',
      quantity_g: 30,
    }
    raw.meals = [milk, whey]
    raw.counts.meals = 2
    const proof = (row: typeof milk, value: number, unit: string) => ({
      meal: row,
      binding: {
        command_id: 'ad111111-1111-4111-8111-111111111111',
        revision: 0,
        group_version: 'a'.repeat(64),
      },
      display_quantity: {
        value,
        unit,
        estimated: false,
        provenance: 'sealed_original',
        reference: {
          original_log_id: row.id,
          value,
          unit,
          quantity_g: row.quantity_g,
          quantity_basis: 'portion_reference',
        },
      },
    })
    const capture = { ...raw, units: [proof(milk, 200, 'mL'), proof(whey, 1, 'scoop')] }
    const first = projectNutritionWindow(scope(), undefined, capture).days[2]
    expect(first.meals[0].display_quantity).toMatchObject({
      value: 200,
      unit: 'mL',
      estimated: false,
    })
    expect(first.meals[1].display_quantity).toMatchObject({
      value: 1,
      unit: 'scoop',
      estimated: false,
    })
    const corrected = structuredClone(capture)
    const correctedMeal = { ...whey, id: 'a8888888-8888-4888-8888-888888888888', quantity_g: 40 }
    corrected.meals[1] = correctedMeal
    corrected.units[1] = {
      ...corrected.units[1],
      meal: correctedMeal,
      binding: { ...corrected.units[1].binding, revision: 1 },
      display_quantity: {
        ...corrected.units[1].display_quantity,
        value: 1.333333,
        estimated: true,
        provenance: 'audited_same_food_scale',
      },
    }
    expect(
      projectNutritionWindow(scope(), undefined, corrected).days[2].meals[1].display_quantity,
    ).toMatchObject({ value: 1.333333, estimated: true, reference: { quantity_g: 30 } })
    expect(
      projectNutritionWindow(scope(), undefined, raw).days[2].meals[0].display_quantity,
    ).toBeNull()
  })
  it.each([
    'owner',
    'row',
    'duplicate',
    'binding',
  ] as const)('refuses %s display metadata detached from the current owned meal', (attack) => {
    const row = meal(),
      raw = {
        ...empty(),
        meals: [row],
        counts: { meals: 1, snapshots: 0, prescriptions: 0 },
        units: [
          {
            meal: { ...row },
            binding: {
              command_id: 'ad111111-1111-4111-8111-111111111111',
              revision: 0,
              group_version: 'a'.repeat(64),
            },
            display_quantity: {
              value: 200,
              unit: 'mL',
              estimated: false,
              provenance: 'sealed_original',
              reference: {
                original_log_id: row.id,
                value: 200,
                unit: 'mL',
                quantity_g: row.quantity_g,
                quantity_basis: 'portion_reference',
              },
            },
          },
        ],
      }
    if (attack === 'owner') raw.units[0].meal.user_id = AUTH
    if (attack === 'row') raw.units[0].meal.quantity_g = 201
    if (attack === 'duplicate') raw.units.push(raw.units[0])
    if (attack === 'binding') raw.units[0].binding.group_version = 'invalid'
    expect(() => projectNutritionWindow(scope(), undefined, raw)).toThrow()
  })
  it('does not turn missing totals or nutrients into zero', () => {
    const raw = empty()
    raw.meals = [{ ...meal(), snapshot_id: null, kcal: null }]
    raw.counts.meals = 1
    const actual = projectNutritionWindow(scope(), undefined, raw).days[2]
    expect(actual.meals[0].kcal).toBeNull()
    expect(actual.totals).toMatchObject({ source: 'unavailable', kcal: null })
  })
  it('withholds stored totals if attached rows belong to another current-zone day', () => {
    const raw = empty()
    raw.meals = [{ ...meal(), consumed_at: '2026-11-05T04:00:00.000000Z' }]
    raw.snapshots = [day()]
    raw.counts = { meals: 1, snapshots: 1, prescriptions: 0 }
    const value = projectNutritionWindow(scope(), undefined, raw)
    expect(value.days[2].totals.source).toBe('unavailable')
    expect(value.days[3].meals).toHaveLength(1)
  })
  it('projects explicit weekdays separately from consumed records', () => {
    const raw = empty()
    raw.prescriptions = [
      prescription({ horizon: 'weekly', daily_meals: [plannedMeal(1), plannedMeal(3)] }),
    ]
    raw.counts.prescriptions = 1
    const value = projectNutritionWindow(scope(), undefined, raw)
    expect(value.days[0].planned.meals).toHaveLength(1)
    expect(value.days[1].planned.meals).toHaveLength(0)
    expect(value.days[2].planned.meals[0].items[0].food_name).toBe('Feijão cozido')
    expect(value.days.every((d) => d.meals.length === 0 && d.totals.kcal === 0)).toBe(true)
  })
  it('compares prescription validity by actual instants rather than offset spelling', () => {
    const raw = empty()
    raw.prescriptions = [
      {
        ...prescription({ horizon: 'daily', daily_meals: [plannedMeal()] }),
        generated_at: '2026-11-05T01:00:00-03:00',
      },
    ]
    raw.counts.prescriptions = 1
    expect(projectNutritionWindow(scope(), undefined, raw).days[2].planned.meals).toHaveLength(0)
  })
  it('retains known prescribed foods when optional imported macros are absent', () => {
    const raw = empty()
    raw.prescriptions = [
      prescription({
        horizon: 'daily',
        daily_meals: [{ meal_type: 'almoco', items: [{ food_name: 'Arroz', quantity_g: 150 }] }],
      }),
    ]
    raw.counts.prescriptions = 1
    const actual = projectNutritionWindow(scope(), undefined, raw).days[2].planned
    expect(actual.status).toBe('available')
    expect(actual.meals[0].items[0].kcal).toBeNull()
  })
  it('withholds inconsistent stored totals instead of publishing a stable but incorrect sum', () => {
    const raw = empty()
    raw.meals = [meal()]
    raw.snapshots = [{ ...day(), calories_consumed: 999 }]
    raw.counts = { meals: 1, snapshots: 1, prescriptions: 0 }
    expect(projectNutritionWindow(scope(), undefined, raw).days[2].totals).toMatchObject({
      source: 'unavailable',
      kcal: null,
    })
  })
  it.each([
    'quantity',
    'macro',
  ] as const)('refuses a stored plan with invalid actual-schema %s without inventing a replacement', (field) => {
    const raw = empty(),
      planned = plannedMeal()
    const item = {
      ...planned.items[0],
      ...(field === 'quantity' ? { quantity_g: null } : { protein_g: 301 }),
    }
    raw.prescriptions = [
      prescription({ horizon: 'daily', daily_meals: [{ ...planned, items: [item] }] }),
    ]
    raw.counts.prescriptions = 1
    const value = projectNutritionWindow(scope(), undefined, raw).days[2]
    expect(value.planned.status).toBe('unavailable')
    expect(value.planned.meals).toHaveLength(0)
    expect(value.meals).toHaveLength(0)
  })
  it('marks ambiguous plans unavailable and clinically withheld guidance protected', () => {
    const raw = empty()
    raw.prescriptions = [prescription({ daily_meals: [plannedMeal()] })]
    raw.counts.prescriptions = 1
    expect(projectNutritionWindow(scope(), undefined, raw).days[0].planned.status).toBe(
      'unavailable',
    )
    const held = scope()
    held.policy.hide.calories = true
    expect(projectNutritionWindow(held, undefined, raw).days[0].planned.status).toBe('protected')
  })
  it('refuses foreign rows or incomplete exact-count proof', () => {
    const raw = empty()
    raw.counts.meals = 1
    expect(() => projectNutritionWindow(scope(), undefined, raw)).toThrow()
    raw.meals = [{ ...meal(), user_id: AUTH }]
    expect(() => projectNutritionWindow(scope(), undefined, raw)).toThrow()
  })
  it.each([
    'meal',
    'day',
    'prescription',
  ] as const)('rejects a %s change across the captures while clinical epoch remains identical', async (layer) => {
    const first = empty()
    first.meals = [meal()]
    first.snapshots = [day()]
    first.counts = { meals: 1, snapshots: 1, prescriptions: 0 }
    const second = structuredClone(first)
    if (layer === 'meal') second.meals[0].quantity_g = 175
    if (layer === 'day') second.snapshots[0].updated_at = '2026-11-04T15:00:00.000001Z'
    if (layer === 'prescription') {
      second.prescriptions = [prescription({ horizon: 'daily', daily_meals: [plannedMeal()] })]
      second.counts.prescriptions = 1
    }
    let count = 0
    await expect(
      readNutritionWindow(auth, undefined, {
        observe: async () => scope(),
        capture: async () => (++count === 1 ? first : second),
      }),
    ).rejects.toMatchObject({ status: 409, code: 'nutrition_window_changed' })
    expect(count).toBe(2)
  })
  it('rejects owner/epoch/timezone/clinical changes after a complete read', async () => {
    for (const key of ['ownerID', 'epoch', 'timezone', 'binding'] as const) {
      let calls = 0
      await expect(
        readNutritionWindow(auth, undefined, {
          observe: async () => {
            const s = scope()
            if (++calls > 1) s[key] = 'changed'
            return s
          },
          capture: async () => empty(),
        }),
      ).rejects.toThrow()
    }
  })
})
