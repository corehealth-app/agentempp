import { createClient } from '@supabase/supabase-js'
import { describe, expect, it } from 'vitest'
import { createPrivateMediaSingleDisposal } from './private-conversation-media-disposal'

const owner = 'c1740000-0000-4000-8000-000000000001',
  id = 'c1740000-0000-4000-8000-000000000002',
  token = 'c1740000-0000-4000-8000-000000000003',
  version = 'c1740000-0000-4000-8000-000000000004'
const identity = {
  catalog_version: 2 as const,
  user_id: owner,
  asset_id: id,
  kind: 'audio_note' as const,
  bucket_id: 'audio-notes' as const,
  object_path: `conversation-v2/${owner}/${id}.m4a`,
  mime_type: 'audio/mp4' as const,
  declared_size_bytes: 8,
}
function setup(
  options: {
    state?: 'payload' | 'empty' | 'absent'
    busy?: boolean
    wrongClaim?: Record<string, unknown>
    wrongInspection?: Record<string, unknown>
    removeFailed?: boolean
    uncertainBarrier?: boolean
  } = {},
) {
  let state = options.state ?? 'payload'
  const calls: Array<{ path: string; method: string; body: unknown; upsert: string | null }> = []
  const client = createClient('https://single-private.invalid', 'synthetic-test-only', {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (input, init) => {
        const request = new Request(input, init),
          path = new URL(request.url).pathname
        const bytes = await request.arrayBuffer(),
          content = request.headers.get('content-type')
        const body =
          content?.includes('json') && bytes.byteLength
            ? JSON.parse(new TextDecoder().decode(bytes))
            : bytes.byteLength
        calls.push({ path, method: request.method, body, upsert: request.headers.get('x-upsert') })
        const reply = (value: unknown, status = 200) => Response.json(value, { status })
        if (path.endsWith('/rpc/claim_conversation_media_owned_disposal_v2')) {
          expect(body).toEqual({ p_user_id: owner, p_asset_id: id })
          return reply({
            schema: 'conversation.media-owned-disposal.v2',
            catalog_version: 2,
            asset_id: id,
            user_id: owner,
            claim: options.busy ? null : { ...identity, claim_token: token, ...options.wrongClaim },
          })
        }
        if (path.endsWith('/rpc/inspect_conversation_media_disposal_v2'))
          return reply({
            schema: 'conversation.media-disposal-state.v2',
            catalog_version: 2,
            asset_id: id,
            user_id: owner,
            claim_token: token,
            bucket_id: identity.bucket_id,
            object_path: identity.object_path,
            bucket_private: true,
            versioning: 'DISABLED',
            mime_type: 'audio/mp4',
            state,
            size_bytes: state === 'absent' ? null : state === 'empty' ? 0 : 8,
            object_version: state === 'absent' ? null : version,
            ...options.wrongInspection,
          })
        if (path.endsWith('/rpc/acknowledge_conversation_media_disposal_v2'))
          return reply({
            schema: 'conversation.media-disposal-ack.v2',
            catalog_version: 2,
            asset_id: id,
            user_id: owner,
            claim_token: token,
            state: 'barrier_retained',
            issuance_reconciled: false,
          })
        if (path === '/storage/v1/object/audio-notes' && request.method === 'DELETE') {
          if (options.removeFailed) return reply({ message: 'private diagnostic' }, 500)
          expect(body).toEqual({ prefixes: [{ path: identity.object_path, versionId: version }] })
          state = 'absent'
          return reply([])
        }
        if (
          path === `/storage/v1/object/audio-notes/${identity.object_path}` &&
          request.method === 'POST'
        ) {
          expect(body).toBe(0)
          expect(request.headers.get('x-upsert')).toBe('false')
          state = 'empty'
          if (options.uncertainBarrier) return reply({ message: 'uncertain diagnostic' }, 500)
          return reply({ Key: `audio-notes/${identity.object_path}` })
        }
        throw Error('Unexpected request; a user operation must never use the global claim')
      },
    },
  })
  return { dispose: createPrivateMediaSingleDisposal(client).dispose, calls, state: () => state }
}

describe('single private media deletion through installed SDK', () => {
  it('claims only the chosen owner and source, removes the observed version and retains a verified barrier', async () => {
    const x = setup()
    await x.dispose(identity)
    expect(x.state()).toBe('empty')
    expect(x.calls.map((c) => c.path.split('/v1/')[1])).toEqual([
      'rpc/claim_conversation_media_owned_disposal_v2',
      'rpc/inspect_conversation_media_disposal_v2',
      'object/audio-notes',
      `object/audio-notes/${identity.object_path}`,
      'rpc/inspect_conversation_media_disposal_v2',
      'rpc/acknowledge_conversation_media_disposal_v2',
    ])
  })
  it('preserves an existing zero-byte barrier and still verifies the acknowledgement', async () => {
    const x = setup({ state: 'empty' })
    await x.dispose(identity)
    expect(x.calls).toHaveLength(3)
    expect(x.calls.every((c) => c.path.startsWith('/rest/v1/rpc/'))).toBe(true)
  })
  it('installs a barrier for an absent payload instead of claiming absence proves completion', async () => {
    const x = setup({ state: 'absent' })
    await x.dispose(identity)
    expect(x.calls.filter((c) => c.path.startsWith('/storage/'))).toHaveLength(1)
    expect(x.calls.some((c) => c.method === 'DELETE')).toBe(false)
  })
  it.each([
    { user_id: id },
    { declared_size_bytes: 9 },
    { catalog_version: 1 },
    { object_path: `${owner}/${id}.m4a` },
  ])('refuses an unrelated or changed claim before external IO: %o', async (wrongClaim) => {
    const x = setup({ wrongClaim })
    await expect(x.dispose(identity)).rejects.toMatchObject({ code: 'media_disposal_unavailable' })
    expect(x.calls).toHaveLength(1)
  })
  it('does not remove anything when the single-source lease is busy', async () => {
    const x = setup({ busy: true })
    await expect(x.dispose(identity)).rejects.toMatchObject({ code: 'media_disposal_unavailable' })
    expect(x.calls).toHaveLength(1)
  })
  it('refuses changed inspection without external removal', async () => {
    const x = setup({ wrongInspection: { user_id: id } })
    await expect(x.dispose(identity)).rejects.toMatchObject({ code: 'media_disposal_unavailable' })
    expect(x.calls).toHaveLength(2)
  })
  it('does not fall back to plain removal when the conditional operation fails', async () => {
    const x = setup({ removeFailed: true })
    await expect(x.dispose(identity)).rejects.toMatchObject({ code: 'media_disposal_unavailable' })
    expect(x.calls).toHaveLength(3)
    expect(x.state()).toBe('payload')
  })
  it('leaves uncertain barrier outcome unacknowledged, then preserves it on retry', async () => {
    const x = setup({ uncertainBarrier: true })
    await expect(x.dispose(identity)).rejects.toMatchObject({ code: 'media_disposal_unavailable' })
    expect(x.calls).toHaveLength(4)
    expect(x.state()).toBe('empty')
    await x.dispose(identity)
    expect(x.calls.filter((c) => c.path.startsWith('/storage/'))).toHaveLength(2)
  })
})
