import { z } from 'zod'
import { MobileApiError } from './http'
import { type nutritionWindowDates, readNutritionUnitsResult } from './nutrition-window-service'

interface QueryResult {
  data: unknown[] | null
  error: unknown | null
  count: number | null
}
export interface NutritionWindowQuery extends PromiseLike<QueryResult> {
  select(columns: string, options: { count: 'exact' }): NutritionWindowQuery
  eq(column: string, value: unknown): NutritionWindowQuery
  gte(column: string, value: string): NutritionWindowQuery
  lt(column: string, value: string): NutritionWindowQuery
  lte(column: string, value: string): NutritionWindowQuery
  in(column: string, values: string[]): NutritionWindowQuery
  or(filter: string): NutritionWindowQuery
  order(column: string, options: { ascending: boolean }): NutritionWindowQuery
  limit(value: number): NutritionWindowQuery
}
/** No insert/update/delete or writable RPC capability. The one named RPC is a readonly owned unit proof. Counts must come from
 * the actual bounded PostgREST reads, never guessed from a short first page. */
export interface NutritionWindowReadPort {
  from(table: 'meal_logs' | 'daily_snapshots' | 'prescriptions'): NutritionWindowQuery
  rpc?(
    name: 'read_nutrition_window_units',
    args: { p_user_id: string; p_meal_ids: string[] },
  ): PromiseLike<{ data: unknown; error: unknown | null }>
}
function rows(result: QueryResult, maximum: number) {
  if (
    result.error !== null ||
    result.data === null ||
    typeof result.count !== 'number' ||
    !Number.isSafeInteger(result.count) ||
    result.count !== result.data.length ||
    result.count > maximum
  )
    throw new MobileApiError(
      503,
      'nutrition_window_unavailable',
      'A complete nutrition window is unavailable',
    )
  return result.data
}
export function createNutritionWindowCapture(port: NutritionWindowReadPort, rawOwner: string) {
  const owner = z.string().uuid().parse(rawOwner),
    from = port.from.bind(port)
  return async (window: ReturnType<typeof nutritionWindowDates>) => {
    const snapshots = rows(
      await from('daily_snapshots')
        .select(
          'id, user_id, date, calories_consumed, calories_target, protein_g, protein_target, carbs_g, fat_g, current_protocol, day_closed, updated_at',
          { count: 'exact' },
        )
        .eq('user_id', owner)
        .gte('date', window.weekStart)
        .lte('date', window.weekEnd)
        .order('date', { ascending: true })
        .limit(8),
      7,
    )
    // Also read every row attached to those snapshots. A timezone change can
    // move a meal's civil date: its stored totals must then be withheld rather
    // than mixed with current-zone records or mistaken for an empty day.
    const snapshotIDs = z
      .array(z.object({ id: z.string().uuid() }).passthrough())
      .parse(snapshots)
      .map((s) => s.id)
    let query = from('meal_logs')
      .select(
        'id, user_id, snapshot_id, meal_type, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, consumed_at, raw_provider_message_id, source',
        { count: 'exact' },
      )
      .eq('user_id', owner)
    query = snapshotIDs.length
      ? query.or(
          `and(consumed_at.gte.${window.startUTC},consumed_at.lt.${window.endUTC}),snapshot_id.in.(${snapshotIDs.join(',')})`,
        )
      : query.gte('consumed_at', window.startUTC).lt('consumed_at', window.endUTC)
    const meals = rows(
      await query
        .order('consumed_at', { ascending: true })
        .order('id', { ascending: true })
        .limit(1001),
      1000,
    )
    let units: ReturnType<typeof readNutritionUnitsResult> = []
    if (meals.length) {
      if (!port.rpc)
        throw new MobileApiError(
          503,
          'nutrition_window_unavailable',
          'Owned display facts are unavailable',
        )
      const ids = z
        .array(z.object({ id: z.string().uuid() }).passthrough())
        .parse(meals)
        .map((m) => m.id)
      const result = await port.rpc('read_nutrition_window_units', {
        p_user_id: owner,
        p_meal_ids: ids,
      })
      if (result.error !== null)
        throw new MobileApiError(
          503,
          'nutrition_window_unavailable',
          'Owned display facts are unavailable',
        )
      units = readNutritionUnitsResult(result.data, meals, owner)
    }
    const prescriptions = rows(
      await from('prescriptions')
        .select('id, user_id, type, payload, generated_at, valid_until, version, notes', {
          count: 'exact',
        })
        .eq('user_id', owner)
        .in('type', ['diet', 'combined'])
        .lt('generated_at', window.endUTC)
        .or(`valid_until.is.null,valid_until.gt.${window.startUTC}`)
        .order('generated_at', { ascending: false })
        .order('id', { ascending: true })
        .limit(21),
      20,
    )
    return {
      meals,
      units,
      snapshots,
      prescriptions,
      counts: {
        meals: meals.length,
        snapshots: snapshots.length,
        prescriptions: prescriptions.length,
      },
    }
  }
}
