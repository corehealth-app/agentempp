import { randomUUID } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  parseCurrentPhotoUpload,
  parsePreparedPhotoUpload,
  parseRegisteredPhotoUpload,
  photoUploadError,
  type ReevaluationPhotoUploadDependencies,
} from './reevaluation-photo-upload'

/** Backend-only adapter. It neither creates a client nor exposes a route. */
export function createSupabaseReevaluationPhotoUploadDependencies(
  supabase: ServiceClient,
  options: { storageOrigin: string },
): ReevaluationPhotoUploadDependencies {
  const rpc = supabase.rpc.bind(supabase) as unknown as (
    name: string,
    args: Record<string, string>,
  ) => PromiseLike<unknown>
  async function invoke(name: string, args: Record<string, string>) {
    let result: unknown
    try {
      result = await rpc(name, args)
    } catch {
      throw photoUploadError()
    }
    if (
      !result ||
      typeof result !== 'object' ||
      Array.isArray(result) ||
      !Object.hasOwn(result, 'data') ||
      !Object.hasOwn(result, 'error')
    )
      throw photoUploadError()
    const response = result as { data: unknown; error: unknown }
    if (response.error !== null) {
      const code =
        response.error &&
        typeof response.error === 'object' &&
        Object.hasOwn(response.error, 'code')
          ? (response.error as { code: unknown }).code
          : null
      throw photoUploadError(code === '40001' ? 'changed' : 'unavailable')
    }
    return response.data
  }
  function args(scope: { userId: string; cycleId: string; assetId: string }) {
    if (![scope.userId, scope.cycleId, scope.assetId].every((id) => uuid.safeParse(id).success))
      throw photoUploadError('input')
    return { p_user_id: scope.userId, p_cycle_id: scope.cycleId, p_asset_id: scope.assetId }
  }
  return {
    storageOrigin: options.storageOrigin,
    now: () => new Date(),
    nonce: () => randomUUID(),
    async prepare(scope, ticketId) {
      if (!uuid.safeParse(ticketId).success) throw photoUploadError('input')
      return parsePreparedPhotoUpload(
        await invoke('prepare_mobile_reevaluation_photo_upload', {
          ...args(scope),
          p_ticket_id: ticketId,
        }),
        scope,
        ticketId,
      )
    },
    async sign(asset) {
      try {
        const { data, error } = await supabase.storage
          .from(asset.bucket_id)
          .createSignedUploadUrl(asset.object_path, { upsert: false })
        if (
          error ||
          !data ||
          data.path !== asset.object_path ||
          data.token !== new URL(data.signedUrl).searchParams.get('token')
        )
          throw photoUploadError()
        return { signedUrl: data.signedUrl }
      } catch {
        throw photoUploadError()
      }
    },
    async register(prepared, expiresAt) {
      const { asset, ticket } = prepared
      const scope = { userId: asset.user_id, cycleId: asset.cycle_id, assetId: asset.id }
      return parseRegisteredPhotoUpload(
        await invoke('register_mobile_reevaluation_photo_upload_ticket', {
          ...args(scope),
          p_ticket_id: ticket.id,
          p_provider_expires_at: expiresAt,
        }),
        prepared,
        expiresAt,
      )
    },
    async current(scope) {
      const data = await invoke('get_mobile_reevaluation_photo_asset', args(scope))
      return data === null ? null : parseCurrentPhotoUpload(data, scope)
    },
  }
}
