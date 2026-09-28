import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { WeightInput } from './contracts'
import { MobileApiError } from './http'

// The official weight lives in user_profiles.weight_kg (no second ledger).
// Conversion, rounding, ordering and ties are decided by the database
// (record_weight_atomic); this service only validates the request window and
// maps the outcome.

const POUND_IN_KG = 0.45359237
const MINIMUM_KG = 30
const MAXIMUM_KG = 300

export interface WeightRecordInput {
  userId: string
  value: number
  unit: 'kg' | 'lb'
  measuredAt: string
  idempotencyKey: string
}

export interface WeightRecordResult {
  applied: boolean
  reason: 'applied' | 'same_measurement' | 'older_than_current'
  weight_kg: number
  measured_at: string
}

export interface WeightRepository {
  record(input: WeightRecordInput): Promise<WeightRecordResult>
}

export interface WeightServiceDependencies {
  repository: WeightRepository
}

const weightResultSchema = z.object({
  applied: z.boolean(),
  reason: z.enum(['applied', 'same_measurement', 'older_than_current']),
  weight_kg: z.number().min(MINIMUM_KG).max(MAXIMUM_KG),
  measured_at: z.string().datetime({ offset: true }),
})

function outOfRange(): MobileApiError {
  return new MobileApiError(422, 'weight_out_of_range', 'Weight must be between 30 and 300 kg')
}

export async function recordWeight(
  deps: WeightServiceDependencies,
  userId: string,
  input: WeightInput,
  idempotencyKey: string,
  now = new Date(),
) {
  const measuredAt = new Date(input.measured_at).getTime()
  if (
    measuredAt > now.getTime() + 5 * 60 * 1000 ||
    measuredAt < now.getTime() - 7 * 24 * 60 * 60 * 1000
  ) {
    throw new MobileApiError(
      422,
      'measured_at_out_of_range',
      'measured_at must be within the supported offline window',
    )
  }
  // Early, typed refusal of values that cannot be in range; the database
  // repeats the check on the converted and rounded value.
  const kilograms = input.unit === 'lb' ? input.value * POUND_IN_KG : input.value
  if (kilograms < MINIMUM_KG - 0.005 || kilograms >= MAXIMUM_KG + 0.005) throw outOfRange()

  return deps.repository.record({
    userId,
    value: input.value,
    unit: input.unit,
    measuredAt: input.measured_at,
    idempotencyKey,
  })
}

type UntypedRpc = (
  functionName: string,
  params: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: { code?: string; message: string } | null }>

export function createSupabaseWeightDependencies(
  supabase: ServiceClient,
): WeightServiceDependencies {
  const rpc = supabase.rpc.bind(supabase) as unknown as UntypedRpc
  return {
    repository: {
      async record(input) {
        const { data, error } = await rpc('record_weight_atomic', {
          p_user_id: input.userId,
          p_value: input.value,
          p_unit: input.unit,
          p_measured_at: input.measuredAt,
          p_idempotency_key: input.idempotencyKey,
        })
        if (error?.code === '23505') {
          throw new MobileApiError(
            409,
            'weight_measurement_conflict',
            'Another weight is already recorded for this instant',
          )
        }
        if (error?.code === '22023') throw outOfRange()
        if (error || !data) {
          console.error('[mobile-weight] database_failure', {
            error_code: error?.code ?? 'empty_result',
          })
          throw new MobileApiError(500, 'weight_storage_failed', 'Weight operation failed')
        }
        const parsed = weightResultSchema.safeParse(data)
        if (!parsed.success) {
          console.error('[mobile-weight] database_failure', { error_code: 'parse_result' })
          throw new MobileApiError(500, 'weight_storage_failed', 'Weight operation failed')
        }
        return parsed.data
      },
    },
  }
}
