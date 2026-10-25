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
  }
  const deps: ReevaluationPhotoAccountPurgeDependencies = {
    begin: vi.fn().mockResolvedValue(true),
    purge: vi.fn().mockResolvedValueOnce(false).mockResolvedValue(true),
    claimScopes: vi.fn().mockResolvedValue(receipt),
    drain: vi.fn().mockResolvedValue({ state: 'settled', newlyDeleted: 1 }),
  }
  return { deps, receipt }
}
describe('bounded recurring account purge coordination', () => {
  it('defers a lost owner precondition before purge or scope claims', async () => {
    const { deps } = setup()
    vi.mocked(deps.begin).mockResolvedValue(false)
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(deps.purge).not.toHaveBeenCalled()
    expect(deps.claimScopes).not.toHaveBeenCalled()
  })
  it('advances actual attempts across calls even when every removal is incomplete', async () => {
    const { deps, receipt } = setup()
    const ids = Array.from(
      { length: 21 },
      (_, i) => `b3b01000-0000-4000-8000-${String(i + 10).padStart(12, '0')}`,
    )
    let position = 0
    vi.mocked(deps.purge).mockReset().mockResolvedValue(false)
    vi.mocked(deps.claimScopes).mockImplementation(async () => ({
      ...receipt,
      items: [{ cycle_id: cycle, acceptance_id: ids[position++ % ids.length] }],
      has_more: true,
    }))
    vi.mocked(deps.drain).mockResolvedValue({
      state: 'incomplete',
      reason: 'unavailable',
      newlyDeleted: 0,
    })
    for (let i = 0; i < 21; i++)
      expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(
      new Set(vi.mocked(deps.drain).mock.calls.map(([scope]) => scope.acceptanceId)).size,
    ).toBe(21)
    expect(deps.purge).toHaveBeenCalledTimes(21)
  })
  it('uses the transactional fast path for an already settled or empty owner', async () => {
    const { deps } = setup()
    vi.mocked(deps.purge).mockReset().mockResolvedValue(true)
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(true)
    expect(deps.claimScopes).not.toHaveBeenCalled()
    expect(deps.drain).not.toHaveBeenCalled()
  })
  it('drains only bound scopes then asks SQL to prove and purge the complete owner', async () => {
    const { deps } = setup()
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(true)
    expect(deps.claimScopes).toHaveBeenCalledWith(user, cutoff, 1, expect.any(AbortSignal))
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
    vi.mocked(deps.claimScopes)
      .mockResolvedValueOnce({ ...receipt, items: [receipt.items[0]], has_more: true })
      .mockResolvedValueOnce({ ...receipt, items: [receipt.items[1]], has_more: false })
    vi.mocked(deps.drain).mockResolvedValueOnce({ state: 'waiting', newlyDeleted: 1 })
    vi.mocked(deps.purge).mockReset().mockResolvedValue(false)
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(deps.drain).toHaveBeenCalledTimes(2)
  })
  it.each([
    { change: { user_id: other } },
    { change: { eligible: false } },
    { change: { items: [], has_more: true } },
    { change: { extra: 'private' } },
    {
      change: {
        items: [
          { cycle_id: cycle, acceptance_id: acceptance },
          { cycle_id: cycle, acceptance_id: acceptance },
        ],
      },
    },
    { change: { eligible: false, items: [] } },
  ])('defers malformed, foreign, duplicate or inconsistent lookup receipts: $change', async ({
    change,
  }) => {
    const { deps, receipt } = setup()
    vi.mocked(deps.claimScopes).mockResolvedValue({ ...receipt, ...change })
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(deps.drain).not.toHaveBeenCalled()
    expect(deps.purge).toHaveBeenCalledOnce()
  })
  it('does not treat a truthy malformed purge reply as permission', async () => {
    const { deps } = setup()
    vi.mocked(deps.purge).mockReset().mockResolvedValue({ ok: true })
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(deps.claimScopes).not.toHaveBeenCalled()
  })
  it('preserves durable progress when the scope budget runs out', async () => {
    const { deps, receipt } = setup()
    vi.mocked(deps.claimScopes).mockResolvedValue({ ...receipt, has_more: true })
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff, { maxScopes: 1 })).toBe(
      false,
    )
    expect(deps.claimScopes).toHaveBeenCalledWith(user, cutoff, 1, expect.any(AbortSignal))
    expect(deps.drain).toHaveBeenCalledOnce()
    expect(deps.purge).toHaveBeenCalledOnce()
  })
  it('claims one scope per actual attempt so a timeout cannot mark unattempted scopes visited', async () => {
    const { deps, receipt } = setup()
    const rows = Array.from({ length: 21 }, (_, i) => ({
      cycle_id: cycle,
      acceptance_id: `b3b01000-0000-4000-8000-${String(i + 10).padStart(12, '0')}`,
    }))
    vi.mocked(deps.claimScopes).mockImplementation(async () => ({
      ...receipt,
      items: [rows.shift()],
      has_more: rows.length > 0,
    }))
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff, { maxScopes: 25 })).toBe(
      true,
    )
    expect(deps.claimScopes).toHaveBeenCalledTimes(21)
    expect(deps.claimScopes).toHaveBeenCalledWith(user, cutoff, 1, expect.any(AbortSignal))
    expect(deps.drain).toHaveBeenCalledTimes(21)
  })
  it('does not start a drain after a timed-out lookup completes late', async () => {
    const { deps, receipt } = setup()
    let finish: ((value: unknown) => void) | undefined
    vi.mocked(deps.claimScopes).mockImplementation(
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
    vi.mocked(deps.claimScopes).mockRejectedValue(new Error('private provider token'))
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, cutoff)).toBe(false)
    expect(await prepareReevaluationPhotoAccountPurge(deps, '../bad', cutoff)).toBe(false)
    expect(await prepareReevaluationPhotoAccountPurge(deps, user, 'bad')).toBe(false)
    expect(deps.purge).toHaveBeenCalledOnce()
  })
})
