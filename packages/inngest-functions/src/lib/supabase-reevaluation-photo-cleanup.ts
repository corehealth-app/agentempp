import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { ReevaluationPhotoCleanupDependencies } from './reevaluation-photo-cleanup.js'
import { drainReevaluationPhotoDisposition } from './reevaluation-photo-disposition.js'
import { createReevaluationPhotoDispositionDependencies } from './supabase-reevaluation-photo-disposition.js'

interface ClaimClient {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): { abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }> }
}
/** Backend client injection only; importing never reads credentials or starts work. */
export function createReevaluationPhotoCleanupDependencies(
  client: ServiceClient,
): ReevaluationPhotoCleanupDependencies {
  const api = client as unknown as ClaimClient
  const disposition = createReevaluationPhotoDispositionDependencies(client)
  return {
    async claim(limit, signal) {
      if (!z.number().int().min(1).max(100).safeParse(limit).success || signal.aborted)
        throw new Error('reevaluation_photo_cleanup_unavailable')
      try {
        const result = await api
          .rpc('claim_mobile_reevaluation_photo_cleanup_scopes', { p_limit: limit })
          .abortSignal(signal)
        if (!result || result.error !== null || signal.aborted)
          throw new Error('reevaluation_photo_cleanup_unavailable')
        return result.data
      } catch {
        throw new Error('reevaluation_photo_cleanup_unavailable')
      }
    },
    drain(scope, options) {
      return drainReevaluationPhotoDisposition(disposition, scope, options)
    },
  }
}
