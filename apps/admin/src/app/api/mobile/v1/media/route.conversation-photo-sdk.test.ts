/** Real handler, service AND Supabase factory/closed row decoder. Only the
 * external Auth/SDK/idempotency store is synthetic; no network or credentials. */
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  completeMediaUpload,
  createMediaAsset,
  getMediaAsset,
} from '@/lib/mobile-api/media-service'
import { createSupabaseMediaDependencies } from '@/lib/mobile-api/supabase-media'
import { auth } from '@/lib/mobile-api/testing/confirmed-meal-fixtures'

const ports = vi.hoisted(() => ({ client: vi.fn() }))
vi.mock('@/lib/mobile-api/route', async (original) => {
  const actual = await original<typeof import('@/lib/mobile-api/route')>()
  return {
    ...actual,
    createMobileRoute: (handler: Parameters<typeof actual.createMobileRoute>[0]) =>
      actual.createMobileRoute(handler, {
        authenticate: async () => auth,
        authorizeEntitlement: async () => undefined,
        createServiceClient: ports.client,
        createRequestId: () => 'synthetic-sdk-request',
      }),
  }
})
vi.mock('@/lib/mobile-api/idempotency', () => ({
  executeSupabaseIdempotent: async (_ctx: unknown, _input: unknown, op: () => unknown) => op(),
}))
const { POST } = await import('./route')
function fixture() {
  let row: Record<string, unknown> | null = null,
    collision = false
  const signed = vi.fn(async () => ({
    data: { signedUrl: 'https://storage.invalid/synthetic' },
    error: null,
  }))
  const from = vi.fn(() => {
    let mode = 'read',
      value: Record<string, unknown> = {},
      filters: Record<string, unknown> = {}
    const q = {
      select: (_columns: string) => q,
      eq: (k: string, v: unknown) => {
        filters[k] = v
        return q
      },
      is: (k: string, v: unknown) => {
        filters[k] = v
        return q
      },
      insert: (v: Record<string, unknown>) => {
        mode = 'insert'
        value = v
        return q
      },
      update: (v: Record<string, unknown>) => {
        mode = 'update'
        value = v
        return q
      },
      maybeSingle: async () => {
        if (mode === 'insert') {
          if (collision)
            return { data: null, error: { code: '23505', message: 'synthetic unique collision' } }
          row = {
            ...value,
            actual_size_bytes: null,
            status: 'pending_upload',
            failure_stage: null,
            failure_code: null,
            uploaded_at: null,
            processed_at: null,
            deleted_at: null,
            processing_result: null,
            created_at: '2026-11-06T12:00:00Z',
            updated_at: '2026-11-06T12:00:00Z',
          }
        } else if (!row || Object.entries(filters).some(([k, v]) => row?.[k] !== v))
          return { data: null, error: null }
        if (mode === 'update') row = { ...row, ...value }
        return { data: structuredClone(row), error: null }
      },
    }
    return q
  })
  const sdk = {
    from,
    storage: {
      from: () => ({
        createSignedUploadUrl: signed,
        createSignedUrl: signed,
        info: async () => ({
          data: { size: 1200, contentType: 'image/jpeg', etag: 'synthetic' },
          error: null,
        }),
      }),
    },
  } as unknown as ServiceClient
  return {
    sdk,
    from,
    signed,
    get: () => row,
    set: (v: Record<string, unknown>) => {
      row = v
    },
    collide: () => {
      collision = true
    },
  }
}
describe('conversation photo through real Supabase adapter', () => {
  const key = 'synthetic-photo-sdk-key',
    input = {
      kind: 'conversation_photo' as const,
      mime_type: 'image/jpeg' as const,
      size_bytes: 1200,
    },
    options = { conversationPhotoEnabled: () => true }
  const request = () =>
    POST(
      new Request('https://example.invalid/api/mobile/v1/media', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': key,
          'X-Conversation-Owner': auth.userId,
        },
        body: JSON.stringify(input),
      }),
    )
  beforeEach(() => {
    vi.clearAllMocks()
    vi.stubEnv('MOBILE_CONVERSATION_PHOTOS_ENABLED', 'true')
    vi.stubEnv('MOBILE_CONVERSATION_INTAKES_ENABLED', 'true')
    vi.stubEnv('MOBILE_CURRENT_CLINICAL_PROJECT_REF', 'xitugspwfxkcluxvrdeg')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
  })
  afterEach(() => vi.unstubAllEnvs())
  it('returns an upload ticket and replays the same row through the actual handler/factory', async () => {
    const f = fixture()
    ports.client.mockReturnValue(f.sdk)
    const first = await request()
    expect(first.status).toBe(201)
    const body = await first.json()
    expect(body.data.asset.kind).toBe('conversation_photo')
    expect(body.data.upload).not.toBeNull()
    const second = await request()
    expect(second.status).toBe(201)
    expect((await second.json()).data.asset.id).toBe(body.data.asset.id)
    expect(f.get()?.kind).toBe('conversation_photo')
  })
  it('supports lookup by hash/owner, upload completion and strict processed-result reads', async () => {
    const f = fixture(),
      deps = createSupabaseMediaDependencies(f.sdk)
    const made = await createMediaAsset(
      deps,
      auth.userId,
      input,
      key,
      undefined,
      undefined,
      options,
    )
    expect((await deps.repository.findOwned(auth.userId, made.asset.id))?.kind).toBe(
      'conversation_photo',
    )
    const complete = await completeMediaUpload(deps, auth.userId, made.asset.id)
    expect(complete.status).toBe('uploaded')
    f.set({
      ...f.get(),
      status: 'processed',
      processed_at: '2026-11-06T12:02:00Z',
      processing_result: {
        schema: 'conversation.image-result.v1',
        status: 'unsupported',
        classification: 'body',
        reason: 'image_not_supported_for_conversation',
      },
    })
    expect((await getMediaAsset(deps, auth.userId, made.asset.id)).result).toMatchObject({
      status: 'unsupported',
    })
    expect(
      await deps.repository.findOwned('00000000-0000-4000-8000-000000000099', made.asset.id),
    ).toBeNull()
  })
  it('keeps the genuine uniqueness-collision lookup on the same immutable row', async () => {
    const f = fixture(),
      deps = createSupabaseMediaDependencies(f.sdk)
    const made = await createMediaAsset(
      deps,
      auth.userId,
      input,
      key,
      undefined,
      undefined,
      options,
    )
    f.collide()
    const row = f.get()
    if (!row) throw new Error('missing fixture row')
    const hash = String(row.source_request_hash)
    const stored = await deps.repository.create({
      id: made.asset.id,
      userId: auth.userId,
      kind: input.kind,
      bucketId: 'meal-photos',
      objectPath: String(row.object_path),
      mimeType: input.mime_type,
      declaredSizeBytes: 1200,
      contextText: null,
      sourceRequestHash: hash,
      retentionUntil: String(row.retention_until),
    })
    expect(stored.id).toBe(made.asset.id)
  })
  it.each([
    'unknown_kind',
    'malformed',
  ])('still refuses %s rows in the actual decoder', async (bad) => {
    const f = fixture(),
      deps = createSupabaseMediaDependencies(f.sdk)
    const made = await createMediaAsset(
      deps,
      auth.userId,
      input,
      key,
      undefined,
      undefined,
      options,
    )
    f.set({
      ...f.get(),
      ...(bad === 'unknown_kind' ? { kind: 'unknown' } : { declared_size_bytes: -1 }),
    })
    await expect(deps.repository.findOwned(auth.userId, made.asset.id)).rejects.toThrow(
      'Invalid media asset database response',
    )
  })
})
