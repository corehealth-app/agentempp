import { randomUUID } from 'node:crypto'
import {
  conversationMediaUploadTicketsEnabled,
  conversationPhotoMobileEnabled,
} from '@mpp/core/conversation-photo-purpose'
import type { MediaUploadInput } from './contracts'
import { MobileApiError, mobileSuccess } from './http'
import { createVersionedConversationMediaUpload } from './private-conversation-media-api'
import { issuePrivateConversationMediaUpload } from './private-conversation-media-upload'
import type { MobileRouteContext } from './route'
import { createSupabasePrivateConversationMedia } from './supabase-private-conversation-media'

/** Trusted staging opt-in; request JSON/header never selects the catalog. */
export function privateConversationMediaCatalogEnabled(
  env: Readonly<Record<string, string | undefined>> = process.env,
) {
  return (
    env.MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED === 'true' &&
    conversationMediaUploadTicketsEnabled(env)
  )
}

export async function versionedMediaUploadResponse(
  context: MobileRouteContext,
  input: MediaUploadInput,
  legacy: () => Promise<Response>,
  env: Readonly<Record<string, string | undefined>> = process.env,
): Promise<Response> {
  if (
    !privateConversationMediaCatalogEnabled(env) ||
    !['conversation_photo', 'audio_note'].includes(input.kind)
  )
    return legacy()
  try {
    const source = createSupabasePrivateConversationMedia(context.supabase, {
      storageOrigin: new URL(env.NEXT_PUBLIC_SUPABASE_URL ?? '').origin,
    })
    const api = context.supabase as unknown as {
      rpc(
        name: string,
        args: Record<string, unknown>,
      ): { abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }> }
    }
    const result = await createVersionedConversationMediaUpload(
      {
        enabled: () => privateConversationMediaCatalogEnabled(env),
        photoEnabled: () => conversationPhotoMobileEnabled(env),
        now: () => new Date(),
        nonce: randomUUID,
        catalog: source.catalog,
        issue: (asset) => issuePrivateConversationMediaUpload(source.uploads, asset),
        async resolve(userId, sourceRequestHash) {
          const result = await api
            .rpc('resolve_conversation_media_catalog_v2', {
              p_user_id: userId,
              p_asset_id: null,
              p_source_request_hash: sourceRequestHash,
            })
            .abortSignal(AbortSignal.timeout(15_000))
          if (!result || result.error !== null) throw Error('Media catalog unavailable')
          return result.data
        },
      },
      context.auth.userId,
      input,
      context.request.headers.get('idempotency-key') ?? '',
    )
    if (result.action === 'legacy') return legacy()
    return mobileSuccess(result.value, context.requestId, 201)
  } catch (error) {
    if (error instanceof MobileApiError) throw error
    throw new MobileApiError(503, 'media_catalog_unavailable', 'Media upload unavailable')
  }
}
