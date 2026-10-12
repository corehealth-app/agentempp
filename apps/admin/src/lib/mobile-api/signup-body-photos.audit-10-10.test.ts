/**
 * Audit 2026-10-10 — the sign-up did not ask for the body photos: what the
 * app's server does about it in update 2, package B2 (docs/mobile/api-v1.md,
 * "Fotos do corpo no cadastro"): it RECEIVES one photo per pose, completes
 * the upload, replaces one pose and deletes everything. B3 now requests
 * reading after the current consent and open sign-up checks; the per-case
 * queue assertions below were changed deliberately in the same B3 commit.
 *
 * This file is the audit golden of the server part. It lives here, and not in
 * packages/agent/src/__golden__, because the behaviour belongs to the app's
 * server and the shared engine takes no part in it: importing the routes from
 * the engine package would invert the dependency.
 *
 * THE REPORT, exact. On 2026-10-10 the physician did the sign-up on build
 * 1.0 (3) and wrote, in the project's group (18:55 and 18:59, the owner's
 * clock): "Comecei o cadastro. Ele perguntou qual era a gordura corporal",
 * "Não pediu as fotos" and "Não pediu mesmo as fotos pra cálculo de
 * percentual de gordura". The owner's instruction, the same day: "ele deve
 * aparece como no whatsapp, lembra? pedir as fotos". Nothing here is an
 * approval of the physician: it is what he saw and said.
 *
 * THE POINT OF THE REPORT, as a server scenario, exact: an account at step 2
 * of the sign-up (body data), which has not completed it, has no paid access
 * and has not accepted the consent of the photos, asks to create the photo of
 * the front pose (`image/jpeg`, 480000 bytes).
 *   before: there was no such route (404 of the framework on build 3's
 *           server; the skeleton of package B0 answers 404
 *           `body_photos_unavailable`).
 *   now:    403 `body_photo_consent_required`; nothing is created and the
 *           storage is not called. With the consent accepted the photo is
 *           created in the bucket of body photos, with the pose kept as one
 *           of three fixed sentences in the photo's private context.
 *
 * WHAT THE REST OF THE FILE LOCKS: only image/jpeg up to 15 MiB and the three
 * poses; a repeated Idempotency-Key gives the SAME photo and a new upload
 * ticket, deletes nothing and does not count in the limit; a second photo of
 * a pose does not delete the first, and only the completion of the new upload
 * does; a new upload that fails leaves the earlier photo alone; the limit of
 * 9 creations in 24 hours counts the deleted ones and the ones never
 * uploaded; an account that completed the sign-up cannot create or complete,
 * while GET ON/DELETE use B4a repair: unresolved live photos return503.
 * The completion checks stored size/type; known open profiles keep B2
 * deletion of objects/rows/results OFF or ON. Only deleted tombstones of
 * completed profiles allow byte repair without provenance/new marks.
 * No answer carries the context, a
 * reading result or notes. Only explicitly successful uploaded completions
 * declare the exact reading events; every other case requires an empty queue.
 *
 * ADDED IN THE ANSWER TO THE REVIEW OF 2026-10-11 (round 1), each with the
 * exact scenario the reviewer ran:
 *   - finding 1 (LB1 to LB5, LB7 to LB9, and D2 changed on purpose): bytes
 *     that arrive at the path of a photo AFTER it was deleted — the upload
 *     ticket is valid for two hours and cannot be revoked — are removed by
 *     the next DELETE, with the switch in any position and with no time
 *     window. Before the fix the next DELETE answered 200 {deleted: 0} and
 *     the object stayed. The list DELETE reads is one page, the photos not
 *     deleted first: rows already deleted never leave a live photo out (LB9).
 *   - finding 3 (LB6): deleting again DOES call the storage, for every photo
 *     of the sign-up the account ever created; only the answer and the writes
 *     are idempotent.
 *   - finding 2 (R7): an open repeated Idempotency-Key can renew its ticket.
 *     Task4 changes R8 deliberately: a closed replay cannot renew a ticket;
 *     an undeclared closed scope still refuses cleanup and preserves bytes.
 *   - finding 4 (I1, I2): the acceptance and the sign-up of another account
 *     are never read as the account's own.
 *   - finding 5 (X1): the generic completion of media stores a pending photo
 *     of the sign-up without the checks of these routes. A DECLARED GAP, in
 *     an RC line; it is not closed here.
 *
 * WHOSE DECISIONS. The owner (2026-10-10): the sign-up asks for the body
 * photos. Orchestrator's, announced to the owner on 2026-10-10/11, who can
 * strike any of them: the minimum age, the photos being deleted when the
 * sign-up is completed (NOT in this package), abandoned sign-ups staying as
 * they are, and the switch being born off. The limit of 9 is a number of the
 * plan that waits for the owner's confirmation. None of these is an approval
 * of the owner in writing nor of the physician.
 *
 * WHAT RUNS. The exported route functions of the three route files, with the
 * real route wrapper (authentication and the access gate), the real handlers,
 * service, adapters, media service and idempotency code. Replaced: the
 * database client factory (an in-memory database and storage written from
 * the migrations, which throw on any query nobody declared) and the queue
 * client (it records what is sent). The clock is fixed.
 *
 * ASSUMED — declared: only the words above are in the report. Account, ids,
 * sizes, instants, version and the consent text (a TEST text, not the app's)
 * are synthetic. No database or storage was read or written, nothing was
 * published.
 *
 * > RC P-PHOTOS — cenário cadastro do médico em 2026-10-10 no build 1.0 (3) ("Comecei o cadastro. Ele perguntou qual era a gordura corporal" e "Não pediu as fotos") variante o cadastro pedir as três fotos e estimar o percentual por elas de ponta a ponta (B2 recebe, guarda, troca e apaga; B3 pede leitura após o aceite próprio com o interruptor ligado; a junção/uso, as telas e a conferência física ainda não estão concluídos) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário foto do corpo com envio concluído variante a leitura real por IA e a estimativa integrada das três poses (B3 emite o pedido; B4b junta três slots por média aritmética em testes locais, sem expor leituras individuais; confirmação/uso atômico, UI e fila/provedor reais ainda não foram verificados) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário cadastro concluído com fotos enviadas variante o servidor apagar as fotos na conclusão (decisão D4 do orquestrador, anunciada ao dono; B4a tem hook e mecânica locais, mas o resolver real segue deferred_rule; foto viva fica pendente e GET/DELETE de cadastro concluído respondem 503 até B4b e a disposição explícita) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário cadastro abandonado depois do envio das fotos variante apagar as fotos sem a pessoa voltar (a data de guarda gravada é a de 730 dias da política genérica de mídia e a rotina de limpeza não está publicada no ambiente de teste) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário envio que chega ao armazenamento depois do último DELETE /onboarding/body-photos da conta, com o bilhete ainda válido de uma foto já apagada, trocada ou recusada (o bilhete de envio vale duas horas e não pode ser revogado) variante remover esse objeto sem que o app apague de novo ou chame a conclusão do envio dessa foto (no perfil conhecido aberto, DELETE usa B2; no concluído só tombstones podem ter bytes reparados, enquanto foto viva não resolvida responde 503; o interruptor não impede DELETE no staging, mas nada roda sozinho depois dele, e conclusão OFF responde 404) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário conta com mais de 1000 linhas de foto do corpo no catálogo (só com fotos do cadastro, 112 dias no limite de 9 em 24 horas) variante o estado, a troca e a exclusão olharem além de uma página de 1000 linhas (a exclusão lê primeiro as linhas não apagadas e depois as apagadas mais recentemente: bytes que chegaram ao caminho de uma foto apagada há mais tempo que essas não são removidos, e com mais de 1000 linhas não apagadas uma foto viva pode ficar fora da página) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário repetição da Idempotency-Key de uma foto com envio ainda pendente, depois de entrar em vigor um texto do consentimento que a conta não aceitou ou depois de o cadastro ser concluído variante a repetição só entregar bilhete novo com o aceite em vigor e o cadastro não concluído (a chave é procurada antes das conferências, como o plano fixou, e a repetição responde 201 com bilhete novo, válido por mais duas horas a cada vez; a conclusão do envio continua recusada com 403 ou 409; perfil aberto usa exclusão B2, mas concluído com foto viva não resolvida tem DELETE 503 e preserva os bytes; mudar a ordem da repetição é decisão do orquestrador, ainda não tomada) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário duas criações ou duas conclusões da mesma conta no mesmo instante variante limite de 9 em 24 horas e troca da pose garantidos por trava no banco (as conferências são leituras seguidas de escrita, sem transação; duas criações simultâneas podem passar juntas do limite e duas conclusões simultâneas podem deixar duas fotos guardadas na mesma pose, das quais o estado mostra a mais nova) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário muitas contas novas enviando fotos no mesmo dia variante teto total por dia (o limite é por conta e as rotas ficam fora do acesso pago; o freio é o interruptor) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário foto do corpo recebida pelo servidor variante remoção de metadados e conferência do conteúdo no servidor (a rota só aceita image/jpeg declarado e confere o tipo e o tamanho gravados; não reescreve a imagem nem confere que é uma foto de corpo, da pose pedida ou da dona da conta) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário foto do cadastro com envio pendente concluída pela rota genérica POST /media/:id/complete (exige acesso liberado, mas conclui sem conferir consentimento atual nem cadastro aberto; POST /media agora recusa entrada corporal e bilhete para tipo corporal persistido) variante recusar também essa conclusão genérica e exigir o consentimento nela (a recusa de complete ainda não está em nenhum pacote do plano) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 * > RC P-PHOTOS — cenário rotas de envio, conclusão e exclusão contra o banco, o armazenamento e a fila reais do ambiente de teste variante teste com Supabase e Inngest reais (os testes usam banco e armazenamento em memória escritos a partir das migrations; nenhum banco foi lido nem gravado e nada foi publicado) NÃO coberta nesta PR (pendência da audit 2026-10-11)
 */
import { readFileSync } from 'node:fs'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { POST as COMPLETE } from '@/app/api/mobile/v1/onboarding/body-photos/[id]/complete/route'
import { POST as CONSENT } from '@/app/api/mobile/v1/onboarding/body-photos/consent/route'
import { DELETE, GET, POST } from '@/app/api/mobile/v1/onboarding/body-photos/route'
import { completeMediaUpload } from '@/lib/mobile-api/media-service'
import { SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV } from '@/lib/mobile-api/signup-body-photo-switch'
import { createSupabaseMediaDependencies } from '@/lib/mobile-api/supabase-media'
import { createSupabaseSignupBodyPhotoDependencies } from '@/lib/mobile-api/supabase-signup-body-photos'
import {
  AUTHENTICATION,
  databaseTimestamp,
  type MemoryMediaAsset,
  SignupBodyPhotoMemoryDb,
  sha256Hex,
} from '@/lib/mobile-api/testing/signup-body-photo-memory-db'

/** Typed spy boundary only: keep the strict RPC model and call recording. */
class DeleteBoundaryMemoryDb extends SignupBodyPhotoMemoryDb {
  override rpc(name: string, params: Record<string, unknown>) {
    return super.rpc(name, params)
  }
}

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

const ACCOUNT = '00000000-0000-4000-8000-000000000321'
const AUTH_USER = '00000000-0000-4000-8000-000000000322'
const OTHER_ACCOUNT = '00000000-0000-4000-8000-000000000331'
const OTHER_AUTH_USER = '00000000-0000-4000-8000-000000000332'
const TOKEN = 'token-of-the-account'
const OTHER_TOKEN = 'token-of-another-account'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
const BASE = 'https://bodyflow.test/api/mobile/v1/onboarding/body-photos'
const BUCKET = 'body-checkin-photos'
const HOUR = 60 * 60 * 1000

/** 12:00 of 2026-10-11 in America/Sao_Paulo. */
const NOW = new Date('2026-10-11T15:00:00.000Z')

/** NOT the text of the app: the owner still has to approve the real one. */
const CONSENT_FIXTURE =
  'TEXTO DE TESTE — não é o texto do consentimento do app. Fotos do corpo: frente, lado e costas.'
const VERSION = 'teste-2026-10-11.1'

/** The front photo of the report's scenario. */
const FRONT = { pose: 'front', mime_type: 'image/jpeg', size_bytes: 480_000 }

const POSE_SENTENCE = {
  front: 'Foto de frente.',
  side: 'Foto de lado.',
  back: 'Foto de costas.',
} as const
type Pose = keyof typeof POSE_SENTENCE

function db(): SignupBodyPhotoMemoryDb {
  return world.db as SignupBodyPhotoMemoryDb
}

let keySequence = 0
function newKey(label: string): string {
  keySequence += 1
  return `body-photo-${label}-${String(keySequence).padStart(4, '0')}`
}

interface Call {
  body?: unknown
  key?: string | null
  token?: string
}

function request(method: string, path: string, { body, key, token = TOKEN }: Call): Request {
  const headers: Record<string, string> = { authorization: `Bearer ${token}` }
  if (key) headers['idempotency-key'] = key
  if (body !== undefined) headers['content-type'] = 'application/json'
  return new Request(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

async function readState(token = TOKEN) {
  const response = await GET(request('GET', '', { token }))
  expect(response.status).toBe(200)
  return (await response.json()).data
}

async function acceptConsent(version = VERSION, body = CONSENT_FIXTURE, token = TOKEN) {
  const response = await CONSENT(
    request('POST', '/consent', {
      body: { version, body_hash: sha256Hex(body), birth_date: '1990-05-20' },
      key: newKey('consent'),
      token,
    }),
  )
  expect(response.status).toBe(200)
}

function create(pose: string, call: Call & { size?: number } = {}): Promise<Response> {
  return POST(
    request('POST', '', {
      body: { pose, mime_type: 'image/jpeg', size_bytes: call.size ?? 480_000 },
      key: newKey('create'),
      ...call,
    }),
  )
}

async function created(pose: string, call: Call & { size?: number } = {}) {
  const response = await create(pose, call)
  expect(response.status).toBe(201)
  return (await response.json()).data as {
    photo: { id: string; pose: string; status: string; created_at: string }
    upload: {
      signed_url: string
      method: string
      headers: Record<string, string>
      expires_at: string
    } | null
    replayed: boolean
  }
}

interface ProcessingEvent {
  id: string
  name: 'media.asset.process.requested'
  data: { assetId: string; userId: string; requestId: string }
}
let expectedEvents: ProcessingEvent[] = []

function complete(id: string, call: Call & { expectReading?: boolean } = {}): Promise<Response> {
  const { expectReading = false, ...requestCall } = call
  const key = newKey('complete')
  if (expectReading) {
    const userId = requestCall.token === OTHER_TOKEN ? OTHER_ACCOUNT : ACCOUNT
    const requestId = sha256Hex((requestCall.key ?? key).trim())
    expectedEvents.push({
      id: `media-process:${id}:${requestId}`,
      name: 'media.asset.process.requested',
      data: { assetId: id, userId, requestId },
    })
  }
  return COMPLETE(request('POST', `/${id}/complete`, { key, ...requestCall }), {
    params: Promise.resolve({ id }),
  })
}

function remove(call: Call = {}): Promise<Response> {
  return DELETE(request('DELETE', '', { key: newKey('delete'), ...call }))
}

function rowOf(id: string): MemoryMediaAsset {
  const row = db().mediaAssets.find((entry) => entry.id === id)
  if (!row) throw new Error(`no catalogue row ${id}`)
  return row
}

function objectOf(id: string) {
  const row = rowOf(id)
  return db().objects.get(`${row.bucket_id}/${row.object_path}`)
}

/** What the app does with the ticket: the bytes arrive at the object's path. */
function upload(id: string, overrides: { size?: number; contentType?: string } = {}) {
  const row = rowOf(id)
  db().upload(row, { size: row.declared_size_bytes, contentType: 'image/jpeg', ...overrides })
}

/** A photo created, uploaded and completed: stored on the server. */
async function store(pose: Pose, size = 480_000): Promise<string> {
  const { photo } = await created(pose, { size })
  upload(photo.id)
  const response = await complete(photo.id, { expectReading: true })
  expect(response.status).toBe(200)
  return photo.id
}

async function errorOf(response: Response) {
  return { status: response.status, code: (await response.json()).error?.code }
}

/** Error/GET/DELETE wires never expose internal media, disposition or upload fields. */
function assertPrivate(payload: unknown): void {
  const wire = JSON.stringify(payload)
  expect(wire).not.toMatch(
    /"(?:bucket_id|object_path|processing_result|source_request_hash|processing_request_id|signup_origin|signup_disposition_version|signup_disposition_assigned|signup_upload_open|generation_token|sweep_no|cursor|manifest_count|remaining_count|estimate_proof|signed_url)"\s*:/,
  )
  expect(wire).not.toContain('https://storage.test/')
}

function operationsOf(prefix: string): string[] {
  return db().operations.filter((operation) => operation.startsWith(prefix))
}

/** What each call that removes stored objects carried, in order. */
function removals(): Array<{ bucketId: string; objectPaths: string[] }> {
  return db()
    .calls.filter((call) => call.operation === 'storage:remove')
    .map((call) => {
      const { bucketId, objectPaths } = call.detail as { bucketId: string; objectPaths: string[] }
      return { bucketId, objectPaths: [...objectPaths].sort() }
    })
}

/** A sign-up that was completed, as the profile holds it. */
const COMPLETED_SIGNUP = {
  onboarding_completed: true,
  onboarding_completed_at: '2026-10-11T14:30:00.000000+00:00',
}
const OPEN_SIGNUP = { onboarding_completed: false, onboarding_completed_at: null }

/** A second consent text, in force since before the clock of these tests. Also NOT the text of the app. */
function publishSecondConsentText() {
  db().publishDocument({
    documentKey: 'body_photo_estimate_consent',
    version: 'teste-2026-10-11.2',
    locale: 'pt-BR',
    body: 'TEXTO DE TESTE — segunda versão, também não é o texto do app.',
    requiredFrom: '2026-10-11T14:00:00.000Z',
  })
}

function seed(id: string, pose: Pose, overrides: Partial<MemoryMediaAsset> = {}) {
  return db().seedMediaAsset({
    id,
    user_id: ACCOUNT,
    signup_origin: true,
    context_text: POSE_SENTENCE[pose],
    ...overrides,
  })
}

const STORED_AT = databaseTimestamp(new Date(NOW.getTime() - HOUR))

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(NOW)
  keySequence = 0
  expectedEvents = []
  const database = new DeleteBoundaryMemoryDb()
    .addAccount({ id: ACCOUNT, authUserId: AUTH_USER, token: TOKEN })
    .addAccount({ id: OTHER_ACCOUNT, authUserId: OTHER_AUTH_USER, token: OTHER_TOKEN })
  database.now = () => new Date()
  // The account is in the middle of the sign-up: a profile that is not completed.
  database.profiles.set(ACCOUNT, { onboarding_completed: false, onboarding_completed_at: null })
  database.publishDocument({
    documentKey: 'body_photo_estimate_consent',
    version: VERSION,
    locale: 'pt-BR',
    body: CONSENT_FIXTURE,
    requiredFrom: '2026-01-01T00:00:00.000Z',
  })
  world.db = database
  world.queue.length = 0
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING_REF}.supabase.co`)
  vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, STAGING_REF)
})

afterEach(() => {
  // Zero by default. Allowed cases declare every exact event before the call.
  expect(world.queue).toEqual(expectedEvents)
  // And nothing here writes the profile or an event of the product.
  expect(
    db().operations.filter((operation) => /^(?:insert|update):(?!media_assets)/.test(operation)),
  ).toEqual([])
  vi.useRealTimers()
  vi.unstubAllEnvs()
  vi.restoreAllMocks()
})

describe('golden: the point of the report — creating the photo of a pose', () => {
  it('G1 EXACT: an account at step 2, without paid access and without the consent accepted, asks to create the front photo → 403 body_photo_consent_required, nothing created, storage not called', async () => {
    const response = await create(FRONT.pose, { size: FRONT.size_bytes })

    expect(response.status).toBe(403)
    expect((await response.json()).error).toMatchObject({
      code: 'body_photo_consent_required',
      message: 'Accept the body photo consent first',
    })
    expect(db().mediaAssets).toEqual([])
    expect(operationsOf('storage:')).toEqual([])
    expect(operationsOf('insert:')).toEqual([])
    // Never the paid-access lookup: the in-memory database throws on it.
    expect(db().operations).not.toContain('rpc:resolve_user_entitlement')
    expect((await readState()).poses.every((slot: { photo: unknown }) => slot.photo === null)).toBe(
      true,
    )
  })

  it('G2 with the consent accepted the same request creates a body photo in the body-photo bucket, with the pose kept as a fixed sentence, and hands an upload ticket', async () => {
    await acceptConsent()

    const data = await created(FRONT.pose, { size: FRONT.size_bytes, key: 'body-photo-front-0001' })

    expect(data).toEqual({
      photo: {
        id: expect.stringMatching(/^[0-9a-f-]{36}$/),
        pose: 'front',
        status: 'pending_upload',
        created_at: databaseTimestamp(NOW),
      },
      upload: {
        signed_url: expect.stringContaining('https://storage.test/object/upload/sign/'),
        method: 'PUT',
        headers: { 'Content-Type': 'image/jpeg', 'x-upsert': 'false' },
        expires_at: new Date(NOW.getTime() + 2 * HOUR).toISOString(),
      },
      replayed: false,
    })
    expect(db().mediaAssets).toHaveLength(1)
    expect(rowOf(data.photo.id)).toMatchObject({
      user_id: ACCOUNT,
      kind: 'body_checkin_photo',
      bucket_id: 'body-checkin-photos',
      object_path: `${ACCOUNT}/${data.photo.id}.jpg`,
      mime_type: 'image/jpeg',
      declared_size_bytes: 480_000,
      status: 'pending_upload',
      context_text: 'Foto de frente.',
      source_request_hash: sha256Hex('body-photo-front-0001'),
      // The generic date of body media (730 days): only a recorded date.
      retention_until: new Date(NOW.getTime() + 730 * 24 * HOUR).toISOString(),
      processing_result: null,
    })
    // The ticket is for that object and no other.
    expect(data.upload?.signed_url).toContain(`/${BUCKET}/${ACCOUNT}/${data.photo.id}.jpg?token=`)
  })

  it.each([
    ['front', 'Foto de frente.'],
    ['side', 'Foto de lado.'],
    ['back', 'Foto de costas.'],
  ] as const)('G3 the %s pose is kept as "%s" and read back from it', async (pose, sentence) => {
    await acceptConsent()

    const id = await store(pose)

    expect(rowOf(id).context_text).toBe(sentence)
    const state = await readState()
    expect(state.poses).toEqual(
      (['front', 'side', 'back'] as const).map((slot) => ({
        pose: slot,
        photo:
          slot === pose ? { id, status: 'uploaded', created_at: databaseTimestamp(NOW) } : null,
      })),
    )
  })

  it.each([
    ['a PNG', { mime_type: 'image/png' }],
    ['a HEIC', { mime_type: 'image/heic' }],
    ['more than 15 MiB', { size_bytes: 15 * 1024 * 1024 + 1 }],
    ['zero bytes', { size_bytes: 0 }],
    ['a size that is not a whole number', { size_bytes: 1200.5 }],
    ['a pose outside the three', { pose: 'three-quarters' }],
    ['no pose', { pose: undefined }],
    ['a context text of the client', { context_text: 'Foto de frente.' }],
    ['a media kind of the client', { kind: 'meal_photo' }],
  ])('G4 %s is 422 validation_failed and nothing is created', async (_label, wrong) => {
    await acceptConsent()

    const response = await POST(
      request('POST', '', { body: { ...FRONT, ...wrong }, key: newKey('create') }),
    )

    expect(await errorOf(response)).toEqual({ status: 422, code: 'validation_failed' })
    expect(db().mediaAssets).toEqual([])
    expect(operationsOf('storage:')).toEqual([])
  })

  it('G5 exactly 15 MiB of image/jpeg is accepted', async () => {
    await acceptConsent()

    const data = await created('side', { size: 15 * 1024 * 1024 })

    expect(rowOf(data.photo.id).declared_size_bytes).toBe(15_728_640)
  })

  it('G6 the consent of an EARLIER version does not open the upload once a newer text is in force', async () => {
    await acceptConsent()
    db().publishDocument({
      documentKey: 'body_photo_estimate_consent',
      version: 'teste-2026-10-11.2',
      locale: 'pt-BR',
      body: 'TEXTO DE TESTE — segunda versão, também não é o texto do app.',
      requiredFrom: '2026-10-11T14:00:00.000Z',
    })

    expect(await errorOf(await create('front'))).toEqual({
      status: 403,
      code: 'body_photo_consent_required',
    })
    expect(db().mediaAssets).toEqual([])
  })

  it('G7 without a text in force for the account, creating is 404 body_photos_unavailable', async () => {
    db().legalDocuments.length = 0

    expect(await errorOf(await create('front'))).toEqual({
      status: 404,
      code: 'body_photos_unavailable',
    })
    expect(db().mediaAssets).toEqual([])
  })

  it('G8 the Idempotency-Key is required', async () => {
    await acceptConsent()

    expect(await errorOf(await create('front', { key: null }))).toEqual({
      status: 400,
      code: 'missing_idempotency_key',
    })
    expect(db().mediaAssets).toEqual([])
  })
})

describe('repetition: the same Idempotency-Key', () => {
  beforeEach(() => acceptConsent())

  it('R1 twice gives ONE live photo, a NEW ticket on the second, the same count in the limit, and deletes nothing', async () => {
    const first = await created('front', { key: 'body-photo-repeat-0001' })
    const again = await create('front', { key: 'body-photo-repeat-0001' })

    expect(again.status).toBe(201)
    expect(again.headers.get('idempotency-replayed')).toBe('true')
    const second = (await again.json()).data
    expect(second.photo).toEqual(first.photo)
    expect(second.replayed).toBe(true)
    expect(second.upload.signed_url).not.toBe(first.upload?.signed_url)
    expect(second.upload.signed_url).toContain(`/${ACCOUNT}/${first.photo.id}.jpg?token=`)

    expect(db().mediaAssets).toHaveLength(1)
    expect(rowOf(first.photo.id).status).toBe('pending_upload')
    expect(operationsOf('storage:remove')).toEqual([])
    expect(operationsOf('update:')).toEqual([])
    expect((await readState()).remaining_uploads).toBe(8)
  })

  it('R2 the answer kept for repetition holds no upload address', async () => {
    await created('front', { key: 'body-photo-repeat-0002' })

    const kept = db().ledger.find((row) => row.idempotency_key === 'body-photo-repeat-0002')
    expect(kept).toMatchObject({
      state: 'completed',
      response_status: 201,
      response_body: { temporary_capability_redacted: true },
    })
    expect(JSON.stringify(db().ledger)).not.toContain('storage.test')
    expect(JSON.stringify(db().ledger)).not.toContain('token=')
  })

  it('R3 the key is looked up BEFORE the checks: with the limit reached, repeating an earlier key still answers its photo and counts nothing', async () => {
    const first = await created('front', { key: 'body-photo-repeat-0003' })
    for (let index = 0; index < 8; index += 1) await created('side')
    expect(await errorOf(await create('back'))).toEqual({
      status: 429,
      code: 'body_photo_limit_reached',
    })

    // The ledger of the API forgot the key (24 hours): the service finds the photo by the key itself.
    db().ledger.length = 0
    const again = await create('front', { key: 'body-photo-repeat-0003' })

    expect(again.status).toBe(201)
    expect((await again.json()).data.photo).toEqual(first.photo)
    expect(db().mediaAssets).toHaveLength(9)
  })

  it('R4 a repeated key after the upload was completed answers the photo with no ticket', async () => {
    const first = await created('front', { key: 'body-photo-repeat-0004' })
    upload(first.photo.id)
    expect((await complete(first.photo.id, { expectReading: true })).status).toBe(200)

    const again = (await (await create('front', { key: 'body-photo-repeat-0004' })).json()).data

    expect(again).toEqual({
      photo: { ...first.photo, status: 'uploaded' },
      upload: null,
      replayed: true,
    })
    expect(objectOf(first.photo.id)).toBeDefined()
  })

  it('R5 the same key for another pose or another size is 409 idempotency_key_conflict, at the ledger and at the service, and nothing is created', async () => {
    await created('front', { key: 'body-photo-repeat-0005' })

    expect(await errorOf(await create('side', { key: 'body-photo-repeat-0005' }))).toEqual({
      status: 409,
      code: 'idempotency_key_conflict',
    })
    db().ledger.length = 0
    expect(await errorOf(await create('side', { key: 'body-photo-repeat-0005' }))).toEqual({
      status: 409,
      code: 'idempotency_key_conflict',
    })
    db().ledger.length = 0
    expect(
      await errorOf(await create('front', { key: 'body-photo-repeat-0005', size: 480_001 })),
    ).toEqual({ status: 409, code: 'idempotency_key_conflict' })
    expect(db().mediaAssets).toHaveLength(1)
  })

  it('R6 a key that already belongs to another kind of media of the account is 409, never that media handed back as a body photo', async () => {
    db().seedMediaAsset({
      id: '00000000-0000-4000-8000-000000000601',
      user_id: ACCOUNT,
      kind: 'meal_photo',
      context_text: 'Jantar.',
      source_request_hash: sha256Hex('body-photo-repeat-0006'),
    })

    expect(await errorOf(await create('front', { key: 'body-photo-repeat-0006' }))).toEqual({
      status: 409,
      code: 'idempotency_key_conflict',
    })
    expect(db().mediaAssets).toHaveLength(1)
  })

  // The two cases below lock what the server DOES, which is not what one would
  // wish: the repetition does not make the checks of a new photo again. It is
  // declared in an RC line, and changing it is the orchestrator's decision
  // (the plan fixed "the key first").
  it('R7 EXACT (review of 2026-10-11, round 1, finding 2): the account accepts version 1 and creates the front photo (pending); version 2 comes into force and it did not accept it; the same Idempotency-Key repeated → 201 with the SAME photo and a NEW ticket, valid for two more hours. The completion is still refused (403), the photo never becomes a stored one, and DELETE removes the bytes', async () => {
    const first = await created('front', { key: 'body-photo-repeat-0007' })
    publishSecondConsentText()
    // A NEW photo is refused: the acceptance in force is asked of it.
    expect(await errorOf(await create('side'))).toEqual({
      status: 403,
      code: 'body_photo_consent_required',
    })
    vi.setSystemTime(new Date(NOW.getTime() + 1.5 * HOUR))

    const again = await create('front', { key: 'body-photo-repeat-0007' })

    expect(again.status).toBe(201)
    const second = (await again.json()).data
    expect(second.photo).toEqual(first.photo)
    expect(second.replayed).toBe(true)
    expect(second.upload.signed_url).toContain(`/${ACCOUNT}/${first.photo.id}.jpg?token=`)
    expect(second.upload.signed_url).not.toBe(first.upload?.signed_url)
    // Each repetition, while the upload is pending, hands two more hours.
    expect(second.upload.expires_at).toBe(new Date(NOW.getTime() + 3.5 * HOUR).toISOString())
    expect(db().mediaAssets).toHaveLength(1)

    // The bytes can be put, and that is all: the upload is not completed.
    upload(first.photo.id)
    expect(await errorOf(await complete(first.photo.id))).toEqual({
      status: 403,
      code: 'body_photo_consent_required',
    })
    expect(rowOf(first.photo.id).status).toBe('pending_upload')
    expect((await readState()).poses[0].photo).toBeNull()
    expect((await (await remove()).json()).data).toEqual({ deleted: 1 })
    expect(objectOf(first.photo.id)).toBeUndefined()
  })

  it('R8 closed replay without a sealed scope is 409 with no new ticket; completion is refused and DELETE stays 503 with bytes intact', async () => {
    const first = await created('front', { key: 'body-photo-repeat-0008' })
    const pendingBefore = structuredClone(rowOf(first.photo.id))
    // Deliberately NOT a checked close: no private scope is declared here.
    db().profiles.set(ACCOUNT, COMPLETED_SIGNUP)
    expect(await errorOf(await create('side'))).toEqual({
      status: 409,
      code: 'onboarding_already_completed',
    })
    db().operations.length = 0
    db().calls.length = 0

    const again = await create('front', { key: 'body-photo-repeat-0008' })
    assertPrivate(await again.clone().json())
    expect(await errorOf(again)).toEqual({ status: 409, code: 'media_upload_not_pending' })
    expect(operationsOf('storage:createSignedUploadUrl')).toEqual([])
    expect(db().mediaAssets).toHaveLength(1)

    // The ticket originally handed before close can still deliver bytes.
    upload(first.photo.id)
    const bytesBefore = structuredClone(objectOf(first.photo.id))
    const completion = await complete(first.photo.id)
    assertPrivate(await completion.clone().json())
    expect(await errorOf(completion)).toEqual({
      status: 409,
      code: 'onboarding_already_completed',
    })
    const deletion = await remove()
    assertPrivate(await deletion.clone().json())
    expect(await errorOf(deletion)).toEqual({ status: 503, code: 'body_photo_cleanup_pending' })
    expect(bytesBefore).toBeDefined()
    expect(objectOf(first.photo.id)).toEqual(bytesBefore)
    expect(rowOf(first.photo.id)).toEqual(pendingBefore)
    expect(operationsOf('storage:')).toEqual([])
    expect(operationsOf('insert:media_assets')).toEqual([])
    expect(operationsOf('update:media_assets')).toEqual([])
    expect(operationsOf('rpc:get_mobile_signup_body_photo_disposition_page')).toEqual([])
    expect(operationsOf('rpc:commit_mobile_signup_body_photo_disposition_page')).toEqual([])
    expect(world.queue).toEqual([])
  })
})

describe('each account answers for itself: the acceptance and the sign-up of another account are never read as its own', () => {
  const tokenOf = (account: string) => (account === ACCOUNT ? TOKEN : OTHER_TOKEN)

  it('I1 ANOTHER account accepted the consent and this one did not: this one creating is 403 and its state shows no acceptance; the other one creates', async () => {
    db().profiles.set(OTHER_ACCOUNT, OPEN_SIGNUP)
    await acceptConsent(VERSION, CONSENT_FIXTURE, OTHER_TOKEN)
    expect(db().legalAcceptances.map((row) => row.user_id)).toEqual([OTHER_ACCOUNT])

    expect(await errorOf(await create('front'))).toEqual({
      status: 403,
      code: 'body_photo_consent_required',
    })
    expect(db().mediaAssets).toEqual([])
    expect((await readState()).consent.accepted_at).toBeNull()

    expect((await readState(OTHER_TOKEN)).consent.accepted_at).toBe(databaseTimestamp(NOW))
    expect((await create('front', { token: OTHER_TOKEN })).status).toBe(201)
    expect(db().mediaAssets.map((row) => row.user_id)).toEqual([OTHER_ACCOUNT])
  })

  it.each([
    ['the OTHER account completed its sign-up and this one did not', OTHER_ACCOUNT, ACCOUNT],
    ['THIS account completed its sign-up and the other one did not', ACCOUNT, OTHER_ACCOUNT],
  ])('I2 %s: only the one that completed is refused (409), creating a photo and completing an upload', async (_label, completedAccount, openAccount) => {
    const [completedToken, openToken] = [tokenOf(completedAccount), tokenOf(openAccount)]
    db().profiles.set(completedAccount, OPEN_SIGNUP)
    db().profiles.set(openAccount, OPEN_SIGNUP)
    await acceptConsent(VERSION, CONSENT_FIXTURE, completedToken)
    await acceptConsent(VERSION, CONSENT_FIXTURE, openToken)
    const pendingOfCompleted = await created('front', { token: completedToken })
    const pendingOfOpen = await created('front', { token: openToken })
    upload(pendingOfCompleted.photo.id)
    upload(pendingOfOpen.photo.id)

    db().profiles.set(completedAccount, COMPLETED_SIGNUP)

    expect(await errorOf(await create('side', { token: completedToken }))).toEqual({
      status: 409,
      code: 'onboarding_already_completed',
    })
    expect(
      await errorOf(await complete(pendingOfCompleted.photo.id, { token: completedToken })),
    ).toEqual({ status: 409, code: 'onboarding_already_completed' })
    expect((await create('side', { token: openToken })).status).toBe(201)
    expect(
      (await complete(pendingOfOpen.photo.id, { token: openToken, expectReading: true })).status,
    ).toBe(200)
    expect(rowOf(pendingOfCompleted.photo.id).status).toBe('pending_upload')
    expect(rowOf(pendingOfOpen.photo.id).status).toBe('uploaded')
  })
})

describe('the limit: 9 creations in 24 hours', () => {
  beforeEach(() => acceptConsent())

  it('L1 the 10th creation is 429 body_photo_limit_reached, counting the deleted photos and the ones never uploaded; 24 hours later it is open again', async () => {
    // Three stored, three stored and then deleted, three never uploaded.
    await store('front')
    await store('side')
    await store('back')
    expect((await (await remove()).json()).data).toEqual({ deleted: 3 })
    await store('front')
    await store('side')
    await store('back')
    await created('front')
    await created('side')
    await created('back')
    expect(db().mediaAssets).toHaveLength(9)
    expect(db().mediaAssets.filter((row) => row.status === 'deleted')).toHaveLength(3)
    expect((await readState()).remaining_uploads).toBe(0)

    const refused = await create('front')

    expect(refused.status).toBe(429)
    expect((await refused.json()).error).toMatchObject({
      code: 'body_photo_limit_reached',
      details: { limit: 9, window_hours: 24 },
    })
    expect(db().mediaAssets).toHaveLength(9)

    vi.setSystemTime(new Date(NOW.getTime() + 24 * HOUR + 1000))
    expect((await readState()).remaining_uploads).toBe(9)
    expect((await create('front')).status).toBe(201)
  })

  it('L2 the state counts down as photos are created, whatever becomes of them', async () => {
    expect((await readState()).remaining_uploads).toBe(9)
    await created('front')
    expect((await readState()).remaining_uploads).toBe(8)
    await store('side')
    expect((await readState()).remaining_uploads).toBe(7)
    await remove()
    expect((await readState()).remaining_uploads).toBe(7)
  })

  it('L3 the limit is of each account: another account is not counted', async () => {
    for (let index = 0; index < 9; index += 1) await created('front')
    db().profiles.set(OTHER_ACCOUNT, { onboarding_completed: false, onboarding_completed_at: null })
    const consent = await CONSENT(
      request('POST', '/consent', {
        body: { version: VERSION, body_hash: sha256Hex(CONSENT_FIXTURE), birth_date: '1990-05-20' },
        key: newKey('consent'),
        token: OTHER_TOKEN,
      }),
    )
    expect(consent.status).toBe(200)

    expect((await create('front', { token: OTHER_TOKEN })).status).toBe(201)
    expect((await readState(OTHER_TOKEN)).remaining_uploads).toBe(8)
  })
})

describe('the limit counts photos of the sign-up only', () => {
  beforeEach(() => acceptConsent())

  it('L4 body photos that carry no pose sentence, and other media even with a pose sentence as caption, do not count and are not shown', async () => {
    for (let index = 0; index < 5; index += 1) {
      db().seedMediaAsset({
        id: `00000000-0000-4000-8000-0000000004a${index}`,
        user_id: ACCOUNT,
        context_text: index === 0 ? null : 'Avaliação mensal.',
        status: 'uploaded',
        actual_size_bytes: 1200,
        uploaded_at: STORED_AT,
      })
    }
    db().seedMediaAsset({
      id: '00000000-0000-4000-8000-0000000004b0',
      user_id: ACCOUNT,
      kind: 'meal_photo',
      context_text: 'Foto de frente.',
      status: 'uploaded',
      actual_size_bytes: 1200,
      uploaded_at: STORED_AT,
    })

    const state = await readState()

    expect(state.remaining_uploads).toBe(9)
    expect(state.poses.every((slot: { photo: unknown }) => slot.photo === null)).toBe(true)
    for (let index = 0; index < 9; index += 1) expect((await create('front')).status).toBe(201)
    expect((await create('front')).status).toBe(429)
  })
})

describe('an account that already completed the sign-up', () => {
  beforeEach(() => acceptConsent())

  it.each([
    [
      'completed with its time',
      { onboarding_completed: true, onboarding_completed_at: '2026-10-11T14:30:00.000000+00:00' },
    ],
    [
      'an older account marked completed with no time',
      { onboarding_completed: true, onboarding_completed_at: null },
    ],
    [
      'a completion time with the mark still false',
      { onboarding_completed: false, onboarding_completed_at: '2026-10-11T14:30:00.000000+00:00' },
    ],
  ])('C1 B4a %s: unresolved photo finalization refuses GET/DELETE and preserves every object/result', async (_label, profile) => {
    const stored = await store('front')
    db().profiles.set(ACCOUNT, profile)

    expect(await errorOf(await create('side'))).toEqual({
      status: 409,
      code: 'onboarding_already_completed',
    })
    expect(db().mediaAssets).toHaveLength(1)

    const before = structuredClone(db().mediaAssets)
    db().operations.length = 0
    const get = await GET(request('GET', '', {}))
    const deletion = await remove()
    expect(await errorOf(get)).toEqual({ status: 503, code: 'body_photo_cleanup_pending' })
    expect(await errorOf(deletion)).toEqual({ status: 503, code: 'body_photo_cleanup_pending' })
    expect(db().mediaAssets).toEqual(before)
    expect(objectOf(stored)).toBeDefined()
    expect(operationsOf('storage:remove')).toEqual([])
    expect(operationsOf('update:')).toEqual([])
    expect(operationsOf('rpc:complete_mobile_api_request')).toEqual([])
  })

  it('C2 an upload still pending when the sign-up was completed cannot be completed either: 409, and the photo does not become a stored one', async () => {
    const { photo } = await created('front')
    upload(photo.id)
    db().profiles.set(ACCOUNT, {
      onboarding_completed: true,
      onboarding_completed_at: '2026-10-11T14:30:00.000000+00:00',
    })

    expect(await errorOf(await complete(photo.id))).toEqual({
      status: 409,
      code: 'onboarding_already_completed',
    })
    expect(rowOf(photo.id).status).toBe('pending_upload')
    // B4a preserves this live photo until a disposition is supplied.
    expect(await errorOf(await GET(request('GET', '', {})))).toEqual({
      status: 503,
      code: 'body_photo_cleanup_pending',
    })
    expect(await errorOf(await remove())).toEqual({
      status: 503,
      code: 'body_photo_cleanup_pending',
    })
    expect(objectOf(photo.id)).toBeDefined()
    expect(rowOf(photo.id).status).toBe('pending_upload')
  })

  it('C3 an account with no profile row cannot issue an upload ticket or insert a signup asset', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    db().profiles.delete(ACCOUNT)
    const before = structuredClone(db().mediaAssets)
    const response = await create('front')
    assertPrivate(await response.clone().json())
    expect(await errorOf(response)).toEqual({ status: 500, code: 'media_storage_failed' })
    expect(db().mediaAssets).toEqual(before)
    expect(operationsOf('storage:')).toEqual([])
    expect(world.queue).toEqual([])
  })

  it('C4 a profile that cannot be read creates nothing: 500, not "not completed"', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    db().failNext('select:user_profiles')

    expect(await errorOf(await create('front'))).toEqual({
      status: 500,
      code: 'data_access_failed',
    })
    expect(db().mediaAssets).toEqual([])
  })
})

describe('completing an upload', () => {
  beforeEach(() => acceptConsent())

  it('U1 the stored size and type are checked and the photo becomes stored: 200, in its pose, and the exact reading event leaves', async () => {
    const { photo } = await created('front')
    upload(photo.id)

    const response = await complete(photo.id, { expectReading: true })

    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({
      photo: { id: photo.id, pose: 'front', status: 'uploaded', created_at: photo.created_at },
    })
    expect(rowOf(photo.id)).toMatchObject({
      status: 'uploaded',
      actual_size_bytes: 480_000,
      uploaded_at: NOW.toISOString(),
      processing_request_id: null,
      processing_result: null,
    })
    expect(world.queue).toEqual(expectedEvents)
  })

  it.each([
    ['another size', { size: 479_999 }],
    ['another type', { contentType: 'image/png' }],
  ])('U2 an object of %s than declared is 422 media_upload_mismatch: the object is removed, the photo is a failed upload, and the same key replays the refusal', async (_label, wrong) => {
    const { photo } = await created('front')
    upload(photo.id, wrong)

    const first = await complete(photo.id, { key: 'body-photo-complete-mismatch' })

    expect(await errorOf(first)).toEqual({ status: 422, code: 'media_upload_mismatch' })
    expect(objectOf(photo.id)).toBeUndefined()
    expect(rowOf(photo.id)).toMatchObject({
      status: 'failed',
      failure_stage: 'upload',
      failure_code: 'metadata_mismatch',
    })
    expect((await readState()).poses[0].photo).toBeNull()

    const again = await complete(photo.id, { key: 'body-photo-complete-mismatch' })
    expect(again.headers.get('idempotency-replayed')).toBe('true')
    expect(await errorOf(again)).toEqual({ status: 422, code: 'media_upload_mismatch' })
  })

  it('U3 completing before the bytes arrived is 422 media_upload_missing, and the photo is a failed upload', async () => {
    const { photo } = await created('front')

    expect(await errorOf(await complete(photo.id))).toEqual({
      status: 422,
      code: 'media_upload_missing',
    })
    expect(rowOf(photo.id)).toMatchObject({
      status: 'failed',
      failure_stage: 'upload',
      failure_code: 'object_missing',
    })
  })

  it('U4 the id of a photo of ANOTHER account is 404 body_photo_not_found, and nothing of it is touched', async () => {
    const { photo } = await created('front')
    upload(photo.id)

    const response = await complete(photo.id, { token: OTHER_TOKEN })

    expect(await errorOf(response)).toEqual({ status: 404, code: 'body_photo_not_found' })
    expect(rowOf(photo.id).status).toBe('pending_upload')
    expect(objectOf(photo.id)).toBeDefined()
    expect(operationsOf('storage:info')).toEqual([])
  })

  it.each([
    ['a meal photo of the same account', { kind: 'meal_photo', context_text: 'Foto de frente.' }],
    ['a body photo that carries no pose sentence', { context_text: null }],
    ['a body photo with another context', { context_text: 'Foto de frente' }],
  ] satisfies [
    string,
    Partial<MemoryMediaAsset>,
  ][])('U5 %s is not a photo of the sign-up: 404 body_photo_not_found, untouched', async (_label, other) => {
    const id = '00000000-0000-4000-8000-000000000701'
    db().seedMediaAsset({ id, user_id: ACCOUNT, ...other })
    upload(id, { size: 1200 })

    expect(await errorOf(await complete(id))).toEqual({ status: 404, code: 'body_photo_not_found' })
    expect(rowOf(id).status).toBe('pending_upload')
    expect(objectOf(id)).toBeDefined()
  })

  it('U6 an id that does not exist is 404, and an id that is not one is 422', async () => {
    expect(await errorOf(await complete('00000000-0000-4000-8000-000000000799'))).toEqual({
      status: 404,
      code: 'body_photo_not_found',
    })
    expect(await errorOf(await complete('not-an-id'))).toEqual({
      status: 422,
      code: 'validation_failed',
    })
  })

  it('U7 completing again, with another key, answers the same state and changes nothing', async () => {
    const id = await store('front')
    const before = { ...rowOf(id) }

    const response = await complete(id, { expectReading: true })

    expect(response.status).toBe(200)
    expect((await response.json()).data.photo).toMatchObject({ id, status: 'uploaded' })
    expect(rowOf(id)).toEqual(before)
    expect(objectOf(id)).toBeDefined()
  })

  it('U8 a text of the consent that changed after the photo was created stops its completion: 403, the photo stays pending', async () => {
    const { photo } = await created('front')
    upload(photo.id)
    db().publishDocument({
      documentKey: 'body_photo_estimate_consent',
      version: 'teste-2026-10-11.2',
      locale: 'pt-BR',
      body: 'TEXTO DE TESTE — segunda versão, também não é o texto do app.',
      requiredFrom: '2026-10-11T14:00:00.000Z',
    })

    expect(await errorOf(await complete(photo.id))).toEqual({
      status: 403,
      code: 'body_photo_consent_required',
    })
    expect(rowOf(photo.id).status).toBe('pending_upload')
  })

  it('U9 the storage being unavailable is 503 and changes nothing: the same completion works afterwards', async () => {
    const { photo } = await created('front')
    upload(photo.id)
    db().failNext('storage:info', { message: 'storage is down' })

    expect(await errorOf(await complete(photo.id, { key: 'body-photo-complete-retry' }))).toEqual({
      status: 503,
      code: 'media_storage_unavailable',
    })
    expect(rowOf(photo.id).status).toBe('pending_upload')

    expect(
      (await complete(photo.id, { key: 'body-photo-complete-retry', expectReading: true })).status,
    ).toBe(200)
    expect(rowOf(photo.id).status).toBe('uploaded')
  })

  it('U10 a photo already deleted is 409 media_upload_not_pending, and bytes that arrived with its old ticket are removed', async () => {
    const { photo } = await created('front')
    expect((await (await remove()).json()).data).toEqual({ deleted: 1 })
    // The ticket handed before the deletion is still valid for two hours.
    upload(photo.id)

    expect(await errorOf(await complete(photo.id))).toEqual({
      status: 409,
      code: 'media_upload_not_pending',
    })
    expect(objectOf(photo.id)).toBeUndefined()
    expect(rowOf(photo.id).status).toBe('deleted')
  })

  it('U11 the same for a photo refused at upload: bytes sent again with the old ticket do not stay', async () => {
    const { photo } = await created('front')
    expect((await complete(photo.id)).status).toBe(422)
    upload(photo.id)

    expect(await errorOf(await complete(photo.id))).toEqual({
      status: 409,
      code: 'media_upload_not_pending',
    })
    expect(objectOf(photo.id)).toBeUndefined()
    expect(rowOf(photo.id)).toMatchObject({ status: 'failed', failure_stage: 'upload' })
  })

  it('U12 the Idempotency-Key is required', async () => {
    const { photo } = await created('front')

    expect(await errorOf(await complete(photo.id, { key: null }))).toEqual({
      status: 400,
      code: 'missing_idempotency_key',
    })
  })
})

describe('replacing one pose', () => {
  beforeEach(() => acceptConsent())

  it('T1 a second creation of the same pose does NOT delete the earlier photo; only the completion of the new upload does', async () => {
    const earlier = await store('front')
    vi.setSystemTime(new Date(NOW.getTime() + 60_000))

    const { photo: newer } = await created('front')

    // Created, not uploaded: the earlier photo is whole and is still the one shown.
    expect(rowOf(earlier).status).toBe('uploaded')
    expect(objectOf(earlier)).toBeDefined()
    expect(operationsOf('storage:remove')).toEqual([])
    expect((await readState()).poses[0].photo.id).toBe(earlier)

    upload(newer.id)
    // Uploaded, not completed: still nothing is deleted.
    expect(rowOf(earlier).status).toBe('uploaded')
    expect((await readState()).poses[0].photo.id).toBe(earlier)

    expect((await complete(newer.id, { expectReading: true })).status).toBe(200)

    expect(rowOf(earlier)).toMatchObject({
      status: 'deleted',
      deleted_at: new Date(NOW.getTime() + 60_000).toISOString(),
      processing_result: null,
    })
    expect(objectOf(earlier)).toBeUndefined()
    expect(rowOf(newer.id).status).toBe('uploaded')
    expect(objectOf(newer.id)).toBeDefined()
    expect((await readState()).poses[0].photo.id).toBe(newer.id)
  })

  const FAILED_UPLOADS: Array<[string, (id: string) => unknown, string]> = [
    ['the bytes never arrive (object missing)', () => undefined, 'media_upload_missing'],
    [
      'the bytes differ from the declaration',
      (id: string) => upload(id, { size: 12 }),
      'media_upload_mismatch',
    ],
  ]

  it.each(
    FAILED_UPLOADS,
  )('T2 a new upload that fails (%s) leaves the earlier photo, and what was read of it, as they were', async (_label, sendBytes, code) => {
    const earlier = '00000000-0000-4000-8000-000000000801'
    const reading = { type: 'body', bf_percent_estimate: 22, notes: 'anotação da leitura' }
    seed(earlier, 'front', {
      status: 'processed',
      actual_size_bytes: 1200,
      uploaded_at: STORED_AT,
      processed_at: STORED_AT,
      processing_request_id: 'a'.repeat(64),
      processing_result: reading,
    })
    upload(earlier)
    const { photo: newer } = await created('front')
    sendBytes(newer.id)

    expect(await errorOf(await complete(newer.id))).toEqual({ status: 422, code })

    expect(rowOf(earlier)).toMatchObject({ status: 'processed', processing_result: reading })
    expect(objectOf(earlier)).toBeDefined()
    expect(rowOf(newer.id)).toMatchObject({ status: 'failed', failure_stage: 'upload' })
    expect((await readState()).poses[0].photo).toMatchObject({ id: earlier, status: 'read' })
  })

  it('T3 the other two poses are not touched by the replacement of one', async () => {
    const front = await store('front')
    const side = await store('side')
    const back = await store('back')
    vi.setSystemTime(new Date(NOW.getTime() + 60_000))

    const newSide = await store('side')

    expect(rowOf(side).status).toBe('deleted')
    for (const id of [front, back, newSide]) {
      expect(rowOf(id).status).toBe('uploaded')
      expect(objectOf(id)).toBeDefined()
    }
    expect(
      (await readState()).poses.map((slot: { photo: { id: string } }) => slot.photo.id),
    ).toEqual([front, newSide, back])
  })

  it('T4 the replacement is one storage call and one write, and it empties what a reading left of the earlier photo', async () => {
    const earlier = '00000000-0000-4000-8000-000000000802'
    seed(earlier, 'back', {
      status: 'failed',
      failure_stage: 'processing',
      failure_code: 'provider_error',
      actual_size_bytes: 1200,
      uploaded_at: STORED_AT,
    })
    upload(earlier)
    const { photo: newer } = await created('back')
    upload(newer.id)
    db().operations.length = 0
    db().calls.length = 0

    expect((await complete(newer.id, { expectReading: true })).status).toBe(200)

    expect(operationsOf('storage:remove')).toHaveLength(1)
    expect(db().calls.find((call) => call.operation === 'storage:remove')?.detail).toEqual({
      bucketId: BUCKET,
      objectPaths: [`${ACCOUNT}/${earlier}.jpg`],
    })
    expect(rowOf(earlier)).toMatchObject({
      status: 'deleted',
      failure_stage: null,
      failure_code: null,
      processing_result: null,
    })
  })

  it('T5 completing an OLDER photo again never deletes the newer one of the pose', async () => {
    const older = '00000000-0000-4000-8000-000000000803'
    const newer = '00000000-0000-4000-8000-000000000804'
    seed(older, 'front', { status: 'uploaded', actual_size_bytes: 1200, uploaded_at: STORED_AT })
    seed(newer, 'front', {
      status: 'uploaded',
      actual_size_bytes: 1200,
      uploaded_at: databaseTimestamp(new Date(NOW.getTime() - HOUR / 2)),
    })
    upload(older)
    upload(newer)

    expect((await complete(older, { expectReading: true })).status).toBe(200)

    expect(rowOf(newer).status).toBe('uploaded')
    expect(objectOf(newer)).toBeDefined()
    // Two stored photos of one pose (two completions at once): the state shows the newest.
    expect((await readState()).poses[0].photo.id).toBe(newer)

    // And completing the newer one again finishes the replacement.
    expect((await complete(newer, { expectReading: true })).status).toBe(200)
    expect(rowOf(older).status).toBe('deleted')
    expect(objectOf(older)).toBeUndefined()
  })

  it('T7 two uploads of one pose still on their way: completing the first does not delete the second, which is not a stored photo yet; completing the second replaces the first', async () => {
    const { photo: first } = await created('front')
    const { photo: second } = await created('front')
    upload(first.id)
    upload(second.id)

    expect((await complete(first.id, { expectReading: true })).status).toBe(200)

    expect(rowOf(second.id).status).toBe('pending_upload')
    expect(objectOf(second.id)).toBeDefined()
    expect(operationsOf('storage:remove')).toEqual([])

    vi.setSystemTime(new Date(NOW.getTime() + 1000))
    expect((await complete(second.id, { expectReading: true })).status).toBe(200)

    expect(rowOf(first.id).status).toBe('deleted')
    expect(objectOf(first.id)).toBeUndefined()
    expect((await readState()).poses[0].photo.id).toBe(second.id)
  })

  it('T6 a storage failure while the earlier photo is removed is 503 with the new photo stored; completing again finishes the replacement', async () => {
    const earlier = await store('front')
    vi.setSystemTime(new Date(NOW.getTime() + 60_000))
    const { photo: newer } = await created('front')
    upload(newer.id)
    db().failNext('storage:remove', { message: 'storage is down' })

    expect(await errorOf(await complete(newer.id))).toEqual({
      status: 503,
      code: 'media_delete_failed',
    })
    expect(rowOf(newer.id).status).toBe('uploaded')
    expect(rowOf(earlier).status).toBe('uploaded')
    expect((await readState()).poses[0].photo.id).toBe(newer.id)

    expect((await complete(newer.id, { expectReading: true })).status).toBe(200)
    expect(rowOf(earlier).status).toBe('deleted')
    expect(objectOf(earlier)).toBeUndefined()
  })
})

describe('deleting everything', () => {
  beforeEach(() => acceptConsent())

  it('D1 DELETE removes the objects in one storage call, marks the rows in one write and empties what a reading left; the rows stay and keep counting in the limit', async () => {
    const front = await store('front')
    const side = await store('side')
    const back = '00000000-0000-4000-8000-000000000901'
    seed(back, 'back', {
      status: 'processed',
      actual_size_bytes: 1200,
      uploaded_at: STORED_AT,
      processed_at: STORED_AT,
      processing_request_id: 'b'.repeat(64),
      processing_result: { type: 'body', bf_percent_estimate: 24, notes: 'anotação da leitura' },
    })
    upload(back)
    db().operations.length = 0
    db().calls.length = 0

    const response = await remove()

    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({ deleted: 3 })
    expect(operationsOf('storage:remove')).toHaveLength(1)
    const removed = db().calls.find((call) => call.operation === 'storage:remove')?.detail as {
      bucketId: string
      objectPaths: string[]
    }
    expect(removed.bucketId).toBe(BUCKET)
    expect([...removed.objectPaths].sort()).toEqual(
      [front, side, back].map((id) => `${ACCOUNT}/${id}.jpg`).sort(),
    )
    expect(operationsOf('update:media_assets')).toHaveLength(1)
    expect(db().objects.size).toBe(0)

    // The catalogue rows are NOT removed: they are marked, and the limit depends on them.
    expect(db().mediaAssets).toHaveLength(3)
    for (const id of [front, side, back]) {
      expect(rowOf(id)).toMatchObject({
        status: 'deleted',
        deleted_at: NOW.toISOString(),
        processing_result: null,
        failure_stage: null,
        failure_code: null,
      })
    }
    const state = await readState()
    expect(state.poses.every((slot: { photo: unknown }) => slot.photo === null)).toBe(true)
    expect(state.remaining_uploads).toBe(6)
  })

  // CHANGED ON PURPOSE in the answer to the review of 2026-10-11 (round 1,
  // findings 1 and 3). It used to say "deleting again finds nothing and calls
  // nothing" and to expect no storage call: that is what left the bytes of a
  // late upload stored. Deleting again still marks nothing and answers
  // { deleted: 0 }; what changed is that the storage IS asked again.
  it('D2 it is idempotent in what it answers and writes: deleting again marks nothing and answers {deleted: 0}, with another key or with the same; and each time the storage is asked again, in one call, for the photo already deleted', async () => {
    const stored = await store('front')
    const first = await remove({ key: 'body-photo-delete-same' })
    expect((await first.json()).data).toEqual({ deleted: 1 })
    db().operations.length = 0
    db().calls.length = 0

    const replay = await remove({ key: 'body-photo-delete-same' })
    expect(replay.status).toBe(200)
    expect(replay.headers.get('idempotency-replayed')).toBe('true')
    expect((await replay.json()).data).toEqual({ deleted: 0 })
    expect(operationsOf('storage:')).toEqual(['storage:remove'])

    const again = await remove()
    expect(again.status).toBe(200)
    expect((await again.json()).data).toEqual({ deleted: 0 })
    const itsObject = { bucketId: BUCKET, objectPaths: [`${ACCOUNT}/${stored}.jpg`] }
    expect(removals()).toEqual([itsObject, itsObject])
    expect(operationsOf('storage:')).toEqual(['storage:remove', 'storage:remove'])
    expect(operationsOf('update:')).toEqual([])
    expect(rowOf(stored)).toMatchObject({ status: 'deleted', deleted_at: NOW.toISOString() })
  })

  it('D2b a repeated key runs the deletion AGAIN, never the stored answer: a photo sent after the first DELETE is deleted by the second, even with the same key', async () => {
    await store('front')
    expect((await (await remove({ key: 'body-photo-delete-reused' })).json()).data).toEqual({
      deleted: 1,
    })
    const later = await store('side')

    const second = await remove({ key: 'body-photo-delete-reused' })

    expect(second.status).toBe(200)
    expect((await second.json()).data).toEqual({ deleted: 1 })
    expect(rowOf(later).status).toBe('deleted')
    expect(objectOf(later)).toBeUndefined()
    expect(db().objects.size).toBe(0)
  })

  it('D3 it does not depend on the switch: with the photos switched off afterwards, DELETE still deletes them', async () => {
    const stored = await store('front')
    vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, '')
    expect((await readState()).available).toBe(false)
    expect(await errorOf(await create('side'))).toEqual({
      status: 404,
      code: 'body_photos_unavailable',
    })

    expect((await (await remove()).json()).data).toEqual({ deleted: 1 })
    expect(objectOf(stored)).toBeUndefined()
    expect(rowOf(stored).status).toBe('deleted')
  })

  it('D4 it takes the uploads still pending and the bytes of a photo refused at upload, whose row stays as a failed upload', async () => {
    const { photo: pending } = await created('front')
    upload(pending.id)
    const { photo: refused } = await created('side')
    expect((await complete(refused.id)).status).toBe(422)
    // Bytes sent with the old ticket after the refusal.
    upload(refused.id)

    expect((await (await remove()).json()).data).toEqual({ deleted: 1 })

    expect(db().objects.size).toBe(0)
    expect(rowOf(pending.id).status).toBe('deleted')
    // The database does not let a failed upload become "deleted": the row stays what it is.
    expect(rowOf(refused.id)).toMatchObject({ status: 'failed', failure_stage: 'upload' })
  })

  it('D5 only the photos of the sign-up of THIS account: another account, a meal photo and a body photo without a pose stay', async () => {
    const mine = await store('front')
    const mealPhoto = '00000000-0000-4000-8000-000000000911'
    const otherBody = '00000000-0000-4000-8000-000000000912'
    const theirs = '00000000-0000-4000-8000-000000000913'
    const captionedMeal = '00000000-0000-4000-8000-000000000914'
    db().seedMediaAsset({ id: mealPhoto, user_id: ACCOUNT, kind: 'meal_photo' })
    db().seedMediaAsset({ id: otherBody, user_id: ACCOUNT, context_text: null })
    db().seedMediaAsset({ id: theirs, user_id: OTHER_ACCOUNT, context_text: 'Foto de frente.' })
    // A meal photo whose caption happens to be a pose sentence is still a meal photo.
    db().seedMediaAsset({
      id: captionedMeal,
      user_id: ACCOUNT,
      kind: 'meal_photo',
      context_text: 'Foto de frente.',
    })
    for (const id of [mealPhoto, otherBody, theirs, captionedMeal]) upload(id, { size: 1200 })

    expect((await (await remove()).json()).data).toEqual({ deleted: 1 })

    expect(rowOf(mine).status).toBe('deleted')
    for (const id of [mealPhoto, otherBody, theirs, captionedMeal]) {
      expect(rowOf(id).status).toBe('pending_upload')
      expect(objectOf(id)).toBeDefined()
    }
  })

  it('D6 if the storage cannot remove, nothing is marked: 503, and the same DELETE works afterwards', async () => {
    const stored = await store('front')
    db().failNext('storage:remove', { message: 'storage is down' })

    expect(await errorOf(await remove({ key: 'body-photo-delete-retry' }))).toEqual({
      status: 503,
      code: 'media_delete_failed',
    })
    expect(rowOf(stored).status).toBe('uploaded')
    expect(objectOf(stored)).toBeDefined()

    expect((await (await remove({ key: 'body-photo-delete-retry' })).json()).data).toEqual({
      deleted: 1,
    })
    expect(objectOf(stored)).toBeUndefined()
  })

  it('D7 after deleting, the acceptance still stands and a new photo can be sent without accepting again', async () => {
    await store('front')
    await remove()

    expect((await readState()).consent.accepted_at).toBe(databaseTimestamp(NOW))
    expect((await create('front')).status).toBe(201)
    expect(db().legalAcceptances).toHaveLength(1)
  })
})

describe('explicit DELETE authorization observed while open versus a subsequent close', () => {
  beforeEach(() => acceptConsent())

  function boundaryDb(): DeleteBoundaryMemoryDb {
    const database = db()
    if (!(database instanceof DeleteBoundaryMemoryDb))
      throw new Error('missing typed DELETE boundary')
    return database
  }

  function processedTriad(): string[] {
    return (
      [
        { id: '00000000-0000-4000-8000-000000000d41', pose: 'front', value: 18 },
        { id: '00000000-0000-4000-8000-000000000d42', pose: 'side', value: 24 },
        { id: '00000000-0000-4000-8000-000000000d43', pose: 'back', value: 30 },
      ] as const
    ).map(({ id, pose, value }) => {
      seed(id, pose, {
        status: 'processed',
        actual_size_bytes: 1200,
        uploaded_at: STORED_AT,
        processed_at: STORED_AT,
        processing_request_id: sha256Hex(`delete-boundary-${id}`),
        processing_result: { type: 'body', bf_percent_estimate: value },
      })
      upload(id, { size: 1200 })
      return id
    })
  }

  it.each([
    false,
    true,
  ])('DC1 open list wins before close; Storage failure=%s preserves D6 and observed-ID scope', async (storageFails) => {
    const database = boundaryDb()
    const ids = processedTriad()
    expect((await readState()).estimate.by_sex.masculino).toEqual({
      usable: true,
      body_fat_percent: 24,
    })
    const rowsBefore = ids.map((id) => structuredClone(rowOf(id)))
    const bytesBefore = ids.map((id) => structuredClone(objectOf(id)))
    const laterId = '00000000-0000-4000-8000-000000000d44'
    const generation = databaseTimestamp(new Date(NOW.getTime() + 1000))
    let laterBefore: MemoryMediaAsset | undefined
    let laterBytes: ReturnType<typeof objectOf>
    let boundaryCalls = 0
    const actualRpc = database.rpc.bind(database)
    vi.spyOn(database, 'rpc').mockImplementation(async (name, params) => {
      const result = await actualRpc(name, params)
      if (name === 'list_mobile_open_signup_body_photo_assets' && boundaryCalls === 0) {
        boundaryCalls += 1
        expect(params).toEqual({ p_user_id: ACCOUNT, p_include_deleted: true, p_limit: 1000 })
        expect(result.error).toBeNull()
        expect(result.data).toEqual(
          expect.arrayContaining(ids.map((id) => expect.objectContaining({ id }))),
        )
        expect(Array.isArray(result.data) && result.data.length).toBe(3)
        expect(removals()).toEqual([])
        expect(database.profiles.get(ACCOUNT)).toEqual(OPEN_SIGNUP)
        // A later INSERT wins before the close, but after this DELETE's list.
        seed(laterId, 'front')
        upload(laterId)
        laterBefore = structuredClone(rowOf(laterId))
        laterBytes = structuredClone(objectOf(laterId))
        database.profiles.set(ACCOUNT, {
          onboarding_completed: true,
          onboarding_completed_at: generation,
        })
        // Explicit fixture membership only. Native SQL proves capture/BF3/transactionality.
        database.declareCompletedSignupScope(ACCOUNT, generation, [...ids, laterId])
      }
      return result
    })
    database.operations.length = 0
    database.calls.length = 0
    if (storageFails) database.failNext('storage:remove', { message: 'storage is down' })

    const response = await remove({ key: 'body-photo-delete-open-close-characterization' })
    assertPrivate(await response.clone().json())
    expect(boundaryCalls).toBe(1)
    expect(removals()).toEqual([
      { bucketId: BUCKET, objectPaths: ids.map((id) => `${ACCOUNT}/${id}.jpg`).sort() },
    ])
    expect(operationsOf('rpc:prepare_mobile_signup_body_photo_disposition')).toHaveLength(1)
    expect(operationsOf('rpc:get_mobile_signup_body_photo_disposition_page')).toEqual([])
    expect(operationsOf('rpc:commit_mobile_signup_body_photo_disposition_page')).toEqual([])
    expect(rowOf(laterId)).toEqual(laterBefore)
    expect(objectOf(laterId)).toEqual(laterBytes)
    expect(objectOf(laterId)).toBeDefined()
    expect(world.queue).toEqual([])

    if (storageFails) {
      expect(await errorOf(response)).toEqual({ status: 503, code: 'media_delete_failed' })
      expect(ids.map((id) => rowOf(id))).toEqual(rowsBefore)
      expect(ids.map((id) => objectOf(id))).toEqual(bytesBefore)
      expect(operationsOf('update:media_assets')).toEqual([])
      database.calls.length = 0
      database.operations.length = 0
      // The same key retries AFTER close: now it uses the declared D4 scope,
      // which includes the later photo. No earlier failed request marked rows.
      const retried = await remove({ key: 'body-photo-delete-open-close-characterization' })
      expect(retried.status).toBe(200)
      const body = await retried.json()
      assertPrivate(body)
      expect(body.data).toEqual({ deleted: 4 })
      expect(removals()).toEqual([
        {
          bucketId: BUCKET,
          objectPaths: [...ids, laterId].map((id) => `${ACCOUNT}/${id}.jpg`).sort(),
        },
      ])
      expect(operationsOf('rpc:list_mobile_open_signup_body_photo_assets')).toEqual([])
      expect(
        database.calls.filter(
          (call) => call.operation === 'rpc:commit_mobile_signup_body_photo_disposition_page',
        ),
      ).toEqual([
        {
          operation: 'rpc:commit_mobile_signup_body_photo_disposition_page',
          detail: {
            p_user_id: ACCOUNT,
            p_generation: generation,
            p_expected_sweep: 1,
            p_expected_after: null,
            p_asset_ids: [...ids, laterId],
          },
        },
      ])
      for (const id of [...ids, laterId]) {
        expect(rowOf(id)).toMatchObject({ status: 'deleted', processing_result: null })
        expect(objectOf(id)).toBeUndefined()
      }
    } else {
      expect(response.status).toBe(200)
      expect((await response.json()).data).toEqual({ deleted: 3 })
      for (const id of ids) {
        expect(rowOf(id)).toMatchObject({ status: 'deleted', processing_result: null })
        expect(objectOf(id)).toBeUndefined()
      }
      expect(database.objects.size).toBe(1)
    }
    expect(operationsOf('storage:createSignedUploadUrl')).toEqual([])
    expect(operationsOf('storage:info')).toEqual([])
    expect(world.queue).toEqual([])
  })

  it('DC2 close wins after open repair but before list: the scoped list rejects before any Storage or tombstone', async () => {
    const database = boundaryDb()
    const ids = processedTriad()
    const rowsBefore = ids.map((id) => structuredClone(rowOf(id)))
    const bytesBefore = ids.map((id) => structuredClone(objectOf(id)))
    const generation = databaseTimestamp(new Date(NOW.getTime() + 1000))
    let boundaryCalls = 0
    const actualRpc = database.rpc.bind(database)
    vi.spyOn(database, 'rpc').mockImplementation(async (name, params) => {
      if (name === 'list_mobile_open_signup_body_photo_assets') {
        boundaryCalls += 1
        expect(database.profiles.get(ACCOUNT)).toEqual(OPEN_SIGNUP)
        database.profiles.set(ACCOUNT, {
          onboarding_completed: true,
          onboarding_completed_at: generation,
        })
        database.declareCompletedSignupScope(ACCOUNT, generation, ids)
      }
      return actualRpc(name, params)
    })
    database.operations.length = 0
    database.calls.length = 0

    const response = await remove()

    assertPrivate(await response.clone().json())
    expect(await errorOf(response)).toEqual({ status: 409, code: 'onboarding_already_completed' })
    expect(boundaryCalls).toBe(1)
    expect(operationsOf('rpc:prepare_mobile_signup_body_photo_disposition')).toHaveLength(1)
    expect(operationsOf('rpc:list_mobile_open_signup_body_photo_assets')).toHaveLength(1)
    expect(operationsOf('rpc:get_mobile_signup_body_photo_disposition_page')).toEqual([])
    expect(operationsOf('rpc:commit_mobile_signup_body_photo_disposition_page')).toEqual([])
    expect(operationsOf('storage:')).toEqual([])
    expect(operationsOf('update:media_assets')).toEqual([])
    expect(ids.map((id) => rowOf(id))).toEqual(rowsBefore)
    expect(ids.map((id) => objectOf(id))).toEqual(bytesBefore)
    expect(world.queue).toEqual([])
  })
})

describe('bytes that arrive AFTER a photo was deleted, replaced or refused: the upload ticket is valid for two hours and cannot be revoked', () => {
  beforeEach(() => acceptConsent())

  it('LB1 EXACT (review of 2026-10-11, round 1, finding 1): the account creates the front photo (pending) and its PUT is on its way; the person deletes — DELETE answers {deleted: 1}, there is no object yet; the PUT ends with the old ticket; the next DELETE answers {deleted: 0} and REMOVES that object', async () => {
    const { photo } = await created('front')
    const first = await remove()
    expect(first.status).toBe(200)
    expect((await first.json()).data).toEqual({ deleted: 1 })
    expect(objectOf(photo.id)).toBeUndefined()
    // The PUT that was on its way ends now, with the ticket handed before the deletion.
    upload(photo.id)
    expect(objectOf(photo.id)).toBeDefined()
    db().operations.length = 0
    db().calls.length = 0

    const second = await remove()

    expect(second.status).toBe(200)
    const secondBody = await second.json()
    assertPrivate(secondBody)
    expect(secondBody.data).toEqual({ deleted: 0 })
    expect(objectOf(photo.id)).toBeUndefined()
    expect(db().objects.size).toBe(0)
    // Empty historical repair, then one scoped open catalogue read and one remove.
    expect(operationsOf('select:media_assets')).toEqual([])
    expect(
      db().calls.filter(
        (call) => call.operation === 'rpc:prepare_mobile_signup_body_photo_disposition',
      ),
    ).toEqual([
      {
        operation: 'rpc:prepare_mobile_signup_body_photo_disposition',
        detail: {
          p_user_id: ACCOUNT,
          p_generation: null,
          p_swept_generations: [],
        },
      },
    ])
    expect(
      db().calls.filter(
        (call) => call.operation === 'rpc:list_mobile_open_signup_body_photo_assets',
      ),
    ).toEqual([
      {
        operation: 'rpc:list_mobile_open_signup_body_photo_assets',
        detail: {
          p_user_id: ACCOUNT,
          p_include_deleted: true,
          p_limit: 1000,
        },
      },
    ])
    expect(operationsOf('rpc:commit_mobile_signup_body_photo_disposition_page')).toEqual([])
    expect(removals()).toEqual([{ bucketId: BUCKET, objectPaths: [`${ACCOUNT}/${photo.id}.jpg`] }])
    expect(operationsOf('update:')).toEqual([])
    expect(rowOf(photo.id)).toMatchObject({ status: 'deleted', deleted_at: NOW.toISOString() })
    expect(world.queue).toEqual([])
  })

  it('LB2 EXACT, the variant of the same finding with the photos switched OFF afterwards: the completion of the upload answers 404 and removes nothing, and DELETE still removes the object', async () => {
    const { photo } = await created('front')
    expect((await (await remove()).json()).data).toEqual({ deleted: 1 })
    upload(photo.id)
    vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, '')

    expect(await errorOf(await complete(photo.id))).toEqual({
      status: 404,
      code: 'body_photos_unavailable',
    })
    expect(objectOf(photo.id)).toBeDefined()

    const second = await remove()

    expect(second.status).toBe(200)
    expect((await second.json()).data).toEqual({ deleted: 0 })
    expect(objectOf(photo.id)).toBeUndefined()
    expect(db().objects.size).toBe(0)
  })

  it('LB3 there is no time window: late bytes on a tombstone are removed the next day from the scope sealed by checked close', async () => {
    const { photo } = await created('front')
    expect((await (await remove()).json()).data).toEqual({ deleted: 1 })
    const tombstoneBefore = structuredClone(rowOf(photo.id))
    vi.setSystemTime(new Date(NOW.getTime() + 60_000))
    upload(photo.id)
    expect(objectOf(photo.id)).toBeDefined()
    vi.setSystemTime(new Date(NOW.getTime() + 26 * HOUR))
    const generation = databaseTimestamp(new Date())
    db().profiles.set(ACCOUNT, { onboarding_completed: true, onboarding_completed_at: generation })
    // Explicit fixture authorization only. Native SQL separately proves the
    // checked close sealed this existing tombstone; this fake simulates no BF3/TX.
    db().declareCompletedSignupScope(ACCOUNT, generation, [photo.id])
    db().operations.length = 0
    db().calls.length = 0

    const nextDay = await remove()

    expect(nextDay.status).toBe(200)
    const body = await nextDay.json()
    assertPrivate(body)
    expect(body.data).toEqual({ deleted: 0 })
    expect(objectOf(photo.id)).toBeUndefined()
    expect(rowOf(photo.id)).toEqual(tombstoneBefore)
    expect(removals()).toEqual([{ bucketId: BUCKET, objectPaths: [`${ACCOUNT}/${photo.id}.jpg`] }])
    expect(operationsOf('rpc:prepare_mobile_signup_body_photo_disposition')).toHaveLength(2)
    expect(
      db().calls.filter(
        (call) => call.operation === 'rpc:commit_mobile_signup_body_photo_disposition_page',
      ),
    ).toEqual([
      {
        operation: 'rpc:commit_mobile_signup_body_photo_disposition_page',
        detail: {
          p_user_id: ACCOUNT,
          p_generation: generation,
          p_expected_sweep: 1,
          p_expected_after: null,
          p_asset_ids: [photo.id],
        },
      },
    ])
    expect(operationsOf('rpc:list_mobile_open_signup_body_photo_assets')).toEqual([])
    expect(operationsOf('select:media_assets')).toEqual([])
    expect(operationsOf('storage:createSignedUploadUrl')).toEqual([])
    expect(operationsOf('storage:info')).toEqual([])
    expect(world.queue).toEqual([])
  })

  it('LB4 a photo that was REPLACED: its PUT, repeated with the old ticket after the replacement removed the object, leaves bytes again; DELETE removes them in the same storage call as the photo of the pose', async () => {
    const earlier = await store('front')
    vi.setSystemTime(new Date(NOW.getTime() + 60_000))
    const newer = await store('front')
    expect(rowOf(earlier).status).toBe('deleted')
    expect(objectOf(earlier)).toBeUndefined()
    upload(earlier)
    db().calls.length = 0

    const response = await remove()

    expect((await response.json()).data).toEqual({ deleted: 1 })
    expect(db().objects.size).toBe(0)
    expect(removals()).toEqual([
      {
        bucketId: BUCKET,
        objectPaths: [`${ACCOUNT}/${earlier}.jpg`, `${ACCOUNT}/${newer}.jpg`].sort(),
      },
    ])
    expect(rowOf(newer).status).toBe('deleted')
  })

  it('LB5 only the photos of the sign-up of THIS account: bytes at the path of a deleted photo of another account, of a deleted meal photo and of a deleted body photo with no pose sentence are not touched', async () => {
    const { photo: mine } = await created('front')
    expect((await (await remove()).json()).data).toEqual({ deleted: 1 })
    upload(mine.id)
    const theirs = '00000000-0000-4000-8000-000000000c01'
    const myMeal = '00000000-0000-4000-8000-000000000c02'
    const otherBody = '00000000-0000-4000-8000-000000000c03'
    const deleted = { status: 'deleted', deleted_at: STORED_AT }
    db().seedMediaAsset({
      id: theirs,
      user_id: OTHER_ACCOUNT,
      context_text: 'Foto de frente.',
      ...deleted,
    })
    db().seedMediaAsset({
      id: myMeal,
      user_id: ACCOUNT,
      kind: 'meal_photo',
      context_text: 'Foto de frente.',
      ...deleted,
    })
    db().seedMediaAsset({ id: otherBody, user_id: ACCOUNT, context_text: null, ...deleted })
    for (const id of [theirs, myMeal, otherBody]) upload(id, { size: 1200 })
    db().calls.length = 0

    expect((await (await remove()).json()).data).toEqual({ deleted: 0 })

    expect(objectOf(mine.id)).toBeUndefined()
    for (const id of [theirs, myMeal, otherBody]) expect(objectOf(id)).toBeDefined()
    expect(removals()).toEqual([{ bucketId: BUCKET, objectPaths: [`${ACCOUNT}/${mine.id}.jpg`] }])
  })

  it('LB6 EXACT (the same review, finding 3): the account creates the side photo and completes before its bytes arrived (422: a refused upload, which the catalogue never lets become "deleted"); DELETE twice — the second answers {deleted: 0}, writes nothing, and asks the storage again, in one call, for that photo', async () => {
    const { photo } = await created('side')
    expect((await complete(photo.id)).status).toBe(422)
    expect((await (await remove()).json()).data).toEqual({ deleted: 0 })
    db().operations.length = 0
    db().calls.length = 0

    const second = await remove()

    expect(second.status).toBe(200)
    expect((await second.json()).data).toEqual({ deleted: 0 })
    expect(operationsOf('storage:')).toEqual(['storage:remove'])
    expect(removals()).toEqual([{ bucketId: BUCKET, objectPaths: [`${ACCOUNT}/${photo.id}.jpg`] }])
    expect(operationsOf('update:')).toEqual([])
    expect(rowOf(photo.id)).toMatchObject({ status: 'failed', failure_stage: 'upload' })
  })

  it('LB7 with the storage down, DELETE is 503 even when no photo is alive: it cannot say that nothing is left. The same DELETE works afterwards', async () => {
    await store('front')
    expect((await (await remove()).json()).data).toEqual({ deleted: 1 })
    db().failNext('storage:remove', { message: 'storage is down' })

    expect(await errorOf(await remove({ key: 'body-photo-delete-late-retry' }))).toEqual({
      status: 503,
      code: 'media_delete_failed',
    })

    const retried = await remove({ key: 'body-photo-delete-late-retry' })
    expect(retried.status).toBe(200)
    expect((await retried.json()).data).toEqual({ deleted: 0 })
  })

  it('LB9 a photo that is ALIVE is never left out by rows already deleted: with 1000 deleted photos created after it — a full page — DELETE still deletes it, and looks at the 999 most recently deleted; the one deleted longest ago is the row the page leaves out', async () => {
    const alive = '00000000-0000-4000-8000-000000000d01'
    const longAgo = databaseTimestamp(new Date(NOW.getTime() - 200 * 24 * HOUR))
    seed(alive, 'back', {
      status: 'uploaded',
      actual_size_bytes: 1200,
      uploaded_at: longAgo,
      created_at: longAgo,
    })
    upload(alive)
    const gone = Array.from({ length: 1000 }, (_unused, index) => {
      const id = `00000000-0000-4000-8000-00000001${String(index).padStart(4, '0')}`
      // The first is the one deleted last; the thousandth, the one deleted longest ago.
      seed(id, 'front', {
        status: 'deleted',
        deleted_at: databaseTimestamp(new Date(NOW.getTime() - HOUR - index * 1000)),
      })
      return id
    })
    const [lastDeleted, deletedLongestAgo] = [gone[0] ?? '', gone[999] ?? '']
    // Bytes that arrived late at the two ends of that list.
    upload(lastDeleted)
    upload(deletedLongestAgo)
    db().calls.length = 0

    const response = await remove()

    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({ deleted: 1 })
    expect(rowOf(alive).status).toBe('deleted')
    expect(objectOf(alive)).toBeUndefined()
    expect(objectOf(lastDeleted)).toBeUndefined()
    const [removal] = removals()
    expect(removals()).toHaveLength(1)
    expect(removal?.objectPaths).toHaveLength(1000)
    expect(removal?.objectPaths).toContain(`${ACCOUNT}/${alive}.jpg`)
    // The bound, as it is: one page. The row deleted longest ago is not looked at.
    expect(removal?.objectPaths).not.toContain(`${ACCOUNT}/${deletedLongestAgo}.jpg`)
    expect(objectOf(deletedLongestAgo)).toBeDefined()
  })

  it('LB8 an account without signup photos: one empty repair and one scoped catalogue read, no Storage', async () => {
    db().operations.length = 0
    db().calls.length = 0

    const response = await remove()

    expect(response.status).toBe(200)
    const body = await response.json()
    assertPrivate(body)
    expect(body.data).toEqual({ deleted: 0 })
    expect(operationsOf('select:media_assets')).toEqual([])
    expect(
      db().calls.filter(
        (call) => call.operation === 'rpc:prepare_mobile_signup_body_photo_disposition',
      ),
    ).toEqual([
      {
        operation: 'rpc:prepare_mobile_signup_body_photo_disposition',
        detail: {
          p_user_id: ACCOUNT,
          p_generation: null,
          p_swept_generations: [],
        },
      },
    ])
    expect(
      db().calls.filter(
        (call) => call.operation === 'rpc:list_mobile_open_signup_body_photo_assets',
      ),
    ).toEqual([
      {
        operation: 'rpc:list_mobile_open_signup_body_photo_assets',
        detail: {
          p_user_id: ACCOUNT,
          p_include_deleted: true,
          p_limit: 1000,
        },
      },
    ])
    expect(operationsOf('rpc:get_mobile_signup_body_photo_disposition_page')).toEqual([])
    expect(operationsOf('rpc:commit_mobile_signup_body_photo_disposition_page')).toEqual([])
    expect(operationsOf('storage:')).toEqual([])
    expect(operationsOf('update:')).toEqual([])
    expect(world.queue).toEqual([])
  })
})

describe('declared gap: the generic routes of media still reach a photo of the sign-up (RC line; it closes in package B3)', () => {
  it('X1 the generic completion of an upload — what POST /media/:id/complete runs, for an account with access — stores a pending photo of the sign-up after the sign-up was completed and with a newer consent text in force: the two things for which these routes refuse the completion', async () => {
    await acceptConsent()
    const { photo } = await created('front')
    upload(photo.id)
    db().profiles.set(ACCOUNT, COMPLETED_SIGNUP)
    publishSecondConsentText()
    expect(await errorOf(await complete(photo.id))).toEqual({
      status: 403,
      code: 'body_photo_consent_required',
    })
    expect(rowOf(photo.id).status).toBe('pending_upload')

    db().operations.length = 0

    // The route itself asks for released access, which this in-memory database
    // does not model (it throws on that lookup): its service is called here.
    const generic = await completeMediaUpload(
      createSupabaseMediaDependencies(db().client),
      ACCOUNT,
      photo.id,
    )

    expect(generic).toMatchObject({ id: photo.id, kind: 'body_checkin_photo', status: 'uploaded' })
    expect(rowOf(photo.id).status).toBe('uploaded')
    expect(objectOf(photo.id)).toBeDefined()
    // It reads neither the consent nor the profile on the way.
    expect(db().operations).toEqual(['select:media_assets', 'storage:info', 'update:media_assets'])
  })
})

describe('the write that marks photos as deleted', () => {
  it('W1 reaches only body photos of the account it is given, even when handed the id of another row', async () => {
    const mine = '00000000-0000-4000-8000-000000000b01'
    const theirs = '00000000-0000-4000-8000-000000000b02'
    const myMeal = '00000000-0000-4000-8000-000000000b03'
    seed(mine, 'front')
    db().seedMediaAsset({ id: theirs, user_id: OTHER_ACCOUNT, context_text: 'Foto de frente.' })
    db().seedMediaAsset({ id: myMeal, user_id: ACCOUNT, kind: 'meal_photo' })
    const { catalogue } = createSupabaseSignupBodyPhotoDependencies(db().client, { enabled: true })

    const marked = await catalogue.markDeleted(ACCOUNT, [theirs, myMeal, mine], NOW.toISOString())

    expect(marked).toBe(1)
    expect(rowOf(mine).status).toBe('deleted')
    expect(rowOf(theirs).status).toBe('pending_upload')
    expect(rowOf(myMeal).status).toBe('pending_upload')
  })

  it('W2 is all or nothing: one row the catalogue refuses to change leaves every row as it was, and the failure is 500', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    const stored = '00000000-0000-4000-8000-000000000b11'
    const refused = '00000000-0000-4000-8000-000000000b12'
    seed(stored, 'front', { status: 'uploaded', actual_size_bytes: 1200, uploaded_at: STORED_AT })
    seed(refused, 'side', {
      status: 'failed',
      failure_stage: 'upload',
      failure_code: 'object_missing',
    })
    const { catalogue } = createSupabaseSignupBodyPhotoDependencies(db().client, { enabled: true })

    await expect(
      catalogue.markDeleted(ACCOUNT, [stored, refused], NOW.toISOString()),
    ).rejects.toMatchObject({ status: 500, code: 'data_access_failed' })

    expect(rowOf(stored).status).toBe('uploaded')
    expect(rowOf(refused).status).toBe('failed')
  })
})

describe('the state with photos, and what no answer carries', () => {
  beforeEach(() => acceptConsent())

  it('S1 only photos whose upload was completed are in the poses; each state of the catalogue is told in the words of the contract', async () => {
    const read = '00000000-0000-4000-8000-000000000a01'
    const reading = '00000000-0000-4000-8000-000000000a02'
    const failed = '00000000-0000-4000-8000-000000000a03'
    seed(read, 'front', {
      status: 'processed',
      actual_size_bytes: 1200,
      uploaded_at: STORED_AT,
      processed_at: STORED_AT,
      processing_request_id: 'c'.repeat(64),
      processing_result: {
        type: 'body',
        bf_percent_estimate: 21.5,
        bf_confidence: 0.4,
        notes: 'x',
      },
    })
    seed(reading, 'side', {
      status: 'processing',
      actual_size_bytes: 1200,
      uploaded_at: STORED_AT,
      processing_request_id: 'd'.repeat(64),
    })
    seed(failed, 'back', {
      status: 'failed',
      failure_stage: 'processing',
      failure_code: 'provider_error',
      actual_size_bytes: 1200,
      uploaded_at: STORED_AT,
    })
    // Not stored: none of these is in a pose.
    seed('00000000-0000-4000-8000-000000000a04', 'front', { status: 'pending_upload' })
    seed('00000000-0000-4000-8000-000000000a05', 'side', {
      status: 'failed',
      failure_stage: 'upload',
      failure_code: 'object_missing',
    })
    seed('00000000-0000-4000-8000-000000000a06', 'back', {
      status: 'deleted',
      deleted_at: STORED_AT,
    })

    const state = await readState()

    const createdAt = databaseTimestamp(NOW)
    expect(state.poses).toEqual([
      { pose: 'front', photo: { id: read, status: 'read', created_at: createdAt } },
      { pose: 'side', photo: { id: reading, status: 'reading', created_at: createdAt } },
      { pose: 'back', photo: { id: failed, status: 'reading_failed', created_at: createdAt } },
    ])
    // Whatever was read, there is no estimate in this package.
    expect(state.estimate).toBeNull()
  })

  it('S2 no answer of these routes carries the context, a reading result, notes, the bucket or the path of the object', async () => {
    const answers: unknown[] = []
    const first = await created('front')
    answers.push(first)
    upload(first.photo.id)
    answers.push((await (await complete(first.photo.id, { expectReading: true })).json()).data)
    const readPhoto = '00000000-0000-4000-8000-000000000a11'
    seed(readPhoto, 'side', {
      status: 'processed',
      actual_size_bytes: 1200,
      uploaded_at: STORED_AT,
      processed_at: STORED_AT,
      processing_request_id: 'e'.repeat(64),
      processing_result: {
        type: 'body',
        view: 'side',
        bf_percent_estimate: 23,
        bf_confidence: 0.5,
        notes: 'anotação livre do modelo sobre o corpo',
        posture_notes: 'anotação sobre a postura',
      },
    })
    answers.push(await readState())
    answers.push((await (await create('front', { key: 'body-photo-create-0002' })).json()).data)
    const projected = await createSupabaseSignupBodyPhotoDependencies(db().client, {
      enabled: true,
    }).catalogue.listOpen(ACCOUNT)
    expect(projected.length).toBeGreaterThan(0)
    expect(projected.some((photo) => photo.id === readPhoto)).toBe(true)
    for (const photo of projected) {
      expect(Object.keys(photo).sort()).toEqual(
        [
          'id',
          'bucketId',
          'objectPath',
          'pose',
          'status',
          'failureStage',
          'createdAt',
          'uploadedAt',
          'bodyFatPercent',
        ].sort(),
      )
      expect(photo.bodyFatPercent).toBe(photo.id === readPhoto ? 23 : null)
    }
    answers.push((await (await remove()).json()).data)

    const everything = JSON.stringify(answers)
    for (const forbidden of [
      'Foto de',
      'context',
      'result',
      'notes',
      'anotação',
      'bf_percent',
      'bf_confidence',
      'confidence',
      'view',
      'object_path',
      'bucket',
      'retention',
      'source_request_hash',
    ]) {
      expect(everything, forbidden).not.toContain(forbidden)
    }
    // The object's address is only inside the upload ticket, never as a field.
    expect(everything).toContain('"signed_url":"https://storage.test/object/upload/sign/')
    expect(everything.replace(/"signed_url":"[^"]*"/g, '"signed_url":"<ticket>"')).not.toContain(
      ACCOUNT,
    )
    // B3 selects the private reading internally but projects only its number.
    // The public DTO assertions above still prohibit any reading fields.
    const listed = db().calls.filter(
      (call) =>
        call.operation === 'select:media_assets' &&
        (call.detail as { filters: Array<{ column: string }> }).filters.some(
          (filter) => filter.column === 'kind',
        ),
    )
    expect(listed.length).toBeGreaterThan(0)
    for (const call of listed) {
      const columns = (call.detail as { columns: string }).columns
      expect(columns).toBe(
        columns.includes('status')
          ? 'id, bucket_id, object_path, status, failure_stage, context_text, created_at, uploaded_at, processing_result'
          : 'context_text',
      )
    }
  })

  it('S3 reading an open signup uses one official snapshot then one completion repair', async () => {
    await store('front')
    const queuedBeforeRead = structuredClone(world.queue)
    db().operations.length = 0

    const state = await readState()
    assertPrivate(state)

    expect(db().operations).toEqual([
      ...AUTHENTICATION,
      'rpc:get_mobile_legal_document',
      'rpc:get_mobile_signup_body_photo_snapshot',
      'rpc:prepare_mobile_signup_body_photo_disposition',
    ])
    expect(world.queue).toEqual(queuedBeforeRead)
  })

  it('S4 a catalogue that cannot be read is 500, not "no photos"', async () => {
    await store('front')
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
    db().failNext('rpc:get_mobile_signup_body_photo_snapshot')

    const response = await GET(request('GET', '', {}))

    expect(await errorOf(response)).toEqual({ status: 500, code: 'data_access_failed' })
  })
})

describe('declared pendencies', () => {
  const doc = readFileSync(new URL('../../../../../docs/mobile/api-v1.md', import.meta.url), 'utf8')

  it('every "RC P-PHOTOS" line of the docs is in the header of a test of these routes, identical: this file and the consent test', () => {
    const linesOf = (source: string) =>
      Array.from(source.matchAll(/^ \* (> RC P-PHOTOS — .*)$/gm), (match) => match[1] ?? '')
    const here = linesOf(readFileSync(new URL(import.meta.url), 'utf8'))
    const consent = linesOf(
      readFileSync(
        new URL(
          '../../app/api/mobile/v1/onboarding/body-photos/consent/route.test.ts',
          import.meta.url,
        ),
        'utf8',
      ),
    )
    const fromDoc = Array.from(doc.matchAll(/^(> RC P-PHOTOS — .*)$/gm), (match) => match[1] ?? '')

    expect(consent).toHaveLength(7)
    expect(here).toHaveLength(12)
    for (const line of here) {
      expect(line).toMatch(
        /^> RC P-PHOTOS — cenário .+ variante .+ NÃO coberta nesta PR \(pendência da audit 2026-10-11\)$/,
      )
    }
    expect(fromDoc).toEqual([...consent, ...here])
  })

  it('the docs say what is whose decision, and that reading is exclusive to the consented sign-up', () => {
    const flat = doc.replace(/\s+/g, ' ')
    const start = flat.indexOf('## Fotos do corpo no cadastro')
    const section = flat.slice(start, flat.indexOf('## Rascunhos de plano', start))

    expect(section).toContain('### Envio por pose, conclusão do envio, troca e exclusão')
    expect(section).toContain('Uploaded pede a leitura pelo emissor existente')
    expect(section).toContain('O limite de 9 é um número do plano, à espera da confirmação do dono')
    expect(section).not.toMatch(/aprovad[oa] pelo (?:dono|médico|Dr\.)/i)
    // B3 opens only the sign-up; the generic refusal remains explicit.
    expect(flat).toContain(
      '### Foto do corpo só vai à leitura por IA pelo cadastro, depois do consentimento próprio',
    )
  })
})

describe('B4b owner decision 2026-10-11: arithmetic mean of three slot readings', () => {
  async function readTriad() {
    await acceptConsent()
    const ids: string[] = []
    for (const [index, pose] of (['front', 'side', 'back'] as const).entries()) {
      const id = await store(pose)
      ids.push(id)
      rowOf(id).status = 'processed'
      rowOf(id).processing_result = { type: 'body', bf_percent_estimate: [18, 24, 30][index] }
    }
    return ids
  }

  it('B4B-02 three processed readings but a new current consent is not accepted: no estimate/writes', async () => {
    const ids = await readTriad()
    publishSecondConsentText()
    db().operations.length = 0
    const state = await readState()
    expect(state.consent.accepted_at).toBeNull()
    expect(state.estimate).toBeNull()
    expect(state.poses.map((slot: { photo: { id: string } }) => slot.photo.id)).toEqual(ids)
    expect(db().operations.some((operation) => /^(insert|update|storage:)/.test(operation))).toBe(
      false,
    )
  })

  it('B4B-03 mean24 survives a pending replacement; completing it selects the new uploaded slot and waits for reading', async () => {
    const ids = await readTriad()
    const replacement = await created('front')
    const before = await readState()
    expect(before.poses.map((slot: { photo: { id: string } }) => slot.photo.id)).toEqual(ids)
    expect(before.estimate.by_sex.masculino).toEqual({ usable: true, body_fat_percent: 24 })
    upload(replacement.photo.id, { size: 480_000 })
    // This is a later completion, not the documented same-instant UUID tie.
    vi.setSystemTime(new Date(NOW.getTime() + 1000))
    expect((await complete(replacement.photo.id, { expectReading: true })).status).toBe(200)
    expect(Date.parse(rowOf(replacement.photo.id).uploaded_at ?? '')).toBeGreaterThan(
      Date.parse(rowOf(ids[0] ?? '').uploaded_at ?? ''),
    )
    const after = await readState()
    expect(after.poses[0].photo).toMatchObject({ id: replacement.photo.id, status: 'uploaded' })
    expect(after.estimate).toBeNull()
    expect(rowOf(ids[0] ?? '').status).toBe('deleted')
  })
  it('B4B-01 EXACT male readings18/24/30 return24 for both sexes, regardless of repeated model views/confidence', async () => {
    await acceptConsent()
    const values = [18, 24, 30]
    const ids: string[] = []
    for (const [index, pose] of (['front', 'side', 'back'] as const).entries()) {
      const id = await store(pose)
      ids.push(id)
      rowOf(id).status = 'processed'
      rowOf(id).processing_result = {
        type: 'body',
        bf_percent_estimate: values[index],
        view: 'front',
        bf_confidence: [0.9, 0.6, 0.7][index],
        composition_notes: 'private synthetic composition',
        posture_notes: 'private synthetic posture',
      }
    }
    db().operations.length = 0
    const state = await readState()
    expect(state.estimate).toEqual({
      is_estimate: true,
      by_sex: {
        masculino: { usable: true, body_fat_percent: 24 },
        feminino: { usable: true, body_fat_percent: 24 },
      },
      source_ids: { front: ids[0], side: ids[1], back: ids[2] },
      fingerprint: expect.stringMatching(/^[0-9a-f]{64}$/),
    })
    const wire = JSON.stringify(state)
    expect(wire).not.toContain('private synthetic')
    expect(wire).not.toContain('confidence')
    expect(wire).not.toContain('view')
    expect(state.estimate).not.toHaveProperty('readings')
    expect(
      db().operations.filter((operation) => /^(insert|update|storage:remove)/.test(operation)),
    ).toEqual([])
    expect(state.poses.map((slot: { photo: { status: string } }) => slot.photo.status)).toEqual([
      'read',
      'read',
      'read',
    ])
  })
})

describe('B4b trusted signup origin: historical body photos are UNKNOWN', () => {
  it('B4B-ORIGIN-11 SQL scopes origin before limit1000:1001 newer UNKNOWN rows cannot hide three signup readings', async () => {
    await acceptConsent()
    const ids: string[] = []
    for (const [index, pose] of (['front', 'side', 'back'] as const).entries()) {
      const id = await store(pose)
      ids.push(id)
      rowOf(id).status = 'processed'
      rowOf(id).processing_result = { type: 'body', bf_percent_estimate: [18, 24, 30][index] }
    }
    const historical = Array.from({ length: 1001 }, (_unused, index) => {
      const row = db().seedMediaAsset({
        id: `00000000-0000-4000-8000-00000002${String(index).padStart(4, '0')}`,
        user_id: ACCOUNT,
        signup_origin: false,
        context_text: 'Foto de frente.',
        created_at: databaseTimestamp(new Date(NOW.getTime() + 60_000 + index)),
      })
      db().upload(row, { size: 1200 })
      return row
    })
    const state = await readState()
    expect(state.poses.map((slot: { photo: { id: string } }) => slot.photo.id)).toEqual(ids)
    expect(state.estimate.by_sex.masculino).toEqual({ usable: true, body_fat_percent: 24 })
    expect(state.remaining_uploads).toBe(6)
    const response = await remove()
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({ deleted: 3 })
    for (const row of historical) {
      expect(row.status).toBe('pending_upload')
      expect(objectOf(row.id)).toBeDefined()
    }
  })
  it.each([
    false,
    null,
  ])('B4B-ORIGIN-01 origin=%s same pose contexts cannot become signup photos or estimates', async (signupOrigin) => {
    await acceptConsent()
    for (const [index, pose] of (['front', 'side', 'back'] as const).entries()) {
      db().seedMediaAsset({
        id: `00000000-0000-4000-8000-000000000c0${index}`,
        user_id: ACCOUNT,
        signup_origin: signupOrigin,
        context_text: POSE_SENTENCE[pose],
        status: 'processed',
        actual_size_bytes: 1200,
        uploaded_at: databaseTimestamp(NOW),
        processed_at: databaseTimestamp(NOW),
        processing_request_id: sha256Hex(`historical-${pose}`),
        processing_result: { type: 'body', bf_percent_estimate: [18, 24, 30][index] },
      })
    }
    const state = await readState()
    expect(state.poses.map((slot: { photo: unknown }) => slot.photo)).toEqual([null, null, null])
    expect(state.estimate).toBeNull()
    expect(state.remaining_uploads).toBe(9)
  })

  it.each([
    false,
    null,
  ])('B4B-ORIGIN-02 origin=%s same context bytes survive DELETE', async (signupOrigin) => {
    const row = db().seedMediaAsset({
      id: '00000000-0000-4000-8000-000000000c10',
      user_id: ACCOUNT,
      signup_origin: signupOrigin,
      context_text: 'Foto de frente.',
    })
    db().upload(row, { size: 1200 })
    const before = structuredClone(row)
    const response = await DELETE(request('DELETE', '', { key: newKey('delete-unknown') }))
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual({ deleted: 0 })
    expect(row).toEqual(before)
    expect(db().objects.has(`${row.bucket_id}/${row.object_path}`)).toBe(true)
    expect(db().operations).not.toContain('storage:remove')
    expect(db().operations).not.toContain('update:media_assets')
  })

  it.each([
    false,
    null,
  ])('B4B-ORIGIN-03 origin=%s same context cannot be completed by signup', async (signupOrigin) => {
    await acceptConsent()
    const row = db().seedMediaAsset({
      id: '00000000-0000-4000-8000-000000000c11',
      user_id: ACCOUNT,
      signup_origin: signupOrigin,
      context_text: 'Foto de frente.',
    })
    db().upload(row, { size: 1200 })
    const before = structuredClone(row)
    const response = await complete(row.id)
    expect(response.status).toBe(404)
    expect((await response.json()).error.code).toBe('body_photo_not_found')
    expect(row).toEqual(before)
    expect(db().operations).not.toContain('storage:info')
    expect(db().operations).not.toContain('update:media_assets')
  })
})
