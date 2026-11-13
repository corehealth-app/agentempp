import type { ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { createMediaAsset } from './media-service'
import { createSupabaseMediaDependencies } from './supabase-media'

const user = '11110000-0000-4000-8000-000000000001',
  asset = '11110000-0000-4000-8000-000000000002'
const now = new Date('2026-11-13T03:00:00.000Z'),
  expiry = '2026-11-13T05:00:15.000Z',
  origin = 'https://synthetic.invalid'
function setup(failPrepare = false) {
  const requests: Request[] = []
  let ticket = ''
  const row = {
    id: asset,
    user_id: user,
    kind: 'audio_note',
    bucket_id: 'audio-notes',
    object_path: `${user}/${asset}.m4a`,
    mime_type: 'audio/mp4',
    declared_size_bytes: 100,
    actual_size_bytes: null,
    status: 'pending_upload',
    failure_stage: null,
    failure_code: null,
    context_text: null,
    retention_until: '2026-12-13T03:00:00.000Z',
    uploaded_at: null,
    processed_at: null,
    deleted_at: null,
    processing_result: null,
    created_at: now.toISOString(),
    updated_at: now.toISOString(),
  }
  const wire = {
    id: asset,
    user_id: user,
    kind: row.kind,
    bucket_id: row.bucket_id,
    object_path: row.object_path,
    mime_type: row.mime_type,
    size_bytes: 100,
    status: row.status,
    retention_until: row.retention_until,
  }
  const ticketWire = (registered = false) => ({
    id: ticket,
    asset_id: asset,
    user_id: user,
    prepared_at: now.toISOString(),
    provider_expires_at: registered ? expiry : null,
    registered_at: registered ? now.toISOString() : null,
  })
  const json = (v: unknown, status = 200) =>
    new Response(JSON.stringify(v), { status, headers: { 'content-type': 'application/json' } })
  const token = [
    Buffer.from('{"alg":"HS256"}').toString('base64url'),
    Buffer.from(
      JSON.stringify({
        exp: Date.parse(expiry) / 1000,
        url: `audio-notes/${row.object_path}`,
        upsert: false,
      }),
    ).toString('base64url'),
    Buffer.from('synthetic-signature').toString('base64url'),
  ].join('.')
  const client = createClient(origin, 'synthetic-server-key', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: async (input, init) => {
        const q = new Request(input, init)
        expect(new URL(q.url).origin).toBe(origin)
        requests.push(q)
        const path = new URL(q.url).pathname
        if (path === '/rest/v1/media_assets') return json([row])
        if (path === '/rest/v1/rpc/prepare_conversation_media_upload') {
          const body = await q.clone().json()
          ticket = body.p_ticket_id
          if (failPrepare) return json({ code: '42703', message: 'private missing schema' }, 400)
          return json({
            schema: 'conversation.upload-prepared.v1',
            asset: wire,
            ticket: ticketWire(),
          })
        }
        if (path.startsWith('/storage/v1/object/upload/sign/'))
          return json({ url: `/object/upload/sign/audio-notes/${row.object_path}?token=${token}` })
        if (path === '/rest/v1/rpc/register_conversation_media_upload')
          return json({ schema: 'conversation.upload-registered.v1', ticket: ticketWire(true) })
        if (path === '/rest/v1/rpc/get_conversation_media_upload_state')
          return json({ schema: 'conversation.upload-state.v1', asset: wire })
        throw Error('Unexpected synthetic SDK request')
      },
    },
  }) as unknown as ServiceClient
  const opts = { ordinaryUploadTickets: { storageOrigin: origin } } as unknown as Parameters<
    typeof createSupabaseMediaDependencies
  >[1]
  const run = () =>
    createMediaAsset(
      createSupabaseMediaDependencies(client, opts),
      user,
      { kind: 'audio_note', mime_type: 'audio/mp4', size_bytes: 100 },
      'same-request',
      now,
    )
  return { requests, run, getTicket: () => ticket }
}
afterEach(() => vi.useRealTimers())
describe('real media service + factory + installed Supabase SDK ordinary tickets', () => {
  it('sends the private prepare/sign/register/current sequence and returns actual expiry', async () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(now)
    const a = setup()
    expect((await a.run()).upload?.expires_at).toBe(expiry)
    const paths = a.requests.map((q) => new URL(q.url).pathname)
    expect(paths).toEqual([
      '/rest/v1/media_assets',
      '/rest/v1/rpc/prepare_conversation_media_upload',
      `/storage/v1/object/upload/sign/audio-notes/${user}/${asset}.m4a`,
      '/rest/v1/rpc/register_conversation_media_upload',
      '/rest/v1/rpc/get_conversation_media_upload_state',
    ])
    expect(await a.requests[1]?.json()).toEqual({
      p_user_id: user,
      p_asset_id: asset,
      p_ticket_id: a.getTicket(),
    })
    expect(await a.requests[3]?.json()).toEqual({
      p_user_id: user,
      p_asset_id: asset,
      p_ticket_id: a.getTicket(),
      p_provider_expires_at: expiry,
    })
  })
  it('missing ticket schema fails before Storage signing, with no untracked fallback', async () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(now)
    const a = setup(true)
    const failure = await a.run().catch((e) => e)
    expect(failure).toMatchObject({ status: 503, code: 'ordinary_media_upload_unavailable' })
    expect(String(failure)).not.toContain('private missing schema')
    expect(a.requests.some((q) => new URL(q.url).pathname.startsWith('/storage/'))).toBe(false)
  })
})
