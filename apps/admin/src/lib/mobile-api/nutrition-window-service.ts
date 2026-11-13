/** Read-only nutrition window. Shape validation is not authority: production
 * composition obtains the scope from actual existing-account clinical reads. */

import { createHash } from 'node:crypto'
import { getLocalDateString, getLocalDayUtcBounds } from '@mpp/agent'
import { z } from 'zod'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { MobileApiError } from './http'
import { hashMobileRequest } from './idempotency'
import {
  clinicalWindowDates as nutritionWindowDates,
  type OwnedClinicalWindowScope,
  parseOwnedClinicalWindowScope,
} from './owned-clinical-window'

export { clinicalWindowDates as nutritionWindowDates } from './owned-clinical-window'

const uuid = z.string().uuid()
const clock = z.string().datetime({ offset: true })
const amount = z.number().finite().nonnegative().max(Number.MAX_SAFE_INTEGER).nullable()
const civil = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine((v) => {
    const d = new Date(`${v}T00:00:00Z`)
    return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === v
  })
export type NutritionWindowScope = OwnedClinicalWindowScope
export interface NutritionWindowDependencies {
  observe(): Promise<NutritionWindowScope>
  capture(window: ReturnType<typeof nutritionWindowDates>): Promise<unknown>
}
const mealSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    snapshot_id: uuid.nullable(),
    meal_type: z.string().nullable(),
    food_name: z.string().min(1).max(240),
    quantity_g: amount,
    kcal: amount,
    protein_g: amount,
    carbs_g: amount,
    fat_g: amount,
    consumed_at: clock,
    raw_provider_message_id: z.string().min(1).max(1000).nullable(),
    source: z.string().nullable(),
  })
  .strict()
const displayQuantity = z
  .object({
    value: z.number().finite().positive().max(999999),
    unit: z
      .string()
      .min(1)
      .max(40)
      .refine((v) => v === v.trim()),
    estimated: z.boolean(),
    provenance: z.enum(['sealed_original', 'audited_restore', 'audited_same_food_scale']),
    reference: z
      .object({
        original_log_id: uuid,
        value: z.number().finite().positive().max(999999),
        unit: z
          .string()
          .min(1)
          .max(40)
          .refine((v) => v === v.trim()),
        quantity_g: z.number().finite().positive().max(9999),
        quantity_basis: z.enum(['stated', 'portion_reference', 'visual_estimate']),
      })
      .strict(),
  })
  .strict()
  .refine(
    (d) =>
      d.unit === d.reference.unit &&
      (d.provenance !== 'audited_same_food_scale' || d.estimated) &&
      (d.reference.quantity_basis !== 'visual_estimate' || d.estimated),
    'Invalid display reference',
  )
const unitProof = z
  .object({
    meal: mealSchema,
    binding: z
      .object({
        command_id: uuid,
        revision: z.number().int().min(0).max(2147483647),
        group_version: z.string().regex(/^[0-9a-f]{64}$/),
      })
      .strict()
      .nullable(),
    display_quantity: displayQuantity.nullable(),
  })
  .strict()
function sameUnitMeal(a: z.infer<typeof mealSchema>, b: z.infer<typeof mealSchema>) {
  return (
    hashMobileRequest({
      ...a,
      consumed_at: conversationJournalInstant(a.consumed_at).toString(),
    }) ===
    hashMobileRequest({ ...b, consumed_at: conversationJournalInstant(b.consumed_at).toString() })
  )
}
function proveUnits(
  units: z.infer<typeof unitProof>[],
  meals: z.infer<typeof mealSchema>[],
  owner: string,
) {
  if (new Set(units.map((u) => u.meal.id)).size !== units.length) return invalid()
  for (const unit of units) {
    const row = meals.find((m) => m.id === unit.meal.id)
    if (
      !row ||
      unit.meal.user_id !== owner ||
      !sameUnitMeal(row, unit.meal) ||
      (unit.display_quantity !== null && unit.binding === null)
    )
      return invalid()
    const display = unit.display_quantity
    if (
      display &&
      display.provenance !== 'audited_same_food_scale' &&
      (display.value !== display.reference.value || row.quantity_g !== display.reference.quantity_g)
    )
      return invalid()
  }
  return units
}
/** Only the actual service-only RPC produces this observation. It grants no writes. */
export function readNutritionUnitsResult(raw: unknown, rawMeals: unknown, owner: string) {
  const value = z
    .object({
      schema: z.literal('nutrition.window-units.v1'),
      owner_id: uuid,
      items: z.array(unitProof).max(1000),
    })
    .strict()
    .safeParse(raw)
  const meals = z.array(mealSchema).max(1000).safeParse(rawMeals)
  if (
    !value.success ||
    !meals.success ||
    value.data.owner_id !== owner ||
    value.data.items.length !== meals.data.length
  )
    return invalid()
  return proveUnits(value.data.items, meals.data, owner)
}
const daySchema = z
  .object({
    id: uuid,
    user_id: uuid,
    date: civil,
    calories_consumed: amount,
    calories_target: amount,
    protein_g: amount,
    protein_target: amount,
    carbs_g: amount,
    fat_g: amount,
    current_protocol: z.string().nullable(),
    day_closed: z.boolean(),
    updated_at: clock,
  })
  .strict()
const prescriptionSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    type: z.enum(['diet', 'combined']),
    payload: z.unknown(),
    generated_at: clock,
    valid_until: clock.nullable(),
    version: z.number().int().nonnegative().nullable(),
    notes: z.string().nullable(),
  })
  .strict()
const captureSchema = z
  .object({
    meals: z.array(mealSchema).max(1000),
    units: z.array(unitProof).max(1000).default([]),
    snapshots: z.array(daySchema).max(7),
    prescriptions: z.array(prescriptionSchema).max(20),
    counts: z
      .object({
        meals: z.number().int().nonnegative(),
        snapshots: z.number().int().nonnegative(),
        prescriptions: z.number().int().nonnegative(),
      })
      .strict(),
  })
  .strict()
type Capture = z.infer<typeof captureSchema>
const planMacro = (maximum: number) =>
  z.number().finite().min(0).max(maximum).nullable().default(null)
const plannedItem = z
  .object({
    food_name: z.string().min(1).max(120),
    quantity_g: z.number().finite().min(0).max(2000),
    kcal: planMacro(3000),
    protein_g: planMacro(300),
    carbs_g: planMacro(500),
    fat_g: planMacro(300),
    display_qty: z.number().finite().positive().max(10000).optional(),
    display_unit: z.string().min(1).max(20).optional(),
  })
  .strict()
const plannedMeal = z
  .object({
    meal_type: z.enum(['cafe', 'lanche_manha', 'almoco', 'lanche_tarde', 'jantar', 'ceia']),
    day_of_week: z.number().int().min(1).max(7).optional(),
    time_suggestion: z.string().min(1).max(40).optional(),
    items: z.array(plannedItem).min(1).max(12),
    total_kcal: planMacro(3000),
    total_protein_g: planMacro(300),
    notes: z.string().min(1).max(300).optional(),
  })
  .strict()
// Full stored diet payload has other metadata/shopping lists. Only known meal
// fields are projected; an unproved horizon/schedule never acquires a day.
const planSchema = z.object({
  horizon: z.enum(['daily', 'weekly']),
  daily_meals: z.array(plannedMeal).min(1).max(42),
})
function changed(): never {
  throw new MobileApiError(
    409,
    'nutrition_window_changed',
    'Nutrition changed during this read; refresh the window',
  )
}
function invalid(): never {
  throw new MobileApiError(
    503,
    'nutrition_window_unavailable',
    'A complete nutrition window is unavailable',
  )
}

function capture(raw: unknown, owner: string): Capture {
  const parsed = captureSchema.safeParse(raw)
  if (!parsed.success) return invalid()
  const value = parsed.data
  for (const key of ['meals', 'snapshots', 'prescriptions'] as const) {
    if (
      value.counts[key] !== value[key].length ||
      new Set(value[key].map((v) => v.id)).size !== value[key].length ||
      value[key].some((v) => v.user_id !== owner)
    )
      return invalid()
  }
  if (new Set(value.snapshots.map((d) => d.date)).size !== value.snapshots.length) return invalid()
  proveUnits(value.units, value.meals, owner)
  return value
}
function version(value: Capture) {
  return hashMobileRequest({
    meals: [...value.meals].sort((a, b) => a.id.localeCompare(b.id)),
    units: [...value.units].sort((a, b) => a.meal.id.localeCompare(b.meal.id)),
    snapshots: [...value.snapshots].sort((a, b) => a.id.localeCompare(b.id)),
    prescriptions: [...value.prescriptions].sort((a, b) => a.id.localeCompare(b.id)),
    counts: value.counts,
  })
}
function plansFor(
  date: string,
  scope: NutritionWindowScope,
  prescriptions: Capture['prescriptions'],
) {
  const hidden =
    scope.policy.pause_weight_loss_guidance ||
    scope.policy.hide.objective ||
    scope.policy.hide.calories ||
    scope.policy.hide.protein
  if (hidden)
    return { status: 'protected' as const, meals: [], unavailable_prescription_ids: [] as string[] }
  const bounds = getLocalDayUtcBounds(scope.timezone, date)
  const applicable = prescriptions.filter(
    (p) =>
      Date.parse(p.generated_at) < Date.parse(bounds.endExclusiveIso) &&
      (p.valid_until === null || Date.parse(p.valid_until) > Date.parse(bounds.startIso)),
  )
  const unavailable: string[] = []
  const meals: Array<
    z.infer<typeof plannedMeal> & {
      id: string
      prescription_id: string
      generated_at: string
      valid_until: string | null
    }
  > = []
  const weekday = ((new Date(`${date}T00:00:00Z`).getUTCDay() + 6) % 7) + 1
  for (const p of applicable) {
    const result = planSchema.safeParse(p.payload)
    if (
      !result.success ||
      result.data.daily_meals.some((m) =>
        result.data.horizon === 'weekly'
          ? m.day_of_week === undefined
          : m.day_of_week !== undefined,
      )
    ) {
      unavailable.push(p.id)
      continue
    }
    for (const [index, m] of result.data.daily_meals.entries()) {
      if (result.data.horizon === 'weekly' && m.day_of_week !== weekday) continue
      meals.push({
        ...m,
        id: `${p.id}/${index}`,
        prescription_id: p.id,
        generated_at: p.generated_at,
        valid_until: p.valid_until,
      })
    }
  }
  return {
    status: unavailable.length
      ? meals.length
        ? ('partial' as const)
        : ('unavailable' as const)
      : applicable.length
        ? ('available' as const)
        : ('none' as const),
    meals,
    unavailable_prescription_ids: unavailable,
  }
}
export function projectNutritionWindow(
  rawScope: NutritionWindowScope,
  selectedDate: string | undefined,
  raw: unknown,
) {
  const scope = parseOwnedClinicalWindowScope(rawScope),
    window = nutritionWindowDates(scope.timezone, selectedDate ?? scope.currentLocalDate),
    value = capture(raw, scope.ownerID)
  if (value.snapshots.some((d) => !window.dates.includes(d.date))) return invalid()
  const localDate = (m: Capture['meals'][number]) =>
    getLocalDateString(scope.timezone, new Date(m.consumed_at))
  const days = window.dates.map((date) => {
    const rows = value.meals.filter((m) => localDate(m) === date)
    const stored = value.snapshots.find((d) => d.date === date)
    const calendarCoherent =
      stored !== undefined &&
      rows.every((m) => m.snapshot_id === stored.id) &&
      value.meals.filter((m) => m.snapshot_id === stored.id).every((m) => localDate(m) === date)
    const agrees = (
      key: 'kcal' | 'protein_g' | 'carbs_g' | 'fat_g',
      storedAmount: number | null,
    ) => {
      if (storedAmount === null || rows.some((m) => m[key] === null)) return false
      const sum = rows.reduce((total, m) => total + (m[key] ?? 0), 0)
      const expected = key === 'kcal' ? Math.round(sum) : sum
      return Number.isFinite(expected) && Math.abs(expected - storedAmount) <= 0.000001
    }
    const coherent =
      calendarCoherent &&
      agrees('kcal', stored.calories_consumed) &&
      agrees('protein_g', stored.protein_g) &&
      agrees('carbs_g', stored.carbs_g) &&
      agrees('fat_g', stored.fat_g)
    const source = coherent
      ? ('daily_snapshot' as const)
      : !stored && rows.length === 0
        ? ('empty_confirmed_set' as const)
        : ('unavailable' as const)
    const empty = source === 'empty_confirmed_set'
    return {
      local_date: date,
      day_closed: stored?.day_closed ?? null,
      day_version: stored?.updated_at ?? null,
      meals: projectNutritionMealFacts(
        rows,
        value.units.filter((u) => rows.some((m) => m.id === u.meal.id)),
        scope.ownerID,
      ),
      totals: {
        source,
        kcal: coherent ? stored.calories_consumed : empty ? 0 : null,
        protein_g: coherent ? stored.protein_g : empty ? 0 : null,
        carbs_g: coherent ? stored.carbs_g : empty ? 0 : null,
        fat_g: coherent ? stored.fat_g : empty ? 0 : null,
      },
      targets: {
        source: coherent ? ('daily_snapshot' as const) : ('unavailable' as const),
        calories_kcal: coherent && !scope.policy.hide.calories ? stored.calories_target : null,
        protein_g: coherent && !scope.policy.hide.protein ? stored.protein_target : null,
      },
      planned: plansFor(date, scope, value.prescriptions),
    }
  })
  const result = {
    schema: 'nutrition.window.v1' as const,
    auth_user_id: scope.authUserID,
    owner_id: scope.ownerID,
    epoch: scope.epoch,
    timezone: scope.timezone,
    current_local_date: scope.currentLocalDate,
    selected_local_date: window.selectedDate,
    week_start: window.weekStart,
    week_end: window.weekEnd,
    observed_at: scope.observedAt,
    source_version: version(value),
    completeness: 'complete' as const,
    clinical_policy: scope.policy,
    days,
  }
  if (Buffer.byteLength(JSON.stringify(result), 'utf8') > 750000) return invalid()
  return result
}
export async function readNutritionWindow(
  auth: { userId: string; authUserId: string },
  selectedDate: string | undefined,
  dependencies: NutritionWindowDependencies,
) {
  const observe = dependencies.observe.bind(dependencies),
    read = dependencies.capture.bind(dependencies)
  const before = parseOwnedClinicalWindowScope(await observe())
  if (before.ownerID !== auth.userId || before.authUserID !== auth.authUserId) return changed()
  const window = nutritionWindowDates(before.timezone, selectedDate ?? before.currentLocalDate)
  const first = capture(await read(window), before.ownerID)
  const second = capture(await read(window), before.ownerID)
  if (version(first) !== version(second)) return changed()
  const after = parseOwnedClinicalWindowScope(await observe())
  if (
    after.ownerID !== before.ownerID ||
    after.authUserID !== before.authUserID ||
    after.epoch !== before.epoch ||
    after.timezone !== before.timezone ||
    after.currentLocalDate !== before.currentLocalDate ||
    after.binding !== before.binding ||
    Date.parse(after.observedAt) < Date.parse(before.observedAt)
  )
    return changed()
  return projectNutritionWindow(after, selectedDate, second)
}

/** Current owned meal facts only; no day, clock, target, Auth or write authority is manufactured. */
export function projectNutritionMealFacts(rawMeals: unknown, rawUnits: unknown, owner: string) {
  const meals = z.array(mealSchema).max(1000).parse(rawMeals),
    units = proveUnits(z.array(unitProof).max(1000).parse(rawUnits), meals, owner)
  if (meals.some((m) => m.user_id !== owner)) return invalid()
  return meals.map((m) => ({
    id: m.id,
    registration_key: createHash('sha256')
      .update(`${owner}\n${m.raw_provider_message_id ?? `meal-log:${m.id}`}`)
      .digest('hex'),
    meal_type: m.meal_type,
    food_name: m.food_name,
    quantity_g: m.quantity_g,
    display_quantity: units.find((u) => u.meal.id === m.id)?.display_quantity ?? null,
    kcal: m.kcal,
    protein_g: m.protein_g,
    carbs_g: m.carbs_g,
    fat_g: m.fat_g,
    consumed_at: m.consumed_at,
    nutrition_source: m.source,
  }))
}
