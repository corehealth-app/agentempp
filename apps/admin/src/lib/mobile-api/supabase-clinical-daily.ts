/** Backend-only daily transport. No default route, clock input or activation.
 * SQL owns the APPLICATION capture and rechecks the full context after locks. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type ClinicalDailyCalculation,
  type ClinicalDailyRepository,
  clinicalDailyRepositoryError,
} from './clinical-daily-service'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

type RpcName =
  | 'get_mobile_clinical_daily_receipt'
  | 'get_mobile_clinical_daily_context'
  | 'apply_mobile_clinical_daily'
type DailyRpc = (name: RpcName, args: Record<string, unknown>) => PromiseLike<unknown>
const kcal = z.number().int().min(1).max(2147483647).nullable()
const protein = z.number().finite().min(0).max(9999.99).nullable()
const calculationSchema = z
  .object({
    version: z.literal(1),
    formulaKcal: kcal,
    maintenanceKcal: kcal,
    sedentaryKcal: kcal,
    proteinTarget: protein,
    maintenanceProteinTarget: protein,
  })
  .strict()
function owner(value: unknown) {
  const parsed = uuid.safeParse(value)
  if (!parsed.success) throw clinicalDailyRepositoryError('unavailable')
  return parsed.data
}

export function createSupabaseClinicalDailyRepository(
  supabase: ServiceClient,
): ClinicalDailyRepository {
  const rpc = supabase.rpc.bind(supabase) as unknown as DailyRpc
  async function call(name: RpcName, args: Record<string, unknown>, nullable = false) {
    let raw: unknown
    try {
      raw = await rpc(name, Object.freeze(args))
    } catch {
      throw clinicalDailyRepositoryError('unavailable')
    }
    if (
      !raw ||
      typeof raw !== 'object' ||
      Array.isArray(raw) ||
      !Object.hasOwn(raw, 'data') ||
      !Object.hasOwn(raw, 'error')
    )
      throw clinicalDailyRepositoryError('unavailable')
    const response = raw as { data: unknown; error: unknown }
    if (response.error !== null) {
      const error = response.error
      const code =
        error && typeof error === 'object' && !Array.isArray(error) && Object.hasOwn(error, 'code')
          ? (error as { code: unknown }).code
          : null
      if (code === '40001') throw clinicalDailyRepositoryError('changed')
      if (code === '55P03') throw clinicalDailyRepositoryError('busy')
      throw clinicalDailyRepositoryError('unavailable')
    }
    if (nullable && response.data === null) return null
    if (!response.data || typeof response.data !== 'object' || Array.isArray(response.data))
      throw clinicalDailyRepositoryError('unavailable')
    return structuredClone(response.data)
  }
  return Object.freeze({
    async findReceipt(userId: string, operationKey: string) {
      return call(
        'get_mobile_clinical_daily_receipt',
        { p_user_id: owner(userId), p_operation_key: owner(operationKey) },
        true,
      )
    },
    async capture(userId: string) {
      return call('get_mobile_clinical_daily_context', { p_user_id: owner(userId) })
    },
    async apply(
      userId: string,
      operationKey: string,
      contextHash: string,
      calculation: ClinicalDailyCalculation,
    ) {
      const user = owner(userId),
        key = owner(operationKey)
      const parsed = calculationSchema.safeParse(calculation)
      if (!parsed.success || !/^[0-9a-f]{64}$/.test(contextHash))
        throw clinicalDailyRepositoryError('unavailable')
      return call('apply_mobile_clinical_daily', {
        p_user_id: user,
        p_operation_key: key,
        p_context_hash: contextHash,
        p_calculation: Object.freeze(parsed.data),
      })
    },
  })
}
