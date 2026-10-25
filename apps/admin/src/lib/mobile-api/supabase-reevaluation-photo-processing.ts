import type { ServiceClient } from '@mpp/db'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  type ReevaluationPhotoContext,
  resolveReevaluationPhotoCandidate,
} from './reevaluation-photo-candidate'
import {
  type PhotoProcessingScope,
  type PhotoProcessingWire,
  parsePhotoProcessingContinuation,
  parsePhotoProcessingReading,
  parsePhotoProcessingWire,
  photoProcessingError,
  type ReevaluationPhotoProcessingDependencies,
} from './reevaluation-photo-processing'
import { reevaluationPhotoAssetWireSchema } from './reevaluation-photo-upload'

/** No client creation or registration. The analyzer is preconfigured by the
 * caller before any SQL authorization; this adapter never starts a provider. */
export function createSupabaseReevaluationPhotoProcessingDependencies(
  client: ServiceClient,
  options: { analyze: ReevaluationPhotoProcessingDependencies['analyze']; now?: () => Date },
): ReevaluationPhotoProcessingDependencies & {
  resolveCandidate(
    expected: ReevaluationPhotoContext,
  ): Promise<ReturnType<typeof resolveReevaluationPhotoCandidate>>
} {
  const rpc = client.rpc.bind(client) as unknown as (
    name: string,
    args: Record<string, unknown>,
  ) => PromiseLike<unknown>
  function args(scope: PhotoProcessingScope) {
    if (
      ![scope.userId, scope.cycleId, scope.assetId, scope.requestId].every(
        (id) => uuid.safeParse(id).success,
      )
    )
      throw photoProcessingError()
    return {
      p_user_id: scope.userId,
      p_cycle_id: scope.cycleId,
      p_asset_id: scope.assetId,
      p_request_id: scope.requestId,
    }
  }
  function scope(wire: PhotoProcessingWire): PhotoProcessingScope {
    return {
      userId: wire.asset.user_id,
      cycleId: wire.asset.cycle_id,
      assetId: wire.asset.id,
      requestId: wire.attempt.id,
    }
  }
  async function invoke(name: string, params: Record<string, unknown>) {
    let value: unknown
    try {
      value = await rpc(name, params)
    } catch {
      throw photoProcessingError()
    }
    if (
      !value ||
      typeof value !== 'object' ||
      Array.isArray(value) ||
      !Object.hasOwn(value, 'data') ||
      !Object.hasOwn(value, 'error')
    )
      throw photoProcessingError()
    const response = value as { data: unknown; error: unknown }
    if (response.error !== null) {
      const code =
        response.error &&
        typeof response.error === 'object' &&
        Object.hasOwn(response.error, 'code')
          ? (response.error as { code: unknown }).code
          : null
      throw photoProcessingError(code === '40001' || code === 'P0002')
    }
    return response.data
  }
  return {
    now: options.now ?? (() => new Date()),
    analyze: options.analyze,
    async claim(input) {
      const data = await invoke('claim_mobile_reevaluation_photo_processing', args(input))
      return data === null ? null : parsePhotoProcessingWire(data, input)
    },
    async download(asset) {
      if (!reevaluationPhotoAssetWireSchema.shape.asset.safeParse(asset).success)
        throw photoProcessingError()
      try {
        const { data, error } = await client.storage
          .from(asset.bucket_id)
          .download(asset.object_path)
        if (
          error ||
          !data ||
          data.size !== asset.size_bytes ||
          typeof data.arrayBuffer !== 'function'
        )
          throw photoProcessingError()
        const buffer = await data.arrayBuffer()
        if (!(buffer instanceof ArrayBuffer) || buffer.byteLength !== asset.size_bytes)
          throw photoProcessingError()
        return new Uint8Array(buffer)
      } catch {
        throw photoProcessingError()
      }
    },
    async authorize(before) {
      const input = scope(before)
      const checked = parsePhotoProcessingWire(before, input)
      if (checked.attempt.status !== 'claimed') throw photoProcessingError()
      const data = await invoke('authorize_mobile_reevaluation_photo_provider', args(input))
      return data === null ? null : parsePhotoProcessingContinuation(data, checked, 'authorized')
    },
    async complete(before, reading) {
      const input = scope(before)
      const checked = parsePhotoProcessingWire(before, input)
      const result = parsePhotoProcessingReading(reading, checked.asset.pose)
      if (checked.attempt.status !== 'authorized' || result === null) throw photoProcessingError()
      return parsePhotoProcessingContinuation(
        await invoke('complete_mobile_reevaluation_photo_processing', {
          ...args(input),
          p_result: result,
        }),
        checked,
        'succeeded',
        result,
      )
    },
    async fail(before, code) {
      const input = scope(before)
      parsePhotoProcessingWire(before, input)
      const result = await invoke('fail_mobile_reevaluation_photo_processing', {
        ...args(input),
        p_failure_code: code,
      })
      if (typeof result !== 'boolean') throw photoProcessingError()
      return result
    },
    async resolveCandidate(expected) {
      if (![expected.userId, expected.cycleId].every((id) => uuid.safeParse(id).success))
        throw photoProcessingError()
      const snapshot = await invoke('get_mobile_reevaluation_photo_snapshot', {
        p_user_id: expected.userId,
        p_cycle_id: expected.cycleId,
      })
      return resolveReevaluationPhotoCandidate(expected, snapshot)
    },
  }
}
