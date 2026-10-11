/**
 * Engineering synthetic candidate, not a clinical estimate. The causal RED
 * against the read-only scaffold and the route RED are preserved separately.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  type CandidateResolution,
  deferSignupBodyPhotoCandidate,
  type EstimatedProvenancePatch,
  type FinalizationDependencies,
  type FinalizationPhoto,
  finalizeSignupBodyPhotos,
  type PreparedPhotoCandidate,
  type WriteReceipt,
} from './signup-body-photo-finalization'

const ACCOUNT = '00000000-0000-4000-8000-000000000401'
const OTHER = '00000000-0000-4000-8000-000000000402'
const IDS = [
  '00000000-0000-4000-8000-000000000411',
  '00000000-0000-4000-8000-000000000412',
  '00000000-0000-4000-8000-000000000413',
]
const EXTRA = '00000000-0000-4000-8000-000000000414'
const SECOND_EXTRA = '00000000-0000-4000-8000-000000000415'
const BUCKET = 'body-checkin-photos' as const
const NOW = new Date('2026-10-11T20:00:00.000Z')
const ESTIMATED_AT = '2026-10-11T19:30:00.000Z'

function photos(userId = ACCOUNT): FinalizationPhoto[] {
  return (['front', 'side', 'back'] as const).map((pose, index) => ({
    id: IDS[index],
    userId,
    bucketId: BUCKET,
    objectPath: userId + '/' + IDS[index] + '.jpg',
    pose,
    status: 'processed',
    failureStage: null,
    createdAt: '2026-10-11T19:00:00.000Z',
    uploadedAt: '2026-10-11T19:15:00.000Z',
    bodyFatPercent: 21 + index,
  }))
}

function ready(userId = ACCOUNT): PreparedPhotoCandidate {
  return {
    userId,
    // Ready test scalar, deliberately not calculated from the three readings.
    bodyFatPercent: 17.25,
    estimatedAt: ESTIMATED_AT,
    sources: (['front', 'side', 'back'] as const).map((pose, index) => ({
      pose,
      assetId: IDS[index],
    })),
    cleanupAssetIds: [...IDS],
  }
}

function provenanceReceipt(userId: string, patch: EstimatedProvenancePatch): WriteReceipt {
  return { data: [{ user_id: userId, ...patch }], error: null }
}

function markReceipt(userId: string, ids: readonly string[], deletedAt: string): WriteReceipt {
  return {
    data: ids.map((id) => ({
      id,
      user_id: userId,
      status: 'deleted',
      deleted_at: deletedAt,
      processing_result: null,
    })),
    error: null,
  }
}

function fixture(userId = ACCOUNT) {
  const rows = photos(userId)
  const trace: string[] = []
  let profile: Record<string, unknown> | null = null
  const dependencies = {
    repository: {
      loadSnapshot: vi.fn(async (_userId: string, _signal: AbortSignal) => {
        trace.push('read')
        return rows
      }),
      persistProvenance: vi.fn(
        async (owner: string, patch: EstimatedProvenancePatch, _signal: AbortSignal) => {
          trace.push('persist')
          profile = { user_id: owner, ...patch }
          return provenanceReceipt(owner, patch)
        },
      ),
      markDeleted: vi.fn(
        async (owner: string, ids: readonly string[], at: string, _signal: AbortSignal) => {
          trace.push('mark')
          return markReceipt(owner, ids, at)
        },
      ),
    },
    storage: {
      remove: vi.fn(async (_bucket: 'body-checkin-photos', _paths: readonly string[]) => {
        trace.push('remove')
      }),
    },
    resolveCandidate: vi.fn(deferSignupBodyPhotoCandidate),
    now: vi.fn(() => Date.now()),
    warn: vi.fn<FinalizationDependencies['warn']>(),
  } satisfies FinalizationDependencies
  return {
    rows,
    trace,
    dependencies,
    get profile() {
      return profile
    },
    setProfile(value: Record<string, unknown>) {
      profile = { ...value }
    },
    resolve(candidate = ready(userId)) {
      dependencies.resolveCandidate.mockImplementation(async () => {
        trace.push('resolve')
        return { kind: 'resolved', candidate } as CandidateResolution
      })
    },
    run() {
      return finalizeSignupBodyPhotos({ userId, sex: 'masculino' }, dependencies)
    },
  }
}

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: unknown) => void
  const promise = new Promise<T>((yes, no) => {
    resolve = yes
    reject = no
  })
  return { promise, resolve, reject }
}
async function drain() {
  for (let index = 0; index < 20; index += 1) await Promise.resolve()
}

function noMutation(f: ReturnType<typeof fixture>) {
  expect(f.dependencies.repository.persistProvenance).not.toHaveBeenCalled()
  expect(f.dependencies.storage.remove).not.toHaveBeenCalled()
  expect(f.dependencies.repository.markDeleted).not.toHaveBeenCalled()
}

function safeLog(f: ReturnType<typeof fixture>) {
  for (const [event] of f.dependencies.warn.mock.calls) {
    expect(Object.keys(event).sort()).toEqual(['phase', 'reason', 'state'])
    const encoded = JSON.stringify(event)
    for (const privateValue of [
      ACCOUNT,
      OTHER,
      IDS[0],
      '17.25',
      'synthetic private error',
      '.jpg',
    ]) {
      expect(encoded).not.toContain(privateValue)
    }
  }
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date', 'setTimeout', 'clearTimeout'] })
  vi.setSystemTime(NOW)
})
afterEach(() => {
  try {
    expect(vi.getTimerCount()).toBe(0)
  } finally {
    vi.useRealTimers()
    vi.restoreAllMocks()
  }
})

describe('B4a mechanical boundaries; no clinical resolver supplied by B4a', () => {
  it('M01 no photos: exactly one snapshot read, no resolver, no extra profile read or mutation', async () => {
    const f = fixture()
    f.rows.length = 0
    expect(await f.run()).toEqual({ state: 'empty' })
    expect(f.dependencies.repository.loadSnapshot).toHaveBeenCalledOnce()
    expect(f.dependencies.repository.loadSnapshot.mock.calls[0][0]).toBe(ACCOUNT)
    expect(f.dependencies.resolveCandidate).not.toHaveBeenCalled()
    noMutation(f)
    expect(f.dependencies.warn).not.toHaveBeenCalled()
  })

  it('M02 real callback defaults to deferred_rule even with three readings: no invented scalar/disposal', async () => {
    const f = fixture()
    expect(await f.run()).toEqual({ state: 'deferred_rule' })
    expect(f.dependencies.repository.loadSnapshot).toHaveBeenCalledOnce()
    expect(f.dependencies.resolveCandidate).toHaveBeenCalledOnce()
    expect(f.dependencies.resolveCandidate.mock.calls[0][0]).toEqual({
      userId: ACCOUNT,
      photos: f.rows,
    })
    noMutation(f)
    expect(f.profile).toBeNull()
    expect(f.dependencies.warn).not.toHaveBeenCalled()
  })

  it('M03 unusable callback has no cleanup and does not become a zero/manual/old estimate', async () => {
    const f = fixture()
    f.dependencies.resolveCandidate.mockResolvedValue({ kind: 'unusable' })
    expect(await f.run()).toEqual({ state: 'unusable' })
    noMutation(f)
  })

  it.each([
    'vision',
    'signup_photos',
  ])('M04 old provenance %s and equal scalar are not snapshot proof or user confirmation', async (source) => {
    const f = fixture()
    f.setProfile({
      user_id: ACCOUNT,
      bf_percent_estimated: 17.25,
      bf_source: source,
      bf_estimated_at: ESTIMATED_AT,
      body_fat_percent: 17.25,
    })
    const before = f.profile
    expect(await f.run()).toEqual({ state: 'deferred_rule' })
    noMutation(f)
    expect(f.profile).toEqual(before)
  })

  it('M05 engineering ready candidate: THREE source readings, FIVE explicit cleanup assets; exact three columns before remove before mark', async () => {
    const f = fixture()
    f.rows.push(
      {
        ...f.rows[0],
        id: EXTRA,
        objectPath: ACCOUNT + '/' + EXTRA + '.jpg',
        status: 'pending_upload',
        uploadedAt: null,
        bodyFatPercent: null,
      },
      {
        ...f.rows[1],
        id: SECOND_EXTRA,
        objectPath: ACCOUNT + '/' + SECOND_EXTRA + '.jpg',
        status: 'failed',
        failureStage: 'upload',
        uploadedAt: null,
        bodyFatPercent: null,
      },
    )
    const candidate = { ...ready(), cleanupAssetIds: [...IDS, EXTRA, SECOND_EXTRA] }
    f.resolve(candidate)
    expect(await f.run()).toEqual({ state: 'complete' })
    expect(f.trace).toEqual(['read', 'resolve', 'persist', 'remove', 'mark'])
    const [owner, patch, signal] = f.dependencies.repository.persistProvenance.mock.calls[0]
    expect(owner).toBe(ACCOUNT)
    expect(patch).toEqual({
      bf_percent_estimated: 17.25,
      bf_source: 'signup_photos',
      bf_estimated_at: ESTIMATED_AT,
    })
    expect(Object.keys(patch).sort()).toEqual([
      'bf_estimated_at',
      'bf_percent_estimated',
      'bf_source',
    ])
    expect(signal.aborted).toBe(false)
    expect(f.profile).toEqual({ user_id: ACCOUNT, ...patch })
    // Storage receives exactly the two SDK arguments; no invented signal API.
    expect(f.dependencies.storage.remove.mock.calls).toEqual([
      [BUCKET, candidate.cleanupAssetIds.map((id) => ACCOUNT + '/' + id + '.jpg')],
    ])
    expect(f.dependencies.repository.markDeleted.mock.calls[0].slice(0, 3)).toEqual([
      ACCOUNT,
      candidate.cleanupAssetIds,
      NOW.toISOString(),
    ])
    expect(f.dependencies.warn).not.toHaveBeenCalled()
  })

  it.each([
    ['error', { data: null, error: { message: 'synthetic private error' } }],
    ['null data', { data: null, error: null }],
    ['zero rows', { data: [], error: null }],
    ['malformed row', { data: [null], error: null }],
    [
      'duplicate rows',
      {
        data: [
          {
            user_id: ACCOUNT,
            bf_percent_estimated: 17.25,
            bf_source: 'signup_photos',
            bf_estimated_at: ESTIMATED_AT,
          },
          {
            user_id: ACCOUNT,
            bf_percent_estimated: 17.25,
            bf_source: 'signup_photos',
            bf_estimated_at: ESTIMATED_AT,
          },
        ],
        error: null,
      },
    ],
    [
      'other user',
      {
        data: [
          {
            user_id: OTHER,
            bf_percent_estimated: 17.25,
            bf_source: 'signup_photos',
            bf_estimated_at: ESTIMATED_AT,
          },
        ],
        error: null,
      },
    ],
    [
      'wrong scalar',
      {
        data: [
          {
            user_id: ACCOUNT,
            bf_percent_estimated: 18,
            bf_source: 'signup_photos',
            bf_estimated_at: ESTIMATED_AT,
          },
        ],
        error: null,
      },
    ],
    [
      'wrong source',
      {
        data: [
          {
            user_id: ACCOUNT,
            bf_percent_estimated: 17.25,
            bf_source: 'vision',
            bf_estimated_at: ESTIMATED_AT,
          },
        ],
        error: null,
      },
    ],
    [
      'wrong instant',
      {
        data: [
          {
            user_id: ACCOUNT,
            bf_percent_estimated: 17.25,
            bf_source: 'signup_photos',
            bf_estimated_at: NOW.toISOString(),
          },
        ],
        error: null,
      },
    ],
  ])('M06 persistence %s is not confirmed: zero Storage/mark', async (_label, receipt) => {
    const f = fixture()
    f.resolve()
    f.dependencies.repository.persistProvenance.mockResolvedValue(receipt)
    expect(await f.run()).toMatchObject({ state: 'provenance_unknown', phase: 'persist' })
    expect(f.dependencies.storage.remove).not.toHaveBeenCalled()
    expect(f.dependencies.repository.markDeleted).not.toHaveBeenCalled()
    expect(f.dependencies.warn).toHaveBeenCalledOnce()
    safeLog(f)
  })

  it('M07 timestamptz receipt in DB notation confirms the SAME instant, not only identical string formatting', async () => {
    const f = fixture()
    f.resolve()
    f.dependencies.repository.persistProvenance.mockResolvedValue({
      data: [
        {
          user_id: ACCOUNT,
          bf_percent_estimated: 17.25,
          bf_source: 'signup_photos',
          bf_estimated_at: '2026-10-11T19:30:00.000000+00:00',
        },
      ],
      error: null,
    })
    expect(await f.run()).toEqual({ state: 'complete' })
  })

  it.each([
    ['different owner', { ...ready(), userId: OTHER }],
    [
      'source id absent',
      {
        ...ready(),
        sources: [{ pose: 'front' as const, assetId: EXTRA }, ...ready().sources.slice(1)],
      },
    ],
    [
      'duplicate poses',
      { ...ready(), sources: [ready().sources[0], ready().sources[0], ready().sources[2]] },
    ],
    ['cleanup id absent', { ...ready(), cleanupAssetIds: [...IDS, EXTRA] }],
    ['duplicate cleanup id', { ...ready(), cleanupAssetIds: [...IDS, IDS[0]] }],
    ['cleanup misses a source', { ...ready(), cleanupAssetIds: IDS.slice(1) }],
    ['non-finite scalar', { ...ready(), bodyFatPercent: Number.POSITIVE_INFINITY }],
  ])('M08 %s candidate is not bound to this snapshot: zero effects', async (_label, candidate) => {
    const f = fixture()
    f.resolve(candidate)
    expect(await f.run()).toMatchObject({ state: 'unusable' })
    noMutation(f)
    safeLog(f)
  })

  it('M09 a newer completed upload still processing makes the OLD read inadmissible; pending replacement does not', async () => {
    const f = fixture()
    f.rows.push({
      ...f.rows[0],
      id: EXTRA,
      objectPath: ACCOUNT + '/' + EXTRA + '.jpg',
      status: 'processing',
      uploadedAt: NOW.toISOString(),
      bodyFatPercent: null,
    })
    f.resolve()
    expect(await f.run()).toMatchObject({ state: 'unusable' })
    noMutation(f)
    // M05 separately proves pending upload is excluded from current-pose selection.
  })

  it('M16 the snapshot is owned by this execution: mutating the adapter array while resolver is pending cannot change its IDs/account/paths', async () => {
    const f = fixture()
    const pending = deferred<CandidateResolution>()
    let received: unknown
    f.dependencies.resolveCandidate.mockImplementation((snapshot) => {
      received = snapshot
      return pending.promise
    })
    const original = structuredClone(f.rows)
    const result = f.run()
    await drain()
    const captured = received as { userId: string; photos: readonly FinalizationPhoto[] }
    expect(Object.isFrozen(captured)).toBe(true)
    expect(Object.isFrozen(captured.photos)).toBe(true)
    expect(captured.photos.every((photo) => Object.isFrozen(photo))).toBe(true)
    // Mutate the original object itself before replacing its containing array slot.
    Object.assign(f.rows[0], {
      id: EXTRA,
      userId: OTHER,
      objectPath: OTHER + '/' + EXTRA + '.jpg',
      bodyFatPercent: 99,
    })
    expect(received).toEqual({ userId: ACCOUNT, photos: original })
    f.rows[0] = { ...f.rows[0], id: EXTRA, userId: OTHER, objectPath: OTHER + '/' + EXTRA + '.jpg' }
    expect(received).toEqual({ userId: ACCOUNT, photos: original })
    pending.resolve({ kind: 'resolved', candidate: ready() })
    expect(await result).toEqual({ state: 'complete' })
    expect(f.dependencies.storage.remove.mock.calls).toEqual([
      [BUCKET, original.map((row) => row.objectPath)],
    ])
    expect(f.dependencies.repository.persistProvenance.mock.calls[0][0]).toBe(ACCOUNT)
  })

  it.each([
    'uploaded_at',
    'id_tie',
  ] as const)('M09b current front selected by %s despite older createdAt: old candidate is refused', async (ordering) => {
    const f = fixture()
    Object.assign(f.rows[0], { createdAt: '2026-10-11T20:10:00.000Z' })
    f.rows.push({
      ...f.rows[0],
      id: EXTRA,
      objectPath: ACCOUNT + '/' + EXTRA + '.jpg',
      createdAt: '2026-10-11T18:00:00.000Z',
      uploadedAt: ordering === 'id_tie' ? f.rows[0].uploadedAt : '2026-10-11T19:45:00.000Z',
      status: 'processing',
      bodyFatPercent: null,
    })
    f.resolve()
    expect(await f.run()).toMatchObject({ state: 'unusable' })
    noMutation(f)
  })

  it.each([
    false,
    true,
  ])('M09c equal uploadedAt chooses higher ID independently of insertion order reversed=%s', async (reverse) => {
    const f = fixture()
    const winner = {
      ...f.rows[0],
      id: EXTRA,
      objectPath: ACCOUNT + '/' + EXTRA + '.jpg',
      createdAt: '2026-10-11T18:00:00.000Z',
    }
    Object.assign(f.rows[0], { createdAt: '2026-10-11T20:10:00.000Z' })
    f.rows.push(winner)
    if (reverse) f.rows.reverse()
    const candidate = {
      ...ready(),
      sources: ready().sources.map((source) =>
        source.pose === 'front' ? { ...source, assetId: EXTRA } : source,
      ),
      cleanupAssetIds: [...IDS, EXTRA],
    }
    f.resolve(candidate)
    expect(await f.run()).toEqual({ state: 'complete' })
    expect(f.dependencies.storage.remove.mock.calls).toEqual([
      [BUCKET, candidate.cleanupAssetIds.map((id) => ACCOUNT + '/' + id + '.jpg')],
    ])
    expect(f.dependencies.repository.markDeleted.mock.calls[0].slice(0, 3)).toEqual([
      ACCOUNT,
      candidate.cleanupAssetIds,
      NOW.toISOString(),
    ])
  })

  it('M18 candidate retained by resolver is copied before persistence: later scalar/date/source/cleanup mutation cannot retarget effects', async () => {
    const f = fixture()
    const candidate = ready()
    const original = structuredClone(candidate)
    f.resolve(candidate)
    const pending = deferred<WriteReceipt>()
    f.dependencies.repository.persistProvenance.mockImplementation(() => pending.promise)
    const result = f.run()
    await drain()
    expect(f.dependencies.repository.persistProvenance).toHaveBeenCalledOnce()
    expect(f.dependencies.storage.remove).not.toHaveBeenCalled()
    const expectedPatch = {
      bf_percent_estimated: original.bodyFatPercent,
      bf_source: 'signup_photos' as const,
      bf_estimated_at: original.estimatedAt,
    }
    expect(f.dependencies.repository.persistProvenance.mock.calls[0][1]).toEqual(expectedPatch)
    Object.assign(candidate, { userId: OTHER, bodyFatPercent: 99, estimatedAt: NOW.toISOString() })
    Object.assign(candidate.sources[0], { pose: 'side', assetId: EXTRA })
    Array.prototype.push.call(candidate.sources, { pose: 'front', assetId: SECOND_EXTRA })
    Array.prototype.push.call(candidate.cleanupAssetIds, EXTRA)
    expect(f.dependencies.repository.persistProvenance.mock.calls[0][1]).toEqual(expectedPatch)
    pending.resolve(provenanceReceipt(ACCOUNT, expectedPatch))
    expect(await result).toEqual({ state: 'complete' })
    expect(f.dependencies.storage.remove.mock.calls).toEqual([
      [BUCKET, original.cleanupAssetIds.map((id) => ACCOUNT + '/' + id + '.jpg')],
    ])
    expect(f.dependencies.repository.markDeleted.mock.calls[0].slice(0, 3)).toEqual([
      ACCOUNT,
      original.cleanupAssetIds,
      NOW.toISOString(),
    ])
    expect(f.dependencies.warn).not.toHaveBeenCalled()
  })

  it('M10 remove fails after confirmed provenance: unknown cleanup, no catalog mark; retry keeps supplied timestamp', async () => {
    const f = fixture()
    f.resolve()
    f.dependencies.storage.remove.mockRejectedValueOnce(
      new Error('synthetic private error ' + ACCOUNT),
    )
    expect(await f.run()).toMatchObject({ state: 'cleanup_unknown', phase: 'remove' })
    expect(f.profile).toEqual({
      user_id: ACCOUNT,
      bf_percent_estimated: 17.25,
      bf_source: 'signup_photos',
      bf_estimated_at: ESTIMATED_AT,
    })
    expect(f.dependencies.repository.markDeleted).not.toHaveBeenCalled()
    expect(await f.run()).toEqual({ state: 'complete' })
    expect(
      f.dependencies.repository.persistProvenance.mock.calls.map((call) => call[1].bf_estimated_at),
    ).toEqual([ESTIMATED_AT, ESTIMATED_AT])
    safeLog(f)
  })

  it.each([
    'error',
    'missing ids',
    'duplicate ids',
    'other user',
    'not deleted',
    'result retained',
  ])('M11 catalogue %s is cleanup_unknown despite Storage success', async (invalid) => {
    const f = fixture()
    f.resolve()
    const valid = markReceipt(ACCOUNT, IDS, NOW.toISOString())
    const rows = valid.data as Array<Record<string, unknown>>
    const receipt =
      invalid === 'error'
        ? { data: null, error: { message: 'synthetic private error' } }
        : invalid === 'missing ids'
          ? { data: rows.slice(1), error: null }
          : invalid === 'duplicate ids'
            ? { data: [rows[0], rows[0], rows[2]], error: null }
            : {
                data: rows.map((row, index) =>
                  index
                    ? row
                    : {
                        ...row,
                        ...(invalid === 'other user'
                          ? { user_id: OTHER }
                          : invalid === 'not deleted'
                            ? { status: 'processed' }
                            : { processing_result: { notes: 'synthetic private error' } }),
                      },
                ),
                error: null,
              }
    f.dependencies.repository.markDeleted.mockResolvedValue(receipt)
    expect(await f.run()).toMatchObject({ state: 'cleanup_unknown', phase: 'mark' })
    expect(f.dependencies.storage.remove).toHaveBeenCalledOnce()
    safeLog(f)
  })
  it.each([
    'missing',
    'wrong_instant',
  ] as const)('M11b catalogue deleted_at %s is unconfirmed even with the exact IDs', async (invalid) => {
    const f = fixture()
    f.resolve()
    const receipt = markReceipt(ACCOUNT, IDS, NOW.toISOString())
    const rows = receipt.data as Array<Record<string, unknown>>
    receipt.data = rows.map((row, index) => {
      if (index) return row
      const copy = { ...row }
      if (invalid === 'missing') delete copy.deleted_at
      else copy.deleted_at = ESTIMATED_AT
      return copy
    })
    f.dependencies.repository.markDeleted.mockResolvedValue(receipt)
    expect(await f.run()).toMatchObject({ state: 'cleanup_unknown', phase: 'mark' })
    expect(f.dependencies.storage.remove).toHaveBeenCalledOnce()
    expect(f.dependencies.warn).toHaveBeenCalledOnce()
    safeLog(f)
  })

  it('M11c catalogue deleted_at equivalent timestamptz confirms the same deletion instant', async () => {
    const f = fixture()
    f.resolve()
    f.dependencies.repository.markDeleted.mockResolvedValue(
      markReceipt(ACCOUNT, IDS, '2026-10-11T20:00:00.000000+00:00'),
    )
    expect(await f.run()).toEqual({ state: 'complete' })
    expect(f.dependencies.warn).not.toHaveBeenCalled()
  })
})

describe('one 3000 ms budget, late promises and isolated controllers', () => {
  it.each([
    'read',
    'resolve',
    'persist',
    'remove',
    'mark',
  ] as const)('M12 deadline during %s: return unknown at 3000, late resolution never starts next phase', async (phase) => {
    const f = fixture()
    f.resolve()
    const pending = deferred<unknown>()
    if (phase === 'read')
      f.dependencies.repository.loadSnapshot.mockImplementation(
        () => pending.promise as Promise<FinalizationPhoto[]>,
      )
    if (phase === 'resolve')
      f.dependencies.resolveCandidate.mockImplementation(
        () => pending.promise as Promise<CandidateResolution>,
      )
    if (phase === 'persist')
      f.dependencies.repository.persistProvenance.mockImplementation(
        () => pending.promise as Promise<WriteReceipt>,
      )
    if (phase === 'remove')
      f.dependencies.storage.remove.mockImplementation(() => pending.promise as Promise<void>)
    if (phase === 'mark')
      f.dependencies.repository.markDeleted.mockImplementation(
        () => pending.promise as Promise<WriteReceipt>,
      )
    const result = f.run()
    await drain()
    await vi.advanceTimersByTimeAsync(3000)
    expect(await result).toMatchObject({
      state:
        phase === 'read' || phase === 'resolve'
          ? 'source_unknown'
          : phase === 'persist'
            ? 'provenance_unknown'
            : 'cleanup_unknown',
      phase,
      reason: 'timeout',
    })
    const before = [
      f.dependencies.repository.persistProvenance.mock.calls.length,
      f.dependencies.storage.remove.mock.calls.length,
      f.dependencies.repository.markDeleted.mock.calls.length,
    ]
    const patch = {
      bf_percent_estimated: 17.25,
      bf_source: 'signup_photos' as const,
      bf_estimated_at: ESTIMATED_AT,
    }
    pending.resolve(
      phase === 'read'
        ? f.rows
        : phase === 'resolve'
          ? { kind: 'resolved', candidate: ready() }
          : phase === 'persist'
            ? provenanceReceipt(ACCOUNT, patch)
            : phase === 'mark'
              ? markReceipt(ACCOUNT, IDS, NOW.toISOString())
              : undefined,
    )
    await drain()
    expect([
      f.dependencies.repository.persistProvenance.mock.calls.length,
      f.dependencies.storage.remove.mock.calls.length,
      f.dependencies.repository.markDeleted.mock.calls.length,
    ]).toEqual(before)
    expect(f.dependencies.warn).toHaveBeenCalledOnce()
    safeLog(f)
    // No assertion claims rollback or intact remote objects in an in-flight phase.
  })

  it.each([
    'read',
    'resolve',
    'persist',
    'remove',
    'mark',
  ] as const)('M12b rejection AFTER %s timed out has zero subsequent effect or duplicate warning', async (phase) => {
    const f = fixture()
    f.resolve()
    const pending = deferred<unknown>()
    if (phase === 'read')
      f.dependencies.repository.loadSnapshot.mockImplementation(
        () => pending.promise as Promise<FinalizationPhoto[]>,
      )
    if (phase === 'resolve')
      f.dependencies.resolveCandidate.mockImplementation(
        () => pending.promise as Promise<CandidateResolution>,
      )
    if (phase === 'persist')
      f.dependencies.repository.persistProvenance.mockImplementation(
        () => pending.promise as Promise<WriteReceipt>,
      )
    if (phase === 'remove')
      f.dependencies.storage.remove.mockImplementation(() => pending.promise as Promise<void>)
    if (phase === 'mark')
      f.dependencies.repository.markDeleted.mockImplementation(
        () => pending.promise as Promise<WriteReceipt>,
      )
    const result = f.run()
    await drain()
    await vi.advanceTimersByTimeAsync(3000)
    expect(await result).toMatchObject({
      state:
        phase === 'read' || phase === 'resolve'
          ? 'source_unknown'
          : phase === 'persist'
            ? 'provenance_unknown'
            : 'cleanup_unknown',
      phase,
      reason: 'timeout',
    })
    const before = [
      f.dependencies.repository.persistProvenance.mock.calls.length,
      f.dependencies.storage.remove.mock.calls.length,
      f.dependencies.repository.markDeleted.mock.calls.length,
    ]
    expect(f.dependencies.warn).toHaveBeenCalledOnce()
    pending.reject(new Error('synthetic private error ' + ACCOUNT))
    await drain()
    expect([
      f.dependencies.repository.persistProvenance.mock.calls.length,
      f.dependencies.storage.remove.mock.calls.length,
      f.dependencies.repository.markDeleted.mock.calls.length,
    ]).toEqual(before)
    expect(f.dependencies.warn).toHaveBeenCalledOnce()
    safeLog(f)
    // Vitest must also observe no unhandled rejection from the late promise.
  })

  it.each([
    'read',
    'resolve',
    'persist',
    'remove',
    'mark',
  ] as const)('M17 rejection during %s is bounded and never starts the next effect', async (phase) => {
    const f = fixture()
    f.resolve()
    const error = new Error('synthetic private error ' + ACCOUNT)
    if (phase === 'read') f.dependencies.repository.loadSnapshot.mockRejectedValue(error)
    if (phase === 'resolve') f.dependencies.resolveCandidate.mockRejectedValue(error)
    if (phase === 'persist') f.dependencies.repository.persistProvenance.mockRejectedValue(error)
    if (phase === 'remove') f.dependencies.storage.remove.mockRejectedValue(error)
    if (phase === 'mark') f.dependencies.repository.markDeleted.mockRejectedValue(error)
    expect(await f.run()).toMatchObject({
      state:
        phase === 'read' || phase === 'resolve'
          ? 'source_unknown'
          : phase === 'persist'
            ? 'provenance_unknown'
            : 'cleanup_unknown',
      phase,
      reason: 'error',
    })
    if (phase === 'read' || phase === 'resolve') noMutation(f)
    if (phase === 'persist') expect(f.dependencies.storage.remove).not.toHaveBeenCalled()
    if (phase !== 'mark') expect(f.dependencies.repository.markDeleted).not.toHaveBeenCalled()
    expect(f.dependencies.warn).toHaveBeenCalledOnce()
    safeLog(f)
  })

  it('M19 valid receipt is confirmed before the next guard consumes the deadline: cleanup remains pending and remove is never dispatched', async () => {
    const f = fixture()
    f.resolve()
    let requiredReceiptFieldsRead = false
    f.dependencies.now.mockImplementation(
      () => NOW.getTime() + (requiredReceiptFieldsRead ? 3000 : 0),
    )
    f.dependencies.repository.persistProvenance.mockImplementation(async (owner, patch) => {
      f.setProfile({ user_id: owner, ...patch })
      return {
        data: [
          {
            user_id: owner,
            bf_percent_estimated: patch.bf_percent_estimated,
            bf_source: patch.bf_source,
            // No await/clock change occurred during receipt transport. The marker
            // moves only the next guard after required values were inspected.
            get bf_estimated_at() {
              requiredReceiptFieldsRead = true
              return patch.bf_estimated_at
            },
          },
        ],
        error: null,
      }
    })
    expect(await f.run()).toMatchObject({ state: 'provenance_committed_cleanup_pending' })
    expect(requiredReceiptFieldsRead).toBe(true)
    expect(f.dependencies.repository.persistProvenance).toHaveBeenCalledOnce()
    expect(f.profile).toEqual({
      user_id: ACCOUNT,
      bf_percent_estimated: 17.25,
      bf_source: 'signup_photos',
      bf_estimated_at: ESTIMATED_AT,
    })
    expect(f.dependencies.storage.remove).not.toHaveBeenCalled()
    expect(f.dependencies.repository.markDeleted).not.toHaveBeenCalled()
    safeLog(f)
    // M12 separately keeps UPDATE resolving at the deadline provenance_unknown.
  })

  it.each([
    2999, 3000,
  ])('M13 first read resolves at %s ms: strict now >= deadline, never renewed budget', async (milliseconds) => {
    const f = fixture()
    f.resolve()
    f.dependencies.repository.loadSnapshot.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve(f.rows), milliseconds)),
    )
    const result = f.run()
    await vi.advanceTimersByTimeAsync(milliseconds)
    const outcome = await result
    if (milliseconds === 2999) expect(outcome).toEqual({ state: 'complete' })
    else {
      expect(outcome).toMatchObject({ state: 'source_unknown', reason: 'timeout' })
      noMutation(f)
    }
  })

  it('M14 read 1500 + resolve 1400 + persist 200 uses ONE budget: timeout 3000 before cleanup, not 3000 per phase', async () => {
    const f = fixture()
    f.resolve()
    f.dependencies.repository.loadSnapshot.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve(f.rows), 1500)),
    )
    f.dependencies.resolveCandidate.mockImplementation(
      () =>
        new Promise((resolve) =>
          setTimeout(() => resolve({ kind: 'resolved', candidate: ready() }), 1400),
        ),
    )
    f.dependencies.repository.persistProvenance.mockImplementation(
      (_user, patch) =>
        new Promise((resolve) => setTimeout(() => resolve(provenanceReceipt(ACCOUNT, patch)), 200)),
    )
    const result = f.run()
    await vi.advanceTimersByTimeAsync(3000)
    expect(await result).toMatchObject({
      state: 'provenance_unknown',
      phase: 'persist',
      reason: 'timeout',
    })
    await vi.advanceTimersByTimeAsync(100)
    expect(f.dependencies.storage.remove).not.toHaveBeenCalled()
    expect(f.dependencies.repository.markDeleted).not.toHaveBeenCalled()
    expect(f.dependencies.warn).toHaveBeenCalledOnce()
    safeLog(f)
  })

  it('M15 timing out one execution does not abort the second account/operation', async () => {
    const a = fixture()
    const b = fixture(OTHER)
    const readA = deferred<FinalizationPhoto[]>()
    const readB = deferred<FinalizationPhoto[]>()
    a.dependencies.repository.loadSnapshot.mockImplementation(() => readA.promise)
    b.dependencies.repository.loadSnapshot.mockImplementation(() => readB.promise)
    b.resolve(ready(OTHER))
    const resultA = a.run()
    await vi.advanceTimersByTimeAsync(500)
    const resultB = b.run()
    await drain()
    const signalA = a.dependencies.repository.loadSnapshot.mock.calls[0][1]
    const signalB = b.dependencies.repository.loadSnapshot.mock.calls[0][1]
    expect(signalA).not.toBe(signalB)
    await vi.advanceTimersByTimeAsync(2500)
    expect(await resultA).toMatchObject({ state: 'source_unknown', reason: 'timeout' })
    expect(signalA.aborted).toBe(true)
    expect(signalB.aborted).toBe(false)
    readB.resolve(b.rows)
    expect(await resultB).toEqual({ state: 'complete' })
    readA.resolve(a.rows)
    await drain()
    noMutation(a)
    expect(b.dependencies.repository.persistProvenance.mock.calls[0][0]).toBe(OTHER)
  })
})
