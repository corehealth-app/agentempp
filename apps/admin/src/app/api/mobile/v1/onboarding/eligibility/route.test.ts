/**
 * POST /api/mobile/v1/onboarding/eligibility (docs/mobile/api-v1.md,
 * "Conferência de objetivo no cadastro"; docs/CALCULO-MPP.md §10l).
 *
 * The real handler behind the real route wrapper (error mapping included), the
 * real entitlement gate, the real calc-config loader and the real rule
 * (`decideSignupEligibility`). Only the authentication is a pass-through and
 * the database is a double that answers ONE read — the `calc.*` rows — and
 * fails on any insert, update, upsert, delete or rpc: the route must write
 * nothing, keep no idempotency record and query no entitlement.
 *
 * NUMBERS — the client's cuts and their neighbours (19 / 20 / 27 / 28 %, BMI
 * 25.0, 2 and 3 sessions), the same as the golden of the rule. No patient.
 * The three `calc.*` rows are the ones of staging as recorded on 2026-10-04
 * (audit-10-04-goal-ladder-floors.test.ts); no database was read.
 */
import { clearCalcConfigCache } from '@mpp/agent'
import {
  gainBlockedAboveRangeMessage,
  gainUnavailableBodyFatReason,
  gainUnavailableTrainingReason,
  signupAssignedNotice,
} from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from '@/lib/mobile-api/auth'
import { authorizeMobileEntitlement } from '@/lib/mobile-api/entitlement-service'
import { createMobileRoute, type MobileRouteRuntime } from '@/lib/mobile-api/route'
import { handleOnboardingEligibilityPost } from './handler'

const USER_ID = '00000000-0000-4000-8000-000000000961'
const AUTH_USER_ID = '00000000-0000-4000-8000-000000000962'
const REQUEST_ID = 'request-eligibility-961'
const ENDPOINT = 'https://bodyflow.test/api/mobile/v1/onboarding/eligibility'

type ConfigRow = { key: string; value: unknown }

const STAGING_CALC_ROWS: ConfigRow[] = [
  {
    key: 'calc.bf_limits',
    value: { feminino: { gain: 27, recomp: 28 }, masculino: { gain: 19, recomp: 20 } },
  },
  { key: 'calc.imc_limit_recomp', value: 25 },
  { key: 'calc.training_min', value: 3 },
]

/**
 * Answers the one statement of the calc-config loader. Every other table and
 * every write or rpc is recorded and throws.
 */
class ReadOnlyConfigDb {
  readonly reads: string[] = []
  readonly writes: string[] = []
  rows: ConfigRow[] = STAGING_CALC_ROWS
  error: { message: string } | null = null

  readonly client = {
    from: (table: string) => {
      if (table !== 'global_config') return this.refused(`from:${table}`)
      return {
        select: (columns: string) => ({
          like: async (column: string, pattern: string) => {
            this.reads.push(`select:${table}:${columns}:${column} like ${pattern}`)
            return this.error ? { data: null, error: this.error } : { data: this.rows, error: null }
          },
        }),
        insert: () => this.refused(`insert:${table}`),
        update: () => this.refused(`update:${table}`),
        upsert: () => this.refused(`upsert:${table}`),
        delete: () => this.refused(`delete:${table}`),
      }
    },
    rpc: (name: string) => this.refused(`rpc:${name}`),
  } as unknown as ServiceClient

  private refused(operation: string): never {
    this.writes.push(operation)
    throw new Error(`the eligibility check touched the database: ${operation}`)
  }
}

const AUTH: MobileAuthContext = {
  accessToken: 'redacted-test-token',
  authUserId: AUTH_USER_ID,
  userId: USER_ID,
  identity: {
    id: AUTH_USER_ID,
    email: 'synthetic@example.invalid',
    emailConfirmedAt: '2026-10-07T12:00:00.000Z',
  },
  patient: {
    id: USER_ID,
    authUserId: AUTH_USER_ID,
    email: 'synthetic@example.invalid',
    name: null,
    locale: null,
    timezone: null,
    country: null,
    countryConfirmed: false,
    status: 'active',
  },
}

/** The route as route.ts builds it, with the authentication stubbed out. */
function route(db: ReadOnlyConfigDb) {
  const runtime: MobileRouteRuntime = {
    authenticate: async () => AUTH,
    authorizeEntitlement: (auth, request, supabase) =>
      authorizeMobileEntitlement(supabase, auth.userId, new URL(request.url).pathname),
    createServiceClient: () => db.client,
    createRequestId: () => REQUEST_ID,
  }
  return createMobileRoute(handleOnboardingEligibilityPost, runtime)
}

function request(body: unknown, headers: Record<string, string | null> = {}): Request {
  const merged = new Headers({
    'content-type': 'application/json',
    'idempotency-key': 'eligibility-key-0001',
  })
  for (const [name, value] of Object.entries(headers)) {
    if (value === null) merged.delete(name)
    else merged.set(name, value)
  }
  return new Request(ENDPOINT, { method: 'POST', headers: merged, body: JSON.stringify(body) })
}

/** Homem, 180 cm, 80 kg (IMC 24,69), sem gordura informada, musculação 3x. */
function man(patch: Record<string, unknown> = {}) {
  return {
    locale: 'pt-BR',
    sex: 'masculino',
    height_cm: 180,
    weight_kg: 80,
    training_frequency: 3,
    ...patch,
  }
}

/** Mulher, 165 cm, 62 kg (IMC 22,77), sem gordura informada, musculação 3x. */
function woman(patch: Record<string, unknown> = {}) {
  return {
    locale: 'pt-BR',
    sex: 'feminino',
    height_cm: 165,
    weight_kg: 62,
    training_frequency: 3,
    ...patch,
  }
}

/** The envelope of the route: `data` on success, `error` otherwise. */
interface EligibilityJson {
  data: {
    decision: string
    basis: string
    objective: string | null
    notice: string[]
    options: Array<{ objective: string; status: string; reasons: string[]; message: string[] }>
  }
  error: { code: string; message: string; request_id: string; details?: unknown }
}

async function check(db: ReadOnlyConfigDb, body: unknown, headers?: Record<string, string | null>) {
  const response = await route(db)(request(body, headers))
  return { response, json: (await response.json()) as EligibilityJson }
}

const AVAILABLE = { status: 'available', reasons: [], message: [] }
const THREE = [
  { objective: 'recomposicao', ...AVAILABLE },
  { objective: 'ganho_massa', ...AVAILABLE },
  { objective: 'manutencao', ...AVAILABLE },
]
const CONFIG_READ = 'select:global_config:key, value:key like calc.%'

function logs() {
  return (['log', 'info', 'warn', 'error', 'debug'] as const).map((level) =>
    vi.spyOn(console, level).mockImplementation(() => undefined),
  )
}

beforeEach(() => clearCalcConfigCache())

afterEach(() => {
  clearCalcConfigCache()
  vi.restoreAllMocks()
})

describe('POST /onboarding/eligibility — the client’s numbers through the real rule', () => {
  it('man with 20.0% of body fat → assigned: recomposição, the notice, the blocking phrase by body fat', async () => {
    const db = new ReadOnlyConfigDb()

    const { response, json } = await check(db, man({ body_fat_percent: 20 }))

    expect(response.status).toBe(200)
    expect(json).toEqual({
      data: {
        decision: 'assigned',
        basis: 'body_fat',
        objective: 'recomposicao',
        notice: signupAssignedNotice('pt-BR'),
        options: [
          { objective: 'recomposicao', ...AVAILABLE },
          {
            objective: 'ganho_massa',
            status: 'blocked',
            reasons: ['gain_composition'],
            message: gainBlockedAboveRangeMessage('BF', 'pt-BR'),
          },
          { objective: 'manutencao', status: 'not_offered', reasons: [], message: [] },
        ],
      },
      meta: { api_version: 'v1', request_id: REQUEST_ID },
    })
    expect(json.data.notice[0]).toContain('o seu protocolo é definido automaticamente')
    expect(json.data.options[1].message[0]).toContain('seu percentual de gordura atual coloca você')
    expect(db.reads).toEqual([CONFIG_READ])
    expect(db.writes).toEqual([])
  })

  it('woman with 28.0% → assigned', async () => {
    const { json } = await check(new ReadOnlyConfigDb(), woman({ body_fat_percent: 28 }))
    expect(json.data).toMatchObject({
      decision: 'assigned',
      basis: 'body_fat',
      objective: 'recomposicao',
    })
  })

  it('woman with 27.0% and 3 sessions → choice: the three objectives, no text', async () => {
    const { response, json } = await check(new ReadOnlyConfigDb(), woman({ body_fat_percent: 27 }))

    expect(response.status).toBe(200)
    expect(json.data).toEqual({
      decision: 'choice',
      basis: 'body_fat',
      objective: null,
      notice: null,
      options: THREE,
    })
  })

  it('no body fat, 64 kg / 160 cm (BMI 25.0) → assigned, and the phrase names the BMI', async () => {
    const { json } = await check(new ReadOnlyConfigDb(), woman({ height_cm: 160, weight_kg: 64 }))

    expect(json.data).toMatchObject({
      decision: 'assigned',
      basis: 'bmi',
      objective: 'recomposicao',
    })
    expect(json.data.options[1]).toEqual({
      objective: 'ganho_massa',
      status: 'blocked',
      reasons: ['gain_composition'],
      message: gainBlockedAboveRangeMessage('IMC', 'pt-BR'),
    })
    expect(json.data.options[1].message[0]).toContain('seu IMC atual coloca você')
    expect(json.data.options[2].status).toBe('not_offered')
  })

  it('man with 19.0% and 2 sessions → choice; ganho de massa blocked by training, with the minimum and what he informed', async () => {
    const { json } = await check(
      new ReadOnlyConfigDb(),
      man({ body_fat_percent: 19, training_frequency: 2 }),
    )

    expect(json.data).toEqual({
      decision: 'choice',
      basis: 'body_fat',
      objective: null,
      notice: null,
      options: [
        { objective: 'recomposicao', ...AVAILABLE },
        {
          objective: 'ganho_massa',
          status: 'blocked',
          reasons: ['gain_training'],
          message: gainUnavailableTrainingReason(3, 2, 'pt-BR'),
        },
        { objective: 'manutencao', ...AVAILABLE },
      ],
    })
    expect(json.data.options[1].message[0]).toContain('pelo menos 3 vezes por semana')
    expect(json.data.options[1].message[0]).toContain('Você informou 2 por semana.')
  })

  it('no body fat, 79.38 kg / 180 cm (BMI 24.5) and 3 sessions → choice: the three objectives', async () => {
    const { json } = await check(new ReadOnlyConfigDb(), man({ weight_kg: 79.38 }))

    expect(json.data).toEqual({
      decision: 'choice',
      basis: 'bmi',
      objective: null,
      notice: null,
      options: THREE,
    })
  })

  it('man with 19.5% → choice; ganho de massa blocked by composition, citing the cut of his sex (19), never the blocking phrase', async () => {
    const { json } = await check(new ReadOnlyConfigDb(), man({ body_fat_percent: 19.5 }))

    expect(json.data.decision).toBe('choice')
    expect(json.data.options[1]).toEqual({
      objective: 'ganho_massa',
      status: 'blocked',
      reasons: ['gain_composition'],
      message: gainUnavailableBodyFatReason(19, 'pt-BR'),
    })
    expect(json.data.options[1].message[0]).toContain('de até 19%')
    expect(json.data.options[2]).toEqual({ objective: 'manutencao', ...AVAILABLE })
  })

  it('woman with 27.5% → the cut of her sex (27)', async () => {
    const { json } = await check(new ReadOnlyConfigDb(), woman({ body_fat_percent: 27.5 }))
    expect(json.data.options[1].message).toEqual(gainUnavailableBodyFatReason(27, 'pt-BR'))
  })

  it('en-US → the same decisions, every text in English', async () => {
    const assigned = await check(
      new ReadOnlyConfigDb(),
      man({ locale: 'en-US', body_fat_percent: 20 }),
    )
    expect(assigned.json.data.notice).toEqual(signupAssignedNotice('en-US'))
    expect(assigned.json.data.notice[0]).toContain('your protocol is set automatically')
    expect(assigned.json.data.options[1].message).toEqual(
      gainBlockedAboveRangeMessage('BF', 'en-US'),
    )
    expect(assigned.json.data.options[1].message[0]).toContain(
      'your current body fat percentage places you',
    )

    clearCalcConfigCache()
    const choice = await check(
      new ReadOnlyConfigDb(),
      man({ locale: 'en-US', body_fat_percent: 19.5, training_frequency: 2 }),
    )
    expect(choice.json.data.options[1]).toEqual({
      objective: 'ganho_massa',
      status: 'blocked',
      reasons: ['gain_composition', 'gain_training'],
      message: [
        ...gainUnavailableBodyFatReason(19, 'en-US'),
        ...gainUnavailableTrainingReason(3, 2, 'en-US'),
      ],
    })
    expect(JSON.stringify([assigned.json.data, choice.json.data])).not.toMatch(
      /você|musculação|gordura|recomposição corporal/,
    )
  })

  it('the cuts are read from the config rows: with calc.training_min = 4, 3 sessions no longer do', async () => {
    const db = new ReadOnlyConfigDb()
    db.rows = STAGING_CALC_ROWS.map((row) =>
      row.key === 'calc.training_min' ? { key: row.key, value: 4 } : row,
    )

    const { json } = await check(db, man({ body_fat_percent: 19 }))

    expect(json.data.options[1]).toEqual({
      objective: 'ganho_massa',
      status: 'blocked',
      reasons: ['gain_training'],
      message: gainUnavailableTrainingReason(4, 3, 'pt-BR'),
    })
    expect(json.data.options[1].message[0]).toContain('pelo menos 4 vezes por semana')
  })
})

describe('POST /onboarding/eligibility — decided on the value the profile will store', () => {
  it('man with 19.995% (stored as 20.00) → assigned', async () => {
    const { json } = await check(new ReadOnlyConfigDb(), man({ body_fat_percent: 19.995 }))
    expect(json.data).toMatchObject({
      decision: 'assigned',
      basis: 'body_fat',
      objective: 'recomposicao',
    })
  })

  it('man with 19.994% (stored as 19.99) → choice, ganho de massa blocked by composition', async () => {
    const { json } = await check(new ReadOnlyConfigDb(), man({ body_fat_percent: 19.994 }))
    expect(json.data.decision).toBe('choice')
    expect(json.data.options[1].reasons).toEqual(['gain_composition'])
  })

  it('no body fat, 80.999 kg / 180 cm (stored as 81.00 kg, BMI 25.0) → assigned', async () => {
    const { json } = await check(new ReadOnlyConfigDb(), man({ weight_kg: 80.999 }))
    expect(json.data).toMatchObject({
      decision: 'assigned',
      basis: 'bmi',
      objective: 'recomposicao',
    })
  })

  it('no body fat, 80.994 kg / 180 cm (stored as 80.99 kg) → choice: the three objectives', async () => {
    const { json } = await check(new ReadOnlyConfigDb(), man({ weight_kg: 80.994 }))
    expect(json.data).toMatchObject({ decision: 'choice', basis: 'bmi', options: THREE })
  })
})

describe('POST /onboarding/eligibility — it writes nothing', () => {
  it('a run of requests: one config read (cached after it), no write, no rpc, nothing logged', async () => {
    const spies = logs()
    const db = new ReadOnlyConfigDb()
    const bodies = [
      man({ body_fat_percent: 20 }),
      woman({ body_fat_percent: 27 }),
      woman({ height_cm: 160, weight_kg: 64 }),
      man({ body_fat_percent: 19, training_frequency: 2 }),
      man({ weight_kg: 79.38 }),
      man({ locale: 'en-US', body_fat_percent: 19.995 }),
    ]

    for (const [index, body] of bodies.entries()) {
      const { response } = await check(db, body, { 'idempotency-key': `eligibility-run-${index}` })
      expect(response.status).toBe(200)
    }

    expect(db.reads).toEqual([CONFIG_READ])
    expect(db.writes).toEqual([])
    for (const spy of spies) expect(spy).not.toHaveBeenCalled()
  })

  it('keeps no idempotency record: the same key answers two different requests, and a repeat is computed again', async () => {
    const db = new ReadOnlyConfigDb()
    const key = { 'idempotency-key': 'eligibility-same-key-1' }

    const first = await check(db, man({ body_fat_percent: 20 }), key)
    const other = await check(db, woman({ body_fat_percent: 27 }), key)
    const repeat = await check(db, man({ body_fat_percent: 20 }), key)

    expect(first.json.data.decision).toBe('assigned')
    expect(other.response.status).toBe(200)
    expect(other.json.data.decision).toBe('choice')
    expect(repeat.json).toEqual(first.json)
    expect(repeat.response.headers.get('idempotency-replayed')).toBeNull()
    expect(db.writes).toEqual([])
  })

  it('requires no entitlement: the gate asks nothing of the database for this path', async () => {
    const db = new ReadOnlyConfigDb()

    const { response } = await check(db, man())

    // `resolve_user_entitlement` is an rpc: the double would have thrown.
    expect(response.status).toBe(200)
    expect(db.writes).toEqual([])
  })

  it('answers like every patient response: no-store, varied by the authorization', async () => {
    const { response } = await check(new ReadOnlyConfigDb(), man())

    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
    expect(response.headers.get('x-request-id')).toBe(REQUEST_ID)
  })

  it('the response carries no body value of the request', async () => {
    const { json } = await check(
      new ReadOnlyConfigDb(),
      man({ height_cm: 181.37, weight_kg: 77.31, body_fat_percent: 19.37 }),
    )

    expect(Object.keys(json.data).sort()).toEqual([
      'basis',
      'decision',
      'notice',
      'objective',
      'options',
    ])
    const serialized = JSON.stringify(json)
    for (const value of ['181.37', '77.31', '19.37', '181,37', '77,31', '19,37']) {
      expect(serialized).not.toContain(value)
    }
  })
})

describe('POST /onboarding/eligibility — what it refuses', () => {
  it.each([
    ['an extra key', man({ objective: 'ganho_massa' }), 'objective'],
    ['a name', man({ name: 'Synthetic User' }), 'name'],
    ['a caller-owned identity', man({ user_id: USER_ID }), 'user_id'],
  ])('%s → 422 validation_failed, before any database access', async (_case, body, key) => {
    const spies = logs()
    const db = new ReadOnlyConfigDb()

    const { response, json } = await check(db, body)

    expect(response.status).toBe(422)
    expect(json.error).toMatchObject({ code: 'validation_failed', request_id: REQUEST_ID })
    expect(JSON.stringify(json.error.details)).toContain(key)
    expect(json).not.toHaveProperty('data')
    expect(db.reads).toEqual([])
    expect(db.writes).toEqual([])
    for (const spy of spies) expect(spy).not.toHaveBeenCalled()
  })

  it.each([
    ['height below the sign-up range', man({ height_cm: 99.99 })],
    ['weight above the sign-up range', man({ weight_kg: 300.01 })],
    ['body fat below the sign-up range', man({ body_fat_percent: 2.99 })],
    ['body fat sent as null', man({ body_fat_percent: null })],
    ['fractional sessions', man({ training_frequency: 2.5 })],
    ['a language the sign-up does not have', man({ locale: 'es-ES' })],
    ['no sex', { locale: 'pt-BR', height_cm: 180, weight_kg: 80, training_frequency: 3 }],
  ])('%s → 422, nothing decided', async (_case, body) => {
    const db = new ReadOnlyConfigDb()

    const { response, json } = await check(db, body)

    expect(response.status).toBe(422)
    expect(json.error.code).toBe('validation_failed')
    expect(db.reads).toEqual([])
  })

  it('no Idempotency-Key → 400 missing_idempotency_key, as on every POST', async () => {
    const db = new ReadOnlyConfigDb()

    const { response, json } = await check(db, man(), { 'idempotency-key': null })

    expect(response.status).toBe(400)
    expect(json.error.code).toBe('missing_idempotency_key')
    expect(db.reads).toEqual([])
    expect(db.writes).toEqual([])
  })

  it('a malformed Idempotency-Key → 400 invalid_idempotency_key', async () => {
    const { response, json } = await check(new ReadOnlyConfigDb(), man(), {
      'idempotency-key': 'short',
    })

    expect(response.status).toBe(400)
    expect(json.error.code).toBe('invalid_idempotency_key')
  })

  it('a body that is not JSON → 415, nothing read', async () => {
    const db = new ReadOnlyConfigDb()

    const { response, json } = await check(db, man(), { 'content-type': 'text/plain' })

    expect(response.status).toBe(415)
    expect(json.error.code).toBe('unsupported_media_type')
    expect(db.reads).toEqual([])
  })

  it('the calc config cannot be read → 500 data_access_failed: no decision on the code defaults, no detail, nothing logged', async () => {
    const spies = logs()
    const db = new ReadOnlyConfigDb()
    db.error = { message: 'connection reset by peer at 10.0.0.7' }

    const { response, json } = await check(db, man({ body_fat_percent: 20 }))

    expect(response.status).toBe(500)
    expect(json).toEqual({
      error: {
        code: 'data_access_failed',
        message: 'Calculation config lookup failed',
        request_id: REQUEST_ID,
      },
    })
    expect(db.writes).toEqual([])
    for (const spy of spies) expect(spy).not.toHaveBeenCalled()
  })
})

describe('the route file', () => {
  it('exports POST and the runtime, and nothing else', async () => {
    const module = await import('./route')
    expect(Object.keys(module).sort()).toEqual(['POST', 'runtime'])
    expect(module.runtime).toBe('nodejs')
  })
})
