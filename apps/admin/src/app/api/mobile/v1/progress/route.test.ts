/**
 * GET /progress with the on-request day close (docs/mobile/api-v1.md,
 * "Fechamento do dia sob demanda"): the close runs BEFORE the read, the
 * response keeps its shape, and with the switch absent the handler does
 * exactly the one read it always did.
 *
 * The authentication wrapper is replaced by a pass-through so the handler
 * can be called with a context; the handler, the hook, the read model and
 * the close function are the real ones. In-memory database, no network.
 */
import { clearCalcConfigCache } from '@mpp/agent'
import { DayCloseMemoryDb } from '@mpp/agent/testing/day-close-memory-db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

vi.mock('@/lib/mobile-api/route', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/mobile-api/route')>()),
  createMobileRoute: (handler: unknown) => handler,
}))

const { GET } = await import('./route')
const handler = GET as unknown as (context: MobileRouteContext) => Promise<Response>

const USER = '0b9f6f0e-0000-4000-8000-00000000d0c6'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
/** 08:00 of 2026-10-05 in America/Sao_Paulo. */
const NOW = new Date('2026-10-05T11:00:00.000Z')

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
    request: new Request('https://bodyflow.test/api/mobile/v1/progress'),
    requestId: 'request-progress',
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

const PROGRESS_KEYS = [
  'badges_earned',
  'blocks_completed',
  'current_bf_percent',
  'current_streak',
  'current_weight',
  'deficit_block',
  'last_active_date',
  'level',
  'longest_streak',
  'next_reevaluation',
  'updated_at',
  'xp_total',
]

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '')
  vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', '')
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING_REF}.supabase.co`)
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

describe('GET /api/mobile/v1/progress', () => {
  it('switch absent: one read, no write, the progress row as it is', async () => {
    const db = database()
    const response = await handler(context(db))
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(db.operations).toHaveLength(1)
    expect(db.operations[0]).toMatchObject({ kind: 'select', target: 'user_progress' })
    expect(Object.keys(body.data).sort()).toEqual(PROGRESS_KEYS)
    expect(body.data).toMatchObject({ xp_total: 0, current_streak: 0, deficit_block: 0 })
  })

  it('switch on: yesterday is closed first, and the same shape carries the new numbers', async () => {
    vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '2026-09-22')
    vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', STAGING_REF)
    vi.spyOn(console, 'info').mockImplementation(() => undefined)
    const db = database()

    const response = await handler(context(db))
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(Object.keys(body).sort()).toEqual(['data', 'meta'])
    expect(Object.keys(body.data).sort()).toEqual(PROGRESS_KEYS)
    // balance = 1500 − 1576 = −76; credit = 500 + 76 = 576; XP 10 + 5.
    expect(body.data).toMatchObject({
      xp_total: 15,
      level: 1,
      current_streak: 1,
      longest_streak: 1,
      blocks_completed: 0,
      deficit_block: 576,
      badges_earned: [],
      last_active_date: '2026-10-04',
      next_reevaluation: null,
    })
    // The read the response is built from comes after the finalization.
    const kinds = db.operations.map((operation) => `${operation.kind}:${operation.target}`)
    expect(kinds.lastIndexOf('select:user_progress')).toBeGreaterThan(
      kinds.indexOf('rpc:finalize_daily_close_atomic'),
    )
  })

  it('switch on and the close fails: the request still answers 200 with the stored row', async () => {
    vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '2026-09-22')
    vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', STAGING_REF)
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const db = database()
    db.failWith = (operation) => (operation.kind === 'rpc' ? 'database unavailable' : null)

    const response = await handler(context(db))
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(body.data).toMatchObject({ xp_total: 0, current_streak: 0 })
  })
})
