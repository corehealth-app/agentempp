/**
 * POST /api/mobile/v1/media/:id/process — a body photo is never sent to AI
 * reading by this generic route, whatever the request carries (docs/mobile/api-v1.md,
 * "Foto do corpo só vai à leitura por IA pelo cadastro, depois do consentimento próprio";
 * the golden and the declared pendencies are in
 * lib/mobile-api/media-service.body-photo-ai-guard.test.ts).
 *
 * The exported POST and the media service are the real code. Replaced, as in
 * the other route tests of this tree: the wrapper that authenticates (it
 * hands the handler through), the idempotency ledger (it runs the operation
 * with the Idempotency-Key of the request) and the Supabase dependencies of
 * media (an in-memory catalogue that finds an asset only for its owner, and a
 * queue that records what is sent). The route reads the id and the
 * Idempotency-Key and nothing else: a body or a query naming another kind
 * does not reach the service. No database, no network.
 */
import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { MediaAssetRecord, MediaServiceDependencies } from '@/lib/mobile-api/media-service'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

const ACCOUNT = '00000000-0000-0000-0000-000000000101'
const OTHER_ACCOUNT = '00000000-0000-0000-0000-000000000102'
const ASSET = '00000000-0000-0000-0000-000000000201'
const REQUEST_KEY = 'mobile-media-process-0001'
const PATH = `https://bodyflow.test/api/mobile/v1/media/${ASSET}/process`

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

function context(request: Request, account = ACCOUNT): MobileRouteContext {
  return {
    request,
    requestId: 'request-media-process-0201',
    supabase: {} as unknown as ServiceClient,
    auth: {
      accessToken: 'redacted',
      authUserId: account,
      userId: account,
      identity: { id: account, email: null, emailConfirmedAt: null },
      patient: {
        id: account,
        authUserId: account,
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

type Post = (
  mobileContext: MobileRouteContext,
  routeContext: { params: Promise<{ id: string }> },
) => Promise<Response>

async function loadRoute(stored: MediaAssetRecord) {
  vi.resetModules()
  const sendProcessingRequested = vi.fn(
    async (_input: { assetId: string; userId: string; requestId: string }) => undefined,
  )
  const findOwned = vi.fn(async (userId: string, assetId: string) =>
    stored.user_id === userId && stored.id === assetId ? stored : null,
  )
  const dependencies: MediaServiceDependencies = {
    repository: {
      findByRequestHash: vi.fn(),
      create: vi.fn(),
      findOwned,
      markUploaded: vi.fn(),
      markUploadFailed: vi.fn(),
      markDeleted: vi.fn(),
    },
    storage: {
      createSignedUpload: vi.fn(),
      getObjectInfo: vi.fn(),
      createSignedDownload: vi.fn(),
      remove: vi.fn(),
    },
    events: { sendProcessingRequested },
  }
  vi.doMock('@/lib/mobile-api/route', () => ({
    createMobileRouteWithContext: (handler: Post) => handler,
  }))
  vi.doMock('@/lib/mobile-api/idempotency', () => ({
    executeSupabaseIdempotent: async (
      mobileContext: MobileRouteContext,
      _payload: unknown,
      operation: (idempotencyKey: string) => Promise<Response>,
    ) => operation(mobileContext.request.headers.get('idempotency-key') ?? ''),
  }))
  vi.doMock('@/lib/mobile-api/supabase-media', () => ({
    createSupabaseMediaDependencies: () => dependencies,
  }))
  const route = await import('./route')
  return { post: route.POST as unknown as Post, sendProcessingRequested, findOwned }
}

afterEach(() => {
  vi.doUnmock('@/lib/mobile-api/route')
  vi.doUnmock('@/lib/mobile-api/idempotency')
  vi.doUnmock('@/lib/mobile-api/supabase-media')
  vi.resetModules()
})

const routeContext = () => ({ params: Promise.resolve({ id: ASSET }) })
const keyed = { 'idempotency-key': REQUEST_KEY }

/** What the route ended in, without letting a refusal throw past the assertions. */
function outcomeOf(call: Promise<Response>) {
  return call.then(
    (response) => ({ status: response.status }),
    (error: { status?: unknown; code?: unknown }) => ({ status: error.status, code: error.code }),
  )
}

describe('POST /media/:id/process', () => {
  it.each([
    ['no body', () => new Request(PATH, { method: 'POST', headers: keyed })],
    [
      'a JSON body naming another kind with force',
      () =>
        new Request(PATH, {
          method: 'POST',
          headers: { ...keyed, 'content-type': 'application/json' },
          body: JSON.stringify({ kind: 'meal_photo', hint: 'meal', force: true }),
        }),
    ],
    [
      'a query naming another kind',
      () => new Request(`${PATH}?kind=meal_photo&hint=meal`, { method: 'POST', headers: keyed }),
    ],
  ] satisfies [
    string,
    () => Request,
  ][])('for a body photo is refused whatever the request carries (%s): no reading event', async (_label, request) => {
    const { post, sendProcessingRequested } = await loadRoute(bodyPhoto())

    const outcome = await outcomeOf(post(context(request()), routeContext()))

    expect(sendProcessingRequested).toHaveBeenCalledTimes(0)
    expect(outcome).toEqual({ status: 422, code: 'media_kind_not_supported' })
  })

  it('a meal photo of the same account is accepted with 202 and one reading event carrying the hash of the Idempotency-Key', async () => {
    const { post, sendProcessingRequested } = await loadRoute(
      bodyPhoto({
        kind: 'meal_photo',
        bucket_id: 'meal-photos',
        retention_until: '2026-08-19T12:00:00.000Z',
      }),
    )

    const response = await post(
      context(new Request(PATH, { method: 'POST', headers: keyed })),
      routeContext(),
    )

    expect(response.status).toBe(202)
    expect(sendProcessingRequested.mock.calls).toEqual([
      [
        {
          assetId: ASSET,
          userId: ACCOUNT,
          requestId: createHash('sha256').update(REQUEST_KEY).digest('hex'),
        },
      ],
    ])
    expect((await response.json()).data).toMatchObject({
      id: ASSET,
      kind: 'meal_photo',
      status: 'uploaded',
    })
  })

  it("another account's body photo is 404 media_asset_not_found with nothing sent", async () => {
    const { post, sendProcessingRequested, findOwned } = await loadRoute(bodyPhoto())

    const outcome = await outcomeOf(
      post(
        context(new Request(PATH, { method: 'POST', headers: keyed }), OTHER_ACCOUNT),
        routeContext(),
      ),
    )

    expect(sendProcessingRequested).toHaveBeenCalledTimes(0)
    expect(outcome).toEqual({ status: 404, code: 'media_asset_not_found' })
    expect(findOwned).toHaveBeenCalledWith(OTHER_ACCOUNT, ASSET)
  })
})
