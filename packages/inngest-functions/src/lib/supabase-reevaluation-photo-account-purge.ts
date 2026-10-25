import type { ServiceClient } from '@mpp/db'
import type { ReevaluationPhotoAccountPurgeDependencies } from './reevaluation-photo-account-purge.js'
import { drainReevaluationPhotoDisposition } from './reevaluation-photo-disposition.js'
import { createReevaluationPhotoDispositionDependencies } from './supabase-reevaluation-photo-disposition.js'

interface RpcClient {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): {
    abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }>
  }
}
/** Injected backend client only; no import-time runtime or job registration. */
export function createReevaluationPhotoAccountPurgeDependencies(
  client: ServiceClient,
): ReevaluationPhotoAccountPurgeDependencies {
  const api = client as unknown as RpcClient
  const disposition = createReevaluationPhotoDispositionDependencies(client)
  async function rpc(name: string, args: Record<string, unknown>, signal: AbortSignal) {
    try {
      const result = await api.rpc(name, args).abortSignal(signal)
      if (!result || result.error !== null) throw new Error('unavailable')
      return result.data
    } catch {
      throw new Error('reevaluation_photo_account_purge_unavailable')
    }
  }
  return {
    purge(userId, cutoff, signal) {
      return rpc(
        'purge_mobile_reevaluation_photo_catalog_for_deleted_user',
        { p_user_id: userId, p_cutoff: cutoff },
        signal,
      )
    },
    listScopes(userId, cutoff, after, limit, signal) {
      return rpc(
        'list_mobile_reevaluation_photo_purge_scopes',
        { p_user_id: userId, p_cutoff: cutoff, p_after_acceptance: after, p_limit: limit },
        signal,
      )
    },
    drain(scope, options) {
      return drainReevaluationPhotoDisposition(disposition, scope, options)
    },
  }
}
