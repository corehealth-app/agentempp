/**
 * GET /today and GET /progress arriving at the same time, with the on-request
 * day close switched on (review of 2026-10-05, HIGH; docs/CALCULO-MPP.md §3a,
 * rule 1).
 *
 * THE REPRODUCTION, exact. The iPhone opens and fires both requests. The
 * account has the shape of staging's conta-11 (read on 2026-10-04): 27/09
 * with only an inbound Flow message and NO day row, then 30/09 with a meal.
 * Both requests read "no row" for 27/09. One creates the row; the insert of
 * the other comes back empty (`changed_concurrently`). Before the fix the
 * loser went on and closed 30/09; the request that owned 27/09, delayed by
 * one slow round trip, then found the frontier past it: 27/09 stayed open
 * for ever, with `xp_earned = 10` on its row, and the account had 15 XP
 * instead of 25.
 *
 * Here the two REAL route handlers run against one in-memory database, each
 * through its own client (`DayCloseMemoryDb.session`), so one request can be
 * held at that exact point while the other runs to its end. The
 * authentication wrapper is a pass-through and the daily-state read of
 * GET /today is a marker; the hook, the sweep, the close and the progress
 * read are the real ones. No network.
 *
 * ASSUMED, declared: the profile (homem, 80 kg, 180 cm, born 1986-01-01,
 * atividade leve, recomposição → 1576 kcal) and the meal of 30/09 (1500 kcal,
 * 110 g) are synthetic; of the staging account only the SHAPE is used.
 *   27/09: message only → XP 10, credit 0.
 *   30/09: 1500 − 1576 = −76 → 500 + 76 = 576; 110 g ≥ 100 → XP 15.
 *   28 and 29/09 are empty, so 30/09 restarts the streak at 1; 01 to 04/10
 *   are empty, so the request that finishes the sweep zeroes it.
 */
import { clearCalcConfigCache } from '@mpp/agent'
import { DayCloseMemoryDb, type MemoryOperation } from '@mpp/agent/testing/day-close-memory-db'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from './route'

const readModel = vi.hoisted(() => ({ loadToday: vi.fn() }))

vi.mock('@/lib/mobile-api/route', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./route')>()),
  createMobileRoute: (handler: unknown) => handler,
}))
vi.mock('@/lib/mobile-api/read-model', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./read-model')>()),
  loadToday: readModel.loadToday,
}))

type Handler = (context: MobileRouteContext) => Promise<Response>
const today = (await import('@/app/api/mobile/v1/today/route')).GET as unknown as Handler
const progress = (await import('@/app/api/mobile/v1/progress/route')).GET as unknown as Handler

const USER = '0b9f6f0e-0000-4000-8000-00000000d0c8'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
/** 08:00 of 2026-10-05 in America/Sao_Paulo. */
const NOW = new Date('2026-10-05T11:00:00.000Z')
const STATE = { local_date: '2026-10-05', calculation_version: 'bodyflow.daily-state.v3' }

function stagingShapedAccount() {
  const db = new DayCloseMemoryDb()
  db.addAccount({
    userId: USER,
    profile: {
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
    },
  })
  // 27/09, 10:00 local: one inbound Flow message, no day row.
  db.addInboundMessage(USER, '2026-09-27T13:00:00.000Z')
  // 30/09, 12:00 local: a lunch.
  db.registerMeal({
    userId: USER,
    date: '2026-09-30',
    consumedAt: '2026-09-30T15:00:00.000Z',
    kcal: 1500,
    proteinG: 110,
    mealType: 'almoco',
    caloriesTarget: 1576,
    proteinTarget: 120,
  })
  return db
}

function context(path: 'today' | 'progress', supabase: ServiceClient): MobileRouteContext {
  return {
    request: new Request(`https://bodyflow.test/api/mobile/v1/${path}`),
    requestId: `request-${path}`,
    supabase,
    auth: {
      accessToken: 'redacted',
      authUserId: USER,
      userId: USER,
      identity: { id: USER, email: null, emailConfirmedAt: null },
      patient: {
        id: USER,
        authUserId: USER,
        email: null,
        name: null,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function deferred() {
  let open: () => void = () => undefined
  const wait = new Promise<void>((resolvePromise) => {
    open = resolvePromise
  })
  return { wait, open }
}

function state(db: DayCloseMemoryDb) {
  const { updated_at: _updated, user_id: _user, ...progressRow } = db.progress(USER) ?? {}
  return {
    progress: progressRow,
    days: ['2026-09-27', '2026-09-30'].map((date) => {
      const row = db.snapshot(USER, date)
      return [date, row?.day_closed, row?.calories_consumed, row?.calories_target, row?.xp_earned]
    }),
    closes: db
      .events(USER, 'daily_closer.completed')
      .map((event) => (event.properties as { snapshot_date?: string }).snapshot_date),
    resets: db.events(USER, 'streak.reset_inactive').length,
  }
}

/** What one request alone leaves (first test below). */
const SERIAL = {
  progress: {
    xp_total: 25,
    level: 1,
    current_streak: 0,
    longest_streak: 1,
    blocks_completed: 0,
    deficit_block: 576,
    badges_earned: [],
    last_active_date: '2026-09-30',
    next_reevaluation: null,
    current_weight: null,
    current_bf_percent: null,
  },
  days: [
    ['2026-09-27', true, 0, 1576, 10],
    ['2026-09-30', true, 1500, 1576, 15],
  ],
  closes: ['2026-09-27', '2026-09-30'],
  resets: 1,
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  readModel.loadToday.mockReset()
  readModel.loadToday.mockResolvedValue(STATE)
  vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '2026-09-17')
  vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', STAGING_REF)
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING_REF}.supabase.co`)
  vi.spyOn(console, 'info').mockImplementation(() => undefined)
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

describe('GET /today and GET /progress at the same time, a message-only day then a day with a meal', () => {
  it('one request alone: both days close, 25 XP, bloco 576, the streak zeroed once', async () => {
    const db = stagingShapedAccount()
    const response = await progress(context('progress', db.client))
    expect(response.status).toBe(200)
    expect(state(db)).toEqual(SERIAL)
    expect((await response.json()).data).toMatchObject({ xp_total: 25, deficit_block: 576 })
  })

  it.each([
    ['GET /progress', 'GET /today'],
    ['GET /today', 'GET /progress'],
  ] as const)('%s creates the row of 27/09 and stalls; %s runs whole meanwhile: the account ends as with one request', async (slow, fast) => {
    const db = stagingShapedAccount()
    const run = (name: 'GET /progress' | 'GET /today', client: ServiceClient) =>
      name === 'GET /today'
        ? today(context('today', client))
        : progress(context('progress', client))

    // The slow request: a long round trip right after it created the row of
    // 27/09, before it reads the progress it will finalize from.
    const rowCreated = deferred()
    const resume = deferred()
    let justCreated = false
    const slowResponse = run(
      slow,
      db.session(async (operation: MemoryOperation) => {
        if (justCreated && operation.kind === 'select' && operation.target === 'user_progress') {
          justCreated = false
          rowCreated.open()
          await resume.wait
        }
        if (operation.kind === 'upsert' && operation.target === 'daily_snapshots') {
          justCreated = true
        }
      }),
    )
    // The fast request read "no row for 27/09" too; its insert arrives second.
    let held = false
    const fastResponse = run(
      fast,
      db.session(async (operation: MemoryOperation) => {
        if (!held && operation.kind === 'upsert' && operation.target === 'daily_snapshots') {
          held = true
          await rowCreated.wait
        }
      }),
    )

    const fastResult = await fastResponse
    expect(fastResult.status).toBe(200)
    expect(held).toBe(true)
    // The fast request lost 27/09 and stopped there: 30/09 is still open and
    // nothing was finalized. (Before the fix it had closed 30/09 here.)
    expect(db.snapshot(USER, '2026-09-30')).toMatchObject({ day_closed: false, xp_earned: 0 })
    expect(db.progress(USER)).toMatchObject({ xp_total: 0, last_active_date: null })
    expect(db.operations.filter((operation) => operation.kind === 'rpc')).toEqual([])

    resume.open()
    const slowResult = await slowResponse
    expect(slowResult.status).toBe(200)
    expect(state(db)).toEqual(SERIAL)

    // The response of whichever request was GET /progress is one read of the
    // row: the finished numbers when it was the slow one, the numbers of
    // before the close when it was the fast one (one request late, by design).
    const progressBody = await (slow === 'GET /progress' ? slowResult : fastResult).json()
    expect(progressBody.data).toMatchObject(
      slow === 'GET /progress'
        ? { xp_total: 25, deficit_block: 576, current_streak: 0, longest_streak: 1 }
        : { xp_total: 0, deficit_block: 0, current_streak: 0, longest_streak: 0 },
    )
    const todayBody = await (slow === 'GET /today' ? slowResult : fastResult).json()
    expect(todayBody.data).toEqual(STATE)

    // The next GET /progress shows the serial numbers and writes nothing.
    const writes = db.writes.length
    const next = await progress(context('progress', db.client))
    expect((await next.json()).data).toMatchObject({
      xp_total: 25,
      deficit_block: 576,
      last_active_date: '2026-09-30',
    })
    expect(db.writes.length).toBe(writes)
    expect(state(db)).toEqual(SERIAL)
  })
})
