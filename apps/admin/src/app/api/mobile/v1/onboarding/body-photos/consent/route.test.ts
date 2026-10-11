/**
 * Body photos of the sign-up — the consent of its own, the minimum age and
 * the reading of the state (docs/mobile/api-v1.md, "Fotos do corpo no
 * cadastro"; update 2, package B1). No photo exists yet in this package.
 *
 * WHY A CONSENT OF ITS OWN. The photos are offered at step 2 of the sign-up,
 * and the four notices of the sign-up are only accepted at step 5 and only
 * recorded at the completion. So the acceptance of the photos is asked for on
 * the spot, before the first photo, and recorded at once with the version,
 * the mark of the text and the time, by the generic functions the medication
 * disclaimer already uses (`get_mobile_legal_document`,
 * `accept_mobile_legal_document`), with the key `body_photo_estimate_consent`.
 * No migration.
 *
 * THE TEXT IS A FIXTURE. The text of the consent is a row of
 * `legal_documents` that the owner still has to approve; it is not part of
 * this change. Every test here runs against CONSENT_FIXTURE below, which says
 * it is a test text. No row was written to any database.
 *
 * THE MINIMUM AGE (18) is a decisão do orquestrador, anunciada ao dono em
 * 2026-10-10/11, que pode riscar qualquer uma. It is not an approval of the
 * owner nor of the physician. The age is the one of the DECLARED birth date,
 * counted in whole years on today's date in the account's time zone
 * (America/Sao_Paulo when the account has none or an invalid one); someone
 * born on 29 February completes the year on 1 March of a year without that
 * day. The date is sent in the body, checked, and never recorded.
 *
 * WHAT RUNS. The exported route functions, the real route wrapper
 * (authentication and the access gate), the real handlers, service, adapter
 * and idempotency code. Replaced: the database client factory (an in-memory
 * database written from the migrations, which throws on any query nobody
 * declared) and the queue client. The clock is fixed.
 *
 * ASSUMED — declared: account, ids, version, text and instants are synthetic.
 * No database was read or written, nothing was published.
 *
 * > RC P-PHOTOS — cenário texto do consentimento das fotos do corpo (linha body_photo_estimate_consent de legal_documents) variante o texto definitivo (o dono ainda não aprovou nenhum), a gravação dele no banco e a revisão por advogado (os testes usam um texto de teste, que não é o texto do app; nenhuma linha foi gravada) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário pessoa menor de idade variante o servidor conferir a idade real (a idade é a da data declarada no pedido do aceite; a data não é gravada nem cruzada com a enviada na conclusão do cadastro) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário pessoa que completa 18 anos no dia do pedido com o relógio do aparelho num fuso diferente do fuso gravado na conta variante app e servidor concordarem nessas horas (o servidor conta a idade na data de hoje do fuso da conta, que antes da conclusão do cadastro é o valor inicial America/Sao_Paulo) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário pessoa que apaga as fotos para retirar o consentimento variante desfazer o registro do aceite e perguntar de novo antes de novos envios (o registro é imutável e o aceite da versão continua valendo) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário conta com idioma en-US variante texto do consentimento em inglês (sem linha do documento para o idioma da conta o servidor responde "não disponível") NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário funções get_mobile_legal_document e accept_mobile_legal_document e tabela user_legal_acceptances reais do Postgres para conta que ainda não concluiu o cadastro variante teste contra o banco do ambiente de teste (os testes usam um banco em memória escrito a partir das migrations; nenhum banco foi lido nem gravado) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário servidor já publicado no ambiente de teste (commit 6dc669f, sem as rotas das fotos e sem a variável do interruptor) variante rotas novas e interruptor em vigor nele NÃO coberta nesta PR (pendência da audit 2026-10-11)
 */
import { readFileSync } from 'node:fs'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { hashMobileRequest } from '@/lib/mobile-api/idempotency'
import { SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV } from '@/lib/mobile-api/signup-body-photo-switch'
import {
  AUTHENTICATION,
  databaseTimestamp,
  type MemoryAccount,
  SignupBodyPhotoMemoryDb,
  sha256Hex,
} from '@/lib/mobile-api/testing/signup-body-photo-memory-db'
import { GET } from '../route'
import { POST as CONSENT } from './route'

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

const ACCOUNT = '00000000-0000-4000-8000-000000000311'
const AUTH_USER = '00000000-0000-4000-8000-000000000312'
const TOKEN = 'token-of-the-account'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
const BASE = 'https://bodyflow.test/api/mobile/v1/onboarding/body-photos'
const CONSENT_KEY = 'body_photo_estimate_consent'

/** 12:00 of 2026-10-11 in America/Sao_Paulo. */
const NOW = new Date('2026-10-11T15:00:00.000Z')
/** Turns 18 on 2026-10-11: the minimum age is met on that very day. */
const BIRTHDAY_TODAY = '2008-10-11'
/** One day short of 18 on 2026-10-11. */
const ONE_DAY_SHORT = '2008-10-12'

/** NOT the text of the app: the owner still has to approve the real one. */
const CONSENT_FIXTURE =
  'TEXTO DE TESTE — não é o texto do consentimento do app. Fotos do corpo: frente, lado e costas.'
const VERSION = 'teste-2026-10-11.1'
const BODY_HASH = sha256Hex(CONSENT_FIXTURE)

function db(): SignupBodyPhotoMemoryDb {
  return world.db as SignupBodyPhotoMemoryDb
}

function newDatabase(account: Partial<MemoryAccount> = {}): SignupBodyPhotoMemoryDb {
  const database = new SignupBodyPhotoMemoryDb().addAccount({
    id: ACCOUNT,
    authUserId: AUTH_USER,
    token: TOKEN,
    ...account,
  })
  // Real auth bootstrap ensures this row before serving the request.
  // 20260720020351_p0_email_first_patient_identity.sql:201, ON CONFLICT DO NOTHING.
  database.profiles.set(ACCOUNT, { onboarding_completed: false, onboarding_completed_at: null })
  database.now = () => new Date()
  world.db = database
  return database
}

function publishFixture(overrides: { version?: string; body?: string; locale?: string } = {}) {
  return db().publishDocument({
    documentKey: CONSENT_KEY,
    version: overrides.version ?? VERSION,
    locale: overrides.locale ?? 'pt-BR',
    body: overrides.body ?? CONSENT_FIXTURE,
    requiredFrom: '2026-01-01T00:00:00.000Z',
  })
}

function getState(): Promise<Response> {
  return GET(new Request(BASE, { headers: { authorization: `Bearer ${TOKEN}` } }))
}

interface ConsentCall {
  body?: unknown
  key?: string | null
}

function consentBody(overrides: Record<string, unknown> = {}) {
  return { version: VERSION, body_hash: BODY_HASH, birth_date: BIRTHDAY_TODAY, ...overrides }
}

function accept({ body = consentBody(), key = 'body-photo-consent-0001' }: ConsentCall = {}) {
  const headers: Record<string, string> = {
    authorization: `Bearer ${TOKEN}`,
    'content-type': 'application/json',
  }
  if (key) headers['idempotency-key'] = key
  return CONSENT(
    new Request(`${BASE}/consent`, { method: 'POST', headers, body: JSON.stringify(body) }),
  )
}

async function errorOf(response: Response) {
  return { status: response.status, code: (await response.json()).error?.code }
}

const EMPTY_POSES = [
  { pose: 'front', photo: null },
  { pose: 'side', photo: null },
  { pose: 'back', photo: null },
]

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(NOW)
  newDatabase()
  world.queue.length = 0
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING_REF}.supabase.co`)
  vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, STAGING_REF)
})

afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllEnvs()
  vi.restoreAllMocks()
})

describe('GET /onboarding/body-photos with the switch on — the state', () => {
  it('an account that has not completed the sign-up and has no paid access reads the current text with its version and mark, no acceptance, three empty poses, no estimate and the minimum age', async () => {
    publishFixture()

    const response = await getState()

    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      available: true,
      unavailable_reason: null,
      consent: {
        document_key: 'body_photo_estimate_consent',
        version: VERSION,
        locale: 'pt-BR',
        body: CONSENT_FIXTURE,
        body_hash: BODY_HASH,
        accepted_at: null,
      },
      minimum_age: 18,
      poses: EMPTY_POSES,
      estimate: null,
      remaining_uploads: 9,
    })
    // Never the paid-access lookup: the fake database throws on it.
    expect(db().operations).not.toContain('rpc:resolve_user_entitlement')
    expect(db().operationsAfterAuthentication().slice(0, 3)).toEqual([
      'rpc:get_mobile_legal_document',
      'select:user_profiles',
      'select:user_legal_acceptances',
    ])
    expect(db().calls.find((call) => call.operation === 'rpc:get_mobile_legal_document')).toEqual({
      operation: 'rpc:get_mobile_legal_document',
      detail: { p_user_id: ACCOUNT, p_document_key: 'body_photo_estimate_consent' },
    })
  })

  it.each([
    ['no row of the document exists', () => undefined, {}],
    [
      'the document exists only in another language (en-US) and the account is pt-BR',
      () => publishFixture({ locale: 'en-US' }),
      {},
    ],
    [
      'the account is en-US and the document exists only in pt-BR',
      () => publishFixture(),
      { locale: 'en-US' },
    ],
    ['the account has a language outside the two', () => publishFixture(), { locale: 'es-ES' }],
    ['the account has no language', () => publishFixture(), { locale: null }],
    [
      'the only row is not in force yet (required from tomorrow)',
      () =>
        db().publishDocument({
          documentKey: CONSENT_KEY,
          version: VERSION,
          locale: 'pt-BR',
          body: CONSENT_FIXTURE,
          requiredFrom: '2026-10-12T15:00:00.000Z',
        }),
      {},
    ],
  ] satisfies [
    string,
    () => unknown,
    Partial<MemoryAccount>,
  ][])('without a text for the account: %s → not available, consent_text_missing, and nothing else is asked', async (_label, arrange, account) => {
    newDatabase(account)
    arrange()

    const response = await getState()

    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      available: false,
      unavailable_reason: 'consent_text_missing',
      consent: null,
      minimum_age: 18,
      poses: EMPTY_POSES,
      estimate: null,
      remaining_uploads: 0,
    })
    expect(db().operationsAfterAuthentication()).toEqual(['rpc:get_mobile_legal_document'])
  })

  it('the text shown is the newest in force, and an acceptance of the earlier version does not count for it', async () => {
    publishFixture()
    expect((await accept()).status).toBe(200)
    const newer = 'TEXTO DE TESTE — segunda versão, também não é o texto do app.'
    db().publishDocument({
      documentKey: CONSENT_KEY,
      version: 'teste-2026-10-11.2',
      locale: 'pt-BR',
      body: newer,
      requiredFrom: '2026-10-11T14:00:00.000Z',
    })

    const state = (await (await getState()).json()).data

    expect(state.consent).toEqual({
      document_key: 'body_photo_estimate_consent',
      version: 'teste-2026-10-11.2',
      locale: 'pt-BR',
      body: newer,
      body_hash: sha256Hex(newer),
      accepted_at: null,
    })
  })

  it('a document that cannot be read is not answered as "missing": 500, and the log line carries no personal data', async () => {
    publishFixture()
    const logged = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    db().failNext('rpc:get_mobile_legal_document', {
      code: '57014',
      message: `timeout reading consent of ${ACCOUNT}`,
    })

    expect(await errorOf(await getState())).toEqual({ status: 500, code: 'data_access_failed' })

    expect(logged).toHaveBeenCalledTimes(1)
    expect(JSON.stringify(logged.mock.calls)).not.toContain(ACCOUNT)
    expect(logged.mock.calls[0]).toEqual([
      '[mobile-signup-body-photos] operation_failed',
      { request_id: expect.any(String), operation: 'get_consent', database_code: 'unknown_error' },
    ])
  })

  it('an acceptance that cannot be read is 500, not "never accepted"', async () => {
    publishFixture()
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    db().failNext('select:user_legal_acceptances')

    expect(await errorOf(await getState())).toEqual({ status: 500, code: 'data_access_failed' })
  })
})

describe('POST /onboarding/body-photos/consent — accepting', () => {
  beforeEach(() => {
    publishFixture()
  })

  it('the version and mark shown, with a birth date of the minimum age, are recorded at once: 200 with the time, and the state shows it', async () => {
    const response = await accept()

    expect(response.status).toBe(200)
    const acceptedAt = databaseTimestamp(NOW)
    expect((await response.json()).data).toEqual({
      document_key: 'body_photo_estimate_consent',
      version: VERSION,
      accepted_at: acceptedAt,
    })
    expect(db().legalAcceptances).toEqual([
      {
        user_id: ACCOUNT,
        legal_document_id: db().legalDocuments[0]?.id,
        document_key: 'body_photo_estimate_consent',
        version: VERSION,
        locale: 'pt-BR',
        body_hash: BODY_HASH,
        accepted_at: acceptedAt,
      },
    ])
    expect(
      db().calls.find((call) => call.operation === 'rpc:accept_mobile_legal_document'),
    ).toEqual({
      operation: 'rpc:accept_mobile_legal_document',
      detail: {
        p_user_id: ACCOUNT,
        p_document_key: 'body_photo_estimate_consent',
        p_version: VERSION,
        p_body_hash: BODY_HASH,
        p_idempotency_key: 'body-photo-consent-0001',
      },
    })

    const state = (await (await getState()).json()).data
    expect(state.consent.accepted_at).toBe(acceptedAt)
    expect(state.available).toBe(true)
    expect(world.queue).toEqual([])
  })

  it('the same key repeated answers the same, and one acceptance exists', async () => {
    const first = await accept()
    vi.setSystemTime(new Date(NOW.getTime() + 60_000))
    const second = await accept()

    expect(second.status).toBe(200)
    expect(second.headers.get('idempotency-replayed')).toBe('true')
    expect((await second.json()).data).toEqual((await first.json()).data)
    expect(db().legalAcceptances).toHaveLength(1)
    expect(
      db().operations.filter((name) => name === 'rpc:accept_mobile_legal_document'),
    ).toHaveLength(1)
  })

  it('another key after the acceptance answers the time of the FIRST acceptance: the record is not written again', async () => {
    const first = (await (await accept()).json()).data
    vi.setSystemTime(new Date(NOW.getTime() + 60_000))

    const second = await accept({ key: 'body-photo-consent-0002' })

    expect(second.status).toBe(200)
    expect((await second.json()).data).toEqual(first)
    expect(db().legalAcceptances).toHaveLength(1)
  })

  it.each([
    ['another version', { version: 'teste-2026-10-10.9' }],
    ['another mark of the text', { body_hash: sha256Hex('outro texto') }],
  ])('%s than the current one is refused with 409 body_photo_consent_version_stale and no acceptance is recorded', async (_label, wrong) => {
    const response = await accept({ body: consentBody(wrong) })

    expect(await errorOf(response)).toEqual({
      status: 409,
      code: 'body_photo_consent_version_stale',
    })
    expect(db().legalAcceptances).toEqual([])
    expect(db().mutationReceipts).toEqual([])
    expect((await (await getState()).json()).data.consent.accepted_at).toBeNull()
  })

  it('a text that stopped being the current one between the reading and the acceptance is refused the same way', async () => {
    db().publishDocument({
      documentKey: CONSENT_KEY,
      version: 'teste-2026-10-11.2',
      locale: 'pt-BR',
      body: 'TEXTO DE TESTE — segunda versão, também não é o texto do app.',
      requiredFrom: '2026-10-11T14:00:00.000Z',
    })

    expect(await errorOf(await accept())).toEqual({
      status: 409,
      code: 'body_photo_consent_version_stale',
    })
    expect(db().legalAcceptances).toEqual([])
  })

  it('with no text in force the acceptance is refused as a stale version (409) and nothing is recorded: the database function does not tell "no text" from "another version"', async () => {
    newDatabase()

    expect(await errorOf(await accept())).toEqual({
      status: 409,
      code: 'body_photo_consent_version_stale',
    })
    expect(db().legalAcceptances).toEqual([])
    expect(db().mutationReceipts).toEqual([])
    // Reading the state again, as the refusal asks, says the photos are not available.
    expect((await (await getState()).json()).data).toMatchObject({
      available: false,
      unavailable_reason: 'consent_text_missing',
    })
  })

  it.each([
    ['a language outside the two', 'es-ES'],
    ['no language', null],
  ])('an account with %s has no text it could accept: 404 body_photos_unavailable, nothing recorded', async (_label, locale) => {
    newDatabase({ locale })
    publishFixture()

    expect(await errorOf(await accept())).toEqual({ status: 404, code: 'body_photos_unavailable' })
    expect(db().legalAcceptances).toEqual([])
    expect(db().mutationReceipts).toEqual([])
  })

  it('the Idempotency-Key is required, and without it nothing is asked', async () => {
    expect(await errorOf(await accept({ key: null }))).toEqual({
      status: 400,
      code: 'missing_idempotency_key',
    })
    expect(db().operations).toEqual(AUTHENTICATION)
  })

  it.each([
    ['no version', { version: undefined }],
    ['a version outside the alphabet of a version', { version: 'versão 1' }],
    ['a mark that is not 64 lowercase hexadecimal characters', { body_hash: 'A'.repeat(64) }],
    ['no birth date', { birth_date: undefined }],
    ['a birth date that is not a date', { birth_date: '2008-02-30' }],
    ['a birth date in another format', { birth_date: '11/10/2008' }],
    ['a field nobody asked for', { accepted: true }],
  ])('%s is 422 validation_failed and nothing is asked', async (_label, wrong) => {
    expect(await errorOf(await accept({ body: consentBody(wrong) }))).toEqual({
      status: 422,
      code: 'validation_failed',
    })
    expect(db().operations).toEqual(AUTHENTICATION)
  })

  it('the same key used for another version is 409 idempotency_key_conflict, at the ledger and at the function', async () => {
    expect((await accept()).status).toBe(200)

    // The ledger of the API answers first.
    expect(
      await errorOf(await accept({ body: consentBody({ version: 'teste-2026-10-10.9' }) })),
    ).toEqual({ status: 409, code: 'idempotency_key_conflict' })

    // After the ledger forgot the key (24 hours), the function's own receipt answers.
    db().ledger.length = 0
    expect(
      await errorOf(await accept({ body: consentBody({ version: 'teste-2026-10-10.9' }) })),
    ).toEqual({ status: 409, code: 'idempotency_key_conflict' })
    expect(db().legalAcceptances).toHaveLength(1)
  })

  it('a failure of the function is 500 with a log line that carries no personal data, and the key can be used again', async () => {
    const logged = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    db().failNext('rpc:accept_mobile_legal_document', {
      code: '08006',
      message: `connection lost for ${ACCOUNT} born ${BIRTHDAY_TODAY}`,
    })

    expect(await errorOf(await accept())).toEqual({ status: 500, code: 'data_access_failed' })
    expect(JSON.stringify(logged.mock.calls)).not.toContain(ACCOUNT)
    expect(JSON.stringify(logged.mock.calls)).not.toContain(BIRTHDAY_TODAY)
    expect(logged.mock.calls[0]).toEqual([
      '[mobile-signup-body-photos] operation_failed',
      {
        request_id: expect.any(String),
        operation: 'accept_consent',
        database_code: 'unknown_error',
      },
    ])

    expect((await accept()).status).toBe(200)
    expect(db().legalAcceptances).toHaveLength(1)
  })
})

describe('POST /onboarding/body-photos/consent — the minimum age (18, by the declared birth date)', () => {
  beforeEach(() => {
    publishFixture()
  })

  it('EXACT: a birth date one day short of 18 is refused with 403 body_photo_age_not_allowed and nothing at all is recorded', async () => {
    const response = await accept({ body: consentBody({ birth_date: ONE_DAY_SHORT }) })

    expect(response.status).toBe(403)
    expect((await response.json()).error).toMatchObject({
      code: 'body_photo_age_not_allowed',
      details: { minimum_age: 18 },
    })
    // Not a query after the authentication of the request: no acceptance, no
    // receipt, not even a reserved key.
    expect(db().operations).toEqual(AUTHENTICATION)
    expect(db().legalAcceptances).toEqual([])
    expect(db().mutationReceipts).toEqual([])
    expect(db().ledger).toEqual([])
    expect((await (await getState()).json()).data.consent.accepted_at).toBeNull()
  })

  it('EXACT: on the day of the 18th birthday the acceptance is taken', async () => {
    const response = await accept({ body: consentBody({ birth_date: BIRTHDAY_TODAY }) })

    expect(response.status).toBe(200)
    expect(db().legalAcceptances).toHaveLength(1)
  })

  it('the birth date is in no write and in no log: not in a query, not in the ledger, not in the acceptance, not in a receipt', async () => {
    const consoles = (['error', 'warn', 'info', 'log', 'debug'] as const).map((level) =>
      vi.spyOn(console, level).mockImplementation(() => undefined),
    )

    expect((await accept({ body: consentBody({ birth_date: ONE_DAY_SHORT }) })).status).toBe(403)
    const accepted = await accept({ body: consentBody({ birth_date: BIRTHDAY_TODAY }) })
    expect(accepted.status).toBe(200)

    const everythingKept = JSON.stringify({
      calls: db().calls,
      ledger: db().ledger,
      acceptances: db().legalAcceptances,
      receipts: db().mutationReceipts,
      queue: world.queue,
      answer: await accepted.json(),
      logs: consoles.map((spy) => spy.mock.calls),
    })
    for (const date of [ONE_DAY_SHORT, BIRTHDAY_TODAY, '20081012', '20081011', '2008-10']) {
      expect(everythingKept, date).not.toContain(date)
    }
    // What the ledger hashes is the acceptance without the date: the hash of
    // a date of birth can be undone by trying every day of a century.
    expect(db().ledger).toHaveLength(1)
    expect(db().ledger[0]?.request_hash).toBe(
      hashMobileRequest({
        document_key: 'body_photo_estimate_consent',
        version: VERSION,
        body_hash: BODY_HASH,
      }),
    )
    expect(db().ledger[0]?.request_hash).not.toBe(hashMobileRequest(consentBody()))
    for (const spy of consoles) expect(spy).not.toHaveBeenCalled()
  })

  it('the day is the one of the account time zone: at 22:30 of the eve in São Paulo the person is still 17; the same instant in Tokyo is already the birthday', async () => {
    // 2026-10-12T01:30Z = 2026-10-11 22:30 in America/Sao_Paulo = 2026-10-12 10:30 in Asia/Tokyo.
    vi.setSystemTime(new Date('2026-10-12T01:30:00.000Z'))
    const born = '2008-10-12'

    expect(await errorOf(await accept({ body: consentBody({ birth_date: born }) }))).toEqual({
      status: 403,
      code: 'body_photo_age_not_allowed',
    })

    newDatabase({ timezone: 'Asia/Tokyo' })
    publishFixture()
    expect((await accept({ body: consentBody({ birth_date: born }) })).status).toBe(200)
  })

  it.each([
    ['no time zone', null],
    ['a time zone that does not exist', 'Mars/Olympus_Mons'],
  ])('an account with %s is counted on the day of America/Sao_Paulo', async (_label, timezone) => {
    vi.setSystemTime(new Date('2026-10-12T01:30:00.000Z'))
    newDatabase({ timezone })
    publishFixture()

    expect(
      await errorOf(await accept({ body: consentBody({ birth_date: '2008-10-12' }) })),
    ).toEqual({ status: 403, code: 'body_photo_age_not_allowed' })
    expect((await accept({ body: consentBody({ birth_date: '2008-10-11' }) })).status).toBe(200)
  })

  it('someone born on 29 February completes 18 on 1 March of a year without that day, not on 28 February', async () => {
    const born = '2008-02-29'
    vi.setSystemTime(new Date('2026-02-28T15:00:00.000Z'))
    expect(await errorOf(await accept({ body: consentBody({ birth_date: born }) }))).toEqual({
      status: 403,
      code: 'body_photo_age_not_allowed',
    })

    vi.setSystemTime(new Date('2026-03-01T15:00:00.000Z'))
    expect((await accept({ body: consentBody({ birth_date: born }) })).status).toBe(200)
  })

  it.each([
    ['a child (born 2015-06-01)', '2015-06-01'],
    ['a birth date in the future', '2030-01-01'],
    ['17 years and 364 days', '2008-10-12'],
  ])('%s is refused; and an adult born decades ago is taken', async (_label, born) => {
    expect(await errorOf(await accept({ body: consentBody({ birth_date: born }) }))).toEqual({
      status: 403,
      code: 'body_photo_age_not_allowed',
    })
    expect((await accept({ body: consentBody({ birth_date: '1982-03-04' }) })).status).toBe(200)
  })

  it('the age is checked before the text is compared: an under-age request with a stale version is 403, and it leaves nothing', async () => {
    const response = await accept({
      body: consentBody({ birth_date: ONE_DAY_SHORT, version: 'teste-2026-10-10.9' }),
    })

    expect(await errorOf(response)).toEqual({ status: 403, code: 'body_photo_age_not_allowed' })
    expect(db().operations).toEqual(AUTHENTICATION)
  })
})

describe('declared pendencies of this package', () => {
  it('every "RC P-PHOTOS" line of this header is in docs/mobile/api-v1.md, identical, in the mandatory wording', () => {
    const header = readFileSync(new URL(import.meta.url), 'utf8')
    const doc = readFileSync(
      new URL('../../../../../../../../../../docs/mobile/api-v1.md', import.meta.url),
      'utf8',
    )
    const fromHeader = Array.from(
      header.matchAll(/^ \* (> RC P-PHOTOS — .*)$/gm),
      (match) => match[1] ?? '',
    )
    const fromDoc = Array.from(doc.matchAll(/^(> RC P-PHOTOS — .*)$/gm), (match) => match[1] ?? '')

    expect(fromHeader).toHaveLength(7)
    for (const line of fromHeader) {
      expect(line).toMatch(
        /^> RC P-PHOTOS — cenário .+ variante .+ NÃO coberta nesta PR \(pendência da audit 2026-10-11\)$/,
      )
      expect(fromDoc, line).toContain(line)
    }
  })

  it('the docs say whose decision the minimum age and the switch are, and never as an approval', () => {
    const doc = readFileSync(
      new URL('../../../../../../../../../../docs/mobile/api-v1.md', import.meta.url),
      'utf8',
    ).replace(/\s+/g, ' ')
    const start = doc.indexOf('## Fotos do corpo no cadastro')
    const section = doc.slice(start, doc.indexOf('## Rascunhos de plano', start))

    expect(start).toBeGreaterThan(-1)
    expect(section).toContain('### Consentimento próprio e idade mínima')
    expect(
      section.match(
        /decisão do orquestrador, anunciada ao dono em 2026-10-10\/11, que pode riscar qualquer uma/gi,
      )?.length ?? 0,
    ).toBeGreaterThanOrEqual(2)
    expect(section).toContain('O texto do consentimento não faz parte desta mudança')
    expect(section).not.toMatch(/aprovad[oa] pelo (?:dono|médico|Dr\.)/i)
  })
})
