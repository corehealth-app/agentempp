import { describe, expect, it, vi } from 'vitest'
import { MobileApiError } from './http'
import {
  processReevaluationPhoto,
  type ReevaluationPhotoProcessingDependencies,
} from './reevaluation-photo-processing'
import {
  jpegBytes,
  processingWire,
  processingScope as scope,
} from './testing/reevaluation-photo-processing-fixtures'

function setup() {
  return {
    now: vi.fn(() => new Date(Date.parse(processingWire().attempt.claimed_at) + 2000)),
    claim: vi
      .fn<ReevaluationPhotoProcessingDependencies['claim']>()
      .mockResolvedValue(processingWire()),
    download: vi
      .fn<ReevaluationPhotoProcessingDependencies['download']>()
      .mockResolvedValue(jpegBytes()),
    authorize: vi
      .fn<ReevaluationPhotoProcessingDependencies['authorize']>()
      .mockResolvedValue(processingWire('authorized')),
    analyze: vi.fn<ReevaluationPhotoProcessingDependencies['analyze']>().mockResolvedValue({
      type: 'body',
      view: 'front',
      bf_percent_estimate: 22,
      raw_response: 'private',
      notes: 'https://private.invalid',
    }),
    complete: vi
      .fn<ReevaluationPhotoProcessingDependencies['complete']>()
      .mockResolvedValue(processingWire('succeeded')),
    fail: vi.fn<ReevaluationPhotoProcessingDependencies['fail']>().mockResolvedValue(true),
  }
}
describe('dedicated recurring photo processor', () => {
  it('validates bytes, authorizes immediately before analysis, and persists only approved keys', async () => {
    const f = setup()
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'processed' })
    expect(f.analyze).toHaveBeenCalledWith(
      jpegBytes(),
      'image/jpeg',
      expect.objectContaining({ signal: expect.any(AbortSignal), timeoutMs: 60000 }),
    )
    expect(f.complete).toHaveBeenCalledWith(processingWire('authorized'), {
      type: 'body',
      view: 'front',
      bf_percent_estimate: 22,
    })
    const calls = [f.claim, f.download, f.authorize, f.analyze, f.complete].map(
      (fn) => fn.mock.invocationCallOrder[0],
    )
    expect(calls).toEqual([...calls].sort((a, b) => a - b))
    expect(f.fail).not.toHaveBeenCalled()
  })
  it('does not authorize or pay until download resolves', async () => {
    const f = setup()
    let done!: (bytes: Uint8Array) => void
    f.download.mockImplementation(
      () =>
        new Promise((resolve) => {
          done = resolve
        }),
    )
    const task = processReevaluationPhoto(f, scope)
    await vi.waitFor(() => expect(f.download).toHaveBeenCalledOnce())
    expect(f.authorize).not.toHaveBeenCalled()
    expect(f.analyze).not.toHaveBeenCalled()
    done(jpegBytes())
    await task
  })
  it('refuses stale authority after download without a provider call', async () => {
    const f = setup()
    f.authorize.mockRejectedValue(new MobileApiError(409, 'changed', 'private'))
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'skipped' })
    expect(f.analyze).not.toHaveBeenCalled()
    expect(f.complete).not.toHaveBeenCalled()
  })
  it('refuses provider authorization delivered after its lease deadline', async () => {
    const f = setup()
    f.now.mockReturnValue(new Date(processingWire().attempt.lease_until))
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'skipped' })
    expect(f.analyze).not.toHaveBeenCalled()
    expect(f.fail).not.toHaveBeenCalled()
  })
  it('rejects authorization delivered at the scheduled consent boundary before the original lease', async () => {
    const f = setup()
    const auth = {
      ...processingWire('authorized'),
      attempt: {
        ...processingWire('authorized').attempt,
        provider_authorized_until: new Date(Date.parse(processingWire().attempt.claimed_at) + 20000)
          .toISOString()
          .replace('Z', '000Z'),
      },
    }
    f.authorize.mockResolvedValue(auth)
    f.now.mockReturnValue(new Date(auth.attempt.provider_authorized_until))
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'skipped' })
    expect(f.analyze).not.toHaveBeenCalled()
    expect(f.complete).not.toHaveBeenCalled()
    expect(f.fail).not.toHaveBeenCalled()
  })
  it('bounds provider timeout by the scheduled consent cutoff', async () => {
    const f = setup()
    const deadline = new Date(Date.parse(processingWire().attempt.claimed_at) + 20000)
      .toISOString()
      .replace('Z', '000Z')
    const auth = {
      ...processingWire('authorized'),
      attempt: { ...processingWire('authorized').attempt, provider_authorized_until: deadline },
    }
    const done = {
      ...processingWire('succeeded'),
      attempt: { ...processingWire('succeeded').attempt, provider_authorized_until: deadline },
    }
    f.authorize.mockResolvedValue(auth)
    f.complete.mockResolvedValue(done)
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'processed' })
    expect(f.analyze).toHaveBeenCalledWith(
      jpegBytes(),
      'image/jpeg',
      expect.objectContaining({ timeoutMs: 18000, signal: expect.any(AbortSignal) }),
    )
  })
  it.each([
    'missing',
    'before_start',
    'after_lease',
  ])('rejects invalid authorization deadline: %s', async (mode) => {
    const f = setup()
    const auth = processingWire('authorized')
    auth.attempt.provider_authorized_until =
      mode === 'missing'
        ? null
        : mode === 'before_start'
          ? auth.attempt.claimed_at
          : auth.asset.retention_until
    f.authorize.mockResolvedValue(auth)
    await expect(processReevaluationPhoto(f, scope)).rejects.toMatchObject({ status: 503 })
    expect(f.analyze).not.toHaveBeenCalled()
  })
  it('rejects a receipt that extends the authorized provider deadline', async () => {
    const f = setup()
    const auth = processingWire('authorized')
    auth.attempt.provider_authorized_until = new Date(Date.parse(auth.attempt.claimed_at) + 20000)
      .toISOString()
      .replace('Z', '000Z')
    f.authorize.mockResolvedValue(auth)
    await expect(processReevaluationPhoto(f, scope)).rejects.toMatchObject({ status: 503 })
    expect(f.analyze).toHaveBeenCalledOnce()
    expect(f.fail).not.toHaveBeenCalled()
  })
  it('discards delayed provider result when SQL source changed', async () => {
    const f = setup()
    let done!: (value: unknown) => void
    f.analyze.mockImplementation(
      () =>
        new Promise((resolve) => {
          done = resolve
        }),
    )
    const task = processReevaluationPhoto(f, scope)
    await vi.waitFor(() => expect(f.analyze).toHaveBeenCalledOnce())
    f.complete.mockRejectedValue(new MobileApiError(409, 'changed', 'private'))
    done({ type: 'body', view: 'front', bf_percent_estimate: 22 })
    expect(await task).toEqual({ status: 'skipped' })
    expect(f.fail).not.toHaveBeenCalled()
  })
  it.each([
    new Uint8Array(),
    new Uint8Array(1199),
    new Uint8Array(1200),
    new Uint8Array(1201),
  ])('invalid size/signature blocks provider', async (bytes) => {
    const f = setup()
    f.download.mockResolvedValue(bytes)
    expect(await processReevaluationPhoto(f, scope)).toEqual({
      status: 'failed',
      reason: 'invalid_bytes',
    })
    expect(f.authorize).not.toHaveBeenCalled()
    expect(f.analyze).not.toHaveBeenCalled()
    expect(f.fail).toHaveBeenCalledWith(processingWire(), 'invalid_bytes')
  })
  it.each([
    { type: 'meal', view: 'front', bf_percent_estimate: 22 },
    { type: 'body', view: 'unknown', bf_percent_estimate: 22 },
    { type: 'body', view: 'side', bf_percent_estimate: 22 },
    ...[null, Number.NaN, Number.POSITIVE_INFINITY, 2.99, 60.01, '22'].map((bf) => ({
      type: 'body',
      view: 'front',
      bf_percent_estimate: bf,
    })),
  ])('refuses bad provider classification/reading %j', async (analysis) => {
    const f = setup()
    f.analyze.mockResolvedValue(analysis)
    expect(await processReevaluationPhoto(f, scope)).toEqual({
      status: 'failed',
      reason: 'invalid_analysis',
    })
    expect(f.complete).not.toHaveBeenCalled()
    expect(f.fail).toHaveBeenCalledOnce()
  })
  it('claim null or duplicate authorization never pays', async () => {
    const f = setup()
    f.claim.mockResolvedValueOnce(null)
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'skipped' })
    expect(f.download).not.toHaveBeenCalled()
    f.authorize.mockResolvedValueOnce(null)
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'skipped' })
    expect(f.analyze).not.toHaveBeenCalled()
  })
  it('terminal replay returns without redownload or analysis', async () => {
    const f = setup()
    f.claim.mockResolvedValue(processingWire('succeeded'))
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'processed' })
    expect(f.download).not.toHaveBeenCalled()
    expect(f.analyze).not.toHaveBeenCalled()
  })
  it('ambiguous completion never closes the attempt or repeats a paid call', async () => {
    const f = setup()
    f.complete.mockRejectedValue(new Error('token=private'))
    await expect(processReevaluationPhoto(f, scope)).rejects.toMatchObject({
      status: 503,
      message: 'Photo processing is unavailable',
    })
    expect(f.fail).not.toHaveBeenCalled()
    expect(f.analyze).toHaveBeenCalledOnce()
    f.claim.mockResolvedValue(processingWire('succeeded'))
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'processed' })
    expect(f.analyze).toHaveBeenCalledOnce()
  })
  it.each([
    'download',
    'analyze',
  ] as const)('sanitizes %s error and conditionally fails only this attempt', async (phase) => {
    const f = setup()
    f[phase].mockRejectedValue(new Error('raw secret'))
    await expect(processReevaluationPhoto(f, scope)).rejects.toMatchObject({
      status: 503,
      message: 'Photo processing is unavailable',
    })
    expect(f.fail).toHaveBeenCalledOnce()
    expect(f.complete).not.toHaveBeenCalled()
  })
  it('a failure that lost its claim is skipped', async () => {
    const f = setup()
    f.download.mockResolvedValue(new Uint8Array())
    f.fail.mockResolvedValue(false)
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'skipped' })
  })
  it.each([
    'invalid_bytes',
    'invalid_analysis',
  ])('sanitizes failure-recording rejection for %s', async (reason) => {
    const f = setup()
    if (reason === 'invalid_bytes') f.download.mockResolvedValue(new Uint8Array())
    else f.analyze.mockResolvedValue(null)
    f.fail.mockRejectedValue(new Error('raw-private-provider-value'))
    await expect(processReevaluationPhoto(f, scope)).rejects.toMatchObject({
      status: 503,
      message: 'Photo processing is unavailable',
    })
  })
  it.each([
    ['image/png', 'png', [137, 80, 78, 71, 13, 10, 26, 10]],
    ['image/webp', 'webp', [82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80]],
    ['image/heic', 'heic', [0, 0, 0, 20, 102, 116, 121, 112, 104, 101, 105, 99]],
    ['image/heif', 'heif', [0, 0, 0, 20, 102, 116, 121, 112, 109, 105, 102, 49]],
  ])('accepts supported %s signature', async (mime, extension, prefix) => {
    const f = setup()
    const bytes = new Uint8Array(1200)
    bytes.set(prefix as number[])
    f.download.mockResolvedValue(bytes)
    const wires = [processingWire(), processingWire('authorized'), processingWire('succeeded')]
    for (const wire of wires) {
      wire.asset.mime_type = mime as string
      wire.asset.object_path = wire.asset.object_path.replace(/jpg$/, extension as string)
    }
    f.claim.mockResolvedValue(wires[0])
    f.authorize.mockResolvedValue(wires[1])
    f.complete.mockResolvedValue(wires[2])
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'processed' })
    expect(f.analyze).toHaveBeenCalledWith(
      bytes,
      mime,
      expect.objectContaining({ signal: expect.any(AbortSignal) }),
    )
  })
  it.each([
    'source_revision',
    'signup_generation',
    'consent_acceptance_id',
    'pose',
  ])('refuses altered %s before provider', async (field) => {
    const f = setup()
    const wire = processingWire('authorized')
    if (field === 'source_revision') wire.source_revision = wire.attempt.source_revision = '3'
    else Object.assign(wire.asset, { [field]: field === 'pose' ? 'side' : scope.requestId })
    f.authorize.mockResolvedValue(wire)
    await expect(processReevaluationPhoto(f, scope)).rejects.toMatchObject({ status: 503 })
    expect(f.analyze).not.toHaveBeenCalled()
  })
  it('accepts unrelated pose cycle progress with exact attempt identity', async () => {
    const f = setup()
    const auth = processingWire('authorized')
    const done = processingWire('succeeded')
    auth.cycle_revision = '7'
    done.cycle_revision = '8'
    f.authorize.mockResolvedValue(auth)
    f.complete.mockResolvedValue(done)
    expect(await processReevaluationPhoto(f, scope)).toEqual({ status: 'processed' })
  })
  it('rejects receipt with changed reading or request hash', async () => {
    const f = setup()
    const done = processingWire('succeeded')
    done.attempt.processing_request_id = 'b'.repeat(64)
    f.complete.mockResolvedValue(done)
    await expect(processReevaluationPhoto(f, scope)).rejects.toMatchObject({ status: 503 })
  })
})
