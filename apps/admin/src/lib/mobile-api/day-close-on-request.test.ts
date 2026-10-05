/**
 * The opt-in hook that closes past open days from GET /today and GET
 * /progress on the test environment (docs/CALCULO-MPP.md §3a,
 * docs/mobile/api-v1.md "Fechamento do dia sob demanda").
 *
 * What is locked here: the three locks (and that a closed lock costs not a
 * single query), the hard refusal of the production project, that a failure
 * never reaches the request, and that nothing else in the admin app imports
 * the hook. The numbers of a closed day are locked in packages/agent
 * (__golden__/audit-10-04-app-day-close.test.ts).
 *
 * In-memory database; no network. The project refs are the two real ones
 * (they are identifiers of projects, not credentials); every URL here is only
 * parsed, never called.
 */
import { readdirSync, readFileSync } from 'node:fs'
import { dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { clearCalcConfigCache } from '@mpp/agent'
import { DayCloseMemoryDb } from '@mpp/agent/testing/day-close-memory-db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  closeOpenDaysOnRequest,
  DAY_CLOSE_FROM_ENV,
  DAY_CLOSE_PROJECT_REF_ENV,
  projectRefFromUrl,
  resolveDayCloseStart,
} from './day-close-on-request'
import type { MobileRouteContext } from './route'

const USER = '0b9f6f0e-0000-4000-8000-00000000d0c5'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
const PRODUCTION_REF = 'xuxehkhdvjivitduarvb'
const STAGING_URL = `https://${STAGING_REF}.supabase.co`
const PRODUCTION_URL = `https://${PRODUCTION_REF}.supabase.co`
/** 08:00 of 2026-10-05 in America/Sao_Paulo. */
const NOW = new Date('2026-10-05T11:00:00.000Z')

const ON = {
  [DAY_CLOSE_FROM_ENV]: '2026-09-22',
  [DAY_CLOSE_PROJECT_REF_ENV]: STAGING_REF,
  NEXT_PUBLIC_SUPABASE_URL: STAGING_URL,
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

function account(overrides: { wpp?: string | null; timezone?: string | null } = {}) {
  const db = new DayCloseMemoryDb()
  db.addAccount({ userId: USER, profile: PROFILE, ...overrides })
  // Yesterday (2026-10-04): 1500 kcal against 1576, 110 g of protein.
  db.registerMeal({
    userId: USER,
    date: '2026-10-04',
    consumedAt: '2026-10-04T15:00:00.000Z',
    kcal: 1500,
    proteinG: 110,
    mealType: 'almoco',
    caloriesTarget: 1576,
    proteinTarget: 120,
  })
  return db
}

function context(
  db: DayCloseMemoryDb,
): Pick<MobileRouteContext, 'auth' | 'requestId' | 'supabase'> {
  return {
    requestId: 'request-day-close',
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
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

describe('lock 1 and 2 — the environment', () => {
  it('reads the project ref only from a hosted https URL', () => {
    expect(projectRefFromUrl(STAGING_URL)).toBe(STAGING_REF)
    expect(projectRefFromUrl(`${STAGING_URL}/`)).toBe(STAGING_REF)
    expect(projectRefFromUrl(undefined)).toBeNull()
    expect(projectRefFromUrl('')).toBeNull()
    expect(projectRefFromUrl('not a url')).toBeNull()
    expect(projectRefFromUrl(`http://${STAGING_REF}.supabase.co`)).toBeNull()
    expect(projectRefFromUrl('https://db.example.com')).toBeNull()
    expect(projectRefFromUrl(`https://${STAGING_REF}.supabase.co.example.com`)).toBeNull()
    expect(projectRefFromUrl('http://localhost:54321')).toBeNull()
  })

  it.each([
    ['everything set for staging', ON, '2026-09-22'],
    ['the date variable absent', { ...ON, [DAY_CLOSE_FROM_ENV]: undefined }, null],
    ['the date variable empty', { ...ON, [DAY_CLOSE_FROM_ENV]: '  ' }, null],
    ['the date variable "true"', { ...ON, [DAY_CLOSE_FROM_ENV]: 'true' }, null],
    ['the date variable in another format', { ...ON, [DAY_CLOSE_FROM_ENV]: '22/09/2026' }, null],
    ['an impossible date', { ...ON, [DAY_CLOSE_FROM_ENV]: '2026-13-45' }, null],
    ['a date the calendar does not have', { ...ON, [DAY_CLOSE_FROM_ENV]: '2026-02-31' }, null],
    ['the project variable absent', { ...ON, [DAY_CLOSE_PROJECT_REF_ENV]: undefined }, null],
    [
      'the project variable naming another project',
      { ...ON, [DAY_CLOSE_PROJECT_REF_ENV]: 'abcdefghijklmnopqrst' },
      null,
    ],
    ['the database URL absent', { ...ON, NEXT_PUBLIC_SUPABASE_URL: undefined }, null],
    ['the database URL of production', { ...ON, NEXT_PUBLIC_SUPABASE_URL: PRODUCTION_URL }, null],
    [
      'production URL AND production listed as allowed',
      {
        ...ON,
        NEXT_PUBLIC_SUPABASE_URL: PRODUCTION_URL,
        [DAY_CLOSE_PROJECT_REF_ENV]: PRODUCTION_REF,
      },
      null,
    ],
    [
      'staging URL, but production also listed as allowed',
      { ...ON, [DAY_CLOSE_PROJECT_REF_ENV]: `${STAGING_REF},${PRODUCTION_REF}` },
      null,
    ],
    [
      'several allowed projects, staging among them',
      { ...ON, [DAY_CLOSE_PROJECT_REF_ENV]: `abcdefghijklmnopqrst, ${STAGING_REF}` },
      '2026-09-22',
    ],
  ])('%s', (_name, env, expected) => {
    expect(resolveDayCloseStart(env)).toBe(expected)
  })

  it.each([
    ['both variables absent (the default everywhere)', { NEXT_PUBLIC_SUPABASE_URL: STAGING_URL }],
    ['only the date variable', { ...ON, [DAY_CLOSE_PROJECT_REF_ENV]: undefined }],
    ['only the project variable', { ...ON, [DAY_CLOSE_FROM_ENV]: undefined }],
    [
      'the production database, with both variables set for it',
      {
        [DAY_CLOSE_FROM_ENV]: '2026-09-22',
        [DAY_CLOSE_PROJECT_REF_ENV]: PRODUCTION_REF,
        NEXT_PUBLIC_SUPABASE_URL: PRODUCTION_URL,
      },
    ],
    [
      'the production database, with the staging ref allowed',
      {
        ...ON,
        NEXT_PUBLIC_SUPABASE_URL: PRODUCTION_URL,
      },
    ],
    [
      'a project that is not listed',
      { ...ON, [DAY_CLOSE_PROJECT_REF_ENV]: 'abcdefghijklmnopqrst' },
    ],
  ])('off — %s: not a single query, not a single write', async (_name, env) => {
    const db = account()
    const operationsBefore = db.operations.length
    // A client that fails on ANY use: off means the client is never touched.
    const untouchable = new Proxy(
      {},
      {
        get() {
          throw new Error('the database client was used')
        },
      },
    ) as MobileRouteContext['supabase']
    const error = vi.spyOn(console, 'error').mockImplementation(() => undefined)

    await closeOpenDaysOnRequest({ ...context(db), supabase: untouchable }, { env, now: NOW })
    await closeOpenDaysOnRequest(context(db), { env, now: NOW })

    expect(db.operations.length).toBe(operationsBefore)
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ day_closed: false })
    // Nothing was caught either: the client was not reached at all.
    expect(error).not.toHaveBeenCalled()
  })

  it('reads the real process environment when no environment is handed in', async () => {
    const db = account()
    vi.stubEnv(DAY_CLOSE_FROM_ENV, '')
    vi.stubEnv(DAY_CLOSE_PROJECT_REF_ENV, '')
    await closeOpenDaysOnRequest(context(db))
    expect(db.operations).toEqual([])

    vi.stubEnv(DAY_CLOSE_FROM_ENV, '2026-09-22')
    vi.stubEnv(DAY_CLOSE_PROJECT_REF_ENV, STAGING_REF)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', PRODUCTION_URL)
    await closeOpenDaysOnRequest(context(db))
    expect(db.operations).toEqual([])

    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', STAGING_URL)
    vi.spyOn(console, 'info').mockImplementation(() => undefined)
    await closeOpenDaysOnRequest(context(db))
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ day_closed: true })
  })
})

describe('lock 3 — the account', () => {
  it('an account with a WhatsApp number: one read of the account, nothing else', async () => {
    const db = account({ wpp: '5511999990000' })
    await closeOpenDaysOnRequest(context(db), { env: ON, now: NOW })
    expect(db.operations).toHaveLength(1)
    expect(db.operations[0]).toMatchObject({ kind: 'select', target: 'users' })
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ day_closed: false })
  })

  it.each([
    [null],
    [''],
  ])('an account with time zone %j: one read, nothing else', async (timezone) => {
    const db = account({ timezone })
    await closeOpenDaysOnRequest(context(db), { env: ON, now: NOW })
    expect(db.operations).toHaveLength(1)
    expect(db.writes).toEqual([])
  })

  it('an account row that does not exist: nothing is closed', async () => {
    const db = account()
    db.tables.users.length = 0
    await closeOpenDaysOnRequest(context(db), { env: ON, now: NOW })
    expect(db.writes).toEqual([])
  })
})

describe('all three locks open', () => {
  it('closes yesterday, logs counts only, and a second request writes nothing', async () => {
    const db = account()
    const info = vi.spyOn(console, 'info').mockImplementation(() => undefined)

    await closeOpenDaysOnRequest(context(db), { env: ON, now: NOW })

    // balance = 1500 − 1576 = −76; credit = 500 + 76 = 576; XP 10 + 5.
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ day_closed: true, xp_earned: 15 })
    expect(db.progress(USER)).toMatchObject({
      xp_total: 15,
      current_streak: 1,
      deficit_block: 576,
      last_active_date: '2026-10-04',
      // The reassessment schedule is not advanced by this path.
      next_reevaluation: null,
    })
    expect(info).toHaveBeenCalledTimes(1)
    expect(info).toHaveBeenCalledWith('[mobile-api] day_close', {
      request_id: 'request-day-close',
      scope: 'mobile_api_v1',
      closed: 1,
      pending: 0,
      left_open_behind_frontier: 0,
      streak_reset: false,
    })
    expect(JSON.stringify(info.mock.calls)).not.toContain(USER)

    const writes = db.writes.length
    const operations = db.operations.length
    await closeOpenDaysOnRequest(context(db), { env: ON, now: NOW })
    expect(db.writes.length).toBe(writes)
    // The account read, then the one progress read of the fast exit.
    expect(db.operations.length).toBe(operations + 2)
    expect(info).toHaveBeenCalledTimes(1)
  })

  it('never closes a date before MOBILE_DAY_CLOSE_FROM', async () => {
    const db = account()
    vi.spyOn(console, 'info').mockImplementation(() => undefined)
    await closeOpenDaysOnRequest(context(db), {
      env: { ...ON, [DAY_CLOSE_FROM_ENV]: '2026-10-05' },
      now: NOW,
    })
    expect(db.operations).toEqual([expect.objectContaining({ kind: 'select', target: 'users' })])
    expect(db.snapshot(USER, '2026-10-04')).toMatchObject({ day_closed: false })
  })

  it('one request closes at most three days; the next ones finish, in order', async () => {
    const db = account()
    for (const date of ['2026-09-30', '2026-10-01', '2026-10-02', '2026-10-03']) {
      db.registerMeal({
        userId: USER,
        date,
        consumedAt: `${date}T15:00:00.000Z`,
        kcal: 1500,
        proteinG: 110,
        caloriesTarget: 1576,
        proteinTarget: 120,
      })
    }
    vi.spyOn(console, 'info').mockImplementation(() => undefined)

    await closeOpenDaysOnRequest(context(db), { env: ON, now: NOW })
    expect(db.progress(USER)).toMatchObject({ current_streak: 3, last_active_date: '2026-10-02' })
    await closeOpenDaysOnRequest(context(db), { env: ON, now: NOW })
    expect(db.progress(USER)).toMatchObject({
      current_streak: 5,
      xp_total: 75,
      last_active_date: '2026-10-04',
    })
  })

  it('a failure in the sweep is logged without personal data and does not throw', async () => {
    const db = account()
    db.failWith = (operation) =>
      operation.kind === 'rpc' ? `user ${USER} patient@example.com failed` : null
    const error = vi.spyOn(console, 'error').mockImplementation(() => undefined)

    await expect(
      closeOpenDaysOnRequest(context(db), { env: ON, now: NOW }),
    ).resolves.toBeUndefined()

    expect(error).toHaveBeenCalledTimes(1)
    expect(error).toHaveBeenCalledWith('[mobile-api] day_close_failed', {
      request_id: 'request-day-close',
      scope: 'mobile_api_v1',
      error_name: 'Error',
    })
    const logged = JSON.stringify(error.mock.calls)
    expect(logged).not.toContain(USER)
    expect(logged).not.toContain('example.com')
  })

  it('a failed account lookup is logged the same way and does not throw', async () => {
    const db = account()
    db.failWith = (operation) => (operation.target === 'users' ? 'relation missing' : null)
    const error = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    await expect(
      closeOpenDaysOnRequest(context(db), { env: ON, now: NOW }),
    ).resolves.toBeUndefined()
    expect(error).toHaveBeenCalledTimes(1)
    expect(db.writes).toEqual([])
  })
})

describe('where the hook is called from', () => {
  const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..')

  function sourceFiles(root: string): string[] {
    return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
      const path = resolve(root, entry.name)
      if (entry.isDirectory()) return sourceFiles(path)
      return /\.(?:ts|tsx)$/.test(entry.name) ? [path] : []
    })
  }

  it('only the read handlers of GET /today and GET /progress import it', () => {
    const importers = sourceFiles(sourceRoot)
      .filter((path) => !/\.test\.tsx?$/.test(path))
      .filter((path) => readFileSync(path, 'utf8').includes('day-close-on-request'))
      .map((path) => relative(sourceRoot, path).split(sep).join('/'))
      .sort()
    expect(importers).toEqual([
      'app/api/mobile/v1/progress/route.ts',
      'app/api/mobile/v1/today/route.ts',
    ])
  })

  it('the route wrapper shared by the 48 routes does not know it', () => {
    const wrapper = readFileSync(resolve(sourceRoot, 'lib/mobile-api/route.ts'), 'utf8')
    expect(wrapper).not.toContain('closeOpenDaysOnRequest')
    expect(wrapper).not.toContain('closePastOpenDays')
  })
})
