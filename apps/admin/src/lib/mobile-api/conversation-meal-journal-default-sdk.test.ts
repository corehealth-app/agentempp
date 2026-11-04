/** Real default Auth + SDK composition under a controlled synthetic HTTP seam.
 * No GoTrue/PG/provider/network is contacted. */
import type { Database, ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { journalAuth, journalClinical } from './__fixtures__/conversation-journal'
import { threadPage } from './__fixtures__/conversation-thread-page'

const cell = vi.hoisted(() => ({ db: null as ServiceClient | null }))
vi.mock('../supabase/server', () => ({
  createServiceClient: () => {
    if (!cell.db) throw new Error('No synthetic SDK')
    return cell.db
  },
  createPatientBearerClient: () => {
    if (!cell.db) throw new Error('No synthetic SDK')
    return cell.db
  },
}))

import { createConversationMealJournalRoutes } from './conversation-meal-journal-routes'

afterEach(() => {
  cell.db = null
  vi.unstubAllGlobals()
})
function setup(
  options: { empty?: boolean; remapDuringRead?: boolean; mutateRequestDuringRead?: boolean } = {},
) {
  const auth = journalAuth(),
    page = options.empty
      ? { ...threadPage(), threads: [], items: [], has_more: false, next_cursor: null }
      : threadPage(),
    calls: string[] = [],
    outside = vi.fn(async () => {
      throw new Error('External network is forbidden')
    })
  vi.stubGlobal('fetch', outside)
  let profiles = 0,
    remapped = false,
    originalRequest: Request | null = null
  const authHeaders: (string | null)[] = []
  const fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(
      typeof input === 'string' ? input : input instanceof URL ? input.href : input.url,
    )
    calls.push(url.pathname)
    let data: unknown
    if (url.pathname === '/auth/v1/user') {
      authHeaders.push(new Headers(init?.headers).get('Authorization'))
      data = {
        id: auth.authUserId,
        email: 'synthetic@example.invalid',
        email_confirmed_at: '2026-01-01T00:00:00Z',
        role: 'authenticated',
        aud: 'authenticated',
        app_metadata: {},
        user_metadata: {},
        created_at: '2026-01-01T00:00:00Z',
      }
    } else if (url.pathname === '/rest/v1/admin_users') data = []
    else if (url.pathname === '/rest/v1/users')
      data = [
        {
          id: remapped ? '10000000-0000-4000-8000-000000000099' : auth.userId,
          auth_user_id: auth.authUserId,
          email: null,
          name: null,
          locale: 'pt-BR',
          timezone: 'UTC',
          country: 'BR',
          country_confirmed: true,
          status: 'active',
        },
      ]
    else if (url.pathname.endsWith('/bootstrap_patient_profile')) data = auth.userId
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
    else if (url.pathname.endsWith('/get_mobile_current_clinical_state'))
      data = profiles++ === 0 ? journalClinical('2026-11-04T12:02:00.000001Z') : journalClinical()
    else if (url.pathname.endsWith('/read_conversation_meal_journal_page_v2')) {
      data = page
      if (options.remapDuringRead) remapped = true
      if (options.mutateRequestDuringRead)
        originalRequest?.headers.set('Authorization', 'Bearer changed-by-late-callback')
    } else throw new Error('Unexpected request or write')
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  })
  cell.db = createClient<Database>('https://synthetic.supabase.invalid', 'synthetic-service-key', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch },
  })
  const legacy = { schema: 'conversation.journal-page.v1' },
    read = vi.fn().mockResolvedValue(legacy),
    routes = createConversationMealJournalRoutes({ enabled: () => true, service: () => ({ read }) })
  const request = (query: string) =>
    (originalRequest = new Request(
      `https://app.invalid/api/mobile/v1/conversation/journal${query}`,
      {
        headers: {
          Authorization: `Bearer ${auth.accessToken}`,
          'X-Conversation-Owner': auth.userId,
          'X-Conversation-Epoch': page.epoch,
        },
      },
    ))
  return { calls, routes, request, outside, read, legacy, auth, authHeaders }
}
describe('actual default journal version Auth dispatch', () => {
  it('revalidates the same immutable original bearer after a late callback mutates the incoming request', async () => {
    const f = setup({ mutateRequestDuringRead: true }),
      response = await f.routes.GET(f.request('?version=2'))
    expect(response.status).toBe(200)
    expect(f.authHeaders).toEqual([`Bearer ${f.auth.accessToken}`, `Bearer ${f.auth.accessToken}`])
    expect(f.outside).not.toHaveBeenCalled()
  })

  it.each([
    '?version=2',
    '?version=2&version=2',
    '?version=1&version=2',
  ])('never bootstraps for v2 or a malformed v2 selector %s', async (query) => {
    const f = setup(),
      r = await f.routes.GET(f.request(query))
    expect(r.status).toBe(query === '?version=2' ? 200 : 422)
    expect(f.calls.some((p) => p.endsWith('/bootstrap_patient_profile'))).toBe(false)
    expect(f.calls.some((p) => p === '/auth/v1/user')).toBe(true)
    expect(
      f.calls.filter((p) => p.endsWith('/read_conversation_meal_journal_page_v2')),
    ).toHaveLength(query === '?version=2' ? 1 : 0)
    expect(f.read).not.toHaveBeenCalled()
    expect(r.headers.get('cache-control')).toBe('no-store')
    expect(f.outside).not.toHaveBeenCalled()
  })
  it.each([
    false,
    true,
  ])('denies v2 publication after an actual patient remap during an empty=%s read', async (empty) => {
    const f = setup({ empty, remapDuringRead: true }),
      response = await f.routes.GET(f.request('?version=2'))
    expect(response.status).toBe(409)
    const json = await response.json()
    expect(json).not.toHaveProperty('data')
    expect(f.calls.some((p) => p.endsWith('/bootstrap_patient_profile'))).toBe(false)
    expect(
      f.calls.filter((p) => p.endsWith('/read_conversation_meal_journal_page_v2')),
    ).toHaveLength(1)
    expect(f.outside).not.toHaveBeenCalled()
  })
  it.each([
    '',
    '?version=1',
  ])('preserves legacy default Auth/bootstrap and payload %s', async (query) => {
    const f = setup(),
      r = await f.routes.GET(f.request(query))
    expect(r.status).toBe(200)
    expect((await r.json()).data).toEqual(f.legacy)
    expect(f.calls.filter((p) => p.endsWith('/bootstrap_patient_profile'))).toHaveLength(1)
    expect(f.calls.some((p) => p.endsWith('/read_conversation_meal_journal_page_v2'))).toBe(false)
    expect(f.read).toHaveBeenCalledTimes(1)
    expect(f.outside).not.toHaveBeenCalled()
  })
})
