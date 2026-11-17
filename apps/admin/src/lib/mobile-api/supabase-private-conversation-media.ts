import { randomUUID } from 'node:crypto'
import {
  conversationMediaIdentityV2Schema,
  createPrivateMediaCatalogV2,
  PrivateMediaCatalogError,
} from '@mpp/core/conversation-media'
import type { ServiceClient } from '@mpp/db'
import type { PrivateConversationMediaUploadPorts } from './private-conversation-media-upload'

/** Uses the existing server client. This constructor does not create credentials,
 * enable routes, mirror public rows or retry a possibly committed operation. */
export function createSupabasePrivateConversationMedia(
  client: ServiceClient,
  options: { storageOrigin: string; now?: () => Date; nonce?: () => string },
) {
  try {
    const origin = new URL(options.storageOrigin)
    if (
      origin.protocol !== 'https:' ||
      origin.origin !== options.storageOrigin ||
      origin.username ||
      origin.password
    )
      throw new PrivateMediaCatalogError()
  } catch {
    throw new PrivateMediaCatalogError()
  }
  const api = client as unknown as {
    rpc(
      name: string,
      args: Record<string, unknown>,
    ): {
      abortSignal(
        signal: AbortSignal,
      ): PromiseLike<{ data: unknown; error: { code?: string } | null }>
    }
  }
  const catalog = createPrivateMediaCatalogV2(async (name, args) => {
    const result = await api.rpc(name, args).abortSignal(AbortSignal.timeout(15_000))
    return { data: result.data, error: result.error ? { code: result.error.code } : null }
  })
  const uploads: PrivateConversationMediaUploadPorts = {
    catalog,
    storageOrigin: options.storageOrigin,
    now: options.now ?? (() => new Date()),
    nonce: options.nonce ?? randomUUID,
    async sign(raw) {
      try {
        const identity = conversationMediaIdentityV2Schema.parse(raw)
        const { data, error } = await client.storage
          .from(identity.bucket_id)
          .createSignedUploadUrl(identity.object_path, { upsert: false })
        if (
          error ||
          !data ||
          data.path !== identity.object_path ||
          typeof data.token !== 'string' ||
          new URL(data.signedUrl).searchParams.get('token') !== data.token
        )
          throw new PrivateMediaCatalogError()
        return { signedUrl: data.signedUrl }
      } catch {
        throw new PrivateMediaCatalogError()
      }
    },
  }
  return { catalog, uploads }
}
