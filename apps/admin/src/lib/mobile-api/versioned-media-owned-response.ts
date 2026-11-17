import {
  conversationMediaUploadTicketsEnabled,
  conversationPhotoMobileEnabled,
} from '@mpp/core/conversation-photo-purpose'
import { MobileApiError, mobileSuccess } from './http'
import { ownedConversationMediaOperation } from './private-conversation-media-owned'
import type { MobileRouteContext } from './route'
import { createSupabasePrivateConversationMedia } from './supabase-private-conversation-media'

/** Request-owned opt-in, same qualified staging gates as creation. Resolving a
 * catalog version never depends on a caller's kind or on a public lookup miss. */
export async function versionedOwnedMediaResponse(
  context: MobileRouteContext,
  assetId: string,
  operation: 'read' | 'complete' | 'process',
  legacy: () => Promise<Response>,
  env: Readonly<Record<string, string | undefined>> = process.env,
  processing?: {
    requestKey: string
    enqueue(input: { userId: string; assetId: string; requestId: string }): Promise<void>
  },
): Promise<Response> {
  const enabled = () =>
    env.MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED === 'true' &&
    conversationMediaUploadTicketsEnabled(env)
  if (!enabled()) return legacy()
  try {
    const storageOrigin = new URL(env.NEXT_PUBLIC_SUPABASE_URL ?? '').origin
    const source = createSupabasePrivateConversationMedia(context.supabase, { storageOrigin })
    const api = context.supabase as unknown as {
      rpc(
        name: string,
        args: Record<string, unknown>,
      ): {
        abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }>
      }
    }
    async function rpc(name: string, args: Record<string, unknown>) {
      const reply = await api.rpc(name, args).abortSignal(AbortSignal.timeout(15_000))
      if (!reply || reply.error !== null) throw Error('Private media unavailable')
      return reply.data
    }
    const result = await ownedConversationMediaOperation(
      {
        enabled,
        photoEnabled: () => conversationPhotoMobileEnabled(env),
        now: () => new Date(),
        storageOrigin,
        catalog: source.catalog,
        ...(processing ? { enqueue: processing.enqueue } : {}),
        resolve: (userId, id) =>
          rpc('resolve_conversation_media_catalog_v2', {
            p_user_id: userId,
            p_asset_id: id,
            p_source_request_hash: null,
          }),
        async info(identity) {
          const reply = await context.supabase.storage
            .from(identity.bucket_id)
            .info(identity.object_path)
          if (reply.error) {
            const status = (reply.error as { statusCode?: unknown }).statusCode
            if (status === 404 || status === '404') return null
            throw Error('Private Storage unavailable')
          }
          if (!reply.data || typeof reply.data.size !== 'number')
            throw Error('Private Storage unavailable')
          return {
            size: reply.data.size,
            contentType: reply.data.contentType ?? null,
            etag: reply.data.etag ?? null,
          }
        },
        async signDownload(identity, seconds) {
          const reply = await context.supabase.storage
            .from(identity.bucket_id)
            .createSignedUrl(identity.object_path, seconds, { download: false })
          if (reply.error || !reply.data) throw Error('Private Storage unavailable')
          return { signedUrl: reply.data.signedUrl }
        },
        async close(userId, id) {
          return (
            (await rpc('close_conversation_media_v2', { p_user_id: userId, p_asset_id: id })) ===
            true
          )
        },
      },
      context.auth.userId,
      assetId,
      operation,
      processing?.requestKey,
    )
    if (result.action === 'legacy') return legacy()
    return mobileSuccess(result.value, context.requestId, operation === 'process' ? 202 : 200)
  } catch (error) {
    if (error instanceof MobileApiError) throw error
    throw new MobileApiError(503, 'media_catalog_unavailable', 'Media operation unavailable')
  }
}
