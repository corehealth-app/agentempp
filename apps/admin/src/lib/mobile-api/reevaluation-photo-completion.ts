import { z } from 'zod'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  type PhotoUploadAsset,
  type PhotoUploadScope,
  reevaluationPhotoAssetWireSchema,
  reevaluationPhotoRevisionSchema,
} from './reevaluation-photo-upload'

const scopeSchema = z.object({ userId: uuid, cycleId: uuid, assetId: uuid }).strict()
const wireSchema = reevaluationPhotoAssetWireSchema
  .extend({
    source_revision: reevaluationPhotoRevisionSchema,
    selection_state: z.enum(['pending', 'selected']),
  })
  .strict()
const metadataSchema = z
  .object({
    size: z.number().int().min(1).max(15728640),
    contentType: z
      .string()
      .transform((value) => value.split(';', 1)[0].trim().toLowerCase())
      .pipe(z.enum(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])),
    etag: z
      .string()
      .min(1)
      .max(256)
      .refine((value) =>
        [...value].every((char) => {
          const code = char.charCodeAt(0)
          return code > 31 && (code < 127 || code > 159)
        }),
      )
      .nullable(),
  })
  .strict()
export type PhotoCompletionWire = z.infer<typeof wireSchema>
export type PhotoCompletionMetadata = z.infer<typeof metadataSchema>
export interface ReevaluationPhotoCompletionDependencies {
  current(scope: PhotoUploadScope): Promise<unknown>
  info(asset: PhotoUploadAsset): Promise<unknown>
  commit(prepared: PhotoCompletionWire, metadata: PhotoCompletionMetadata): Promise<unknown>
}
export function photoCompletionError(
  kind: 'unavailable' | 'changed' | 'metadata' | 'input' = 'unavailable',
) {
  return new MobileApiError(
    kind === 'changed' ? 409 : kind === 'metadata' || kind === 'input' ? 422 : 503,
    `mobile_reevaluation_photo_completion_${kind}`,
    'Photo completion is unavailable',
  )
}
export function parsePhotoCompletionWire(value: unknown, scope: PhotoUploadScope) {
  const result = wireSchema.safeParse(value)
  if (!result.success) throw photoCompletionError()
  const w = result.data
  if (
    w.asset.id !== scope.assetId ||
    w.asset.user_id !== scope.userId ||
    w.asset.cycle_id !== scope.cycleId ||
    (w.selection_state === 'pending'
      ? w.asset.status !== 'pending_upload'
      : !['uploaded', 'processing', 'processed'].includes(w.asset.status))
  )
    throw photoCompletionError()
  return w
}
export function parsePhotoCompletionMetadata(value: unknown) {
  const result = metadataSchema.safeParse(value)
  if (!result.success) throw photoCompletionError('metadata')
  return result.data
}
function identity(asset: PhotoUploadAsset) {
  const { status: _status, retention_until: _retention, ...identity } = asset
  return identity
}
export function parsePhotoCompletionReceipt(value: unknown, before: PhotoCompletionWire) {
  const after = parsePhotoCompletionWire(value, {
    userId: before.asset.user_id,
    cycleId: before.asset.cycle_id,
    assetId: before.asset.id,
  })
  const pending = before.selection_state === 'pending'
  if (
    after.selection_state !== 'selected' ||
    JSON.stringify(identity(before.asset)) !== JSON.stringify(identity(after.asset)) ||
    BigInt(after.source_revision) !== BigInt(before.source_revision) + (pending ? 1n : 0n) ||
    (pending
      ? BigInt(after.cycle_revision) <= BigInt(before.cycle_revision)
      : BigInt(after.cycle_revision) < BigInt(before.cycle_revision)) ||
    (pending && after.asset.status !== 'uploaded')
  )
    throw photoCompletionError()
  return after
}

/** Metadata only. Byte signature/provider pose and clinical confirmation are
 * separate later gates. No public route consumes this before full lifecycle. */
export async function completeReevaluationPhotoUpload(
  deps: ReevaluationPhotoCompletionDependencies,
  input: PhotoUploadScope,
) {
  const scope = scopeSchema.safeParse(input)
  if (!scope.success) throw photoCompletionError('input')
  try {
    const prepared = parsePhotoCompletionWire(await deps.current(scope.data), scope.data)
    const metadata = parsePhotoCompletionMetadata(await deps.info(prepared.asset))
    if (
      metadata.size !== prepared.asset.size_bytes ||
      metadata.contentType !== prepared.asset.mime_type
    )
      throw photoCompletionError('metadata')
    return parsePhotoCompletionReceipt(await deps.commit(prepared, metadata), prepared)
  } catch (error) {
    throw photoCompletionError(
      error instanceof MobileApiError && error.status === 409
        ? 'changed'
        : error instanceof MobileApiError && error.status === 422
          ? 'metadata'
          : 'unavailable',
    )
  }
}
