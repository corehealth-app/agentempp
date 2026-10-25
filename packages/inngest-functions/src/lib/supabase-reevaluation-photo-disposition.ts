import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { ReevaluationPhotoDispositionDependencies } from './reevaluation-photo-disposition.js'

interface RpcResult {
  data: unknown
  error: unknown
}
interface RpcClient {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): { abortSignal(signal: AbortSignal): PromiseLike<RpcResult> }
}
const pathSchema = z
  .string()
  .regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp|heic|heif)$/,
  )
function unavailable() {
  return new Error('reevaluation_photo_disposition_unavailable')
}

/** Captures an injected backend client. Import never creates one or registers jobs. */
export function createReevaluationPhotoDispositionDependencies(
  client: ServiceClient,
): ReevaluationPhotoDispositionDependencies {
  const api = client as unknown as RpcClient
  async function rpc(name: string, args: Record<string, unknown>, signal: AbortSignal) {
    try {
      const result = await api.rpc(name, args).abortSignal(signal)
      if (!result || result.error !== null) throw unavailable()
      return result.data
    } catch {
      throw unavailable()
    }
  }
  return {
    prepare(scope, signal) {
      return rpc(
        'prepare_mobile_reevaluation_photo_disposition',
        { p_user_id: scope.userId, p_cycle_id: scope.cycleId, p_acceptance_id: scope.acceptanceId },
        signal,
      )
    },
    page(header, cursor, signal) {
      return rpc(
        'get_mobile_reevaluation_photo_disposition_page',
        {
          p_user_id: header.user_id,
          p_disposition_id: header.id,
          p_expected_sweep: header.sweep_no,
          p_expected_capability_revision: header.capability_revision,
          p_expected_after: cursor,
        },
        signal,
      )
    },
    async remove(paths) {
      const parsed = z.array(pathSchema).min(1).max(200).safeParse(paths)
      if (
        !parsed.success ||
        new Set(parsed.data).size !== parsed.data.length ||
        new Set(parsed.data.map((path) => path.split('/')[0])).size !== 1
      )
        throw unavailable()
      try {
        const result = await client.storage.from('body-checkin-photos').remove([...parsed.data])
        if (!result || result.error !== null) throw unavailable()
      } catch {
        throw unavailable()
      }
    },
    commit(header, cursor, assetIds, signal) {
      return rpc(
        'commit_mobile_reevaluation_photo_disposition_page',
        {
          p_user_id: header.user_id,
          p_disposition_id: header.id,
          p_expected_sweep: header.sweep_no,
          p_expected_capability_revision: header.capability_revision,
          p_expected_after: cursor,
          p_asset_ids: [...assetIds],
        },
        signal,
      )
    },
  }
}
