import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  drainReevaluationPhotoDisposition,
  type ReevaluationPhotoDispositionDependencies,
} from './reevaluation-photo-disposition.js'
import fixture from './testing/reevaluation-photo-disposition-fixture.json'

function required<T>(value: T | undefined): T {
  if (value === undefined) throw new Error('Missing synthetic fixture item')
  return value
}
function setup() {
  const data = structuredClone(fixture)
  const deps = {
    prepare: vi
      .fn<ReevaluationPhotoDispositionDependencies['prepare']>()
      .mockResolvedValue(data.prepare),
    page: vi.fn<ReevaluationPhotoDispositionDependencies['page']>().mockResolvedValue(data.page),
    remove: vi
      .fn<ReevaluationPhotoDispositionDependencies['remove']>()
      .mockResolvedValue(undefined),
    commit: vi.fn<ReevaluationPhotoDispositionDependencies['commit']>().mockResolvedValue(data.ack),
  }
  return { deps, data }
}
function terminal(kind: 'waiting' | 'settled') {
  const prep = structuredClone(fixture.prepare)
  prep.kind = kind
  prep.disposition.sweep_state = kind
  Object.assign(prep.disposition, {
    cursor: fixture.ack.cursor,
    last_ack_at: fixture.prepare.disposition.sweep_started_at,
    next_sweep_at: kind === 'waiting' ? fixture.prepare.disposition.sweep_started_at : null,
  })
  return prep
}
function items(count: number, start = 1) {
  return Array.from({ length: count }, (_, i) => {
    const id = `b3b01000-0000-4000-8000-${String(start + i).padStart(12, '0')}`
    return {
      asset_id: id,
      bucket_id: 'body-checkin-photos',
      object_path: `${fixture.scope.userId}/${id}.jpg`,
    }
  })
}
afterEach(() => {
  vi.useRealTimers()
})
describe('recurring disposition uses SQL-produced authority', () => {
  it('removes exact frozen paths before committing the matching complete page', async () => {
    const { deps, data } = setup()
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'settled',
      newlyDeleted: 2,
    })
    expect(deps.remove).toHaveBeenCalledWith(data.page.items.map((item) => item.object_path))
    expect(Object.isFrozen(deps.remove.mock.calls[0]?.[0])).toBe(true)
    expect(deps.commit).toHaveBeenCalledWith(
      data.prepare.disposition,
      null,
      data.page.items.map((item) => item.asset_id),
      expect.any(AbortSignal),
    )
    expect(deps.remove.mock.invocationCallOrder[0]).toBeLessThan(
      deps.commit.mock.invocationCallOrder[0] ?? 0,
    )
  })
  it.each([
    'waiting',
    'settled',
  ] as const)('never removes files when SQL says %s', async (state) => {
    const { deps } = setup()
    deps.prepare.mockResolvedValue(terminal(state))
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state,
      newlyDeleted: 0,
    })
    expect(deps.page).not.toHaveBeenCalled()
    expect(deps.remove).not.toHaveBeenCalled()
  })
  it('preserves a live consent and a zero-photo settled scope', async () => {
    const { deps, data } = setup()
    deps.prepare.mockResolvedValue({ ...data.prepare, kind: 'live', disposition: null })
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'live',
      newlyDeleted: 0,
    })
    const zero = terminal('settled')
    zero.disposition.manifest_count = '0'
    zero.disposition.cursor = null
    deps.prepare.mockResolvedValue(zero)
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'settled',
      newlyDeleted: 0,
    })
    expect(deps.remove).not.toHaveBeenCalled()
  })
  it.each([
    'foreign_owner',
    'wrong_manifest',
    'wrong_capability',
    'duplicate',
    'unsorted',
    'bad_path',
    'mixed_bucket',
  ])('blocks invalid page %s before Storage', async (mode) => {
    const { deps, data } = setup()
    if (mode === 'foreign_owner') data.page.user_id = data.page.cycle_id
    if (mode === 'wrong_manifest') data.page.disposition_id = data.page.cycle_id
    if (mode === 'wrong_capability') data.page.capability_revision = '2'
    if (mode === 'duplicate') data.page.items[1] = { ...required(data.page.items[0]) }
    if (mode === 'unsorted') data.page.items.reverse()
    if (mode === 'bad_path')
      required(data.page.items[0]).object_path = `${data.page.user_id}/../another.jpg`
    if (mode === 'mixed_bucket') required(data.page.items[0]).bucket_id = 'meal-photos'
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'incomplete',
      reason: 'invalid_receipt',
      newlyDeleted: 0,
    })
    expect(deps.remove).not.toHaveBeenCalled()
    expect(deps.commit).not.toHaveBeenCalled()
  })
  it('does not advance or report completion from a partial acknowledgement', async () => {
    const { deps, data } = setup()
    data.ack.assets.pop()
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'incomplete',
      reason: 'invalid_receipt',
      newlyDeleted: 0,
    })
    expect(deps.remove).toHaveBeenCalledOnce()
    expect(deps.page).toHaveBeenCalledOnce()
  })
  it.each([
    'prepare',
    'page',
    'remove',
    'commit',
  ] as const)('sanitizes %s failure and stops', async (phase) => {
    const { deps } = setup()
    deps[phase].mockRejectedValue(new Error('private signed URL and provider token'))
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'incomplete',
      reason: 'unavailable',
      newlyDeleted: 0,
    })
    if (phase !== 'commit') expect(deps.commit).not.toHaveBeenCalled()
  })
  it.each([
    'user_id',
    'capability_revision',
  ] as const)('rejects ACK with changed %s after Storage', async (field) => {
    const { deps, data } = setup()
    data.ack[field] = field === 'user_id' ? data.ack.cycle_id : '2'
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'incomplete',
      reason: 'invalid_receipt',
      newlyDeleted: 0,
    })
    expect(deps.remove).toHaveBeenCalledOnce()
    expect(deps.prepare).toHaveBeenCalledOnce()
  })
  it('waits for Storage and stops when a late capability makes SQL reject the ACK', async () => {
    const { deps } = setup()
    let release!: () => void
    deps.remove.mockImplementation(
      () =>
        new Promise((done) => {
          release = done
        }),
    )
    const task = drainReevaluationPhotoDisposition(deps, fixture.scope)
    await vi.waitFor(() => expect(deps.remove).toHaveBeenCalledOnce())
    expect(deps.commit).not.toHaveBeenCalled()
    deps.commit.mockRejectedValue(new Error('capability revision changed'))
    release()
    expect(await task).toEqual({ state: 'incomplete', reason: 'unavailable', newlyDeleted: 0 })
    expect(deps.prepare).toHaveBeenCalledOnce()
    expect(deps.page).toHaveBeenCalledOnce()
  })
  it('repeats the same remove after Storage succeeded but SQL did not commit', async () => {
    const { deps, data } = setup()
    deps.commit.mockRejectedValueOnce(new Error('unknown SQL result'))
    expect((await drainReevaluationPhotoDisposition(deps, fixture.scope)).state).toBe('incomplete')
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'settled',
      newlyDeleted: 2,
    })
    expect(deps.remove.mock.calls).toEqual([
      [data.page.items.map((item) => item.object_path)],
      [data.page.items.map((item) => item.object_path)],
    ])
  })
  it('observes persisted settlement after ambiguous ACK without removing again', async () => {
    const { deps } = setup()
    deps.commit.mockRejectedValueOnce(new Error('response lost after SQL commit'))
    await drainReevaluationPhotoDisposition(deps, fixture.scope)
    deps.prepare.mockResolvedValue(terminal('settled'))
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'settled',
      newlyDeleted: 0,
    })
    expect(deps.remove).toHaveBeenCalledOnce()
  })
  it('handles exact 200 plus one keyset pages without partial completion', async () => {
    const { deps, data } = setup()
    data.prepare.disposition.manifest_count = '201'
    const first = { ...data.page, items: items(200), has_more: true }
    const lastId = required(first.items.at(-1)).asset_id
    const second = { ...data.page, items: items(1, 201), cursor: lastId, has_more: false }
    const ack1 = {
      ...data.ack,
      cursor: lastId,
      sweep_complete: false,
      state: 'pending',
      assets: first.items.map((item) => ({
        asset_id: item.asset_id,
        newly_deleted: true,
        catalogue_state: 'deleted',
      })),
    }
    const ack2 = {
      ...data.ack,
      previous_cursor: lastId,
      cursor: required(second.items[0]).asset_id,
      assets: [
        {
          asset_id: required(second.items[0]).asset_id,
          newly_deleted: true,
          catalogue_state: 'deleted',
        },
      ],
    }
    deps.page.mockResolvedValueOnce(first).mockResolvedValueOnce(second)
    deps.commit.mockResolvedValueOnce(ack1).mockResolvedValueOnce(ack2)
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope)).toEqual({
      state: 'settled',
      newlyDeleted: 201,
    })
    expect(deps.page).toHaveBeenLastCalledWith(
      data.prepare.disposition,
      lastId,
      expect.any(AbortSignal),
    )
  })
  it('stops at a page budget while preserving acknowledged progress', async () => {
    const { deps, data } = setup()
    data.prepare.disposition.manifest_count = '201'
    const first = { ...data.page, items: items(200), has_more: true }
    deps.page.mockResolvedValue(first)
    deps.commit.mockResolvedValue({
      ...data.ack,
      cursor: required(first.items.at(-1)).asset_id,
      sweep_complete: false,
      state: 'pending',
      assets: first.items.map((item) => ({
        asset_id: item.asset_id,
        newly_deleted: true,
        catalogue_state: 'deleted',
      })),
    })
    expect(await drainReevaluationPhotoDisposition(deps, fixture.scope, { maxPages: 1 })).toEqual({
      state: 'incomplete',
      reason: 'page_limit',
      newlyDeleted: 200,
    })
    expect(deps.page).toHaveBeenCalledOnce()
  })
  it('never commits after timed-out Storage resolves later', async () => {
    vi.useFakeTimers()
    const { deps } = setup()
    let resolve!: () => void
    deps.remove.mockImplementation(
      () =>
        new Promise((done) => {
          resolve = done
        }),
    )
    const task = drainReevaluationPhotoDisposition(deps, fixture.scope, { timeoutMs: 5 })
    await vi.advanceTimersByTimeAsync(0)
    expect(deps.remove).toHaveBeenCalledOnce()
    await vi.advanceTimersByTimeAsync(5)
    expect(await task).toEqual({ state: 'incomplete', reason: 'timeout', newlyDeleted: 0 })
    resolve()
    await vi.advanceTimersByTimeAsync(1)
    expect(deps.commit).not.toHaveBeenCalled()
  })
})
