import type { Json, ServiceClient } from '@mpp/db'
import { ConsumedFoodReferenceUnavailableError } from './consumed-food-defaults.js'

/** Rows returned by the real command-bound SQL nutrition-source RPC. */
export interface MealHistoryRow {
  readonly id: string
  readonly user_id: string
  readonly created_at: string
  readonly food_name: string
  readonly food_db_id: number | null
  readonly quantity_g: number | null
  readonly kcal: number | null
  readonly protein_g: number | null
  readonly carbs_g: number | null
  readonly fat_g: number | null
  readonly source: string | null
  readonly food_db: Readonly<{ is_verified: boolean | null }> | null
}
export interface MealNutritionSourceReader {
  readonly ownerId: string
  /** Exact server capture timestamp, never a newly chosen BFF clock. */
  readonly asOf: string
  read(
    kind: 'trusted_recent' | 'exact_median',
    foodName: string | null,
  ): Promise<readonly MealHistoryRow[]>
}
export interface MealCalculationAuditEvent {
  readonly user_id: string | null
  readonly event: string
  readonly properties: Readonly<Record<string, Json | undefined>>
}
export type MealCalculationAuditSink = (event: MealCalculationAuditEvent) => void | Promise<void>
export interface MealCalculationOptions {
  readonly consumptionPolicy?: 'consumed-meal-v1'
  readonly preparationAnnotations?: 'consumed.preparation.v1'
  readonly sourceReader?: MealNutritionSourceReader
  readonly auditSink?: MealCalculationAuditSink
}
export interface CapturedMealCalculationOptions {
  readonly consumptionPolicy?: 'consumed-meal-v1'
  readonly preparationAnnotations?: 'consumed.preparation.v1'
  readonly sourceReader?: MealNutritionSourceReader
  readonly auditSink?: MealCalculationAuditSink
}

/** RFC3339 with a real civil date; Date.parse alone normalizes February30. */
export function mealSourceClock(value: string): number {
  const match =
    /^(\d{4}-\d{2}-\d{2})T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,9})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/.exec(
      value,
    )
  if (!match || value.startsWith('0000')) throw new ConsumedFoodReferenceUnavailableError()
  const civil = new Date(`${match[1]}T00:00:00.000Z`),
    instant = Date.parse(value)
  if (
    !Number.isFinite(civil.getTime()) ||
    civil.toISOString().slice(0, 10) !== match[1] ||
    !Number.isFinite(instant)
  )
    throw new ConsumedFoodReferenceUnavailableError()
  return instant
}
export function captureMealCalculationOptions(
  options: MealCalculationOptions | undefined,
  owner: string | undefined,
): CapturedMealCalculationOptions {
  const consumptionPolicy = options?.consumptionPolicy,
    preparationAnnotations = options?.preparationAnnotations,
    reader = options?.sourceReader,
    sink = options?.auditSink
  let sourceReader: MealNutritionSourceReader | undefined
  if (reader) {
    const ownerId = reader.ownerId,
      asOf = reader.asOf,
      read = reader.read
    if (
      typeof ownerId !== 'string' ||
      !owner ||
      ownerId.toLowerCase() !== owner.toLowerCase() ||
      typeof asOf !== 'string' ||
      typeof read !== 'function'
    )
      throw new ConsumedFoodReferenceUnavailableError()
    mealSourceClock(asOf)
    sourceReader = Object.freeze({ ownerId, asOf, read: read.bind(reader) })
  }
  return Object.freeze({
    consumptionPolicy,
    preparationAnnotations,
    sourceReader,
    auditSink: sink?.bind(options),
  })
}
export async function readBoundMealHistory(
  reader: MealNutritionSourceReader,
  kind: 'trusted_recent' | 'exact_median',
  foodName: string | null,
): Promise<readonly MealHistoryRow[]> {
  const rows = structuredClone(await reader.read(kind, foodName))
  if (!Array.isArray(rows) || rows.length > (kind === 'trusted_recent' ? 50 : 20))
    throw new ConsumedFoodReferenceUnavailableError()
  const seen = new Set<string>()
  for (const row of rows) {
    if (
      !row ||
      typeof row !== 'object' ||
      typeof row.id !== 'string' ||
      seen.has(row.id) ||
      typeof row.user_id !== 'string' ||
      row.user_id.toLowerCase() !== reader.ownerId.toLowerCase() ||
      typeof row.created_at !== 'string' ||
      typeof row.food_name !== 'string' ||
      !(row.source === null || typeof row.source === 'string') ||
      !(row.food_db_id === null || Number.isSafeInteger(row.food_db_id)) ||
      ![row.quantity_g, row.kcal, row.protein_g, row.carbs_g, row.fat_g].every(
        (n) => n === null || (typeof n === 'number' && Number.isFinite(n)),
      ) ||
      !(
        row.food_db === null ||
        (typeof row.food_db === 'object' &&
          !Array.isArray(row.food_db) &&
          (row.food_db.is_verified === null || typeof row.food_db.is_verified === 'boolean'))
      )
    )
      throw new ConsumedFoodReferenceUnavailableError()
    mealSourceClock(row.created_at)
    seen.add(row.id)
  }
  return rows
}
export async function emitMealCalculationAudit(
  db: ServiceClient,
  captured: CapturedMealCalculationOptions,
  event: MealCalculationAuditEvent,
): Promise<void> {
  if (captured.auditSink) {
    try {
      await captured.auditSink(structuredClone(event))
    } catch {
      // Optional preparation audit collection cannot trigger a domain retry or
      // silently fall back to a pre-commit database analytics write.
    }
    return
  }
  await db.from('product_events').insert(event)
}
