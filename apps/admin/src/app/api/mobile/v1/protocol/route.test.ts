/**
 * GET /api/mobile/v1/protocol (docs/mobile/api-v1.md, "Objetivo atual";
 * docs/CALCULO-MPP.md §10l): the protocol the profile holds, the targets of
 * the Today screen and the entry message of that protocol. Read only.
 *
 * Two layers. The handler with its two reads replaced (what it asks for and
 * what it does with the answers), and the real handler behind the real route
 * wrapper, the real entitlement gate and the real reads (`loadProfile`,
 * `loadToday`) over an in-memory database that answers reads and FAILS on any
 * insert, update, upsert, delete or write rpc.
 *
 * NUMBERS — no patient. The account is the synthetic man of
 * docs/CALCULO-MPP.md §2c: 81 kg, 180 cm, 44 years old, "moderado", no body
 * fat. Mifflin: 10 × 81 + 6,25 × 180 − 5 × 44 + 5 = 1720. Recomposição with
 * the 500 deficit: 1720 × 1,2 − 500 = 1564. Manutenção: 1720 × 1,55 = 2666.
 * Ganho de massa: 2666 × 1,05 = 2799. Protein in recomposição: 81 × 1,5 =
 * 121,5 g.
 */
import { clearCalcConfigCache } from '@mpp/agent'
import { protocolWelcomeMessage } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from '@/lib/mobile-api/auth'
import { authorizeMobileEntitlement } from '@/lib/mobile-api/entitlement-service'
import { MobileApiError } from '@/lib/mobile-api/http'
import { loadToday } from '@/lib/mobile-api/read-model'
import {
  createMobileRoute,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import { handleProtocolGet, type ProtocolRouteDependencies } from './handler'

const USER_ID = '00000000-0000-4000-8000-000000000971'
const AUTH_USER_ID = '00000000-0000-4000-8000-000000000972'
const REQUEST_ID = 'request-protocol-971'
const ENDPOINT = 'https://bodyflow.test/api/mobile/v1/protocol'
const NAME = 'Synthetic User'
/** 09:00 of 2026-10-07 in America/Sao_Paulo. */
const NOW = new Date('2026-10-07T12:00:00.000Z')
const TODAY = '2026-10-07'

function auth(patch: Partial<MobileAuthContext['patient']> = {}): MobileAuthContext {
  return {
    accessToken: 'redacted-test-token',
    authUserId: AUTH_USER_ID,
    userId: USER_ID,
    identity: {
      id: AUTH_USER_ID,
      email: 'synthetic@example.invalid',
      emailConfirmedAt: '2026-10-01T12:00:00.000Z',
    },
    patient: {
      id: USER_ID,
      authUserId: AUTH_USER_ID,
      email: 'synthetic@example.invalid',
      name: NAME,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
      ...patch,
    },
  }
}

// ── The handler, with its two reads replaced ────────────────────────────────

function context(patch: Partial<MobileAuthContext['patient']> = {}): MobileRouteContext {
  return {
    request: new Request(ENDPOINT),
    requestId: REQUEST_ID,
    supabase: { kind: 'service-client' } as unknown as ServiceClient,
    auth: auth(patch),
  }
}

function reads(
  profile: Record<string, unknown> | null,
  targets = { calories_kcal: 1564 as number | null, protein_g: 121.5 as number | null },
) {
  return {
    loadProfile: vi.fn(async () => profile),
    loadToday: vi.fn(async () => ({ protocol: 'manutencao', targets })),
  } as unknown as ProtocolRouteDependencies & {
    loadProfile: ReturnType<typeof vi.fn>
    loadToday: ReturnType<typeof vi.fn>
  }
}

describe('GET /protocol — the handler', () => {
  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ] as const)('reads the profile and the daily state of the authenticated user and answers %s', async (protocol) => {
    const dependencies = reads({ current_protocol: protocol, onboarding_completed: true })
    const requestContext = context()

    const response = await handleProtocolGet(requestContext, dependencies)

    expect(dependencies.loadProfile).toHaveBeenCalledWith(requestContext.supabase, USER_ID)
    expect(dependencies.loadToday).toHaveBeenCalledWith(
      requestContext.supabase,
      USER_ID,
      'America/Sao_Paulo',
    )
    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
    expect(await response.json()).toEqual({
      data: {
        current_protocol: protocol,
        targets: { calories: 1564, protein_g: 121.5 },
        welcome: { protocol, paragraphs: protocolWelcomeMessage(protocol, NAME, 'pt-BR') },
      },
      meta: { api_version: 'v1', request_id: REQUEST_ID },
    })
  })

  it('the protocol is the one the PROFILE holds, not the one of the day row', async () => {
    // `reads()` hands over a daily state whose `protocol` is manutenção.
    const response = await handleProtocolGet(context(), reads({ current_protocol: 'ganho_massa' }))

    const { data } = await response.json()
    expect(data.current_protocol).toBe('ganho_massa')
    expect(data.welcome.protocol).toBe('ganho_massa')
  })

  it('an account in en-US gets the entry message in English, with its name', async () => {
    const response = await handleProtocolGet(
      context({ locale: 'en-US' }),
      reads({ current_protocol: 'recomposicao' }),
    )

    const { data } = await response.json()
    expect(data.welcome.paragraphs).toEqual(protocolWelcomeMessage('recomposicao', NAME, 'en-US'))
    expect(data.welcome.paragraphs[0]).toMatch(
      /^Synthetic User, as of now you are officially entering the body recomposition phase\./,
    )
  })

  it('an account with no locale yet reads Portuguese, and with no timezone the day is the UTC one', async () => {
    const dependencies = reads({ current_protocol: 'manutencao' })
    const requestContext = context({ locale: null, timezone: null })

    const response = await handleProtocolGet(requestContext, dependencies)

    expect(dependencies.loadToday).toHaveBeenCalledWith(requestContext.supabase, USER_ID, 'UTC')
    expect((await response.json()).data.welcome.paragraphs).toEqual(
      protocolWelcomeMessage('manutencao', NAME, 'pt-BR'),
    )
  })

  it('an account with no registered name gets the message without the vocative', async () => {
    const response = await handleProtocolGet(
      context({ name: null }),
      reads({ current_protocol: 'recomposicao' }),
    )

    const { data } = await response.json()
    expect(data.welcome.paragraphs).toEqual(protocolWelcomeMessage('recomposicao', null, 'pt-BR'))
    expect(data.welcome.paragraphs[0]).toMatch(/^A partir de agora você entra oficialmente /)
  })

  it.each([
    'fr-FR',
    'es',
    'en',
    'pt-PT',
  ])('a locale the texts do not exist in (%s) → 409 protocol_locale_unsupported, before any read', async (locale) => {
    const dependencies = reads({ current_protocol: 'recomposicao' })

    await expect(handleProtocolGet(context({ locale }), dependencies)).rejects.toMatchObject({
      status: 409,
      code: 'protocol_locale_unsupported',
    })
    expect(dependencies.loadProfile).not.toHaveBeenCalled()
    expect(dependencies.loadToday).not.toHaveBeenCalled()
  })

  it.each([
    ['no profile row', null],
    [
      'sign-up not completed: a profile with no protocol',
      { current_protocol: null, onboarding_completed: false },
    ],
  ])('%s → 200 with no protocol and no entry message', async (_case, profile) => {
    const response = await handleProtocolGet(
      context(),
      reads(profile, { calories_kcal: null, protein_g: null }),
    )

    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      current_protocol: null,
      targets: { calories: null, protein_g: null },
      welcome: null,
    })
  })

  it('a daily state that cannot be read fails the request: no protocol is answered without its targets', async () => {
    const dependencies = reads({ current_protocol: 'recomposicao' })
    dependencies.loadToday.mockRejectedValue(
      new MobileApiError(500, 'data_access_failed', 'Daily state lookup failed'),
    )

    await expect(handleProtocolGet(context(), dependencies)).rejects.toMatchObject({
      status: 500,
      code: 'data_access_failed',
    })
  })
})

// ── The real reads over a read-only database ────────────────────────────────

type Row = Record<string, unknown>

const ACTIVE_ACCESS = {
  entitlement: 'bodyflow_full',
  has_active_access: true,
  status: 'active',
  source: 'manual',
  plan: 'trial',
  access_expires_at: '2026-11-06T00:00:00.000Z',
  grace_expires_at: null,
  cancel_at_period_end: false,
  reason: 'valid_entitlement',
  decision_at: NOW.toISOString(),
}

const NO_ACCESS = {
  ...ACTIVE_ACCESS,
  has_active_access: false,
  status: 'expired',
  source: null,
  plan: null,
  access_expires_at: null,
  reason: 'no_entitlement',
}

/** Read functions the routes of the app call through `rpc`. Anything else is a write. */
const READ_RPCS = new Set(['list_mobile_routine_items', 'resolve_user_entitlement'])

/**
 * Answers selects from the rows it was given and the two read rpcs. Any
 * insert, update, upsert, delete or other rpc is recorded and throws.
 */
class ReadOnlyDb {
  readonly reads: string[] = []
  readonly writes: string[] = []
  profile: Row | null = null
  todayRow: Row | null = null
  access: Row = ACTIVE_ACCESS

  readonly client = {
    from: (table: string) => this.query(table),
    rpc: async (name: string, params: Row) => {
      if (!READ_RPCS.has(name)) return this.refused(`rpc:${name}`)
      this.reads.push(`rpc:${name}`)
      if (name === 'resolve_user_entitlement') return { data: this.access, error: null }
      expect(params.p_user_id).toBe(USER_ID)
      return { data: { local_date: TODAY, items: [] }, error: null }
    },
  } as unknown as ServiceClient

  private refused(operation: string): never {
    this.writes.push(operation)
    throw new Error(`GET /protocol touched the database: ${operation}`)
  }

  private single(table: string): Row | null {
    if (table === 'user_profiles') return this.profile
    if (table === 'daily_snapshots') return this.todayRow
    return null
  }

  private query(table: string) {
    this.reads.push(`select:${table}`)
    const chain = ['select', 'eq', 'gt', 'gte', 'lt', 'lte', 'like', 'in', 'not', 'or', 'filter']
    const builder: Record<string, unknown> = {
      maybeSingle: async () => ({ data: this.single(table), error: null }),
      // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are intentionally thenable.
      then: (
        onFulfilled: (value: { data: Row[]; error: null }) => unknown,
        onRejected?: (reason: unknown) => unknown,
      ) => Promise.resolve({ data: [], error: null }).then(onFulfilled, onRejected),
    }
    for (const method of [...chain, 'order', 'limit']) builder[method] = () => builder
    for (const method of ['insert', 'update', 'upsert', 'delete']) {
      builder[method] = () => this.refused(`${method}:${table}`)
    }
    return builder
  }
}

function profileRow(patch: Row = {}): Row {
  return {
    sex: 'masculino',
    birth_date: '1982-01-01',
    height_cm: 180,
    weight_kg: 81,
    body_fat_percent: null,
    activity_level: 'moderado',
    training_frequency: 3,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    wake_time: '07:00:00',
    bedtime: '23:00:00',
    current_protocol: 'recomposicao',
    goal_type: null,
    goal_value: null,
    deficit_level: 500,
    food_organization: 'sim',
    onboarding_completed: true,
    onboarding_step: 6,
    updated_at: '2026-10-01T12:00:00.000Z',
    weight_measured_at: null,
    weight_instant_source: null,
    ...patch,
  }
}

/** Today's row after the first meal: the targets were stored with it. */
function todayRow(caloriesTarget: number, proteinTarget: number): Row {
  return {
    id: '00000000-0000-4000-8000-0000000009d1',
    calories_consumed: 600,
    calories_target: caloriesTarget,
    protein_g: 40,
    protein_target: proteinTarget,
    carbs_g: 70,
    fat_g: 15,
    exercise_calories: 0,
    water_consumed_ml: 0,
    current_protocol: null,
    day_closed: false,
    day_status: 'pending_close',
    updated_at: '2026-10-07T11:00:00.000Z',
    meal_logs: [],
    workout_logs: [],
  }
}

/** The route as route.ts builds it, with the authentication stubbed out. */
function route(db: ReadOnlyDb, patient: Partial<MobileAuthContext['patient']> = {}) {
  const runtime: MobileRouteRuntime = {
    authenticate: async () => auth(patient),
    authorizeEntitlement: (authenticated, request, supabase) =>
      authorizeMobileEntitlement(supabase, authenticated.userId, new URL(request.url).pathname),
    createServiceClient: () => db.client,
    createRequestId: () => REQUEST_ID,
  }
  return createMobileRoute(handleProtocolGet, runtime)
}

async function get(db: ReadOnlyDb, patient?: Partial<MobileAuthContext['patient']>) {
  const response = await route(db, patient)(new Request(ENDPOINT))
  return { response, json: await response.json() }
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
})

afterEach(() => {
  vi.useRealTimers()
  clearCalcConfigCache()
  vi.restoreAllMocks()
})

describe('GET /protocol — the real reads: the targets are the ones of the Today screen', () => {
  it('recomposição with no row for today yet: the target calculated from the profile — 1564 kcal, 121,5 g', async () => {
    const db = new ReadOnlyDb()
    db.profile = profileRow()

    const { response, json } = await get(db)

    expect(response.status).toBe(200)
    expect(json).toEqual({
      data: {
        current_protocol: 'recomposicao',
        targets: { calories: 1564, protein_g: 121.5 },
        welcome: {
          protocol: 'recomposicao',
          paragraphs: protocolWelcomeMessage('recomposicao', NAME, 'pt-BR'),
        },
      },
      meta: { api_version: 'v1', request_id: REQUEST_ID },
    })
    const today = await loadToday(db.client, USER_ID, 'America/Sao_Paulo')
    expect(today.targets).toMatchObject({
      calories_kcal: 1564,
      protein_g: 121.5,
      source: 'profile_calculation',
    })
    expect(db.writes).toEqual([])
  })

  it.each([
    ['manutencao', null, 2666],
    ['ganho_massa', null, 2799],
  ] as const)('%s: the target of that protocol, and its entry message', async (protocol, deficit, kcal) => {
    const db = new ReadOnlyDb()
    db.profile = profileRow({ current_protocol: protocol, deficit_level: deficit })

    const { json } = await get(db)

    const today = await loadToday(db.client, USER_ID, 'America/Sao_Paulo')
    expect(json.data.current_protocol).toBe(protocol)
    expect(json.data.targets.calories).toBe(kcal)
    expect(json.data.targets).toEqual({
      calories: today.targets.calories_kcal,
      protein_g: today.targets.protein_g,
    })
    expect(json.data.welcome).toEqual({
      protocol,
      paragraphs: protocolWelcomeMessage(protocol, NAME, 'pt-BR'),
    })
  })

  it('today already has a row: the target STORED on it wins over the calculation, as on the Today screen', async () => {
    const db = new ReadOnlyDb()
    // The weight changed after the first meal of the day: the profile now
    // calculates 1564, the day keeps the 1576 it was opened with.
    db.profile = profileRow()
    db.todayRow = todayRow(1576, 120)

    const { json } = await get(db)

    expect(json.data.targets).toEqual({ calories: 1576, protein_g: 120 })
    const today = await loadToday(db.client, USER_ID, 'America/Sao_Paulo')
    expect(today.targets).toMatchObject({
      calories_kcal: 1576,
      protein_g: 120,
      source: 'daily_snapshot',
    })
  })

  it('an account in en-US: the same numbers, the message in English', async () => {
    const db = new ReadOnlyDb()
    db.profile = profileRow({ current_protocol: 'ganho_massa', deficit_level: null })

    const { json } = await get(db, { locale: 'en-US' })

    expect(json.data.targets.calories).toBe(2799)
    expect(json.data.welcome.paragraphs).toEqual(
      protocolWelcomeMessage('ganho_massa', NAME, 'en-US'),
    )
  })

  it('writes nothing: selects and the two read rpcs only', async () => {
    const db = new ReadOnlyDb()
    db.profile = profileRow()
    db.todayRow = todayRow(1576, 120)

    await get(db)

    expect(db.writes).toEqual([])
    expect(new Set(db.reads.filter((read) => read.startsWith('rpc:')))).toEqual(
      new Set(['rpc:resolve_user_entitlement', 'rpc:list_mobile_routine_items']),
    )
    expect(db.reads).toContain('select:user_profiles')
    expect(db.reads).toContain('select:daily_snapshots')
    expect(db.reads).toContain('select:global_config')
  })
})

describe('GET /protocol — an account without a protocol', () => {
  it('no profile row: 200, no protocol, no entry message, no targets', async () => {
    const db = new ReadOnlyDb()

    const { response, json } = await get(db)

    expect(response.status).toBe(200)
    expect(json.data).toEqual({
      current_protocol: null,
      targets: { calories: null, protein_g: null },
      welcome: null,
    })
    expect(db.writes).toEqual([])
  })

  it('sign-up not completed, body data already in the profile: no protocol and no entry message; the targets are whatever GET /today answers', async () => {
    const db = new ReadOnlyDb()
    db.profile = profileRow({
      current_protocol: null,
      deficit_level: null,
      onboarding_completed: false,
      onboarding_step: 3,
    })

    const { response, json } = await get(db)

    const today = await loadToday(db.client, USER_ID, 'America/Sao_Paulo')
    expect(response.status).toBe(200)
    expect(json.data.current_protocol).toBeNull()
    expect(json.data.welcome).toBeNull()
    expect(today.protocol).toBeNull()
    expect(json.data.targets).toEqual({
      calories: today.targets.calories_kcal,
      protein_g: today.targets.protein_g,
    })
  })

  it('the route does not look at the completion of the sign-up: it reports what the profile holds', async () => {
    const db = new ReadOnlyDb()
    db.profile = profileRow({ onboarding_completed: false, onboarding_step: 3 })

    const { json } = await get(db)

    expect(json.data.current_protocol).toBe('recomposicao')
    expect(json.data.welcome.protocol).toBe('recomposicao')
  })
})

describe('GET /protocol — access', () => {
  it('needs an active access, like GET /today: without one → 402 and nothing is read', async () => {
    const db = new ReadOnlyDb()
    db.profile = profileRow()
    db.access = NO_ACCESS

    const { response, json } = await get(db)

    expect(response.status).toBe(402)
    expect(json.error.code).toBe('subscription_required')
    expect(json).not.toHaveProperty('data')
    expect(db.reads).toEqual(['rpc:resolve_user_entitlement'])
  })

  it('an unsupported locale → 409 through the wrapper, with no profile or daily-state read', async () => {
    const db = new ReadOnlyDb()
    db.profile = profileRow()

    const { response, json } = await get(db, { locale: 'fr-FR' })

    expect(response.status).toBe(409)
    expect(json.error).toMatchObject({
      code: 'protocol_locale_unsupported',
      request_id: REQUEST_ID,
    })
    expect(db.reads).toEqual(['rpc:resolve_user_entitlement'])
  })
})

describe('the route file', () => {
  it('exports GET and the runtime, and nothing else: there is no way to change the objective here', async () => {
    const module = await import('./route')
    expect(Object.keys(module).sort()).toEqual(['GET', 'runtime'])
    expect(module.runtime).toBe('nodejs')
  })
})
