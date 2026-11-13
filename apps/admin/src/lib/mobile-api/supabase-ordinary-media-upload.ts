import { randomUUID } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import {
  type OrdinaryMediaUploadDependencies,
  ordinaryMediaUploadError,
} from './ordinary-media-upload'

/** Called only through the trusted server rollout option. No caller-provided
 * origin, Storage token or ticket identity is accepted by the HTTP route. */
export function createSupabaseOrdinaryMediaUploadDependencies(
  client: ServiceClient,
  options: { storageOrigin: string },
): OrdinaryMediaUploadDependencies {
  const rpc = async (name: string, args: Record<string, unknown>): Promise<unknown> => {
    const api = client as unknown as {
      rpc(
        name: string,
        args: Record<string, unknown>,
      ): PromiseLike<{
        data: unknown
        error: { code?: string } | null
      }>
    }
    try {
      const result = await api.rpc(name, args)
      if (!result || result.error) throw ordinaryMediaUploadError(result?.error?.code === '40001')
      return result.data
    } catch (error) {
      // Never include PostgREST details, provider URLs or credentials.
      throw ordinaryMediaUploadError(
        error instanceof Error && 'status' in error && error.status === 409,
      )
    }
  }
  return {
    storageOrigin: options.storageOrigin,
    now: () => new Date(),
    nonce: randomUUID,
    prepare: (scope, ticketId) =>
      rpc('prepare_conversation_media_upload', {
        p_user_id: scope.userId,
        p_asset_id: scope.assetId,
        p_ticket_id: ticketId,
      }),
    register: (scope, ticketId, expiresAt) =>
      rpc('register_conversation_media_upload', {
        p_user_id: scope.userId,
        p_asset_id: scope.assetId,
        p_ticket_id: ticketId,
        p_provider_expires_at: expiresAt,
      }),
    current: (scope) =>
      rpc('get_conversation_media_upload_state', {
        p_user_id: scope.userId,
        p_asset_id: scope.assetId,
      }),
    async sign(asset) {
      const { data, error } = await client.storage
        .from(asset.bucket_id)
        .createSignedUploadUrl(asset.object_path, { upsert: false })
      if (
        error ||
        !data ||
        data.path !== asset.object_path ||
        typeof data.token !== 'string' ||
        new URL(data.signedUrl).searchParams.get('token') !== data.token
      )
        throw ordinaryMediaUploadError()
      return { signedUrl: data.signedUrl }
    },
  }
}
