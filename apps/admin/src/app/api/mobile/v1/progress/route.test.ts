/**
 * GET /progress with the on-request day close (docs/mobile/api-v1.md,
 * "Fechamento do dia sob demanda"): the close runs BEFORE the read, the
 * response preserves its saved fields and adds presentation eligibility.
 * With the switch absent, the handler only reads progress and its objective.
 *
 * The authentication wrapper is replaced by a pass-through so the handler
 * can be called with a context; the handler, the hook, the read model and
 * the close function are the real ones. In-memory database, no network.
 */
import { clearCalcConfigCache } from '@mpp/agent'
import { DayCloseMemoryDb } from '@mpp/agent/testing/day-close-memory-db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'
import { invokeContextRoute } from '@/lib/mobile-api/testing/mobile-route-context-fixture'

vi.mock('@/lib/mobile-api/route', async (importOriginal) => {
  const { wrapContextRouteHandler } = await import(
    '@/lib/mobile-api/testing/mobile-route-context-fixture'
  )
  return {
    ...(await importOriginal<typeof import('@/lib/mobile-api/route')>()),
    createMobileRoute: wrapContextRouteHandler,
  }
})

const { GET } = await import('./route')
const handler = (context: MobileRouteContext) => invokeContextRoute(GET, context)

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
  'block_7700_enabled',
  'blocks_completed',
  'current_bf_origin',
  'current_bf_percent',
  'current_protocol',
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
  it.each([
    ['recomposicao', true],
    ['ganho_massa', false],
    ['manutencao', false],
    [null, false],
    ['RECOMPOSICAO', false],
    ['desconhecido', false],
  ] as const)('current official protocol %s projects eligibility %s without rewriting saved progress', async (protocol, enabled) => {
    const db = database()
    const profile = db.tables.user_profiles[0]
    const saved = db.tables.user_progress[0]
    if (!profile || !saved) throw new Error('Missing fixture account')
    profile.current_protocol = protocol
    Object.assign(saved, {
      deficit_block: 3_120,
      blocks_completed: 4,
      xp_total: 1_240,
      level: 2,
      current_streak: 3,
      longest_streak: 7,
      current_weight: 80,
      current_bf_percent: null,
      last_active_date: '2026-10-04',
      next_reevaluation: '2026-10-18',
      badges_earned: ['Primeiro Bloco', 'Primeira Semana'],
    })
    const original = structuredClone(saved)
    // Another patient's profile must not decide this patient's presentation.
    db.addAccount({
      userId: '0b9f6f0e-0000-4000-8000-00000000ffff',
      profile: { current_protocol: enabled ? 'ganho_massa' : 'recomposicao' },
    })

    const response = await handler(context(db))
    const body = await response.json()
    expect(response.status).toBe(200)
    expect(body.data).toEqual({
      ...Object.fromEntries(PROGRESS_KEYS.map((key) => [key, original[key]])),
      current_protocol:
        protocol === 'recomposicao' || protocol === 'ganho_massa' || protocol === 'manutencao'
          ? protocol
          : null,
      block_7700_enabled: enabled,
      current_bf_origin: null,
    })
    expect(db.progress(USER)).toEqual(original)
    expect(db.writes).toEqual([])
    expect(db.operations.find((op) => op.target === 'user_profiles')?.filters).toEqual([
      { op: 'eq', column: 'user_id', value: USER },
    ])
  })

  it('a missing profile hides block presentation without deleting the saved balance', async () => {
    const db = database()
    db.tables.user_profiles.length = 0
    const body = await (await handler(context(db))).json()
    expect(body.data).toMatchObject({
      current_protocol: null,
      block_7700_enabled: false,
      deficit_block: 0,
    })
    expect(db.writes).toEqual([])
  })

  it('a missing progress row remains data:null, even with an official recomposition profile', async () => {
    const db = database()
    db.tables.user_progress.length = 0
    const body = await (await handler(context(db))).json()
    expect(body.data).toBeNull()
    expect(db.writes).toEqual([])
  })

  it('profile read failure remains a typed error even when the progress row is missing', async () => {
    const db = database()
    db.tables.user_progress.length = 0
    db.failWith = (operation) =>
      operation.target === 'user_profiles' ? 'database unavailable' : null
    await expect(handler(context(db))).rejects.toMatchObject({
      status: 500,
      code: 'data_access_failed',
    })
    expect(db.writes).toEqual([])
  })

  it('starts the independent profile read while the progress read is still held', async () => {
    const db = database()
    let releaseProgress: () => void = () => {
      throw new Error('Missing progress release')
    }
    const progressGate = new Promise<void>((resolve) => {
      releaseProgress = resolve
    })
    let markProgressStarted: () => void = () => {
      throw new Error('Missing progress marker')
    }
    const progressStarted = new Promise<void>((resolve) => {
      markProgressStarted = resolve
    })
    let profileReads = 0
    const requestContext = context(db)
    requestContext.supabase = db.session(async (operation) => {
      if (operation.kind === 'select' && operation.target === 'user_progress') {
        markProgressStarted()
        await progressGate
      }
      if (operation.kind === 'select' && operation.target === 'user_profiles') profileReads += 1
    })
    const pendingResponse = handler(requestContext)
    await progressStarted
    try {
      expect(profileReads).toBe(1)
      expect(db.writes).toEqual([])
    } finally {
      releaseProgress()
    }
    const response = await pendingResponse
    expect(response.status).toBe(200)
    expect((await response.json()).data).toMatchObject({
      current_protocol: 'recomposicao',
      block_7700_enabled: true,
    })
  })

  it.each([
    'user_profiles',
    'user_progress',
  ])('query failure in %s is a typed error, not a silent eligibility fallback', async (table) => {
    const db = database()
    db.failWith = (operation) => (operation.target === table ? 'database unavailable' : null)
    await expect(handler(context(db))).rejects.toMatchObject({
      status: 500,
      code: 'data_access_failed',
    })
    expect(db.writes).toEqual([])
  })

  it('switch absent: two scoped reads, no write, saved progress plus presentation eligibility', async () => {
    const db = database()
    const response = await handler(context(db))
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(db.operations).toHaveLength(2)
    expect(db.operations[0]).toMatchObject({ kind: 'select', target: 'user_progress' })
    expect(db.operations[1]).toMatchObject({ kind: 'select', target: 'user_profiles' })
    expect(Object.keys(body.data).sort()).toEqual(PROGRESS_KEYS)
    expect(body.data).toMatchObject({
      xp_total: 0,
      current_streak: 0,
      deficit_block: 0,
      current_protocol: 'recomposicao',
      block_7700_enabled: true,
    })
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
