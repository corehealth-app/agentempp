import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import {
  reevaluationPhotoAssetWireSchema,
  reevaluationPhotoRevisionSchema,
} from './reevaluation-photo-upload'

/** Public policy, not an estimate of remaining private usage. SQL is authority. */
export const REEVALUATION_PHOTO_QUOTA = Object.freeze({ max_new_photos: 6, window_seconds: 86400 })
const requestSchema = z
  .object({
    cycleId: uuid,
    expectedRevision: reevaluationPhotoRevisionSchema,
    acceptanceId: uuid,
    pose: z.enum(['front', 'side', 'back']),
    mimeType: z.enum(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
    sizeBytes: z.number().int().min(1).max(15728640),
    requestKey: uuid,
  })
  .strict()
export type ReevaluationPhotoAllocationRequest = z.infer<typeof requestSchema>
type Failure =
  | 'invalid_input'
  | 'identity_invalid'
  | 'state_changed'
  | 'quota_reached'
  | 'unavailable'
  | 'invalid_response'
const errorStatuses = {
  invalid_input: 422,
  identity_invalid: 403,
  state_changed: 409,
  quota_reached: 429,
  unavailable: 503,
  invalid_response: 500,
} as const
const ownedErrors = new WeakSet<MobileApiError>()
export function photoAllocationFailure(kind: Failure): MobileApiError {
  const error = new MobileApiError(
    errorStatuses[kind],
    `mobile_reevaluation_photo_allocation_${kind}`,
    kind === 'quota_reached'
      ? 'Você atingiu o limite de 6 novas fotos em 24 horas.'
      : 'Não foi possível preparar esta foto agora.',
    kind === 'quota_reached' ? REEVALUATION_PHOTO_QUOTA : undefined,
  )
  ownedErrors.add(error)
  return error
}
export function sanitizePhotoAllocationFailure(error: unknown): MobileApiError {
  return error instanceof MobileApiError && ownedErrors.has(error)
    ? error
    : photoAllocationFailure('unavailable')
}
export function parsePhotoAllocationRequest(input: unknown): ReevaluationPhotoAllocationRequest {
  const parsed = requestSchema.safeParse(input)
  if (!parsed.success) throw photoAllocationFailure('invalid_input')
  return {
    ...parsed.data,
    cycleId: parsed.data.cycleId.toLowerCase(),
    acceptanceId: parsed.data.acceptanceId.toLowerCase(),
    requestKey: parsed.data.requestKey.toLowerCase(),
  }
}
export function parsePhotoAllocationResponse(
  value: unknown,
  userId: string,
  request: ReevaluationPhotoAllocationRequest,
) {
  // A replaced allocation can have no currently usable source. Never allocate
  // another automatically, and never let a stale replay retake the source.
  if (value === null) throw photoAllocationFailure('state_changed')
  const parsed = reevaluationPhotoAssetWireSchema.safeParse(value)
  if (!parsed.success) throw photoAllocationFailure('invalid_response')
  const { asset, cycle_revision } = parsed.data
  if (
    asset.user_id !== userId.toLowerCase() ||
    asset.cycle_id !== request.cycleId ||
    asset.consent_acceptance_id !== request.acceptanceId ||
    asset.pose !== request.pose ||
    asset.mime_type !== request.mimeType ||
    asset.size_bytes !== request.sizeBytes ||
    asset.status === 'deleted' ||
    asset.retention_until <= asset.created_at ||
    BigInt(cycle_revision) < BigInt(request.expectedRevision)
  )
    throw photoAllocationFailure('invalid_response')
  return parsed.data
}
export interface ReevaluationPhotoAllocationRepository {
  allocate(userId: string, request: unknown): Promise<unknown>
}
export interface ReevaluationPhotoAllocationDependencies {
  readonly enabled: boolean
  readonly repository: ReevaluationPhotoAllocationRepository
}
function authenticatedOwner(auth: MobileAuthContext): string {
  const ids = [
    auth?.userId,
    auth?.authUserId,
    auth?.identity?.id,
    auth?.patient?.id,
    auth?.patient?.authUserId,
  ]
  if (
    ids.some((id) => !uuid.safeParse(id).success) ||
    auth.userId.toLowerCase() !== auth.patient.id.toLowerCase() ||
    auth.authUserId.toLowerCase() !== auth.identity.id.toLowerCase() ||
    auth.authUserId.toLowerCase() !== auth.patient.authUserId.toLowerCase() ||
    auth.patient.status !== 'active'
  )
    throw photoAllocationFailure('identity_invalid')
  return auth.userId.toLowerCase()
}

/** Injected and dormant: no route, default dependency, provider or upload call. */
export async function allocateReevaluationPhoto(
  auth: MobileAuthContext,
  input: unknown,
  dependencies: ReevaluationPhotoAllocationDependencies,
) {
  const userId = authenticatedOwner(auth)
  const request = parsePhotoAllocationRequest(input)
  if (dependencies.enabled !== true)
    return { availability: 'unavailable', reason: 'disabled' } as const
  try {
    return {
      availability: 'available',
      ...parsePhotoAllocationResponse(
        await dependencies.repository.allocate(userId, request),
        userId,
        request,
      ),
    } as const
  } catch (error) {
    throw sanitizePhotoAllocationFailure(error)
  }
}
