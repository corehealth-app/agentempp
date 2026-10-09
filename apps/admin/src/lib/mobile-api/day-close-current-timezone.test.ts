/**
 * C11-26: one instant, two official time zones. The real request hook reads
 * Tokyo, then the real updateMe changes the account to Honolulu. The close
 * reaches its final RPC with a date that is now the account's current day.
 *
 * The database boundary is the existing day-close memory double, including
 * the effective legacy finalizer. This proves the stale request path, not
 * PostgreSQL locks or the not-yet-implemented C11 mutation RPC.
 */
import { clearCalcConfigCache } from '@mpp/agent'
import { DayCloseMemoryDb } from '@mpp/agent/testing/day-close-memory-db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { updateMe } from './commands'
import { closeOpenDaysOnRequest } from './day-close-on-request'
import type { MobileRouteContext } from './route'

const USER = '0b9f6f0e-0000-4000-8000-00000000c126'
const OTHER = '0b9f6f0e-0000-4000-8000-00000000c127'
const NOW = new Date('2026-10-09T20:00:00.000Z')
const CONSUMED_AT = '2026-10-09T10:30:00.000Z'
const ON = {
  MOBILE_DAY_CLOSE_FROM: '2026-10-09',
  MOBILE_DAY_CLOSE_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
  NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
}
const PROFILE = {
  sex: 'masculino',
  birth_date: '1986-01-01',
  height_cm: 180,
  weight_kg: 80,
  body_fat_percent: null,
  activity_level: 'leve',
  training_frequency: 3,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  goal_type: null,
  goal_value: null,
  current_protocol: 'recomposicao',
  deficit_level: 500,
}

function setup() {
  const db = new DayCloseMemoryDb()
  db.addAccount({ userId: USER, timezone: 'Asia/Tokyo', profile: PROFILE })
  db.addAccount({ userId: OTHER, timezone: 'Pacific/Honolulu', profile: PROFILE })
  const user = db.tables.users.find((row) => row.id === USER)
  if (!user) throw new Error('synthetic account missing')
  Object.assign(user, {
    auth_user_id: USER,
    country: 'BR',
    country_confirmed: true,
    locale: 'pt-BR',
    name: null,
    email: null,
  })
  db.registerMeal({
    userId: USER,
    date: '2026-10-09',
    consumedAt: CONSUMED_AT,
    kcal: 1000,
    proteinG: 60,
    caloriesTarget: 1576,
    proteinTarget: 120,
  })
  const context: Pick<MobileRouteContext, 'auth' | 'supabase' | 'requestId'> = {
    requestId: 'synthetic-current-day-c11-26',
    supabase: db.client,
    auth: {
      accessToken: 'synthetic-not-a-token',
      authUserId: USER,
      userId: USER,
      identity: { id: USER, email: null, emailConfirmedAt: null },
      patient: {
        id: USER,
        authUserId: USER,
        email: null,
        name: null,
        locale: 'pt-BR',
        timezone: 'Asia/Tokyo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
  return { db, context }
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  vi.spyOn(console, 'info').mockImplementation(() => undefined)
})
afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

describe('C11-26 current-day safety at finalization', () => {
  it('empty discovery after Tokyo to Honolulu must not reset an active streak using the old calendar', async () => {
    const { db, context } = setup()
    // No meal/workout/IN candidate remains. Tokyo latest=09 (gap2), while
    // Honolulu latest=08 (gap1) at this exact same instant.
    db.tables.meal_logs = []
    db.tables.daily_snapshots = []
    const progress = db.tables.user_progress.find((row) => row.user_id === USER)
    if (!progress) throw new Error('synthetic progress missing')
    Object.assign(progress, {
      xp_total: 40,
      current_streak: 3,
      longest_streak: 3,
      last_active_date: '2026-10-07',
    })
    const before = db.progress(USER)
    let moved = false
    db.before = async (operation) => {
      if (!moved && operation.kind === 'select' && operation.target === 'user_progress') {
        moved = true
        await updateMe(db.client, context.auth, { timezone: 'Pacific/Honolulu' })
      }
    }
    await closeOpenDaysOnRequest(context, { env: ON, now: NOW })
    expect(moved).toBe(true)
    expect(db.progress(USER)).toEqual(before)
    expect(db.events(USER)).toEqual([])
  })
  it('the exact timezone race preserves an existing streak and produces no inactivity reset', async () => {
    const { db, context } = setup()
    const progress = db.tables.user_progress.find((row) => row.user_id === USER)
    if (!progress) throw new Error('synthetic progress missing')
    Object.assign(progress, {
      xp_total: 40,
      current_streak: 3,
      longest_streak: 3,
      last_active_date: '2026-10-07',
    })
    const before = db.progress(USER)
    let moved = false
    db.before = async (operation) => {
      if (!moved && operation.kind === 'select' && operation.target === 'user_profiles') {
        moved = true
        await updateMe(db.client, context.auth, { timezone: 'Pacific/Honolulu' })
      }
    }
    await closeOpenDaysOnRequest(context, { env: ON, now: NOW })
    expect(moved).toBe(true)
    expect(db.snapshot(USER, '2026-10-09')?.day_closed).toBe(false)
    expect(db.progress(USER)).toEqual(before)
    expect(db.events(USER)).toEqual([])
  })
  it.each([
    false,
    true,
  ])('Tokyo to Honolulu before finalization, correction boundary=%s: current day stays open', async (corrected) => {
    const { db, context } = setup()
    const otherBefore = structuredClone({
      user: db.tables.users.find((row) => row.id === OTHER),
      profile: db.tables.user_profiles.find((row) => row.user_id === OTHER),
      progress: db.progress(OTHER),
    })
    let moved = false
    let reachedFinalization = false
    db.before = async (operation) => {
      if (!moved && operation.kind === 'select' && operation.target === 'user_profiles') {
        moved = true
        await updateMe(db.client, context.auth, { timezone: 'Pacific/Honolulu' })
      }
      if (
        operation.kind === 'rpc' &&
        ['finalize_daily_close_atomic', 'finalize_mobile_daily_close_atomic'].includes(
          operation.target,
        )
      ) {
        reachedFinalization = true
        if (corrected) {
          // Exact interleaving after the closer UPDATE, before finalization.
          // Only the existing meal is replaced: no new fictitious food.
          const meal = db.tables.meal_logs.find((row) => row.user_id === USER)
          const snapshot = db.tables.daily_snapshots.find((row) => row.user_id === USER)
          if (!meal || !snapshot) throw new Error('synthetic confirmed record missing')
          meal.kcal = 500
          meal.protein_g = 30
          snapshot.calories_consumed = 500
          snapshot.protein_g = 30
          snapshot.updated_at = db.timestamp()
        }
      }
    }
    await closeOpenDaysOnRequest(context, { env: ON, now: NOW })
    expect(moved).toBe(true)
    expect(reachedFinalization).toBe(true)
    expect(db.tables.users.find((row) => row.id === USER)?.timezone).toBe('Pacific/Honolulu')
    expect(db.snapshot(USER, '2026-10-09')).toMatchObject({
      day_closed: false,
      calories_consumed: corrected ? 500 : 1000,
    })
    expect(db.progress(USER)).toMatchObject({
      xp_total: 0,
      current_streak: 0,
      deficit_block: 0,
      last_active_date: null,
    })
    expect(db.events(USER)).toEqual([])
    expect({
      user: db.tables.users.find((row) => row.id === OTHER),
      profile: db.tables.user_profiles.find((row) => row.user_id === OTHER),
      progress: db.progress(OTHER),
    }).toEqual(otherBefore)
  })
})
