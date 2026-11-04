/** Actual default Auth/SDK/service composition over controlled synthetic HTTP;
 * no external network, GoTrue or PostgreSQL is contacted by these tests. */
import type { Database, ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import {
  editAuthId,
  editBinding,
  editInput,
  editOperationId,
  editReadState,
} from './__fixtures__/conversation-meal-edit'

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

import { createConversationMealEditPublicRoutes } from './conversation-meal-edit-public-routes'

afterEach(() => {
  cell.db = null
  vi.unstubAllGlobals()
})
function setup(
  remap = false,
  options: { requestedEpoch?: string; requestedHash?: string; state?: () => unknown } = {},
) {
  const b = editBinding(),
    calls: string[] = [],
    bearers: string[] = []
  const outside = vi.fn(async () => {
    throw new Error('External network is forbidden')
  })
  vi.stubGlobal('fetch', outside)
  let mapped = b.ownerId
  const fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input))
    calls.push(url.pathname)
    let data: unknown
    if (url.pathname === '/auth/v1/user') {
      bearers.push(
        new Headers(input instanceof Request ? input.headers : init?.headers).get(
          'authorization',
        ) ?? '',
      )
      data = {
        id: editAuthId,
        email: 'qa@synthetic.invalid',
        email_confirmed_at: '2026-11-01T00:00:00Z',
      }
    } else if (url.pathname === '/rest/v1/admin_users') data = []
    else if (url.pathname === '/rest/v1/users')
      data = [
        {
          id: mapped,
          auth_user_id: editAuthId,
          email: null,
          name: null,
          locale: 'pt-BR',
          timezone: 'UTC',
          country: 'BR',
          country_confirmed: true,
          status: 'active',
        },
      ]
    else if (url.pathname.endsWith('/bootstrap_patient_profile')) data = b.ownerId
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
    else if (url.pathname.endsWith('/read_conversation_meal_edit_operation'))
      data = { action: 'absent' }
    else if (url.pathname.endsWith('/read_conversation_meal_edit_state')) {
      data = options.state ? options.state() : editReadState()
      if (remap) mapped = '10000000-0000-4000-8000-000000000099'
    } else throw new Error(`Unexpected request ${url.pathname}`)
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  })
  cell.db = createClient<Database>('https://synthetic.supabase.invalid', 'synthetic-service-key', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch },
  })
  const routes = createConversationMealEditPublicRoutes({ enabled: () => true })
  const request = (method: string) =>
    new Request(
      `https://app.invalid/api/mobile/v1/conversation/meal-commands/${b.commandId}/${method === 'GET' ? 'meal' : `edits/${editOperationId}/reconcile`}`,
      {
        method,
        headers: {
          Authorization: `Bearer ${candidateAuth.accessToken}`,
          'Content-Type': 'application/json',
          'X-Conversation-Owner': b.ownerId,
          'X-Conversation-Epoch': options.requestedEpoch ?? b.epoch,
          'X-Conversation-Input-Hash': options.requestedHash ?? b.inputHash,
          'Idempotency-Key': `cmedit1:${editOperationId}`,
        },
        ...(method === 'GET' ? {} : { body: JSON.stringify(editInput()) }),
      },
    )
  const params = {
    params: Promise.resolve({ commandId: b.commandId, operationId: editOperationId }),
  }
  return {
    calls,
    bearers,
    outside,
    run: (method: 'GROUP' | 'RECONCILE') =>
      routes[method](request(method === 'GROUP' ? 'GET' : 'POST'), params),
  }
}
describe('actual default edit read Auth composition', () => {
  it.each([
    ['GROUP', 'epoch', 'stale_epoch'],
    ['GROUP', 'hash', 'event_conflict'],
    ['GROUP', 'both', 'stale_epoch'],
    ['RECONCILE', 'epoch', 'stale_epoch'],
    ['RECONCILE', 'hash', 'event_conflict'],
    ['RECONCILE', 'both', 'stale_epoch'],
  ] as const)('%s returns409 for a qualified private state with requested %s mismatch', async (method, mismatch, action) => {
    const f = setup(false, {
        ...(mismatch !== 'hash' ? { requestedEpoch: editOperationId } : {}),
        ...(mismatch !== 'epoch' ? { requestedHash: 'f'.repeat(64) } : {}),
      }),
      response = await f.run(method)
    expect(response.status).toBe(409)
    expect(await response.json()).toMatchObject({
      error: { code: `conversation_meal_edit_${action}` },
    })
    expect(
      f.calls.filter((path) => path.endsWith('/read_conversation_meal_edit_state')),
    ).toHaveLength(1)
    expect(f.calls.some((path) => /\/(bootstrap_|commit_|undo_)/u.test(path))).toBe(false)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(f.outside).not.toHaveBeenCalled()
  })
  it.each([
    'owner',
    'command',
    'current',
    'extra',
  ] as const)('keeps malformed actual %s state503 despite a mismatched request', async (corruption) => {
    const f = setup(false, {
        requestedEpoch: editOperationId,
        requestedHash: 'f'.repeat(64),
        state: () => {
          const raw = editReadState()
          if (corruption === 'owner') raw.command.owner_id = editOperationId
          if (corruption === 'command') raw.command.command_id = editOperationId
          if (corruption === 'current') raw.current_state.items[0].user_id = editOperationId
          if (corruption === 'extra') Object.assign(raw, { private_extra: 'private-source' })
          return raw
        },
      }),
      response = await f.run('GROUP'),
      packet = await response.json()
    expect(response.status).toBe(503)
    expect(packet).toMatchObject({ error: { code: 'conversation_meal_edit_unavailable' } })
    expect(packet).not.toHaveProperty('data')
    expect(JSON.stringify(packet)).not.toContain('private-source')
    expect(f.calls.some((path) => /\/(bootstrap_|commit_|undo_)/u.test(path))).toBe(false)
    expect(f.outside).not.toHaveBeenCalled()
  })
  it.each([
    'GROUP',
    'RECONCILE',
  ] as const)('%s reads an existing account without bootstrap or a domain writer', async (method) => {
    const f = setup(),
      response = await f.run(method)
    expect(response.status).toBe(200)
    expect(f.calls.some((path) => path.endsWith('/bootstrap_patient_profile'))).toBe(false)
    expect(f.calls.some((path) => /\/(commit_|undo_)/u.test(path))).toBe(false)
    expect(f.bearers).toEqual([
      `Bearer ${candidateAuth.accessToken}`,
      `Bearer ${candidateAuth.accessToken}`,
    ])
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(f.outside).not.toHaveBeenCalled()
  })
  it.each([
    'GROUP',
    'RECONCILE',
  ] as const)('%s withholds facts after a patient remap during the actual state read', async (method) => {
    const f = setup(true),
      response = await f.run(method)
    expect(response.status).toBe(409)
    expect(await response.json()).not.toHaveProperty('data')
    expect(f.calls.some((path) => /\/(commit_|undo_)/u.test(path))).toBe(false)
    expect(f.outside).not.toHaveBeenCalled()
  })
})
