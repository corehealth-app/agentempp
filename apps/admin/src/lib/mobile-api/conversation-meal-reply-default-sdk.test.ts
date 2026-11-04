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
function sdkFixture(key: 'prepared' | 'saved' = 'prepared') {
  const f = replyFixture(key),
    saved = replyFixture('saved')
  let current: unknown = f.state
  const calls: { path: string; method: string }[] = []
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
    let data: unknown
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
  return { f, saved, db, calls, routes, request, outside }
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
    expect(s.outside).not.toHaveBeenCalled()
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
