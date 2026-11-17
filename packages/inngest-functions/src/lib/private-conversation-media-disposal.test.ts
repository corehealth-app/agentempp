import { createClient } from '@supabase/supabase-js'
import { describe, expect, it } from 'vitest'
import { createPrivateMediaDisposalV2 } from './private-conversation-media-disposal.js'

const owner = 'c1690000-0000-4000-8000-000000000001'
const asset = 'c1690000-0000-4000-8000-000000000002'
const token = 'c1690000-0000-4000-8000-000000000003'
const version = 'c1690000-0000-4000-8000-000000000004'
const path = `conversation-v2/${owner}/${asset}.m4a`
const claim = {
  catalog_version: 2,
  user_id: owner,
  asset_id: asset,
  kind: 'audio_note',
  bucket_id: 'audio-notes',
  object_path: path,
  mime_type: 'audio/mp4',
  declared_size_bytes: 8,
  claim_token: token,
}

// Only the external HTTP boundary is synthetic; the installed Supabase SDK,
// RPC/Storage serialization and disposal implementation all run normally.
function setup(
  options: {
    initial?: 'absent' | 'empty' | 'payload'
    wrongClaim?: Record<string, unknown>
    wrongInspection?: Record<string, unknown>
    wrongAck?: Record<string, unknown>
    removeFailure?: boolean
    uncertainBarrier?: boolean
    remainPayload?: boolean
  } = {},
) {
  let state = options.initial ?? 'payload'
  const calls: Array<{ url: string; body: unknown; headers: Headers }> = []
  const fetcher: typeof fetch = async (input, init) => {
    const url = String(input)
    const body = typeof init?.body === 'string' ? JSON.parse(init.body) : init?.body
    calls.push({ url, body, headers: new Headers(init?.headers) })
    const reply = (value: unknown, status = 200) =>
      new Response(JSON.stringify(value), {
        status,
        headers: { 'content-type': 'application/json' },
      })
    if (url.endsWith('/rpc/claim_conversation_media_disposal_batch_v2'))
      return reply({
        schema: 'conversation.media-disposal-page.v2',
        items: [{ ...claim, ...options.wrongClaim }],
        has_more: false,
      })
    if (url.endsWith('/rpc/inspect_conversation_media_disposal_v2'))
      return reply({
        schema: 'conversation.media-disposal-state.v2',
        catalog_version: 2,
        asset_id: asset,
        user_id: owner,
        claim_token: token,
        bucket_id: 'audio-notes',
        object_path: path,
        bucket_private: true,
        versioning: 'DISABLED',
        mime_type: 'audio/mp4',
        state,
        size_bytes: state === 'absent' ? null : state === 'empty' ? 0 : 8,
        object_version: state === 'absent' ? null : version,
        ...options.wrongInspection,
      })
    if (url.endsWith('/rpc/acknowledge_conversation_media_disposal_v2'))
      return reply({
        schema: 'conversation.media-disposal-ack.v2',
        catalog_version: 2,
        asset_id: asset,
        user_id: owner,
        claim_token: token,
        state: 'barrier_retained',
        issuance_reconciled: false,
        ...options.wrongAck,
      })
    if (
      url.endsWith('/rpc/close_conversation_media_v2') ||
      url.endsWith('/rpc/prepare_conversation_media_account_purge_v2')
    )
      return reply(true)
    if (url.endsWith('/storage/v1/object/audio-notes')) {
      if (options.removeFailure) return reply({ message: 'private-provider-diagnostic' }, 500)
      state = 'absent'
      return reply([])
    }
    if (url.endsWith(`/storage/v1/object/audio-notes/${path}`)) {
      if (!options.remainPayload) state = 'empty'
      if (options.uncertainBarrier) return reply({ message: 'private-upload-diagnostic' }, 500)
      return reply({ Key: `audio-notes/${path}` })
    }
    throw Error('Unexpected external HTTP request')
  }
  const client = createClient('https://private-disposal.invalid', 'synthetic-local-key', {
    global: { fetch: fetcher },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  return { adapter: createPrivateMediaDisposalV2(client), calls, state: () => state }
}

describe('private media independent disposal through installed SDK', () => {
  it('removes only the observed version and installs a non-upsert barrier before ack', async () => {
    const x = setup()
    expect(await x.adapter.sweep(10)).toEqual({ swept: 1, hasMore: false })
    expect(x.state()).toBe('empty')
    expect(x.calls.map((c) => c.url.split('/v1/')[1])).toEqual([
      'rpc/claim_conversation_media_disposal_batch_v2',
      'rpc/inspect_conversation_media_disposal_v2',
      'object/audio-notes',
      `object/audio-notes/${path}`,
      'rpc/inspect_conversation_media_disposal_v2',
      'rpc/acknowledge_conversation_media_disposal_v2',
    ])
    expect(x.calls[2]?.body).toEqual({ prefixes: [{ path, versionId: version }] })
    expect(x.calls[3]?.headers.get('x-upsert')).toBe('false')
    expect(x.calls[3]?.headers.get('content-type')).toBe('audio/mp4')
    expect(x.calls[3]?.body).toBeInstanceOf(Uint8Array)
    expect((x.calls[3]?.body as Uint8Array).byteLength).toBe(0)
  })
  it('retains an existing empty barrier without any Storage mutation', async () => {
    const x = setup({ initial: 'empty' })
    expect(await x.adapter.sweep()).toEqual({ swept: 1, hasMore: false })
    expect(x.calls.every((c) => !c.url.includes('/storage/'))).toBe(true)
  })
  it('installs a barrier for absence rather than treating absence as disposed', async () => {
    const x = setup({ initial: 'absent' })
    expect(await x.adapter.sweep()).toEqual({ swept: 1, hasMore: false })
    expect(x.calls.filter((c) => c.url.includes('/storage/')).map((c) => c.url)).toEqual([
      `https://private-disposal.invalid/storage/v1/object/audio-notes/${path}`,
    ])
  })
  it.each([
    { catalog_version: 1 },
    { user_id: asset },
    { object_path: `${owner}/${asset}.m4a` },
    { object_path: `${path}/unexpected` },
    { kind: 'body_photo' },
    { mime_type: 'image/jpeg' },
  ])('refuses invalid or legacy claim before any Storage operation: %o', async (wrongClaim) => {
    const x = setup({ wrongClaim })
    await expect(x.adapter.sweep()).rejects.toThrow('Private media disposal unavailable')
    expect(x.calls).toHaveLength(1)
  })
  it.each([
    { object_path: `${owner}/${asset}.m4a` },
    { user_id: asset },
    { claim_token: asset },
    { state: 'empty', size_bytes: 8 },
    { versioning: 'ENABLED' },
    { bucket_private: false },
  ])('refuses changed inspection without deletion or acknowledgement: %o', async (wrongInspection) => {
    const x = setup({ wrongInspection })
    await expect(x.adapter.sweep()).rejects.toThrow('Private media disposal unavailable')
    expect(x.calls).toHaveLength(2)
  })
  it('does not fall back to plain removal on provider rejection', async () => {
    const x = setup({ removeFailure: true })
    await expect(x.adapter.sweep()).rejects.toThrow('Private media disposal unavailable')
    expect(x.calls).toHaveLength(3)
    expect(x.state()).toBe('payload')
  })
  it('does not acknowledge uncertain barrier writes; next sweep inspects without deleting it', async () => {
    const x = setup({ uncertainBarrier: true })
    await expect(x.adapter.sweep()).rejects.toThrow('Private media disposal unavailable')
    expect(x.state()).toBe('empty')
    expect(x.calls).toHaveLength(4)
    expect(await x.adapter.sweep()).toEqual({ swept: 1, hasMore: false })
    expect(x.calls.filter((c) => c.url.includes('/storage/'))).toHaveLength(2)
  })
  it('requires observed emptiness before acknowledging a claimed source', async () => {
    const x = setup({ remainPayload: true })
    await expect(x.adapter.sweep()).rejects.toThrow('Private media disposal unavailable')
    expect(x.calls.some((c) => c.url.includes('/rpc/acknowledge_'))).toBe(false)
  })
  it('refuses a foreign ack even after successful byte revocation', async () => {
    const x = setup({ wrongAck: { asset_id: owner } })
    await expect(x.adapter.sweep()).rejects.toThrow('Private media disposal unavailable')
    expect(x.state()).toBe('empty')
  })
  it('closes only the explicit owned private source and uses a deleted-account cutoff for purge', async () => {
    const x = setup()
    expect(await x.adapter.closeOwned(owner, asset)).toBe(true)
    expect(await x.adapter.prepareAccountPurge(owner, '2026-11-17T12:00:00.000Z')).toBe(true)
    expect(x.calls.map((c) => c.body)).toEqual([
      { p_user_id: owner, p_asset_id: asset },
      { p_user_id: owner, p_cutoff: '2026-11-17T12:00:00.000Z' },
    ])
    expect(x.calls.every((c) => !c.url.includes('/storage/'))).toBe(true)
  })
})
