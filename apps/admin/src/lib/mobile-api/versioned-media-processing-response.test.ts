import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from './route'
import { versionedMediaProcessingResponse } from './versioned-media-processing-response'

const events = vi.hoisted(() => ({
  send: vi.fn(async (_input: unknown) => ({ ids: ['synthetic-event'] })),
}))
vi.mock('@mpp/inngest-functions/client', async (original) => {
  const actual = await original<typeof import('@mpp/inngest-functions/client')>()
  vi.spyOn(actual.inngest, 'send').mockImplementation(events.send)
  return actual
})
vi.mock('@/lib/mobile-api/route', () => ({
  createMobileRouteWithContext: (handler: unknown) => handler,
}))
vi.mock('@/lib/mobile-api/idempotency', () => ({
  executeSupabaseIdempotent: async (_c: unknown, _p: unknown, fn: () => Promise<Response>) => fn(),
}))
const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co',
  owner = 'c1730000-0000-4000-8000-000000000001',
  id = 'c1730000-0000-4000-8000-000000000002'
const at = '2026-11-17T21:00:00.000Z',
  key = 'r173-private-processing-0001'
const env = {
  MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED: 'true',
  MOBILE_CONVERSATION_MEDIA_PROTOCOL_ENABLED: 'true',
  MOBILE_CONVERSATION_INTAKES_ENABLED: 'true',
  MOBILE_CURRENT_CLINICAL_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
  NEXT_PUBLIC_SUPABASE_URL: origin,
}
function setup(version = 2) {
  vi.useFakeTimers({ toFake: ['Date'] })
  vi.setSystemTime(new Date(at))
  events.send.mockClear()
  const calls: string[] = []
  const row = {
    id,
    user_id: owner,
    kind: 'audio_note',
    bucket_id: 'audio-notes',
    object_path: `conversation-v2/${owner}/${id}.m4a`,
    mime_type: 'audio/mp4',
    declared_size_bytes: 8,
    actual_size_bytes: 8,
    etag: 'etag',
    status: 'uploaded',
    failure_stage: null,
    failure_code: null,
    context_text: 'Leite com whey',
    processing_request_id: null,
    processing_result: null,
    source_request_hash: 'b'.repeat(64),
    retention_until: '2026-12-17T21:00:00.000Z',
    uploaded_at: at,
    processed_at: null,
    deleted_at: null,
    created_at: at,
    updated_at: at,
  }
  const json = (value: unknown, status = 200) => Response.json(value, { status })
  const client = createClient(origin, 'synthetic-server-only', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: async (input, init) => {
        const req = new Request(input, init)
        const url = new URL(req.url)
        expect(url.origin).toBe(origin)
        calls.push(url.pathname)
        if (
          req.method === 'POST' &&
          url.pathname === '/rest/v1/rpc/resolve_conversation_media_catalog_v2'
        ) {
          expect(await req.json()).toEqual({
            p_user_id: owner,
            p_asset_id: id,
            p_source_request_hash: null,
          })
          return json({
            schema: 'conversation.media-catalog.v2',
            catalog_version: version,
            user_id: owner,
            asset_id: id,
            kind: 'audio_note',
          })
        }
        if (
          req.method === 'POST' &&
          url.pathname === '/rest/v1/rpc/get_conversation_media_asset_v2'
        )
          return json({ schema: 'conversation.media-asset.v2', catalog_version: 2, asset: row })
        return json({ code: '42501', message: 'Unexpected physical IO' }, 400)
      },
    },
  }) as unknown as ServiceClient
  const context = {
    supabase: client,
    request: new Request(`${origin}/api/mobile/v1/media/${id}/process`, {
      method: 'POST',
      headers: { 'idempotency-key': key },
    }),
    auth: { userId: owner },
    requestId: 'r173-sdk-process',
  } as MobileRouteContext
  return { context, calls, row }
}
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllEnvs()
  events.send.mockReset()
  events.send.mockResolvedValue({ ids: ['synthetic-event'] })
})
describe('private processing response and internal event boundary', () => {
  it('returns202 and queues only a source-proven private versioned event', async () => {
    const x = setup(),
      response = await versionedMediaProcessingResponse(
        x.context,
        id,
        async () => {
          throw Error('forbidden legacy fallback')
        },
        env,
      )
    expect(response.status).toBe(202)
    expect(await response.json()).toMatchObject({ data: { id, status: 'uploaded' } })
    const hash = createHash('sha256').update(key).digest('hex')
    expect(events.send).toHaveBeenCalledWith({
      id: `conversation-media-v2:${id}:${hash}`,
      name: 'conversation.media.private.process.requested',
      data: {
        schema: 'conversation.media-process.v2',
        catalogVersion: 2,
        assetId: id,
        userId: owner,
        requestId: hash,
      },
    })
    expect(x.calls.every((p) => p.startsWith('/rest/v1/rpc/'))).toBe(true)
  })
  it('returns the identical old response for a legacy source without publishing a v2 event', async () => {
    const x = setup(1),
      original = Response.json({ legacy: true }, { status: 202 })
    expect(await versionedMediaProcessingResponse(x.context, id, async () => original, env)).toBe(
      original,
    )
    expect(events.send).not.toHaveBeenCalled()
  })
  it('keeps private creation disabled without touching the SDK or event service', async () => {
    const x = setup(),
      original = Response.json({ legacy: true })
    expect(await versionedMediaProcessingResponse(x.context, id, async () => original, {})).toBe(
      original,
    )
    expect(x.calls).toEqual([])
    expect(events.send).not.toHaveBeenCalled()
  })
  it('does not pretend a queue outage is an accepted processing request', async () => {
    const x = setup()
    events.send.mockRejectedValue(Error('private provider diagnostic'))
    await expect(
      versionedMediaProcessingResponse(
        x.context,
        id,
        async () => {
          throw Error('forbidden fallback')
        },
        env,
      ),
    ).rejects.toMatchObject({ code: 'media_catalog_unavailable' })
  })
  it('routes the exported POST through the private SDK response and event service', async () => {
    const x = setup()
    for (const [name, value] of Object.entries(env)) vi.stubEnv(name, value)
    const route = await import('../../app/api/mobile/v1/media/[id]/process/route')
    const post = route.POST as unknown as (
      context: MobileRouteContext,
      route: { params: Promise<{ id: string }> },
    ) => Promise<Response>
    expect((await post(x.context, { params: Promise.resolve({ id }) })).status).toBe(202)
    expect(events.send).toHaveBeenCalledTimes(1)
  })
})
