import { healthRiskSetSchema } from '@mpp/core/health-check'
import type { ServiceClient } from '@mpp/db'
import {
  healthHoldFailure,
  parseHealthHoldSnapshot,
  parseHealthRiskDeclaration,
  sanitizeHealthHoldFailure,
} from './health-hold-contracts'
import type { HealthHoldRepository } from './health-hold-service'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

type HealthRpc = (
  name: 'get_mobile_health_hold_state' | 'declare_mobile_health_risk',
  args: { p_user_id: string; p_operation_key?: string; p_items?: readonly string[] },
) => PromiseLike<unknown>

/** Backend-only injected client. Does not read env, construct an SDK or activate a route. */
export function createSupabaseHealthHoldRepository(supabase: ServiceClient): HealthHoldRepository {
  const rpc = supabase.rpc.bind(supabase) as unknown as HealthRpc
  async function invoke(
    name: Parameters<HealthRpc>[0],
    args: Parameters<HealthRpc>[1],
  ): Promise<unknown> {
    let response: unknown
    try {
      response = await rpc(name, args)
    } catch {
      throw healthHoldFailure('unavailable')
    }
    try {
      if (
        !response ||
        typeof response !== 'object' ||
        Array.isArray(response) ||
        !Object.hasOwn(response, 'data') ||
        !Object.hasOwn(response, 'error')
      )
        throw healthHoldFailure('invalid_response')
      const envelope = response as { data: unknown; error: unknown }
      if (envelope.error !== null) {
        if (!envelope.error || typeof envelope.error !== 'object' || Array.isArray(envelope.error))
          throw healthHoldFailure('invalid_response')
        const code = Object.hasOwn(envelope.error, 'code')
          ? (envelope.error as { code: unknown }).code
          : null
        if (code === '40001') throw healthHoldFailure('state_changed')
        if (code === 'XX001') throw healthHoldFailure('invalid_response')
        throw healthHoldFailure('unavailable')
      }
      return envelope.data
    } catch (error) {
      // Recognize only errors created here; return new fixed text with no remote details.
      throw sanitizeHealthHoldFailure(error)
    }
  }
  return Object.freeze({
    async get(userId: string) {
      if (!uuid.safeParse(userId).success) throw healthHoldFailure('invalid_input')
      return parseHealthHoldSnapshot(
        await invoke('get_mobile_health_hold_state', { p_user_id: userId.toLowerCase() }),
        userId,
      )
    },
    async declare(userId: string, operationKey: string, items: readonly string[]) {
      const parsed = healthRiskSetSchema.safeParse(items)
      if (
        !uuid.safeParse(userId).success ||
        !uuid.safeParse(operationKey).success ||
        !parsed.success
      )
        throw healthHoldFailure('invalid_input')
      const result = await invoke('declare_mobile_health_risk', {
        p_user_id: userId.toLowerCase(),
        p_operation_key: operationKey.toLowerCase(),
        p_items: parsed.data,
      })
      return parseHealthRiskDeclaration(result, userId, operationKey, parsed.data)
    },
  })
}
