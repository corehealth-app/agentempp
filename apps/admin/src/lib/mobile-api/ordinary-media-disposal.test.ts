import type { ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { describe, expect, it } from 'vitest'
import type { MediaAssetRecord } from './media-service'
import { createOrdinaryMediaDisposal } from './ordinary-media-disposal'
import { createSupabaseMediaDependencies } from './supabase-media'

const user = '11110000-0000-4000-8000-000000000001'
const assetID = '11110000-0000-4000-8000-000000000002'
const claim = '11110000-0000-4000-8000-000000000003'
const version = '11110000-0000-4000-8000-000000000004'
const path = `${user}/${assetID}.m4a`
const asset: MediaAssetRecord = {
  id: assetID,
  user_id: user,
  kind: 'audio_note',
  bucket_id: 'audio-notes',
  object_path: path,
  mime_type: 'audio/mp4',
  declared_size_bytes: 8,
  actual_size_bytes: null,
  status: 'pending_upload',
  failure_stage: null,
  failure_code: null,
  context_text: null,
  retention_until: '2026-12-13T06:00:00Z',
  uploaded_at: null,
  processed_at: null,
  deleted_at: null,
  created_at: '2026-11-13T06:00:00Z',
  updated_at: '2026-11-13T06:00:00Z',
}
function fixture(
  initial: number | null = 8,
  mode: 'normal' | 'busy' | 'foreign' | 'missing' | 'uncertain' | 'badAck' = 'normal',
) {
  let size = initial
  const requests: Request[] = []
  const origin = 'https://synthetic.invalid'
  const response = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } })
  const client = createClient(origin, 'synthetic-server-only', {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: {
      fetch: async (input, init) => {
        const request = new Request(input, init)
        expect(new URL(request.url).origin).toBe(origin)
        requests.push(request.clone())
        const url = new URL(request.url)
        if (url.pathname.endsWith('/claim_conversation_media_disposal')) {
          expect(await request.json()).toEqual({ p_asset_id: assetID, p_user_id: user })
          if (mode === 'missing')
            return response({ message: 'private/backend detail', code: 'PGRST202' }, 404)
          return response({
            schema: 'conversation.media-disposal.v1',
            asset_id: assetID,
            user_id: user,
            claim:
              mode === 'busy'
                ? null
                : {
                    asset_id: assetID,
                    user_id: mode === 'foreign' ? assetID : user,
                    kind: 'audio_note',
                    bucket_id: 'audio-notes',
                    object_path: mode === 'foreign' ? `${assetID}/${assetID}.m4a` : path,
                    claim_token: claim,
                  },
          })
        }
        if (url.pathname.endsWith('/inspect_conversation_media_payload_revocation')) {
          expect(await request.json()).toEqual({
            p_asset_id: assetID,
            p_user_id: user,
            p_claim_token: claim,
          })
          return response({
            schema: 'conversation.media-revocation-state.v1',
            asset_id: assetID,
            user_id: user,
            claim_token: claim,
            bucket_id: 'audio-notes',
            object_path: path,
            bucket_private: true,
            versioning: 'DISABLED',
            mime_type: 'audio/mp4',
            state: size === null ? 'absent' : size === 0 ? 'empty' : 'payload',
            size_bytes: size,
            object_version: size === null ? null : version,
          })
        }
        if (url.pathname.endsWith('/acknowledge_conversation_media_expiry_sweep'))
          return response({
            schema: 'conversation.media-expiry-ack.v1',
            asset_id: assetID,
            user_id: mode === 'badAck' ? assetID : user,
            claim_token: claim,
            state: 'waiting_for_issuance_drain',
          })
        if (request.method === 'DELETE' && url.pathname === '/storage/v1/object/audio-notes') {
          expect(await request.json()).toEqual({ prefixes: [{ path, versionId: version }] })
          size = null
          return response([])
        }
        if (
          request.method === 'POST' &&
          url.pathname === `/storage/v1/object/audio-notes/${path}`
        ) {
          expect(request.headers.get('x-upsert')).toBe('false')
          expect(request.headers.get('content-type')).toBe('audio/mp4')
          expect((await request.arrayBuffer()).byteLength).toBe(0)
          size = 0
          return mode === 'uncertain'
            ? response({ message: 'private uncertain write' }, 500)
            : response({ Key: `audio-notes/${path}` })
        }
        throw Error('Unexpected SDK request')
      },
    },
  }) as unknown as ServiceClient
  return {
    client,
    requests,
    size: () => size,
    deps: createSupabaseMediaDependencies(client, {
      ordinaryDisposals: createOrdinaryMediaDisposal(client),
    }),
  }
}

describe('ordinary disposal through the actual Supabase SDK factory', () => {
  it('closes first, deletes only the observed payload version, installs an empty barrier and then acknowledges', async () => {
    const f = fixture()
    await f.deps.ordinaryDisposals?.dispose(asset)
    expect(f.size()).toBe(0)
    expect(f.requests.map((r) => `${r.method} ${new URL(r.url).pathname}`)).toEqual([
      'POST /rest/v1/rpc/claim_conversation_media_disposal',
      'POST /rest/v1/rpc/inspect_conversation_media_payload_revocation',
      'DELETE /storage/v1/object/audio-notes',
      `POST /storage/v1/object/audio-notes/${path}`,
      'POST /rest/v1/rpc/inspect_conversation_media_payload_revocation',
      'POST /rest/v1/rpc/acknowledge_conversation_media_expiry_sweep',
    ])
  })
  it('does not delete or rewrite an already installed barrier', async () => {
    const f = fixture(0)
    await f.deps.ordinaryDisposals?.dispose({ ...asset, status: 'deleted' })
    expect(f.size()).toBe(0)
    expect(f.requests.map((r) => new URL(r.url).pathname)).toEqual([
      '/rest/v1/rpc/claim_conversation_media_disposal',
      '/rest/v1/rpc/inspect_conversation_media_payload_revocation',
      '/rest/v1/rpc/acknowledge_conversation_media_expiry_sweep',
    ])
  })
  it('seals an absent path without issuing any DELETE', async () => {
    const f = fixture(null)
    await f.deps.ordinaryDisposals?.dispose(asset)
    expect(f.size()).toBe(0)
    expect(f.requests.some((r) => r.method === 'DELETE')).toBe(false)
    expect(f.requests).toHaveLength(5)
  })
  it.each([
    'busy',
    'foreign',
    'missing',
  ] as const)('refuses %s preparation before touching Storage or acknowledging', async (mode) => {
    const f = fixture(8, mode)
    await expect(f.deps.ordinaryDisposals?.dispose(asset)).rejects.toMatchObject({
      status: 503,
      code: 'media_disposal_unavailable',
      message: 'Media deletion unavailable',
    })
    expect(f.size()).toBe(8)
    expect(f.requests).toHaveLength(1)
  })
  it('preserves a successful-but-uncertain barrier write as unacknowledged debt', async () => {
    const f = fixture(8, 'uncertain')
    await expect(f.deps.ordinaryDisposals?.dispose(asset)).rejects.toMatchObject({
      code: 'media_disposal_unavailable',
    })
    expect(f.size()).toBe(0)
    expect(
      f.requests.some((r) =>
        new URL(r.url).pathname.endsWith('/acknowledge_conversation_media_expiry_sweep'),
      ),
    ).toBe(false)
  })
  it('refuses a receipt for another owner even after payload revocation', async () => {
    const f = fixture(8, 'badAck')
    await expect(f.deps.ordinaryDisposals?.dispose(asset)).rejects.toMatchObject({
      code: 'media_disposal_unavailable',
    })
    expect(f.size()).toBe(0)
  })
  it('leaves the legacy/default factory free of the new disposal RPC dependency', () => {
    const f = fixture()
    expect(createSupabaseMediaDependencies(f.client).ordinaryDisposals).toBeUndefined()
    expect(f.requests).toHaveLength(0)
  })
})
