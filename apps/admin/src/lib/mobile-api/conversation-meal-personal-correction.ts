/** Exact owned approval-state reads only. No learning, writes, model, history,
 * nutrition calculation or permission to register a meal. */
import { isDeepStrictEqual } from 'node:util'
import { hasImpossibleKcalDensity } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'

// Exact normalization used by lookupFoodCorrection and its learning writer.
// Do not collapse interior whitespace or normalize through a fuzzy matcher.
const normalize = (s: string) =>
  s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/gu, '')
    .trim()
const number = z.number().finite().nullable()
const rowSchema = z
  .object({
    id: z.string().uuid(),
    user_id: z.string().uuid(),
    said_name: z.string().min(1).max(250),
    corrected_to: z.string().trim().min(1).max(250),
    custom_kcal_per_100g: number,
    custom_protein_g: number,
    custom_carbs_g: number,
    custom_fat_g: number,
    status: z.enum(['active', 'learning', 'retired']),
    confirmed_count: z.number().int().min(-32768).max(32767),
    last_seen: z.string(),
  })
  .strict()
type Row = z.infer<typeof rowSchema>
export type BoundConversationMealCorrection =
  | { readonly status: 'none' }
  | { readonly status: 'unproven' }
  | { readonly status: 'learning' }
  | { readonly status: 'active'; readonly row: Readonly<Row>; readonly customNutrition: boolean }
function refuse(): never {
  throw new Error('Personal meal correction unavailable')
}
function instant(value: string): bigint {
  // Same civil-date/RFC3339/nanosecond check as the real source factory.
  const match =
    /^(\d{4}-\d{2}-\d{2})T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.(\d{1,9}))?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/u.exec(
      value,
    )
  if (!match || value.startsWith('0000')) refuse()
  const date = new Date(`${match[1]}T00:00:00.000Z`),
    time = Date.parse(value)
  if (
    !Number.isFinite(time) ||
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 10) !== match[1]
  )
    refuse()
  return BigInt(time) * 1_000_000n + BigInt((match[2] ?? '').padEnd(9, '0').slice(3))
}

/** Captures owner, exact server clock and SDK callback before any await.
 * The shared calculator still receives its original food_name and applies
 * one correction itself. No destination recursion or pre-rewrite occurs. */
export function createBoundConversationMealCorrectionReader(
  db: ServiceClient,
  original: { ownerId: string; asOf: string },
): (name: string) => Promise<BoundConversationMealCorrection> {
  const from = db.from.bind(db),
    binding = z
      .object({ ownerId: z.string().uuid(), asOf: z.string() })
      .strict()
      .parse(structuredClone(original))
  const asOf = instant(binding.asOf)
  // Match the existing lookup's Date/ISO30-day lower bound exactly. Preserve
  // nanos for future/winner checks; never choose a fresh application clock.
  const lookback = new Date(Date.parse(binding.asOf) - 30 * 24 * 3600 * 1000).toISOString(),
    lower = instant(lookback)
  return async (name: string): Promise<BoundConversationMealCorrection> => {
    const target = normalize(name)
    // The unchanged shared calculator still interpolates these delimiters.
    // Refuse such an original input rather than pass an unsafe alias to it.
    if (!target || target.length > 160 || /[(),"]/u.test(target)) refuse()
    const found = new Map<string, Row>()
    for (const field of ['said_name', 'corrected_to'] as const) {
      const result = await from('user_food_corrections')
        .select(
          'id,user_id,said_name,corrected_to,custom_kcal_per_100g,custom_protein_g,custom_carbs_g,custom_fat_g,status,confirmed_count,last_seen',
        )
        .eq('user_id', binding.ownerId)
        .eq(field, target)
        .neq('status', 'retired')
        .gte('last_seen', lookback)
        .order('last_seen', { ascending: false })
        .limit(2)
      if (!result || result.error) refuse()
      const raw = structuredClone(result.data),
        rows = z.array(rowSchema).max(2).parse(raw)
      if (!isDeepStrictEqual(raw, rows)) refuse()
      let previous: bigint | null = null
      const ids = new Set<string>()
      for (const row of rows) {
        const clock = instant(row.last_seen)
        if (ids.has(row.id)) refuse()
        ids.add(row.id)
        if (
          row.user_id !== binding.ownerId ||
          row[field] !== target ||
          row.status === 'retired' ||
          clock < lower ||
          clock > asOf ||
          (previous !== null && clock > previous)
        )
          refuse()
        previous = clock
        const same = found.get(row.id)
        if (same && !isDeepStrictEqual(same, row)) refuse()
        found.set(row.id, row)
      }
    }
    const rows = [...found.values()].sort((a, b) => {
      const left = instant(a.last_seen),
        right = instant(b.last_seen)
      return left > right ? -1 : left < right ? 1 : 0
    })
    const row = rows[0]
    if (!row) return Object.freeze({ status: 'none' })
    if (rows[1] && instant(rows[1].last_seen) === instant(row.last_seen)) refuse()
    // Actual writer convention: repeat same destination activates on count2.
    // DDL does not enforce it, so active/count1 is an explicit unproven gate.
    if (row.status === 'learning') return Object.freeze({ status: 'learning' })
    if (row.status !== 'active' || row.confirmed_count < 2)
      return Object.freeze({ status: 'unproven' })
    const custom = row.custom_kcal_per_100g !== null
    if (custom) {
      const values = [
        row.custom_kcal_per_100g,
        row.custom_protein_g ?? 0,
        row.custom_carbs_g ?? 0,
        row.custom_fat_g ?? 0,
      ]
      if (
        values.some((value) => value === null || !Number.isFinite(value) || value < 0) ||
        hasImpossibleKcalDensity(row.custom_kcal_per_100g ?? NaN, 100)
      )
        return Object.freeze({ status: 'unproven' })
    }
    return freezeInterpretation({ status: 'active', row, customNutrition: custom })
  }
}
