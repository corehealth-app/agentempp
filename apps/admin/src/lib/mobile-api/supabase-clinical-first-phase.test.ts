import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createSupabaseClinicalFirstPhaseRepository } from './supabase-clinical-first-phase'

const id = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const user = id(1),
  preview = id(2),
  prepareKey = id(3),
  confirmKey = id(4)
function prepared() {
  return {
    version: 1,
    user_id: user,
    preview_id: preview,
    prepare_operation_key: prepareKey,
    signup_generation: id(5),
    signup_epoch: id(6),
    context_hash: 'a'.repeat(64),
    selection: { phase: 'recomposicao' },
    package: {
      version: 1,
      phase: 'recomposicao',
      deficitLevel: 500,
      effectiveDate: '2026-10-26',
      targets: {
        beforeKcal: null,
        beforeProtein: null,
        afterKcal: 1413,
        afterProtein: 121.5,
        formulaAfterKcal: 1413,
      },
      formulaBodyFat: { origin: 'report', percent: null },
      episode: { difficultyCount: 0, ledgerSteps: null, schedule: null, maintenanceSince: null },
    },
    created_at: '2026-10-26T12:00:00.000000Z',
    valid_until: '2026-10-26T12:15:00.000000Z',
  }
}
function receipt() {
  return {
    version: 1,
    user_id: user,
    preview_id: preview,
    operation_key: confirmKey,
    operation_matched: true,
    prepared: prepared(),
    result: {
      version: 1,
      source: 'confirmed_first_phase_v1',
      first_phase_id: preview,
      event_id: id(7),
      episode_id: id(8),
      signup_generation: id(5),
      signup_epoch: id(6),
      phase: 'recomposicao',
      deficit_level: 500,
      decision_date: '2026-10-26',
      effective_date: '2026-10-26',
      confirmed_at: '2026-10-26T12:01:00.000000Z',
      applied_snapshot_id: id(9),
      targets: { calories_target: 1413, protein_target: 121.5, formula_target: 1413 },
      maintenance_since: null,
    },
  }
}
function setup(data: unknown) {
  const rpc = vi.fn().mockResolvedValue({ data, error: null })
  return {
    rpc,
    repository: createSupabaseClinicalFirstPhaseRepository({ rpc } as unknown as ServiceClient),
  }
}
describe('first-phase private transport bindings', () => {
  it.each([
    { operationKey: id(99) },
    { previewId: id(99) },
  ])('rejects a valid packet belonging to another lookup: %j', async (lookup) => {
    const { rpc, repository } = setup(prepared())
    await expect(repository.findPrepared(user, lookup)).rejects.toMatchObject({ status: 503 })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    { deficit_level: 400 },
    { confirmed_at: '2026-10-26T11:59:00.000000Z' },
    { confirmed_at: '2026-10-26T12:15:00.000000Z' },
  ])('rejects a receipt contradicting its original approved package: %j', async (patch) => {
    const value = receipt()
    Object.assign(value.result, patch)
    const { rpc, repository } = setup(value)
    await expect(repository.findReceipt(user, preview, confirmKey)).rejects.toMatchObject({
      status: 503,
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })
  it('accepts and freezes the original package and receipt without a recapture', async () => {
    const value = receipt(),
      { rpc, repository } = setup(value)
    const result = await repository.findReceipt(user, preview, confirmKey)
    expect(result).toEqual(value)
    expect(Object.isFrozen(result?.prepared.package.targets)).toBe(true)
    expect(rpc.mock.calls[0]?.[0]).toBe('get_mobile_clinical_first_phase_receipt')
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
