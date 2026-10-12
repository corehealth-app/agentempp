/**
 * Audit 2026-10-10 — B3: AI reading is requested only by the sign-up after
 * the current body-photo consent, with the switch on and the sign-up open.
 *
 * EXACT report: the physician wrote "Comecei o cadastro. Ele perguntou qual
 * era a gordura corporal", "Não pediu as fotos" and "Não pediu mesmo as
 * fotos pra cálculo de percentual de gordura" on build 1.0 (3). The owner
 * instructed "ele deve aparece como no whatsapp, lembra? pedir as fotos".
 * Here the account reaches body data, accepts the TEST consent, sends the
 * front photo (image/jpeg, 480000 bytes) and completes the upload. Exactly
 * one media.asset.process.requested event is expected, with only the three
 * official ids and sha256 of the normalized completion Idempotency-Key.
 *
 * The real exported routes, authentication, access gate, handlers, services,
 * adapters and ledger execute. Replaced: service/bearer client factories and
 * the queue client. The strict B2 memory database is reused unchanged; this
 * file adds ONLY an explicit per-account entitlement decision for generic
 * routes and signed download support for their GET. It does not bypass the
 * access gate or accept arbitrary SQL. Entitlement is denied by default.
 *
 * All ids, tokens, bytes, consent text, dates and historical ledger responses
 * are synthetic. No live database, Storage, worker or provider is exercised.
 * No aggregate, profile fat, objective, target or product event is written.
 * The first causal RED preserved the B2 golden and zero-event assertion.
 * GREEN reconciles it with exact explicitly allowed case events; negatives
 * still require an empty queue. Added B3-13b is a post-fix regression; B3-18
 * has its own causal RED for a snapshot race discovered during review.
 * This is neither an owner/physician approval nor a deployment claim.
 */
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { POST as MEDIA_COMPLETE } from '@/app/api/mobile/v1/media/[id]/complete/route'
import { GET as MEDIA_GET } from '@/app/api/mobile/v1/media/[id]/route'
import { POST as MEDIA_POST } from '@/app/api/mobile/v1/media/route'
import { POST as PHOTO_COMPLETE } from '@/app/api/mobile/v1/onboarding/body-photos/[id]/complete/route'
import { POST as CONSENT } from '@/app/api/mobile/v1/onboarding/body-photos/consent/route'
import {
  GET as PHOTO_GET,
  POST as PHOTO_POST,
} from '@/app/api/mobile/v1/onboarding/body-photos/route'
import { hashMobileRequest } from '@/lib/mobile-api/idempotency'
import { createMediaAsset } from '@/lib/mobile-api/media-service'
import { SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV } from '@/lib/mobile-api/signup-body-photo-switch'
import { createSupabaseMediaDependencies } from '@/lib/mobile-api/supabase-media'
import {
  AUTHENTICATION,
  databaseTimestamp,
  type MemoryMediaAsset,
  SignupBodyPhotoMemoryDb,
  sha256Hex,
} from '@/lib/mobile-api/testing/signup-body-photo-memory-db'

const world = vi.hoisted(() => ({ db: undefined as unknown, queue: [] as unknown[] }))
vi.mock('@/lib/supabase/server', () => ({
  createServiceClient: () => (world.db as B3MemoryDb).client,
  createPatientBearerClient: (token: string) => (world.db as B3MemoryDb).bearerClient(token),
}))
vi.mock('@mpp/inngest-functions', () => ({
  inngest: {
    send: async (event: unknown) => {
      world.queue.push(event)
    },
  },
}))

const ACCOUNT = '00000000-0000-4000-8000-000000000321'
const AUTH_USER = '00000000-0000-4000-8000-000000000322'
const OTHER_ACCOUNT = '00000000-0000-4000-8000-000000000331'
const OTHER_AUTH_USER = '00000000-0000-4000-8000-000000000332'
const ASSET = '00000000-0000-4000-8000-000000000b31'
const TOKEN = 'token-of-the-account'
const OTHER_TOKEN = 'token-of-another-account'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
const ORIGIN = 'https://bodyflow.test/api/mobile/v1'
const PHOTO_PATH = '/onboarding/body-photos'
const NOW = new Date('2026-10-11T15:00:00.000Z')
const STORED_AT = databaseTimestamp(new Date(NOW.getTime() - 3_600_000))
const VERSION = 'teste-2026-10-11.1'
const CONSENT_TEXT =
  'TEXTO DE TESTE — não é o consentimento do app. Fotos de frente, lado e costas.'
const FRONT = { pose: 'front', mime_type: 'image/jpeg', size_bytes: 480_000 }
const BODY_RESULT = {
  type: 'body',
  view: 'front',
  bf_percent_estimate: 21.5,
  bf_confidence: 0.4,
  notes: 'synthetic private reading notes',
}

/**
 * The gap in the existing B2 fixture is explicit: it throws for the generic
 * route's resolve_user_entitlement RPC and has no signed-download method.
 * This fixture models exactly those APIs, with normal auth/gate still real.
 */
class B3MemoryDb extends SignupBodyPhotoMemoryDb {
  readonly accountsWithAccess = new Set<string>()

  protected override otherRpc(name: string, params: Record<string, unknown>) {
    if (name !== 'resolve_user_entitlement') return super.otherRpc(name, params)
    if (params.p_entitlement_key !== 'bodyflow_full' || typeof params.p_user_id !== 'string') {
      throw new Error('unexpected entitlement fixture parameters')
    }
    const active = this.accountsWithAccess.has(params.p_user_id)
    return {
      data: {
        entitlement: 'bodyflow_full',
        has_active_access: active,
        status: active ? 'active' : 'expired',
        source: active ? 'manual' : null,
        plan: active ? 'mensal' : null,
        access_expires_at: active ? '2026-10-12T15:00:00.000Z' : null,
        grace_expires_at: null,
        cancel_at_period_end: false,
        reason: active ? 'valid_entitlement' : 'no_entitlement',
        decision_at: String(params.p_now),
      },
      error: null,
    }
  }

  override get client(): ServiceClient {
    const base = super.client
    return {
      ...base,
      storage: {
        from: (bucketId: string) => ({
          ...base.storage.from(bucketId),
          createSignedUrl: async (objectPath: string, expiresIn: number, options: unknown) => {
            const error = this.record('storage:createSignedUrl', {
              bucketId,
              objectPath,
              expiresIn,
              options,
            })
            if (error) return { data: null, error }
            return { data: { signedUrl: 'https://storage.test/synthetic-download' }, error: null }
          },
        }),
      },
    } as unknown as ServiceClient
  }
}

function db(): B3MemoryDb {
  return world.db as B3MemoryDb
}

interface Call {
  body?: unknown
  key?: string
  token?: string
  requestId?: string
}
function request(method: string, path: string, call: Call = {}): Request {
  const headers: Record<string, string> = { authorization: `Bearer ${call.token ?? TOKEN}` }
  if (call.key !== undefined) headers['idempotency-key'] = call.key
  if (call.requestId) headers['x-request-id'] = call.requestId
  if (call.body !== undefined) headers['content-type'] = 'application/json'
  return new Request(`${ORIGIN}${path}`, {
    method,
    headers,
    body: call.body === undefined ? undefined : JSON.stringify(call.body),
  })
}

function photoComplete(id: string, key: string, token = TOKEN) {
  return PHOTO_COMPLETE(request('POST', `${PHOTO_PATH}/${id}/complete`, { key, token }), {
    params: Promise.resolve({ id }),
  })
}
function mediaComplete(id: string, key: string, requestId = 'b3-current-request-id') {
  return MEDIA_COMPLETE(request('POST', `/media/${id}/complete`, { key, requestId }), {
    params: Promise.resolve({ id }),
  })
}
function mediaGet(id: string) {
  return MEDIA_GET(request('GET', `/media/${id}`), { params: Promise.resolve({ id }) })
}
function genericCreate(input: unknown, key: string) {
  return MEDIA_POST(request('POST', '/media', { body: input, key }))
}
async function errorOf(response: Response) {
  return { status: response.status, code: (await response.json()).error?.code }
}
async function acceptConsent(token = TOKEN) {
  const response = await CONSENT(
    request('POST', `${PHOTO_PATH}/consent`, {
      body: { version: VERSION, body_hash: sha256Hex(CONSENT_TEXT), birth_date: '1990-05-20' },
      key: token === TOKEN ? 'body-photo-consent-main' : 'body-photo-consent-other',
      token,
    }),
  )
  expect(response.status).toBe(200)
}
async function createFront(key = 'body-photo-create-front') {
  const response = await PHOTO_POST(request('POST', PHOTO_PATH, { body: FRONT, key }))
  expect(response.status).toBe(201)
  return (await response.json()).data as { photo: { id: string; created_at: string } }
}
function seed(state: Partial<MemoryMediaAsset> = {}) {
  return db().seedMediaAsset({
    id: ASSET,
    user_id: ACCOUNT,
    signup_origin: true,
    context_text: 'Foto de frente.',
    ...state,
  })
}
function storedState(status: string): Partial<MemoryMediaAsset> {
  if (status === 'pending_upload') return {}
  const state: Partial<MemoryMediaAsset> = {
    status,
    actual_size_bytes: 1200,
    uploaded_at: STORED_AT,
  }
  if (status === 'processing' || status === 'processed')
    state.processing_request_id = 'c'.repeat(64)
  if (status === 'processed')
    Object.assign(state, { processed_at: STORED_AT, processing_result: BODY_RESULT })
  if (status === 'failed')
    Object.assign(state, { failure_stage: 'processing', failure_code: 'provider_error' })
  return state
}

interface ProcessingEvent {
  id: string
  name: 'media.asset.process.requested'
  data: { assetId: string; userId: string; requestId: string }
}
let expectedEvents: ProcessingEvent[] = []
function expectDispatch(assetId: string, key: string) {
  const requestId = sha256Hex(key.trim())
  expectedEvents.push({
    id: `media-process:${assetId}:${requestId}`,
    name: 'media.asset.process.requested',
    data: { assetId, userId: ACCOUNT, requestId },
  })
}
function assertNoMediaEffects() {
  expect(
    db().operations.filter((operation) => /^(?:insert|update):|^storage:/.test(operation)),
  ).toEqual([])
  expect(world.queue).toEqual([])
}
function forgetRecordedCalls() {
  db().operations.length = 0
  db().calls.length = 0
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(NOW)
  expectedEvents = []
  world.queue.length = 0
  const database = new B3MemoryDb()
    .addAccount({ id: ACCOUNT, authUserId: AUTH_USER, token: TOKEN })
    .addAccount({ id: OTHER_ACCOUNT, authUserId: OTHER_AUTH_USER, token: OTHER_TOKEN })
  database.now = () => new Date()
  database.profiles.set(ACCOUNT, { onboarding_completed: false, onboarding_completed_at: null })
  database.publishDocument({
    documentKey: 'body_photo_estimate_consent',
    version: VERSION,
    locale: 'pt-BR',
    body: CONSENT_TEXT,
    requiredFrom: '2026-01-01T00:00:00.000Z',
  })
  world.db = database
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING_REF}.supabase.co`)
  vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, STAGING_REF)
})

afterEach(() => {
  try {
    // Zero by default; an allowed case declares every exact event BEFORE its
    // call. A new/duplicate event anywhere else fails this guard.
    expect(world.queue).toEqual(expectedEvents)
    // B3 does not write a profile, targets, protocol or product_events.
    expect(
      db().operations.filter((operation) => /^(?:insert|update):(?!media_assets)/.test(operation)),
    ).toEqual([])
  } finally {
    vi.useRealTimers()
    vi.unstubAllEnvs()
    vi.restoreAllMocks()
  }
})

describe('B3 golden — the report, consent then front photo then one reading request', () => {
  it('B3-1 EXACT: step 2 with no paid access accepts the current consent, uploads front JPEG 480000 and completes → one exact event; the same key never emits a second', async () => {
    await acceptConsent()
    const { photo } = await createFront()
    const row = db().mediaAssets.find((asset) => asset.id === photo.id)
    if (!row) throw new Error('created photo missing')
    db().upload(row, { size: 480_000, contentType: 'image/jpeg' })
    const key = 'body-photo-reading-front-0001'
    expectDispatch(photo.id, key)

    const first = await photoComplete(photo.id, `  ${key}  `)

    expect(first.status).toBe(200)
    expect(world.queue).toEqual(expectedEvents)
    expect((await first.json()).data.photo).toMatchObject({ id: photo.id, pose: 'front' })
    // Only the worker claims processing: dispatch must not invent a DB state.
    expect(row).toMatchObject({
      status: 'uploaded',
      actual_size_bytes: 480_000,
      processing_request_id: null,
    })
    const beforeReplay = db().operations.length
    const replay = await photoComplete(photo.id, key)
    expect(replay.status).toBe(200)
    expect(replay.headers.get('idempotency-replayed')).toBe('true')
    expect(world.queue).toEqual(expectedEvents)
    expect(db().operations.slice(beforeReplay)).toEqual([
      ...AUTHENTICATION,
      'rpc:claim_mobile_api_request',
    ])
    expect(db().operations).not.toContain('rpc:resolve_user_entitlement')
  })

  it('B3-2 uploaded with two DIFFERENT completion keys emits two exact requests while the worker has not claimed the photo; no row mutation', async () => {
    await acceptConsent()
    const row = seed(storedState('uploaded'))
    const before = { ...row }
    for (const key of ['body-photo-reading-first', 'body-photo-reading-second']) {
      expectDispatch(row.id, key)
      expect((await photoComplete(row.id, key)).status).toBe(200)
      expect(world.queue).toEqual(expectedEvents)
    }
    expect(row).toEqual(before)
    expect(
      db().operations.filter((operation) => /^(?:insert|update):media_assets$/.test(operation)),
    ).toEqual([])
  })

  it.each([
    ['processing', 'reading'],
    ['processed', 'read'],
  ])('B3-3 %s returns %s without requesting reading again', async (status, publicStatus) => {
    await acceptConsent()
    const row = seed(storedState(status))
    const before = { ...row }
    const response = await photoComplete(row.id, 'body-photo-no-reread')
    expect(response.status).toBe(200)
    expect((await response.json()).data.photo).toMatchObject({ id: row.id, status: publicStatus })
    expect(row).toEqual(before)
    assertNoMediaEffects()
  })

  it('B3-4 failed reading requires a NEW photo: 409 body_photo_reading_failed, no dispatch, deletion or row mutation', async () => {
    await acceptConsent()
    const row = seed(storedState('failed'))
    const before = { ...row }
    expect(await errorOf(await photoComplete(row.id, 'body-photo-failed-reading'))).toEqual({
      status: 409,
      code: 'body_photo_reading_failed',
    })
    expect(row).toEqual(before)
    assertNoMediaEffects()
  })

  it('B3-3b processed without a number also returns unreadable from completion: 200, no event or mutation', async () => {
    await acceptConsent()
    const row = seed({ ...storedState('processed'), processing_result: null })
    const before = { ...row }
    const response = await photoComplete(row.id, 'body-photo-processed-without-number')
    expect(response.status).toBe(200)
    expect((await response.json()).data.photo).toMatchObject({ id: row.id, status: 'unreadable' })
    expect(row).toEqual(before)
    assertNoMediaEffects()
  })
})

describe('B3 reading policy is rechecked for every stored state', () => {
  const states = ['pending_upload', 'uploaded', 'processing', 'processed', 'failed']

  it.each(states)('B3-5 %s without consent → 403 before any storage or event', async (status) => {
    const row = seed(storedState(status))
    const before = { ...row }
    expect(await errorOf(await photoComplete(row.id, 'body-photo-without-consent'))).toEqual({
      status: 403,
      code: 'body_photo_consent_required',
    })
    expect(row).toEqual(before)
    assertNoMediaEffects()
  })

  it.each(
    states,
  )('B3-6 %s with consent accepted by ANOTHER account → 403, no event', async (status) => {
    await acceptConsent(OTHER_TOKEN)
    const row = seed(storedState(status))
    const before = { ...row }
    expect(await errorOf(await photoComplete(row.id, 'body-photo-other-consent'))).toEqual({
      status: 403,
      code: 'body_photo_consent_required',
    })
    expect(row).toEqual(before)
    assertNoMediaEffects()
  })

  it.each(
    states,
  )('B3-7 %s with acceptance of the OLD consent text → 403 before event', async (status) => {
    await acceptConsent()
    db().publishDocument({
      documentKey: 'body_photo_estimate_consent',
      version: 'teste-2026-10-11.2',
      locale: 'pt-BR',
      body: 'TEXTO DE TESTE — segunda versão, não aprovado.',
      requiredFrom: '2026-10-11T14:00:00.000Z',
    })
    const row = seed(storedState(status))
    const before = { ...row }
    expect(await errorOf(await photoComplete(row.id, 'body-photo-old-consent'))).toEqual({
      status: 403,
      code: 'body_photo_consent_required',
    })
    expect(row).toEqual(before)
    assertNoMediaEffects()
  })

  it.each(states)('B3-8 %s after sign-up completed → 409 and no reading', async (status) => {
    await acceptConsent()
    db().profiles.set(ACCOUNT, { onboarding_completed: true, onboarding_completed_at: STORED_AT })
    const row = seed(storedState(status))
    const before = { ...row }
    expect(await errorOf(await photoComplete(row.id, 'body-photo-signup-complete'))).toEqual({
      status: 409,
      code: 'onboarding_already_completed',
    })
    expect(row).toEqual(before)
    assertNoMediaEffects()
  })

  it.each(
    states,
  )('B3-9 %s while OFF → 404 before ledger, owner, storage or event', async (status) => {
    const row = seed(storedState(status))
    vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, '')
    expect(await errorOf(await photoComplete(row.id, 'body-photo-disabled'))).toEqual({
      status: 404,
      code: 'body_photos_unavailable',
    })
    expect(db().operations).toEqual(AUTHENTICATION)
    expect(db().ledger).toEqual([])
  })

  it.each(states)('B3-10 %s of another owner → 404 even before consent lookup', async (status) => {
    const row = seed({ ...storedState(status), user_id: OTHER_ACCOUNT })
    const before = { ...row }
    expect(await errorOf(await photoComplete(row.id, 'body-photo-other-owner'))).toEqual({
      status: 404,
      code: 'body_photo_not_found',
    })
    expect(row).toEqual(before)
    expect(db().operations).not.toContain('rpc:get_mobile_legal_document')
    assertNoMediaEffects()
  })
})

describe('B3 GET distinguishes a finished reading without a number; no aggregate yet', () => {
  it.each([
    ['valid body number', BODY_RESULT, 'read'],
    ['no result', null, 'unreadable'],
    ['body without number', { type: 'body', notes: 'synthetic private notes' }, 'unreadable'],
    ['null number', { type: 'body', bf_percent_estimate: null }, 'unreadable'],
    ['string number', { type: 'body', bf_percent_estimate: '21.5' }, 'unreadable'],
    ['wrong reading type', { type: 'meal', bf_percent_estimate: 21.5 }, 'unreadable'],
    [
      'non-finite number',
      { type: 'body', bf_percent_estimate: Number.POSITIVE_INFINITY },
      'unreadable',
    ],
  ])('B3-11 processed with %s → %s, never free reading fields', async (_label, result, status) => {
    seed({ ...storedState('processed'), processing_result: result })
    const response = await PHOTO_GET(request('GET', PHOTO_PATH))
    expect(response.status).toBe(200)
    const data = (await response.json()).data
    expect(data.poses[0].photo).toEqual({ id: ASSET, status, created_at: databaseTimestamp(NOW) })
    expect(data.estimate).toBeNull()
    const visible = JSON.stringify(data)
    for (const forbidden of [
      'bf_percent_estimate',
      'bf_confidence',
      'notes',
      'processing_result',
      'object_path',
      'Foto de frente.',
    ]) {
      expect(visible, forbidden).not.toContain(forbidden)
    }
    assertNoMediaEffects()
  })
})

describe('B3 generic media is closed to body creation and masked replay', () => {
  beforeEach(() => {
    db().accountsWithAccess.add(ACCOUNT)
  })

  it.each([
    true,
    false,
  ])('B3-12 POST /media body_checkin_photo with signup feature enabled=%s → 422 BEFORE reserving ledger, creating row or handing a ticket', async (enabled) => {
    vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, enabled ? STAGING_REF : '')
    const response = await genericCreate(
      { kind: 'body_checkin_photo', mime_type: 'image/jpeg', size_bytes: 480_000 },
      'generic-body-create',
    )
    expect(response.status).toBe(422)
    expect(db().ledger).toEqual([])
    expect(db().mediaAssets).toEqual([])
    expect(db().operations).toEqual([...AUTHENTICATION, 'rpc:resolve_user_entitlement'])
    assertNoMediaEffects()
  })

  it('B3-13 EXACT masked replay: meal_photo input + same signup-body key AFTER the ledger expired → 422, no refreshed ticket', async () => {
    await acceptConsent()
    const key = 'body-photo-masked-replay'
    const { photo } = await createFront(key)
    const row = db().mediaAssets.find((entry) => entry.id === photo.id)
    if (!row) throw new Error('created photo missing')
    const original = { ...row }
    const ledger = db().ledger.find((entry) => entry.idempotency_key === key)
    if (!ledger) throw new Error('signup creation ledger missing')
    // A real elapsed ledger window, while the body row is still pending.
    // No receipt is erased or rewritten to manufacture a new claim.
    vi.setSystemTime(new Date(NOW.getTime() + 25 * 3_600_000))
    expect(ledger.expires_at).toBeLessThan(Date.now())
    forgetRecordedCalls()

    const response = await genericCreate(
      { kind: 'meal_photo', mime_type: 'image/jpeg', size_bytes: 480_000 },
      key,
    )

    expect(response.status).toBe(422)
    expect(row).toEqual(original)
    expect(db().mediaAssets).toHaveLength(1)
    expect(db().operations).toContain('rpc:resolve_user_entitlement')
    expect(db().operations).toContain('rpc:claim_mobile_api_request')
    assertNoMediaEffects()
  })

  it('B3-13b EXACT concurrent 23505: lookup null, INSERT meal loses to body pending with the same hash → 422 before any signed ticket', async () => {
    const key = 'body-photo-concurrent-create-race'
    const executeReal = db().execute.bind(db())
    let injected = 0
    let lookups = 0
    let firstLookupWasEmpty = false
    let concurrentBefore: MemoryMediaAsset | null = null
    vi.spyOn(db(), 'execute').mockImplementation(async (spec) => {
      if (spec.table === 'media_assets' && spec.operation === 'select') {
        lookups += 1
        const result = await executeReal(spec)
        if (lookups === 1) {
          firstLookupWasEmpty = Array.isArray(result.data) && result.data.length === 0
        }
        return result
      }
      if (
        spec.table === 'media_assets' &&
        spec.operation === 'insert' &&
        spec.payload?.kind === 'meal_photo' &&
        injected === 0
      ) {
        // The competing signup request commits its body row between this
        // generic request's lookup and INSERT. The strict database then
        // returns a real 23505 and the real adapter resolves that row.
        expect(firstLookupWasEmpty).toBe(true)
        expect(spec.payload.source_request_hash).toBe(sha256Hex(key))
        expect(db().mediaAssets).toEqual([])
        injected += 1
        const concurrent = seed({ source_request_hash: sha256Hex(key) })
        concurrentBefore = { ...concurrent }
      }
      return executeReal(spec)
    })

    const response = await genericCreate(
      { kind: 'meal_photo', mime_type: 'image/jpeg', size_bytes: 1200 },
      key,
    )

    expect(response.status).toBe(422)
    expect(injected).toBe(1)
    expect(firstLookupWasEmpty).toBe(true)
    expect(lookups).toBe(2)
    expect(concurrentBefore).not.toBeNull()
    expect(db().mediaAssets).toEqual([concurrentBefore])
    // INSERT was attempted and refused; no new row was created by it.
    expect(db().operations.filter((operation) => operation === 'insert:media_assets')).toHaveLength(
      1,
    )
    expect(db().operations.filter((operation) => /^update:|^storage:/.test(operation))).toEqual([])
    expect(db().operations).not.toContain('rpc:complete_mobile_api_request')
    expect(world.queue).toEqual([])
  })

  it('B3-14 the fixture does not bypass entitlement: the same generic request without access → 402 before any ledger or Storage call', async () => {
    db().accountsWithAccess.delete(ACCOUNT)
    const response = await genericCreate(
      { kind: 'meal_photo', mime_type: 'image/jpeg', size_bytes: 480_000 },
      'generic-needs-access',
    )
    expect(await errorOf(response)).toEqual({ status: 402, code: 'subscription_required' })
    expect(db().operations).toEqual([...AUTHENTICATION, 'rpc:resolve_user_entitlement'])
    expect(db().ledger).toEqual([])
    assertNoMediaEffects()
  })

  it.each([
    ['meal_photo', 'image/jpeg'],
    ['gym_photo', 'image/jpeg'],
    ['audio_note', 'audio/mp4'],
  ])('B3-15 %s generic creation and replay still give the same row and a fresh ticket, no processing event', async (kind, mime_type) => {
    const key = `generic-neighbor-${kind}`
    const input = { kind, mime_type, size_bytes: 1200 }
    const first = await genericCreate(input, key)
    expect(first.status).toBe(201)
    const a = (await first.json()).data
    const replay = await genericCreate(input, key)
    expect(replay.status).toBe(201)
    const b = (await replay.json()).data
    expect(b.asset).toEqual(a.asset)
    expect(b.asset.kind).toBe(kind)
    expect(b.replayed).toBe(true)
    expect(b.upload.signed_url).not.toEqual(a.upload.signed_url)
    expect(db().mediaAssets).toHaveLength(1)
    expect(db().operations.filter((op) => op === 'insert:media_assets')).toHaveLength(1)
    expect(db().operations.filter((op) => op === 'storage:createSignedUploadUrl')).toHaveLength(2)
  })
})

describe('B3 generic DTOs hide ONLY body results', () => {
  beforeEach(() => {
    db().accountsWithAccess.add(ACCOUNT)
  })

  it.each([
    'body_checkin_photo',
    'meal_photo',
    'gym_photo',
    'audio_note',
  ])('B3-16 %s: generic GET, completion and service creation replay preserve fields and only body result becomes null', async (kind) => {
    const key = `existing-processed-${kind}`
    const result =
      kind === 'body_checkin_photo'
        ? BODY_RESULT
        : { type: kind, synthetic_result: 'preserve exactly', notes: 'synthetic neighboring notes' }
    const row = seed({
      ...storedState('processed'),
      kind,
      bucket_id:
        kind === 'body_checkin_photo'
          ? 'body-checkin-photos'
          : kind === 'meal_photo'
            ? 'meal-photos'
            : kind === 'gym_photo'
              ? 'gym-photos'
              : 'audio-notes',
      mime_type: kind === 'audio_note' ? 'audio/mp4' : 'image/jpeg',
      object_path: `${ACCOUNT}/${ASSET}${kind === 'audio_note' ? '.m4a' : '.jpg'}`,
      processing_result: result,
      source_request_hash: sha256Hex(key),
    })
    const before = { ...row }
    const get = await mediaGet(row.id)
    expect(get.status).toBe(200)
    const fromGet = (await get.json()).data
    const completion = await mediaComplete(row.id, `complete-existing-${kind}`)
    expect(completion.status).toBe(200)
    const fromComplete = (await completion.json()).data
    // The service keeps default body support for the dedicated sign-up caller;
    // this is not a claim that POST /media is allowed to hand the replay back.
    const serviceReplay = await createMediaAsset(
      createSupabaseMediaDependencies(db().client),
      ACCOUNT,
      {
        kind: 'meal_photo',
        mime_type: 'image/jpeg',
        size_bytes: 1200,
      },
      key,
    )
    const expectedResult = kind === 'body_checkin_photo' ? null : result
    for (const data of [fromGet, fromComplete, serviceReplay.asset]) {
      expect(data).toMatchObject({
        id: ASSET,
        kind,
        status: 'processed',
        size_bytes: 1200,
        result: expectedResult,
        has_context: true,
      })
    }
    // Generic DTOs must not spread raw records returned by an internal helper.
    const publicDtoKeys = [
      'id',
      'kind',
      'mime_type',
      'size_bytes',
      'status',
      'failure_stage',
      'failure_code',
      'has_context',
      'retention_until',
      'uploaded_at',
      'processed_at',
      'deleted_at',
      'result',
      'created_at',
      'updated_at',
    ]
    expect(Object.keys(fromGet).sort()).toEqual([...publicDtoKeys, 'download'].sort())
    for (const data of [fromComplete, serviceReplay.asset]) {
      expect(Object.keys(data).sort()).toEqual([...publicDtoKeys].sort())
    }
    expect(serviceReplay.upload).toBeNull()
    expect(serviceReplay.replayed).toBe(true)
    expect(row).toEqual(before)
    expect(
      db().operations.filter((op) => /^(?:insert|update):|^storage:(?!createSignedUrl)/.test(op)),
    ).toEqual([])
    expect(db().operations.filter((op) => op === 'storage:createSignedUrl')).toHaveLength(1)
  })
})

function historicalDto(row: MemoryMediaAsset) {
  return {
    id: row.id,
    kind: row.kind,
    mime_type: row.mime_type,
    size_bytes: row.actual_size_bytes ?? row.declared_size_bytes,
    status: row.status,
    failure_stage: row.failure_stage,
    failure_code: row.failure_code,
    has_context: Boolean(row.context_text),
    retention_until: row.retention_until,
    uploaded_at: row.uploaded_at,
    processed_at: row.processed_at,
    deleted_at: row.deleted_at,
    result: row.processing_result,
    created_at: row.created_at,
    updated_at: row.updated_at,
  }
}

describe('B3-18 sign-up creation replay uses one coherent reading snapshot', () => {
  it('B3-18 EXACT interleaving: first hash lookup uploaded, worker completes before second lookup → 201 read, no upload ticket/event/private fields', async () => {
    await acceptConsent()
    const key = 'body-photo-coherent-replay-snapshot'
    const row = seed({
      ...storedState('uploaded'),
      declared_size_bytes: 480_000,
      actual_size_bytes: 480_000,
      source_request_hash: sha256Hex(key),
    })
    db().upload(row, { size: 480_000, contentType: 'image/jpeg' })
    forgetRecordedCalls()
    const executeReal = db().execute.bind(db())
    const workerProcessing = {
      status: 'processing' as const,
      processing_request_id: 'c'.repeat(64),
    }
    const workerProcessed = {
      status: 'processed' as const,
      processed_at: NOW.toISOString(),
      processing_result: BODY_RESULT,
    }
    let hashLookups = 0
    let firstWasUploaded = false
    let workerTransitions = 0
    vi.spyOn(db(), 'execute').mockImplementation(async (spec) => {
      const isHashLookup =
        spec.table === 'media_assets' &&
        spec.operation === 'select' &&
        spec.filters.some(
          (filter) =>
            filter.kind === 'eq' &&
            filter.column === 'source_request_hash' &&
            filter.value === sha256Hex(key),
        )
      if (!isHashLookup) return executeReal(spec)
      hashLookups += 1
      if (hashLookups === 2) {
        expect(firstWasUploaded).toBe(true)
        // An external worker completes between the two route reads. Both
        // transitions use the strict DB trigger; there is no illegal direct
        // uploaded -> processed assignment and no route-side write hidden.
        const processing = await db()
          .client.from('media_assets')
          .update(workerProcessing)
          .eq('user_id', ACCOUNT)
          .eq('id', ASSET)
          .select('id')
        expect(processing.error).toBeNull()
        expect(processing.data).toEqual([{ id: ASSET }])
        workerTransitions += 1
        const processed = await db()
          .client.from('media_assets')
          .update(workerProcessed)
          .eq('user_id', ACCOUNT)
          .eq('id', ASSET)
          .select('id')
        expect(processed.error).toBeNull()
        expect(processed.data).toEqual([{ id: ASSET }])
        workerTransitions += 1
      }
      const result = await executeReal(spec)
      if (hashLookups === 1) {
        const first = Array.isArray(result.data) ? result.data[0] : null
        firstWasUploaded = first?.status === 'uploaded' && first.processing_result === null
        expect(firstWasUploaded).toBe(true)
      }
      return result
    })

    const response = await PHOTO_POST(request('POST', PHOTO_PATH, { body: FRONT, key }))

    expect(response.status).toBe(201)
    expect(hashLookups).toBe(2)
    expect(firstWasUploaded).toBe(true)
    expect(workerTransitions).toBe(2)
    expect(row).toMatchObject({ status: 'processed', processing_result: BODY_RESULT })
    expect((await response.json()).data).toEqual({
      photo: { id: ASSET, pose: 'front', status: 'read', created_at: databaseTimestamp(NOW) },
      upload: null,
      replayed: true,
    })
    expect(db().mediaAssets).toHaveLength(1)
    expect(
      db().operations.filter(
        (operation) => operation.startsWith('insert:') || operation.startsWith('storage:'),
      ),
    ).toEqual([])
    const writes = db().calls.filter((call) => call.operation === 'update:media_assets')
    expect(writes.map((call) => (call.detail as { payload: unknown }).payload)).toEqual([
      workerProcessing,
      workerProcessed,
    ])
    expect(world.queue).toEqual([])
  })
})

describe('B3-19 sign-up completion uses one coherent reading snapshot', () => {
  it('B3-19 EXACT interleaving: first owned lookup pending, another completion and worker finish before second lookup → 200 read, no Storage/event/private fields', async () => {
    await acceptConsent()
    const row = seed({ declared_size_bytes: 480_000 })
    // Bytes and the following state transitions belong to the external
    // actor in this fixture, not to the route under test.
    db().upload(row, { size: 480_000, contentType: 'image/jpeg' })
    forgetRecordedCalls()
    const executeReal = db().execute.bind(db())
    const workerUploaded = {
      status: 'uploaded' as const,
      actual_size_bytes: 480_000,
      uploaded_at: NOW.toISOString(),
      etag: 'synthetic-external-upload-etag',
    }
    const workerProcessing = {
      status: 'processing' as const,
      processing_request_id: 'c'.repeat(64),
    }
    const workerProcessed = {
      status: 'processed' as const,
      processed_at: NOW.toISOString(),
      processing_result: BODY_RESULT,
    }
    let ownedLookups = 0
    let firstWasPending = false
    let externalTransitions = 0
    vi.spyOn(db(), 'execute').mockImplementation(async (spec) => {
      const isOwnedLookup =
        spec.table === 'media_assets' &&
        spec.operation === 'select' &&
        spec.filters.some(
          (filter) => filter.kind === 'eq' && filter.column === 'id' && filter.value === ASSET,
        ) &&
        spec.filters.some(
          (filter) =>
            filter.kind === 'eq' && filter.column === 'user_id' && filter.value === ACCOUNT,
        )
      if (!isOwnedLookup) return executeReal(spec)
      ownedLookups += 1
      if (ownedLookups === 2) {
        expect(firstWasPending).toBe(true)
        // Valid transitions through the real strict memory DB trigger.
        // Metadata proves that the external completion did store this photo;
        // the route must classify the processed snapshot it subsequently sees.
        for (const patch of [workerUploaded, workerProcessing, workerProcessed]) {
          const transition = await db()
            .client.from('media_assets')
            .update(patch)
            .eq('user_id', ACCOUNT)
            .eq('id', ASSET)
            .select('id')
          expect(transition.error).toBeNull()
          expect(transition.data).toEqual([{ id: ASSET }])
          externalTransitions += 1
        }
      }
      const result = await executeReal(spec)
      if (ownedLookups === 1) {
        const first = Array.isArray(result.data) ? result.data[0] : null
        firstWasPending =
          first?.status === 'pending_upload' &&
          first.actual_size_bytes === null &&
          first.uploaded_at === null &&
          first.processing_result === null
        expect(firstWasPending).toBe(true)
      }
      return result
    })

    const response = await photoComplete(ASSET, 'body-photo-coherent-complete-snapshot')

    expect(response.status).toBe(200)
    expect(ownedLookups).toBe(2)
    expect(firstWasPending).toBe(true)
    expect(externalTransitions).toBe(3)
    expect(row).toMatchObject({
      status: 'processed',
      actual_size_bytes: 480_000,
      processing_result: BODY_RESULT,
    })
    expect((await response.json()).data).toEqual({
      photo: {
        id: ASSET,
        pose: 'front',
        status: 'read',
        created_at: databaseTimestamp(NOW),
      },
    })
    expect(db().mediaAssets).toHaveLength(1)
    expect(
      db().operations.filter(
        (operation) => operation.startsWith('insert:') || operation.startsWith('storage:'),
      ),
    ).toEqual([])
    const writes = db().calls.filter((call) => call.operation === 'update:media_assets')
    expect(writes.map((call) => (call.detail as { payload: unknown }).payload)).toEqual([
      workerUploaded,
      workerProcessing,
      workerProcessed,
    ])
    expect(world.queue).toEqual([])
  })
})

describe('B3 historical ledger replay of generic complete is sanitized without executing a mutation', () => {
  beforeEach(() => {
    db().accountsWithAccess.add(ACCOUNT)
  })

  it.each([
    'body_checkin_photo',
    'meal_photo',
    'gym_photo',
    'audio_note',
  ])('B3-17 EXACT historical %s complete envelope: status, meta, replay headers preserved; body result null, neighbors identical, no operation replay', async (kind) => {
    const result =
      kind === 'body_checkin_photo'
        ? BODY_RESULT
        : { type: kind, synthetic_result: 'preserve exactly' }
    const row = seed({
      ...storedState('processed'),
      kind,
      bucket_id:
        kind === 'body_checkin_photo'
          ? 'body-checkin-photos'
          : kind === 'meal_photo'
            ? 'meal-photos'
            : kind === 'gym_photo'
              ? 'gym-photos'
              : 'audio-notes',
      mime_type: kind === 'audio_note' ? 'audio/mp4' : 'image/jpeg',
      object_path: `${ACCOUNT}/${ASSET}${kind === 'audio_note' ? '.m4a' : '.jpg'}`,
      processing_result: result,
    })
    const key = `historical-complete-${kind}`
    const historical = {
      data: historicalDto(row),
      meta: { request_id: 'old-historical-request-id', synthetic_marker: 'keep this meta' },
    }
    db().ledger.push({
      id: 'historical-claim',
      user_id: ACCOUNT,
      idempotency_key: key,
      request_method: 'POST',
      request_route: `/api/mobile/v1/media/${ASSET}/complete`,
      request_hash: hashMobileRequest({ media_asset_id: ASSET }),
      state: 'completed',
      response_status: 200,
      response_body: historical,
      attempt_count: 1,
      updated_at: NOW.getTime() - 60_000,
      expires_at: NOW.getTime() + 60_000,
    })
    const before = JSON.stringify(db().mediaAssets)
    const historyBefore = JSON.stringify(historical)
    const currentRequestId = 'b3-current-replay-request'

    const response = await mediaComplete(ASSET, key, currentRequestId)

    expect(response.status).toBe(200)
    expect(response.headers.get('idempotency-replayed')).toBe('true')
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
    expect(response.headers.get('x-request-id')).toBe(currentRequestId)
    expect(await response.json()).toEqual({
      data: { ...historical.data, result: kind === 'body_checkin_photo' ? null : result },
      meta: { ...historical.meta, request_id: currentRequestId },
    })
    expect(JSON.stringify(historical)).toBe(historyBefore)
    expect(JSON.stringify(db().mediaAssets)).toBe(before)
    expect(db().operations).toEqual([
      ...AUTHENTICATION,
      'rpc:resolve_user_entitlement',
      'rpc:claim_mobile_api_request',
    ])
    expect(db().operations).not.toContain('rpc:complete_mobile_api_request')
    assertNoMediaEffects()
  })
})
