import { describe, expect, it, vi } from 'vitest'
import {
  closePastOpenDays,
  type DayCloseClinicalAuthority,
  type DayCloseResult,
} from './day-close.js'
import { DayCloseMemoryDb } from './testing/day-close-memory-db.js'

const owner = 'b3b01000-0000-4000-8000-000000003700'
const zone = 'America/Sao_Paulo'
const now = new Date('2026-10-05T11:00:00Z')
const base = { userId: owner, timezone: zone, from: '2026-09-22', now }
function db(dates: string[] = []) {
  const value = new DayCloseMemoryDb()
  value.addAccount({
    userId: owner,
    profile: { current_protocol: 'recomposicao', deficit_level: 500 },
  })
  for (const date of dates)
    value.registerMeal({
      userId: owner,
      date,
      consumedAt: `${date}T15:00:00Z`,
      kcal: 1500,
      proteinG: 100,
      mealType: 'almoco',
      caloriesTarget: 2000,
      proteinTarget: 130,
    })
  value.failWith = (op) =>
    op.kind === 'select' ? null : 'Legacy writer forbidden in clinical path'
  return value
}
function closed(date: string): DayCloseResult {
  return {
    date,
    closed: true,
    dryRun: false,
    late: true,
    detail: {
      caloriesConsumed: 1500,
      exerciseCalories: 0,
      storedCaloriesTarget: 2000,
      caloriesTarget: 2000,
      storedProteinTarget: 130,
      proteinTarget: 130,
      dayStatus: 'complete',
      xpEarned: 15,
      blockCredit: 1000,
      newBadges: [],
      progress: {
        xpTotal: 15,
        level: 1,
        currentStreak: 1,
        longestStreak: 1,
        blocksCompleted: 0,
        deficitBlock: 1000,
        badgesEarned: [],
        lastActiveDate: date,
      },
    },
  }
}
function authority() {
  return {
    closeDate: vi.fn<DayCloseClinicalAuthority['closeDate']>(async ({ date }) => closed(date)),
    resetInactive: vi.fn<DayCloseClinicalAuthority['resetInactive']>(async () => null),
  }
}
describe('paired authoritative clinical close/reset sweep', () => {
  it('uses only clinical ports in date order and preserves the existing effective-close budget', async () => {
    const data = db(['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04']),
      ports = authority()
    const result = await closePastOpenDays(data.client, {
      ...base,
      limits: { maxDays: 3 },
      clinicalAuthority: ports,
    })
    expect(ports.closeDate.mock.calls.map(([scope]) => scope.date)).toEqual([
      '2026-10-01',
      '2026-10-02',
      '2026-10-03',
    ])
    expect(ports.closeDate.mock.calls[0]).toEqual([
      { userId: owner, from: base.from, timezone: zone, date: '2026-10-01' },
    ])
    expect(result.pendingDates).toEqual(['2026-10-04'])
    expect(result.complete).toBe(false)
    expect(ports.resetInactive).not.toHaveBeenCalled()
    expect(data.writes).toEqual([])
  })
  it('calls the clinical inactivity authority even with empty discovery and never performs a legacy reset/event', async () => {
    const data = db(),
      ports = authority()
    data.tables.user_progress[0] = {
      ...data.tables.user_progress[0],
      user_id: owner,
      current_streak: 4,
      longest_streak: 9,
      last_active_date: '2026-10-02',
    }
    ports.resetInactive.mockResolvedValueOnce({
      applied: true,
      previousStreak: 4,
      lastActiveDate: '2026-10-02',
      gapDays: 2,
    })
    const result = await closePastOpenDays(data.client, { ...base, clinicalAuthority: ports })
    expect(ports.closeDate).not.toHaveBeenCalled()
    expect(ports.resetInactive).toHaveBeenCalledWith({
      userId: owner,
      from: base.from,
      timezone: zone,
      latestClosableDate: '2026-10-04',
    })
    expect(result.streakReset).toEqual({
      applied: true,
      previousStreak: 4,
      lastActiveDate: '2026-10-02',
      gapDays: 2,
    })
    expect(data.writes).toEqual([])
  })
  it('stops on a refused date without visiting later dates or resetting inactivity', async () => {
    const data = db(['2026-10-02', '2026-10-03']),
      ports = authority()
    ports.closeDate.mockResolvedValueOnce({
      date: '2026-10-02',
      closed: false,
      dryRun: false,
      late: true,
      reason: 'earlier_date_changed',
    })
    const result = await closePastOpenDays(data.client, { ...base, clinicalAuthority: ports })
    expect(result.pendingDates).toEqual(['2026-10-02', '2026-10-03'])
    expect(result.complete).toBe(false)
    expect(ports.closeDate).toHaveBeenCalledTimes(1)
    expect(ports.resetInactive).not.toHaveBeenCalled()
    expect(data.writes).toEqual([])
  })
  it('propagates port errors without retry or fallback', async () => {
    const data = db(['2026-10-04']),
      ports = authority(),
      error = new Error('clinical conflict')
    ports.closeDate.mockRejectedValueOnce(error)
    await expect(
      closePastOpenDays(data.client, { ...base, clinicalAuthority: ports }),
    ).rejects.toBe(error)
    expect(ports.closeDate).toHaveBeenCalledTimes(1)
    expect(ports.resetInactive).not.toHaveBeenCalled()
    expect(data.writes).toEqual([])
  })
  it('binds both callbacks and the budget before yielding to discovery', async () => {
    const data = db(['2026-10-03', '2026-10-04']),
      ports = authority(),
      close = ports.closeDate,
      reset = ports.resetInactive
    const input = { ...base, limits: { maxDays: 1 }, clinicalAuthority: ports }
    data.before = () => {
      input.limits.maxDays = 9
      ports.closeDate = vi.fn(async () => {
        throw new Error('replaced')
      })
      ports.resetInactive = vi.fn(async () => {
        throw new Error('replaced')
      })
    }
    const result = await closePastOpenDays(data.client, input)
    expect(close).toHaveBeenCalledTimes(1)
    expect(reset).not.toHaveBeenCalled()
    expect(result.pendingDates).toEqual(['2026-10-04'])
    expect(data.writes).toEqual([])
  })
  it.each([
    null,
    {},
    { closeDate: async () => closed('2026-10-04') },
    { resetInactive: async () => null },
  ])('refuses an incomplete authority before any query', async (partial) => {
    const data = db()
    await expect(
      closePastOpenDays(data.client, {
        ...base,
        // Deliberately cross the runtime boundary with a malformed paired port.
        clinicalAuthority: partial as unknown as DayCloseClinicalAuthority,
      }),
    ).rejects.toThrow()
    expect(data.operations).toEqual([])
  })
  it.each([
    { dryRun: true },
    { advanceReevaluation: true },
  ])('cannot use a writing authority for unsupported mode %o', async (mode) => {
    const data = db(),
      ports = authority()
    await expect(
      closePastOpenDays(data.client, { ...base, ...mode, clinicalAuthority: ports }),
    ).rejects.toThrow()
    expect(data.operations).toEqual([])
  })
  it('refuses an invalid returned result without falling through to a writer or reset', async () => {
    const data = db(['2026-10-04']),
      ports = authority()
    ports.closeDate.mockResolvedValueOnce({ ...closed('2026-10-04'), date: '2026-10-03' })
    await expect(
      closePastOpenDays(data.client, { ...base, clinicalAuthority: ports }),
    ).rejects.toThrow()
    expect(ports.resetInactive).not.toHaveBeenCalled()
    expect(data.writes).toEqual([])
  })
})
