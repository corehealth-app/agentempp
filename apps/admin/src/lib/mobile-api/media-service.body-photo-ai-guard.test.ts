/**
 * A body photo is never sent to AI reading by the app's server — golden of
 * the audit of 2026-10-09 for C24a (docs/mobile/api-v1.md, "Foto do corpo
 * nunca vai à leitura por IA").
 *
 * This file is the audit golden of C24a. It lives here and not in
 * packages/agent/src/__golden__ because the behaviour belongs to the app's
 * server and the shared engine takes no part in it: importing the media
 * service from the engine package would invert the dependency.
 *
 * THE AUDITED CASE, exact. Account 00000000-0000-0000-0000-000000000101 owns
 * the asset 00000000-0000-0000-0000-000000000201: kind `body_checkin_photo`,
 * bucket `body-checkin-photos`, path
 * `00000000-0000-0000-0000-000000000101/00000000-0000-0000-0000-000000000201.jpg`,
 * `image/jpeg`, 1200 bytes declared and 1200 stored, status `uploaded`, kept
 * until 2028-07-19T12:00:00.000Z. The account calls
 * `POST /api/mobile/v1/media/<asset>/process` with `Idempotency-Key:
 * mobile-media-process-0001`.
 *   before: 202, and the reading event leaves with
 *           { assetId, userId, requestId:
 *           da2513f442502c6d4a506234e1093de51a765f33faa93a33e301b7980d5474eb }
 *           (the sha256 of the key). The reading function takes the kind from
 *           the catalogue row and reads the image with the body-photo prompt,
 *           whose default text asks for a body-fat estimate.
 *   now:    422 `media_kind_not_supported`, no event, and neither the catalogue
 *           row nor the stored object is touched.
 *
 * The kind is refused before the state is looked at, so the answer for a body
 * photo is the same in every state; ownership is still answered first (404),
 * so the refusal does not tell another account that the asset exists. The
 * route reads nothing from the request but the id and the Idempotency-Key
 * (its own test is in app/api/mobile/v1/media/[id]/process/route.test.ts).
 *
 * WHERE THE RULE COMES FROM. Item 11 of the decisions on the method-backlog
 * plan (decisions-v1.md, 2026-10-07; the orchestrator's decisions, not the
 * owner's): body photos are not asked for before it is known who evaluates them. The
 * question of who evaluates them and of what the person sees has no approved
 * answer yet; nothing here decides it. The refusal has no switch and no
 * environment variable: reopening the path is a change of code, with this
 * golden changed on purpose.
 *
 * WHAT IS LOCKED AS UNCHANGED: a meal photo, a gym photo and an audio note
 * leave with the same event as before; a meal photo being read or failed at
 * reading is sent again and one not uploaded yet is still 409; another
 * account's asset is 404 before any kind is looked at; a body photo offered to
 * `POST /plan-imports` — the second caller of the reading event — is refused
 * there as it already was; and the event has one emitter and two callers in
 * the app's server. A plan document asked for reading keeps its own refusal
 * (media-service.test.ts). The replay of a stored answer and the release of a
 * refused key are the generic mechanism locked in idempotency.test.ts
 * ("replays a completed response without running the mutation again", "marks
 * an interrupted operation as failed before propagating the error"); it was
 * not run again here with a body photo (last RC line below).
 *
 * ASSUMED — declared: account, asset, sizes, dates and request keys are
 * synthetic. Repository, storage and queue are in memory. No database was
 * read or written, nothing was deployed.
 *
 * > RC C24a — cenário foto do corpo enviada com outro tipo declarado (meal_photo, gym_photo ou plan_document) variante o servidor reconhecer pelo conteúdo que a imagem é do corpo e recusar a leitura NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C24a — cenário evento media.asset.process.requested publicado direto na fila para uma foto do corpo (fora do servidor do app) variante recusa também na função de leitura NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C24a — cenário pedido de leitura de foto do corpo aceito antes desta mudança e ainda na fila ou em andamento variante cancelar a leitura já despachada NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C24a — cenário foto do corpo lida antes desta mudança (resultado gravado em media_assets.processing_result) variante as respostas de mídia (GET /media/:id, POST /media repetido e POST /media/:id/complete) deixarem de devolver o resultado e apagar o que foi gravado NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C24a — cenário envio e guarda da foto do corpo (POST /media segue aceitando body_checkin_photo, com guarda de 730 dias) variante recusar o envio enquanto não houver avaliador, aceite específico e prazo aprovados NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C24a — cenário código legado do agente de WhatsApp, encerrado (process-message.ts ainda contém a leitura da imagem e a gravação da estimativa de gordura) variante retirar essa leitura do código legado NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C24a — cenário rota contra o banco e a fila reais do ambiente de teste variante teste com Supabase e Inngest reais (os testes usam repositório, armazenamento e fila em memória; nenhum banco foi lido nem gravado) NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C24a — cenário app instalado no iPhone registrando refeição por foto e por áudio e importando plano depois da mudança variante conferência no aparelho NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C24a — cenário servidores já publicados (o ambiente de teste do app e a produção antiga, que publica o mesmo apps/admin no commit em que está) variante recusa em vigor neles NÃO coberta nesta PR (pendência da audit 2026-10-09)
 * > RC C24a — cenário pedido de leitura de foto do corpo aceito antes desta mudança e repetido com a mesma Idempotency-Key em até 24 horas variante resposta 202 gravada devolvida de novo no lugar da recusa (sem novo evento) NÃO coberta nesta PR (pendência da audit 2026-10-09)
 *
 * Carried from the plan of the method backlog (package C24), as written there:
 * > RC C24 — cenário fotos enviadas variante gordura estimada a partir delas NÃO coberta nesta PR (pendência da audit 2026-10-07).
 */
import { readdirSync, readFileSync } from 'node:fs'
import { dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it, vi } from 'vitest'
import {
  type MediaAssetRecord,
  type MediaServiceDependencies,
  requestMediaProcessing,
} from './media-service'
import { createPlanImport, type PlanDraftDependencies } from './plan-draft-service'

const ACCOUNT = '00000000-0000-0000-0000-000000000101'
const OTHER_ACCOUNT = '00000000-0000-0000-0000-000000000102'
const ASSET = '00000000-0000-0000-0000-000000000201'
const REQUEST_KEY = 'mobile-media-process-0001'
/** sha256 of REQUEST_KEY: the request id the reading event carries. */
const REQUEST_ID = 'da2513f442502c6d4a506234e1093de51a765f33faa93a33e301b7980d5474eb'
const REFUSED = { status: 422, code: 'media_kind_not_supported' }

function bodyPhoto(overrides: Partial<MediaAssetRecord> = {}): MediaAssetRecord {
  return {
    id: ASSET,
    user_id: ACCOUNT,
    kind: 'body_checkin_photo',
    bucket_id: 'body-checkin-photos',
    object_path: `${ACCOUNT}/${ASSET}.jpg`,
    mime_type: 'image/jpeg',
    declared_size_bytes: 1200,
    actual_size_bytes: 1200,
    status: 'uploaded',
    failure_stage: null,
    failure_code: null,
    context_text: null,
    retention_until: '2028-07-19T12:00:00.000Z',
    uploaded_at: '2026-07-20T12:05:00.000Z',
    processed_at: null,
    deleted_at: null,
    created_at: '2026-07-20T12:00:00.000Z',
    updated_at: '2026-07-20T12:05:00.000Z',
    ...overrides,
  }
}

/** The catalogue holds one asset; a lookup by another account finds nothing. */
function memory(stored: MediaAssetRecord) {
  const repository = {
    findByRequestHash: vi.fn(),
    create: vi.fn(),
    findOwned: vi.fn(async (userId: string, assetId: string) =>
      stored.user_id === userId && stored.id === assetId ? stored : null,
    ),
    markUploaded: vi.fn(),
    markUploadFailed: vi.fn(),
    markDeleted: vi.fn(),
  }
  const storage = {
    createSignedUpload: vi.fn(),
    getObjectInfo: vi.fn(),
    createSignedDownload: vi.fn(),
    remove: vi.fn(),
  }
  const events = {
    sendProcessingRequested: vi.fn(
      async (_input: { assetId: string; userId: string; requestId: string }) => undefined,
    ),
  }
  const deps: MediaServiceDependencies = { repository, storage, events }
  return { deps, repository, storage, events }
}

/** What a call ended in, without letting a refusal throw past the assertions. */
function outcomeOf<T>(call: Promise<T>) {
  return call.then(
    (dto) => ({ refused: null, dto }),
    (error: { status?: unknown; code?: unknown }) => ({
      refused: { status: error.status, code: error.code },
      dto: null,
    }),
  )
}

function ask(deps: MediaServiceDependencies, account = ACCOUNT) {
  return outcomeOf(requestMediaProcessing(deps, account, ASSET, REQUEST_KEY))
}

describe('a body photo asked for AI reading', () => {
  it('golden: an uploaded body photo asked for reading is refused with 422 media_kind_not_supported and no reading event is sent', async () => {
    const stored = bodyPhoto()
    const { deps, repository, storage, events } = memory(stored)

    const outcome = await ask(deps)

    expect(events.sendProcessingRequested).toHaveBeenCalledTimes(0)
    expect(outcome.refused).toEqual(REFUSED)
    expect(outcome.dto).toBeNull()
    // Neither the catalogue row nor the stored object is touched.
    expect(repository.findOwned).toHaveBeenCalledTimes(1)
    expect(repository.findOwned).toHaveBeenCalledWith(ACCOUNT, ASSET)
    for (const write of [
      repository.findByRequestHash,
      repository.create,
      repository.markUploaded,
      repository.markUploadFailed,
      repository.markDeleted,
      storage.createSignedUpload,
      storage.getObjectInfo,
      storage.createSignedDownload,
      storage.remove,
    ]) {
      expect(write).not.toHaveBeenCalled()
    }
    expect(stored).toEqual(bodyPhoto())
  })

  it.each([
    ['being read (status processing)', { status: 'processing' }],
    [
      'whose reading failed (failed, failure_stage processing, failure_code provider_error)',
      { status: 'failed', failure_stage: 'processing', failure_code: 'provider_error' },
    ],
  ] satisfies [
    string,
    Partial<MediaAssetRecord>,
  ][])('a body photo %s is refused and nothing is sent', async (_label, state) => {
    const { deps, events } = memory(bodyPhoto(state))

    const outcome = await ask(deps)

    expect(events.sendProcessingRequested).toHaveBeenCalledTimes(0)
    expect(outcome.refused).toEqual(REFUSED)
  })

  it.each([
    ['pending_upload', { status: 'pending_upload', actual_size_bytes: null, uploaded_at: null }],
    ['processed', { status: 'processed', processed_at: '2026-07-20T12:06:00.000Z' }],
    [
      'failed at upload (metadata_mismatch)',
      {
        status: 'failed',
        failure_stage: 'upload',
        failure_code: 'metadata_mismatch',
        actual_size_bytes: null,
        uploaded_at: null,
      },
    ],
    ['deleted', { status: 'deleted', deleted_at: '2026-07-20T12:10:00.000Z' }],
  ] satisfies [
    string,
    Partial<MediaAssetRecord>,
  ][])('a body photo %s answers 422 media_kind_not_supported, never 409 — the kind is refused before the state is looked at', async (_label, state) => {
    const { deps, events } = memory(bodyPhoto(state))

    const outcome = await ask(deps)

    expect(events.sendProcessingRequested).toHaveBeenCalledTimes(0)
    expect(outcome.refused).toEqual(REFUSED)
  })
})

describe('what did not change in the reading request', () => {
  it.each([
    ['meal_photo', { kind: 'meal_photo', bucket_id: 'meal-photos' }],
    ['gym_photo', { kind: 'gym_photo', bucket_id: 'gym-photos' }],
    [
      'audio_note',
      {
        kind: 'audio_note',
        bucket_id: 'audio-notes',
        mime_type: 'audio/mp4',
        object_path: `${ACCOUNT}/${ASSET}.m4a`,
      },
    ],
  ] satisfies [
    string,
    Partial<MediaAssetRecord>,
  ][])('%s is still sent to reading exactly as before', async (_kind, other) => {
    const { deps, events } = memory(
      bodyPhoto({ retention_until: '2026-08-19T12:00:00.000Z', ...other }),
    )

    const outcome = await ask(deps)

    expect(events.sendProcessingRequested).toHaveBeenCalledTimes(1)
    expect(events.sendProcessingRequested).toHaveBeenCalledWith({
      assetId: ASSET,
      userId: ACCOUNT,
      requestId: REQUEST_ID,
    })
    expect(outcome.refused).toBeNull()
    expect(outcome.dto).toMatchObject({ id: ASSET, kind: other.kind, status: 'uploaded' })
  })

  it('a meal photo with a caption leaves with the three ids only: the caption is not in the event', async () => {
    const { deps, events } = memory(
      bodyPhoto({
        kind: 'meal_photo',
        bucket_id: 'meal-photos',
        context_text: 'Sensitive meal caption',
      }),
    )

    const outcome = await ask(deps)

    expect(events.sendProcessingRequested.mock.calls).toEqual([
      [{ assetId: ASSET, userId: ACCOUNT, requestId: REQUEST_ID }],
    ])
    expect(JSON.stringify(events.sendProcessingRequested.mock.calls)).not.toContain(
      'Sensitive meal caption',
    )
    expect(outcome.dto).toMatchObject({ id: ASSET, status: 'uploaded', has_context: true })
  })

  it.each([
    ['being read', { status: 'processing' }],
    [
      'whose reading failed',
      { status: 'failed', failure_stage: 'processing', failure_code: 'provider_error' },
    ],
  ] satisfies [
    string,
    Partial<MediaAssetRecord>,
  ][])('a meal photo %s is still sent again', async (_label, state) => {
    const { deps, events } = memory(
      bodyPhoto({ kind: 'meal_photo', bucket_id: 'meal-photos', ...state }),
    )

    const outcome = await ask(deps)

    expect(events.sendProcessingRequested).toHaveBeenCalledTimes(1)
    expect(outcome.refused).toBeNull()
  })

  it('a meal photo not uploaded yet is still 409 media_not_processable', async () => {
    const { deps, events } = memory(
      bodyPhoto({
        kind: 'meal_photo',
        bucket_id: 'meal-photos',
        status: 'pending_upload',
        actual_size_bytes: null,
        uploaded_at: null,
      }),
    )

    const outcome = await ask(deps)

    expect(events.sendProcessingRequested).toHaveBeenCalledTimes(0)
    expect(outcome.refused).toEqual({ status: 409, code: 'media_not_processable' })
  })

  it("another account's body photo is 404 media_asset_not_found before any kind is looked at", async () => {
    const { deps, repository, events } = memory(bodyPhoto())

    const outcome = await ask(deps, OTHER_ACCOUNT)

    expect(events.sendProcessingRequested).toHaveBeenCalledTimes(0)
    expect(outcome.refused).toEqual({ status: 404, code: 'media_asset_not_found' })
    expect(repository.findOwned).toHaveBeenCalledWith(OTHER_ACCOUNT, ASSET)
  })
})

describe('the other caller of the reading event: POST /plan-imports', () => {
  it.each([
    ['uploaded', 'nutrition', {}],
    ['uploaded', 'training', {}],
    [
      'failed at reading',
      'nutrition',
      { status: 'failed', failure_stage: 'processing', failure_code: 'provider_error' },
    ],
    [
      'failed at reading',
      'training',
      { status: 'failed', failure_stage: 'processing', failure_code: 'provider_error' },
    ],
  ] satisfies [
    string,
    'nutrition' | 'training',
    Partial<MediaAssetRecord>,
  ][])('a body photo (%s) offered as a %s plan is refused with 422 media_kind_not_supported: no draft, no reading event', async (_label, domain, state) => {
    const findImportOfMedia = vi.fn()
    const createImport = vi.fn()
    const sendProcessingRequested = vi.fn(
      async (_input: { assetId: string; userId: string; requestId: string }) => undefined,
    )
    const deps: PlanDraftDependencies = {
      repository: { findImportOfMedia, createImport } as never,
      media: { findOwned: async () => bodyPhoto(state) },
      events: { sendProcessingRequested },
    }

    const outcome = await outcomeOf(
      createPlanImport(deps, ACCOUNT, { media_asset_id: ASSET, domain }, 'mobile-plan-import-0001'),
    )

    expect(sendProcessingRequested).toHaveBeenCalledTimes(0)
    expect(outcome.refused).toEqual(REFUSED)
    expect(createImport).not.toHaveBeenCalled()
    expect(findImportOfMedia).not.toHaveBeenCalled()
  })
})

describe('where the reading event can leave from', () => {
  const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..')

  function sourceFiles(directory: string): string[] {
    return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
      const path = resolve(directory, entry.name)
      if (entry.isDirectory()) return sourceFiles(path)
      return /\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name) ? [path] : []
    })
  }

  function filesContaining(text: string): string[] {
    return sourceFiles(sourceRoot)
      .filter((path) => readFileSync(path, 'utf8').includes(text))
      .map((path) => relative(sourceRoot, path).split(sep).join('/'))
      .sort()
  }

  it('the reading event has one emitter and two callers in the app server', () => {
    expect(filesContaining('sendProcessingRequested')).toEqual([
      'lib/mobile-api/media-service.ts',
      'lib/mobile-api/plan-draft-service.ts',
      'lib/mobile-api/supabase-media.ts',
    ])
    expect(filesContaining('media.asset.process.requested')).toEqual([
      'lib/mobile-api/supabase-media.ts',
    ])
  })
})

describe('declared pendencies', () => {
  it('every "RC C24a" line of this header is in docs/mobile/api-v1.md, identical', () => {
    const header = readFileSync(new URL(import.meta.url), 'utf8')
    const doc = readFileSync(
      new URL('../../../../../docs/mobile/api-v1.md', import.meta.url),
      'utf8',
    )
    const fromHeader = Array.from(header.matchAll(/^ \* (> RC C24a — .*)$/gm), (match) => match[1])
    const fromDoc = Array.from(doc.matchAll(/^(> RC C24a — .*)$/gm), (match) => match[1])
    expect(fromHeader).toHaveLength(10)
    for (const line of fromHeader) {
      expect(line).toMatch(
        /^> RC C24a — cenário .+ variante .+ NÃO coberta nesta PR \(pendência da audit 2026-10-09\)$/,
      )
    }
    expect(fromDoc).toEqual(fromHeader)
    // The line the plan of the method backlog already carried for C24, as written there.
    expect(doc).toContain(
      '> RC C24 — cenário fotos enviadas variante gordura estimada a partir delas NÃO coberta nesta PR (pendência da audit 2026-10-07).',
    )
  })
})
