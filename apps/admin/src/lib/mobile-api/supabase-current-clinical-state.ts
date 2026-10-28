/** Backend transport only. No default factory, route capability or activation.
 * The public RPC is service-only; the clock-bearing private helper stays revoked. */
import type { ServiceClient } from '@mpp/db'
import {
  type CurrentClinicalRequest,
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
  currentClinicalError,
} from './current-clinical-state'

type CurrentRpc = (
  name: 'get_mobile_current_clinical_state',
  args: Record<string, unknown>,
) => PromiseLike<unknown>

export function createSupabaseCurrentClinicalStateSource(
  supabase: ServiceClient,
): CurrentClinicalStateSource {
  const rpc = supabase.rpc.bind(supabase) as unknown as CurrentRpc
  return Object.freeze({
    capture: (input: Readonly<CurrentClinicalRequest>) =>
      captureCurrentClinicalState(
        {
          capture: async (request) => {
            const expected = {
              ...(request.expectedEpoch === undefined ? {} : { epoch: request.expectedEpoch }),
              ...(request.expectedGeneration === undefined
                ? {}
                : { generation_token: request.expectedGeneration }),
            }
            let response: unknown
            try {
              response = await rpc('get_mobile_current_clinical_state', {
                p_user_id: request.userId,
                p_mode: request.mode,
                p_body: request.mode === 'signup' ? request.body : null,
                p_expected: Object.keys(expected).length ? expected : null,
              })
            } catch {
              throw currentClinicalError('unavailable')
            }
            if (
              !response ||
              typeof response !== 'object' ||
              Array.isArray(response) ||
              !Object.hasOwn(response, 'data') ||
              !Object.hasOwn(response, 'error')
            )
              throw currentClinicalError('invalid_response')
            const envelope = response as { data: unknown; error: unknown }
            if (envelope.error !== null) {
              if (
                !envelope.error ||
                typeof envelope.error !== 'object' ||
                Array.isArray(envelope.error)
              )
                throw currentClinicalError('invalid_response')
              const code = Object.hasOwn(envelope.error, 'code')
                ? (envelope.error as { code: unknown }).code
                : null
              if (code === '40001') throw currentClinicalError('changed')
              if (code === '55P03') throw currentClinicalError('busy')
              throw currentClinicalError('unavailable')
            }
            return envelope.data
          },
        },
        input,
      ),
  })
}
