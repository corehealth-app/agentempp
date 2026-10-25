import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
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
const ownerBatchSchema = z
  .object({
    version: z.literal(1),
    users: z
      .array(
        z
          .object({
            id: z
              .string()
              .uuid()
              .refine((x) => x === x.toLowerCase()),
          })
          .strict(),
      )
      .max(100),
  })
  .strict()

/** Reserves a technical visit without changing users.updated_at or eligibility. */
export async function claimDeletedUsersForPhotoPurge(
  client: ServiceClient,
  cutoff: string,
  limit: number,
): Promise<Array<{ id: string }>> {
  const signal = AbortSignal.timeout(5000)
  try {
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('invalid')
    const result = await (client as unknown as RpcClient)
      .rpc('list_mobile_deleted_users_for_photo_purge', { p_cutoff: cutoff, p_limit: limit })
      .abortSignal(signal)
    if (!result || result.error !== null) throw new Error('unavailable')
    const data = ownerBatchSchema.parse(result.data)
    if (
      data.users.length > limit ||
      new Set(data.users.map((x) => x.id)).size !== data.users.length
    )
      throw new Error('invalid')
    return data.users
  } catch {
    throw new Error('reevaluation_photo_account_purge_unavailable')
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
    begin(userId, cutoff, signal) {
      return rpc(
        'begin_mobile_deleted_user_photo_purge',
        { p_user_id: userId, p_cutoff: cutoff },
        signal,
      )
    },
    purge(userId, cutoff, signal) {
      return rpc(
        'purge_mobile_reevaluation_photo_catalog_for_deleted_user',
        { p_user_id: userId, p_cutoff: cutoff },
        signal,
      )
    },
    claimScopes(userId, cutoff, limit, signal) {
      return rpc(
        'claim_mobile_reevaluation_photo_purge_scopes',
        { p_user_id: userId, p_cutoff: cutoff, p_limit: limit },
        signal,
      )
    },
    drain(scope, options) {
      return drainReevaluationPhotoDisposition(disposition, scope, options)
    },
  }
}
