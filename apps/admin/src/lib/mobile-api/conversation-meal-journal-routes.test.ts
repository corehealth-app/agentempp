import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { journalAuth, journalClinical } from './__fixtures__/conversation-journal'
import { writerEpoch, writerOwner } from './__fixtures__/conversation-meal-writer'
import { createConversationMealJournalRoutes } from './conversation-meal-journal-routes'
import type { MobileRouteRuntime } from './route'

function setup() {
  const read = vi.fn().mockResolvedValue({
      schema: 'conversation.journal-page.v1',
      auth_user_id: journalAuth().authUserId,
      owner_id: writerOwner,
      epoch: writerEpoch,
      observed_at: journalClinical().observed_at,
      items: [],
      has_more: false,
      next_cursor: null,
    }),
    service = vi.fn(() => ({ read })),
    enabled = vi.fn(() => true),
    runtime: MobileRouteRuntime = {
      createServiceClient: () => ({}) as ServiceClient,
      authenticate: vi.fn(async () => journalAuth()),
      authorizeEntitlement: vi.fn(async () => {}),
      createRequestId: () => 'journal-route-test',
    }
  return {
    read,
    service,
    enabled,
    runtime,
    routes: createConversationMealJournalRoutes({ enabled, service }, runtime),
  }
}
function request(query = '', headers: Record<string, string> = {}) {
  return new Request(`https://app.invalid/api/mobile/v1/conversation/journal${query}`, {
    headers: {
      'X-Conversation-Owner': writerOwner,
      'X-Conversation-Epoch': writerEpoch,
      ...headers,
    },
  })
}
describe('read-only authenticated conversation journal GET', () => {
  it('negotiates presentation2 only on actual journal2 and keeps legacy journal literal', async () => {
    const f = setup(),
      read2 = vi.fn().mockResolvedValue({ schema: 'conversation.journal-page.v2' }),
      routes = createConversationMealJournalRoutes(
        { enabled: () => true, service: f.service, version2Service: () => ({ read: read2 }) },
        f.runtime,
      )
    const r = await routes.GET(
      request('?version=2', { 'X-Conversation-Feedback-Presentation': '2' }),
    )
    expect(r.headers.get('X-Conversation-Feedback-Presentation')).toBe('2')
    expect(r.headers.get('Vary')).toBe('Authorization, X-Conversation-Feedback-Presentation')
    expect(read2).toHaveBeenCalledWith(
      journalAuth(),
      { epoch: writerEpoch, limit: 10, cursor: null },
      '2',
    )
    const old = await routes.GET(request('', { 'X-Conversation-Feedback-Presentation': '2' }))
    expect(old.headers.get('X-Conversation-Feedback-Presentation')).toBeNull()
    expect(f.read).toHaveBeenCalledWith(journalAuth(), {
      epoch: writerEpoch,
      limit: 10,
      cursor: null,
    })
  })
  it('selects journal3 additively with readonly Auth and a final original identity check', async () => {
    const f = setup(),
      read3 = vi.fn().mockResolvedValue({
        schema: 'conversation.journal-page.v3',
        mode: 'historical',
        items: [],
      }),
      routes = createConversationMealJournalRoutes(
        { enabled: () => true, service: f.service, version3Service: () => ({ read: read3 }) },
        f.runtime,
      ),
      response = await routes.GET(request('?version=3&limit=2&cursor=opaque'))
    expect(response.status).toBe(200)
    expect(read3).toHaveBeenCalledWith(journalAuth(), {
      epoch: writerEpoch,
      limit: 2,
      cursor: 'opaque',
    })
    expect(f.read).not.toHaveBeenCalled()
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(2)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect((await response.json()).data.schema).toBe('conversation.journal-page.v3')
  })
  it('uses actual Auth/entitlement, owner/epoch preconditions and the standard no-store envelope', async () => {
    const f = setup(),
      response = await f.routes.GET(request('?limit=2&cursor=opaque'))
    expect(response.status).toBe(200)
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(1)
    expect(f.runtime.authorizeEntitlement).toHaveBeenCalledTimes(1)
    expect(f.read).toHaveBeenCalledWith(journalAuth(), {
      epoch: writerEpoch,
      limit: 2,
      cursor: 'opaque',
    })
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('vary')).toBe('Authorization')
    expect((await response.json()).meta).toEqual({
      api_version: 'v1',
      request_id: 'journal-route-test',
    })
    expect(Object.keys(f.routes)).toEqual(['GET'])
  })
  it('defaults to ten without cursor or any command hash requirement', async () => {
    const f = setup()
    expect((await f.routes.GET(request())).status).toBe(200)
    expect(f.read).toHaveBeenCalledWith(journalAuth(), {
      epoch: writerEpoch,
      limit: 10,
      cursor: null,
    })
  })
  it.each([
    '?limit=0',
    '?limit=26',
    '?limit=1.5',
    '?limit=01',
    '?limit=',
    '?limit=1&limit=2',
    '?cursor=a&cursor=b',
    '?cursor=',
    '?unknown=a',
  ])('rejects closed query %s before service composition', async (query) => {
    const f = setup()
    expect((await f.routes.GET(request(query))).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('rejects an old patient header before any journal or clinical service', async () => {
    const f = setup()
    expect(
      (await f.routes.GET(request('', { 'X-Conversation-Owner': journalAuth().authUserId })))
        .status,
    ).toBe(409)
    expect(f.service).not.toHaveBeenCalled()
  })
  it.each([
    'X-Conversation-Owner',
    'X-Conversation-Epoch',
  ])('requires actual %s precondition', async (key) => {
    const f = setup()
    expect((await f.routes.GET(request('', { [key]: '' }))).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
  })
  it('keeps capability disabled without falling back to old messages', async () => {
    const f = setup()
    f.enabled.mockReturnValue(false)
    expect((await f.routes.GET(request())).status).toBe(503)
    expect(f.service).not.toHaveBeenCalled()
  })
})
