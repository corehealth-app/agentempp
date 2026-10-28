/**
 * GET /today with the on-request day close (docs/mobile/api-v1.md,
 * "Fechamento do dia sob demanda"): the close runs before the daily state is
 * read, the handler hands the read model the same arguments as before, and a
 * failed close never reaches the response.
 *
 * The authentication wrapper is a pass-through and the daily-state read is
 * replaced by a marker (its own suite is read-model.test.ts and
 * packages/agent/src/daily-state-service.test.ts); the handler, the hook and
 * the close function are the real ones. In-memory database, no network.
 */
import { clearCalcConfigCache } from '@mpp/agent'
import { DayCloseMemoryDb } from '@mpp/agent/testing/day-close-memory-db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import { invokeContextRoute } from '@/lib/mobile-api/testing/mobile-route-context-fixture'

const readModel = vi.hoisted(() => ({ loadToday: vi.fn() }))

vi.mock('@/lib/mobile-api/route', async (importOriginal) => {
  const { wrapContextRouteHandler } = await import(
    '@/lib/mobile-api/testing/mobile-route-context-fixture'
  )
  return {
    ...(await importOriginal<typeof import('@/lib/mobile-api/route')>()),
    createMobileRoute: wrapContextRouteHandler,
  }
})
vi.mock('@/lib/mobile-api/read-model', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/mobile-api/read-model')>()),
  ...readModel,
}))

const { GET } = await import('./route')
const handler = (context: MobileRouteContext) => invokeContextRoute(GET, context)

const USER = '0b9f6f0e-0000-4000-8000-00000000d0c7'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
/** 08:00 of 2026-10-05 in America/Sao_Paulo. */
const NOW = new Date('2026-10-05T11:00:00.000Z')
const STATE = { local_date: '2026-10-05', calculation_version: 'bodyflow.daily-state.v3' }

function database() {
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
  db.registerMeal({
    userId: USER,
    date: '2026-10-04',
    consumedAt: '2026-10-04T15:00:00.000Z',
    kcal: 1500,
    proteinG: 110,
    caloriesTarget: 1576,
    proteinTarget: 120,
  })
  return db
}

function context(db: DayCloseMemoryDb): MobileRouteContext {
  return {
    request: new Request('https://bodyflow.test/api/mobile/v1/today'),
    requestId: 'request-today',
    supabase: db.client,
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

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  readModel.loadToday.mockReset()
  vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '')
  vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', '')
  vi.stubEnv('MOBILE_STRENGTH_WEEK_PROJECT_REF', '')
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING_REF}.supabase.co`)
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

describe('GET /api/mobile/v1/today', () => {
  it('switch absent: the database is not touched before the daily state is read', async () => {
    const db = database()
    let operationsAtRead = -1
    readModel.loadToday.mockImplementation(async () => {
      operationsAtRead = db.operations.length
      return STATE
    })

    const response = await handler(context(db))

    expect(response.status).toBe(200)
    expect(operationsAtRead).toBe(0)
    expect(db.operations).toEqual([])
    expect(readModel.loadToday).toHaveBeenCalledWith(db.client, USER, 'America/Sao_Paulo')
    expect(await response.json()).toMatchObject({ data: STATE })
  })

  it('switch on: yesterday is closed before the daily state is read; the response is the read model result', async () => {
    vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '2026-09-22')
    vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', STAGING_REF)
    vi.spyOn(console, 'info').mockImplementation(() => undefined)
    const db = database()
    let closedAtRead: unknown = null
    readModel.loadToday.mockImplementation(async () => {
      closedAtRead = db.snapshot(USER, '2026-10-04')?.day_closed
      return STATE
    })

    const response = await handler(context(db))
    const body = await response.json()

    expect(closedAtRead).toBe(true)
    expect(db.progress(USER)).toMatchObject({ xp_total: 15, deficit_block: 576, current_streak: 1 })
    expect(readModel.loadToday).toHaveBeenCalledWith(db.client, USER, 'America/Sao_Paulo')
    expect(Object.keys(body).sort()).toEqual(['data', 'meta'])
    expect(body.data).toEqual(STATE)
  })

  it('switch on and the close fails: the daily state is still read and returned', async () => {
    vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '2026-09-22')
    vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', STAGING_REF)
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const db = database()
    db.failWith = () => 'database unavailable'
    readModel.loadToday.mockResolvedValue(STATE)

    const response = await handler(context(db))

    expect(response.status).toBe(200)
    expect(await response.json()).toMatchObject({ data: STATE })
  })
})
