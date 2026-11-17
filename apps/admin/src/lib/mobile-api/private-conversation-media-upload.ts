import {
  type ConversationMediaIdentityV2,
  type PrivateMediaAssetV2,
  PrivateMediaCatalogError,
  type PrivateMediaCatalogV2,
  privateMediaAssetV2Schema,
  privateMediaIdentityOfV2,
  privateMediaUploadPreparedV2Schema,
  privateMediaUploadRegisteredV2Schema,
  privateMediaUploadStateV2Schema,
} from '@mpp/core/conversation-media'
import type { MediaSignedUpload } from './media-service'
import { providerExpiry } from './ordinary-media-upload'

export interface PrivateConversationMediaUploadPorts {
  catalog: Pick<PrivateMediaCatalogV2, 'prepareUpload' | 'registerUpload' | 'uploadState'>
  storageOrigin: string
  now(): Date
  nonce(): string
  sign(identity: ConversationMediaIdentityV2): Promise<{ signedUrl: string }>
}

/** One tracked private source. An uncertain request is not retried here; its
 * pre-existing independent obligation remains available for byte revocation. */
export async function issuePrivateConversationMediaUpload(
  deps: PrivateConversationMediaUploadPorts,
  original: PrivateMediaAssetV2,
): Promise<MediaSignedUpload> {
  try {
    const source = privateMediaAssetV2Schema.parse(original)
    const identity = Object.freeze(privateMediaIdentityOfV2(source))
    const scope = Object.freeze({ userId: identity.user_id, assetId: identity.asset_id })
    const expected = JSON.stringify(identity)
    const sameSource = (value: {
      identity: ConversationMediaIdentityV2
      state: { created_at: string; retention_until: string }
    }) =>
      JSON.stringify(value.identity) === expected &&
      Date.parse(value.state.created_at) === Date.parse(source.created_at) &&
      Date.parse(value.state.retention_until) === Date.parse(source.retention_until)
    if (
      source.status !== 'pending_upload' ||
      Date.parse(source.retention_until) <= deps.now().getTime()
    )
      throw new PrivateMediaCatalogError('changed')
    const ticketId = deps.nonce()
    const prepared = privateMediaUploadPreparedV2Schema.parse(
      await deps.catalog.prepareUpload(scope, ticketId),
    )
    if (!sameSource(prepared.asset) || prepared.ticket.id !== ticketId)
      throw new PrivateMediaCatalogError('changed')
    const signed = await deps.sign(identity)
    const observedAt = deps.now().getTime()
    // Reuse the exact URL/expiry parser. This structural object is only input
    // to that pure parser, never a legacy catalog record or write authority.
    const expiry = providerExpiry(
      signed.signedUrl,
      {
        id: identity.asset_id,
        user_id: identity.user_id,
        kind: identity.kind,
        bucket_id: identity.bucket_id,
        object_path: identity.object_path,
        mime_type: identity.mime_type,
        size_bytes: identity.declared_size_bytes,
        status: source.status,
        retention_until: source.retention_until,
      },
      deps.storageOrigin,
    )
    const registered = privateMediaUploadRegisteredV2Schema.parse(
      await deps.catalog.registerUpload(scope, ticketId, expiry),
    )
    if (
      registered.ticket.id !== ticketId ||
      registered.ticket.user_id !== scope.userId ||
      registered.ticket.asset_id !== scope.assetId ||
      registered.ticket.prepared_at !== prepared.ticket.prepared_at ||
      Date.parse(registered.ticket.provider_expires_at ?? '') !== Date.parse(expiry)
    )
      throw new PrivateMediaCatalogError()
    // Persist the provider observation before clock/scope/expiry refusal.
    if (!Number.isFinite(observedAt) || Date.parse(expiry) > observedAt + 7320000)
      throw new PrivateMediaCatalogError()
    const raw = await deps.catalog.uploadState(scope)
    if (raw === null) throw new PrivateMediaCatalogError('changed')
    const current = privateMediaUploadStateV2Schema.parse(raw)
    const now = deps.now().getTime()
    if (
      !sameSource(current.asset) ||
      !Number.isFinite(now) ||
      Date.parse(expiry) <= now ||
      Date.parse(current.asset.state.retention_until) <= now
    )
      throw new PrivateMediaCatalogError('changed')
    return {
      signed_url: signed.signedUrl,
      method: 'PUT',
      headers: { 'Content-Type': identity.mime_type, 'x-upsert': 'false' },
      expires_at: expiry,
    }
  } catch (error) {
    throw error instanceof PrivateMediaCatalogError ? error : new PrivateMediaCatalogError()
  }
}
