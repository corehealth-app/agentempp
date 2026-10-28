import { describe, expect, it, vi } from 'vitest'
import { cleanupReevaluationPhotos } from './reevaluation-photo-cleanup.js'

const scope = (n: number) => ({
  user_id: `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`,
  cycle_id: `b3b01000-0000-4000-8001-${String(n).padStart(12, '0')}`,
  acceptance_id: `b3b01000-0000-4000-8002-${String(n).padStart(12, '0')}`,
})
const page = (n: number, more = false) => ({ version: 1, items: [scope(n)], has_more: more })
describe('bounded normal recurring photo cleanup', () => {
  it('continues after one Storage failure; reserves only one scope per attempt', async () => {
    const claim = vi.fn().mockResolvedValueOnce(page(1, true)).mockResolvedValueOnce(page(2))
    const drain = vi
      .fn()
      .mockRejectedValueOnce(new Error('private path and token'))
      .mockResolvedValueOnce({ state: 'settled', newlyDeleted: 3 })
    const result = await cleanupReevaluationPhotos({ claim, drain })
    expect(claim.mock.calls.map(([limit]) => limit)).toEqual([1, 1])
    expect(drain.mock.calls.map(([value]) => value)).toEqual([
      {
        userId: scope(1).user_id,
        cycleId: scope(1).cycle_id,
        acceptanceId: scope(1).acceptance_id,
      },
      {
        userId: scope(2).user_id,
        cycleId: scope(2).cycle_id,
        acceptanceId: scope(2).acceptance_id,
      },
    ])
    expect(result).toMatchObject({ attempted: 2, incomplete: 1, settled: 1, newlyDeleted: 3 })
    expect(JSON.stringify(result)).not.toMatch(/b3b01000|private|token/)
  })
  it('refuses malformed, repeated or cross-scope claim packets before another drain', async () => {
    const drain = vi.fn().mockResolvedValue({ state: 'live', newlyDeleted: 0 })
    const repeated = vi.fn().mockResolvedValue(page(1, true))
    expect(await cleanupReevaluationPhotos({ claim: repeated, drain })).toMatchObject({
      attempted: 1,
      stopped: 'retry_deferred',
    })
    expect(drain).toHaveBeenCalledTimes(1)
    for (const value of [
      { version: 1, items: [scope(1), scope(2)], has_more: true },
      { version: 1, items: [], has_more: true },
      { ...page(1), user_id: scope(9).user_id },
      page(1, false).items,
    ]) {
      const next = vi.fn()
      expect(
        await cleanupReevaluationPhotos({ claim: vi.fn().mockResolvedValue(value), drain: next }),
      ).toMatchObject({ attempted: 0, stopped: 'invalid_receipt' })
      expect(next).not.toHaveBeenCalled()
    }
  })
  it('leaves failed and waiting scopes for later runs without replaying them in the same run', async () => {
    const claim = vi.fn().mockResolvedValueOnce(page(1, true)).mockResolvedValueOnce(page(2))
    const drain = vi
      .fn()
      .mockResolvedValueOnce({ state: 'incomplete', reason: 'unavailable', newlyDeleted: 1 })
      .mockResolvedValueOnce({ state: 'waiting', newlyDeleted: 0 })
    expect(await cleanupReevaluationPhotos({ claim, drain })).toMatchObject({
      attempted: 2,
      incomplete: 1,
      waiting: 1,
      newlyDeleted: 1,
    })
  })
  it('bounds the total scope budget and does not report all work completed', async () => {
    let n = 0
    const claim = vi.fn(async () => page(++n, true)),
      drain = vi.fn().mockResolvedValue({ state: 'settled', newlyDeleted: 1 })
    expect(await cleanupReevaluationPhotos({ claim, drain }, { maxScopes: 2 })).toMatchObject({
      attempted: 2,
      settled: 2,
      stopped: 'scope_limit',
      hasMore: true,
    })
    expect(claim).toHaveBeenCalledTimes(2)
  })
  it('a claim finishing after the global deadline cannot start a removal', async () => {
    let finish: ((value: unknown) => void) | undefined
    const claim = vi.fn(
        (_limit: number, _signal: AbortSignal) =>
          new Promise((resolve) => {
            finish = resolve
          }),
      ),
      drain = vi.fn()
    const result = await cleanupReevaluationPhotos({ claim, drain }, { timeoutMs: 15 })
    expect(result.stopped).toBe('timeout')
    finish?.(page(1))
    await new Promise((resolve) => setTimeout(resolve, 5))
    expect(drain).not.toHaveBeenCalled()
    expect(claim.mock.calls[0]?.[1].aborted).toBe(true)
  })
  it('rejects invalid limits before calling any dependency', async () => {
    const claim = vi.fn(),
      drain = vi.fn()
    expect(await cleanupReevaluationPhotos({ claim, drain }, { maxScopes: 101 })).toMatchObject({
      attempted: 0,
      stopped: 'invalid_input',
    })
    expect(claim).not.toHaveBeenCalled()
  })
})
