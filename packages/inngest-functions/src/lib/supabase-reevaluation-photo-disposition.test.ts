import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { drainReevaluationPhotoDisposition } from './reevaluation-photo-disposition.js'
import { createReevaluationPhotoDispositionDependencies } from './supabase-reevaluation-photo-disposition.js'
import fixture from './testing/reevaluation-photo-disposition-fixture.json'

function setup() {
  const values: Record<string, unknown> = {
    prepare_mobile_reevaluation_photo_disposition: fixture.prepare,
    get_mobile_reevaluation_photo_disposition_page: fixture.page,
    commit_mobile_reevaluation_photo_disposition_page: fixture.ack,
  }
  const signals: AbortSignal[] = []
  const rpc = vi.fn((name: string, _args: Record<string, unknown>) => ({
    abortSignal(signal: AbortSignal): Promise<{ data: unknown; error: unknown }> {
      signals.push(signal)
      return Promise.resolve({ data: values[name], error: null })
    },
  }))
  const remove = vi.fn().mockResolvedValue({ data: [], error: null })
  const from = vi.fn(() => ({ remove }))
  const client = { rpc, storage: { from } } as unknown as ServiceClient
  return { rpc, remove, from, client, signals }
}
describe('dedicated recurring disposal Supabase adapter', () => {
  it('uses only three dedicated RPCs and exact private paths', async () => {
    const f = setup()
    const deps = createReevaluationPhotoDispositionDependencies(f.client)
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'settled',
      newlyDeleted: 2,
    })
    expect(f.rpc.mock.calls.map((call) => call[0])).toEqual([
      'prepare_mobile_reevaluation_photo_disposition',
      'get_mobile_reevaluation_photo_disposition_page',
      'commit_mobile_reevaluation_photo_disposition_page',
    ])
    expect(f.rpc.mock.calls[0]?.[1]).toEqual({
      p_user_id: fixture.scope.userId,
      p_cycle_id: fixture.scope.cycleId,
      p_acceptance_id: fixture.scope.acceptanceId,
    })
    expect(f.rpc.mock.calls[2]?.[1]).toEqual({
      p_user_id: fixture.scope.userId,
      p_disposition_id: fixture.prepare.disposition.id,
      p_expected_sweep: fixture.prepare.disposition.sweep_no,
      p_expected_capability_revision: fixture.prepare.disposition.capability_revision,
      p_expected_after: null,
      p_asset_ids: fixture.page.items.map((item) => item.asset_id),
    })
    expect(f.from).toHaveBeenCalledOnce()
    expect(f.from).toHaveBeenCalledWith('body-checkin-photos')
    expect(f.remove).toHaveBeenCalledWith(fixture.page.items.map((item) => item.object_path))
    expect(f.signals).toHaveLength(3)
    expect(new Set(f.signals).size).toBe(1)
  })
  it('does not commit catalogue deletion when Storage reports failure', async () => {
    const f = setup()
    f.remove.mockResolvedValue({ data: null, error: { message: 'private provider token' } })
    expect(
      await drainReevaluationPhotoDisposition(
        createReevaluationPhotoDispositionDependencies(f.client),
        fixture.scope,
      ),
    ).toEqual({ state: 'incomplete', reason: 'unavailable', newlyDeleted: 0 })
    expect(f.rpc).toHaveBeenCalledTimes(2)
  })
  it('sanitizes RPC errors before they leave the adapter', async () => {
    const f = setup()
    f.rpc.mockImplementation(() => ({
      abortSignal: () => Promise.resolve({ data: null, error: { message: 'raw credentials' } }),
    }))
    await expect(
      createReevaluationPhotoDispositionDependencies(f.client).prepare(
        fixture.scope,
        new AbortController().signal,
      ),
    ).rejects.toThrow('reevaluation_photo_disposition_unavailable')
    expect(f.from).not.toHaveBeenCalled()
  })
  const firstPath = fixture.page.items[0]?.object_path
  if (firstPath === undefined) throw new Error('Missing synthetic fixture path')
  it.each([
    { paths: [] },
    { paths: ['../foreign.jpg'] },
    { paths: [firstPath, firstPath] },
  ])('rejects malformed or duplicate removal paths %j', async ({ paths }) => {
    const f = setup()
    await expect(
      createReevaluationPhotoDispositionDependencies(f.client).remove(paths),
    ).rejects.toThrow('reevaluation_photo_disposition_unavailable')
    expect(f.from).not.toHaveBeenCalled()
  })
})
