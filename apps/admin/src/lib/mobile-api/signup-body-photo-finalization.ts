/** Mechanical finalization. Candidate resolution is supplied separately; no aggregation here. */
export type PhotoPose = 'front' | 'side' | 'back'
export type FinalizationPhase = 'read' | 'resolve' | 'persist' | 'remove' | 'mark'
export type FinalizationState =
  | 'empty'
  | 'deferred_rule'
  | 'unusable'
  | 'source_unknown'
  | 'provenance_unknown'
  | 'provenance_committed_cleanup_pending'
  | 'cleanup_unknown'
  | 'complete'

export interface FinalizationPhoto {
  readonly id: string
  readonly userId: string
  readonly bucketId: 'body-checkin-photos'
  readonly objectPath: string
  readonly pose: PhotoPose
  readonly status: 'pending_upload' | 'uploaded' | 'processing' | 'processed' | 'failed' | 'deleted'
  readonly failureStage: 'upload' | 'processing' | null
  readonly createdAt: string
  readonly uploadedAt: string | null
  /** Reduced finite body value only. Never notes, model view or confidence. */
  readonly bodyFatPercent: number | null
}

export interface FinalizationSnapshot {
  readonly userId: string
  readonly photos: readonly FinalizationPhoto[]
}

export interface PreparedPhotoCandidate {
  readonly userId: string
  /** Ready scalar supplied externally; helper NEVER calculates it. */
  readonly bodyFatPercent: number
  /** Supplied stable instant; do not replace with Date.now on a retry. */
  readonly estimatedAt: string
  readonly sources: readonly { pose: PhotoPose; assetId: string }[]
  /** Explicit disposition supplied with the candidate, not a default policy. */
  readonly cleanupAssetIds: readonly string[]
}

export type CandidateResolution =
  | { readonly kind: 'deferred_rule' }
  | { readonly kind: 'unusable' }
  | { readonly kind: 'resolved'; readonly candidate: PreparedPhotoCandidate }

export type EstimatedProvenancePatch = {
  bf_percent_estimated: number
  bf_source: 'signup_photos'
  bf_estimated_at: string
}

/** Raw receipt permits the helper to fail closed on error:null + bad data. */
export interface WriteReceipt {
  data: unknown
  error: unknown
}
export interface FinalizationOutcome {
  readonly state: FinalizationState
  readonly phase?: FinalizationPhase
  readonly reason?: 'timeout' | 'error' | 'invalid_receipt' | 'snapshot_mismatch'
}

export interface FinalizationRepository {
  loadSnapshot(userId: string, signal: AbortSignal): Promise<readonly FinalizationPhoto[]>
  persistProvenance(
    userId: string,
    patch: EstimatedProvenancePatch,
    signal: AbortSignal,
  ): Promise<WriteReceipt>
  markDeleted(
    userId: string,
    assetIds: readonly string[],
    deletedAt: string,
    signal: AbortSignal,
  ): Promise<WriteReceipt>
}

export interface FinalizationDependencies {
  readonly repository: FinalizationRepository
  readonly storage: {
    /** SDK remove(paths) has NO signal argument. Only guards can stop next phases. */
    remove(bucketId: 'body-checkin-photos', objectPaths: readonly string[]): Promise<void>
  }
  /** Required callback: the real B4a factory explicitly supplies deferred_rule. */
  resolveCandidate(
    snapshot: FinalizationSnapshot,
    sex: 'masculino' | 'feminino' | null,
    signal: AbortSignal,
  ): Promise<CandidateResolution>
  now(): number
  /** Closed object only: never raw Error, user/asset ids, paths or scalar. */
  warn(event: {
    phase: FinalizationPhase
    state: FinalizationState
    reason: 'timeout' | 'error' | 'invalid_receipt' | 'snapshot_mismatch'
  }): void
}

export async function deferSignupBodyPhotoCandidate(
  _snapshot: FinalizationSnapshot,
  _sex: 'masculino' | 'feminino' | null,
  _signal: AbortSignal,
): Promise<CandidateResolution> {
  return { kind: 'deferred_rule' }
}

function instantKey(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const match = value.match(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.(\d{1,9}))?(?:Z|[+-]\d\d:\d\d)$/)
  const milliseconds = Date.parse(value)
  return match && Number.isFinite(milliseconds)
    ? `${milliseconds}:${(match[1] ?? '').slice(3).padEnd(6, '0')}`
    : null
}

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function exactKeys(row: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(row).sort().join(',') === [...keys].sort().join(',')
}

function validSnapshot(userId: string, photos: readonly FinalizationPhoto[]): boolean {
  return (
    new Set(photos.map((photo) => photo.id)).size === photos.length &&
    photos.every(
      (photo) =>
        photo.userId === userId &&
        photo.bucketId === 'body-checkin-photos' &&
        photo.objectPath.startsWith(`${userId}/`) &&
        photo.objectPath.length > userId.length + 1 &&
        !photo.objectPath.split('/').some((part) => part === '..' || part === '.') &&
        ['front', 'side', 'back'].includes(photo.pose) &&
        instantKey(photo.createdAt) !== null &&
        (photo.uploadedAt === null || instantKey(photo.uploadedAt) !== null),
    )
  )
}

function isStored(photo: FinalizationPhoto): boolean {
  return (
    ['uploaded', 'processing', 'processed'].includes(photo.status) ||
    (photo.status === 'failed' && photo.failureStage === 'processing')
  )
}

/** Same ordering as the state service: upload time, then ID. Never creation time. */
function newer(left: FinalizationPhoto, right: FinalizationPhoto): boolean {
  const leftAt = left.uploadedAt ? Date.parse(left.uploadedAt) : 0
  const rightAt = right.uploadedAt ? Date.parse(right.uploadedAt) : 0
  return leftAt > rightAt || (leftAt === rightAt && left.id > right.id)
}

function validCandidate(
  snapshot: FinalizationSnapshot,
  candidate: PreparedPhotoCandidate,
): boolean {
  if (
    candidate.userId !== snapshot.userId ||
    !Number.isFinite(candidate.bodyFatPercent) ||
    instantKey(candidate.estimatedAt) === null ||
    candidate.sources.length !== 3 ||
    new Set(candidate.sources.map((source) => source.pose)).size !== 3 ||
    new Set(candidate.cleanupAssetIds).size !== candidate.cleanupAssetIds.length
  )
    return false
  const ids = new Set(candidate.cleanupAssetIds)
  if (
    !candidate.cleanupAssetIds.every((id) =>
      snapshot.photos.some((photo) => photo.id === id && photo.status !== 'deleted'),
    )
  )
    return false
  return (['front', 'side', 'back'] as const).every((pose) => {
    const source = candidate.sources.find((entry) => entry.pose === pose)
    const latest = snapshot.photos
      .filter((photo) => photo.pose === pose && isStored(photo))
      .reduce<FinalizationPhoto | null>(
        (current, photo) => (!current || newer(photo, current) ? photo : current),
        null,
      )
    return (
      source &&
      latest &&
      source.assetId === latest.id &&
      ids.has(source.assetId) &&
      latest.status === 'processed' &&
      typeof latest.bodyFatPercent === 'number' &&
      Number.isFinite(latest.bodyFatPercent)
    )
  })
}

function confirmsProvenance(
  receipt: WriteReceipt,
  owner: string,
  patch: EstimatedProvenancePatch,
): boolean {
  if (receipt.error !== null || !Array.isArray(receipt.data) || receipt.data.length !== 1)
    return false
  const row = record(receipt.data[0])
  return (
    !!row &&
    exactKeys(row, ['user_id', 'bf_percent_estimated', 'bf_source', 'bf_estimated_at']) &&
    row.user_id === owner &&
    row.bf_percent_estimated === patch.bf_percent_estimated &&
    row.bf_source === 'signup_photos' &&
    instantKey(row.bf_estimated_at) === instantKey(patch.bf_estimated_at)
  )
}

function confirmsDeletion(
  receipt: WriteReceipt,
  owner: string,
  ids: readonly string[],
  at: string,
): boolean {
  if (receipt.error !== null || !Array.isArray(receipt.data) || receipt.data.length !== ids.length)
    return false
  const seen = new Set<string>()
  return receipt.data.every((value) => {
    const row = record(value)
    if (
      !row ||
      !exactKeys(row, ['id', 'user_id', 'status', 'deleted_at', 'processing_result']) ||
      typeof row.id !== 'string' ||
      !ids.includes(row.id) ||
      seen.has(row.id) ||
      row.user_id !== owner ||
      row.status !== 'deleted' ||
      row.processing_result !== null ||
      instantKey(row.deleted_at) !== instantKey(at)
    )
      return false
    seen.add(row.id)
    return true
  })
}

/** One local deadline. An aborted wait does not undo a sent remote write/delete. */
export async function finalizeSignupBodyPhotos(
  input: {
    userId: string
    sex: 'masculino' | 'feminino' | null
    cleanupDeletedObjects?: boolean
    deadline?: number
  },
  dependencies: FinalizationDependencies,
): Promise<FinalizationOutcome> {
  const controller = new AbortController()
  const deadline = Math.min(input.deadline ?? Number.POSITIVE_INFINITY, dependencies.now() + 3000)
  let phase: FinalizationPhase = 'read'
  let stopped = false
  let outcome: FinalizationOutcome | undefined
  let provenanceConfirmed = false
  let cleanupSent = false
  const unknownState = (): FinalizationState =>
    phase === 'read' || phase === 'resolve'
      ? 'source_unknown'
      : provenanceConfirmed && !cleanupSent
        ? 'provenance_committed_cleanup_pending'
        : phase === 'persist'
          ? 'provenance_unknown'
          : 'cleanup_unknown'
  const fail = (
    reason: NonNullable<FinalizationOutcome['reason']>,
    state = unknownState(),
  ): FinalizationOutcome => {
    if (outcome) return outcome
    stopped = true
    controller.abort()
    outcome = { state, phase, reason }
    dependencies.warn({ state, phase, reason })
    return outcome
  }
  const guard = () => {
    if (stopped || dependencies.now() >= deadline) {
      fail('timeout')
      throw new Error('finalization_stopped')
    }
  }
  const step = async <T>(next: FinalizationPhase, operation: () => Promise<T>): Promise<T> => {
    guard()
    phase = next
    const value = await operation()
    guard()
    return value
  }
  let timeout!: ReturnType<typeof setTimeout>
  const timedOut = new Promise<FinalizationOutcome>((resolve) => {
    timeout = setTimeout(() => resolve(fail('timeout')), Math.max(0, deadline - dependencies.now()))
  })
  const work = async (): Promise<FinalizationOutcome> => {
    try {
      const rawPhotos = await step('read', () =>
        dependencies.repository.loadSnapshot(input.userId, controller.signal),
      )
      const photos = Object.freeze(rawPhotos.map((photo) => Object.freeze({ ...photo })))
      if (!validSnapshot(input.userId, photos)) return fail('snapshot_mismatch', 'unusable')
      if (photos.length === 0) return { state: 'empty' }
      if (input.cleanupDeletedObjects && photos.every((photo) => photo.status === 'deleted')) {
        // Existing deletion policy: a still-valid upload ticket can place bytes
        // at an already deleted row's path. No estimate or new catalogue mark.
        await step('remove', () =>
          dependencies.storage.remove(
            'body-checkin-photos',
            photos.map((photo) => photo.objectPath),
          ),
        )
        return { state: 'complete' }
      }
      const snapshot = Object.freeze({ userId: input.userId, photos })
      const resolution = await step('resolve', () =>
        dependencies.resolveCandidate(snapshot, input.sex, controller.signal),
      )
      if (resolution.kind !== 'resolved') return { state: resolution.kind }
      const candidate = Object.freeze({
        ...resolution.candidate,
        sources: Object.freeze(
          resolution.candidate.sources.map((source) => Object.freeze({ ...source })),
        ),
        cleanupAssetIds: Object.freeze([...resolution.candidate.cleanupAssetIds]),
      })
      if (!validCandidate(snapshot, candidate)) return fail('snapshot_mismatch', 'unusable')
      const patch: EstimatedProvenancePatch = Object.freeze({
        bf_percent_estimated: candidate.bodyFatPercent,
        bf_source: 'signup_photos',
        bf_estimated_at: candidate.estimatedAt,
      })
      const saved = await step('persist', () =>
        dependencies.repository.persistProvenance(input.userId, patch, controller.signal),
      )
      if (!confirmsProvenance(saved, input.userId, patch)) return fail('invalid_receipt')
      provenanceConfirmed = true
      const paths = candidate.cleanupAssetIds.map(
        (id) => photos.find((photo) => photo.id === id)?.objectPath as string,
      )
      await step('remove', () => {
        cleanupSent = true
        return dependencies.storage.remove('body-checkin-photos', paths)
      })
      // Wall clock for the database timestamp; dependencies.now is only the budget clock.
      const deletedAt = new Date().toISOString()
      const marked = await step('mark', () =>
        dependencies.repository.markDeleted(
          input.userId,
          candidate.cleanupAssetIds,
          deletedAt,
          controller.signal,
        ),
      )
      if (!confirmsDeletion(marked, input.userId, candidate.cleanupAssetIds, deletedAt))
        return fail('invalid_receipt')
      return { state: 'complete' }
    } catch {
      return outcome ?? fail(dependencies.now() >= deadline ? 'timeout' : 'error')
    }
  }
  try {
    return await Promise.race([work(), timedOut])
  } finally {
    clearTimeout(timeout)
  }
}
