import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import {
  createReevaluationPhotoLifecycleService,
  type ReevaluationPhotoLifecycleOperations,
} from './reevaluation-photo-lifecycle'
import { uid } from './testing/reevaluation-photo-consent-fixture'
import { processingWire, snapshotFixture } from './testing/reevaluation-photo-processing-fixtures'

function setup() {
  const wire = processingWire('succeeded'),
    a = wire.asset
  const auth = {
    userId: a.user_id,
    authUserId: uid(5699),
    identity: { id: uid(5699) },
    patient: { id: a.user_id, authUserId: uid(5699), status: 'active' },
  } as MobileAuthContext
  const privateOutcome = { status: 'processed' as const, privateNote: 'fake-private-marker' }
  const operations: ReevaluationPhotoLifecycleOperations = {
    snapshot: vi.fn().mockResolvedValue(structuredClone(snapshotFixture.snapshot)),
    allocate: vi.fn().mockResolvedValue({
      availability: 'available',
      version: 1,
      cycle_revision: wire.cycle_revision,
      asset: a,
    }),
    upload: vi.fn().mockResolvedValue({
      asset: { ...a, status: 'pending_upload' },
      upload: {
        signed_url: `https://test-project.supabase.co/storage/v1/object/upload/sign/body-checkin-photos/${a.object_path}?token=synthetic`,
        method: 'PUT',
        headers: {
          'Content-Type': a.mime_type,
          'x-upsert': 'false',
          Authorization: 'fake-private-marker',
        },
        expires_at: new Date(a.retention_until).toISOString(),
      },
    }),
    complete: vi.fn().mockResolvedValue({
      version: 1,
      cycle_revision: wire.cycle_revision,
      source_revision: wire.source_revision,
      asset: a,
      selection_state: 'selected',
    }),
    process: vi.fn().mockResolvedValue(privateOutcome),
    discard: vi.fn().mockResolvedValue({
      id: uid(5670),
      user_id: a.user_id,
      cycle_id: a.cycle_id,
      acceptance_id: a.consent_acceptance_id,
      reason: 'discarded',
      request_revision: wire.cycle_revision,
      signup_generation: a.signup_generation,
      sweep_state: 'idle',
    }),
    drain: vi.fn().mockResolvedValue({ state: 'waiting', newlyDeleted: 0 }),
  }
  const input = {
    expectedRevision: wire.cycle_revision,
    acceptanceId: a.consent_acceptance_id,
    pose: a.pose,
    mimeType: a.mime_type,
    sizeBytes: a.size_bytes,
  }
  return {
    wire,
    a,
    auth,
    operations,
    input,
    service: createReevaluationPhotoLifecycleService(operations),
  }
}
describe('recurring lifecycle — patient-safe projection and existing authority', () => {
  it('projects current pose/status identities without the raw provider/private source packet', async () => {
    const x = setup(),
      value = await x.service.snapshot(x.auth, x.a.cycle_id)
    expect(value.photos.map((p) => p.pose)).toEqual(['front', 'side', 'back'])
    expect(value.photos.every((p) => p.asset?.status === 'processed')).toBe(true)
    for (const key of [
      'user_id',
      'signup_generation',
      'analysis',
      'bf_percent_estimate',
      'body_hash',
      'photo_fingerprint',
    ])
      expect(JSON.stringify(value)).not.toContain(key)
    const wrong = structuredClone(snapshotFixture.snapshot)
    wrong.photos[0].photo.user_id = uid(5690)
    vi.mocked(x.operations.snapshot).mockResolvedValueOnce(wrong)
    await expect(x.service.snapshot(x.auth, x.a.cycle_id)).rejects.toMatchObject({ status: 503 })
  })
  it('shows the three validated current readings without exposing provider metadata or writing anything', async () => {
    const x = setup(),
      raw = structuredClone(snapshotFixture.snapshot)
    raw.photos.forEach((slot, index) => {
      slot.photo.analysis.bf_percent_estimate = [22.25, 24.5, 26.75][index]
      Object.assign(slot.photo.analysis, { private_note: 'fake-private-marker' })
    })
    vi.mocked(x.operations.snapshot).mockResolvedValueOnce(raw)
    const value = await x.service.snapshot(x.auth, x.a.cycle_id)
    expect(value.photos).toEqual(
      raw.photos.map((slot) => ({
        pose: slot.pose,
        asset: {
          id: slot.photo.asset_id,
          status: 'processed',
          estimated_body_fat_percent: slot.photo.analysis.bf_percent_estimate,
        },
      })),
    )
    expect(JSON.stringify(value)).not.toContain('fake-private-marker')
    expect(x.operations.allocate).not.toHaveBeenCalled()
    expect(x.operations.process).not.toHaveBeenCalled()
    expect(x.operations.discard).not.toHaveBeenCalled()
  })
  it.each([
    'pending',
    'failed',
    'missing',
    'unreadable',
    'wrong_pose',
    'out_of_range',
  ] as const)('withholds all readings when the current triplet is %s', async (kind) => {
    const x = setup(),
      raw = structuredClone(snapshotFixture.snapshot)
    if (kind === 'pending') raw.photos[1].photo.status = 'processing'
    if (kind === 'failed') raw.photos[1].photo.status = 'failed'
    if (kind === 'wrong_pose') raw.photos[1].photo.analysis.view = 'front'
    if (kind === 'out_of_range') raw.photos[1].photo.analysis.bf_percent_estimate = 61
    const response: unknown = {
      ...raw,
      photos: raw.photos.map((slot, index) => {
        if (index !== 1) return slot
        if (kind === 'missing') return { ...slot, photo: null }
        if (kind === 'unreadable')
          return {
            ...slot,
            photo: {
              ...slot.photo,
              analysis: { ...slot.photo.analysis, bf_percent_estimate: null },
            },
          }
        return slot
      }),
    }
    vi.mocked(x.operations.snapshot).mockResolvedValueOnce(response)
    const value = await x.service.snapshot(x.auth, x.a.cycle_id)
    expect(
      value.photos.every(
        (slot) => slot.asset === null || slot.asset.estimated_body_fat_percent === null,
      ),
    ).toBe(true)
  })
  it('binds allocation to owner/cycle/header intention and strips all private asset fields', async () => {
    const x = setup(),
      value = await x.service.allocate(x.auth, x.a.cycle_id, uid(5604), x.input)
    expect(x.operations.allocate).toHaveBeenCalledWith(x.auth, {
      ...x.input,
      cycleId: x.a.cycle_id,
      requestKey: uid(5604),
    })
    expect(value.cycle_revision).toBe(x.wire.cycle_revision)
    for (const key of ['user_id', 'signup_generation', 'object_path', 'bucket_id', 'origin'])
      expect(JSON.stringify(value)).not.toContain(key)
    await expect(
      x.service.allocate(x.auth, x.a.cycle_id, uid(5604), { ...x.input, meanHundredths: 2200 }),
    ).rejects.toMatchObject({ status: 422 })
    expect(x.operations.allocate).toHaveBeenCalledOnce()
  })
  it('exposes only the narrow PUT capability, never extra headers or processing notes', async () => {
    const x = setup(),
      upload = await x.service.upload(x.auth, x.a.cycle_id, x.a.id)
    expect(upload.upload.headers).toEqual({ 'Content-Type': x.a.mime_type, 'x-upsert': 'false' })
    expect(JSON.stringify(upload)).not.toContain('fake-private-marker')
    const processed = await x.service.process(x.auth, x.a.cycle_id, x.a.id, uid(5604))
    expect(processed).toEqual({
      version: 1,
      cycle_id: x.a.cycle_id,
      asset_id: x.a.id,
      status: 'processed',
    })
    expect(x.operations.process).toHaveBeenCalledWith({
      userId: x.a.user_id,
      cycleId: x.a.cycle_id,
      assetId: x.a.id,
      requestId: uid(5604),
    })
  })
  it('returns the server revision after completion and does not infer a revision after discard', async () => {
    const x = setup(),
      completed = await x.service.complete(x.auth, x.a.cycle_id, x.a.id)
    expect(completed.cycle_revision).toBe(x.wire.cycle_revision)
    const value = await x.service.discard(x.auth, x.a.cycle_id, {
      expectedRevision: x.wire.cycle_revision,
      acceptanceId: x.a.consent_acceptance_id,
    })
    expect(value).toEqual({
      version: 1,
      cycle_id: x.a.cycle_id,
      acceptance_id: x.a.consent_acceptance_id,
      status: 'discard_requested',
      deletion: 'waiting',
    })
    expect(value).not.toHaveProperty('cycle_revision')
    vi.mocked(x.operations.drain).mockRejectedValueOnce(new Error('private removal failure'))
    expect(
      (
        await x.service.discard(x.auth, x.a.cycle_id, {
          expectedRevision: x.wire.cycle_revision,
          acceptanceId: x.a.consent_acceptance_id,
        })
      ).deletion,
    ).toBe('pending')
  })
  it('does not drain an unverified discard receipt or forward raw dependency errors', async () => {
    const x = setup()
    vi.mocked(x.operations.discard).mockResolvedValueOnce({
      id: uid(5670),
      user_id: uid(5690),
      cycle_id: x.a.cycle_id,
      acceptance_id: x.a.consent_acceptance_id,
      reason: 'discarded',
      request_revision: x.wire.cycle_revision,
    })
    await expect(
      x.service.discard(x.auth, x.a.cycle_id, {
        expectedRevision: x.wire.cycle_revision,
        acceptanceId: x.a.consent_acceptance_id,
      }),
    ).rejects.toMatchObject({ status: 503 })
    expect(x.operations.drain).not.toHaveBeenCalled()
    vi.mocked(x.operations.process).mockRejectedValueOnce(new Error('fake-private-marker'))
    await expect(x.service.process(x.auth, x.a.cycle_id, x.a.id, uid(5604))).rejects.toMatchObject({
      status: 503,
      message: 'Reassessment photo operation is unavailable',
    })
  })
})
