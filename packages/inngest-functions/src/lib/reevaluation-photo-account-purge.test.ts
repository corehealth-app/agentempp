import { describe, expect, it, vi } from 'vitest'
import {
  prepareReevaluationPhotoAccountPurge,
  type ReevaluationPhotoAccountPurgeDependencies,
} from './reevaluation-photo-account-purge.js'

const user = 'b3b01000-0000-4000-8000-000000000001'
const other = 'b3b01000-0000-4000-8000-000000000002'
const cycle = 'b3b01000-0000-4000-8000-000000000003'
const acceptance = 'b3b01000-0000-4000-8000-000000000004'
const cutoff = '2026-10-25T11:00:00.000Z'
function setup() {
  const receipt = {
    version: 1,
    user_id: user,
    eligible: true,
    items: [{ cycle_id: cycle, acceptance_id: acceptance }],
    has_more: false,
    cursor: acceptance,
  }
  const deps: ReevaluationPhotoAccountPurgeDependencies = {
    purge: vi.fn().mockResolvedValueOnce(false).mockResolvedValue(true),
    listScopes: vi.fn().mockResolvedValue(receipt),
    drain: vi.fn().mockResolvedValue({ state: 'settled', newlyDeleted: 1 }),
  }
  return { deps, receipt }
}
describe('bounded recurring account purge coordination', () => {
  it('uses the transactional fast path for an already settled or empty owner', async () => {
    const { deps } = setup()
    vi.mocked(deps.purge).mockReset().mockResolvedValue(true)
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(true)
    expect(deps.listScopes).not.toHaveBeenCalled()
    expect(deps.drain).not.toHaveBeenCalled()
  })
  it('drains only bound scopes then asks SQL to prove and purge the complete owner', async () => {
    const { deps } = setup()
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(true)
    expect(deps.listScopes).toHaveBeenCalledWith(user, cutoff, null, 20, expect.any(AbortSignal))
    expect(deps.drain).toHaveBeenCalledWith(
      { userId: user, cycleId: cycle, acceptanceId: acceptance },
      expect.objectContaining({ signal: expect.any(AbortSignal) }),
    )
    expect(deps.purge).toHaveBeenCalledTimes(2)
    expect(vi.mocked(deps.purge).mock.invocationCallOrder[1]).toBeGreaterThan(
      vi.mocked(deps.drain).mock.invocationCallOrder[0] ?? 0,
    )
  })
  it('continues other due scopes when one is waiting; final SQL proof decides', async () => {
    const { deps, receipt } = setup()
    receipt.items.push({ cycle_id: cycle, acceptance_id: other })
    receipt.items.sort((a, b) => a.acceptance_id.localeCompare(b.acceptance_id))
    receipt.cursor = acceptance
    vi.mocked(deps.drain).mockResolvedValueOnce({ state: 'waiting', newlyDeleted: 1 })
    vi.mocked(deps.purge).mockReset().mockResolvedValue(false)
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(deps.drain).toHaveBeenCalledTimes(2)
  })
  it.each([
    { change: { user_id: other } },
    { change: { eligible: false } },
    { change: { cursor: other } },
    { change: { extra: 'private' } },
    {
      change: {
        items: [
          { cycle_id: cycle, acceptance_id: acceptance },
          { cycle_id: cycle, acceptance_id: acceptance },
        ],
      },
    },
    { change: { items: [] } },
  ])('defers malformed, foreign, duplicate or inconsistent lookup receipts: $change', async ({
    change,
  }) => {
    const { deps, receipt } = setup()
    vi.mocked(deps.listScopes).mockResolvedValue({ ...receipt, ...change })
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(deps.drain).not.toHaveBeenCalled()
    expect(deps.purge).toHaveBeenCalledOnce()
  })
  it('does not treat a truthy malformed purge reply as permission', async () => {
    const { deps } = setup()
    vi.mocked(deps.purge).mockReset().mockResolvedValue({ ok: true })
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(deps.listScopes).not.toHaveBeenCalled()
  })
  it('preserves durable progress when the scope budget runs out', async () => {
    const { deps, receipt } = setup()
    vi.mocked(deps.listScopes).mockResolvedValue({ ...receipt, has_more: true })
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff, { maxScopes: 1 })).toBe(
      false,
    )
    expect(deps.listScopes).toHaveBeenCalledWith(user, cutoff, null, 1, expect.any(AbortSignal))
    expect(deps.drain).toHaveBeenCalledOnce()
    expect(deps.purge).toHaveBeenCalledOnce()
  })
  it('continues a full keyset page without scanning settled history again', async () => {
    const { deps, receipt } = setup()
    const ids = Array.from(
      { length: 21 },
      (_, i) => `b3b01000-0000-4000-8000-${String(i + 10).padStart(12, '0')}`,
    )
    const rows = ids.map((id) => ({ cycle_id: cycle, acceptance_id: id }))
    vi.mocked(deps.listScopes)
      .mockResolvedValueOnce({
        ...receipt,
        items: rows.slice(0, 20),
        cursor: ids[19],
        has_more: true,
      })
      .mockResolvedValueOnce({ ...receipt, items: rows.slice(20), cursor: ids[20] })
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff, { maxScopes: 25 })).toBe(
      true,
    )
    expect(deps.drain).toHaveBeenCalledTimes(21)
    expect(deps.listScopes).toHaveBeenNthCalledWith(
      2,
      user,
      cutoff,
      ids[19],
      5,
      expect.any(AbortSignal),
    )
  })
  it('does not start a drain after a timed-out lookup completes late', async () => {
    const { deps, receipt } = setup()
    let finish: ((value: unknown) => void) | undefined
    vi.mocked(deps.listScopes).mockImplementation(
      () =>
        new Promise((resolve) => {
          finish = resolve
        }),
    )
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff, { timeoutMs: 10 })).toBe(
      false,
    )
    finish?.(receipt)
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(deps.drain).not.toHaveBeenCalled()
    expect(deps.purge).toHaveBeenCalledOnce()
  })
  it('does not purge after an incomplete or live scope', async () => {
    for (const outcome of [
      { state: 'live', newlyDeleted: 0 },
      { state: 'incomplete', reason: 'unavailable', newlyDeleted: 0 },
    ] as const) {
      const { deps } = setup()
      vi.mocked(deps.drain).mockResolvedValue(outcome)
      expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
      expect(deps.purge).toHaveBeenCalledOnce()
    }
  })
  it('stops the nested drain and never invokes purge after the whole-owner deadline', async () => {
    const { deps } = setup()
    let resolveDrain: ((x: { state: 'settled'; newlyDeleted: number }) => void) | undefined
    let signal: AbortSignal | undefined
    vi.mocked(deps.drain).mockImplementation((_scope, options) => {
      signal = options.signal
      return new Promise((resolve) => {
        resolveDrain = resolve
      })
    })
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff, { timeoutMs: 15 })).toBe(
      false,
    )
    expect(signal?.aborted).toBe(true)
    resolveDrain?.({ state: 'settled', newlyDeleted: 1 })
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(deps.purge).toHaveBeenCalledOnce()
  })
  it('sanitizes dependency failures and rejects invalid inputs before calling them', async () => {
    const { deps } = setup()
    vi.mocked(deps.listScopes).mockRejectedValue(new Error('private provider token'))
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(await prepareReevaluationPhotoAccountPurge(deps, '../bad', cutoff)).toBe(false)
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, 'bad')).toBe(false)
    expect(deps.purge).toHaveBeenCalledOnce()
  })
})
