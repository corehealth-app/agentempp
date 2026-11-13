import type { ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { expect, it } from 'vitest'
import { cleanupExpiredMedia, createRetentionDependencies } from './media-retention-cleanup.js'

it('uses the actual SDK to remove payload, seal its non-upsert path and inspect before acknowledgment', async () => {
  const origin = 'https://synthetic.invalid'
  const user = '11110000-0000-4000-8000-000000000001'
  const asset = '11110000-0000-4000-8000-000000000002'
  const claim = '11110000-0000-4000-8000-000000000003'
  const requests: Request[] = []
  let sealed = false
  const client = createClient(origin, 'synthetic-server-only', {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: {
      fetch: async (input, init) => {
        const request = new Request(input, init)
        expect(new URL(request.url).origin).toBe(origin)
        requests.push(request)
        if (new URL(request.url).pathname.endsWith('/claim_conversation_media_expiry_batch'))
          return new Response(
            JSON.stringify({
              schema: 'conversation.media-expiry-page.v1',
              items: [
                {
                  asset_id: asset,
                  user_id: user,
                  kind: 'conversation_photo',
                  bucket_id: 'meal-photos',
                  object_path: `${user}/${asset}.jpg`,
                  claim_token: claim,
                },
              ],
              has_more: false,
            }),
            { status: 200, headers: { 'content-type': 'application/json' } },
          )
        if (new URL(request.url).pathname.endsWith('/acknowledge_conversation_media_expiry_sweep'))
          return new Response(
            JSON.stringify({
              schema: 'conversation.media-expiry-ack.v1',
              asset_id: asset,
              user_id: user,
              claim_token: claim,
              state: 'waiting_for_issuance_drain',
            }),
            { status: 200, headers: { 'content-type': 'application/json' } },
          )
        if (
          new URL(request.url).pathname.endsWith('/inspect_conversation_media_payload_revocation')
        )
          return new Response(
            JSON.stringify({
              schema: 'conversation.media-revocation-state.v1',
              asset_id: asset,
              user_id: user,
              claim_token: claim,
              bucket_id: 'meal-photos',
              object_path: `${user}/${asset}.jpg`,
              bucket_private: true,
              versioning: 'DISABLED',
              mime_type: 'image/jpeg',
              state: sealed ? 'empty' : 'payload',
              size_bytes: sealed ? 0 : 8,
              object_version: sealed
                ? '11110000-0000-4000-8000-000000000005'
                : '11110000-0000-4000-8000-000000000004',
            }),
            { status: 200, headers: { 'content-type': 'application/json' } },
          )
        if (request.method === 'DELETE')
          return new Response('[]', {
            status: 200,
            headers: { 'content-type': 'application/json' },
          })
        if (
          request.method === 'POST' &&
          new URL(request.url).pathname === `/storage/v1/object/meal-photos/${user}/${asset}.jpg`
        ) {
          expect(request.headers.get('x-upsert')).toBe('false')
          expect(request.headers.get('content-type')).toBe('image/jpeg')
          expect((await request.arrayBuffer()).byteLength).toBe(0)
          sealed = true
          return new Response(JSON.stringify({ Key: `meal-photos/${user}/${asset}.jpg` }), {
            status: 200,
            headers: { 'content-type': 'application/json' },
          })
        }
        throw Error('Unexpected synthetic SDK request')
      },
    },
  }) as unknown as ServiceClient
  const now = '2026-11-12T12:00:00.000Z'
  expect(
    await cleanupExpiredMedia(
      createRetentionDependencies(client, { scope: 'conversation' }),
      new Date(now),
    ),
  ).toEqual({ deleted: 1 })
  expect(requests.map((r) => r.method)).toEqual(['POST', 'POST', 'DELETE', 'POST', 'POST', 'POST'])
  const [list, inspection, removal, barrier, reinspection, patch] = requests.map(
    (r) => new URL(r.url),
  )
  expect(list?.pathname).toBe('/rest/v1/rpc/claim_conversation_media_expiry_batch')
  expect(await requests[0]?.json()).toEqual({ p_limit: 100 })
  expect(removal?.pathname).toBe('/storage/v1/object/meal-photos')
  expect(await requests[2]?.json()).toEqual({
    prefixes: [{ path: `${user}/${asset}.jpg`, versionId: '11110000-0000-4000-8000-000000000004' }],
  })
  expect(inspection?.pathname).toBe('/rest/v1/rpc/inspect_conversation_media_payload_revocation')
  expect(reinspection?.pathname).toBe(inspection?.pathname)
  expect(await requests[1]?.json()).toEqual({
    p_asset_id: asset,
    p_user_id: user,
    p_claim_token: claim,
  })
  expect(await requests[4]?.json()).toEqual({
    p_asset_id: asset,
    p_user_id: user,
    p_claim_token: claim,
  })
  expect(barrier?.pathname).toBe(`/storage/v1/object/meal-photos/${user}/${asset}.jpg`)
  expect(patch?.pathname).toBe('/rest/v1/rpc/acknowledge_conversation_media_expiry_sweep')
  expect(await requests[5]?.json()).toEqual({
    p_asset_id: asset,
    p_user_id: user,
    p_claim_token: claim,
  })
})
