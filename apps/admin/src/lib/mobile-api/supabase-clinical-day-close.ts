/** Narrow backend-only RPCs. No clock, direct table read, fallback or retry. */
import type { ServiceClient } from '@mpp/db'
import {
  type ClinicalCloseScope,
  type ClinicalDayCloseEffect,
  clinicalCloseError,
  clinicalCloseScopeSchema,
  clinicalDayCloseEffectSchema,
  closeHash,
} from './clinical-day-close-contracts'
import type { ClinicalDayCloseRepository } from './clinical-day-close-service'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

type RpcName =
  | 'get_mobile_clinical_day_close_receipt'
  | 'capture_mobile_clinical_day_close'
  | 'apply_mobile_clinical_day_close'
type Rpc = (name: RpcName, args: Record<string, unknown>) => PromiseLike<unknown>
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
export function createSupabaseClinicalDayCloseRepository(
  supabase: ServiceClient,
): ClinicalDayCloseRepository {
  const rpc = supabase.rpc.bind(supabase) as unknown as Rpc
  async function call(name: RpcName, args: Record<string, unknown>, nullable = false) {
    let raw: unknown
    try {
      raw = await rpc(name, freeze(args))
    } catch {
      throw clinicalCloseError('unavailable')
    }
    if (
      !raw ||
      typeof raw !== 'object' ||
      Array.isArray(raw) ||
      !Object.hasOwn(raw, 'data') ||
      !Object.hasOwn(raw, 'error')
    )
      throw clinicalCloseError('unavailable')
    const reply = raw as { data: unknown; error: unknown }
    if (reply.error !== null) {
      const code =
        reply.error &&
        typeof reply.error === 'object' &&
        !Array.isArray(reply.error) &&
        Object.hasOwn(reply.error, 'code')
          ? (reply.error as { code: unknown }).code
          : null
      throw clinicalCloseError(
        code === '40001' ? 'changed' : code === '55P03' ? 'busy' : 'unavailable',
      )
    }
    if (nullable && reply.data === null) return null
    if (!reply.data || typeof reply.data !== 'object' || Array.isArray(reply.data))
      throw clinicalCloseError('unavailable')
    return structuredClone(reply.data)
  }
  function scopeArgs(raw: ClinicalCloseScope) {
    const scope = clinicalCloseScopeSchema.parse(raw)
    return {
      p_user_id: scope.userId.toLowerCase(),
      p_from: scope.from,
      p_close_date: scope.date,
      p_expected_timezone: scope.timezone,
    }
  }
  return Object.freeze({
    async findReceipt(userId: string, key: string) {
      return call(
        'get_mobile_clinical_day_close_receipt',
        {
          p_user_id: uuid.parse(userId).toLowerCase(),
          p_operation_key: uuid.parse(key).toLowerCase(),
        },
        true,
      )
    },
    async capture(scope: ClinicalCloseScope) {
      return call('capture_mobile_clinical_day_close', scopeArgs(scope))
    },
    async apply(
      scope: ClinicalCloseScope,
      key: string,
      contextHash: string,
      effect: ClinicalDayCloseEffect,
    ) {
      return call('apply_mobile_clinical_day_close', {
        ...scopeArgs(scope),
        p_operation_key: uuid.parse(key).toLowerCase(),
        p_context_hash: closeHash.parse(contextHash),
        p_effect: clinicalDayCloseEffectSchema.parse(effect),
      })
    },
  })
}
