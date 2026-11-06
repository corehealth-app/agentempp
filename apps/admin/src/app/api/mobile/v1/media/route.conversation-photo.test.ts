/** Real HTTP wrapper/handler/service; SDK and idempotency ledger are synthetic.
 * Exercises opt-in + owner binding, without Auth/network/Storage effects. */
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MediaAssetRecord, MediaServiceDependencies } from '@/lib/mobile-api/media-service'
import { auth } from '@/lib/mobile-api/testing/confirmed-meal-fixtures'

const ports = vi.hoisted(() => ({ authenticate: vi.fn(), deps: vi.fn() }))
vi.mock('@/lib/mobile-api/route', async (original) => {
  const actual = await original<typeof import('@/lib/mobile-api/route')>()
  return {
    ...actual,
    createMobileRoute: (handler: Parameters<typeof actual.createMobileRoute>[0]) =>
      actual.createMobileRoute(handler, {
        authenticate: ports.authenticate,
        authorizeEntitlement: async () => undefined,
        createServiceClient: () => ({}) as ServiceClient,
        createRequestId: () => 'synthetic-http-request',
      }),
  }
})
vi.mock('@/lib/mobile-api/supabase-media', () => ({ createSupabaseMediaDependencies: ports.deps }))
vi.mock('@/lib/mobile-api/idempotency', () => ({
  executeSupabaseIdempotent: async (_ctx: unknown, _input: unknown, operation: () => unknown) =>
    operation(),
}))
const { POST } = await import('./route')
describe('conversational photo HTTP purpose', () => {
  let row: MediaAssetRecord | null = null,
    deps: MediaServiceDependencies
  const request = (kind = 'conversation_photo', owner: string | null = auth.userId) =>
    POST(
      new Request('https://example.invalid/api/mobile/v1/media', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': 'synthetic-photo-key',
          ...(owner === null ? {} : { 'X-Conversation-Owner': owner }),
        },
        body: JSON.stringify({ kind, mime_type: 'image/jpeg', size_bytes: 1200 }),
      }),
    )
  beforeEach(() => {
    vi.clearAllMocks()
    row = null
    ports.authenticate.mockResolvedValue(auth)
    vi.stubEnv('MOBILE_CONVERSATION_PHOTOS_ENABLED', 'true')
    vi.stubEnv('MOBILE_CONVERSATION_INTAKES_ENABLED', 'true')
    vi.stubEnv('MOBILE_CURRENT_CLINICAL_PROJECT_REF', 'xitugspwfxkcluxvrdeg')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    deps = {
      repository: {
        findByRequestHash: vi.fn(async () => null),
        create: vi.fn(
          async (i: Parameters<MediaServiceDependencies['repository']['create']>[0]) => {
            row = {
              id: i.id,
              user_id: i.userId,
              kind: i.kind,
              bucket_id: i.bucketId,
              object_path: i.objectPath,
              mime_type: i.mimeType,
              declared_size_bytes: i.declaredSizeBytes,
              actual_size_bytes: null,
              status: 'pending_upload',
              failure_stage: null,
              failure_code: null,
              context_text: i.contextText,
              retention_until: i.retentionUntil,
              uploaded_at: null,
              processed_at: null,
              deleted_at: null,
              created_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            }
            return row
          },
        ),
        findOwned: vi.fn(async () => row),
        markUploaded: vi.fn(),
        markUploadFailed: vi.fn(),
        markDeleted: vi.fn(),
      },
      storage: {
        createSignedUpload: vi.fn(async () => ({
          signedUrl: 'https://storage.invalid/synthetic-upload',
        })),
        getObjectInfo: vi.fn(),
        createSignedDownload: vi.fn(),
        remove: vi.fn(),
      },
      events: { sendProcessingRequested: vi.fn() },
    }
    ports.deps.mockReturnValue(deps)
  })
  afterEach(() => vi.unstubAllEnvs())
  it('creates only the neutral purpose with the matched authenticated patient', async () => {
    const response = await request()
    expect(response.status).toBe(201)
    expect((await response.json()).data.asset.kind).toBe('conversation_photo')
    expect(deps.repository.create).toHaveBeenCalledWith(
      expect.objectContaining({
        kind: 'conversation_photo',
        userId: auth.userId,
        bucketId: 'meal-photos',
      }),
    )
    expect(deps.events.sendProcessingRequested).not.toHaveBeenCalled()
  })
  it.each([
    null,
    '00000000-0000-4000-8000-000000000099',
  ])('refuses missing/remapped owner before capabilities: %s', async (owner) => {
    expect([409, 422]).toContain((await request('conversation_photo', owner)).status)
    expect(deps.repository.create).not.toHaveBeenCalled()
    expect(deps.storage.createSignedUpload).not.toHaveBeenCalled()
  })
  it.each([
    'disabled',
    'wrong-target',
  ])('cannot activate from a client kind when %s', async (condition) => {
    if (condition === 'disabled') vi.stubEnv('MOBILE_CONVERSATION_PHOTOS_ENABLED', 'false')
    else vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://example.invalid')
    const response = await request()
    expect(response.status).toBe(503)
    expect((await response.json()).error.code).toBe('conversation_photo_unavailable')
    expect(deps.repository.findByRequestHash).not.toHaveBeenCalled()
    expect(deps.storage.createSignedUpload).not.toHaveBeenCalled()
  })
  it('keeps existing meal upload without the optional owner header', async () => {
    expect((await request('meal_photo', null)).status).toBe(201)
    expect(deps.repository.create).toHaveBeenCalledWith(
      expect.objectContaining({ kind: 'meal_photo' }),
    )
  })
})
