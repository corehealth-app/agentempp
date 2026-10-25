import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { z } from 'zod'
import { processReevaluationPhoto } from './reevaluation-photo-processing'
import { createSupabaseReevaluationPhotoProcessingDependencies } from './supabase-reevaluation-photo-processing'
import {
  jpegBytes,
  processingWire,
  processingScope as scope,
  snapshotFixture,
} from './testing/reevaluation-photo-processing-fixtures'

function setup() {
  const rpc = vi.fn(async (name: string, _args: Record<string, unknown>) => {
    let data: unknown = null
    if (name === 'claim_mobile_reevaluation_photo_processing') data = processingWire()
    if (name === 'authorize_mobile_reevaluation_photo_provider') data = processingWire('authorized')
    if (name === 'complete_mobile_reevaluation_photo_processing') data = processingWire('succeeded')
    if (name === 'fail_mobile_reevaluation_photo_processing') data = true
    if (name === 'get_mobile_reevaluation_photo_snapshot') data = snapshotFixture.snapshot
    return { data, error: null as unknown }
  })
  const download = vi.fn(async (_path: string) => ({
    data: { size: 1200, arrayBuffer: async () => jpegBytes().buffer } as unknown,
    error: null as unknown,
  }))
  const from = vi.fn((_bucket: string) => ({ download }))
  const analyze = vi.fn(async (_bytes: Uint8Array, _mime: string) => ({
    type: 'body',
    view: 'front',
    bf_percent_estimate: 22,
    notes: 'private',
  }))
  const deps = createSupabaseReevaluationPhotoProcessingDependencies(
    { rpc, storage: { from } } as unknown as ServiceClient,
    { analyze, now: () => new Date(Date.parse(processingWire().attempt.claimed_at) + 2000) },
  )
  return { deps, rpc, download, from, analyze }
}
describe('dedicated recurring processing adapter', () => {
  it('uses only dedicated RPCs and exact private download with actual processor', async () => {
    const f = setup()
    expect(await processReevaluationPhoto(f.deps, scope)).toEqual({ status: 'processed' })
    expect(f.rpc.mock.calls.map(([name]) => name)).toEqual([
      'claim_mobile_reevaluation_photo_processing',
      'authorize_mobile_reevaluation_photo_provider',
      'complete_mobile_reevaluation_photo_processing',
    ])
    expect(f.from).toHaveBeenCalledWith('body-checkin-photos')
    expect(f.download).toHaveBeenCalledWith(processingWire().asset.object_path)
    expect(f.rpc.mock.calls[2][1]).toEqual({
      p_user_id: scope.userId,
      p_cycle_id: scope.cycleId,
      p_asset_id: scope.assetId,
      p_request_id: scope.requestId,
      p_result: { type: 'body', view: 'front', bf_percent_estimate: 22 },
    })
  })
  it('composes the real SQL-produced three-pose snapshot with existing mean calculation', async () => {
    const f = setup()
    const result = await f.deps.resolveCandidate({
      ...snapshotFixture.context,
      currentConsent: {
        ...snapshotFixture.context.currentConsent,
        documentKey: z
          .literal('body_photo_reevaluation_consent')
          .parse(snapshotFixture.context.currentConsent.documentKey),
        locale: z.enum(['pt-BR', 'en-US']).parse(snapshotFixture.context.currentConsent.locale),
      },
    })
    expect(result.status).toBe('ready')
    if (result.status !== 'ready') throw new Error('SQL snapshot should be ready')
    expect(result.estimate.by_sex.masculino).toEqual({
      usable: true,
      body_fat_percent: snapshotFixture.expected_mean,
    })
    expect(result.estimate.readings.map((reading) => reading.body_fat_percent)).toEqual([
      22, 24, 26,
    ])
    expect(f.rpc).toHaveBeenCalledWith('get_mobile_reevaluation_photo_snapshot', {
      p_user_id: scope.userId,
      p_cycle_id: scope.cycleId,
    })
    expect(f.from).not.toHaveBeenCalled()
    expect(f.analyze).not.toHaveBeenCalled()
  })
  it.each(['40001', 'P0002'])('blocks provider after stale authorization %s', async (code) => {
    const f = setup()
    f.rpc
      .mockResolvedValueOnce({ data: processingWire(), error: null })
      .mockResolvedValueOnce({ data: null, error: { code, message: 'private' } })
    expect(await processReevaluationPhoto(f.deps, scope)).toEqual({ status: 'skipped' })
    expect(f.analyze).not.toHaveBeenCalled()
  })
  it('refuses malformed or foreign claim before Storage', async () => {
    const f = setup()
    const wire = processingWire()
    wire.attempt.id = wire.asset.id
    f.rpc.mockResolvedValue({ data: wire, error: null })
    await expect(processReevaluationPhoto(f.deps, scope)).rejects.toMatchObject({ status: 503 })
    expect(f.from).not.toHaveBeenCalled()
  })
  it.each([
    null,
    { size: 1201, arrayBuffer: async () => jpegBytes().buffer },
  ])('refuses absent or wrong-size Blob before provider', async (data) => {
    const f = setup()
    f.download.mockResolvedValue({ data, error: null })
    await expect(processReevaluationPhoto(f.deps, scope)).rejects.toMatchObject({
      status: 503,
      message: 'Photo processing is unavailable',
    })
    expect(f.analyze).not.toHaveBeenCalled()
    expect(f.rpc).toHaveBeenLastCalledWith(
      'fail_mobile_reevaluation_photo_processing',
      expect.objectContaining({ p_failure_code: 'storage_unavailable' }),
    )
  })
  it('sanitizes Storage transport failure', async () => {
    const f = setup()
    f.download.mockRejectedValue(new Error('signed-url-private'))
    await expect(processReevaluationPhoto(f.deps, scope)).rejects.toMatchObject({
      message: 'Photo processing is unavailable',
    })
    expect(f.analyze).not.toHaveBeenCalled()
  })
  it('does not repeat ambiguous completion and terminal retry does not repay', async () => {
    const f = setup()
    f.rpc
      .mockResolvedValueOnce({ data: processingWire(), error: null })
      .mockResolvedValueOnce({ data: processingWire('authorized'), error: null })
      .mockRejectedValueOnce(new Error('private'))
    await expect(processReevaluationPhoto(f.deps, scope)).rejects.toMatchObject({ status: 503 })
    f.rpc.mockResolvedValueOnce({ data: processingWire('succeeded'), error: null })
    expect(await processReevaluationPhoto(f.deps, scope)).toEqual({ status: 'processed' })
    expect(f.analyze).toHaveBeenCalledTimes(1)
  })
})
