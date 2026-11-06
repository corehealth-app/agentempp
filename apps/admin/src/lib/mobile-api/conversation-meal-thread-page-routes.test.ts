import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { journalAuth } from './__fixtures__/conversation-journal'
import { writerEpoch, writerOwner } from './__fixtures__/conversation-meal-writer'
import { createConversationMealJournalRoutes } from './conversation-meal-journal-routes'
import type { MobileRouteRuntime } from './route'

function setup() {
  const oldRead = vi.fn().mockResolvedValue({ schema: 'conversation.journal-page.v1' }),
    read = vi.fn().mockResolvedValue({ schema: 'conversation.journal-page.v2' }),
    service = vi.fn(() => ({ read: oldRead })),
    version2Service = vi.fn(() => ({ read }))
  const runtime: MobileRouteRuntime = {
    createServiceClient: () => ({}) as ServiceClient,
    authenticate: vi.fn(async () => journalAuth()),
    authorizeEntitlement: vi.fn(async () => {}),
    createRequestId: () => 'thread-route',
  }
  return {
    oldRead,
    read,
    service,
    version2Service,
    runtime,
    routes: createConversationMealJournalRoutes(
      { enabled: () => true, service, version2Service },
      runtime,
    ),
  }
}
function request(q: string) {
  return new Request(`https://app.invalid/api/mobile/v1/conversation/journal${q}`, {
    headers: { 'X-Conversation-Owner': writerOwner, 'X-Conversation-Epoch': writerEpoch },
  })
}
describe('existing GET explicit version dispatch', () => {
  it('dispatches actual v2 only when explicitly requested and preserves real auth/no-store', async () => {
    const f = setup()
    const r = await f.routes.GET(request('?version=2&limit=3'))
    expect(r.status).toBe(200)
    expect(f.read).toHaveBeenCalledWith(journalAuth(), {
      epoch: writerEpoch,
      limit: 3,
      cursor: null,
    })
    expect(f.service).not.toHaveBeenCalled()
    expect(f.runtime.authenticate).toHaveBeenCalledTimes(2)
    expect(r.headers.get('cache-control')).toBe('no-store')
    expect((await r.json()).data.schema).toBe('conversation.journal-page.v2')
  })
  it.each(['', '?version=1'])('preserves exact v1 dispatch %s', async (q) => {
    const f = setup()
    expect((await f.routes.GET(request(q))).status).toBe(200)
    expect(f.oldRead).toHaveBeenCalledTimes(1)
    expect(f.version2Service).not.toHaveBeenCalled()
  })
  it.each([
    '?version=',
    '?version=0',
    '?version=4',
    '?version=02',
    '?version=2&version=2',
    '?version=2&unknown=x',
    '?version=2&limit=1&limit=1',
    '?version=2&cursor=',
  ])('refuses malformed selector/query %s before factories', async (q) => {
    const f = setup()
    expect((await f.routes.GET(request(q))).status).toBe(422)
    expect(f.service).not.toHaveBeenCalled()
    expect(f.version2Service).not.toHaveBeenCalled()
  })
})
