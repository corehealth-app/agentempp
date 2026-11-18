import {
  PrivateMediaCatalogError,
  type PrivateMediaCatalogV2,
  privateMediaAssetV2Schema,
  privateMediaIdentityOfV2,
  privateMediaProcessingClaimV2Schema,
} from '@mpp/core/conversation-media'
import { parseConversationImageResult } from '@mpp/providers'
import { z } from 'zod'
import {
  MAX_AUDIO_DURATION_SECONDS,
  measureAudioDurationFromContainer,
  mediaSignatureMatches,
} from '../lib/media-container.js'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const inputSchema = z
  .object({ userId: uuid, assetId: uuid, requestId: z.string().regex(/^[0-9a-f]{64}$/) })
  .strict()
const transcription = z
  .object({
    text: z.string().trim().min(1).max(32000),
    language: z.string().min(1).max(80).optional(),
    duration: z.number().finite().nonnegative().max(MAX_AUDIO_DURATION_SECONDS).optional(),
    latencyMs: z.number().finite().nonnegative(),
  })
  .strip()

export interface PrivateConversationMediaProcessingPorts {
  catalog: Pick<
    PrivateMediaCatalogV2,
    'claimProcessing' | 'findOwned' | 'completeProcessing' | 'failProcessing'
  >
  storage: { download(bucketId: string, objectPath: string): Promise<Uint8Array> }
  providers: {
    analyzeImage(input: {
      bytes: Uint8Array
      mimeType: string
      contextText: string | null
    }): Promise<unknown>
    transcribeAudio(input: { bytes: Uint8Array; mimeType: string }): Promise<unknown>
  }
  now(): Date
  measureAudioDuration?(input: { bytes: Uint8Array; mimeType: string }): Promise<number | null>
}
type ProcessingOutcome =
  | { status: 'processed' | 'skipped' }
  | { status: 'busy'; retry_at: string }
  | { status: 'failed'; reason: string }

/** Inert until the private-source routes and disposition worker are qualified.
 * Only observations are stored here: no meal, workout, XP or assessment writer.
 * A busy lease must be deferred by the caller, never treated as job completion. */
export async function processPrivateConversationMedia(
  deps: PrivateConversationMediaProcessingPorts,
  raw: z.infer<typeof inputSchema>,
): Promise<ProcessingOutcome> {
  try {
    const input = inputSchema.parse(raw)
    const scope = { userId: input.userId, assetId: input.assetId }
    const claim = privateMediaProcessingClaimV2Schema.parse(
      await deps.catalog.claimProcessing(scope, input.requestId),
    )
    if (claim.action === 'unavailable') return { status: 'skipped' }
    if (claim.action === 'busy') return { status: 'busy', retry_at: claim.retry_at }
    const identity = claim.asset.identity
    if (
      identity.user_id !== input.userId ||
      identity.asset_id !== input.assetId ||
      claim.asset.processing_request_id !== input.requestId
    )
      throw new PrivateMediaCatalogError()
    const leaseOpen = () => {
      const at = deps.now().getTime()
      if (!Number.isFinite(at)) throw new PrivateMediaCatalogError()
      return (
        at < Date.parse(claim.claim.lease_until) &&
        at < Date.parse(claim.asset.state.retention_until)
      )
    }
    if (!leaseOpen()) return { status: 'busy', retry_at: claim.claim.lease_until }
    const fail = async (reason: string): Promise<ProcessingOutcome> =>
      (await deps.catalog.failProcessing(scope, input.requestId, claim.claim.token, reason))
        ? { status: 'failed', reason }
        : { status: 'skipped' }
    let bytes: Uint8Array
    try {
      bytes = await deps.storage.download(identity.bucket_id, identity.object_path)
    } catch {
      return await fail('storage_download_error')
    }
    if (!(bytes instanceof Uint8Array) || bytes.byteLength !== identity.declared_size_bytes)
      return await fail('media_size_mismatch')
    if (!mediaSignatureMatches(bytes, identity.mime_type))
      return await fail('invalid_file_signature')
    if (identity.kind === 'audio_note') {
      let seconds: number | null
      try {
        seconds = await (deps.measureAudioDuration ?? measureAudioDurationFromContainer)({
          bytes,
          mimeType: identity.mime_type,
        })
      } catch {
        seconds = null
      }
      if (seconds === null || !Number.isFinite(seconds) || seconds <= 0)
        return await fail('audio_duration_unreadable')
      if (seconds > MAX_AUDIO_DURATION_SECONDS) return await fail('audio_too_long')
    }
    // Refuse a removed or changed source before spending on interpretation.
    // Completion still checks the exact live token atomically after the model.
    const current = await deps.catalog.findOwned(scope)
    if (current === null) return { status: 'skipped' }
    const source = privateMediaAssetV2Schema.parse(current)
    if (
      JSON.stringify(privateMediaIdentityOfV2(source)) !== JSON.stringify(identity) ||
      source.status !== 'processing' ||
      source.processing_request_id !== input.requestId ||
      source.actual_size_bytes !== bytes.byteLength ||
      source.context_text !== claim.asset.context_text ||
      Date.parse(source.created_at) !== Date.parse(claim.asset.state.created_at) ||
      Date.parse(source.retention_until) !== Date.parse(claim.asset.state.retention_until)
    )
      return { status: 'skipped' }
    if (!leaseOpen()) return { status: 'busy', retry_at: claim.claim.lease_until }
    let result: unknown
    try {
      result =
        identity.kind === 'audio_note'
          ? transcription.parse(
              await deps.providers.transcribeAudio({ bytes, mimeType: identity.mime_type }),
            )
          : parseConversationImageResult(
              await deps.providers.analyzeImage({
                bytes,
                mimeType: identity.mime_type,
                contextText: claim.asset.context_text,
              }),
            )
    } catch {
      return await fail('provider_error')
    }
    // Never mark failure after an uncertain completion: it may have committed.
    // This function performs no retry of either provider or database operation.
    return (await deps.catalog.completeProcessing(
      scope,
      input.requestId,
      claim.claim.token,
      result,
    ))
      ? { status: 'processed' }
      : { status: 'skipped' }
  } catch (error) {
    throw error instanceof PrivateMediaCatalogError ? error : new PrivateMediaCatalogError()
  }
}
