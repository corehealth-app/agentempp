import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { completeReevaluationPhotoUpload } from './reevaluation-photo-completion'
import { createSupabaseReevaluationPhotoCompletionDependencies } from './supabase-reevaluation-photo-completion'

const id = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const scope = { userId: id(711), cycleId: id(712), assetId: id(713) }
function setup() {
  const current = {
    version: 1,
    cycle_revision: '2',
    source_revision: '1',
    selection_state: 'pending',
    asset: {
      id: scope.assetId,
      user_id: scope.userId,
      cycle_id: scope.cycleId,
      signup_generation: id(714),
      consent_acceptance_id: id(715),
      origin: 'reevaluation_cycle_v1',
      pose: 'front',
      bucket_id: 'body-checkin-photos',
      object_path: `${scope.userId}/${scope.assetId}.jpg`,
      mime_type: 'image/jpeg',
      size_bytes: 1200,
      status: 'pending_upload',
      created_at: '2026-10-24T22:00:00.000000Z',
      retention_until: '2026-10-25T22:00:00.000000Z',
    },
  }
  const done = {
    ...current,
    cycle_revision: '3',
    source_revision: '2',
    selection_state: 'selected',
    asset: { ...current.asset, status: 'uploaded' },
  }
  const rpc = vi.fn(async (name: string, _args: Record<string, unknown>) => ({
    data: (name === 'get_mobile_reevaluation_photo_upload_completion' ? current : done) as unknown,
    error: null as unknown,
  }))
  const info = vi.fn(async (_path: string) => ({
    data: { size: 1200, contentType: 'IMAGE/JPEG; charset=binary', etag: 'etag' } as unknown,
    error: null as unknown,
  }))
  const from = vi.fn((_bucket: string) => ({ info }))
  const client = { rpc, storage: { from } } as unknown as ServiceClient
  const deps = createSupabaseReevaluationPhotoCompletionDependencies(client)
  return { current, done, rpc, info, from, deps }
}
describe('recurring photo metadata adapter', () => {
  it('real service uses only dedicated context/completion RPCs and exact Storage path', async () => {
    const f = setup()
    expect(await completeReevaluationPhotoUpload(f.deps, scope)).toEqual(f.done)
    expect(f.rpc.mock.calls).toEqual([
      [
        'get_mobile_reevaluation_photo_upload_completion',
        { p_user_id: scope.userId, p_cycle_id: scope.cycleId, p_asset_id: scope.assetId },
      ],
      [
        'complete_mobile_reevaluation_photo_upload',
        {
          p_user_id: scope.userId,
          p_cycle_id: scope.cycleId,
          p_asset_id: scope.assetId,
          p_expected_source_revision: '1',
          p_actual_size_bytes: 1200,
          p_content_type: 'image/jpeg',
          p_etag: 'etag',
        },
      ],
    ])
    expect(f.from).toHaveBeenCalledTimes(1)
    expect(f.from).toHaveBeenCalledWith('body-checkin-photos')
    expect(f.info).toHaveBeenCalledTimes(1)
    expect(f.info).toHaveBeenCalledWith(f.current.asset.object_path)
  })
  it.each([
    404,
    '404',
    400,
    '400',
  ])('missing object %s refuses without commit or deletion', async (status) => {
    const f = setup()
    f.info.mockResolvedValue({ data: null, error: { status, message: 'private' } })
    await expect(completeReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({
      status: 409,
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it('transient metadata error remains retryable without SQL mutation', async () => {
    const f = setup()
    f.info.mockResolvedValue({ data: null, error: { statusCode: 503, message: 'token=private' } })
    await expect(completeReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({
      status: 503,
      message: 'Photo completion is unavailable',
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    null,
    { size: Number.NaN, contentType: 'image/jpeg', etag: null },
    { size: 1200, contentType: 42, etag: null },
  ])('rejects malformed SDK data %j', async (data) => {
    const f = setup()
    f.info.mockResolvedValue({ data, error: null })
    await expect(completeReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({
      status: data === null ? 409 : 422,
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    '40001',
    'P0002',
  ])('propagates stale authority %s after metadata without retry', async (code) => {
    const f = setup()
    f.rpc
      .mockResolvedValueOnce({ data: f.current, error: null })
      .mockResolvedValueOnce({ data: null, error: { code, message: 'private' } })
    await expect(completeReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({
      status: 409,
    })
    expect(f.rpc).toHaveBeenCalledTimes(2)
  })
  it('rejects a foreign context before reading any object', async () => {
    const f = setup()
    f.current.asset.cycle_id = id(999)
    await expect(completeReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({
      status: 503,
    })
    expect(f.from).not.toHaveBeenCalled()
  })
  it('rejects foreign commit receipt even with success envelope', async () => {
    const f = setup()
    f.done.asset.consent_acceptance_id = id(999)
    await expect(completeReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({
      status: 503,
    })
  })
  it('sanitizes an ambiguous RPC transport failure and never repeats it', async () => {
    const f = setup()
    f.rpc
      .mockResolvedValueOnce({ data: f.current, error: null })
      .mockRejectedValueOnce(new Error('secret'))
    await expect(completeReevaluationPhotoUpload(f.deps, scope)).rejects.toMatchObject({
      status: 503,
      message: 'Photo completion is unavailable',
    })
    expect(f.rpc).toHaveBeenCalledTimes(2)
  })
})
