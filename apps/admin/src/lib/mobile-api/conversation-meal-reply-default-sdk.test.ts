/** Actual SDK/default composition; every HTTP response is controlled. No
 * GoTrue/PG/provider/network is contacted, and no fluent SDK fake is used. */

import type { Database } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import {
  createConversationMealReplyPublicRoutes,
  createConversationMealReplyReadonlyRuntime,
} from './conversation-meal-reply-public-routes'

afterEach(() => vi.unstubAllGlobals())
type ScopeFault = 'token' | 'admin' | 'owner' | 'epoch'
function sdkFixture(
  key: 'prepared' | 'saved' = 'prepared',
  failure?: {
    after: 'read_conversation_meal_continuation' | 'commit_conversation_meal_continuation'
    kind: ScopeFault
  },
) {
  const f = replyFixture(key),
    saved = replyFixture('saved')
  let current: unknown = f.state,
    fault: ScopeFault | undefined
  let boundaryReached = false,
    failedOnce = false
  const calls: { path: string; method: string }[] = []
  const continuationReads: unknown[] = []
  const outside = vi.fn(async () => {
    throw new Error('Real network is forbidden')
  })
  vi.stubGlobal('fetch', outside)
  const fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(
        typeof input === 'string' ? input : input instanceof URL ? input.href : input.url,
      ),
      method = init?.method ?? 'GET'
    calls.push({ path: url.pathname, method })
    if (url.pathname.endsWith('/read_conversation_meal_continuation'))
      continuationReads.push(JSON.parse(String(init?.body)))
    let data: unknown
    // One transient denial is enough to close this request permanently. Later
    // fixture responses recover, so an accidental guard retry cannot look safe.
    const deny = fault && !failedOnce ? fault : undefined
    if (
      deny &&
      ((deny === 'token' && url.pathname === '/auth/v1/user') ||
        (deny === 'admin' && url.pathname === '/rest/v1/admin_users') ||
        (deny === 'owner' && url.pathname === '/rest/v1/users') ||
        (deny === 'epoch' && url.pathname.endsWith('/get_mobile_current_clinical_state')))
    ) {
      failedOnce = true
      if (deny === 'token')
        return new Response(JSON.stringify({ message: 'synthetic revoked token' }), { status: 401 })
      if (deny === 'admin') return new Response(JSON.stringify([{ id: f.auth.authUserId }]))
      if (deny === 'owner')
        return new Response(
          JSON.stringify([
            {
              id: 'c3cc0000-0000-4000-8000-000000000099',
              auth_user_id: f.auth.authUserId,
              email: null,
              name: null,
              locale: 'pt-BR',
              timezone: 'UTC',
              country: 'BR',
              country_confirmed: true,
              status: 'active',
            },
          ]),
        )
      return new Response(
        JSON.stringify({ ...saved.profile, epoch: 'c3cc0000-0000-4000-8000-000000000099' }),
      )
    }
    if (failure && !boundaryReached && url.pathname.endsWith(`/${failure.after}`)) {
      boundaryReached = true
      fault = failure.kind
    }
    if (url.pathname === '/auth/v1/user')
      data = {
        id: f.auth.authUserId,
        email: f.auth.identity.email,
        email_confirmed_at: f.auth.identity.emailConfirmedAt,
        role: 'authenticated',
        aud: 'authenticated',
        app_metadata: {},
        user_metadata: {},
        created_at: '2026-01-01T00:00:00Z',
      }
    else if (url.pathname === '/rest/v1/admin_users') data = []
    else if (url.pathname === '/rest/v1/users')
      data = [
        {
          id: f.auth.userId,
          auth_user_id: f.auth.authUserId,
          email: null,
          name: null,
          locale: 'pt-BR',
          timezone: 'UTC',
          country: 'BR',
          country_confirmed: true,
          status: 'active',
        },
      ]
    else if (url.pathname.endsWith('/resolve_user_entitlement'))
      data = {
        entitlement: 'bodyflow_full',
        has_active_access: true,
        status: 'active',
        source: 'revenuecat',
        plan: 'mensal',
        access_expires_at: '2099-01-01T00:00:00Z',
        grace_expires_at: null,
        cancel_at_period_end: false,
        reason: 'valid_entitlement',
        decision_at: '2026-11-04T00:00:00Z',
      }
    else if (url.pathname.endsWith('/get_mobile_current_clinical_state')) data = saved.profile
    else if (url.pathname.endsWith('/read_conversation_meal_continuation')) data = current
    else if (url.pathname.endsWith('/read_conversation_meal_feedback_v2'))
      data = { action: 'absent' }
    else if (url.pathname.endsWith('/read_conversation_meal_feedback_source'))
      data = {
        action: 'unavailable',
        reason: 'original_context_unavailable',
        receipt: saved.state.reply?.receipt,
      }
    else if (url.pathname.endsWith('/commit_conversation_meal_continuation')) {
      current = saved.state
      return new Response(
        JSON.stringify({ message: 'synthetic lost response', code: 'SYNTHETIC' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      )
    } else throw new Error('Unexpected external request or factual writer')
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  })
  const db = createClient<Database>('https://synthetic.supabase.invalid', 'synthetic-service-key', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch },
  })
  const defaults = createConversationMealReplyReadonlyRuntime(),
    routes = createConversationMealReplyPublicRoutes(
      { enabled: () => true },
      { ...defaults, createServiceClient: () => db, createRequestId: () => 'synthetic-sdk-reply' },
    )
  const request = (method: 'POST' | 'GET') =>
    new Request(
      `https://app.invalid/api/mobile/v1/conversation/commands/${f.identity.parentCommandId}/replies${method === 'GET' ? `/${f.identity.replyId}?parent_input_hash=${f.identity.parentInputHash}&reply_input_hash=${f.identity.replyInputHash}` : ''}`,
      {
        method,
        headers: {
          Authorization: `Bearer ${f.auth.accessToken}`,
          'Content-Type': 'application/json',
          'X-Conversation-Owner': f.identity.ownerId,
          'X-Conversation-Epoch': f.identity.epoch,
          'Idempotency-Key': f.key,
        },
        ...(method === 'POST' ? { body: JSON.stringify(f.submission) } : {}),
      },
    )
  return { f, saved, db, calls, continuationReads, routes, request, outside }
}
describe('default public reply actual SDK composition', () => {
  it('uses real readonly Auth/entitlement/epoch and actual K processing to recover one uncertain prepared commit', async () => {
    const s = sdkFixture()
    expect(s.calls).toEqual([])
    const response = await s.routes.POST(s.request('POST'), {
      params: Promise.resolve({ commandId: s.f.identity.parentCommandId }),
    })
    expect(response.status).toBe(200)
    const body = await response.json()
    expect(body.data).toMatchObject({
      status: 'saved',
      auth_user_id: s.f.auth.authUserId,
      owner_id: s.f.identity.ownerId,
      receipt: { schema: 'conversation.meal-continuation-effect.v1' },
      feedback: null,
    })
    expect(
      s.calls.filter((c) => c.path.endsWith('/commit_conversation_meal_continuation')),
    ).toHaveLength(1)
    expect(
      s.calls.filter((c) => c.path.endsWith('/read_conversation_meal_continuation')),
    ).toHaveLength(3)
    expect(
      s.calls.some((c) =>
        /bootstrap|admit_|prepare_|register_|search_food|interpret|capture_conversation|commit_conversation_meal_feedback/u.test(
          c.path,
        ),
      ),
    ).toBe(false)
    expect(
      s.calls.filter((c) => c.path.endsWith('/read_conversation_meal_feedback_v2')),
    ).toHaveLength(2)
    expect(
      s.calls.filter((c) => c.path.endsWith('/read_conversation_meal_feedback_source')),
    ).toHaveLength(1)
    for (const identity of s.continuationReads)
      expect(identity).toEqual({
        p_user_id: s.f.identity.ownerId,
        p_parent_command_id: s.f.identity.parentCommandId,
        p_parent_input_hash: s.f.identity.parentInputHash,
        p_expected_epoch: s.f.identity.epoch,
        p_reply_id: s.f.identity.replyId,
        p_reply_input_hash: s.f.identity.replyInputHash,
      })
    expect(s.outside).not.toHaveBeenCalled()
    // Physical writer operations keep both guards and independent durable reads;
    // an additional outer guard would exceed this bounded default SDK budget.
    expect(s.calls.length).toBeLessThanOrEqual(159)
  })
  it('replays a saved default reply within its SDK budget without another factual write', async () => {
    const s = sdkFixture('saved')
    const response = await s.routes.POST(s.request('POST'), {
      params: Promise.resolve({ commandId: s.f.identity.parentCommandId }),
    })
    expect(response.status).toBe(200)
    expect((await response.json()).data).toMatchObject({
      status: 'saved',
      receipt: s.saved.state.reply?.receipt,
    })
    expect(s.continuationReads).toHaveLength(2)
    expect(s.calls.some((c) => /admit_|prepare_|commit_/u.test(c.path))).toBe(false)
    expect(s.calls.length).toBeLessThanOrEqual(129)
    expect(s.outside).not.toHaveBeenCalled()
  })
  it.each([
    'token',
    'admin',
    'owner',
    'epoch',
  ] as const)('closes default SDK publication after transient %s loss between physical RPCs', async (kind) => {
    for (const after of [
      'read_conversation_meal_continuation',
      'commit_conversation_meal_continuation',
    ] as const) {
      const s = sdkFixture('prepared', { after, kind })
      const response = await s.routes.POST(s.request('POST'), {
        params: Promise.resolve({ commandId: s.f.identity.parentCommandId }),
      })
      expect(response.status).toBeGreaterThanOrEqual(400)
      const body = await response.json()
      expect(body).not.toHaveProperty('data.receipt')
      const boundary = s.calls.findIndex((c) => c.path.endsWith(`/${after}`))
      expect(boundary).toBeGreaterThanOrEqual(0)
      expect(
        s.calls
          .slice(boundary + 1)
          .some(
            (c) =>
              c.path.startsWith('/rest/v1/rpc/') &&
              !c.path.endsWith('/get_mobile_current_clinical_state'),
          ),
      ).toBe(false)
      expect(
        s.calls.filter((c) => c.path.endsWith('/commit_conversation_meal_continuation')),
      ).toHaveLength(after === 'commit_conversation_meal_continuation' ? 1 : 0)
      expect(s.outside).not.toHaveBeenCalled()
    }
  })
  it.each([
    'prepared',
    'saved',
  ] as const)('GET default %s never initializes, processes, seals or commits', async (key) => {
    const s = sdkFixture(key),
      response = await s.routes.GET(s.request('GET'), {
        params: Promise.resolve({
          commandId: s.f.identity.parentCommandId,
          replyId: s.f.identity.replyId,
        }),
      })
    expect(response.status).toBe(200)
    const body = await response.json()
    expect(body.data.status).toBe(key === 'saved' ? 'saved' : 'held')
    expect(
      s.calls.filter((c) => c.path.endsWith('/read_conversation_meal_continuation')),
    ).toHaveLength(1)
    expect(
      s.calls.some((c) =>
        /bootstrap|admit_|prepare_|commit_|register_|feedback_source|search_food|interpret|capture_conversation/u.test(
          c.path,
        ),
      ),
    ).toBe(false)
    expect(
      s.calls.filter((c) => c.path.endsWith('/read_conversation_meal_feedback_v2')),
    ).toHaveLength(key === 'saved' ? 1 : 0)
    expect(s.outside).not.toHaveBeenCalled()
  })
})
