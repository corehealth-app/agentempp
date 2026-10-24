import type { ServiceClient } from '@mpp/db'
import { MobileApiError } from './http'
import {
  parseReevaluationCycleRpcState,
  type ReevaluationCycleState,
  reevaluationCycleUuidSchema,
} from './reevaluation-cycle-contracts'
import type { ReevaluationCycleRepository } from './reevaluation-cycle-service'

type CycleRpc = (
  name: 'get_mobile_reevaluation_cycle' | 'start_mobile_reevaluation_cycle',
  args: { p_user_id: string; p_idempotency_key?: string },
) => PromiseLike<unknown>

function failure(kind: 'invalid_input' | 'invalid_response' | 'unavailable'): MobileApiError {
  return new MobileApiError(
    kind === 'unavailable' ? 503 : 500,
    `mobile_reevaluation_${kind}`,
    'Unable to read reevaluation state',
  )
}

/** Backend-only port; does not change generated database types or instantiate a client. */
export function createSupabaseReevaluationCycleRepository(
  supabase: ServiceClient,
): ReevaluationCycleRepository {
  const rpc = supabase.rpc.bind(supabase) as unknown as CycleRpc
  async function invoke(
    name: Parameters<CycleRpc>[0],
    args: Parameters<CycleRpc>[1],
  ): Promise<ReevaluationCycleState> {
    let response: unknown
    try {
      response = await rpc(name, args)
    } catch {
      throw failure('unavailable')
    }
    if (
      !response ||
      typeof response !== 'object' ||
      Array.isArray(response) ||
      !Object.hasOwn(response, 'data') ||
      !Object.hasOwn(response, 'error')
    )
      throw failure('invalid_response')
    const envelope = response as { data: unknown; error: unknown }
    if (envelope.error !== null) {
      if (!envelope.error || typeof envelope.error !== 'object' || Array.isArray(envelope.error))
        throw failure('invalid_response')
      const code = Object.hasOwn(envelope.error, 'code')
        ? (envelope.error as { code: unknown }).code
        : null
      if (code === '40001')
        throw new MobileApiError(
          409,
          'mobile_reevaluation_state_changed',
          'Reload the reevaluation state before continuing',
        )
      if (code === 'XX001') throw failure('invalid_response')
      throw failure('unavailable')
    }
    return parseReevaluationCycleRpcState(envelope.data)
  }
  return Object.freeze({
    async get(userId: string): Promise<ReevaluationCycleState> {
      if (!reevaluationCycleUuidSchema.safeParse(userId).success) throw failure('invalid_input')
      return invoke('get_mobile_reevaluation_cycle', { p_user_id: userId })
    },
    async start(userId: string, idempotencyKey: string): Promise<ReevaluationCycleState> {
      if (
        !reevaluationCycleUuidSchema.safeParse(userId).success ||
        !reevaluationCycleUuidSchema.safeParse(idempotencyKey).success
      )
        throw failure('invalid_input')
      return invoke('start_mobile_reevaluation_cycle', {
        p_user_id: userId,
        p_idempotency_key: idempotencyKey,
      })
    },
  })
}
