import { z } from 'zod'
import { MobileApiError } from './http'
import type { clinicalWindowDates } from './owned-clinical-window'

interface QueryResult {
  data: unknown[] | null
  error: unknown | null
  count: number | null
}
export interface TrainingWindowQuery extends PromiseLike<QueryResult> {
  select(columns: string, options: { count: 'exact' }): TrainingWindowQuery
  eq(column: string, value: unknown): TrainingWindowQuery
  gte(column: string, value: string): TrainingWindowQuery
  lt(column: string, value: string): TrainingWindowQuery
  order(column: string, options: { ascending: boolean }): TrainingWindowQuery
  limit(value: number): TrainingWindowQuery
}
/** Only bounded reads of existing official records; no RPC or write operation. */
export interface TrainingWindowReadPort {
  from(table: 'workout_logs'): TrainingWindowQuery
}
export function createTrainingWindowCapture(port: TrainingWindowReadPort, rawOwner: string) {
  const owner = z.string().uuid().parse(rawOwner),
    from = port.from.bind(port)
  return async (window: ReturnType<typeof clinicalWindowDates>) => {
    const result = await from('workout_logs')
      .select('id, user_id, workout_type, duration_min, estimated_kcal, intensity, performed_at', {
        count: 'exact',
      })
      .eq('user_id', owner)
      .gte('performed_at', window.startUTC)
      .lt('performed_at', window.endUTC)
      .order('performed_at', { ascending: true })
      .order('id', { ascending: true })
      .limit(1001)
    if (
      result.error !== null ||
      result.data === null ||
      !Number.isSafeInteger(result.count) ||
      result.count !== result.data.length ||
      result.count === null ||
      result.count > 1000
    )
      throw new MobileApiError(
        503,
        'training_window_unavailable',
        'A complete training window is unavailable',
      )
    return { workouts: result.data, count: result.count }
  }
}
