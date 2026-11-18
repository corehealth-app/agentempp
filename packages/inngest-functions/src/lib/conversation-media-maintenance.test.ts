import { createClient } from '@supabase/supabase-js'
import { describe, expect, it, vi } from 'vitest'
import { createConversationMediaMaintenanceHandler } from './conversation-media-maintenance.js'

const dispatch = 'b3770000-0000-4000-8000-000000000001'
const lease = 'b3770000-0000-4000-8000-000000000002'
const start = Date.parse('2026-11-18T02:00:00Z')
const token = 'a'.repeat(64)
const env = {
  SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
  MOBILE_CONVERSATION_MAINTENANCE_BRIDGE_ENABLED: 'true',
}
function request(body: unknown = { dispatch_id: dispatch }, header = token) {
  return new Request('https://example.test/maintenance', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-performe-maintenance-token': header },
    body: JSON.stringify(body),
  })
}
function fixture(lane = 'private') {
  const calls: Array<{ path: string; body: Record<string, unknown> }> = []
  let now = start
  let mode = 'success'
  const handle = createConversationMediaMaintenanceHandler({
    env,
    now: () => now,
    createClient({ signal, assertActive }) {
      return createClient(env.SUPABASE_URL, 'local-test-key', {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
          async fetch(input, init) {
            assertActive()
            if (signal.aborted) throw Error('aborted')
            const path = new URL(String(input)).pathname.split('/').at(-1) ?? ''
            const body = JSON.parse(String(init?.body ?? '{}'))
            calls.push({ path, body })
            let result: unknown
            if (path === 'claim_conversation_media_maintenance') {
              result =
                mode === 'denied'
                  ? null
                  : {
                      schema: 'conversation.media-maintenance-lease.v1',
                      dispatch_id: dispatch,
                      lease_id: lease,
                      lane,
                      expires_at: '2026-11-18T02:01:05Z',
                    }
              if (mode === 'late') now += 70000
              if (mode === 'flag-off') env.MOBILE_CONVERSATION_MAINTENANCE_BRIDGE_ENABLED = 'false'
              if (mode === 'bad-lease') result = { ...(result as object), dispatch_id: lease }
            } else if (path === 'claim_conversation_media_disposal_batch_v2') {
              if (mode === 'fail')
                return new Response(JSON.stringify({ message: 'secret owner raw error' }), {
                  status: 500,
                })
              result = { schema: 'conversation.media-disposal-page.v2', items: [], has_more: false }
            } else if (path === 'claim_conversation_media_expiry_batch') {
              result = { schema: 'conversation.media-expiry-page.v1', items: [], has_more: false }
            } else if (path === 'claim_mobile_reevaluation_photo_cleanup_scopes') {
              result = { version: 1, items: [], has_more: false }
            } else if (path === 'list_mobile_deleted_users_for_photo_purge') {
              result = { version: 1, users: [] }
            } else if (path === 'complete_conversation_media_maintenance')
              result = mode !== 'lost-lease'
            else throw Error(`Unexpected external operation ${path}`)
            return new Response(JSON.stringify(result), {
              headers: { 'content-type': 'application/json' },
            })
          },
        },
      })
    },
  })
  return {
    handle,
    calls,
    setMode: (v: string) => {
      mode = v
    },
    restore: () => {
      env.MOBILE_CONVERSATION_MAINTENANCE_BRIDGE_ENABLED = 'true'
    },
  }
}

describe('bounded conversational maintenance transport', () => {
  it('does not accept a complete JSON prefix when the body never finishes', async () => {
    vi.useFakeTimers()
    const f = fixture()
    try {
      const input = new Request('https://example.test/maintenance', {
        method: 'POST',
        duplex: 'half',
        headers: { 'content-type': 'application/json', 'x-performe-maintenance-token': token },
        body: new ReadableStream({
          start(c) {
            c.enqueue(new TextEncoder().encode(JSON.stringify({ dispatch_id: dispatch })))
          },
        }),
      } as RequestInit)
      const pending = f.handle(input)
      await vi.advanceTimersByTimeAsync(5001)
      expect((await pending).status).toBe(400)
      expect(f.calls).toEqual([])
    } finally {
      vi.useRealTimers()
    }
  })
  it('bounds a chunked body before creating a privileged client', async () => {
    const f = fixture()
    const input = new Request('https://example.test/maintenance', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-performe-maintenance-token': token },
      body: JSON.stringify({ dispatch_id: dispatch }) + ' '.repeat(300),
    })
    expect((await f.handle(input)).status).toBe(400)
    expect(f.calls).toEqual([])
  })
  it.each(['false', undefined])('does no privileged IO while disabled (%s)', async (flag) => {
    const create = vi.fn(() => {
      throw Error('must not construct privileged client')
    })
    const handle = createConversationMediaMaintenanceHandler({
      env: { ...env, MOBILE_CONVERSATION_MAINTENANCE_BRIDGE_ENABLED: flag },
      createClient: create,
    })
    expect((await handle(request())).status).toBe(503)
    expect(create).not.toHaveBeenCalled()
  })
  it('refuses another project before client construction', async () => {
    const create = vi.fn(() => {
      throw Error('must not construct privileged client')
    })
    const handle = createConversationMediaMaintenanceHandler({
      env: { ...env, SUPABASE_URL: 'https://other.supabase.co' },
      createClient: create,
    })
    expect((await handle(request())).status).toBe(503)
    expect(create).not.toHaveBeenCalled()
  })
  it.each([
    [{ dispatch_id: dispatch, user_id: lease }, token],
    [{ dispatch_id: 'invalid' }, token],
    [{ dispatch_id: dispatch }, 'bad-token'],
  ])('refuses an unbound or malformed command without IO', async (body, header) => {
    const f = fixture()
    expect((await f.handle(request(body, header))).status).toBe(400)
    expect(f.calls).toEqual([])
  })
  it.each([
    [
      'private',
      'claim_conversation_media_disposal_batch_v2',
      { swept: 0, hasMore: false, issuanceReconciled: false },
    ],
    ['ordinary', 'claim_conversation_media_expiry_batch', { swept: 0, issuanceReconciled: false }],
    [
      'recurring',
      'claim_mobile_reevaluation_photo_cleanup_scopes',
      {
        attempted: 0,
        live: 0,
        waiting: 0,
        settled: 0,
        incomplete: 0,
        newlyDeleted: 0,
        hasMore: false,
        stopped: 'batch_end',
      },
    ],
    ['accounts', 'list_mobile_deleted_users_for_photo_purge', { purged: 0, mediaRemoved: 0 }],
  ])('executes only the authorized %s lane using the actual SDK', async (lane, rpc, summary) => {
    const f = fixture(lane)
    const response = await f.handle(request())
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ status: 'completed', lane, summary })
    expect(f.calls.map((x) => x.path)).toEqual([
      'claim_conversation_media_maintenance',
      rpc,
      'complete_conversation_media_maintenance',
    ])
    const auth = f.calls[0]?.body
    expect(auth?.p_dispatch_id).toBe(dispatch)
    expect(auth?.p_token_sha256).toMatch(/^[0-9a-f]{64}$/)
    expect(JSON.stringify(f.calls)).not.toContain(token)
    expect(f.calls.at(-1)?.body).toEqual({
      p_dispatch_id: dispatch,
      p_lease_id: lease,
      p_outcome: 'completed',
    })
  })
  it('does not act on a denied/replayed token', async () => {
    const f = fixture()
    f.setMode('denied')
    expect((await f.handle(request())).status).toBe(401)
    expect(f.calls.map((x) => x.path)).toEqual(['claim_conversation_media_maintenance'])
  })
  it.each([
    'late',
    'flag-off',
    'bad-lease',
  ])('rejects %s authorization before any cleanup', async (mode) => {
    const f = fixture()
    f.setMode(mode)
    try {
      expect((await f.handle(request())).status).toBe(503)
      expect(f.calls.map((x) => x.path)).toEqual(['claim_conversation_media_maintenance'])
    } finally {
      f.restore()
    }
  })
  it('preserves failure for retry and never returns raw errors', async () => {
    const f = fixture()
    f.setMode('fail')
    const response = await f.handle(request())
    expect(response.status).toBe(503)
    expect(await response.text()).toBe('{"status":"unavailable"}')
    expect(f.calls.at(-1)?.body.p_outcome).toBe('retry')
  })
  it('does not claim success when the completion lease was lost', async () => {
    const f = fixture()
    f.setMode('lost-lease')
    expect((await f.handle(request())).status).toBe(503)
  })
})
