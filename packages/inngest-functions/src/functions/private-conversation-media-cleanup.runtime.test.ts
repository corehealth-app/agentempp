import { createClient } from '@supabase/supabase-js'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// Real roster, registered callbacks, account coordinator and SDK. Only the
// external privileged-client/HTTP boundary is synthetic; no real owners touched.
const boundary = vi.hoisted(() => ({ client: vi.fn() }))
vi.mock('../lib/env.js', () => ({ createWorkerSupabase: boundary.client }))
const { allFunctions, functionsForSet } = await import('../index.js')
const owner = 'c1750000-0000-4000-8000-000000000001'
const asset = 'c1750000-0000-4000-8000-000000000002'
const token = 'c1750000-0000-4000-8000-000000000003'
const version = 'c1750000-0000-4000-8000-000000000004'
const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
const path = `conversation-v2/${owner}/${asset}.m4a`
const at = '2026-11-17T23:00:00.000Z'
const cutoff = '2026-11-17T22:00:00.000Z'
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
const ids = (set: readonly { id(): string }[]) => set.map((fn) => fn.id())
const select = (id: string) =>
  functionsForSet('media-conversation-staging').find((fn) => fn.id() === id)
const logger = { info: vi.fn(), warn: vi.fn() }
const run = (fn: unknown) => {
  if (!fn) throw Error('Private cleanup callback is not registered')
  return (fn as { fn(ctx: unknown): Promise<unknown> }).fn({
    step: { run: (_id: string, action: () => unknown) => action() },
    logger,
  })
}
function setup(
  options: {
    account?: boolean
    ready?: boolean
    legacyReady?: boolean
    empty?: boolean
    hasMore?: boolean
    failure?: string
    withdrawAfter?: string
  } = {},
) {
  let state = options.empty ? 'empty' : 'payload'
  let erased = false
  const calls: Array<{ route: string; method: string; body: unknown; url: URL; headers: Headers }> =
    []
  const client = createClient(origin, 'synthetic-no-network-key', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: async (input, init) => {
        const req = new Request(input, init),
          url = new URL(req.url)
        expect(url.origin).toBe(origin)
        const route = url.pathname.split('/').at(-1) ?? ''
        const text = await req.clone().text()
        const body =
          req.headers.get('content-type')?.includes('application/json') && text
            ? JSON.parse(text)
            : text
        calls.push({ route, method: req.method, body, url, headers: req.headers })
        if (options.withdrawAfter === route)
          vi.stubEnv('MOBILE_CONVERSATION_PRIVATE_DISPOSAL_ENABLED', 'false')
        if (options.failure === route)
          return Response.json({ message: 'PRIVATE_PROVIDER_DIAGNOSTIC' }, { status: 500 })
        if (route === 'claim_conversation_media_disposal_batch_v2')
          return Response.json({
            schema: 'conversation.media-disposal-page.v2',
            items: [claim],
            has_more: options.hasMore ?? false,
          })
        if (route === 'inspect_conversation_media_disposal_v2')
          return Response.json({
            schema: 'conversation.media-disposal-state.v2',
            catalog_version: 2,
            user_id: owner,
            asset_id: asset,
            claim_token: token,
            bucket_id: 'audio-notes',
            object_path: path,
            bucket_private: true,
            versioning: 'DISABLED',
            mime_type: 'audio/mp4',
            state,
            size_bytes: state === 'empty' ? 0 : 8,
            object_version: version,
          })
        if (route === 'acknowledge_conversation_media_disposal_v2')
          return Response.json({
            schema: 'conversation.media-disposal-ack.v2',
            catalog_version: 2,
            user_id: owner,
            asset_id: asset,
            claim_token: token,
            state: 'barrier_retained',
            issuance_reconciled: false,
          })
        if (url.pathname === '/storage/v1/object/audio-notes') {
          expect(body).toEqual({ prefixes: [{ path, versionId: version }] })
          state = 'absent'
          return Response.json([])
        }
        if (url.pathname === `/storage/v1/object/audio-notes/${path}`) {
          expect(req.headers.get('x-upsert')).toBe('false')
          expect((await req.arrayBuffer()).byteLength).toBe(0)
          state = 'empty'
          return Response.json({ Key: `audio-notes/${path}` })
        }
        if (route === 'list_mobile_deleted_users_for_photo_purge')
          return Response.json({
            version: 1,
            users: options.account && !erased ? [{ id: owner }] : [],
          })
        if (route === 'prepare_conversation_media_account_purge_v2')
          return Response.json(options.ready ?? false)
        if (route === 'prepare_conversation_media_account_purge')
          return Response.json(options.legacyReady ?? true)
        if (
          route === 'begin_mobile_deleted_user_photo_purge' ||
          route === 'purge_mobile_reevaluation_photo_catalog_for_deleted_user'
        )
          return Response.json(true)
        if (route === 'media_assets') return Response.json([])
        if (route === 'users' && req.method === 'DELETE') {
          erased = true
          return Response.json({ id: owner })
        }
        throw Error('Unexpected synthetic HTTP boundary')
      },
    },
  })
  boundary.client.mockReturnValue(client)
  return { calls, state: () => state, erased: () => erased }
}

describe('private cleanup registration and execution', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date(at))
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-conversation-staging')
    vi.stubEnv('SUPABASE_URL', origin)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', undefined)
    vi.stubEnv('MOBILE_CONVERSATION_PRIVATE_DISPOSAL_ENABLED', 'true')
    vi.stubEnv('MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED', 'false')
    vi.stubEnv('MOBILE_CONVERSATION_PHOTOS_ENABLED', 'false')
  })
  afterEach(() => {
    vi.unstubAllEnvs()
    vi.useRealTimers()
  })

  it('serves cleanup and exactly one private-aware account purger with all new processing disabled', () => {
    expect(ids(functionsForSet('media-conversation-staging'))).toEqual([
      'media-asset-processing',
      'reevaluation-photo-disposition-cleanup',
      'conversation-media-retention-cleanup',
      'user-deletion-purger',
      'conversation-private-media-retention-cleanup',
    ])
    expect(select('user-deletion-purger')).not.toBe(
      allFunctions.find((fn) => fn.id() === 'user-deletion-purger'),
    )
    expect(ids(functionsForSet('media-staging'))).toEqual(['media-asset-processing'])
    expect(functionsForSet(undefined)).toBe(allFunctions)
    expect(ids(allFunctions)).not.toContain('conversation-private-media-retention-cleanup')
    vi.stubEnv('INNGEST_FUNCTION_SET', 'media-clinical-staging')
    expect(ids(functionsForSet('media-clinical-staging'))).toEqual([
      'media-asset-processing',
      'reevaluation-photo-disposition-cleanup',
    ])
  })
  it('processes one bounded disposal batch, retains its barrier and never claims issuance drained', async () => {
    const x = setup({ hasMore: true })
    expect(await run(select('conversation-private-media-retention-cleanup'))).toEqual({
      swept: 1,
      hasMore: true,
      issuanceReconciled: false,
    })
    expect(x.state()).toBe('empty')
    expect(x.calls[0]?.body).toEqual({ p_limit: 100 })
    expect(
      x.calls.filter((c) => c.route === 'claim_conversation_media_disposal_batch_v2'),
    ).toHaveLength(1)
    expect(logger.info).toHaveBeenCalledWith('private conversation media sweep completed', {
      swept: 1,
      hasMore: true,
      issuanceReconciled: false,
    })
    const writes = x.calls.filter((c) => c.url.pathname.startsWith('/storage/')).length
    await run(select('conversation-private-media-retention-cleanup'))
    expect(x.calls.filter((c) => c.url.pathname.startsWith('/storage/'))).toHaveLength(writes)
  })
  it.each([
    undefined,
    '',
    'false',
    'TRUE',
  ])('refuses previously selected callbacks after cleanup is disabled (%s)', async (flag) => {
    const fn = select('conversation-private-media-retention-cleanup')
    const purger = select('user-deletion-purger')
    setup()
    vi.stubEnv('MOBILE_CONVERSATION_PRIVATE_DISPOSAL_ENABLED', flag)
    await expect(run(fn)).rejects.toThrow('Private conversation media cleanup unavailable')
    await expect(run(purger)).rejects.toThrow('Private conversation account purge unavailable')
    expect(boundary.client).not.toHaveBeenCalled()
    expect(ids(functionsForSet('media-conversation-staging'))).not.toContain(
      'conversation-private-media-retention-cleanup',
    )
  })
  it.each([
    '',
    'https://foreign.invalid',
    `${origin}/foreign`,
  ])('refuses changed effective target before client construction (%s)', async (url) => {
    const fn = select('conversation-private-media-retention-cleanup')
    const purger = select('user-deletion-purger')
    setup()
    vi.stubEnv('SUPABASE_URL', url)
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', origin)
    await expect(run(fn)).rejects.toThrow('Private conversation media cleanup unavailable')
    await expect(run(purger)).rejects.toThrow('Private conversation account purge unavailable')
    expect(boundary.client).not.toHaveBeenCalled()
  })
  it.each([
    'claim_conversation_media_disposal_batch_v2',
    'inspect_conversation_media_disposal_v2',
  ])('withdrawal after %s prevents subsequent Storage access and acknowledgment', async (route) => {
    const x = setup({ withdrawAfter: route })
    await expect(run(select('conversation-private-media-retention-cleanup'))).rejects.toThrow(
      /^Private conversation media cleanup unavailable$/,
    )
    expect(x.calls.some((c) => c.url.pathname.startsWith('/storage/'))).toBe(false)
    expect(x.calls.some((c) => c.route === 'acknowledge_conversation_media_disposal_v2')).toBe(
      false,
    )
    expect(logger.info).not.toHaveBeenCalled()
  })
  it('does not fall back to legacy retention on a private provider failure', async () => {
    const x = setup({ failure: 'inspect_conversation_media_disposal_v2' })
    await expect(run(select('conversation-private-media-retention-cleanup'))).rejects.toThrow(
      /^Private conversation media cleanup unavailable$/,
    )
    expect(x.state()).toBe('payload')
    expect(x.calls.map((c) => c.route)).toEqual([
      'claim_conversation_media_disposal_batch_v2',
      'inspect_conversation_media_disposal_v2',
    ])
    expect(logger.info).not.toHaveBeenCalled()
    expect(logger.warn).not.toHaveBeenCalled()
  })
  it('preserves an account until private revocation is proved, before invoking legacy or recurring purge', async () => {
    const x = setup({ account: true })
    expect(await run(select('user-deletion-purger'))).toEqual({ purged: 0, mediaRemoved: 0 })
    expect(x.calls.map((c) => c.route)).toEqual([
      'list_mobile_deleted_users_for_photo_purge',
      'prepare_conversation_media_account_purge_v2',
    ])
    expect(x.calls[0]?.body).toEqual({ p_cutoff: cutoff, p_limit: 100 })
    expect(x.calls[1]?.body).toEqual({ p_user_id: owner, p_cutoff: cutoff })
    expect(x.erased()).toBe(false)
  })
  it('requires private, legacy and recurring readiness in order before the existing account deletion', async () => {
    const x = setup({ account: true, ready: true })
    expect(await run(select('user-deletion-purger'))).toEqual({ purged: 1, mediaRemoved: 0 })
    expect(x.calls.map((c) => c.route)).toEqual([
      'list_mobile_deleted_users_for_photo_purge',
      'prepare_conversation_media_account_purge_v2',
      'prepare_conversation_media_account_purge',
      'begin_mobile_deleted_user_photo_purge',
      'purge_mobile_reevaluation_photo_catalog_for_deleted_user',
      'media_assets',
      'media_assets',
      'users',
    ])
    expect(x.erased()).toBe(true)
    expect(x.calls.at(-1)?.url.searchParams.get('status')).toBe('eq.deleted')
    expect(x.calls.at(-1)?.url.searchParams.get('updated_at')).toBe(`lte.${cutoff}`)
    expect(await run(select('user-deletion-purger'))).toEqual({ purged: 0, mediaRemoved: 0 })
  })
  it('keeps legacy readiness mandatory after private catalog detachment', async () => {
    const x = setup({ account: true, ready: true, legacyReady: false })
    expect(await run(select('user-deletion-purger'))).toEqual({ purged: 0, mediaRemoved: 0 })
    expect(x.calls.map((c) => c.route)).toEqual([
      'list_mobile_deleted_users_for_photo_purge',
      'prepare_conversation_media_account_purge_v2',
      'prepare_conversation_media_account_purge',
    ])
    expect(x.erased()).toBe(false)
  })
  it.each([
    'prepare_conversation_media_account_purge_v2',
    'media_assets',
  ])('stops an in-flight account purge after withdrawal at %s', async (route) => {
    const x = setup({ account: true, ready: true, withdrawAfter: route })
    await expect(run(select('user-deletion-purger'))).rejects.toThrow(
      /^Private conversation account purge unavailable$/,
    )
    expect(x.erased()).toBe(false)
    expect(x.calls.some((c) => c.route === 'users')).toBe(false)
    if (route === 'prepare_conversation_media_account_purge_v2') expect(x.calls).toHaveLength(2)
    expect(logger.info).not.toHaveBeenCalled()
  })
  it('does not fall back to old account deletion when private preparation fails', async () => {
    const x = setup({ account: true, failure: 'prepare_conversation_media_account_purge_v2' })
    await expect(run(select('user-deletion-purger'))).rejects.toThrow(
      /^Private conversation account purge unavailable$/,
    )
    expect(x.calls).toHaveLength(2)
    expect(x.erased()).toBe(false)
    expect(logger.info).not.toHaveBeenCalled()
  })
})
