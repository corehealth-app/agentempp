import type { ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { describe, expect, it } from 'vitest'
import { issuePrivateConversationMediaUpload } from './private-conversation-media-upload'
import { createSupabasePrivateConversationMedia } from './supabase-private-conversation-media'

const owner = 'c3672000-0000-4000-8000-000000000001'
const asset = 'c3672000-0000-4000-8000-000000000002'
const ticket = 'c3672000-0000-4000-8000-000000000003'
const at = '2026-11-17T12:00:00.000Z'
const expiry = '2026-11-17T14:00:00.000Z'
const origin = 'https://private-sdk.example.invalid'
const objectPath = `conversation-v2/${owner}/${asset}.m4a`
const identity = {
  catalog_version: 2,
  asset_id: asset,
  user_id: owner,
  kind: 'audio_note',
  bucket_id: 'audio-notes',
  object_path: objectPath,
  mime_type: 'audio/mp4',
  declared_size_bytes: 8,
}
const source = {
  id: asset,
  user_id: owner,
  kind: 'audio_note' as const,
  bucket_id: 'audio-notes' as const,
  object_path: objectPath,
  mime_type: 'audio/mp4',
  declared_size_bytes: 8,
  actual_size_bytes: null,
  etag: null,
  status: 'pending_upload' as const,
  failure_stage: null,
  failure_code: null,
  context_text: null,
  processing_request_id: null,
  processing_result: null,
  source_request_hash: 'a'.repeat(64),
  retention_until: '2026-12-17T12:00:00.000Z',
  uploaded_at: null,
  processed_at: null,
  deleted_at: null,
  created_at: at,
  updated_at: at,
}
const wire = {
  identity,
  state: { status: 'pending_upload', created_at: at, retention_until: source.retention_until },
}
function setup(failure?: 'prepare' | 'sign' | 'register' | 'transport' | 'changed') {
  const requests: Request[] = []
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url')
  const token = `${encode({ alg: 'HS256' })}.${encode({ url: `audio-notes/${objectPath}`, exp: Date.parse(expiry) / 1000, upsert: false })}.c2lnbmF0dXJl`
  const ticketWire = {
    id: ticket,
    asset_id: asset,
    user_id: owner,
    prepared_at: at,
    provider_expires_at: null,
    registered_at: null,
  }
  const json = (value: unknown, status = 200) =>
    new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } })
  const client = createClient(origin, 'synthetic-server-key', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: async (input, init) => {
        const request = new Request(input, init)
        requests.push(request)
        expect(new URL(request.url).origin).toBe(origin)
        if (failure === 'transport') throw new Error('private diagnostic must not escape')
        const path = new URL(request.url).pathname
        if (path === '/rest/v1/rpc/create_conversation_media_asset_v2')
          return json({ schema: 'conversation.media-asset.v2', catalog_version: 2, asset: source })
        if (path === '/rest/v1/rpc/prepare_conversation_media_upload_v2') {
          if (failure === 'prepare' || failure === 'changed')
            return json(
              {
                code: failure === 'changed' ? '40001' : '42883',
                message: 'private diagnostic must not escape',
              },
              400,
            )
          return json({
            schema: 'conversation.upload-prepared.v2',
            asset: wire,
            ticket: ticketWire,
          })
        }
        if (path.startsWith('/storage/v1/object/upload/sign/')) {
          if (failure === 'sign')
            return json(
              {
                statusCode: '503',
                error: 'private diagnostic must not escape',
                message: 'private diagnostic must not escape',
              },
              503,
            )
          return json({ url: `/object/upload/sign/audio-notes/${objectPath}?token=${token}` })
        }
        if (path === '/rest/v1/rpc/register_conversation_media_upload_v2') {
          if (failure === 'register')
            return json({ code: '40001', message: 'private diagnostic must not escape' }, 400)
          return json({
            schema: 'conversation.upload-registered.v2',
            ticket: { ...ticketWire, provider_expires_at: expiry, registered_at: at },
          })
        }
        if (path === '/rest/v1/rpc/get_conversation_media_upload_state_v2')
          return json({ schema: 'conversation.upload-state.v2', asset: wire })
        throw new Error('Unexpected private SDK request')
      },
    },
  }) as unknown as ServiceClient
  const deps = createSupabasePrivateConversationMedia(client, {
    storageOrigin: origin,
    now: () => new Date(at),
    nonce: () => ticket,
  })
  return {
    requests,
    client,
    run: () => issuePrivateConversationMediaUpload(deps.uploads, source),
    catalog: deps.catalog,
  }
}

describe('private catalog and upload through the installed Supabase SDK', () => {
  it('prepares before signing the disjoint non-upsert key and registers the actual expiry', async () => {
    const s = setup()
    const upload = await s.run()
    expect(upload).toMatchObject({
      expires_at: expiry,
      method: 'PUT',
      headers: { 'Content-Type': 'audio/mp4', 'x-upsert': 'false' },
    })
    expect(s.requests.map((r) => [r.method, new URL(r.url).pathname])).toEqual([
      ['POST', '/rest/v1/rpc/prepare_conversation_media_upload_v2'],
      ['POST', `/storage/v1/object/upload/sign/audio-notes/${objectPath}`],
      ['POST', '/rest/v1/rpc/register_conversation_media_upload_v2'],
      ['POST', '/rest/v1/rpc/get_conversation_media_upload_state_v2'],
    ])
    expect(await s.requests[0]?.json()).toEqual({
      p_user_id: owner,
      p_asset_id: asset,
      p_ticket_id: ticket,
    })
    // The installed SDK sends x-upsert only when upsert is true. Its absence
    // on signing plus the validated false token and PUT header forbid overwrite.
    expect(s.requests[1]?.headers.get('x-upsert')).toBeNull()
    expect(await s.requests[2]?.json()).toEqual({
      p_user_id: owner,
      p_asset_id: asset,
      p_ticket_id: ticket,
      p_provider_expires_at: expiry,
    })
  })

  it('creates only through the private RPC, without a public catalog mirror', async () => {
    const s = setup()
    expect(
      (
        await s.catalog.create({
          userId: owner,
          assetId: asset,
          kind: 'audio_note',
          mimeType: 'audio/mp4',
          declaredSizeBytes: 8,
          contextText: null,
          sourceRequestHash: 'a'.repeat(64),
        })
      ).id,
    ).toBe(asset)
    expect(s.requests.map((r) => new URL(r.url).pathname)).toEqual([
      '/rest/v1/rpc/create_conversation_media_asset_v2',
    ])
    expect(await s.requests[0]?.json()).toEqual({
      p_user_id: owner,
      p_asset_id: asset,
      p_kind: 'audio_note',
      p_mime_type: 'audio/mp4',
      p_declared_size_bytes: 8,
      p_context_text: null,
      p_source_request_hash: 'a'.repeat(64),
    })
  })

  it.each([
    'prepare',
    'changed',
    'sign',
    'register',
    'transport',
  ] as const)('does not repeat or fall back after %s failure', async (failure) => {
    const s = setup(failure)
    const error = await s.run().catch((e) => e)
    expect(error).toMatchObject({
      message: 'Private media operation unavailable',
      kind: ['changed', 'register'].includes(failure) ? 'changed' : 'unavailable',
    })
    expect(String(error)).not.toContain('diagnostic')
    expect(s.requests).toHaveLength(failure === 'register' ? 3 : failure === 'sign' ? 2 : 1)
    expect(s.requests.every((r) => !new URL(r.url).pathname.includes('/media_assets'))).toBe(true)
  })

  it.each([
    'http://private-sdk.example.invalid',
    `${origin}/path`,
    `${origin}?token=secret`,
    `https://user:secret@private-sdk.example.invalid`,
  ])('refuses a non-root trusted origin before making a request', (storageOrigin) => {
    const s = setup()
    expect(() => createSupabasePrivateConversationMedia(s.client, { storageOrigin })).toThrow(
      'Private media operation unavailable',
    )
    expect(s.requests).toHaveLength(0)
  })
})
