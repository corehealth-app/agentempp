/** Qualified RPC-boundary tests, separate from the exact Tokyo/Honolulu race. */
import { clearCalcConfigCache, closePastOpenDays } from '@mpp/agent'
import { DayCloseMemoryDb } from '@mpp/agent/testing/day-close-memory-db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const USER = '0b9f6f0e-0000-4000-8000-00000000c128'
const NOW = new Date('2026-10-09T20:00:00.000Z')
function setup(body: (identity: string) => unknown, target = 'finalize_mobile_daily_close_atomic') {
  const db = new DayCloseMemoryDb()
  db.addAccount({
    userId: USER,
    timezone: 'Asia/Tokyo',
    profile: { current_protocol: 'recomposicao', deficit_level: 500 },
    progress: {
      xp_total: 40,
      current_streak: 3,
      longest_streak: 3,
      last_active_date: '2026-10-07',
    },
  })
  for (const date of ['2026-10-08', '2026-10-09'])
    db.registerMeal({
      userId: USER,
      date,
      consumedAt: `${date}T10:30:00.000Z`,
      kcal: 1000,
      caloriesTarget: 1576,
      proteinTarget: 120,
    })
  const client = {
    from: db.from.bind(db),
    rpc: async (name: string, params: Record<string, unknown>) => {
      if (name !== target) return db.rpc(name, params)
      await db.enter({ kind: 'rpc', target: name, params })
      return { data: body(String(params.p_snapshot_id ?? params.p_user_id)), error: null }
    },
  } as unknown as typeof db.client
  return {
    db,
    run: () =>
      closePastOpenDays(client, {
        userId: USER,
        timezone: 'Asia/Tokyo',
        now: NOW,
        from: '2026-10-08',
        finalizationFence: 'mobile-current-v1',
        block7700Policy: 'flow-recomposition-v1',
      }),
  }
}
beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
})
afterEach(() => {
  vi.useRealTimers()
})

describe('M5 mobile finalization result is an authority boundary', () => {
  it.each([
    ['null', () => null],
    ['array', () => []],
    ['foreign identity', () => ({ applied: true, user_id: 'other' })],
    ['nonboolean applied', (id: string) => ({ applied: 1, user_id: id })],
    ['missing metadata', (id: string) => ({ applied: true, user_id: id })],
    [
      'wrong gap',
      (id: string) => ({
        applied: true,
        user_id: id,
        previous_streak: 3,
        last_active_date: '2026-10-07',
        gap_days: 3,
        latest_closable_date: '2026-10-09',
      }),
    ],
    ['unknown refusal', (id: string) => ({ applied: false, user_id: id, reason: 'invented' })],
  ] as const)('inactivity %s cannot publish a reset event', async (_name, body) => {
    const { db, run } = setup(body, 'reset_mobile_inactive_streak_atomic')
    db.tables.meal_logs = []
    db.tables.daily_snapshots = []
    const progress = db.progress(USER)
    await expect(run()).rejects.toThrow(/mobile inactivity/)
    expect(db.progress(USER)).toEqual(progress)
    expect(db.events(USER)).toEqual([])
    expect(db.operations.filter((o) => o.kind === 'rpc')).toHaveLength(1)
  })
  it.each([
    'context_changed',
    'progress_changed',
    'not_inactive',
  ])('inactivity refusal %s preserves all progress and emits no event', async (reason) => {
    const { db, run } = setup(
      (id) => ({ applied: false, user_id: id, reason }),
      'reset_mobile_inactive_streak_atomic',
    )
    db.tables.meal_logs = []
    db.tables.daily_snapshots = []
    const progress = db.progress(USER)
    const result = await run()
    expect(result.streakReset?.applied).toBe(false)
    expect(db.progress(USER)).toEqual(progress)
    expect(db.events(USER)).toEqual([])
  })
  it.each([
    ['null', () => null],
    ['array', () => []],
    ['string', () => 'applied'],
    ['missing identity', () => ({ applied: true, already_closed: false, day_status: 'complete' })],
    ['foreign identity', () => ({ applied: true, already_closed: false, snapshot_id: 'other' })],
    [
      'nonboolean applied',
      (id: string) => ({ applied: 1, already_closed: false, snapshot_id: id }),
    ],
    [
      'contradictory flags',
      (id: string) => ({ applied: true, already_closed: true, snapshot_id: id }),
    ],
    [
      'unknown refusal',
      (id: string) => ({
        applied: false,
        already_closed: false,
        snapshot_id: id,
        reason: 'invented',
      }),
    ],
    [
      'unproven closed',
      (id: string) => ({
        applied: false,
        already_closed: true,
        snapshot_id: id,
        reason: 'context_changed',
      }),
    ],
  ] as const)('%s cannot advance a frontier or publish close telemetry', async (_name, body) => {
    const { db, run } = setup(body)
    const progress = db.progress(USER)
    const later = db.snapshot(USER, '2026-10-09')
    await expect(run()).rejects.toThrow(/(mobile|atomic) daily close/)
    expect(db.progress(USER)).toEqual(progress)
    expect(db.snapshot(USER, '2026-10-09')).toEqual(later)
    expect(db.events(USER)).toEqual([])
    expect(db.operations.filter((o) => o.kind === 'rpc')).toHaveLength(1)
  })
  it.each([
    undefined,
    'user_skipped',
    'invented',
  ])('a success with mismatched day_status=%s cannot produce close telemetry', async (status) => {
    const { db, run } = setup((snapshotId) => ({
      applied: true,
      already_closed: false,
      snapshot_id: snapshotId,
      day_status: status,
    }))
    await expect(run()).rejects.toThrow('invalid mobile daily close result')
    expect(db.events(USER)).toEqual([])
    expect(db.progress(USER)).toMatchObject({
      xp_total: 40,
      current_streak: 3,
      last_active_date: '2026-10-07',
    })
  })
  it.each([
    'context_changed',
    'snapshot_changed',
    'profile_changed',
    'progress_changed',
    'not_closable',
  ])('%s is an open pending date; no next close or inactivity reset', async (reason) => {
    const { db, run } = setup((snapshotId) => ({
      applied: false,
      already_closed: false,
      snapshot_id: snapshotId,
      reason,
    }))
    const later = db.snapshot(USER, '2026-10-09')
    const progress = db.progress(USER)
    const result = await run()
    expect(result).toMatchObject({
      complete: false,
      pendingDates: ['2026-10-08', '2026-10-09'],
      streakReset: null,
      days: [{ date: '2026-10-08', closed: false, reason: 'changed_concurrently' }],
    })
    expect(db.snapshot(USER, '2026-10-09')).toEqual(later)
    expect(db.progress(USER)).toEqual(progress)
    expect(db.events(USER)).toEqual([])
    expect(db.operations.filter((o) => o.kind === 'rpc')).toHaveLength(1)
  })
})
