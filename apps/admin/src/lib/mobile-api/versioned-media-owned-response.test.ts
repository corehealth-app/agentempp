import type { ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from './route'
import { versionedOwnedMediaResponse } from './versioned-media-owned-response'

const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
const owner = 'c1711000-0000-4000-8000-000000000001',
  id = 'c1711000-0000-4000-8000-000000000002'
const path = `conversation-v2/${owner}/${id}.m4a`,
  at = '2026-11-17T20:00:00.000Z'
const env = {
  MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED: 'true',
  MOBILE_CONVERSATION_MEDIA_PROTOCOL_ENABLED: 'true',
  MOBILE_CONVERSATION_INTAKES_ENABLED: 'true',
  MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
  NEXT_PUBLIC_SUPABASE_URL: origin,
}
function setup(
  mode: 'normal' | 'legacy' | 'missing' | 'mismatch' | 'outage' | 'withdraw' = 'normal',
) {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date(at))
  const calls: Array<{ path: string; method: string; body: unknown }> = []
  const row = {
    id,
    user_id: owner,
    kind: 'audio_note',
    bucket_id: 'audio-notes',
    object_path: path,
    mime_type: 'audio/mp4',
    declared_size_bytes: 8,
    actual_size_bytes: null as number | null,
    etag: null as string | null,
    status: 'pending_upload',
    failure_stage: null,
    failure_code: null,
    context_text: null,
    processing_request_id: null,
    processing_result: null,
    source_request_hash: 'a'.repeat(64),
    retention_until: '2026-12-17T20:00:00.000Z',
    uploaded_at: null as string | null,
    processed_at: null,
    deleted_at: null as string | null,
    created_at: at,
    updated_at: at,
  }
  const json = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } })
  const client = createClient(origin, 'synthetic-only-key', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: async (input, init) => {
        const req = new Request(input, init),
          url = new URL(req.url)
        expect(url.origin).toBe(origin)
        const body = req.method === 'GET' ? null : await req.json()
        calls.push({ path: url.pathname, method: req.method, body })
        if (url.pathname.startsWith('/rest/v1/rpc/')) {
          expect(body.p_user_id).toBe(owner)
          const name = url.pathname.split('/').at(-1)
          if (name === 'resolve_conversation_media_catalog_v2') {
            expect(body).toEqual({ p_user_id: owner, p_asset_id: id, p_source_request_hash: null })
            return json({
              schema: 'conversation.media-catalog.v2',
              catalog_version: mode === 'legacy' ? 1 : 2,
              asset_id: id,
              user_id: owner,
              kind: 'audio_note',
            })
          }
          expect(body.p_asset_id).toBe(id)
          if (name === 'get_conversation_media_asset_v2')
            return json({ schema: 'conversation.media-asset.v2', catalog_version: 2, asset: row })
          if (name === 'complete_conversation_media_upload_v2') {
            expect(body).toEqual({
              p_user_id: owner,
              p_asset_id: id,
              p_actual_size_bytes: 8,
              p_mime_type: 'audio/mp4',
              p_etag: 'etag',
            })
            Object.assign(row, {
              status: 'uploaded',
              actual_size_bytes: 8,
              etag: 'etag',
              uploaded_at: at,
            })
            return json({ schema: 'conversation.media-asset.v2', catalog_version: 2, asset: row })
          }
          if (name === 'close_conversation_media_v2') {
            Object.assign(row, { status: 'deleted', deleted_at: at })
            return json(true)
          }
        }
        if (url.pathname === `/storage/v1/object/info/audio-notes/${path}`) {
          if (mode === 'outage')
            return json({ statusCode: '503', error: 'unavailable', message: 'unavailable' }, 503)
          if (mode === 'missing')
            return json({ statusCode: '404', error: 'not_found', message: 'not_found' }, 404)
          if (mode === 'withdraw') envForTest.MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED = 'false'
          return json({
            id,
            version: 'c1711000-0000-4000-8000-000000000003',
            name: path,
            bucket_id: 'audio-notes',
            size: mode === 'mismatch' ? 9 : 8,
            content_type: 'audio/mp4',
            cache_control: '0',
            etag: 'etag',
            created_at: at,
            updated_at: at,
            last_modified: at,
          })
        }
        if (url.pathname === `/storage/v1/object/sign/audio-notes/${path}`) {
          expect(body).toEqual({ expiresIn: 300 })
          return json({ signedURL: `/object/sign/audio-notes/${path}?token=synthetic-only` })
        }
        return json({ code: '42501', message: 'Unexpected physical IO' }, 400)
      },
    },
  }) as unknown as ServiceClient
  const envForTest = { ...env }
  const context = {
    supabase: client,
    auth: { userId: owner },
    requestId: 'r171-sdk',
  } as MobileRouteContext
  return { calls, row, context, env: envForTest }
}
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllEnvs()
})
vi.mock('@/lib/mobile-api/route', () => ({
  createMobileRouteWithContext: (handler: unknown) => handler,
}))
vi.mock('@/lib/mobile-api/idempotency', () => ({
  executeSupabaseIdempotent: async (
    _context: unknown,
    _input: unknown,
    operation: () => Promise<Response>,
  ) => operation(),
}))
describe('owned media response installed SDK boundary', () => {
  it('uses the same server client to complete and then read the selected private source', async () => {
    const x = setup()
    let fallbacks = 0
    const legacy = async () => {
      fallbacks++
      return Response.json({ legacy: true })
    }
    const complete = await versionedOwnedMediaResponse(x.context, id, 'complete', legacy, x.env)
    expect(complete.status).toBe(200)
    expect(await complete.json()).toMatchObject({ data: { id, status: 'uploaded', size_bytes: 8 } })
    const read = await versionedOwnedMediaResponse(x.context, id, 'read', legacy, x.env)
    expect(await read.json()).toMatchObject({
      data: {
        id,
        download: {
          signed_url: `${origin}/storage/v1/object/sign/audio-notes/${path}?token=synthetic-only`,
          expires_in_seconds: 300,
        },
      },
    })
    expect(fallbacks).toBe(0)
    expect(
      x.calls.filter((c) => c.path.includes('complete_conversation_media_upload_v2')),
    ).toHaveLength(1)
  })
  it('returns the identical legacy response for an old source without private reads', async () => {
    const x = setup('legacy'),
      original = Response.json({ legacy: true })
    expect(
      await versionedOwnedMediaResponse(x.context, id, 'read', async () => original, x.env),
    ).toBe(original)
    expect(x.calls).toHaveLength(1)
  })
  it('does no SDK operation when the trusted private gate is off', async () => {
    const x = setup(),
      original = Response.json({ legacy: true })
    expect(
      await versionedOwnedMediaResponse(x.context, id, 'complete', async () => original, {}),
    ).toBe(original)
    expect(x.calls).toEqual([])
  })
  it.each([
    'missing',
    'mismatch',
  ] as const)('persists independent source closure for %s instead of using a plain Storage remove', async (mode) => {
    const x = setup(mode)
    await expect(
      versionedOwnedMediaResponse(
        x.context,
        id,
        'complete',
        async () => {
          throw Error('forbidden legacy fallback')
        },
        x.env,
      ),
    ).rejects.toMatchObject({
      code: mode === 'missing' ? 'media_upload_missing' : 'media_upload_mismatch',
    })
    expect(x.row.status).toBe('deleted')
    expect(x.calls.some((c) => c.method === 'DELETE')).toBe(false)
  })
  it('does not close a source on a Storage outage', async () => {
    const x = setup('outage')
    await expect(
      versionedOwnedMediaResponse(
        x.context,
        id,
        'complete',
        async () => {
          throw Error('forbidden fallback')
        },
        x.env,
      ),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
    expect(x.row.status).toBe('pending_upload')
    expect(x.calls.some((c) => c.path.includes('close_conversation'))).toBe(false)
  })
  it('refuses opt-in withdrawal before committing completion', async () => {
    const x = setup('withdraw')
    await expect(
      versionedOwnedMediaResponse(
        x.context,
        id,
        'complete',
        async () => {
          throw Error('forbidden fallback')
        },
        x.env,
      ),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
    expect(x.row.status).toBe('pending_upload')
  })
})

describe('exported owned media routes', () => {
  it('GET selects the private source through the real route and SDK', async () => {
    const x = setup()
    Object.assign(x.row, { status: 'uploaded', actual_size_bytes: 8, uploaded_at: at })
    for (const [key, value] of Object.entries(x.env)) vi.stubEnv(key, value)
    const route = await import('../../app/api/mobile/v1/media/[id]/route')
    const get = route.GET as unknown as (
      context: MobileRouteContext,
      route: { params: Promise<{ id: string }> },
    ) => Promise<Response>
    const response = await get(x.context, { params: Promise.resolve({ id }) })
    expect(await response.json()).toMatchObject({
      data: { id, status: 'uploaded', download: { expires_in_seconds: 300 } },
    })
  })
  it('complete selects the private source through the real route and SDK', async () => {
    const x = setup()
    for (const [key, value] of Object.entries(x.env)) vi.stubEnv(key, value)
    const route = await import('../../app/api/mobile/v1/media/[id]/complete/route')
    const post = route.POST as unknown as (
      context: MobileRouteContext,
      route: { params: Promise<{ id: string }> },
    ) => Promise<Response>
    const response = await post(x.context, { params: Promise.resolve({ id }) })
    expect(await response.json()).toMatchObject({ data: { id, status: 'uploaded', size_bytes: 8 } })
  })
})
