import {
  drainReevaluationPhotoDisposition,
  type ReevaluationPhotoDispositionOutcome,
  type ReevaluationPhotoDispositionScope,
} from '@mpp/agent/reevaluation-photo-disposition'
import { createReevaluationPhotoDispositionDependencies } from '@mpp/agent/supabase-reevaluation-photo-disposition'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import {
  allocateReevaluationPhoto,
  parsePhotoAllocationResponse,
  REEVALUATION_PHOTO_QUOTA,
} from './reevaluation-photo-allocation'
import {
  parseReevaluationPhotoSnapshot,
  resolveReevaluationPhotoCandidate,
} from './reevaluation-photo-candidate'
import {
  completeReevaluationPhotoUpload,
  parsePhotoCompletionWire,
} from './reevaluation-photo-completion'
import {
  type PhotoProcessingScope,
  processReevaluationPhoto,
  type ReevaluationPhotoProcessingDependencies,
} from './reevaluation-photo-processing'
import {
  issueReevaluationPhotoUpload,
  type PhotoUploadAsset,
  type PhotoUploadScope,
  reevaluationPhotoAssetWireSchema,
  reevaluationPhotoRevisionSchema as revision,
} from './reevaluation-photo-upload'
import { createSupabaseReevaluationPhotoAllocationRepository } from './supabase-reevaluation-photo-allocation'
import { createSupabaseReevaluationPhotoCompletionDependencies } from './supabase-reevaluation-photo-completion'
import { createSupabaseReevaluationPhotoProcessingDependencies } from './supabase-reevaluation-photo-processing'
import { createSupabaseReevaluationPhotoUploadDependencies } from './supabase-reevaluation-photo-upload'

type Scope = { userId: string; cycleId: string }
const poses = ['front', 'side', 'back'] as const
export const reevaluationPhotoAllocateInput = z
  .object({
    expectedRevision: revision,
    acceptanceId: uuid,
    pose: z.enum(poses),
    mimeType: z.enum(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
    sizeBytes: z.number().int().min(1).max(15728640),
  })
  .strict()
export const reevaluationPhotoDiscardInput = z
  .object({ acceptanceId: uuid, expectedRevision: revision })
  .strict()
export interface ReevaluationPhotoLifecycleOperations {
  snapshot(scope: Scope): Promise<unknown>
  allocate(auth: MobileAuthContext, input: unknown): ReturnType<typeof allocateReevaluationPhoto>
  upload(scope: PhotoUploadScope): ReturnType<typeof issueReevaluationPhotoUpload>
  complete(scope: PhotoUploadScope): ReturnType<typeof completeReevaluationPhotoUpload>
  process(scope: PhotoProcessingScope): ReturnType<typeof processReevaluationPhoto>
  discard(scope: Scope, input: z.infer<typeof reevaluationPhotoDiscardInput>): Promise<unknown>
  drain(scope: ReevaluationPhotoDispositionScope): Promise<ReevaluationPhotoDispositionOutcome>
}
export function photoLifecycleError(
  kind: 'input' | 'changed' | 'busy' | 'quota' | 'unavailable' = 'unavailable',
) {
  return new MobileApiError(
    kind === 'input'
      ? 422
      : kind === 'changed' || kind === 'busy'
        ? 409
        : kind === 'quota'
          ? 429
          : 503,
    `mobile_reevaluation_photo_${kind}`,
    'Reassessment photo operation is unavailable',
    kind === 'quota' ? REEVALUATION_PHOTO_QUOTA : undefined,
  )
}
async function safe<T>(operation: () => Promise<T>): Promise<T> {
  try {
    return await operation()
  } catch (error) {
    throw photoLifecycleError(
      error instanceof MobileApiError && error.status === 409
        ? 'changed'
        : error instanceof MobileApiError && error.status === 429
          ? 'quota'
          : error instanceof MobileApiError && error.status === 422
            ? 'input'
            : 'unavailable',
    )
  }
}
function parse<T>(schema: z.ZodType<T>, input: unknown): T {
  const value = schema.safeParse(input)
  if (!value.success) throw photoLifecycleError('input')
  return value.data
}
function scope(auth: MobileAuthContext, cycleId: unknown): Scope {
  return {
    userId: authenticatedReevaluationOwner(structuredClone(auth)).toLowerCase(),
    cycleId: parse(uuid, cycleId).toLowerCase(),
  }
}
function assetScope(auth: MobileAuthContext, cycleId: unknown, assetId: unknown): PhotoUploadScope {
  return { ...scope(auth, cycleId), assetId: parse(uuid, assetId).toLowerCase() }
}
function publicAsset(raw: PhotoUploadAsset, expected: Scope, assetId?: string) {
  const parsed = reevaluationPhotoAssetWireSchema.shape.asset.safeParse(raw)
  if (
    !parsed.success ||
    parsed.data.user_id !== expected.userId ||
    parsed.data.cycle_id !== expected.cycleId ||
    (assetId && parsed.data.id !== assetId)
  )
    throw photoLifecycleError()
  const a = parsed.data
  return {
    id: a.id,
    cycle_id: a.cycle_id,
    acceptance_id: a.consent_acceptance_id,
    pose: a.pose,
    mime_type: a.mime_type,
    size_bytes: a.size_bytes,
    status: a.status,
    created_at: a.created_at,
    retention_until: a.retention_until,
  }
}
function publicUpload(
  raw: Awaited<ReturnType<typeof issueReevaluationPhotoUpload>>,
  expected: PhotoUploadScope,
) {
  const asset = publicAsset(raw.asset, expected, expected.assetId)
  const ticket = raw.upload
  const url = new URL(ticket.signed_url)
  if (
    asset.status !== 'pending_upload' ||
    ticket.method !== 'PUT' ||
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.hash ||
    url.pathname !==
      `/storage/v1/object/upload/sign/${raw.asset.bucket_id}/${raw.asset.object_path}` ||
    [...url.searchParams.keys()].join(',') !== 'token' ||
    !url.searchParams.get('token') ||
    ticket.headers['Content-Type'] !== asset.mime_type ||
    ticket.headers['x-upsert'] !== 'false' ||
    !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(ticket.expires_at) ||
    !Number.isFinite(Date.parse(ticket.expires_at)) ||
    new Date(ticket.expires_at).toISOString() !== ticket.expires_at
  )
    throw photoLifecycleError()
  // The existing upload authority verifies the provider host, token claims and
  // actual expiry. Project the capability rather than forwarding its container.
  return {
    asset,
    upload: {
      signed_url: ticket.signed_url,
      method: 'PUT' as const,
      headers: { 'Content-Type': asset.mime_type, 'x-upsert': 'false' },
      expires_at: ticket.expires_at,
    },
  }
}
const processingResult = z.discriminatedUnion('status', [
  z.object({ status: z.literal('processed') }).strip(),
  z.object({ status: z.literal('skipped') }).strip(),
  z
    .object({
      status: z.literal('failed'),
      reason: z.enum([
        'storage_unavailable',
        'invalid_bytes',
        'provider_unavailable',
        'invalid_analysis',
      ]),
    })
    .strip(),
])
/** All identities come from the authenticated scope and SQL. Public projections
 * contain no generation, owner, path, private receipt, raw provider analysis or
 * download URL. Display estimates require a validated complete current triplet.
 * Upload issuance intentionally returns its narrow PUT capability. */
export function createReevaluationPhotoLifecycleService(
  operations: ReevaluationPhotoLifecycleOperations,
) {
  const ops = Object.freeze({
    snapshot: operations.snapshot.bind(operations),
    allocate: operations.allocate.bind(operations),
    upload: operations.upload.bind(operations),
    complete: operations.complete.bind(operations),
    process: operations.process.bind(operations),
    discard: operations.discard.bind(operations),
    drain: operations.drain.bind(operations),
  })
  return Object.freeze({
    async snapshot(auth: MobileAuthContext, cycleId: unknown) {
      const s = scope(auth, cycleId)
      return safe(async () => {
        const raw = parseReevaluationPhotoSnapshot(await ops.snapshot(s))
        const assets = raw.photos.flatMap((p) => (p.photo ? [p.photo] : []))
        if (
          raw.user_id !== s.userId ||
          raw.cycle_id !== s.cycleId ||
          raw.opened_at > raw.observed_at ||
          new Set(raw.photos.map((p) => p.pose)).size !== 3 ||
          new Set(assets.map((p) => p.asset_id)).size !== assets.length ||
          assets.some(
            (p) =>
              p.user_id !== s.userId ||
              p.cycle_id !== s.cycleId ||
              p.signup_generation !== raw.signup_generation ||
              p.consent_acceptance_id !== raw.consent?.acceptance_id,
          )
        )
          throw photoLifecycleError()
        const candidate = resolveReevaluationPhotoCandidate(
          {
            userId: s.userId,
            signupGeneration: raw.signup_generation,
            cycleId: s.cycleId,
            cycleRevision: raw.cycle_revision,
            currentConsent: raw.consent
              ? {
                  documentId: raw.consent.document_id,
                  documentKey: 'body_photo_reevaluation_consent',
                  version: raw.consent.version,
                  locale: raw.consent.locale,
                  bodyHash: raw.consent.body_hash,
                }
              : null,
          },
          raw,
        )
        return {
          version: 1 as const,
          cycle_id: s.cycleId,
          cycle_revision: raw.cycle_revision,
          acceptance_id: raw.consent?.acceptance_id ?? null,
          photos: poses.map((pose) => {
            const p = raw.photos.find((slot) => slot.pose === pose)?.photo
            return {
              pose,
              asset: p
                ? {
                    id: p.asset_id,
                    status: p.status,
                    estimated_body_fat_percent:
                      candidate.status === 'ready'
                        ? (candidate.estimate.readings.find((reading) => reading.pose === pose)
                            ?.body_fat_percent ?? null)
                        : null,
                  }
                : null,
            }
          }),
          quota: REEVALUATION_PHOTO_QUOTA,
        }
      })
    },
    async allocate(
      auth: MobileAuthContext,
      cycleId: unknown,
      operationKey: unknown,
      input: unknown,
    ) {
      const s = scope(auth, cycleId),
        body = parse(reevaluationPhotoAllocateInput, input),
        key = parse(uuid, operationKey).toLowerCase()
      return safe(async () => {
        const raw = await ops.allocate(structuredClone(auth), {
          ...body,
          cycleId: s.cycleId,
          acceptanceId: body.acceptanceId.toLowerCase(),
          requestKey: key,
        })
        if (raw.availability !== 'available') throw photoLifecycleError()
        const checked = parsePhotoAllocationResponse(
          { version: raw.version, cycle_revision: raw.cycle_revision, asset: raw.asset },
          s.userId,
          {
            ...body,
            cycleId: s.cycleId,
            acceptanceId: body.acceptanceId.toLowerCase(),
            requestKey: key,
          },
        )
        return {
          version: 1 as const,
          cycle_id: s.cycleId,
          cycle_revision: checked.cycle_revision,
          asset: publicAsset(checked.asset, s),
          quota: REEVALUATION_PHOTO_QUOTA,
        }
      })
    },
    async upload(auth: MobileAuthContext, cycleId: unknown, assetId: unknown) {
      const s = assetScope(auth, cycleId, assetId)
      return safe(async () => ({
        version: 1 as const,
        cycle_id: s.cycleId,
        ...publicUpload(await ops.upload(s), s),
      }))
    },
    async complete(auth: MobileAuthContext, cycleId: unknown, assetId: unknown) {
      const s = assetScope(auth, cycleId, assetId)
      return safe(async () => {
        const raw = parsePhotoCompletionWire(await ops.complete(s), s)
        if (raw.selection_state !== 'selected') throw photoLifecycleError()
        return {
          version: 1 as const,
          cycle_id: s.cycleId,
          cycle_revision: raw.cycle_revision,
          source_revision: raw.source_revision,
          asset: publicAsset(raw.asset, s, s.assetId),
        }
      })
    },
    async process(
      auth: MobileAuthContext,
      cycleId: unknown,
      assetId: unknown,
      operationKey: unknown,
    ) {
      const s = {
        ...assetScope(auth, cycleId, assetId),
        requestId: parse(uuid, operationKey).toLowerCase(),
      }
      return safe(async () => {
        const raw = processingResult.safeParse(await ops.process(s))
        if (!raw.success) throw photoLifecycleError()
        return { version: 1 as const, cycle_id: s.cycleId, asset_id: s.assetId, ...raw.data }
      })
    },
    async discard(auth: MobileAuthContext, cycleId: unknown, input: unknown) {
      const s = scope(auth, cycleId),
        body = parse(reevaluationPhotoDiscardInput, input)
      return safe(async () => {
        const header = z
          .object({
            id: uuid,
            user_id: uuid,
            cycle_id: uuid,
            acceptance_id: uuid,
            reason: z.literal('discarded'),
            request_revision: revision,
          })
          .strip()
          .safeParse(await ops.discard(s, body))
        if (
          !header.success ||
          header.data.user_id !== s.userId ||
          header.data.cycle_id !== s.cycleId ||
          header.data.acceptance_id !== body.acceptanceId.toLowerCase() ||
          header.data.request_revision !== body.expectedRevision
        )
          throw photoLifecycleError()
        let deletion: 'pending' | 'waiting' | 'settled' = 'pending'
        try {
          const outcome = await ops.drain({ ...s, acceptanceId: header.data.acceptance_id })
          if (outcome.state === 'waiting' || outcome.state === 'settled') deletion = outcome.state
        } catch {
          /* SQL discard stands; the worker reconciles physical removal. */
        }
        return {
          version: 1 as const,
          cycle_id: s.cycleId,
          acceptance_id: header.data.acceptance_id,
          status: 'discard_requested' as const,
          deletion,
        }
      })
    },
  })
}

/** Pure composition with an injected client and an ALREADY configured analyzer.
 * No SDK client, credentials, job, route or provider starts during import. */
export function createSupabaseReevaluationPhotoLifecycleOperations(
  client: ServiceClient,
  options: { storageOrigin: string; analyze: ReevaluationPhotoProcessingDependencies['analyze'] },
): ReevaluationPhotoLifecycleOperations {
  const rpc = client.rpc.bind(client) as unknown as (
    name: string,
    args: Record<string, unknown>,
  ) => PromiseLike<unknown>
  const allocation = {
    enabled: true,
    repository: createSupabaseReevaluationPhotoAllocationRepository(client),
  }
  const upload = createSupabaseReevaluationPhotoUploadDependencies(client, options),
    completion = createSupabaseReevaluationPhotoCompletionDependencies(client)
  const processing = createSupabaseReevaluationPhotoProcessingDependencies(client, options),
    disposition = createReevaluationPhotoDispositionDependencies(client)
  async function invoke(name: string, args: Record<string, unknown>) {
    let raw: unknown
    try {
      raw = await rpc(name, args)
    } catch {
      throw photoLifecycleError()
    }
    if (
      !raw ||
      typeof raw !== 'object' ||
      Array.isArray(raw) ||
      !Object.hasOwn(raw, 'data') ||
      !Object.hasOwn(raw, 'error')
    )
      throw photoLifecycleError()
    const packet = raw as { data: unknown; error: unknown }
    if (packet.error !== null) {
      const code =
        packet.error && typeof packet.error === 'object' && 'code' in packet.error
          ? packet.error.code
          : null
      throw photoLifecycleError(
        code === '40001'
          ? 'changed'
          : code === '55P03'
            ? 'busy'
            : code === '22023'
              ? 'input'
              : 'unavailable',
      )
    }
    return packet.data
  }
  return Object.freeze({
    snapshot: (s: Scope) =>
      invoke('get_mobile_reevaluation_photo_snapshot', {
        p_user_id: s.userId,
        p_cycle_id: s.cycleId,
      }),
    allocate: (auth: MobileAuthContext, input: unknown) =>
      allocateReevaluationPhoto(auth, input, allocation),
    upload: (s: PhotoUploadScope) => issueReevaluationPhotoUpload(upload, s),
    complete: (s: PhotoUploadScope) => completeReevaluationPhotoUpload(completion, s),
    process: (s: PhotoProcessingScope) => processReevaluationPhoto(processing, s),
    discard: (s: Scope, input: z.infer<typeof reevaluationPhotoDiscardInput>) =>
      invoke('discard_mobile_reevaluation_photos', {
        p_user_id: s.userId,
        p_cycle_id: s.cycleId,
        p_acceptance_id: input.acceptanceId.toLowerCase(),
        p_expected_revision: input.expectedRevision,
      }),
    drain: (s: ReevaluationPhotoDispositionScope) =>
      drainReevaluationPhotoDisposition(disposition, s),
  })
}
