import { describe, expect, it, vi } from 'vitest'
import {
  completeReevaluationPhotoUpload,
  type ReevaluationPhotoCompletionDependencies,
} from './reevaluation-photo-completion'

const completionScope = {
  userId: 'b3b01000-0000-4000-8000-000000000701',
  cycleId: 'b3b01000-0000-4000-8000-000000000702',
  assetId: 'b3b01000-0000-4000-8000-000000000703',
}
function completionWire(selected = false) {
  return {
    version: 1,
    cycle_revision: selected ? '3' : '2',
    source_revision: selected ? '2' : '1',
    selection_state: selected ? 'selected' : 'pending',
    asset: {
      id: completionScope.assetId,
      user_id: completionScope.userId,
      cycle_id: completionScope.cycleId,
      signup_generation: 'b3b01000-0000-4000-8000-000000000704',
      consent_acceptance_id: 'b3b01000-0000-4000-8000-000000000705',
      origin: 'reevaluation_cycle_v1',
      pose: 'front',
      bucket_id: 'body-checkin-photos',
      object_path: `${completionScope.userId}/${completionScope.assetId}.jpg`,
      mime_type: 'image/jpeg',
      size_bytes: 1200,
      status: selected ? 'uploaded' : 'pending_upload',
      created_at: '2026-10-24T22:00:00.000000Z',
      retention_until: '2026-10-25T22:00:00.000000Z',
    },
  }
}
function setup() {
  const deps = {
    current: vi
      .fn<ReevaluationPhotoCompletionDependencies['current']>()
      .mockResolvedValue(completionWire()),
    info: vi.fn<ReevaluationPhotoCompletionDependencies['info']>().mockResolvedValue({
      size: 1200,
      contentType: ' Image/JPEG; charset=binary ',
      etag: 'etag-1',
    }),
    commit: vi
      .fn<ReevaluationPhotoCompletionDependencies['commit']>()
      .mockResolvedValue(completionWire(true)),
  } satisfies ReevaluationPhotoCompletionDependencies
  return deps
}
describe('recurring photo completion service', () => {
  it('gets authority, awaits metadata, commits exact normalized metadata', async () => {
    const deps = setup()
    const result = await completeReevaluationPhotoUpload(deps, completionScope)
    expect(deps.info).toHaveBeenCalledWith(completionWire().asset)
    expect(deps.commit).toHaveBeenCalledWith(completionWire(), {
      size: 1200,
      contentType: 'image/jpeg',
      etag: 'etag-1',
    })
    expect(result).toEqual(completionWire(true))
    expect(deps.current.mock.invocationCallOrder[0]).toBeLessThan(
      deps.info.mock.invocationCallOrder[0],
    )
    expect(deps.info.mock.invocationCallOrder[0]).toBeLessThan(
      deps.commit.mock.invocationCallOrder[0],
    )
  })
  it('never selects while metadata is unresolved', async () => {
    const deps = setup()
    let resolve!: (value: unknown) => void
    deps.info.mockImplementation(
      () =>
        new Promise((done) => {
          resolve = done
        }),
    )
    const task = completeReevaluationPhotoUpload(deps, completionScope)
    await vi.waitFor(() => expect(deps.info).toHaveBeenCalledOnce())
    expect(deps.commit).not.toHaveBeenCalled()
    resolve({ size: 1200, contentType: 'image/jpeg', etag: null })
    await task
    expect(deps.commit).toHaveBeenCalledOnce()
  })
  it.each([
    'reset',
    'expired',
    'source_replaced',
    'softdelete',
  ])('honors SQL authority after metadata await: %s', async () => {
    const deps = setup()
    deps.commit.mockRejectedValue({ code: '40001', message: 'secret-provider-value' })
    await expect(completeReevaluationPhotoUpload(deps, completionScope)).rejects.toMatchObject({
      status: 503,
    })
    expect(deps.commit).toHaveBeenCalledOnce()
  })
  it.each([
    { size: 1199, contentType: 'image/jpeg', etag: null },
    { size: Number.NaN, contentType: 'image/jpeg', etag: null },
    { size: Number.POSITIVE_INFINITY, contentType: 'image/jpeg', etag: null },
    { size: 1200.5, contentType: 'image/jpeg', etag: null },
    { size: 0, contentType: 'image/jpeg', etag: null },
    { size: 1200, contentType: 'image/png', etag: null },
    { size: 1200, contentType: null, etag: null },
    { size: 1200, contentType: 'image/jpeg', etag: '' },
    { size: 1200, contentType: 'image/jpeg', etag: 'bad\nvalue' },
    { size: 1200, contentType: 'image/jpeg', etag: 'x'.repeat(257) },
    { size: 1200, contentType: 'image/jpeg', etag: 42 },
    { size: 1200, contentType: 'image/jpeg', etag: null, token: 'unexpected' },
  ])('refuses invalid or mismatching Storage metadata: %j', async (metadata) => {
    const deps = setup()
    deps.info.mockResolvedValue(metadata)
    await expect(completeReevaluationPhotoUpload(deps, completionScope)).rejects.toMatchObject({
      status: 422,
    })
    expect(deps.commit).not.toHaveBeenCalled()
  })
  it.each([
    null,
    {},
    { ...completionWire(), extra: true },
    { ...completionWire(), source_revision: '01' },
  ])('refuses malformed current wire before Storage', async (wire) => {
    const deps = setup()
    deps.current.mockResolvedValue(wire)
    await expect(completeReevaluationPhotoUpload(deps, completionScope)).rejects.toMatchObject({
      status: 503,
    })
    expect(deps.info).not.toHaveBeenCalled()
  })
  it('refuses a foreign asset before Storage', async () => {
    const deps = setup()
    const wire = completionWire()
    wire.asset.cycle_id = wire.asset.signup_generation
    deps.current.mockResolvedValue(wire)
    await expect(completeReevaluationPhotoUpload(deps, completionScope)).rejects.toMatchObject({
      status: 503,
    })
    expect(deps.info).not.toHaveBeenCalled()
  })
  it.each([
    'pose',
    'signup_generation',
    'consent_acceptance_id',
  ])('refuses immutable %s corruption in commit receipt', async (field) => {
    const deps = setup()
    const wire = completionWire(true)
    Object.assign(wire.asset, { [field]: field === 'pose' ? 'side' : completionScope.cycleId })
    deps.commit.mockResolvedValue(wire)
    await expect(completeReevaluationPhotoUpload(deps, completionScope)).rejects.toMatchObject({
      status: 503,
    })
  })
  it.each([
    { source_revision: '1' },
    { source_revision: '3' },
    { cycle_revision: '2' },
    { selection_state: 'pending' },
  ])('refuses uncommitted or unexpected receipt revisions %j', async (fields) => {
    const deps = setup()
    deps.commit.mockResolvedValue({ ...completionWire(true), ...fields })
    await expect(completeReevaluationPhotoUpload(deps, completionScope)).rejects.toMatchObject({
      status: 503,
    })
  })
  it('accepts unrelated pose progress while preserving its exact source revision', async () => {
    const deps = setup()
    deps.commit.mockResolvedValue({ ...completionWire(true), cycle_revision: '6' })
    expect((await completeReevaluationPhotoUpload(deps, completionScope)).cycle_revision).toBe('6')
  })
  it('replays a selected upload without incrementing its revision', async () => {
    const deps = setup()
    deps.current.mockResolvedValue(completionWire(true))
    expect(await completeReevaluationPhotoUpload(deps, completionScope)).toEqual(
      completionWire(true),
    )
  })
  it('sanitizes provider failures and never commits after a failed metadata read', async () => {
    const deps = setup()
    deps.info.mockRejectedValue(new Error('token=private'))
    await expect(completeReevaluationPhotoUpload(deps, completionScope)).rejects.toMatchObject({
      status: 503,
      message: 'Photo completion is unavailable',
    })
    expect(deps.commit).not.toHaveBeenCalled()
  })
})
