import type { ServiceClient } from '@mpp/db'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  parsePhotoAllocationRequest,
  parsePhotoAllocationResponse,
  photoAllocationFailure,
  type ReevaluationPhotoAllocationRepository,
  sanitizePhotoAllocationFailure,
} from './reevaluation-photo-allocation'

type AllocationRpc = (
  name: 'create_mobile_reevaluation_photo_asset',
  args: {
    p_user_id: string
    p_cycle_id: string
    p_expected_revision: string
    p_acceptance_id: string
    p_pose: string
    p_mime_type: string
    p_size_bytes: number
    p_request_key: string
  },
) => PromiseLike<unknown>

/** Backend client is injected. No SDK construction, environment read or retry. */
export function createSupabaseReevaluationPhotoAllocationRepository(
  supabase: ServiceClient,
): ReevaluationPhotoAllocationRepository {
  const rpc = supabase.rpc.bind(supabase) as unknown as AllocationRpc
  return Object.freeze({
    async allocate(userId: string, input: unknown) {
      if (!uuid.safeParse(userId).success) throw photoAllocationFailure('invalid_input')
      const request = parsePhotoAllocationRequest(input)
      const owner = userId.toLowerCase()
      let response: unknown
      try {
        response = await rpc('create_mobile_reevaluation_photo_asset', {
          p_user_id: owner,
          p_cycle_id: request.cycleId,
          p_expected_revision: request.expectedRevision,
          p_acceptance_id: request.acceptanceId,
          p_pose: request.pose,
          p_mime_type: request.mimeType,
          p_size_bytes: request.sizeBytes,
          p_request_key: request.requestKey,
        })
      } catch {
        throw photoAllocationFailure('unavailable')
      }
      try {
        if (
          !response ||
          typeof response !== 'object' ||
          Array.isArray(response) ||
          !Object.hasOwn(response, 'data') ||
          !Object.hasOwn(response, 'error')
        )
          throw photoAllocationFailure('invalid_response')
        const envelope = response as { data: unknown; error: unknown }
        if (envelope.error !== null) {
          if (
            envelope.data !== null ||
            !envelope.error ||
            typeof envelope.error !== 'object' ||
            Array.isArray(envelope.error)
          )
            throw photoAllocationFailure('invalid_response')
          const error = envelope.error as { code?: unknown; message?: unknown }
          if (error.code === '40001') throw photoAllocationFailure('state_changed')
          if (error.code === 'P0001' && error.message === 'mobile_reevaluation_photo_limit_reached')
            throw photoAllocationFailure('quota_reached')
          throw photoAllocationFailure('unavailable')
        }
        return parsePhotoAllocationResponse(envelope.data, owner, request)
      } catch (error) {
        throw sanitizePhotoAllocationFailure(error)
      }
    },
  })
}
