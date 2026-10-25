import type { ServiceClient } from '@mpp/db'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  parsePhotoCompletionMetadata,
  parsePhotoCompletionReceipt,
  parsePhotoCompletionWire,
  photoCompletionError,
  type ReevaluationPhotoCompletionDependencies,
} from './reevaluation-photo-completion'
import {
  type PhotoUploadScope,
  reevaluationPhotoAssetWireSchema,
} from './reevaluation-photo-upload'

/** Backend-only metadata adapter. No client creation, route or generic fallback. */
export function createSupabaseReevaluationPhotoCompletionDependencies(
  supabase: ServiceClient,
): ReevaluationPhotoCompletionDependencies {
  const rpc = supabase.rpc.bind(supabase) as unknown as (
    name: string,
    args: Record<string, string | number | null>,
  ) => PromiseLike<unknown>
  function args(scope: PhotoUploadScope) {
    if (![scope.userId, scope.cycleId, scope.assetId].every((id) => uuid.safeParse(id).success))
      throw photoCompletionError('input')
    return { p_user_id: scope.userId, p_cycle_id: scope.cycleId, p_asset_id: scope.assetId }
  }
  async function invoke(name: string, params: Record<string, string | number | null>) {
    let value: unknown
    try {
      value = await rpc(name, params)
    } catch {
      throw photoCompletionError()
    }
    if (
      !value ||
      typeof value !== 'object' ||
      Array.isArray(value) ||
      !Object.hasOwn(value, 'data') ||
      !Object.hasOwn(value, 'error')
    )
      throw photoCompletionError()
    const response = value as { data: unknown; error: unknown }
    if (response.error !== null) {
      const code =
        response.error &&
        typeof response.error === 'object' &&
        Object.hasOwn(response.error, 'code')
          ? (response.error as { code: unknown }).code
          : null
      throw photoCompletionError(
        code === '40001' || code === 'P0002'
          ? 'changed'
          : code === '22023'
            ? 'metadata'
            : 'unavailable',
      )
    }
    return response.data
  }
  return {
    async current(scope) {
      return parsePhotoCompletionWire(
        await invoke('get_mobile_reevaluation_photo_upload_completion', args(scope)),
        scope,
      )
    },
    async info(asset) {
      const checked = reevaluationPhotoAssetWireSchema.shape.asset.safeParse(asset)
      if (!checked.success) throw photoCompletionError()
      let value: unknown
      try {
        value = await supabase.storage.from(asset.bucket_id).info(asset.object_path)
      } catch {
        throw photoCompletionError()
      }
      if (
        !value ||
        typeof value !== 'object' ||
        Array.isArray(value) ||
        !Object.hasOwn(value, 'data') ||
        !Object.hasOwn(value, 'error')
      )
        throw photoCompletionError()
      const response = value as { data: unknown; error: unknown }
      if (response.error !== null) {
        const error = response.error as { status?: unknown; statusCode?: unknown } | null
        const status =
          error && typeof error === 'object' ? Number(error.status ?? error.statusCode) : null
        throw photoCompletionError(status === 400 || status === 404 ? 'changed' : 'unavailable')
      }
      if (response.data === null) throw photoCompletionError('changed')
      // Storage may add harmless SDK metadata; consume only the three explicit
      // fields. Neither ETag nor MIME validates the actual image/pose.
      if (!response.data || typeof response.data !== 'object' || Array.isArray(response.data))
        throw photoCompletionError('metadata')
      const data = response.data as { size?: unknown; contentType?: unknown; etag?: unknown }
      return parsePhotoCompletionMetadata({
        size: data.size,
        contentType: data.contentType,
        etag: data.etag ?? null,
      })
    },
    async commit(before, inputMetadata) {
      const scope = {
        userId: before.asset.user_id,
        cycleId: before.asset.cycle_id,
        assetId: before.asset.id,
      }
      const prepared = parsePhotoCompletionWire(before, scope)
      const metadata = parsePhotoCompletionMetadata(inputMetadata)
      return parsePhotoCompletionReceipt(
        await invoke('complete_mobile_reevaluation_photo_upload', {
          ...args(scope),
          p_expected_source_revision: prepared.source_revision,
          p_actual_size_bytes: metadata.size,
          p_content_type: metadata.contentType,
          p_etag: metadata.etag,
        }),
        prepared,
      )
    },
  }
}
