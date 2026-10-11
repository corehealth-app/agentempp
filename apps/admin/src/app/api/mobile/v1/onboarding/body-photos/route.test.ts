/**
 * The routes of the body photos of the sign-up WITH THE SWITCH OFF — what the
 * released builds 1.0 (3) and 1.0 (4), which call none of them, and any
 * client meet on a server that carries the code (docs/mobile/api-v1.md,
 * "Fotos do corpo no cadastro").
 *
 *   GET    /api/mobile/v1/onboarding/body-photos                200 "not available"
 *   POST   /api/mobile/v1/onboarding/body-photos                404 body_photos_unavailable
 *   POST   /api/mobile/v1/onboarding/body-photos/consent        404 body_photos_unavailable
 *   POST   /api/mobile/v1/onboarding/body-photos/:id/complete   404 body_photos_unavailable
 *   DELETE /api/mobile/v1/onboarding/body-photos                200 in known staging; other targets 404
 *
 * WHAT RUNS. The exported route functions of the three route files, with the
 * real route wrapper (authentication and the access gate), the real handlers
 * and the real idempotency ledger code. Replaced: the database client factory
 * (an in-memory database that throws on any query nobody declared and writes
 * every call down) and the queue client (it records what is sent). No
 * database, no storage, no network.
 *
 * The switch being born off is a decisão do orquestrador, anunciada ao dono
 * em 2026-10-10/11, que pode riscar qualquer uma.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV } from '@/lib/mobile-api/signup-body-photo-switch'
import {
  AUTHENTICATION,
  SignupBodyPhotoMemoryDb,
} from '@/lib/mobile-api/testing/signup-body-photo-memory-db'
import { POST as COMPLETE } from './[id]/complete/route'
import { POST as CONSENT } from './consent/route'
import { DELETE, GET, POST } from './route'

const world = vi.hoisted(() => ({ db: undefined as unknown, queue: [] as unknown[] }))

vi.mock('@/lib/supabase/server', () => ({
  createServiceClient: () => (world.db as SignupBodyPhotoMemoryDb).client,
  createPatientBearerClient: (token: string) =>
    (world.db as SignupBodyPhotoMemoryDb).bearerClient(token),
}))
vi.mock('@mpp/inngest-functions', () => ({
  inngest: {
    send: async (event: unknown) => {
      world.queue.push(event)
    },
  },
}))

const ACCOUNT = '00000000-0000-4000-8000-000000000301'
const AUTH_USER = '00000000-0000-4000-8000-000000000302'
const PHOTO = '00000000-0000-4000-8000-000000000401'
const TOKEN = 'token-of-the-account'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
const PRODUCTION_REF = 'xuxehkhdvjivitduarvb'
const BASE = 'https://bodyflow.test/api/mobile/v1/onboarding/body-photos'

/** What a server whose photos are off answers to GET. */
const NOT_AVAILABLE = {
  available: false,
  unavailable_reason: 'disabled',
  consent: null,
  minimum_age: 18,
  poses: [
    { pose: 'front', photo: null },
    { pose: 'side', photo: null },
    { pose: 'back', photo: null },
  ],
  estimate: null,
  remaining_uploads: 0,
}

interface Call {
  method: 'GET' | 'POST' | 'DELETE'
  path?: string
  body?: unknown
  key?: string | null
  token?: string | null
}

function request({ method, path = '', body, key, token = TOKEN }: Call): Request {
  const headers: Record<string, string> = {}
  if (token) headers.authorization = `Bearer ${token}`
  if (key) headers['idempotency-key'] = key
  if (body !== undefined) headers['content-type'] = 'application/json'
  return new Request(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

const VALID_CONSENT = {
  version: '2026-10-11.1',
  body_hash: 'a'.repeat(64),
  birth_date: '1990-05-20',
}
const VALID_PHOTO = { pose: 'front', mime_type: 'image/jpeg', size_bytes: 480_000 }

/** The five calls, each as a complete and valid request of an authenticated account. */
const CALLS = {
  state: (overrides: Partial<Call> = {}) => GET(request({ method: 'GET', ...overrides })),
  consent: (overrides: Partial<Call> = {}) =>
    CONSENT(
      request({
        method: 'POST',
        path: '/consent',
        body: VALID_CONSENT,
        key: 'body-photo-consent-0001',
        ...overrides,
      }),
    ),
  create: (overrides: Partial<Call> = {}) =>
    POST(
      request({ method: 'POST', body: VALID_PHOTO, key: 'body-photo-create-0001', ...overrides }),
    ),
  complete: (overrides: Partial<Call> = {}) =>
    COMPLETE(
      request({
        method: 'POST',
        path: `/${PHOTO}/complete`,
        key: 'body-photo-complete-0001',
        ...overrides,
      }),
      { params: Promise.resolve({ id: PHOTO }) },
    ),
  remove: (overrides: Partial<Call> = {}) =>
    DELETE(request({ method: 'DELETE', key: 'body-photo-delete-0001', ...overrides })),
}

function db(): SignupBodyPhotoMemoryDb {
  return world.db as SignupBodyPhotoMemoryDb
}

beforeEach(() => {
  world.db = new SignupBodyPhotoMemoryDb().addAccount({
    id: ACCOUNT,
    authUserId: AUTH_USER,
    token: TOKEN,
  })
  // The real bootstrap ensures this profile row (20260720020351:201).
  db().profiles.set(ACCOUNT, { onboarding_completed: false, onboarding_completed_at: null })
  world.queue.length = 0
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING_REF}.supabase.co`)
  vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, '')
})

afterEach(() => {
  vi.unstubAllEnvs()
})

/** The three ways the switch is off. */
const OFF: Array<[string, () => void]> = [
  ['without the variable', () => vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, '')],
  [
    'with the wrong ref listed',
    () => vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, 'abcdefghijklmnopqrst'),
  ],
  [
    'on the old production database with its ref listed (refused in code)',
    () => {
      vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${PRODUCTION_REF}.supabase.co`)
      vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, PRODUCTION_REF)
    },
  ],
]

describe.each(OFF)('body photos of the sign-up, switch off %s', (_label, switchOff) => {
  beforeEach(switchOff)

  it('GET answers 200 "not available" (disabled) without a single query', async () => {
    const response = await CALLS.state()

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({
      data: NOT_AVAILABLE,
      meta: { api_version: 'v1', request_id: expect.any(String) },
    })
    expect(response.headers.get('cache-control')).toBe('no-store')
    // Nothing beyond the authentication of the request.
    expect(db().operations).toEqual(AUTHENTICATION)
    expect(world.queue).toEqual([])
  })

  it.each([
    ['POST /consent', CALLS.consent],
    ['POST (create a photo)', CALLS.create],
    ['POST /:id/complete', CALLS.complete],
  ] as const)('%s answers 404 body_photos_unavailable: nothing is read, claimed, stored or sent', async (_name, call) => {
    const response = await call()

    expect(response.status).toBe(404)
    expect((await response.json()).error).toMatchObject({
      code: 'body_photos_unavailable',
      message: 'Body photos are not available',
    })
    expect(db().operations).toEqual(AUTHENTICATION)
    expect(db().ledger).toEqual([])
    expect(world.queue).toEqual([])
  })

  it('DELETE cleans known staging; a blocked target is refused before any claim or photo query', async () => {
    const response = await CALLS.remove()

    if (process.env.NEXT_PUBLIC_SUPABASE_URL === `https://${STAGING_REF}.supabase.co`) {
      expect(response.status).toBe(200)
      expect((await response.json()).data).toEqual({ deleted: 0 })
    } else {
      expect(response.status).toBe(404)
      expect((await response.json()).error.code).toBe('body_photos_unavailable')
      expect(db().operations).toEqual(AUTHENTICATION)
      expect(db().ledger).toEqual([])
    }
    expect(db().operations.filter((operation) => operation.startsWith('storage:'))).toEqual([])
    expect(world.queue).toEqual([])
  })
})

describe('body photos of the sign-up, switch off — the requests themselves', () => {
  it.each(
    Object.entries(CALLS),
  )('%s without a token is 401 before anything is looked at', async (_name, call) => {
    const response = await call({ token: null })

    expect(response.status).toBe(401)
    expect((await response.json()).error.code).toBe('missing_access_token')
    expect(db().operations).toEqual([])
  })

  it.each(Object.entries(CALLS))('%s with an unknown token is 401', async (_name, call) => {
    const response = await call({ token: 'token-of-nobody' })

    expect(response.status).toBe(401)
    expect((await response.json()).error.code).toBe('invalid_access_token')
    expect(db().operations).toEqual(['auth:getUser'])
  })

  it.each(
    Object.entries(CALLS),
  )('%s is outside the paid-access gate: an account with no access is never asked for one (no 402)', async (_name, call) => {
    const response = await call()

    expect(response.status).not.toBe(402)
    expect(db().operations).not.toContain('rpc:resolve_user_entitlement')
  })

  it.each([
    ['POST /consent', CALLS.consent],
    ['POST (create a photo)', CALLS.create],
    ['POST /:id/complete', CALLS.complete],
  ] as const)('%s is 404 whatever it carries: no Idempotency-Key, no body, a body that would not validate', async (_name, call) => {
    for (const overrides of [
      { key: null },
      { body: undefined },
      { body: { pose: 'sideways', nothing: true } },
    ] satisfies Partial<Call>[]) {
      const response = await call(overrides)
      expect(response.status).toBe(404)
      expect((await response.json()).error.code).toBe('body_photos_unavailable')
    }
    expect(db().ledger).toEqual([])
  })

  it('DELETE requires the Idempotency-Key, as every DELETE of the API does', async () => {
    const response = await CALLS.remove({ key: null })

    expect(response.status).toBe(400)
    expect((await response.json()).error.code).toBe('missing_idempotency_key')
  })

  it('DELETE repeated with the same key answers the same when there is nothing to delete, and keeps one ledger row', async () => {
    const first = await CALLS.remove()
    const second = await CALLS.remove()

    expect(second.status).toBe(200)
    expect(second.headers.get('idempotency-replayed')).toBe('true')
    expect((await second.json()).data).toEqual((await first.json()).data)
    expect(db().ledger).toHaveLength(1)
    expect(db().ledger[0]).toMatchObject({
      request_method: 'DELETE',
      request_route: '/api/mobile/v1/onboarding/body-photos',
      state: 'completed',
      response_status: 200,
    })
  })
})
